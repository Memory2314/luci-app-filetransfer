local fs = require "nixio.fs"
local http = luci.http
local sys = require "luci.sys"

-- 设置文件上传目录
local dir = "/tmp/upload/"
nixio.fs.mkdir(dir)

-- 获取 CSRF Token
local csrf_token_file = "/tmp/csrf_token.txt"
function get_csrf_token()
    return luci.sys.exec("cat " .. csrf_token_file):gsub("\n", "")
end

-- 设置 CSRF Token
function set_csrf_token()
    -- 生成新的 CSRF Token
    local csrf_token = sys.exec("uuidgen"):gsub("\n", "")
    -- 存储到临时文件
    luci.sys.call("echo '" .. csrf_token .. "' > " .. csrf_token_file)
    return csrf_token
end

-- 清除 CSRF Token 文件
function clear_csrf_token()
    luci.sys.call("rm -f " .. csrf_token_file)
end

-- 页面初始化时加载 CSRF Token
ful = SimpleForm("upload", translate("Upload"), nil)
ful.reset = false
ful.submit = false

-- 上传表单部分
sul = ful:section(SimpleSection, "", translate("Upload file to '/tmp/upload/'"))
fu = sul:option(FileUpload, "")
fu.template = "cbi/other_upload"
um = sul:option(DummyValue, "", nil)
um.template = "cbi/other_dvalue"

-- 下载表单部分
fdl = SimpleForm("download", translate("Download"), nil)
fdl.reset = false
fdl.submit = false
sdl = fdl:section(SimpleSection, "", translate("Download file :input file/dir path"))
fd = sdl:option(FileUpload, "")
fd.template = "cbi/other_download"
dm = sdl:option(DummyValue, "", nil)
dm.template = "cbi/other_dvalue"

-- 文件下载函数
function Download()
    local sPath, sFile, fd, block
    sPath = http.formvalue("dlfile")
    sFile = nixio.fs.basename(sPath)

    if nixio.fs.stat(sPath, "type") == "directory" then
        fd = io.popen('tar -C "%s" -cz .' % {sPath}, "r")
        sFile = sFile .. ".tar.gz"
    else
        fd = nixio.open(sPath, "r")
    end

    if not fd then
        dm.value = translate("Couldn't open file: ") .. sPath
        return
    end

    dm.value = nil
    http.header('Content-Disposition', 'attachment; filename="%s"' % {sFile})
    http.prepare_content("application/octet-stream")

    while true do
        block = fd:read(nixio.const.buffersize)
        if (not block) or (#block == 0) then
            break
        else
            http.write(block)
        end
    end
    fd:close()
    http.close()
end

-- 处理上传操作
http.setfilehandler(function(meta, chunk, eof)
    local fd
    if not fd then
        if not meta then return end
        fd = nixio.open(dir .. meta.file, "w")
        if not fd then
            um.value = translate("Create upload file error.")
            return
        end
    end
    if chunk and fd then
        fd:write(chunk)
    end
    if eof and fd then
        fd:close()
        fd = nil
        um.value = translate("File saved to") .. ' "/tmp/upload/' .. meta.file .. '"'
    end
end)

-- CSRF Token 处理
local csrf_token = set_csrf_token()  -- 生成 CSRF Token
luci.dispatcher.context.token = csrf_token  -- 将 Token 存储在上下文中

-- 表单提交时验证 CSRF Token
if luci.http.formvalue("upload") then
    local csrf_token_from_form = luci.http.formvalue("token")
    if csrf_token_from_form ~= get_csrf_token() then
        um.value = translate("Invalid CSRF token!")
    else
        local f = luci.http.formvalue("ulfile")
        if #f <= 0 then
            um.value = translate("No specify upload file.")
        end
    end
elseif luci.http.formvalue("download") then
    local csrf_token_from_form = luci.http.formvalue("token")
    if csrf_token_from_form ~= get_csrf_token() then
        dm.value = translate("Invalid CSRF token!")
    else
        Download()
    end
end

-- 获取上传目录下的文件列表
local inits, attr = {}
local idx = 1
for f in fs.glob("/tmp/upload/*") do
    attr = fs.stat(f)
    if attr then
        inits[idx] = {}
        inits[idx].name = fs.basename(f)
        inits[idx].mtime = os.date("%Y-%m-%d %H:%M:%S", attr.mtime)
        inits[idx].modestr = attr.modestr
        inits[idx].size = tostring(attr.size)
        inits[idx].remove = 0
        inits[idx].install = false
        idx = idx + 1
    end
end

-- 显示文件列表
form = SimpleForm("filelist", translate("Upload file list"), nil)
form.reset = false
form.submit = false

tb = form:section(Table, inits)
nm = tb:option(DummyValue, "name", translate("File name"))
mt = tb:option(DummyValue, "mtime", translate("Modify time"))
ms = tb:option(DummyValue, "modestr", translate("Mode string"))
sz = tb:option(DummyValue, "size", translate("Size"))
btnrm = tb:option(Button, "remove", translate("Remove"))
btnrm.render = function(self, section, scope)
    self.inputstyle = "remove"
    Button.render(self, section, scope)
end

btnrm.write = function(self, section)
    local v = nixio.fs.unlink("/tmp/upload/" .. nixio.fs.basename(inits[section].name))
    if v then table.remove(inits, section) end
    return v
end

function IsIpkFile(name)
    name = name or ""
    local ext = string.lower(string.sub(name, -4, -1))
    return ext == ".ipk"
end

btnis = tb:option(Button, "install", translate("Install"))
btnis.template = "cbi/other_button"
btnis.render = function(self, section, scope)
    if not inits[section] then return false end
    if IsIpkFile(inits[section].name) then
        scope.display = ""
    else
        scope.display = "none"
    end
    self.inputstyle = "apply"
    Button.render(self, section, scope)
end

btnis.write = function(self, section)
    local r = luci.sys.exec(string.format('opkg --force-depends install "/tmp/upload/%s"', inits[section].name))
    form.description = string.format('<span style="color: red">%s</span>', r)
end

return ful, fdl, form
