-- 查看JSON数据接口
ngx.header.content_type = "text/html; charset=utf-8"

local cjson = require "cjson"
local persistence = require "persistence"

local function read_json_file()
    local file = io.open(persistence.storage_file, "r")
    if not file then
        return nil, "File not found"
    end
    
    local content = file:read("*a")
    file:close()
    
    if not content or content == "" then
        return nil, "File is empty"
    end
    
    local ok, data = pcall(cjson.decode, content)
    if not ok then
        return nil, "Invalid JSON format"
    end
    
    return data, nil
end

local function format_json_for_display(data)
    local html = [[
    <html>
    <head>
        <title>流量统计数据查看</title>
        <style>
            body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; margin: 20px; background: #f5f5f5; }
            .container { max-width: 1400px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
            h1 { color: #333; border-bottom: 2px solid #007bff; padding-bottom: 10px; }
            .stats { margin: 20px 0; padding: 15px; background: #f8f9fa; border-radius: 5px; }
            .json-view { background: #f8f9fa; border: 1px solid #ddd; border-radius: 5px; padding: 15px; margin: 10px 0; max-height: 600px; overflow-y: auto; }
            .key { color: #d73a49; font-weight: bold; }
            .string { color: #032f62; }
            .number { color: #005cc5; }
            .boolean { color: #e36209; }
            .null { color: #6a737d; }
            .actions { margin: 20px 0; }
            .btn { display: inline-block; padding: 8px 16px; margin: 5px; background: #007bff; color: white; text-decoration: none; border-radius: 4px; border: none; cursor: pointer; }
            .btn:hover { background: #0056b3; }
            .btn-danger { background: #dc3545; }
            .btn-danger:hover { background: #c82333; }
            .btn-success { background: #28a745; }
            .btn-success:hover { background: #218838; }
            .btn-info { background: #17a2b8; }
            .btn-info:hover { background: #138496; }
            .info-box { background: #d1ecf1; border: 1px solid #bee5eb; border-radius: 5px; padding: 15px; margin: 15px 0; }
            .error-box { background: #f8d7da; border: 1px solid #f5c6cb; border-radius: 5px; padding: 15px; margin: 15px 0; color: #721c24; }
            table { width: 100%; border-collapse: collapse; margin: 15px 0; }
            th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
            th { background: #f2f2f2; }
            tr:nth-child(even) { background: #f9f9f9; }
            .ip-table { margin-top: 20px; }
            .data-format { background: #e7f3ff; padding: 10px; border-radius: 5px; margin: 10px 0; }
        </style>
        <script>
            function refreshData() {
                location.reload();
            }
            
            function formatJSON() {
                const jsonText = document.getElementById('json-content').textContent;
                try {
                    const formatted = JSON.stringify(JSON.parse(jsonText), null, 2);
                    document.getElementById('json-content').textContent = formatted;
                } catch(e) {
                    alert('JSON格式错误: ' + e.message);
                }
            }
            
            function toggleAutoRefresh() {
                const btn = document.getElementById('auto-refresh-btn');
                if (btn.textContent.includes('开启')) {
                    btn.textContent = '关闭自动刷新 (5秒)';
                    btn.classList.add('btn-success');
                    autoRefreshInterval = setInterval(refreshData, 5000);
                } else {
                    btn.textContent = '开启自动刷新';
                    btn.classList.remove('btn-success');
                    clearInterval(autoRefreshInterval);
                }
            }
        </script>
    </head>
    <body>
        <div class="container">
            <h1>📊 流量统计数据查看</h1>
    ]]
    
    local data, err = read_json_file()
    
    if data then
        -- 检查数据格式
        local is_structured = data.statistics ~= nil
        local total_ips = 0
        local hour_count = 0
        local day_count = 0
        local forbidden_count = 0
        local total_keys = 0
        
        if is_structured then
            -- 结构化数据统计
            for ip, ip_data in pairs(data.statistics) do
                total_ips = total_ips + 1
                if ip_data.hour and next(ip_data.hour) then
                    hour_count = hour_count + 1
                    if ip_data.hour.forbidden == true then
                        forbidden_count = forbidden_count + 1
                    end
                end
                if ip_data.day and next(ip_data.day) then
                    day_count = day_count + 1
                    if ip_data.day.forbidden == true then
                        forbidden_count = forbidden_count + 1
                    end
                end
            end
            total_keys = data.metadata and data.metadata.total_keys or 0
            
            html = html .. [[
                <div class="data-format">
                    <strong>📋 数据格式:</strong> 结构化数据 (版本 ]] .. (data.metadata and data.metadata.version or "未知") .. [[)
                </div>
                <div class="info-box">
                    <strong>📈 数据统计:</strong><br>
                    - 保存时间: ]] .. (data.metadata and data.metadata.save_time or "未知") .. [[<br>
                    - 总IP地址数量: ]] .. total_ips .. [[<br>
                    - 小时统计IP数: ]] .. hour_count .. [[<br>
                    - 天统计IP数: ]] .. day_count .. [[<br>
                    - 被封禁IP数量: ]] .. forbidden_count .. [[<br>
                    - 原始键值对数量: ]] .. total_keys .. [[
                </div>
                
                <div class="ip-table">
                    <h3>📋 IP统计详情</h3>
                    <table>
                        <thead>
                            <tr>
                                <th>IP地址</th>
                                <th>周期</th>
                                <th>最后活跃</th>
                                <th>请求数</th>
                                <th>流量(bytes)</th>
                                <th>耗时(μs)</th>
                                <th>封禁状态</th>
                            </tr>
                        </thead>
                        <tbody>
            ]]
            
            -- 生成IP统计表格
            for ip, ip_data in pairs(data.statistics) do
                for period, period_data in pairs(ip_data) do
                    if type(period_data) == "table" and next(period_data) then
                        local last_time = period_data.last_time or 0
                        local count = period_data.count or 0
                        local bytes = period_data.bytes or 0
                        local costs = period_data.costs or 0
                        local forbidden = period_data.forbidden or false
                        
                        local last_time_str = os.date("%Y-%m-%d %H:%M:%S", last_time)
                        local forbidden_str = forbidden and "🔴 是" or "🟢 否"
                        
                        html = html .. string.format([[
                            <tr>
                                <td><strong>%s</strong></td>
                                <td>%s</td>
                                <td>%s</td>
                                <td>%d</td>
                                <td>%d</td>
                                <td>%.2f</td>
                                <td>%s</td>
                            </tr>
                        ]], ip, period == "hour" and "小时" or "天", last_time_str, count, bytes, costs, forbidden_str)
                    end
                end
            end
            
            html = html .. [[
                        </tbody>
                    </table>
                </div>
            ]]
        else
            -- 旧的扁平化数据统计
            for key, value in pairs(data) do
                total_keys = total_keys + 1
                if key:find(":hour:") then
                    hour_count = hour_count + 1
                elseif key:find(":day:") then
                    day_count = day_count + 1
                end
                if key:find("forbidden:") and value == true then
                    forbidden_count = forbidden_count + 1
                end
            end
            
            html = html .. [[
                <div class="data-format">
                    <strong>📋 数据格式:</strong> 扁平化数据 (旧格式)
                </div>
                <div class="info-box">
                    <strong>📈 数据统计:</strong><br>
                    - 总键值对数量: ]] .. total_keys .. [[<br>
                    - 小时统计条目: ]] .. hour_count .. [[<br>
                    - 天统计条目: ]] .. day_count .. [[<br>
                    - 被封禁IP数量: ]] .. forbidden_count .. [[
                </div>
            ]]
        end
        
        html = html .. [[
            <div class="actions">
                <button class="btn" onclick="refreshData()">🔄 刷新数据</button>
                <button class="btn" onclick="formatJSON()">📝 格式化JSON</button>
                <button class="btn" id="auto-refresh-btn" onclick="toggleAutoRefresh()">开启自动刷新</button>
                <a href="/dk8s.save?action=save" class="btn btn-success" target="_blank">💾 手动保存</a>
                <a href="/dk8s.stats" class="btn" target="_blank">📋 查看统计页面</a>
                <button class="btn btn-info" onclick="toggleRawJSON()">切换原始JSON视图</button>
            </div>
            
            <div class="json-view">
                <pre id="json-content"><code>]] .. cjson.encode(data) .. [[</code></pre>
            </div>
        ]]
    else
        html = html .. [[
            <div class="error-box">
                <strong>❌ 错误:</strong> ]] .. (err or "未知错误") .. [[
            </div>
            
            <div class="actions">
                <button class="btn" onclick="refreshData()">🔄 刷新数据</button>
                <a href="/dk8s.save?action=save" class="btn btn-success" target="_blank">💾 手动保存</a>
                <a href="/dk8s.stats" class="btn" target="_blank">📋 查看统计页面</a>
            </div>
        ]]
    end
    
    html = html .. [[
        </div>
        <script>
            function toggleRawJSON() {
                const jsonView = document.querySelector('.json-view');
                const ipTable = document.querySelector('.ip-table');
                if (jsonView.style.display === 'none') {
                    jsonView.style.display = 'block';
                    if (ipTable) ipTable.style.display = 'block';
                } else {
                    jsonView.style.display = 'none';
                    if (ipTable) ipTable.style.display = 'none';
                }
            }
        </script>
    </body>
    </html>
    ]]
    
    return html
end

ngx.say(format_json_for_display())
