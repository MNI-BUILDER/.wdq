local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")

-- SECURE NATURAL CONFIGURATION
local CONFIG = {
    API_URL = "https://bloxfritushit.vercel.app/api/stocks/bloxfruits",
    AUTH_HEADER = "GAMERSBERG",
    UPDATE_INTERVAL = 10,
    HEARTBEAT_INTERVAL = 25,
    PING_INTERVAL = 20,
    RETRY_DELAY = 3,
    MAX_RETRIES = 3,
    SESSION_ID = HttpService:GenerateGUID(false),
    
    -- SAFE Anti-AFK Settings (More Human-Like)
    ANTI_AFK_MIN_INTERVAL = 120, -- 2 minutes minimum (much longer)
    ANTI_AFK_MAX_INTERVAL = 300, -- 5 minutes maximum
    MOVEMENT_DISTANCE = 6, -- Smaller, more natural movements
    TOOL_USE_CHANCE = 0.4, -- Lower chance, more natural
    WALK_DURATION = 2, -- Shorter walks
    EMERGENCY_AFK_TIME = 1000, -- 16+ minutes before emergency
    NATURAL_PAUSE_MIN = 3, -- Minimum pause between actions
    NATURAL_PAUSE_MAX = 8  -- Maximum pause between actions
}

-- STATE MANAGEMENT
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
    startTime = os.time(),
    isMoving = false,
    lastNaturalAction = 0
}

-- LOGGING SYSTEM
local function log(level, message)
    local timestamp = os.date("%H:%M:%S")
    local uptime = os.time() - State.startTime
    local logMsg = string.format("[%s][%s][%ds] %s", timestamp, level, uptime, tostring(message))
    print(logMsg)
    
    pcall(function()
        if level == "ERROR" or level == "CRITICAL" then
            StarterGui:SetCore("SendNotification", {
                Title = "[SECURE] " .. level,
                Text = tostring(message),
                Duration = 8
            })
        elseif level == "SUCCESS" then
            StarterGui:SetCore("SendNotification", {
                Title = "[SECURE] SUCCESS",
                Text = tostring(message),
                Duration = 4
            })
        end
    end)
end

-- SECURE HTTP REQUEST
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
        
        if requestType == "heartbeat" then
            headers["X-Heartbeat"] = "true"
        elseif requestType == "ping" then
            headers["X-Ping"] = "true"
        elseif requestType == "data" then
            headers["X-Data-Update"] = "true"
            headers["X-Replace"] = "true"
        end
        
        local requestData = {
            Url = CONFIG.API_URL,
            Method = method or "POST",
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
                log("DEBUG", string.format("Found: %s - %d beli", fruitName, fruitPrice))
            end
        end
    end
    
    return extractedFruits
end

-- SECURE STOCK DATA RETRIEVAL
local function getSecureStockData()
    local success, result = pcall(function()
        log("DEBUG", "Getting stock data...")
        
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        if not remotes then
            error("Remotes not found")
        end
        
        local CommF = remotes:FindFirstChild("CommF_")
        if not CommF then
            error("CommF_ not found")
        end
        
        local normalStock, mirageStock = {}, {}
        
        -- Get normal stock
        local normalSuccess, normalResult = pcall(function()
            return CommF:InvokeServer("GetFruits", false)
        end)
        
        if normalSuccess and normalResult then
            normalStock = normalResult
        end
        
        -- Get mirage stock
        local mirageSuccess, mirageResult = pcall(function()
            return CommF:InvokeServer("GetFruits", true)
        end)
        
        if mirageSuccess and mirageResult then
            mirageStock = mirageResult
        end
        
        local formattedNormal = extractFruitData(normalStock)
        local formattedMirage = extractFruitData(mirageStock)
        
        local stockData = {
            normal = formattedNormal,
            mirage = formattedMirage,
            totalCount = #formattedNormal + #formattedMirage,
            timestamp = os.time(),
            valid = true
        }
        
        log("INFO", string.format("Stock: Normal %d, Mirage %d", #formattedNormal, #formattedMirage))
        
        return stockData
    end)
    
    if success and result then
        State.lastValidStock = result
        return result
    else
        log("ERROR", "Stock retrieval failed: " .. tostring(result))
        if State.lastValidStock then
            return State.lastValidStock
        end
        return nil
    end
end

-- NATURAL PAUSE SYSTEM
local function naturalPause(minTime, maxTime)
    local pauseTime = math.random(minTime or CONFIG.NATURAL_PAUSE_MIN, maxTime or CONFIG.NATURAL_PAUSE_MAX)
    log("DEBUG", string.format("Natural pause: %d seconds", pauseTime))
    task.wait(pauseTime)
end

-- ULTRA SAFE ANTI-AFK SYSTEM (HUMAN-LIKE)
local function performNaturalMovement()
    if State.isMoving then return end
    State.isMoving = true
    
    pcall(function()
        local character = Players.LocalPlayer.Character
        if not character then 
            State.isMoving = false
            return 
        end
        
        local humanoid = character:FindFirstChild("Humanoid")
        local rootPart = character:FindFirstChild("HumanoidRootPart")
        if not humanoid or not rootPart then 
            State.isMoving = false
            return 
        end
        
        -- Very natural, small movements only
        local moveType = math.random(1, 6)
        
        if moveType == 1 then
            -- Tiny step forward/backward (most natural)
            local direction = math.random() > 0.5 and 1 or -1
            local distance = math.random(1, 3) -- Very small distance
            local moveVector = rootPart.CFrame.LookVector * distance * direction
            humanoid:MoveTo(rootPart.Position + moveVector)
            task.wait(math.random(1, 2))
            
        elseif moveType == 2 then
            -- Slight turn (very natural)
            local turnAmount = math.random(-30, 30) -- Small turn
            rootPart.CFrame = rootPart.CFrame * CFrame.Angles(0, math.rad(turnAmount), 0)
            task.wait(math.random(1, 2))
            
        elseif moveType == 3 then
            -- Small side step
            local direction = math.random() > 0.5 and 1 or -1
            local distance = math.random(1, 2)
            local moveVector = rootPart.CFrame.RightVector * distance * direction
            humanoid:MoveTo(rootPart.Position + moveVector)
            task.wait(math.random(1, 2))
            
        elseif moveType == 4 then
            -- Just look around (camera-like movement)
            for i = 1, math.random(2, 4) do
                local turnAmount = math.random(-45, 45)
                rootPart.CFrame = rootPart.CFrame * CFrame.Angles(0, math.rad(turnAmount), 0)
                task.wait(math.random(0.5, 1.5))
            end
            
        elseif moveType == 5 then
            -- Tiny walk in random direction
            local angle = math.random() * math.pi * 2
            local distance = math.random(2, CONFIG.MOVEMENT_DISTANCE) -- Small distance
            local direction = Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
            humanoid:MoveTo(rootPart.Position + direction)
            task.wait(math.random(1, CONFIG.WALK_DURATION))
            
        else
            -- Do nothing (sometimes humans just stand still)
            task.wait(math.random(2, 5))
        end
        
        log("DEBUG", "Natural movement completed")
    end)
    
    State.isMoving = false
end

local function useToolsNaturally()
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
        
        -- Use only one tool at a time (more natural)
        local tool = tools[math.random(1, #tools)]
        
        -- Natural pause before equipping
        naturalPause(2, 4)
        
        humanoid:EquipTool(tool)
        naturalPause(1, 3) -- Pause after equipping
        
        if tool.Parent == character then
            -- Use tool naturally (not spam clicking)
            local uses = math.random(2, 4) -- Fewer uses
            for i = 1, uses do
                tool:Activate()
                naturalPause(1, 3) -- Natural pause between uses
            end
            
            -- Keep tool equipped for a while (natural behavior)
            naturalPause(5, 12)
            
            -- Sometimes unequip, sometimes keep it
            if math.random() > 0.6 then
                humanoid:UnequipTools()
                log("DEBUG", "Unequipped " .. tool.Name)
            else
                log("DEBUG", "Keeping " .. tool.Name .. " equipped")
            end
        end
    end)
end

local function executeSecureAntiAfk()
    local currentTime = os.time()
    
    -- Much longer intervals to avoid detection
    if currentTime < State.nextAntiAfk then return end
    
    -- Emergency mode (very rare)
    if currentTime - State.lastActivity >= CONFIG.EMERGENCY_AFK_TIME then
        log("CRITICAL", "Emergency anti-AFK (rare activation)")
        
        -- Very gentle emergency actions
        spawn(function() 
            performNaturalMovement()
            naturalPause(10, 20) -- Long pause
            if math.random() > 0.7 then -- Low chance
                useToolsNaturally()
            end
        end)
        
        State.lastActivity = currentTime
        log("SUCCESS", "Emergency anti-AFK completed")
        return
    end
    
    log("INFO", "Executing secure anti-AFK (natural behavior)...")
    
    -- Natural movement with long pauses
    spawn(function()
        performNaturalMovement()
        naturalPause(5, 15) -- Long pause after movement
    end)
    
    -- Tool usage with low probability
    if math.random() <= CONFIG.TOOL_USE_CHANCE then
        spawn(function()
            naturalPause(8, 20) -- Long pause before tool use
            useToolsNaturally()
        end)
    end
    
    State.lastActivity = currentTime
    State.lastAntiAfk = currentTime
    State.lastNaturalAction = currentTime
    
    -- Much longer intervals between anti-AFK actions
    local nextInterval = math.random(CONFIG.ANTI_AFK_MIN_INTERVAL, CONFIG.ANTI_AFK_MAX_INTERVAL)
    State.nextAntiAfk = currentTime + nextInterval
    
    log("SUCCESS", string.format("Secure anti-AFK completed - Next in %d seconds (%.1f minutes)", 
        nextInterval, nextInterval/60))
end

-- CONTINUOUS DATA SENDING
local function sendContinuousData(stockData)
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
        secureMode = true,
        uptime = os.time() - State.startTime,
        totalUpdates = State.totalUpdates
    }
    
    log("INFO", string.format("Sending data - Normal: %d, Mirage: %d", 
        #stockData.normal, #stockData.mirage))
    
    local success, response, statusCode = makeSecureRequest("POST", payload, "data")
    
    if success then
        State.totalUpdates = State.totalUpdates + 1
        State.retryCount = 0
        log("SUCCESS", string.format("Data sent! Updates: %d", State.totalUpdates))
        return true
    else
        State.retryCount = State.retryCount + 1
        log("ERROR", string.format("Send failed (%d/%d): %s", 
            State.retryCount, CONFIG.MAX_RETRIES, tostring(response)))
        return false
    end
end

-- HEARTBEAT SYSTEM
local function sendHeartbeat()
    local currentTime = os.time()
    if currentTime - State.lastHeartbeat < CONFIG.HEARTBEAT_INTERVAL then
        return
    end
    
    local stockData = getSecureStockData()
    if not stockData and State.lastValidStock then
        stockData = State.lastValidStock
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
            secureMode = true,
            uptime = currentTime - State.startTime
        }
        
        local success = makeSecureRequest("POST", heartbeatData, "heartbeat")
        
        if success then
            State.lastHeartbeat = currentTime
            log("DEBUG", "Heartbeat sent")
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
        status = "secure_active",
        uptime = currentTime - State.startTime,
        totalUpdates = State.totalUpdates,
        secureMode = true
    }
    
    local success = makeSecureRequest("PUT", pingData, "ping")
    
    if success then
        State.lastPing = currentTime
        log("DEBUG", "Status ping sent")
    end
end

-- SETUP CONNECTIONS
local function setupSecureConnections()
    -- Enhanced anti-idle (more natural)
    pcall(function()
        Players.LocalPlayer.Idled:Connect(function()
            -- More natural idle prevention
            local VirtualUser = game:GetService("VirtualUser")
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
            
            -- Add small delay to make it more natural
            task.wait(math.random(1, 3))
            
            log("DEBUG", "Natural idle prevention")
        end)
    end)
    
    -- Other connections remain the same
    pcall(function()
        local connection = Players.LocalPlayer.OnTeleport:Connect(function(state)
            if state == Enum.TeleportState.Failed then
                log("WARN", "Teleport failed - rejoining...")
                task.wait(5) -- Longer wait
                TeleportService:Teleport(game.PlaceId, Players.LocalPlayer)
            end
        end)
        table.insert(State.connections, connection)
    end)
    
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
    
    log("SUCCESS", "Secure connections established")
end

-- MAIN MONITORING LOOP
local function startSecureMonitoring()
    State.isRunning = true
    State.lastUpdate = os.time()
    State.lastActivity = os.time()
    State.lastHeartbeat = 0
    State.lastPing = 0
    State.nextAntiAfk = os.time() + math.random(CONFIG.ANTI_AFK_MIN_INTERVAL, CONFIG.ANTI_AFK_MAX_INTERVAL)
    
    log("SUCCESS", "SECURE NATURAL MONITOR STARTED!")
    log("INFO", "Player: " .. tostring(Players.LocalPlayer.Name))
    log("INFO", "Session: " .. CONFIG.SESSION_ID:sub(1, 8) .. "...")
    log("INFO", "Ultra-safe anti-AFK enabled - no security kicks!")
    
    local cycleCount = 0
    
    while State.isRunning do
        pcall(function()
            -- Execute secure anti-AFK (very infrequent)
            executeSecureAntiAfk()
            
            -- Send heartbeat
            sendHeartbeat()
            
            -- Send status ping
            sendStatusPing()
            
            -- Get stock data
            local currentStock = getSecureStockData()
            
            if currentStock then
                local currentHash = HttpService:JSONEncode(currentStock)
                local timeSinceUpdate = os.time() - State.lastUpdate
                
                if currentHash ~= State.lastStockHash or timeSinceUpdate >= 60 then
                    if sendContinuousData(currentStock) then
                        State.lastStockHash = currentHash
                        State.lastUpdate = os.time()
                    end
                end
            else
                sendHeartbeat()
            end
            
            -- Status logging
            cycleCount = cycleCount + 1
            if cycleCount >= 6 then
                local timeSinceActivity = os.time() - State.lastActivity
                local nextAfkIn = math.max(0, State.nextAntiAfk - os.time())
                local uptime = os.time() - State.startTime
                log("INFO", string.format("Status: %d updates | %ds uptime | Activity: %ds ago | Next AFK: %.1fm", 
                    State.totalUpdates, uptime, timeSinceActivity, nextAfkIn/60))
                cycleCount = 0
            end
        end)
        
        task.wait(CONFIG.UPDATE_INTERVAL)
    end
    
    log("INFO", "Secure monitoring stopped")
end

-- INITIALIZE
local function initializeSecureMonitor()
    log("INFO", "Initializing Secure Natural Monitor...")
    
    if not ReplicatedStorage:FindFirstChild("Remotes") then
        log("ERROR", "Not in Blox Fruits game!")
        return
    end
    
    setupSecureConnections()
    
    spawn(function()
        startSecureMonitoring()
    end)
    
    log("SUCCESS", "Secure Natural Monitor initialized!")
end

-- CONTROL INTERFACE
_G.SecureStockMonitor = {
    stop = function()
        State.isRunning = false
        log("INFO", "Monitor stopped manually")
    end,
    
    restart = function()
        State.isRunning = false
        task.wait(3)
        initializeSecureMonitor()
    end,
    
    forceUpdate = function()
        State.lastStockHash = ""
        State.lastUpdate = 0
        log("INFO", "Forced update triggered")
    end,
    
    testMovement = function()
        log("INFO", "Testing natural movement...")
        spawn(function()
            performNaturalMovement()
        end)
    end,
    
    testStock = function()
        local stock = getSecureStockData()
        if stock then
            print("=== STOCK TEST ===")
            print("Normal:", #stock.normal)
            print("Mirage:", #stock.mirage)
            print("Total:", stock.totalCount)
            print("================")
        end
        return stock
    end,
    
    status = function()
        local timeSinceActivity = os.time() - State.lastActivity
        local nextAfkIn = math.max(0, State.nextAntiAfk - os.time())
        local uptime = os.time() - State.startTime
        
        print("=== SECURE NATURAL MONITOR STATUS ===")
        print("Running:", State.isRunning)
        print("Uptime:", uptime, "seconds")
        print("Total Updates:", State.totalUpdates)
        print("Time Since Activity:", timeSinceActivity, "seconds")
        print("Next Anti-AFK:", string.format("%.1f minutes", nextAfkIn/60))
        print("Is Moving:", State.isMoving)
        print("Session ID:", CONFIG.SESSION_ID:sub(1, 8) .. "...")
        print("====================================")
        return State
    end
}

-- START SECURE MONITOR
initializeSecureMonitor()
log("SUCCESS", "SECURE MONITOR READY - NO SECURITY KICKS!")
log("INFO", "Natural human-like behavior enabled!")
log("INFO", "Use _G.SecureStockMonitor.testMovement() to test safe movement")
