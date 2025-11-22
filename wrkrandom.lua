local random = math.random

function request()
    -- 按指定格式生成随机IP
    local ip = string.format("%d.%d.%d.%d", random(0, 255), random(0, 255), random(0, 255), random(0, 255))
    wrk.headers["X-Forwarded-For"] = ip

    -- 生成128位随机路径（URL安全字符）
    local path = "/"
    local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"
    for i = 1, 128 do
        path = path .. chars:sub(random(#chars), random(#chars))
    end

    return wrk.format("GET", path)
end
