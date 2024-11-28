module("luci.controller.filetransfer", package.seeall)

-- 在控制器或页面的头部加载翻译
local translate = require "luci.i18n".translate
local sys = require "luci.sys"
local uhttpd = require "luci.http"

-- CSRF Token 存储路径
local csrf_token_file = "/tmp/csrf_token.txt"

-- 生成并设置新的 CSRF Token
function set_csrf_token()
    -- 生成一个新的 CSRF Token
    -- local csrf_token = sys.exec("uuidgen")
    local csrf_token = tostring(os.time()) .. tostring(math.random(100000, 999999))
    
    -- 存储 CSRF Token 到临时文件
    luci.sys.call("echo " .. csrf_token .. " > " .. csrf_token_file)
    
    return csrf_token
end

-- 获取 CSRF Token
function get_csrf_token()
    -- 读取并返回 CSRF Token
    return luci.sys.exec("cat " .. csrf_token_file)
end

-- 清除 CSRF Token 文件
function clear_csrf_token()
    luci.sys.call("rm -f " .. csrf_token_file)
end

-- 设置 CSRF 令牌
function index()
    entry({"admin", "system", "filetransfer"}, cbi("updownload"), translate("FileTransfer"), 89)
end

-- 页面加载时生成并返回 CSRF Token
function action_index()
    -- 生成并存储 CSRF Token
    local csrf_token = set_csrf_token()
    luci.dispatcher.context.token = csrf_token  -- 将 token 存储到上下文中
end

-- 处理表单提交时验证 CSRF Token
function action_submit()
    local csrf_token_from_form = luci.http.formvalue("csrf_token")
    local csrf_token_stored = get_csrf_token()

    -- 如果 CSRF Token 不匹配，拒绝请求
    if csrf_token_from_form ~= csrf_token_stored then
        luci.http.status(403, "Forbidden")
        luci.http.write("Invalid CSRF token.")
        return
    end

    -- 表单处理逻辑
    local message = luci.http.formvalue("message")
    luci.http.write("Form submitted successfully with message: " .. message)
    
    -- 清理临时 CSRF Token 文件
    clear_csrf_token()
end
