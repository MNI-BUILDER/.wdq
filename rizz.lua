local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")

-- FIXED PROFESSIONAL CONFIGURATION
local CONFIG = {
    API_URL = "https://bloxfritushit.vercel.app/api/stocks/bloxfruits",
    AUTH_HEADER = "GAMERSBERG",
    UPDATE_INTERVAL = 10,
    PING_INTERVAL = 30, -- Ping every 30 seconds to keep data alive
    RETRY_DELAY = 3,
    MAX_RETRIES = 5,
    SESSION_ID = HttpService:GenerateGUID(false),
    
    -- FIXED Anti-AFK Settings
    ANTI_AFK_MIN_INTERVAL = 30, -- More frequent
    ANTI_AFK_MAX_INTERVAL = 90,
    MOVEMENT_DISTANCE = 10,
    TOOL_USE_CHANCE = 0.9, -- Higher chance
    WALK_DURATION = 3,
    EMERGENCY_AFK_TIME = 600 -- 10 minutes
}

-- PROFESSIONAL STATE MANAGEMENT
local State = {
    isRunning = false,
    lastUpdate = 0,
    lastPing = 0,
    retryCount = 0,
    sessionActive = true,
    lastStockHash = "",
    totalUpdates = 0,
    lastAntiAfk = 0,
    nextAntiAfk = 0,
    lastActivity = os.time(),
    connections = {},
    currentStockData = nil
}

-- PROFESSIONAL LOGGING
local function log(level, message)
    local timestamp = os.date("%H:%M:%S")
    local logMsg = string.format("[%s][%s] %s", timestamp, level, tostring(message))
    print(logMsg)
    
    pcall(function()
        if level == "ERROR" or level == "SUCCESS" then
            StarterGui:SetCore("SendNotification", {
                Title = "[MONITOR] " .. level,
                Text = tostring(message),
                Duration = level == "ERROR" and 8 or 5
            })
        end
    end)
end

-- FIXED HTTP REQUEST FUNCTION
local function makeRequest(method, data, isPing)
    local success, result = pcall(function()
        local request = http_request or request or (syn and syn.request)
        if not request then
            error("No HTTP request function available")
        end
        
        local headers = {
            ["Authorization"] = CONFIG.AUTH_HEADER,
            ["Content-Type"] = "application/json",
            ["X-Session-ID"] = CONFIG.SESSION_ID
        }
        
        if isPing then
            headers["X-Ping"] = "true"
            headers["X-Keep-Alive"] = "true"
        else
            headers["X-Replace-Data"] = "true"
            headers["X-Clear-Old"] = "true"
        end
        
        local requestData = {
            Url = CONFIG.API_URL,
            Method = method or "GET",
            Headers = headers
        }
        
        if data and (method == "POST" or method == "PUT") then
            requestData.Body = HttpService:JSONEncode(data)
        end
        
        local response = request(requestData)
        
        if response and response.StatusCode then
            if response.StatusCode >= 200 and response.StatusCode < 300 then
                return true, response.Body
            else
                return false, "HTTP " .. tostring(response.StatusCode)
            end
        else
            return false, "No response"
        end
    end)
    
    if success then
        return result
    else
        log("ERROR", "Request failed: " .. tostring(result))
        return false, tostring(result)
    end
end

-- FIXED DATA MANAGEMENT - NO STACKING
local function clearOldData()
    log("INFO", "Clearing old data from API...")
    
    local success = makeRequest("DELETE", {
        action = "CLEAR_SESSION",
        sessionId = CONFIG.SESSION_ID,
        timestamp = os.time()
    })
    
    if success then
        log("SUCCESS", "Old data cleared successfully")
        task.wait(1) -- Wait for server to process
        return true
    else
        log("ERROR", "Failed to clear old data")
        return false
    end
end

local function sendFreshData(stockData)
    -- Step 1: Clear old data first
    clearOldData()
    
    -- Step 2: Format new data
    local normalStock = {}
    local mirageStock = {}
    
    if stockData.normal then
        for _, fruit in pairs(stockData.normal) do
            if fruit and fruit.OnSale and fruit.Name and fruit.Price then
                table.insert(normalStock, {
                    name = tostring(fruit.Name),
                    price = tonumber(fruit.Price),
                    onSale = true
                })
            end
        end
    end
    
    if stockData.mirage then
        for _, fruit in pairs(stockData.mirage) do
            if fruit and fruit.OnSale and fruit.Name and fruit.Price then
                table.insert(mirageStock, {
                    name = tostring(fruit.Name),
                    price = tonumber(fruit.Price),
                    onSale = true
                })
            end
        end
    end
    
    -- Step 3: Send fresh data
    local payload = {
        sessionId = CONFIG.SESSION_ID,
        timestamp = os.time(),
        playerName = tostring(Players.LocalPlayer.Name),
        serverId = tostring(game.JobId or "unknown"),
        normalStock = normalStock,
        mirageStock = mirageStock,
        totalFruits = #normalStock + #mirageStock,
        replaceMode = true,
        freshData = true
    }
    
    local success, response = makeRequest("POST", payload, false)
    
    if success then
        State.totalUpdates = State.totalUpdates + 1
        log("SUCCESS", string.format("Fresh data sent - Normal: %d, Mirage: %d", #normalStock, #mirageStock))
        return true
    else
        log("ERROR", "Failed to send fresh data: " .. tostring(response))
        return false
    end
end

-- KEEP ALIVE PING SYSTEM
local function sendKeepAlivePing()
    local currentTime = os.time()
    if currentTime - State.lastPing < CONFIG.PING_INTERVAL then
        return
    end
    
    local pingData = {
        sessionId = CONFIG.SESSION_ID,
        timestamp = currentTime,
        playerName = tostring(Players.LocalPlayer.Name),
        status = "alive",
        ping = true
    }
    
    local success = makeRequest("POST", pingData, true)
    
    if success then
        State.lastPing = currentTime
        log("DEBUG", "Keep-alive ping sent")
    else
        log("WARN", "Keep-alive ping failed")
    end
end

-- FIXED ANTI-AFK SYSTEM
local function performMovement()
    local success = pcall(function()
        local character = Players.LocalPlayer.Character
        if not character then return end
        
        local humanoid = character:FindFirstChild("Humanoid")
        local rootPart = character:FindFirstChild("HumanoidRootPart")
        if not humanoid or not rootPart then return end
        
        -- Random movement type
        local moveType = math.random(1, 5)
        
        if moveType == 1 then
            -- Walk in random direction
            local angle = math.random() * math.pi * 2
            local distance = math.random(5, CONFIG.MOVEMENT_DISTANCE)
            local direction = Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
            local targetPos = rootPart.Position + direction
            
            humanoid:MoveTo(targetPos)
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
            -- Rotate character
            local rotation = math.random(-180, 180)
            rootPart.CFrame = rootPart.CFrame * CFrame.Angles(0, math.rad(rotation), 0)
            task.wait(1)
            
        elseif moveType == 4 then
            -- Walk in square pattern
            local startPos = rootPart.Position
            local size = math.random(5, 8)
            local positions = {
                startPos + Vector3.new(size, 0, 0),
                startPos + Vector3.new(size, 0, size),
                startPos + Vector3.new(0, 0, size),
                startPos
            }
            
            for _, pos in ipairs(positions) do
                humanoid:MoveTo(pos)
                task.wait(1.5)
            end
            
        else
            -- Random walk with multiple stops
            for i = 1, math.random(2, 4) do
                local angle = math.random() * math.pi * 2
                local distance = math.random(3, 7)
                local direction = Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
                humanoid:MoveTo(rootPart.Position + direction)
                task.wait(math.random(1, 2))
            end
        end
        
        log("DEBUG", "Movement pattern executed")
    end)
    
    if not success then
        log("WARN", "Movement failed")
    end
end

local function useTools()
    local success = pcall(function()
        local character = Players.LocalPlayer.Character
        local backpack = Players.LocalPlayer:FindFirstChild("Backpack")
        if not character or not backpack then return end
        
        local humanoid = character:FindFirstChild("Humanoid")
        if not humanoid then return end
        
        -- Get available tools
        local tools = {}
        for _, item in pairs(backpack:GetChildren()) do
            if item:IsA("Tool") then
                table.insert(tools, item)
            end
        end
        
        if #tools == 0 then return end
        
        -- Use random tool
        local tool = tools[math.random(1, #tools)]
        
        -- Equip tool
        humanoid:EquipTool(tool)
        task.wait(math.random(1, 2))
        
        if tool.Parent == character then
            -- Use tool multiple times
            for i = 1, math.random(3, 6) do
                tool:Activate()
                task.wait(math.random(0.5, 1))
                
                -- Move while using tool
                if math.random() > 0.5 then
                    local rootPart = character:FindFirstChild("HumanoidRootPart")
                    if rootPart then
                        local angle = math.random() * math.pi * 2
                        local distance = math.random(2, 4)
                        local direction = Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
                        humanoid:MoveTo(rootPart.Position + direction)
                    end
                end
            end
            
            task.wait(math.random(2, 4))
            
            -- Sometimes unequip
            if math.random() > 0.3 then
                humanoid:UnequipTools()
            end
            
            log("DEBUG", "Used tool: " .. tool.Name)
        end
    end)
    
    if not success then
        log("WARN", "Tool usage failed")
    end
end

local function executeAntiAfk()
    local currentTime = os.time()
    
    -- Emergency mode
    if currentTime - State.lastActivity >= CONFIG.EMERGENCY_AFK_TIME then
        log("ERROR", "EMERGENCY ANTI-AFK ACTIVATED!")
        
        for i = 1, 3 do
            spawn(function() performMovement() end)
            task.wait(2)
            spawn(function() useTools() end)
            task.wait(3)
        end
        
        State.lastActivity = currentTime
        log("SUCCESS", "Emergency anti-AFK completed")
        return
    end
    
    -- Regular anti-AFK check
    if currentTime < State.nextAntiAfk then return end
    
    log("INFO", "Executing anti-AFK actions...")
    
    -- Execute movement
    spawn(function()
        performMovement()
    end)
    
    -- Execute tool usage
    if math.random() <= CONFIG.TOOL_USE_CHANCE then
        spawn(function()
            task.wait(math.random(1, 3))
            useTools()
        end)
    end
    
    -- Update timers
    State.lastActivity = currentTime
    State.lastAntiAfk = currentTime
    
    local nextInterval = math.random(CONFIG.ANTI_AFK_MIN_INTERVAL, CONFIG.ANTI_AFK_MAX_INTERVAL)
    State.nextAntiAfk = currentTime + nextInterval
    
    log("SUCCESS", string.format("Anti-AFK completed - Next in %d seconds", nextInterval))
end

-- GET STOCK DATA
local function getStockData()
    local success, result = pcall(function()
        local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
        if not remotes then return nil end
        
        local CommF = remotes:WaitForChild("CommF_", 10)
        if not CommF then return nil end
        
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
        log("ERROR", "Failed to get stock data")
        return nil
    end
end

-- SETUP CONNECTIONS
local function setupConnections()
    -- Anti-idle connection
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
    
    -- Window focus optimization
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
    
    log("SUCCESS", "Connections established")
end

-- CLEANUP FUNCTION
local function cleanup()
    log("INFO", "Cleaning up session...")
    
    -- Clear data from API
    makeRequest("DELETE", {
        sessionId = CONFIG.SESSION_ID,
        action = "CLEANUP_SESSION",
        timestamp = os.time()
    })
    
    -- Disconnect all connections
    for _, connection in pairs(State.connections) do
        if connection and connection.Connected then
            connection:Disconnect()
        end
    end
    State.connections = {}
    
    State.sessionActive = false
    log("SUCCESS", "Cleanup completed")
end

-- MAIN MONITORING LOOP
local function startMonitoring()
    State.isRunning = true
    State.lastUpdate = os.time()
    State.lastActivity = os.time()
    State.nextAntiAfk = os.time() + math.random(CONFIG.ANTI_AFK_MIN_INTERVAL, CONFIG.ANTI_AFK_MAX_INTERVAL)
    
    log("SUCCESS", "FIXED PROFESSIONAL MONITOR STARTED!")
    log("INFO", "Player: " .. tostring(Players.LocalPlayer.Name))
    log("INFO", "Session: " .. CONFIG.SESSION_ID:sub(1, 8) .. "...")
    
    local cycleCount = 0
    
    while State.isRunning do
        -- Execute anti-AFK
        executeAntiAfk()
        
        -- Send keep-alive ping
        sendKeepAlivePing()
        
        -- Get current stock data
        local currentStock = getStockData()
        
        if currentStock then
            -- Generate hash to detect changes
            local currentHash = HttpService:JSONEncode(currentStock)
            
            -- Only send if data changed
            if currentHash ~= State.lastStockHash then
                log("INFO", "Stock data changed - sending update...")
                
                if sendFreshData(currentStock) then
                    State.lastStockHash = currentHash
                    State.lastUpdate = os.time()
                    State.currentStockData = currentStock
                else
                    State.retryCount = State.retryCount + 1
                    if State.retryCount >= CONFIG.MAX_RETRIES then
                        log("ERROR", "Max retries reached - stopping")
                        State.isRunning = false
                    end
                end
            else
                log("DEBUG", "No stock changes detected")
            end
        else
            log("WARN", "Could not retrieve stock data")
        end
        
        -- Status logging
        cycleCount = cycleCount + 1
        if cycleCount >= 6 then
            local timeSinceActivity = os.time() - State.lastActivity
            local nextAfkIn = math.max(0, State.nextAntiAfk - os.time())
            log("INFO", string.format("Updates: %d | Activity: %ds ago | Next AFK: %ds", 
                State.totalUpdates, timeSinceActivity, nextAfkIn))
            cycleCount = 0
        end
        
        task.wait(CONFIG.UPDATE_INTERVAL)
    end
    
    log("INFO", "Monitoring stopped")
    cleanup()
end

-- INITIALIZE
local function initialize()
    log("INFO", "Initializing Fixed Professional Monitor...")
    
    -- Check if in correct game
    if not ReplicatedStorage:FindFirstChild("Remotes") then
        log("ERROR", "Not in Blox Fruits game!")
        return
    end
    
    -- Setup connections
    setupConnections()
    
    -- Start monitoring
    spawn(function()
        startMonitoring()
    end)
    
    log("SUCCESS", "Fixed Professional Monitor initialized!")
end

-- CONTROL INTERFACE
_G.FixedStockMonitor = {
    stop = function()
        State.isRunning = false
        log("INFO", "Monitor stopped manually")
    end,
    
    restart = function()
        State.isRunning = false
        task.wait(2)
        initialize()
    end,
    
    forceUpdate = function()
        State.lastStockHash = ""
        log("INFO", "Forced update triggered")
    end,
    
    forceAntiAfk = function()
        State.nextAntiAfk = 0
        log("INFO", "Forced anti-AFK triggered")
    end,
    
    clearData = function()
        clearOldData()
        log("INFO", "Manual data clear executed")
    end,
    
    status = function()
        local timeSinceActivity = os.time() - State.lastActivity
        local nextAfkIn = math.max(0, State.nextAntiAfk - os.time())
        local timeSincePing = os.time() - State.lastPing
        
        print("=== FIXED PROFESSIONAL MONITOR STATUS ===")
        print("Running:", State.isRunning)
        print("Total Updates:", State.totalUpdates)
        print("Time Since Activity:", timeSinceActivity, "seconds")
        print("Next Anti-AFK:", nextAfkIn, "seconds")
        print("Last Ping:", timeSincePing, "seconds ago")
        print("Active Connections:", #State.connections)
        print("Session ID:", CONFIG.SESSION_ID:sub(1, 8) .. "...")
        print("========================================")
        return State
    end
}

-- START THE MONITOR
initialize()
log("SUCCESS", "FIXED MONITOR READY - NO DATA STACKING!")
log("INFO", "Anti-AFK system is ACTIVE and WORKING!")
log("INFO", "Use _G.FixedStockMonitor.status() for info")
