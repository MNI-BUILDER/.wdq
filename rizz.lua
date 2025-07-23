local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")

-- BULLETPROOF PROFESSIONAL CONFIGURATION
local CONFIG = {
    API_URL = "https://bloxfritushit.vercel.app/api/stocks/bloxfruits",
    AUTH_HEADER = "GAMERSBERG",
    UPDATE_INTERVAL = 10,
    HEARTBEAT_INTERVAL = 20, -- Send data every 20 seconds to keep API alive
    PING_INTERVAL = 15, -- Ping every 15 seconds
    RETRY_DELAY = 3,
    MAX_RETRIES = 3,
    SESSION_ID = HttpService:GenerateGUID(false),
    
    -- Anti-AFK Settings
    ANTI_AFK_MIN_INTERVAL = 25,
    ANTI_AFK_MAX_INTERVAL = 75,
    MOVEMENT_DISTANCE = 10,
    TOOL_USE_CHANCE = 0.95,
    WALK_DURATION = 3,
    EMERGENCY_AFK_TIME = 540 -- 9 minutes
}

-- BULLETPROOF STATE MANAGEMENT
local State = {
    isRunning = false,
    lastUpdate = 0,
    lastHeartbeat = 0,
    lastPing = 0,
    retryCount = 0,
    sessionActive = true,
    lastStockHash = "",
    totalUpdates = 0,
    lastAntiAfk = 0,
    nextAntiAfk = 0,
    lastActivity = os.time(),
    connections = {},
    lastValidStock = nil,
    crashCount = 0,
    startTime = os.time()
}

-- PROFESSIONAL LOGGING WITH CRASH DETECTION
local function log(level, message)
    local timestamp = os.date("%H:%M:%S")
    local uptime = os.time() - State.startTime
    local logMsg = string.format("[%s][%s][%ds] %s", timestamp, level, uptime, tostring(message))
    print(logMsg)
    
    pcall(function()
        if level == "ERROR" or level == "CRITICAL" then
            StarterGui:SetCore("SendNotification", {
                Title = "[MONITOR] " .. level,
                Text = tostring(message),
                Duration = 10
            })
        elseif level == "SUCCESS" then
            StarterGui:SetCore("SendNotification", {
                Title = "[MONITOR] SUCCESS",
                Text = tostring(message),
                Duration = 5
            })
        end
    end)
end

-- BULLETPROOF HTTP REQUEST (NO DELETE METHOD)
local function makeSecureRequest(method, data, requestType)
    local success, result = pcall(function()
        local request = http_request or request or (syn and syn.request)
        if not request then
            error("No HTTP request function available")
        end
        
        local headers = {
            ["Authorization"] = CONFIG.AUTH_HEADER,
            ["Content-Type"] = "application/json",
            ["X-Session-ID"] = CONFIG.SESSION_ID,
            ["X-Player"] = tostring(Players.LocalPlayer.Name),
            ["X-Timestamp"] = tostring(os.time())
        }
        
        -- Add request type specific headers
        if requestType == "heartbeat" then
            headers["X-Heartbeat"] = "true"
            headers["X-Keep-Alive"] = "true"
        elseif requestType == "ping" then
            headers["X-Ping"] = "true"
            headers["X-Status"] = "alive"
        elseif requestType == "data" then
            headers["X-Data-Update"] = "true"
            headers["X-Replace"] = "true" -- Signal to replace, not append
        end
        
        local requestData = {
            Url = CONFIG.API_URL,
            Method = method or "POST", -- Always use POST/PUT, no DELETE
            Headers = headers
        }
        
        if data then
            requestData.Body = HttpService:JSONEncode(data)
        end
        
        local response = request(requestData)
        
        if response and response.StatusCode then
            if response.StatusCode >= 200 and response.StatusCode < 300 then
                return true, response.Body, response.StatusCode
            else
                return false, "HTTP " .. tostring(response.StatusCode), response.StatusCode
            end
        else
            return false, "No response", 0
        end
    end)
    
    if success then
        return result
    else
        log("ERROR", "Request failed: " .. tostring(result))
        return false, tostring(result), 0
    end
end

-- ENHANCED FRUIT DATA EXTRACTION
local function extractFruitData(fruits)
    local extractedFruits = {}
    
    if not fruits or type(fruits) ~= "table" then
        return extractedFruits
    end
    
    for i, fruit in pairs(fruits) do
        if fruit and type(fruit) == "table" then
            local fruitName = fruit.Name or fruit.name or fruit.Fruit
            local fruitPrice = fruit.Price or fruit.price or fruit.Cost
            local isOnSale = fruit.OnSale or fruit.onSale or fruit.InStock
            
            if fruitName and fruitPrice and isOnSale then
                table.insert(extractedFruits, {
                    name = tostring(fruitName),
                    price = tonumber(fruitPrice) or 0,
                    onSale = true,
                    index = i,
                    timestamp = os.time()
                })
                log("DEBUG", string.format("Extracted: %s - %d beli", fruitName, fruitPrice))
            end
        end
    end
    
    return extractedFruits
end

-- BULLETPROOF STOCK DATA RETRIEVAL
local function getReliableStockData()
    local success, result = pcall(function()
        log("DEBUG", "Getting stock data from game...")
        
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        if not remotes then
            error("Remotes folder not found")
        end
        
        local CommF = remotes:FindFirstChild("CommF_")
        if not CommF then
            error("CommF_ remote not found")
        end
        
        -- Get stock data with multiple attempts
        local normalStock, mirageStock = {}, {}
        
        for attempt = 1, 3 do
            local normalSuccess, normalResult = pcall(function()
                return CommF:InvokeServer("GetFruits", false)
            end)
            
            if normalSuccess and normalResult then
                normalStock = normalResult
                break
            else
                log("WARN", string.format("Normal stock attempt %d failed", attempt))
                task.wait(1)
            end
        end
        
        for attempt = 1, 3 do
            local mirageSuccess, mirageResult = pcall(function()
                return CommF:InvokeServer("GetFruits", true)
            end)
            
            if mirageSuccess and mirageResult then
                mirageStock = mirageResult
                break
            else
                log("WARN", string.format("Mirage stock attempt %d failed", attempt))
                task.wait(1)
            end
        end
        
        -- Extract and format
        local formattedNormal = extractFruitData(normalStock)
        local formattedMirage = extractFruitData(mirageStock)
        
        local stockData = {
            normal = formattedNormal,
            mirage = formattedMirage,
            totalCount = #formattedNormal + #formattedMirage,
            timestamp = os.time(),
            valid = true
        }
        
        log("INFO", string.format("Stock retrieved - Normal: %d, Mirage: %d", 
            #formattedNormal, #formattedMirage))
        
        return stockData
    end)
    
    if success and result then
        State.lastValidStock = result -- Store last valid stock
        return result
    else
        log("ERROR", "Stock retrieval failed: " .. tostring(result))
        -- Return last valid stock if available
        if State.lastValidStock then
            log("WARN", "Using last valid stock data")
            return State.lastValidStock
        end
        return nil
    end
end

-- CONTINUOUS DATA SENDING (NO DELETE, ONLY REPLACE)
local function sendContinuousData(stockData, forceUpdate)
    if not stockData then
        log("ERROR", "No stock data to send")
        return false
    end
    
    local payload = {
        sessionId = CONFIG.SESSION_ID,
        timestamp = os.time(),
        playerName = tostring(Players.LocalPlayer.Name),
        serverId = tostring(game.JobId or "unknown"),
        normalStock = stockData.normal,
        mirageStock = stockData.mirage,
        totalFruits = stockData.totalCount,
        antiAfkActive = true,
        continuous = true,
        replaceData = true, -- Signal to replace existing data
        uptime = os.time() - State.startTime,
        totalUpdates = State.totalUpdates
    }
    
    log("INFO", string.format("Sending continuous data - Normal: %d, Mirage: %d", 
        #stockData.normal, #stockData.mirage))
    
    local success, response, statusCode = makeSecureRequest("POST", payload, "data")
    
    if success then
        State.totalUpdates = State.totalUpdates + 1
        State.retryCount = 0
        log("SUCCESS", string.format("Data sent successfully! Updates: %d", State.totalUpdates))
        return true
    else
        State.retryCount = State.retryCount + 1
        log("ERROR", string.format("Data send failed (%d/%d): %s", 
            State.retryCount, CONFIG.MAX_RETRIES, tostring(response)))
        return false
    end
end

-- HEARTBEAT SYSTEM TO PREVENT EMPTY API
local function sendHeartbeat()
    local currentTime = os.time()
    if currentTime - State.lastHeartbeat < CONFIG.HEARTBEAT_INTERVAL then
        return
    end
    
    -- Get current stock or use last valid stock
    local stockData = getReliableStockData()
    if not stockData and State.lastValidStock then
        stockData = State.lastValidStock
        log("WARN", "Using cached stock for heartbeat")
    end
    
    if stockData then
        local heartbeatData = {
            sessionId = CONFIG.SESSION_ID,
            timestamp = currentTime,
            playerName = tostring(Players.LocalPlayer.Name),
            normalStock = stockData.normal,
            mirageStock = stockData.mirage,
            totalFruits = stockData.totalCount,
            heartbeat = true,
            keepAlive = true,
            uptime = currentTime - State.startTime
        }
        
        local success = makeSecureRequest("POST", heartbeatData, "heartbeat")
        
        if success then
            State.lastHeartbeat = currentTime
            log("DEBUG", "Heartbeat sent - API kept alive")
        else
            log("WARN", "Heartbeat failed")
        end
    end
end

-- PING SYSTEM
local function sendStatusPing()
    local currentTime = os.time()
    if currentTime - State.lastPing < CONFIG.PING_INTERVAL then
        return
    end
    
    local pingData = {
        sessionId = CONFIG.SESSION_ID,
        timestamp = currentTime,
        playerName = tostring(Players.LocalPlayer.Name),
        status = "active",
        uptime = currentTime - State.startTime,
        totalUpdates = State.totalUpdates,
        ping = true
    }
    
    local success = makeSecureRequest("PUT", pingData, "ping")
    
    if success then
        State.lastPing = currentTime
        log("DEBUG", "Status ping sent")
    else
        log("WARN", "Status ping failed")
    end
end

-- BULLETPROOF ANTI-AFK SYSTEM
local function performReliableMovement()
    pcall(function()
        local character = Players.LocalPlayer.Character
        if not character then return end
        
        local humanoid = character:FindFirstChild("Humanoid")
        local rootPart = character:FindFirstChild("HumanoidRootPart")
        if not humanoid or not rootPart then return end
        
        local moveType = math.random(1, 5)
        
        if moveType == 1 then
            -- Random walk
            local angle = math.random() * math.pi * 2
            local distance = math.random(5, CONFIG.MOVEMENT_DISTANCE)
            local direction = Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
            humanoid:MoveTo(rootPart.Position + direction)
            task.wait(math.random(2, CONFIG.WALK_DURATION))
            
        elseif moveType == 2 then
            -- Jump and move
            humanoid.Jump = true
            task.wait(1)
            local angle = math.random() * math.pi * 2
            local distance = math.random(3, 8)
            local direction = Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
            humanoid:MoveTo(rootPart.Position + direction)
            task.wait(2)
            
        elseif moveType == 3 then
            -- Rotate and walk
            local rotation = math.random(-180, 180)
            rootPart.CFrame = rootPart.CFrame * CFrame.Angles(0, math.rad(rotation), 0)
            task.wait(0.5)
            local angle = math.random() * math.pi * 2
            local distance = math.random(4, 7)
            local direction = Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
            humanoid:MoveTo(rootPart.Position + direction)
            task.wait(2)
            
        elseif moveType == 4 then
            -- Circle walk
            local center = rootPart.Position
            local radius = math.random(4, 8)
            for i = 1, 8 do
                local angle = (i / 8) * math.pi * 2
                local pos = center + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
                humanoid:MoveTo(pos)
                task.wait(0.8)
            end
            
        else
            -- Back and forth with jumps
            local startPos = rootPart.Position
            local angle = math.random() * math.pi * 2
            local distance = math.random(5, 8)
            local direction = Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
            
            humanoid:MoveTo(startPos + direction)
            task.wait(1.5)
            humanoid.Jump = true
            task.wait(1)
            humanoid:MoveTo(startPos)
            task.wait(1.5)
        end
        
        log("DEBUG", "Movement executed successfully")
    end)
end

local function useToolsReliably()
    pcall(function()
        local character = Players.LocalPlayer.Character
        local backpack = Players.LocalPlayer:FindFirstChild("Backpack")
        if not character or not backpack then return end
        
        local humanoid = character:FindFirstChild("Humanoid")
        if not humanoid then return end
        
        local tools = {}
        for _, item in pairs(backpack:GetChildren()) do
            if item:IsA("Tool") then
                table.insert(tools, item)
            end
        end
        
        if #tools == 0 then return end
        
        -- Use multiple tools
        local toolsToUse = math.min(#tools, math.random(1, 3))
        
        for i = 1, toolsToUse do
            local tool = tools[math.random(1, #tools)]
            
            humanoid:EquipTool(tool)
            task.wait(math.random(1, 2))
            
            if tool.Parent == character then
                -- Use tool multiple times with movement
                for j = 1, math.random(4, 8) do
                    tool:Activate()
                    task.wait(math.random(0.3, 0.8))
                    
                    -- Move while using
                    if math.random() > 0.6 then
                        local rootPart = character:FindFirstChild("HumanoidRootPart")
                        if rootPart then
                            local angle = math.random() * math.pi * 2
                            local distance = math.random(2, 4)
                            local direction = Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
                            humanoid:MoveTo(rootPart.Position + direction)
                        end
                    end
                end
                
                task.wait(math.random(2, 5))
                
                if math.random() > 0.4 then
                    humanoid:UnequipTools()
                end
                
                log("DEBUG", "Used tool: " .. tool.Name)
            end
            
            task.wait(math.random(1, 2))
        end
    end)
end

local function executeBulletproofAntiAfk()
    local currentTime = os.time()
    
    -- Emergency mode
    if currentTime - State.lastActivity >= CONFIG.EMERGENCY_AFK_TIME then
        log("CRITICAL", "EMERGENCY ANTI-AFK ACTIVATED!")
        
        for i = 1, 4 do
            spawn(function() performReliableMovement() end)
            task.wait(2)
            spawn(function() useToolsReliably() end)
            task.wait(3)
        end
        
        State.lastActivity = currentTime
        log("SUCCESS", "Emergency anti-AFK completed")
        return
    end
    
    -- Regular anti-AFK
    if currentTime < State.nextAntiAfk then return end
    
    log("INFO", "Executing bulletproof anti-AFK...")
    
    spawn(function() performReliableMovement() end)
    
    if math.random() <= CONFIG.TOOL_USE_CHANCE then
        spawn(function()
            task.wait(math.random(1, 3))
            useToolsReliably()
        end)
    end
    
    State.lastActivity = currentTime
    State.lastAntiAfk = currentTime
    
    local nextInterval = math.random(CONFIG.ANTI_AFK_MIN_INTERVAL, CONFIG.ANTI_AFK_MAX_INTERVAL)
    State.nextAntiAfk = currentTime + nextInterval
    
    log("SUCCESS", string.format("Anti-AFK completed - Next in %d seconds", nextInterval))
end

-- CRASH RECOVERY SYSTEM
local function handleCrash()
    State.crashCount = State.crashCount + 1
    log("CRITICAL", string.format("Crash detected! Count: %d", State.crashCount))
    
    if State.crashCount >= 5 then
        log("CRITICAL", "Too many crashes - stopping monitor")
        State.isRunning = false
        return
    end
    
    -- Wait and restart
    task.wait(5)
    log("INFO", "Attempting crash recovery...")
    
    -- Reset state
    State.retryCount = 0
    State.lastActivity = os.time()
    State.nextAntiAfk = os.time() + 30
    
    log("SUCCESS", "Crash recovery completed")
end

-- SETUP CONNECTIONS
local function setupBulletproofConnections()
    -- Anti-idle
    pcall(function()
        Players.LocalPlayer.Idled:Connect(function()
            local VirtualUser = game:GetService("VirtualUser")
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
            log("DEBUG", "Idle prevention triggered")
        end)
    end)
    
    -- Teleport handling
    pcall(function()
        local connection = Players.LocalPlayer.OnTeleport:Connect(function(state)
            if state == Enum.TeleportState.Failed then
                log("WARN", "Teleport failed - rejoining...")
                task.wait(3)
                TeleportService:Teleport(game.PlaceId, Players.LocalPlayer)
            end
        end)
        table.insert(State.connections, connection)
    end)
    
    -- Window focus
    pcall(function()
        local connection1 = UserInputService.WindowFocusReleased:Connect(function()
            RunService:Set3dRenderingEnabled(false)
        end)
        local connection2 = UserInputService.WindowFocused:Connect(function()
            RunService:Set3dRenderingEnabled(true)
        end)
        table.insert(State.connections, connection1)
        table.insert(State.connections, connection2)
    end)
    
    log("SUCCESS", "Bulletproof connections established")
end

-- BULLETPROOF MAIN LOOP
local function startBulletproofMonitoring()
    State.isRunning = true
    State.lastUpdate = os.time()
    State.lastActivity = os.time()
    State.lastHeartbeat = 0
    State.lastPing = 0
    State.nextAntiAfk = os.time() + math.random(CONFIG.ANTI_AFK_MIN_INTERVAL, CONFIG.ANTI_AFK_MAX_INTERVAL)
    
    log("SUCCESS", "BULLETPROOF PROFESSIONAL MONITOR STARTED!")
    log("INFO", "Player: " .. tostring(Players.LocalPlayer.Name))
    log("INFO", "Session: " .. CONFIG.SESSION_ID:sub(1, 8) .. "...")
    log("INFO", "Continuous data sending enabled - API will never be empty!")
    
    local cycleCount = 0
    
    while State.isRunning do
        pcall(function()
            -- Execute anti-AFK
            executeBulletproofAntiAfk()
            
            -- Send heartbeat to keep API alive
            sendHeartbeat()
            
            -- Send status ping
            sendStatusPing()
            
            -- Get current stock data
            local currentStock = getReliableStockData()
            
            if currentStock then
                -- Generate hash to detect changes
                local currentHash = HttpService:JSONEncode(currentStock)
                
                -- Send if data changed OR every 60 seconds to prevent empty API
                local timeSinceUpdate = os.time() - State.lastUpdate
                if currentHash ~= State.lastStockHash or timeSinceUpdate >= 60 then
                    log("INFO", "Sending data update...")
                    
                    if sendContinuousData(currentStock, timeSinceUpdate >= 60) then
                        State.lastStockHash = currentHash
                        State.lastUpdate = os.time()
                        State.retryCount = 0
                    else
                        if State.retryCount >= CONFIG.MAX_RETRIES then
                            log("ERROR", "Max retries reached - attempting recovery")
                            handleCrash()
                        end
                    end
                else
                    log("DEBUG", "No changes - heartbeat keeping API alive")
                end
            else
                log("WARN", "No stock data - sending heartbeat")
                sendHeartbeat()
            end
            
            -- Status logging
            cycleCount = cycleCount + 1
            if cycleCount >= 6 then
                local timeSinceActivity = os.time() - State.lastActivity
                local nextAfkIn = math.max(0, State.nextAntiAfk - os.time())
                local uptime = os.time() - State.startTime
                log("INFO", string.format("Status: %d updates | %ds uptime | Activity: %ds ago | Next AFK: %ds", 
                    State.totalUpdates, uptime, timeSinceActivity, nextAfkIn))
                cycleCount = 0
            end
        end)
        
        task.wait(CONFIG.UPDATE_INTERVAL)
    end
    
    log("INFO", "Bulletproof monitoring stopped")
end

-- INITIALIZE
local function initializeBulletproofMonitor()
    log("INFO", "Initializing Bulletproof Professional Monitor...")
    
    if not ReplicatedStorage:FindFirstChild("Remotes") then
        log("ERROR", "Not in Blox Fruits game!")
        return
    end
    
    setupBulletproofConnections()
    
    spawn(function()
        startBulletproofMonitoring()
    end)
    
    log("SUCCESS", "Bulletproof Professional Monitor initialized!")
end

-- CONTROL INTERFACE
_G.BulletproofStockMonitor = {
    stop = function()
        State.isRunning = false
        log("INFO", "Monitor stopped manually")
    end,
    
    restart = function()
        State.isRunning = false
        task.wait(3)
        initializeBulletproofMonitor()
    end,
    
    forceUpdate = function()
        State.lastStockHash = ""
        State.lastUpdate = 0
        log("INFO", "Forced update triggered")
    end,
    
    forceHeartbeat = function()
        State.lastHeartbeat = 0
        sendHeartbeat()
        log("INFO", "Forced heartbeat sent")
    end,
    
    testStock = function()
        local stock = getReliableStockData()
        if stock then
            print("=== STOCK TEST RESULTS ===")
            print("Normal fruits:", #stock.normal)
            print("Mirage fruits:", #stock.mirage)
            print("Total fruits:", stock.totalCount)
            for i, fruit in ipairs(stock.normal) do
                print(string.format("Normal %d: %s - %d", i, fruit.name, fruit.price))
            end
            for i, fruit in ipairs(stock.mirage) do
                print(string.format("Mirage %d: %s - %d", i, fruit.name, fruit.price))
            end
            print("========================")
        else
            print("Failed to get stock data")
        end
        return stock
    end,
    
    forceAntiAfk = function()
        State.nextAntiAfk = 0
        log("INFO", "Forced anti-AFK triggered")
    end,
    
    status = function()
        local timeSinceActivity = os.time() - State.lastActivity
        local nextAfkIn = math.max(0, State.nextAntiAfk - os.time())
        local timeSinceHeartbeat = os.time() - State.lastHeartbeat
        local timeSincePing = os.time() - State.lastPing
        local uptime = os.time() - State.startTime
        
        print("=== BULLETPROOF PROFESSIONAL MONITOR STATUS ===")
        print("Running:", State.isRunning)
        print("Uptime:", uptime, "seconds")
        print("Total Updates:", State.totalUpdates)
        print("Crash Count:", State.crashCount)
        print("Time Since Activity:", timeSinceActivity, "seconds")
        print("Next Anti-AFK:", nextAfkIn, "seconds")
        print("Last Heartbeat:", timeSinceHeartbeat, "seconds ago")
        print("Last Ping:", timeSincePing, "seconds ago")
        print("Active Connections:", #State.connections)
        print("Session ID:", CONFIG.SESSION_ID:sub(1, 8) .. "...")
        print("==============================================")
        return State
    end
}

-- START THE BULLETPROOF MONITOR
initializeBulletproofMonitor()
log("SUCCESS", "BULLETPROOF MONITOR READY!")
log("INFO", "API will NEVER be empty - continuous data sending active!")
log("INFO", "Crash recovery system enabled!")
log("INFO", "Use _G.BulletproofStockMonitor.status() for full status")
