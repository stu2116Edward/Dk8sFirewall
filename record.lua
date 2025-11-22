function str_concat(...)
    local str = {...}
    return table.concat(str, ':')
end

function stats(during)
    local request_length = ngx.var.request_length
    local bytes_sent = ngx.var.bytes_sent
    local ip = ngx.var.limit_key
    -- 使用标准化的IP地址进行统计，确保IPv6地址正确处理
    local normalized_ip = ngx.var.normalized_ip or ip
    local dict = ngx.shared.traffic_stats
    local count_key = str_concat("count", during, normalized_ip)
    local bytes_key = str_concat("bytes", during, normalized_ip)
    local costs_key = str_concat("costs", during, normalized_ip)

    -- 使用os.clock()计算实际耗时（秒，高精度）
    local start_clock = ngx.ctx.start_clock or os.clock()
    local request_time = os.clock() - start_clock  -- 耗时（秒）
    -- local request_time_us = math.floor(request_time * 1000000 + 0.5)  -- 转换为微秒
    local request_time_us = request_time * 1000000  -- 转换为微秒

    -- 检查是否能成功写入共享内存，如果失败则记录错误并退出
    local ok, err = dict:incr(count_key, 1)
    if not ok then
        ngx.log(ngx.ERR, "Failed to incr count for key ", count_key, ": ", err)
        -- 可以选择在这里也退出，或者让请求继续，但统计可能不准确
        -- ngx.exit(444) 
    end

    ok, err = dict:incr(bytes_key, request_length + bytes_sent)
    if not ok then
        ngx.log(ngx.ERR, "Failed to incr bytes for key ", bytes_key, ": ", err)
        -- ngx.exit(444)
    end

    ok, err = dict:incr(costs_key, request_time_us)
    if not ok then
        ngx.log(ngx.ERR, "Failed to incr costs for key ", costs_key, ": ", err)
        -- ngx.exit(444)
    end

    -- 添加日志验证（可选）
    -- ngx.log(ngx.INFO, "IP: ", ip, 
    --         " | Duration: ", request_time_us, " μs",
    --         " | Clock: ", request_time, "s")
end

stats("hour")
stats("day")
