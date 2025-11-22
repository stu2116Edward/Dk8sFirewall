-- 手动保存数据接口
ngx.header.content_type = "application/json; charset=utf-8"

local persistence = require "persistence"
local dict = ngx.shared.traffic_stats

local action = ngx.var.arg_action or "save"

if action == "save" then
    local success = persistence.save_to_file(dict)
    if success then
        ngx.say('{"status": "success", "message": "Data saved successfully"}')
    else
        ngx.say('{"status": "error", "message": "Failed to save data"}')
    end
elseif action == "load" then
    local success = persistence.load_from_file(dict)
    if success then
        ngx.say('{"status": "success", "message": "Data loaded successfully"}')
    else
        ngx.say('{"status": "error", "message": "Failed to load data"}')
    end
else
    ngx.say('{"status": "error", "message": "Invalid action. Use save or load"}')
end
