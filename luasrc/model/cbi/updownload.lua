local fs = require "nixio.fs"
local http = luci.http

ful = SimpleForm("upload", translate("Upload"), nil)
ful.reset = false
ful.submit = false

sul = ful:section(SimpleSection, "", translate("Upload file to '/tmp/upload/'"))
fu = sul:option(FileUpload, "")
fu.template = "cbi/other_upload"
um = sul:option(DummyValue, "", nil)
um.template = "cbi/other_dvalue"

fdl = SimpleForm("download", translate("Download"), nil)
fdl.reset = false
fdl.submit = false
sdl = fdl:section(SimpleSection, "", translate("Download file :input file/dir path"))
fd = sdl:option(FileUpload, "")
fd.template = "cbi/other_download"
dm = sdl:option(DummyValue, "", nil)
dm.template = "cbi/other_dvalue"


-- CSRF Token Verification
--local token = http.formvalue("token")
--if not token or token ~= (require "luci.sys").auth().get_csrf_token() then
--    http.status(403, "Invalid CSRF Token")
--    return
--end

-- File Upload Logic
--local filepath = http.formvalue("ulfile")
--if filepath then
--    local success, err = nixio.fs.move(filepath, "/tmp/upload/" .. nixio.fs.basename(filepath))
--    if not success then
--        http.status(500, "Failed to upload file: " .. err)
--        return
--    end
--end


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
		if (not block) or (#block ==0) then
			break
		else
			http.write(block)
		end
	end
	fd:close()
	http.close()
end

local dir, fd
dir = "/tmp/upload/"
nixio.fs.mkdir(dir)
http.setfilehandler(
	function(meta, chunk, eof)
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
	end
)

if luci.http.formvalue("upload") then
	local f = luci.http.formvalue("ulfile")
	if #f <= 0 then
		um.value = translate("No specify upload file.")
	end
elseif luci.http.formvalue("download") then
	Download()
end

local inits, attr = {}
local idx = 1 -- 记录下标
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
