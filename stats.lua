ngx.header.content_type = "text/html; charset=utf-8"

-- Debug
-- 检查URL参数 "ask" 是否为 "true"
-- if ngx.var.arg_ask == "true" then
--     -- -- 获取所有请求头
--     -- local headers = ngx.req.get_headers()
--     -- ngx.say("--- Detected ask=true, Printing All Request Headers ---")
--     -- ngx.say("------------------------------------------------------")
    
--     -- -- 遍历并打印每一个请求头
--     -- for key, value in pairs(headers) do
--     --     -- 有些请求头可能有多个值，以table形式存在，这里做个兼容处理
--     --     if type(value) == "table" then
--     --         ngx.say(key .. ": " .. table.concat(value, ", "))
--     --     else
--     --         ngx.say(key .. ": " .. value)
--     --     end
--     -- end

--     -- ===================================================================
--     -- Part 1: 获取访客真实IP地址 (根据您的要求更新)
--     -- 优先级: CF-Connecting-IP > EO-Connecting-IP > X-Forwarded-For > remote_addr
--     -- ===================================================================
--     local cf_ip = ngx.var.http_cf_connecting_ip
--     local eo_ip = ngx.var.http_eo_connecting_ip -- Nginx 会自动将 'EO-Connecting-IP' 转为 'http_eo_connecting_ip'
--     local xff = ngx.var.http_x_forwarded_for
--     local current_visitor_ip
--     if cf_ip and cf_ip ~= "" then
--         current_visitor_ip = cf_ip
--     elseif eo_ip and eo_ip ~= "" then
--         current_visitor_ip = eo_ip
--     elseif xff and xff ~= "" then
--         -- 遍历 X-Forwarded-For 列表，获取最后一个非空的IP地址
--         local ips = {}
--         for ip in string.gmatch(xff, "([^, ]+)") do
--             table.insert(ips, ip)
--         end
--         if #ips > 0 then
--             current_visitor_ip = ips[#ips]
--         else
--             current_visitor_ip = ngx.var.remote_addr -- 如果 XFF 格式异常，则降级
--         end
--     else
--         -- 如果以上所有头都不存在，则使用直接连接的IP
--         current_visitor_ip = ngx.var.remote_addr
--     end

--     ngx.say("CF-Connecting-IP: ", cf_ip)
--     ngx.say("EO-Connecting-IP: ", eo_ip)
--     ngx.say("X-Forwarded-For: ", xff)
--     ngx.say("Current Visitor IP: ", current_visitor_ip)
    
--     ngx.say("--- All IPs in X-Forwarded-For ---")
--     if xff and xff ~= "" then
--         for ip in string.gmatch(xff, "([^, ]+)") do
--             ngx.say(ip)
--         end
--     else
--         ngx.say("X-Forwarded-For is empty or not present.")
--     end
    
--     ngx.say("------------------------------------------------------")
--     -- 打印完毕，正常退出，不再执行后面的统计代码
--     return ngx.exit(ngx.OK)
-- end

-- ======================================================
-- [[ 您原有的 stats.lua 代码从这里开始 ]]
-- ======================================================


-- status.lua (最终优化版 - 已确认能处理重复IP)

-- 获取当前访问者的真实 IP 地址
local xff = ngx.var.http_x_forwarded_for
local current_visitor_ip
if xff and xff ~= "" then
    -- 遍历 X-Forwarded-For 列表，获取最后一个非空的IP地址
    local ips = {}
    for ip in string.gmatch(xff, "([^, ]+)") do
        table.insert(ips, ip)
    end
    if #ips > 0 then
        current_visitor_ip = ips[#ips]
    else
        current_visitor_ip = ngx.var.remote_addr -- 如果 XFF 格式异常，则降级
    end
else
    current_visitor_ip = ngx.var.remote_addr
end

-- 字节转换
local function human_bytes(n)
    if not n then return "0 B" end
    if n < 1024 then return string.format("%d B", n) end
    if n < 1024 * 1024 then return string.format("%.2f KB", n / 1024) end
    if n < 1024 * 1024 * 1024 then return string.format("%.2f MB", n / (1024 * 1024)) end
    return string.format("%.2f GB", n / (1024 * 1024 * 1024))
end

-- 耗时转换
local function human_duration(us)
    if not us then return "0 μs" end
    return string.format("%d μs", us)
end

-- 获取限制阈值
local function get_limits(during)
    if during == "hour" then
        return {
            count = ngx.var.limit_count_per_hour,
            bytes = ngx.var.limit_bytes_per_hour,
            costs_us = tonumber(ngx.var.limit_costs_per_hour) * 1000
        }
    else -- day
        return {
            count = ngx.var.limit_count_per_day,
            bytes = ngx.var.limit_bytes_per_day,
            costs_us = tonumber(ngx.var.limit_costs_per_day) * 1000
        }
    end
end

-- 生成表格行
local function generate_table_rows(visitor_ip)
    local rows = ""
    local timestamp = ngx.now()
    local dict = ngx.shared.traffic_stats
    
    local function stats(during)
        local limits = get_limits(during)
        local bytes_limit_human = human_bytes(tonumber(limits.bytes))
        local costs_limit_human = human_duration(limits.costs_us)
        
        local keys = dict:get_keys(0)
        for _, val in pairs(keys) do
            local match = "last:"..during
            if val:sub(1, #match) == match then
                local ip = val:sub(#match + 2)
                
                -- 批量获取数据，减少竞态条件窗口
                local last_time = dict:get(val)
                local count = dict:get("count:"..during..":"..ip)
                local bytes = dict:get("bytes:"..during..":"..ip)
                local costs_us = dict:get("costs:"..during..":"..ip)
                local forbidden = dict:get("forbidden:"..during..":"..ip)

                -- 增加nil检查，如果数据在中途被删除，则跳过此条记录
                if last_time and count and bytes and costs_us then
                    local age = math.floor(timestamp - (tonumber(last_time) or timestamp))
                    local bytes_human = human_bytes(tonumber(bytes))
                    local costs_human = human_duration(tonumber(costs_us))
                    local forbidden_str = tostring(forbidden or false)

                    local row_style = ""
                    if ip == visitor_ip then
                        row_style = "style='background-color: #d4edda; font-weight: bold;'"
                    end
                    
                    rows = rows .. string.format([[
                        <tr %s>
                            <td class="ip-cell">%s</td>
                            <td>%s</td>
                            <td>%d</td>
                            <td>%d/%s</td>
                            <td>%s/%s</td>
                            <td>%s/%s</td>
                            <td>%s</td>
                            <td class="location-cell" data-ip="%s"></td>
                        </tr>
                    ]], 
                    row_style,
                    ip, during, age, 
                    tonumber(count), limits.count, 
                    bytes_human, bytes_limit_human, 
                    costs_human, costs_limit_human, 
                    forbidden_str,
                    ip
                    )
                end
            end
        end
    end
    
    stats("hour")
    stats("day")
    return rows
end

local request_type = ngx.var.arg_type or "page"

if request_type == "json" then
    -- JSON API 接口
    ngx.header.content_type = "application/json; charset=utf-8"
    
    local timestamp = ngx.now()
    local dict = ngx.shared.traffic_stats
    local data = {
        current_ip = current_visitor_ip,
        timestamp = timestamp,
        update_time = os.date("%Y-%m-%d %H:%M:%S"),
        stats = {}
    }
    
    local function get_stats_data(during)
        local limits = get_limits(during)
        local stats_data = {}
        local keys = dict:get_keys(0)
        
        for _, val in pairs(keys) do
            local match = "last:"..during
            if val:sub(1, #match) == match then
                local ip = val:sub(#match + 2)
                
                local last_time = dict:get(val)
                local count = dict:get("count:"..during..":"..ip)
                local bytes = dict:get("bytes:"..during..":"..ip)
                local costs_us = dict:get("costs:"..during..":"..ip)
                local forbidden = dict:get("forbidden:"..during..":"..ip)

                if last_time and count and bytes and costs_us then
                    local age = math.floor(timestamp - (tonumber(last_time) or timestamp))
                    
                    table.insert(stats_data, {
                        ip = ip,
                        period = during,
                        age = age,
                        count = tonumber(count),
                        count_limit = tonumber(limits.count),
                        bytes = tonumber(bytes),
                        bytes_limit = tonumber(limits.bytes),
                        bytes_human = human_bytes(tonumber(bytes)),
                        bytes_limit_human = human_bytes(tonumber(limits.bytes)),
                        costs_us = tonumber(costs_us),
                        costs_limit_us = limits.costs_us,
                        costs_human = human_duration(tonumber(costs_us)),
                        costs_limit_human = human_duration(limits.costs_us),
                        forbidden = tostring(forbidden or false),
                        is_current = (ip == current_visitor_ip)
                    })
                end
            end
        end
        
        return stats_data
    end
    
    -- 合并小时和天的数据
    local hour_stats = get_stats_data("hour")
    local day_stats = get_stats_data("day")
    
    for _, stat in ipairs(hour_stats) do
        table.insert(data.stats, stat)
    end
    for _, stat in ipairs(day_stats) do
        table.insert(data.stats, stat)
    end
    
    ngx.say(require("cjson").encode(data))
    
elseif request_type == "data" then
    -- 保持向后兼容的HTML数据接口
    ngx.say(generate_table_rows(current_visitor_ip))
else
    -- 新的客户端渲染页面
    ngx.say([[
    <!DOCTYPE html>
    <html>
    <head>
    <title>IP 限制与使用统计 (含归属地)</title>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; margin: 0; padding: 20px; background: #f5f5f5; }
        .container { max-width: 1800px; margin: 0 auto; background: white; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); overflow: hidden; }
        .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 20px; }
        .header h1 { margin: 0; font-size: 24px; }
        .current-ip { margin: 10px 0 0 0; font-size: 16px; opacity: 0.9; }
        .controls { background: #f8f9fa; padding: 15px 20px; border-bottom: 1px solid #e9ecef; display: flex; justify-content: space-between; align-items: center; }
        .stats-table { width: 100%; border-collapse: collapse; }
        .stats-table th { background: #f8f9fa; padding: 12px 15px; text-align: left; font-weight: 600; color: #495057; border-bottom: 2px solid #dee2e6; }
        .stats-table td { padding: 10px 15px; border-bottom: 1px solid #dee2e6; }
        .stats-table tr:hover { background: #f8f9fa; }
        .stats-table tr.current-ip-row { background: #d4edda !important; font-weight: 600; }
        .ip-cell { font-family: 'Monaco', 'Menlo', monospace; font-weight: 600; }
        .location-cell { min-width: 200px; color: #007bff; }
        .progress { background: #e9ecef; border-radius: 4px; height: 6px; overflow: hidden; margin: 5px 0; }
        .progress-bar { background: #28a745; height: 100%; transition: width 0.3s ease; }
        .progress-bar.warning { background: #ffc107; }
        .progress-bar.danger { background: #dc3545; }
        .btn { padding: 8px 16px; border: none; border-radius: 4px; cursor: pointer; font-size: 14px; transition: all 0.2s; }
        .btn-primary { background: #007bff; color: white; }
        .btn-primary:hover { background: #0056b3; }
        .btn-success { background: #28a745; color: white; }
        .btn-success:hover { background: #218838; }
        .btn-info { background: #17a2b8; color: white; }
        .btn-info:hover { background: #138496; }
        .update-info { color: #6c757d; font-size: 14px; }
        .loading { text-align: center; padding: 40px; color: #6c757d; }
        .error { background: #f8d7da; color: #721c24; padding: 15px; border-radius: 4px; margin: 10px 0; }
        .search-box { padding: 8px 12px; border: 1px solid #ced4da; border-radius: 4px; width: 250px; }
        .refresh-controls { display: flex; align-items: center; gap: 10px; }
        .interval-select { padding: 8px 12px; border: 1px solid #ced4da; border-radius: 4px; background: white; font-size: 14px; }
        .interval-select:focus { outline: none; border-color: #007bff; }
    </style>
    </head>
    <body>
        <div class="container">
            <div class="header">
                <h1>📊 IP 限制与使用统计</h1>
                <div class="current-ip">您的IP: <strong id="current-ip">加载中...</strong></div>
            </div>
            
            <div class="controls">
                <div class="refresh-controls">
                    <input type="text" id="search-box" class="search-box" placeholder="搜索IP地址..." onkeyup="filterTable()">
                    <select id="period-filter" class="interval-select" onchange="changePeriodFilter()">
                        <option value="all">全部周期</option>
                        <option value="hour" selected>小时统计</option>
                        <option value="day">天统计</option>
                    </select>
                    <button class="btn btn-primary" onclick="refreshData()">🔄 刷新数据</button>
                    <button class="btn btn-success" onclick="toggleAutoRefresh()" id="auto-refresh-btn">⏰ 开启自动刷新</button>
                    <select id="refresh-interval" class="interval-select" onchange="changeRefreshInterval()">
                        <option value="500">500ms</option>
                        <option value="1000" selected>1000ms</option>
                        <option value="2000">2000ms</option>
                        <option value="3000">3000ms</option>
                        <option value="5000">5000ms</option>
                    </select>
                </div>
                <div class="update-info">
                    最后更新: <span id="last-update">--</span>
                </div>
            </div>
            
            <div id="loading" class="loading">
                <div>📡 加载数据中...</div>
            </div>
            
            <div id="error-message" class="error" style="display: none;"></div>
            
            <div id="table-container" style="display: none;">
                <table class="stats-table">
                    <thead>
                        <tr>
                            <th>IP地址</th>
                            <th>周期</th>
                            <th>活跃时间</th>
                            <th>请求数</th>
                            <th>流量使用</th>
                            <th>耗时</th>
                            <th>封禁状态</th>
                            <th>归属地</th>
                        </tr>
                    </thead>
                    <tbody id="stats-body">
                    </tbody>
                </table>
            </div>
        </div>

        <script>
            let autoRefreshInterval = null;
            const ipLocationCache = {};
            let ipRequestQueue = [];
            let isProcessingQueue = false;
            let allStatsData = [];
            let currentSearchTerm = '';
            let currentPeriodFilter = 'hour'; // 默认筛选小时统计

            // 格式化字节大小
            function formatBytes(bytes) {
                if (!bytes) return '0 B';
                const k = 1024;
                const sizes = ['B', 'KB', 'MB', 'GB'];
                const i = Math.floor(Math.log(bytes) / Math.log(k));
                return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
            }

            // 格式化时间
            function formatDuration(seconds) {
                if (!seconds) return '0秒';
                if (seconds < 60) return seconds + '秒';
                if (seconds < 3600) return Math.floor(seconds / 60) + '分钟';
                return Math.floor(seconds / 3600) + '小时';
            }

            // 获取进度条颜色类
            function getProgressClass(percentage) {
                if (percentage < 50) return '';
                if (percentage < 80) return 'warning';
                return 'danger';
            }

            // 创建表格行
            function createTableRow(stat) {
                const countPercentage = Math.min((stat.count / stat.count_limit) * 100, 100);
                const bytesPercentage = Math.min((stat.bytes / stat.bytes_limit) * 100, 100);
                const costsPercentage = Math.min((stat.costs_us / stat.costs_limit_us) * 100, 100);
                
                const row = document.createElement('tr');
                if (stat.is_current) {
                    row.className = 'current-ip-row';
                }
                
                row.innerHTML = `
                    <td class="ip-cell">${stat.ip}</td>
                    <td>${stat.period === 'hour' ? '小时' : '天'}</td>
                    <td>${formatDuration(stat.age)}</td>
                    <td>
                        ${stat.count}/${stat.count_limit}
                        <div class="progress">
                            <div class="progress-bar ${getProgressClass(countPercentage)}" style="width: ${countPercentage}%"></div>
                        </div>
                    </td>
                    <td>
                        ${stat.bytes_human}/${stat.bytes_limit_human}
                        <div class="progress">
                            <div class="progress-bar ${getProgressClass(bytesPercentage)}" style="width: ${bytesPercentage}%"></div>
                        </div>
                    </td>
                    <td>
                        ${stat.costs_human}/${stat.costs_limit_human}
                        <div class="progress">
                            <div class="progress-bar ${getProgressClass(costsPercentage)}" style="width: ${costsPercentage}%"></div>
                        </div>
                    </td>
                    <td>${stat.forbidden === 'true' ? '🔴 是' : '🟢 否'}</td>
                    <td class="location-cell" data-ip="${stat.ip}">查询中...</td>
                `;
                
                return row;
            }

            // 平滑更新表格 - 只更新数字，保持DOM结构稳定
            function smoothUpdateTable(newStats) {
                // 更新全局数据
                allStatsData = newStats;
                const tbody = document.getElementById('stats-body');
                const existingRows = Array.from(tbody.querySelectorAll('tr'));
                const newRowsMap = new Map();
                
                // 创建新行的映射
                newStats.forEach(stat => {
                    const rowId = `${stat.ip}-${stat.period}`;
                    newRowsMap.set(rowId, stat);
                });
                
                // 创建现有行的映射
                const existingRowsMap = new Map();
                existingRows.forEach(row => {
                    const ipCell = row.querySelector('.ip-cell');
                    const periodCell = row.cells[1];
                    if (ipCell && periodCell) {
                        const rowId = `${ipCell.textContent}-${periodCell.textContent}`;
                        existingRowsMap.set(rowId, row);
                    }
                });
                
                // 首先更新所有现有行
                existingRowsMap.forEach((row, rowId) => {
                    const newStat = newRowsMap.get(rowId);
                    if (newStat) {
                        // 更新现有行数据
                        updateTableRowNumbers(row, newStat);
                        newRowsMap.delete(rowId);
                    } else {
                        // 删除不存在的行
                        row.remove();
                    }
                });
                
                // 然后添加新行（只添加真正新的行）
                newRowsMap.forEach((stat, rowId) => {
                    if (!existingRowsMap.has(rowId)) {
                        const newRow = createTableRow(stat);
                        tbody.appendChild(newRow);
                    }
                });
                
                updateIPLocations();
            }

            // 只更新表格行的数字内容，保持DOM结构稳定
            function updateTableRowNumbers(row, stat) {
                const countPercentage = Math.min((stat.count / stat.count_limit) * 100, 100);
                const bytesPercentage = Math.min((stat.bytes / stat.bytes_limit) * 100, 100);
                const costsPercentage = Math.min((stat.costs_us / stat.costs_limit_us) * 100, 100);
                
                // 只更新文本内容，不重新创建DOM元素
                const cells = row.cells;
                
                // 活跃时间（第3列）
                if (cells[2].textContent !== formatDuration(stat.age)) {
                    cells[2].textContent = formatDuration(stat.age);
                }
                
                // 请求数（第4列）- 只更新文本部分，保持进度条DOM
                const countText = cells[3].firstChild;
                if (countText && countText.textContent !== `${stat.count}/${stat.count_limit}`) {
                    countText.textContent = `${stat.count}/${stat.count_limit}`;
                    const progressBar = cells[3].querySelector('.progress-bar');
                    if (progressBar) {
                        progressBar.style.width = `${countPercentage}%`;
                        progressBar.className = `progress-bar ${getProgressClass(countPercentage)}`;
                    }
                }
                
                // 流量使用（第5列）- 只更新文本部分，保持进度条DOM
                const bytesText = cells[4].firstChild;
                if (bytesText && bytesText.textContent !== `${stat.bytes_human}/${stat.bytes_limit_human}`) {
                    bytesText.textContent = `${stat.bytes_human}/${stat.bytes_limit_human}`;
                    const progressBar = cells[4].querySelector('.progress-bar');
                    if (progressBar) {
                        progressBar.style.width = `${bytesPercentage}%`;
                        progressBar.className = `progress-bar ${getProgressClass(bytesPercentage)}`;
                    }
                }
                
                // 耗时（第6列）- 只更新文本部分，保持进度条DOM
                const costsText = cells[5].firstChild;
                if (costsText && costsText.textContent !== `${stat.costs_human}/${stat.costs_limit_human}`) {
                    costsText.textContent = `${stat.costs_human}/${stat.costs_limit_human}`;
                    const progressBar = cells[5].querySelector('.progress-bar');
                    if (progressBar) {
                        progressBar.style.width = `${costsPercentage}%`;
                        progressBar.className = `progress-bar ${getProgressClass(costsPercentage)}`;
                    }
                }
                
                // 封禁状态（第7列）
                const newForbiddenText = stat.forbidden === 'true' ? '🔴 是' : '🟢 否';
                if (cells[6].textContent !== newForbiddenText) {
                    cells[6].textContent = newForbiddenText;
                }
                
                // 更新当前IP高亮
                if (stat.is_current) {
                    row.className = 'current-ip-row';
                } else {
                    row.className = '';
                }
            }

            // 改变周期筛选
            function changePeriodFilter() {
                const periodSelect = document.getElementById('period-filter');
                currentPeriodFilter = periodSelect.value;
                applyFilters();
            }

            // 应用所有筛选条件
            function applyFilters() {
                let filteredStats = allStatsData;
                
                // 应用周期筛选
                if (currentPeriodFilter !== 'all') {
                    filteredStats = filteredStats.filter(stat => 
                        stat.period === currentPeriodFilter
                    );
                }
                
                // 应用搜索筛选
                if (currentSearchTerm) {
                    filteredStats = filteredStats.filter(stat => 
                        stat.ip.toLowerCase().includes(currentSearchTerm)
                    );
                }
                
                const tbody = document.getElementById('stats-body');
                tbody.innerHTML = '';
                
                filteredStats.forEach(stat => {
                    const row = createTableRow(stat);
                    tbody.appendChild(row);
                });
                
                updateIPLocations();
            }

            // 过滤表格
            function filterTable() {
                currentSearchTerm = document.getElementById('search-box').value.toLowerCase();
                applyFilters();
            }

            // 更新IP归属地
            function updateIPLocations() {
                document.querySelectorAll('.location-cell').forEach(cell => {
                    const ip = cell.dataset.ip;
                    if (!ip) return;
                    
                    if (ipLocationCache[ip]) {
                        cell.textContent = ipLocationCache[ip];
                    } else {
                        cell.textContent = '查询中...';
                        if (!ipRequestQueue.includes(ip)) {
                            ipRequestQueue.push(ip);
                        }
                    }
                });

                if (!isProcessingQueue && ipRequestQueue.length > 0) {
                    processIpQueue();
                }
            }

            // 处理IP队列
            function processIpQueue() {
                if (ipRequestQueue.length === 0) {
                    isProcessingQueue = false;
                    return;
                }
                isProcessingQueue = true;
                
                const ip = ipRequestQueue.shift();
                
                fetch(`https://api.vore.top/api/IPdata?ip=${ip}`)
                    .then(response => response.json())
                    .then(data => {
                        let location = '查询失败';
                        if (data && data.ipdata && data.ipdata.info1) {
                            location = `${data.ipdata.info1} ${data.ipdata.info2 || ''} ${data.ipdata.info3 || ''}`.trim();
                        }
                        ipLocationCache[ip] = location;
                        document.querySelectorAll(`.location-cell[data-ip="${ip}"]`).forEach(c => {
                            c.textContent = location;
                        });
                    })
                    .catch(error => {
                        console.error('Error fetching IP location for', ip, error);
                        ipLocationCache[ip] = '查询出错';
                        document.querySelectorAll(`.location-cell[data-ip="${ip}"]`).forEach(c => {
                            c.textContent = '查询出错';
                        });
                    })
                    .finally(() => {
                        setTimeout(processIpQueue, 1000);
                    });
            }

            // 获取数据
            async function fetchData() {
                try {
                    const response = await fetch('/dk8s.stats?type=json&t=' + Date.now());
                    if (!response.ok) throw new Error('网络请求失败');
                    
                    const data = await response.json();
                    
                    document.getElementById('current-ip').textContent = data.current_ip;
                    document.getElementById('last-update').textContent = data.update_time;
                    
                    // 隐藏加载状态（如果存在）
                    const loadingEl = document.getElementById('loading');
                    if (loadingEl && loadingEl.style.display !== 'none') {
                        loadingEl.style.display = 'none';
                        document.getElementById('table-container').style.display = 'block';
                    }
                    
                    // 更新全局数据
                    allStatsData = data.stats;
                    
                    // 应用所有筛选条件
                    applyFilters();
                    
                } catch (error) {
                    console.error('数据加载失败:', error);
                    // 只在首次加载时显示错误
                    const loadingEl = document.getElementById('loading');
                    if (loadingEl && loadingEl.style.display !== 'none') {
                        document.getElementById('loading').style.display = 'none';
                        document.getElementById('error-message').style.display = 'block';
                        document.getElementById('error-message').textContent = '❌ 加载数据失败: ' + error.message;
                    }
                }
            }

            // 刷新数据
            function refreshData() {
                // 显示刷新状态
                const lastUpdate = document.getElementById('last-update');
                const originalText = lastUpdate.textContent;
                lastUpdate.textContent = '刷新中...';
                lastUpdate.style.color = '#007bff';
                
                fetchData().finally(() => {
                    setTimeout(() => {
                        lastUpdate.style.color = '#6c757d';
                    }, 1000);
                });
            }

            // 切换自动刷新
            function toggleAutoRefresh() {
                const btn = document.getElementById('auto-refresh-btn');
                if (autoRefreshInterval) {
                    clearInterval(autoRefreshInterval);
                    autoRefreshInterval = null;
                    btn.textContent = '⏰ 开启自动刷新';
                    btn.classList.remove('btn-success');
                    btn.classList.add('btn-primary');
                } else {
                    const interval = parseInt(document.getElementById('refresh-interval').value);
                    autoRefreshInterval = setInterval(fetchData, interval);
                    btn.textContent = '⏹️ 停止自动刷新';
                    btn.classList.remove('btn-primary');
                    btn.classList.add('btn-success');
                }
            }

            // 改变刷新间隔
            function changeRefreshInterval() {
                const interval = parseInt(document.getElementById('refresh-interval').value);
                
                // 如果自动刷新正在运行，重新设置定时器
                if (autoRefreshInterval) {
                    clearInterval(autoRefreshInterval);
                    autoRefreshInterval = setInterval(fetchData, interval);
                    
                    // 显示间隔更改提示
                    const lastUpdate = document.getElementById('last-update');
                    const originalText = lastUpdate.textContent;
                    lastUpdate.textContent = `刷新间隔: ${interval}ms`;
                    lastUpdate.style.color = '#17a2b8';
                    
                    setTimeout(() => {
                        lastUpdate.textContent = originalText;
                        lastUpdate.style.color = '#6c757d';
                    }, 1500);
                }
            }

            // 初始化
            document.addEventListener('DOMContentLoaded', function() {
                fetchData();
            });
        </script>
    </body>
    </html>
    ]])
end
