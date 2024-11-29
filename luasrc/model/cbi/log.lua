--
local NXFS = require "nixio.fs"
local SYS  = require "luci.sys"
local HTTP = require "luci.http"

m = Map("filetransfer", translate("Server Logs"))
s = m:section(TypedSection, "filetransfer")
m.pageaction = false
s.anonymous = true
s.addremove=false

log = s:option(TextValue, "clog")
log.readonly=true
log.pollcheck=true
log.template="filetransfer/log"
log.description = translate("")
log.rows = 29

m:append(Template("filetransfer/toolbar_show"))
m:append(Template("filetransfer/config_editor"))

return m