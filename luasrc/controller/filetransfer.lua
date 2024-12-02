module("luci.controller.filetransfer", package.seeall)



-- 在控制器或页面的头部加载翻译
local translate = require "luci.i18n".translate
local sys = require "luci.sys"
local uhttpd = require "luci.http"

-- CSRF Token 存储路径
local csrf_token_file = "/tmp/csrf_token.txt"
local log_file = "/tmp/filetransfer.log"  -- 日志文件路径

-- 生成并设置新的 CSRF Token
function set_csrf_token()
    -- 生成一个新的 CSRF Token
    local csrf_token = tostring(os.time()) .. tostring(math.random(100000, 999999))
    
    -- 存储 CSRF Token 到临时文件
    luci.sys.call("echo " .. csrf_token .. " > " .. csrf_token_file)
    
    -- 将生成的 CSRF Token 记录到日志文件
    local log_message = "Generated CSRF Token: " .. csrf_token
    log_to_file(log_message)  -- 调用 log_to_file 函数写入日志

    return csrf_token
end

-- 记录日志到文件的函数
function log_to_file(message)
    local file = io.open(log_file, "a")  -- 打开文件，追加模式
    if file then
        file:write(os.date("%Y-%m-%d %H:%M:%S") .. " - " .. message .. "\n")
        file:close()
    end
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
     -- 主入口页面
     entry({"admin", "system", "filetransfer"}, firstchild(), translate("FileTransfer"), 89).dependent = false

     -- 文件传输页面
     entry({"admin", "system", "filetransfer", "updownload"}, cbi("updownload"), translate("File Transfer"), 1).leaf = true
 
     -- 日志页面
     entry({"admin", "system", "filetransfer", "log"}, cbi("log"), translate("Server Logs"), 2).leaf = true
    
     -- 日志页面相关接口
     entry({"admin", "system", "filetransfer", "startlog"}, call("action_start")).leaf = true
     entry({"admin", "system", "filetransfer", "refresh_log"}, call("action_refresh_log"))
     entry({"admin", "system", "filetransfer", "del_log"}, call("action_del_log"))
     entry({"admin", "system", "filetransfer", "del_start_log"}, call("action_del_start_log"))
     entry({"admin", "system", "filetransfer", "log_level"}, call("action_log_level"))
     entry({"admin", "system", "filetransfer", "switch_log"}, call("action_switch_log"))
end

-- 页面加载时生成并返回 CSRF Token
function action_index()
    -- 生成并存储 CSRF Token
    local csrf_token = set_csrf_token()
    luci.dispatcher.context.token = csrf_token  -- 将 token 存储到上下文中

    -- 将 CSRF Token 的创建过程记录到日志
    local log_message = "CSRF Token set during action_index: " .. csrf_token
    log_to_file(log_message)  -- 记录到日志
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



function action_start()
	luci.http.prepare_content("application/json")
	luci.http.write_json({
			startlog = startlog();
	})
end


function action_refresh_log()
    luci.http.prepare_content("application/json")
    local logfile = "/tmp/filetransfer.log"

    -- 调试代码：检查日志文件写入
    local output = luci.sys.exec("echo Hello > /tmp/filetransfer.log")
    log_to_file("Command output: " .. output)

    local file = io.open(logfile, "r+")
    local info, len, line, lens, cache, ex_match, line_trans
    local data = ""
    local limit = 1000
    local log_tb = {}
    local log_len = tonumber(luci.http.formvalue("log_len")) or 0
    if file == nil then
        return nil
    end
    file:seek("set")
    info = file:read("*all")
    info = info:reverse()
    file:close()

    cache, len = string.gsub(info, '[^\n]+', "")
    if len == log_len then return nil end
    if log_len == 0 then
        if len > limit then lens = limit else lens = len end
    else
        lens = len - log_len
    end

    string.gsub(info, '[^\n]+', function(w) table.insert(log_tb, w) end, lens)
    for i = 1, lens do
        line = log_tb[i]:reverse()
        line_trans = line
        ex_match = false
        core_match = false
        time_format = false
        while true do
            ex_keys = {"UDP%-Receive%-Buffer%-Size", "^Sec%-Fetch%-Mode", "^User%-Agent", "^Access%-Control", "^Accept", "^Origin", "^Referer", "^Connection", "^Pragma", "^Cache-"}
            for key = 1, #ex_keys do
                if string.find(line, ex_keys[key]) then
                    ex_match = true
                    break
                end
            end
            if ex_match then break end

            core_keys = {" DBG ", " INF ", "level=", " WRN ", " ERR ", " FTL "}
            for key = 1, #core_keys do
                if string.find(string.sub(line, 0, 13), core_keys[key]) or (string.find(line, core_keys[key]) and core_keys[key] == "level=") then
                    core_match = true
                    if core_keys[key] ~= "level=" then
                        time_format = true
                    end
                    break
                end
            end
            if time_format then
                if string.match(string.sub(line, 0, 8), "%d%d:%d%d:%d%d") then
                    line_trans = '"' .. os.date("%Y-%m-%d %H:%M:%S", tonumber(string.sub(line, 0, 8))) .. '"' .. string.sub(line, 9, -1)
                end
            end
            if not core_match then
                if not string.find(line, "【") or not string.find(line, "】") then
                    line_trans = trans_line_nolabel(line)
                else
                    line_trans = trans_line(line)
                end
            end
            if data == "" then
                data = line_trans
            elseif log_len == 0 and i == limit then
                data = data .. "\n" .. line_trans .. "\n..."
            else
                data = data .. "\n" .. line_trans
            end
            break
        end
    end

    luci.http.write_json({
        len = len,
        log = data;
    })
end


function action_del_log()
	luci.sys.exec(": > /tmp/filetransfer.log")
	return
end

function action_del_start_log()
	luci.sys.exec(": > /tmp/filetransfer_start.log")
	return
end

function action_log_level()
	local level, info
	if is_running() then
		local daip = daip()
		local dase = dase() or ""
		local cn_port = cn_port()
		if not daip or not cn_port then return end
		info = json.parse(luci.sys.exec(string.format('curl -sL -m 3 -H "Content-Type: application/json" -H "Authorization: Bearer %s" -XGET http://"%s":"%s"/configs', dase, daip, cn_port)))
		if info then
			level = info["log-level"]
		else
			level = uci:get("filetransfer", "config", "log_level") or "info"
		end
	else
		level = uci:get("filetransfer", "config", "log_level") or "info"
	end
	luci.http.prepare_content("application/json")
	luci.http.write_json({
		log_level = level;
	})
end

function action_switch_log()
	local level, info
	if is_running() then
		local daip = daip()
		local dase = dase() or ""
		local cn_port = cn_port()
		level = luci.http.formvalue("log_level")
		if not daip or not cn_port then luci.http.status(500, "Switch Faild") return end
		info = luci.sys.exec(string.format('curl -sL -m 3 -H "Content-Type: application/json" -H "Authorization: Bearer %s" -XPATCH http://"%s":"%s"/configs -d \'{\"log-level\": \"%s\"}\'', dase, daip, cn_port, level))
		if info ~= "" then
			luci.http.status(500, "Switch Faild")
		end
	else
		luci.http.status(500, "Switch Faild")
	end
	luci.http.prepare_content("application/json")
	luci.http.write_json({
		info = info;
	})
end