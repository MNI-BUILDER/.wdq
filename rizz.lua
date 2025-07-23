local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")

-- SMART UPDATE CONFIGURATION
local CONFIG = {
    API_URL = "https://bloxfritushit.vercel.app/api/stocks/bloxfruits",
    AUTH_HEADER = "GAMERSBERG",
    UPDATE_INTERVAL = 8,
    PING_INTERVAL = 30, -- Send keepalive ping every 30 seconds
    RETRY_DELAY = 2,
    MAX_RETRIES = 10,
    SESSION_ID = HttpService:GenerateGUID(false),
    
    -- ANTI-AFK SETTINGS
    ANTI_AFK_INTERVAL = 45,
    MOVEMENT_DISTANCE = 15,
    TOOL_USE_CHANCE = 0.9,
    EMERGENCY_AFK_TIME = 900
}

-- SMART STATE MANAGEMENT
local State = {
    isRunning = false,
    lastUpdate = 0,
    lastPing = 0,
    retryCount = 0,
    sessionActive = true,
    lastStockData = nil,
    lastStockHash = "",
    totalUpdates = 0,
    totalPings = 0,
    lastAntiAfk = 0,
    lastActivity = os.time(),
    connections = {},
    antiAfkRunning = false,
    dataChangeDetected = false
}

-- SMART LOGGING
local function smartLog(level, message, forceNotify)
    local timestamp = os.date("%H:%M:%S")
    local logMessage = string.format("[%s][SMART][%s] %s", timestamp, level, tostring(message))
    print(logMessage)
    
    if forceNotify or level == "ERROR" or level == "CRITICAL" or level == "SUCCESS" then
        pcall(function()
            StarterGui:SetCore("SendNotification", {
                Title = "[SMART] " .. level,
                Text = tostring(message),
                Duration = level == "ERROR" and 10 or 5
            })
        end)
    end
end

-- DATA CHANGE DETECTION SYSTEM
local function generateDataHash(stockData)
    if not stockData or not stockData.normal or not stockData.mirage then
        return ""
    end
    
    local hashData = {}
    
    -- Process normal stock
    if stockData.normal and type(stockData.normal) == "table" then
        for _, fruit in pairs(stockData.normal) do
            if fruit and fruit.OnSale and fruit.Name and fruit.Price then
                table.insert(hashData, {
                    type = "normal",
                    name = tostring(fruit.Name),
                    price = tonumber(fruit.Price),
                    onSale = fruit.OnSale
                })
            end
        end
    end
    
    -- Process mirage stock
    if stockData.mirage and type(stockData.mirage) == "table" then
        for _, fruit in pairs(stockData.mirage) do
            if fruit and fruit.OnSale and fruit.Name and fruit.Price then
                table.insert(hashData, {
                    type = "mirage",
                    name = tostring(fruit.Name),
                    price = tonumber(fruit.Price),
                    onSale = fruit.OnSale
                })
            end
        end
    end
    
    -- Sort for consistent hashing
    table.sort(hashData, function(a, b)
        if a.type ~= b.type then
            return a.type < b.type
        end
        if a.name ~= b.name then
            return a.name < b.name
        end
        return a.price < b.price
    end)
    
    return HttpService:JSONEncode(hashData)
end

local function detectDataChanges(newStockData)
    local newHash = generateDataHash(newStockData)
    
    if newHash == "" then
        smartLog("WARN", "Invalid stock data for hash generation")
        return false
    end
    
    if State.lastStockHash == "" then
        -- First time data
        State.lastStockHash = newHash
        State.lastStockData = newStockData
        smartLog("INFO", "First stock data detected")
        return true
    end
    
    if newHash ~= State.lastStockHash then
        smartLog("SUCCESS", "NEW DATA DETECTED - Changes found!", true)
        State.lastStockHash = newHash
        State.lastStockData = newStockData
        State.dataChangeDetected = true
        return true
    end
    
    smartLog("DEBUG", "No data changes detected")
    return false
end

-- API KEEPALIVE PING SYSTEM
local function sendKeepalivePing()
    local success = pcall(function()
        local request = http_request or request or (syn and syn.request)
        if not request then return false end
        
        local pingPayload = {
            action = "KEEPALIVE",
            sessionId = CONFIG.SESSION_ID,
            timestamp = os.time(),
            playerName = tostring(Players.LocalPlayer.Name),
            serverId = tostring(game.JobId or "unknown"),
            status = "ACTIVE"
        }
        
        local response = request({
            Url = CONFIG.API_URL,
            Method = "PUT",
            Headers = {
                ["Authorization"] = CONFIG.AUTH_HEADER,
                ["Content-Type"] = "application/json",
                ["X-Session-ID"] = CONFIG.SESSION_ID,
                ["X-Action"] = "KEEPALIVE",
                ["X-Ping"] = "true"
            },
            Body = HttpService:JSONEncode(pingPayload)
        })
        
        if response and response.StatusCode and response.StatusCode < 300 then
            State.totalPings = State.totalPings + 1
            State.lastPing = os.time()
            smartLog("DEBUG", "Keepalive ping sent successfully")
            return true
        else
            smartLog("WARN", "Keepalive ping failed: " .. tostring(response and response.StatusCode or "No response"))
            return false
        end
    end)
    
    return success
end

-- COMPLETE DATA REPLACEMENT SYSTEM
local function replaceDataCompletely(stockData)
    local success = pcall(function()
        smartLog("INFO", "REPLACING DATA COMPLETELY...")
        
        local request = http_request or request or (syn and syn.request)
        if not request then
            smartLog("CRITICAL", "No HTTP request function available")
            return false
        end
        
        -- STEP 1: DELETE ALL OLD DATA
        local deleteResponse = request({
            Url = CONFIG.API_URL,
            Method = "DELETE",
            Headers = {
                ["Authorization"] = CONFIG.AUTH_HEADER,
                ["Content-Type"] = "application/json",
                ["X-Session-ID"] = CONFIG.SESSION_ID,
                ["X-Action"] = "DELETE_ALL"
            },
            Body = HttpService:JSONEncode({
                action = "DELETE_ALL_SESSION_DATA",
                sessionId = CONFIG.SESSION_ID,
                force = true
            })
        })
        
        smartLog("DEBUG", "Delete response: " .. tostring(deleteResponse and deleteResponse.StatusCode or "No response"))
        
        -- STEP 2: WAIT FOR DELETION TO COMPLETE
        task.wait(1.5)
        
        -- STEP 3: FORMAT NEW DATA
        local function formatFruits(fruits)
            local formatted = {}
            if fruits and type(fruits) == "table" then
                for _, fruit in pairs(fruits) do
                    if fruit and fruit.OnSale and fruit.Name and fruit.Price then
                        table.insert(formatted, {
                            name = tostring(fruit.Name),
                            price = tonumber(fruit.Price) or 0,
                            onSale = true,
                            timestamp = os.time()
                        })
                    end
                end
            end
            return formatted
        end
        
        local normalStock = formatFruits(stockData.normal)
        local mirageStock = formatFruits(stockData.mirage)
        
        -- STEP 4: SEND COMPLETELY NEW DATA
        local newDataPayload = {
            sessionId = CONFIG.SESSION_ID,
            timestamp = os.time(),
            playerName = tostring(Players.LocalPlayer.Name),
            serverId = tostring(game.JobId or "unknown"),
            normalStock = normalStock,
            mirageStock = mirageStock,
            totalFruits = #normalStock + #mirageStock,
            dataVersion = os.time(),
            replaceMode = true,
            freshData = true
        }
        
        local postResponse = request({
            Url = CONFIG.API_URL,
            Method = "POST",
            Headers = {
                ["Authorization"] = CONFIG.AUTH_HEADER,
                ["Content-Type"] = "application/json",
                ["X-Session-ID"] = CONFIG.SESSION_ID,
                ["X-Data-Mode"] = "REPLACE_ALL",
                ["X-Fresh-Data"] = "true",
                ["X-Timestamp"] = tostring(os.time())
            },
            Body = HttpService:JSONEncode(newDataPayload)
        })
        
        if postResponse and postResponse.StatusCode and postResponse.StatusCode >= 200 and postResponse.StatusCode < 300 then
            State.totalUpdates = State.totalUpdates + 1
            State.lastUpdate = os.time()
            smartLog("SUCCESS", string.format("DATA COMPLETELY REPLACED - Normal: %d, Mirage: %d", 
                #normalStock, #mirageStock), true)
            return true
        else
            smartLog("ERROR", "Failed to send new data: " .. tostring(postResponse and postResponse.StatusCode or "No response"))
            return false
        end
    end)
    
    if success then
        State.retryCount = 0
        return true
    else
        State.retryCount = State.retryCount + 1
        smartLog("ERROR", "Data replacement failed, retry: " .. State.retryCount)
        return false
    end
end

-- SMART ANTI-AFK SYSTEM
local function executeSmartAntiAfk()
    if State.antiAfkRunning then return end
    
    State.antiAfkRunning = true
    
    spawn(function()
        pcall(function()
            smartLog("INFO", "Executing smart anti-AFK...")
            
            local character = Players.LocalPlayer.Character
            if not character then
                State.antiAfkRunning = false
                return
            end
            
            local humanoid = character:FindFirstChild("Humanoid")
            local rootPart = character:FindFirstChild("HumanoidRootPart")
            if not humanoid or not rootPart then
                State.antiAfkRunning = false
                return
            end
            
            -- Smart movement pattern
            local patterns = {
                function() -- Random walk
                    for i = 1, 4 do
                        local angle = math.random() * math.pi * 2
                        local distance = math.random(8, CONFIG.MOVEMENT_DISTANCE)
                        local direction = Vector3.new(
                            math.cos(angle) * distance,
                            0,
                            math.sin(angle) * distance
                        )
                        humanoid:MoveTo(rootPart.Position + direction)
                        task.wait(2)
                    end
                end,
                
                function() -- Circle walk
                    local center = rootPart.Position
                    for i = 1, 8 do
                        local angle = (i / 8) * math.pi * 2
                        local pos = center + Vector3.new(
                            math.cos(angle) * 10,
                            0,
                            math.sin(angle) * 10
                        )
                        humanoid:MoveTo(pos)
                        task.wait(1)
                    end
                end,
                
                function() -- Jump and move
                    for i = 1, 6 do
                        humanoid.Jump = true
                        task.wait(0.5)
                        local angle = math.random() * math.pi * 2
                        local distance = math.random(5, 12)
                        local direction = Vector3.new(
                            math.cos(angle) * distance,
                            0,
                            math.sin(angle) * distance
                        )
                        humanoid:MoveTo(rootPart.Position + direction)
                        task.wait(1.5)
                    end
                end
            }
            
            -- Execute random pattern
            local selectedPattern = patterns[math.random(1, #patterns)]
            selectedPattern()
            
            -- Tool usage
            if math.random() <= CONFIG.TOOL_USE_CHANCE then
                task.wait(1)
                local backpack = Players.LocalPlayer:FindFirstChild("Backpack")
                if backpack then
                    local tools = {}
                    for _, item in pairs(backpack:GetChildren()) do
                        if item:IsA("Tool") then
                            table.insert(tools, item)
                        end
                    end
                    
                    if #tools > 0 then
                        local tool = tools[math.random(1, #tools)]
                        humanoid:EquipTool(tool)
                        task.wait(1)
                        
                        if tool.Parent == character then
                            for j = 1, math.random(3, 8) do
                                tool:Activate()
                                task.wait(math.random(0.3, 0.8))
                            end
                            task.wait(2)
                            if math.random() > 0.3 then
                                humanoid:UnequipTools()
                            end
                            smartLog("DEBUG", "Used tool: " .. tool.Name)
                        end
                    end
                end
            end
            
            State.lastActivity = os.time()
            State.lastAntiAfk = os.time()
            smartLog("SUCCESS", "Smart anti-AFK completed")
        end)
        
        task.wait(3)
        State.antiAfkRunning = false
    end)
end

-- GET STOCK DATA
local function getStockData()
    local success, result = pcall(function()
        local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
        if not remotes then error("No remotes found") end
        
        local CommF = remotes:WaitForChild("CommF_", 10)
        if not CommF then error("No CommF_ found") end
        
        local normalStock = CommF:InvokeServer("GetFruits", false)
        local mirageStock = CommF:InvokeServer("GetFruits", true)
        
        return {
            normal = normalStock or {},
            mirage = mirageStock or {}
        }
    end)
    
    if success and result then
        return result
    else
        smartLog("ERROR", "Failed to get stock data: " .. tostring(result))
        return nil
    end
end

-- SETUP CONNECTIONS
local function setupConnections()
    pcall(function()
        -- Anti-idle
        local VirtualUser = game:GetService("VirtualUser")
        Players.LocalPlayer.Idled:Connect(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
            smartLog("INFO", "Idle prevented")
        end)
        
        -- Teleport handling
        Players.LocalPlayer.OnTeleport:Connect(function(state)
            if state == Enum.TeleportState.Failed then
                smartLog("WARN", "Teleport failed - rejoining")
                task.wait(3)
                TeleportService:Teleport(game.PlaceId, Players.LocalPlayer)
            end
        end)
        
        -- Connection monitoring
        local heartbeat = RunService.Heartbeat:Connect(function()
            if not game:IsLoaded() or not Players.LocalPlayer.Parent then
                smartLog("CRITICAL", "Connection lost")
            end
        end)
        table.insert(State.connections, heartbeat)
        
        smartLog("SUCCESS", "Connections established")
    end)
end

-- MAIN SMART MONITORING LOOP
local function startSmartMonitoring()
    State.isRunning = true
    State.lastUpdate = os.time()
    State.lastPing = os.time()
    
    smartLog("SUCCESS", "SMART MONITOR STARTED - Only updates on NEW data!", true)
    smartLog("INFO", "Player: " .. Players.LocalPlayer.Name)
    smartLog("INFO", "Session: " .. CONFIG.SESSION_ID:sub(1, 8) .. "...")
    
    local cycleCount = 0
    local pingCount = 0
    local antiAfkCount = 0
    
    while State.isRunning do
        cycleCount = cycleCount + 1
        pingCount = pingCount + 1
        antiAfkCount = antiAfkCount + 1
        
        -- KEEPALIVE PING SYSTEM (Every 30 seconds)
        if pingCount >= (CONFIG.PING_INTERVAL / CONFIG.UPDATE_INTERVAL) then
            sendKeepalivePing()
            pingCount = 0
        end
        
        -- ANTI-AFK SYSTEM (Every 45 seconds)
        if antiAfkCount >= (CONFIG.ANTI_AFK_INTERVAL / CONFIG.UPDATE_INTERVAL) then
            executeSmartAntiAfk()
            antiAfkCount = 0
        end
        
        -- STOCK DATA MONITORING (Every cycle)
        local stockData = getStockData()
        if stockData then
            -- ONLY UPDATE IF NEW DATA DETECTED
            if detectDataChanges(stockData) then
                smartLog("INFO", "NEW DATA DETECTED - Updating API...", true)
                if replaceDataCompletely(stockData) then
                    smartLog("SUCCESS", "API updated with fresh data!", true)
                else
                    smartLog("ERROR", "Failed to update API with new data")
                end
            end
        else
            smartLog("WARN", "Could not retrieve stock data this cycle")
        end
        
        -- STATUS REPORTING (Every minute)
        if cycleCount >= (60 / CONFIG.UPDATE_INTERVAL) then
            local timeSinceActivity = os.time() - State.lastActivity
            local timeSincePing = os.time() - State.lastPing
            smartLog("INFO", string.format("Status: %d updates | %d pings | Activity: %ds ago | Last ping: %ds ago", 
                State.totalUpdates, State.totalPings, timeSinceActivity, timeSincePing))
            cycleCount = 0
        end
        
        task.wait(CONFIG.UPDATE_INTERVAL)
    end
    
    smartLog("INFO", "Smart monitoring stopped")
end

-- INITIALIZE SMART MONITOR
local function initialize()
    smartLog("INFO", "Initializing SMART monitor...")
    
    if not ReplicatedStorage:FindFirstChild("Remotes") then
        smartLog("CRITICAL", "Not in Blox Fruits game!", true)
        return
    end
    
    setupConnections()
    
    spawn(function()
        startSmartMonitoring()
    end)
    
    smartLog("SUCCESS", "SMART MONITOR INITIALIZED", true)
end

-- CONTROL INTERFACE
_G.SmartMonitor = {
    stop = function()
        State.isRunning = false
        smartLog("INFO", "Monitor stopped")
    end,
    
    restart = function()
        State.isRunning = false
        task.wait(2)
        initialize()
    end,
    
    forceUpdate = function()
        State.lastStockHash = ""
        smartLog("INFO", "Forced update - will detect changes on next cycle")
    end,
    
    sendPing = function()
        sendKeepalivePing()
        smartLog("INFO", "Manual ping sent")
    end,
    
    forceAntiAfk = function()
        executeSmartAntiAfk()
    end,
    
    status = function()
        local timeSinceActivity = os.time() - State.lastActivity
        local timeSincePing = os.time() - State.lastPing
        local timeSinceUpdate = os.time() - State.lastUpdate
        
        print("=== SMART MONITOR STATUS ===")
        print("Running:", State.isRunning)
        print("Total Updates:", State.totalUpdates)
        print("Total Pings:", State.totalPings)
        print("Time Since Activity:", timeSinceActivity, "seconds")
        print("Time Since Ping:", timeSincePing, "seconds")
        print("Time Since Update:", timeSinceUpdate, "seconds")
        print("Anti-AFK Running:", State.antiAfkRunning)
        print("Data Change Detected:", State.dataChangeDetected)
        print("Session ID:", CONFIG.SESSION_ID:sub(1, 8) .. "...")
        print("===========================")
        return State
    end,
    
    testDataChange = function()
        State.lastStockHash = "test_change"
        smartLog("INFO", "Test data change triggered")
    end
}

-- START SMART MONITOR
initialize()
smartLog("SUCCESS", "SMART MONITOR READY!", true)
smartLog("INFO", "✅ Only updates on NEW data detection")
smartLog("INFO", "✅ Completely replaces old data with new")
smartLog("INFO", "✅ Sends keepalive pings every 30 seconds")
smartLog("INFO", "Use _G.SmartMonitor.status() for detailed info")
