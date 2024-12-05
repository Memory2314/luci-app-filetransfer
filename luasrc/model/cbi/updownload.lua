local fs = require "nixio.fs"
local http = luci.http
local sys = require "luci.sys"

-- 设置文件上传目录
local dir = "/tmp/upload/"
nixio.fs.mkdir(dir)

-- CSRF Token 文件路径
local csrf_token_file = "/tmp/csrf_token.txt"

-- 日志文件路径
local log_file = "/tmp/upload/operation_log.txt"
fs.writefile(log_file, "", "w") -- 初始化日志文件

-- 生成或获取 CSRF Token
local function get_or_set_csrf_token()
    if not fs.access(csrf_token_file) then
        local token = tostring(os.time()) .. tostring(math.random(100000, 999999))
        fs.writefile(csrf_token_file, token)
        return token
    end
    return fs.readfile(csrf_token_file):gsub("\n", "")
end

-- 验证 CSRF Token
local function validate_csrf_token(token)
    local valid = false
    if token and #token > 0 then
        valid = token == get_or_set_csrf_token()
    end

    if not valid then
        write_log("CSRF token validation failed: " .. (token or "nil"))
    end
    return valid
end

-- 日志记录函数
local function write_log(message)
    local log_entry = os.date("[%Y-%m-%d %H:%M:%S] ") .. message .. "\n"
    fs.writefile(log_file, log_entry, "a")
end

-- 页面初始化时加载 CSRF Token
local csrf_token = get_or_set_csrf_token()
luci.dispatcher.context.token = csrf_token

-- 上传表单
local ful = SimpleForm("upload", translate("Upload"), nil)
ful.reset = false
ful.submit = false

local sul = ful:section(SimpleSection, "", translate("Upload file to '/tmp/upload/'"))
local fu = sul:option(FileUpload, "")
fu.template = "cbi/other_upload"

local um = sul:option(DummyValue, "", nil)
um.template = "cbi/other_dvalue"

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
        fd = io.popen('tar -C "%s" -cz .' % {sPath}, "r")
        sFile = sFile .. ".tar.gz"
    else
        fd = fs.open(sPath, "r")
    end

    if not fd then
        local msg = translate("Couldn't open file: ") .. sPath
        dm.value = msg
        write_log(msg)
        return
    end

    dm.value = nil
    http.header('Content-Disposition', 'attachment; filename="%s"' % {sFile})
    http.prepare_content("application/octet-stream")

    while true do
        local block = fd:read(nixio.const.buffersize)
        if not block or #block == 0 then break end
        http.write(block)
    end

    fd:close()
    http.close()
    write_log("File downloaded successfully: " .. sPath)
end

-- 上传处理
http.setfilehandler(function(meta, chunk, eof)
    -- 打印 meta, chunk, eof 到前端页面
    local log_message = "Meta: " .. tostring(meta) .. ", Chunk: " .. tostring(chunk) .. ", EOF: " .. tostring(eof)
    um.value = log_message  -- 直接显示在前端页面
    write_log(log_message)  -- 后台日志打印
    local fd
    if not fd then
        if not meta then return end
        fd = fs.open(dir .. meta.file, "w")
        if not fd then
            local msg = translate("Create upload file error.")
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
        local msg = translate("File saved to") .. ' "/tmp/upload/' .. meta.file .. '"'
        um.value = msg
        write_log(msg)
    end
end)

-- 表单提交处理
if http.formvalue("upload") then
    local csrf_token_from_form = http.formvalue("csrf_token")
    if not validate_csrf_token(csrf_token_from_form) then
        local msg = translate("Invalid CSRF token!")
        um.value = msg
        write_log(msg)
    else
        local file = http.formvalue("ulfile")
        if not file or #file == 0 then
            local msg = translate("No specified upload file.")
            um.value = msg
            write_log(msg)
        end
    end
elseif http.formvalue("download") then
    local csrf_token_from_form = http.formvalue("csrf_token")
    if not validate_csrf_token(csrf_token_from_form) then
        local msg = translate("Invalid CSRF token!")
        dm.value = msg
        write_log(msg)
    else
        download_file()
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

-- 判断是否为 IPK 文件
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
