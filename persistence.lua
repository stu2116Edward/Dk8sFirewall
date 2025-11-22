local cjson = require "cjson"

-- 持久化存储模块
local _M = {}

-- 存储文件路径
_M.storage_file = "data/traffic_stats.json"

-- 确保目录存在
local function ensure_directory()
    local dir = "data"
    local cmd = "mkdir " .. dir
    os.execute(cmd)
end

-- 保存数据到文件
function _M.save_to_file(dict)
    ensure_directory()
    
    local keys = dict:get_keys(0)
    local structured_data = {
        metadata = {
            save_time = os.date("%Y-%m-%d %H:%M:%S"),
            total_keys = #keys,
            version = "1.1"
        },
        statistics = {}
    }
    
    -- 按IP地址组织数据
    for _, key in ipairs(keys) do
        local value = dict:get(key)
        if value ~= nil then
            -- 解析键名格式: "type:period:ip"
            -- 修复IPv6地址解析问题：IPv6地址包含冒号，需要特殊处理
            local first_colon = key:find(":")
            local second_colon = first_colon and key:find(":", first_colon + 1)
            
            if first_colon and second_colon then
                local data_type = key:sub(1, first_colon - 1)  -- last, count, bytes, costs, forbidden
                local period = key:sub(first_colon + 1, second_colon - 1)  -- hour, day
                local ip = key:sub(second_colon + 1)  -- IP地址（可能包含冒号的IPv6地址）
                
                -- 初始化IP数据结构
                if not structured_data.statistics[ip] then
                    structured_data.statistics[ip] = {
                        hour = {},
                        day = {}
                    }
                end
                
                -- 根据数据类型存储到对应位置
                if data_type == "last" then
                    structured_data.statistics[ip][period].last_time = value
                elseif data_type == "count" then
                    structured_data.statistics[ip][period].count = value
                elseif data_type == "bytes" then
                    structured_data.statistics[ip][period].bytes = value
                elseif data_type == "costs" then
                    structured_data.statistics[ip][period].costs = value
                elseif data_type == "forbidden" then
                    structured_data.statistics[ip][period].forbidden = value
                end
            else
                -- 对于不符合格式的键，保持原始存储
                if not structured_data.raw_keys then
                    structured_data.raw_keys = {}
                end
                structured_data.raw_keys[key] = value
            end
        end
    end
    
    local file = io.open(_M.storage_file, "w")
    if file then
        file:write(cjson.encode(structured_data))
        file:close()
        ngx.log(ngx.INFO, "Traffic stats saved to structured file: ", _M.storage_file)
        return true
    else
        ngx.log(ngx.ERR, "Failed to open file for writing: ", _M.storage_file)
        return false
    end
end

-- 从文件加载数据
function _M.load_from_file(dict)
    ensure_directory()
    
    local file = io.open(_M.storage_file, "r")
    if not file then
        ngx.log(ngx.INFO, "No existing data file found: ", _M.storage_file)
        return false
    end
    
    local content = file:read("*a")
    file:close()
    
    if not content or content == "" then
        ngx.log(ngx.INFO, "Data file is empty")
        return false
    end
    
    local ok, data = pcall(cjson.decode, content)
    if not ok then
        ngx.log(ngx.ERR, "Failed to parse JSON from file: ", data)
        return false
    end
    
    local loaded_count = 0
    
    -- 检查数据格式：如果是结构化数据
    if data.statistics then
        -- 处理结构化数据
        for ip, ip_data in pairs(data.statistics) do
            for period, period_data in pairs(ip_data) do
                if type(period_data) == "table" then
                    if period_data.last_time then
                        local key = "last:" .. period .. ":" .. ip
                        local set_ok, err = dict:set(key, period_data.last_time)
                        if set_ok then loaded_count = loaded_count + 1 end
                    end
                    if period_data.count then
                        local key = "count:" .. period .. ":" .. ip
                        local set_ok, err = dict:set(key, period_data.count)
                        if set_ok then loaded_count = loaded_count + 1 end
                    end
                    if period_data.bytes then
                        local key = "bytes:" .. period .. ":" .. ip
                        local set_ok, err = dict:set(key, period_data.bytes)
                        if set_ok then loaded_count = loaded_count + 1 end
                    end
                    if period_data.costs then
                        local key = "costs:" .. period .. ":" .. ip
                        local set_ok, err = dict:set(key, period_data.costs)
                        if set_ok then loaded_count = loaded_count + 1 end
                    end
                    if period_data.forbidden then
                        local key = "forbidden:" .. period .. ":" .. ip
                        local set_ok, err = dict:set(key, period_data.forbidden)
                        if set_ok then loaded_count = loaded_count + 1 end
                    end
                end
            end
        end
        
        -- 处理原始键值对（向后兼容）
        if data.raw_keys then
            for key, value in pairs(data.raw_keys) do
                local set_ok, err = dict:set(key, value)
                if set_ok then loaded_count = loaded_count + 1 end
            end
        end
    else
        -- 处理旧的扁平化数据格式（向后兼容）
        for key, value in pairs(data) do
            local set_ok, err = dict:set(key, value)
            if set_ok then
                loaded_count = loaded_count + 1
            else
                ngx.log(ngx.ERR, "Failed to set key ", key, " from file: ", err)
            end
        end
    end
    
    ngx.log(ngx.INFO, "Loaded ", loaded_count, " items from file: ", _M.storage_file)
    return true
end

-- 定时保存函数（在init_worker阶段调用）
function _M.setup_timer_save()
    local dict = ngx.shared.traffic_stats
    
    -- 先尝试加载现有数据
    _M.load_from_file(dict)
    
    -- 设置定时保存（每5分钟保存一次）
    local delay = 300  -- 5分钟
    local handler
    handler = function(premature)
        if premature then
            return
        end
        
        local ok, err = pcall(_M.save_to_file, dict)
        if not ok then
            ngx.log(ngx.ERR, "Timer save failed: ", err)
        end
        
        -- 重新设置定时器
        local ok, err = ngx.timer.at(delay, handler)
        if not ok then
            ngx.log(ngx.ERR, "Failed to create timer: ", err)
        end
    end
    
    -- 启动定时器
    local ok, err = ngx.timer.at(delay, handler)
    if not ok then
        ngx.log(ngx.ERR, "Failed to create initial timer: ", err)
    end
end

-- 优雅关闭时的保存
function _M.save_on_shutdown()
    local dict = ngx.shared.traffic_stats
    _M.save_to_file(dict)
end

return _M
