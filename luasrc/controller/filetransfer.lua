
module("luci.controller.filetransfer", package.seeall)
-- 在控制器或页面的头部加载翻译
local translate = require "luci.i18n".translate

-- 设置 CSRF 令牌
function index()
    --local csrf = require "luci.csrf"  -- 引入 luci.csrf 模块来处理 CSRF
    --local csrf_token = csrf.token()   -- 获取 CSRF 令牌
    --luci.dispatcher.context.token = csrf_token  -- 将 token 存储在 dispatcher 上下文中

    -- 打印 token 值到后台日志
    --print("CSRF Token: " .. (csrf_token or "nil"))

    entry({"admin", "system", "filetransfer"}, cbi("updownload"), translate("FileTransfer"), 89)
end
