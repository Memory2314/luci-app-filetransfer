local fs = require "nixio.fs"
local http = luci.http
local sys = require "luci.sys"

-- 设置文件上传目录
local dir = "/tmp/upload/"
fs.mkdir(dir)

-- CSRF Token 文件路径
local csrf_token_file = "/tmp/csrf_token.txt"

-- 日志文件路径
local log_file = "/tmp/upload/operation_log.txt"
if not fs.access(log_file) then
    fs.writefile(log_file, "") -- 初始化日志文件
end

-- 日志记录函数
local function write_log(message)
    local log_entry = os.date("[%Y-%m-%d %H:%M:%S] ") .. message .. "\n"
    local f = io.open(log_file, "a")
    if f then
        f:write(log_entry)
        f:close()
    end
end

-- 生成或获取 CSRF Token
local function get_or_set_csrf_token()
    if not fs.access(csrf_token_file) then
        local token = luci.dispatcher.context.token --tostring(os.time()) .. tostring(math.random(100000, 999999))
        fs.writefile(csrf_token_file, token)
        return token
    end
    return fs.readfile(csrf_token_file):gsub("\n", "")
end

-- 验证 CSRF Token
local function validate_csrf_token(token)
    if not token or #token == 0 then
        write_log("CSRF token missing or empty.")
        return false
    end
    local server_token = get_or_set_csrf_token()
    if token ~= server_token then
        write_log("CSRF token mismatch: expected " .. server_token .. ", got " .. token)
        return false
    end
    return true
end

-- 页面初始化时加载 CSRF Token
local csrf_token = get_or_set_csrf_token()
--luci.dispatcher.context.token = csrf_token

-- 上传表单
local ful = SimpleForm("upload", translate("Upload"), nil)
ful.reset = false
ful.submit = false

local sul = ful:section(SimpleSection, "", translate("Upload file to '/tmp/upload/'"))
local fu = sul:option(FileUpload, "")
fu.template = "cbi/other_upload"

local um = sul:option(DummyValue, "", nil)
um.template = "cbi/other_dvalue"

-- 上传处理
http.setfilehandler(function(meta, chunk, eof)
    -- 打印 meta, chunk, eof 到前端页面
    local log_message = "Meta: " .. tostring(meta) .. ", Chunk: " .. tostring(chunk) .. ", EOF: " .. tostring(eof)
    um.value = log_message  -- 直接显示在前端页面
    write_log(log_message)  -- 后台日志打印
    local fd
    if meta and not fd then
        fd = io.open(dir .. meta.file, "w")
        if not fd then
            local msg = translate("Failed to open file for writing: ") .. meta.file
            um.value = msg
            write_log(msg)
            return
        end
    end
    if chunk and fd then
        fd:write(chunk)
    end
    if eof and fd then
        fd:close()
        local msg = translate("File saved to ") .. dir .. meta.file
        um.value = msg
        write_log(msg)
    end
end)

-- 下载表单
local fdl = SimpleForm("download", translate("Download"), nil)
fdl.reset = false
fdl.submit = false

local sdl = fdl:section(SimpleSection, "", translate("Download file: input file/dir path"))
local fd = sdl:option(FileUpload, "")
fd.template = "cbi/other_download"

local dm = sdl:option(DummyValue, "", nil)
dm.template = "cbi/other_dvalue"

-- 文件下载函数
local function download_file()
    local sPath = http.formvalue("dlfile")
    if not sPath or #sPath == 0 then
        local msg = translate("No file path specified for download.")
        dm.value = msg
        write_log(msg)
        return
    end

    local sFile = fs.basename(sPath)
    local fd

    if fs.stat(sPath, "type") == "directory" then
        fd = io.popen(string.format('tar -C "%s" -cz .', sPath), "r")
        sFile = sFile .. ".tar.gz"
    else
        fd = io.open(sPath, "r")
    end

    if not fd then
        local msg = translate("Couldn't open file: ") .. sPath
        dm.value = msg
        write_log(msg)
        return
    end

    dm.value = nil
    http.header('Content-Disposition', string.format('attachment; filename="%s"', sFile))
    http.prepare_content("application/octet-stream")

    while true do
        local block = fd:read(8192)
        if not block then break end
        http.write(block)
    end

    fd:close()
    write_log("File downloaded successfully: " .. sPath)
end

-- 表单提交处理
if http.formvalue("upload") then
    -- 获取 CSRF Token
    local csrf_token_from_form = http.formvalue("csrf_token")
    if not csrf_token_from_form or #csrf_token_from_form == 0 then
        um.value = translate("CSRF token is missing.")
        write_log("CSRF token is missing for upload action.")
    elseif not validate_csrf_token(csrf_token_from_form) then
        um.value = translate("Invalid CSRF token!")
        write_log("CSRF token validation failed for upload action.")
    else
        -- 获取上传文件字段
        local upload_file = http.formvalue("ulfile")
        if not upload_file or #upload_file == 0 then
            local msg = translate("No file specified for upload.")
            um.value = msg
            write_log(msg)  -- 记录日志
        end
    end
elseif http.formvalue("download") then
    -- 获取下载路径字段
    local download_path = http.formvalue("dlfile")
        
    -- 路径为空时的处理逻辑
    if not download_path or #download_path == 0 then
        local msg = translate("No file path specified for download.")
        dm.value = msg  -- 将错误信息显示在界面
        write_log(msg)  -- 记录日志
    else
        -- 检查文件是否存在
        if not nixio.fs.stat(download_path) then
            local msg = translate("Specified file or directory does not exist: ") .. download_path
            dm.value = msg  -- 将错误信息显示在界面
            write_log(msg)  -- 记录日志
        else
            -- 下载文件
            download_file()
        end
    end
end



-- 获取上传目录文件列表
local inits = {}
for f in fs.glob("/tmp/upload/*") do
    local attr = fs.stat(f)
    if attr then
        table.insert(inits, {
            name = fs.basename(f),
            mtime = os.date("%Y-%m-%d %H:%M:%S", attr.mtime),
            modestr = attr.modestr,
            size = tostring(attr.size),
        })
    end
end

-- 文件列表显示
local form = SimpleForm("filelist", translate("Upload file list"), nil)
form.reset = false
form.submit = false

local tb = form:section(Table, inits)
local nm = tb:option(DummyValue, "name", translate("File name"))
local mt = tb:option(DummyValue, "mtime", translate("Modify time"))
local ms = tb:option(DummyValue, "modestr", translate("Mode string"))
local sz = tb:option(DummyValue, "size", translate("Size"))

-- 安装 .ipk 文件
function IsIpkFile(name)
    name = name or ""
    local ext = string.lower(string.sub(name, -4, -1))
    return ext == ".ipk"
end

-- 安装按钮逻辑
btnis = tb:option(Button, "install", translate("Install"))
btnis.template = "cbi/other_button"
btnis.render = function(self, section, scope)
    if not inits[section] then return false end
    if IsIpkFile(inits[section].name) then
        scope.display = ""  -- 显示安装按钮
    else
        scope.display = "none"  -- 隐藏按钮
    end
    self.inputstyle = "apply"  -- 按钮样式
    Button.render(self, section, scope)
end

-- 安装 .ipk 文件的操作
btnis.write = function(self, section)
    local filename = inits[section].name
    if not IsIpkFile(filename) then
        return
    end

    -- 执行安装命令
    local install_cmd = "opkg install /tmp/upload/" .. filename
    local result = luci.sys.call(install_cmd)

    if result == 0 then
        local msg = translate("IPK installation successful: ") .. filename
        write_log(msg)
        um.value = msg
    else
        local msg = translate("IPK installation failed: ") .. filename
        write_log(msg)
        um.value = msg
    end
end

-- 删除文件按钮
local btnrm = tb:option(Button, "remove", translate("Remove"))
btnrm.inputstyle = "remove"
btnrm.write = function(self, section)
    local filename = inits[section].name
    if fs.unlink(dir .. filename) then
        table.remove(inits, section)
        write_log("File removed: " .. filename)
    end
end

-- 日志表单
local log_form = SimpleForm("log", translate("Operation Log"), nil)
log_form.reset = false
log_form.submit = false

local log_section = log_form:section(SimpleSection, "", translate("Recent Logs"))
local log_view = log_section:option(TextValue, "log")
log_view.rows = 10
log_view.readonly = true
log_view.cfgvalue = function()
    return fs.readfile(log_file) or ""
end

return ful, fdl, form, log_form
