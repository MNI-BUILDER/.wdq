local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")

-- Configuration
local CONFIG = {
    API_URL = "https://bloxfritushit.vercel.app/api/stocks/bloxfruits",
    AUTH_HEADER = "GAMERSBERG",
    UPDATE_INTERVAL = 10,
    RETRY_DELAY = 5,
    MAX_RETRIES = 3,
    SESSION_ID = HttpService:GenerateGUID(false),
    
    -- Enhanced Anti-AFK Settings
    ANTI_AFK_MIN_INTERVAL = 60,  -- 1 minute minimum
    ANTI_AFK_MAX_INTERVAL = 180, -- 3 minutes maximum
    MOVEMENT_DISTANCE = 15,      -- increased movement range
    TOOL_USE_CHANCE = 0.7,       -- 70% chance to use tool
    WALK_DURATION = 3,           -- seconds to walk
    EMERGENCY_AFK_TIME = 1080    -- 18 minutes (before 20min kick)
}

-- State Management
local State = {
    isRunning = false,
    lastUpdate = 0,
    retryCount = 0,
    sessionActive = true,
    lastStockHash = "",
    totalUpdates = 0,
    lastAntiAfk = 0,
    nextAntiAfk = 0,
    lastActivity = os.time(),
    emergencyMode = false
}

-- Client-side Logging Functions
local function notify(title, text, duration)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title,
            Text = text,
            Duration = duration or 5
        })
    end)
end

local function log(level, message)
    local timestamp = os.date("%H:%M:%S")
    local logMessage = string.format("[%s] [%s] %s", timestamp, level, message)
    
    print(logMessage)
    
    if level == "ERROR" then
        notify("Stock Monitor Error", message, 8)
    elseif level == "INFO" and (string.find(message, "started") or string.find(message, "Anti-AFK")) then
        notify("Anti-AFK", message, 5)
    end
end

-- Enhanced Anti-AFK System
local function getRandomWalkDirection()
    local angles = {0, 45, 90, 135, 180, 225, 270, 315}
    local angle = math.rad(angles[math.random(1, #angles)])
    local distance = math.random(5, CONFIG.MOVEMENT_DISTANCE)
    
    return Vector3.new(
        math.cos(angle) * distance,
        0,
        math.sin(angle) * distance
    )
end

local function performWalkMovement()
    local character = Players.LocalPlayer.Character
    if not character then return false end
    
    local humanoid = character:FindFirstChild("Humanoid")
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    
    if not humanoid or not rootPart then return false end
    
    -- Get current position
    local currentPosition = rootPart.Position
    local walkDirection = getRandomWalkDirection()
    local targetPosition = currentPosition + walkDirection
    
    -- Start walking
    humanoid:MoveTo(targetPosition)
    log("DEBUG", string.format("Walking to position: %.1f, %.1f, %.1f", 
        targetPosition.X, targetPosition.Y, targetPosition.Z))
    
    -- Walk for random duration
    local walkTime = math.random(2, CONFIG.WALK_DURATION)
    task.wait(walkTime)
    
    -- Stop walking by moving to current position
    humanoid:MoveTo(rootPart.Position)
    
    return true
end

local function performComplexMovement()
    local character = Players.LocalPlayer.Character
    if not character then return false end
    
    local humanoid = character:FindFirstChild("Humanoid")
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    
    if not humanoid or not rootPart then return false end
    
    local movementType = math.random(1, 6)
    
    if movementType == 1 then
        -- Walk in a small circle
        local center = rootPart.Position
        for i = 1, 8 do
            local angle = (i / 8) * math.pi * 2
            local offset = Vector3.new(math.cos(angle) * 5, 0, math.sin(angle) * 5)
            humanoid:MoveTo(center + offset)
            task.wait(0.5)
        end
        log("DEBUG", "Anti-AFK: Circular walk completed")
        
    elseif movementType == 2 then
        -- Walk back and forth
        local startPos = rootPart.Position
        local direction = getRandomWalkDirection()
        
        humanoid:MoveTo(startPos + direction)
        task.wait(2)
        humanoid:MoveTo(startPos - direction)
        task.wait(2)
        humanoid:MoveTo(startPos)
        log("DEBUG", "Anti-AFK: Back and forth walk")
        
    elseif movementType == 3 then
        -- Jump while walking
        performWalkMovement()
        task.wait(0.5)
        humanoid.Jump = true
        task.wait(1)
        humanoid.Jump = true
        log("DEBUG", "Anti-AFK: Jump walk")
        
    elseif movementType == 4 then
        -- Spin and walk
        local currentCFrame = rootPart.CFrame
        for i = 1, 4 do
            rootPart.CFrame = currentCFrame * CFrame.Angles(0, math.rad(90 * i), 0)
            task.wait(0.3)
        end
        performWalkMovement()
        log("DEBUG", "Anti-AFK: Spin and walk")
        
    elseif movementType == 5 then
        -- Random direction changes
        for i = 1, 5 do
            local direction = getRandomWalkDirection()
            humanoid:MoveTo(rootPart.Position + direction)
            task.wait(math.random(1, 2))
        end
        log("DEBUG", "Anti-AFK: Random direction walk")
        
    else
        -- Simple walk
        performWalkMovement()
        log("DEBUG", "Anti-AFK: Simple walk")
    end
    
    return true
end

local function getAllTools()
    local tools = {}
    local backpack = Players.LocalPlayer:FindFirstChild("Backpack")
    local character = Players.LocalPlayer.Character
    
    -- Get tools from backpack
    if backpack then
        for _, item in pairs(backpack:GetChildren()) do
            if item:IsA("Tool") then
                table.insert(tools, item)
            end
        end
    end
    
    -- Get equipped tools
    if character then
        for _, item in pairs(character:GetChildren()) do
            if item:IsA("Tool") then
                table.insert(tools, item)
            end
        end
    end
    
    return tools
end

local function useToolAdvanced()
    local tools = getAllTools()
    if #tools == 0 then 
        log("DEBUG", "No tools available")
        return false 
    end
    
    local character = Players.LocalPlayer.Character
    if not character then return false end
    
    local humanoid = character:FindFirstChild("Humanoid")
    if not humanoid then return false end
    
    -- Select random tool
    local tool = tools[math.random(1, #tools)]
    
    pcall(function()
        -- Equip tool if not already equipped
        if tool.Parent ~= character then
            humanoid:EquipTool(tool)
            task.wait(math.random(1, 2))
        end
        
        if tool.Parent == character then
            log("DEBUG", "Using tool: " .. tool.Name)
            
            -- Use tool multiple times with movement
            for i = 1, math.random(2, 5) do
                tool:Activate()
                task.wait(math.random(0.5, 1.5))
                
                -- Sometimes move while using tool
                if math.random() > 0.5 then
                    local humanoid = character:FindFirstChild("Humanoid")
                    local rootPart = character:FindFirstChild("HumanoidRootPart")
                    if humanoid and rootPart then
                        local moveDir = getRandomWalkDirection()
                        humanoid:MoveTo(rootPart.Position + moveDir * 0.3)
                    end
                end
            end
            
            -- Keep tool equipped for a bit longer
            task.wait(math.random(3, 8))
            
            -- Sometimes unequip, sometimes keep it
            if math.random() > 0.3 then
                humanoid:UnequipTools()
                log("DEBUG", "Unequipped " .. tool.Name)
            else
                log("DEBUG", "Keeping " .. tool.Name .. " equipped")
            end
        end
    end)
    
    return true
end

local function emergencyAntiAfk()
    log("WARN", "Emergency Anti-AFK activated!")
    notify("Anti-AFK", "Emergency mode activated!", 8)
    
    -- Perform multiple actions rapidly
    for i = 1, 3 do
        performComplexMovement()
        task.wait(1)
        useToolAdvanced()
        task.wait(2)
    end
    
    -- Reset activity timer
    State.lastActivity = os.time()
    State.emergencyMode = false
    log("INFO", "Emergency Anti-AFK completed")
end

local function performAntiAfk()
    local currentTime = os.time()
    
    -- Check for emergency mode (18+ minutes of inactivity)
    if currentTime - State.lastActivity >= CONFIG.EMERGENCY_AFK_TIME then
        State.emergencyMode = true
        emergencyAntiAfk()
        return
    end
    
    -- Regular anti-AFK check
    if currentTime < State.nextAntiAfk then return end
    
    log("INFO", "Performing enhanced anti-AFK...")
    
    -- Perform complex movement
    task.spawn(function()
        performComplexMovement()
    end)
    
    -- Use tools after movement
    task.spawn(function()
        task.wait(math.random(2, 5))
        if math.random() <= CONFIG.TOOL_USE_CHANCE then
            useToolAdvanced()
        end
    end)
    
    -- Update activity tracking
    State.lastActivity = currentTime
    State.lastAntiAfk = currentTime
    
    -- Set next anti-AFK time
    local nextInterval = math.random(CONFIG.ANTI_AFK_MIN_INTERVAL, CONFIG.ANTI_AFK_MAX_INTERVAL)
    State.nextAntiAfk = currentTime + nextInterval
    
    local timeUntilEmergency = CONFIG.EMERGENCY_AFK_TIME - (currentTime - State.lastActivity)
    log("INFO", string.format("Next anti-AFK: %ds | Emergency in: %ds", 
        nextInterval, math.max(0, timeUntilEmergency)))
end

-- Utility Functions
local function generateStockHash(stockData)
    local hashString = ""
    for stockType, fruits in pairs(stockData) do
        if fruits then
            for _, fruit in pairs(fruits) do
                if fruit and fruit.OnSale then
                    hashString = hashString .. tostring(fruit.Name) .. tostring(fruit.Price)
                end
            end
        end
    end
    return hashString
end

local function formatFruitData(fruits)
    local formattedFruits = {}
    if not fruits then return formattedFruits end
    
    for _, fruit in pairs(fruits) do
        if fruit and fruit.OnSale and fruit.Name and fruit.Price then
            table.insert(formattedFruits, {
                name = tostring(fruit.Name),
                price = tonumber(fruit.Price),
                onSale = true
            })
        end
    end
    return formattedFruits
end

-- Client-side HTTP Request Function
local function makeAPIRequest(method, data)
    local success, response = pcall(function()
        local requestData = {
            Url = CONFIG.API_URL,
            Method = method or "GET",
            Headers = {
                ["Authorization"] = CONFIG.AUTH_HEADER,
                ["Content-Type"] = "application/json",
                ["X-Session-ID"] = CONFIG.SESSION_ID
            }
        }
        
        if data and (method == "POST" or method == "PUT") then
            requestData.Body = HttpService:JSONEncode(data)
        end
        
        local request = http_request or request or syn and syn.request
        if not request then
            log("ERROR", "No HTTP request function available")
            return nil
        end
        
        return request(requestData)
    end)
    
    if success and response then
        if response.StatusCode and response.StatusCode >= 200 and response.StatusCode < 300 then
            State.retryCount = 0
            return true, response.Body
        else
            log("ERROR", "API request failed - Status: " .. tostring(response.StatusCode or "Unknown"))
            return false, response.Body
        end
    else
        log("ERROR", "HTTP request failed: " .. tostring(response))
        return false, nil
    end
end

local function sendStockData(stockData)
    local normalStock = formatFruitData(stockData.normal)
    local mirageStock = formatFruitData(stockData.mirage)
    
    local payload = {
        sessionId = CONFIG.SESSION_ID,
        timestamp = os.time(),
        normalStock = normalStock,
        mirageStock = mirageStock,
        playerName = Players.LocalPlayer.Name,
        serverId = game.JobId or "unknown",
        totalFruits = #normalStock + #mirageStock,
        antiAfkActive = true
    }
    
    local success, responseBody = makeAPIRequest("POST", payload)
    
    if success then
        State.totalUpdates = State.totalUpdates + 1
        log("INFO", string.format("Stock sent - Normal: %d, Mirage: %d", #normalStock, #mirageStock))
        return true
    else
        State.retryCount = State.retryCount + 1
        log("WARN", string.format("Send failed (%d/%d)", State.retryCount, CONFIG.MAX_RETRIES))
        
        if State.retryCount >= CONFIG.MAX_RETRIES then
            log("ERROR", "Max retries reached - stopping")
            State.isRunning = false
        end
        return false
    end
end

local function cleanupSession()
    if not State.sessionActive then return end
    
    log("INFO", "Cleaning up session...")
    pcall(function()
        makeAPIRequest("DELETE", {
            sessionId = CONFIG.SESSION_ID,
            reason = "client_disconnect"
        })
    end)
    State.sessionActive = false
end

-- Game Data Functions
local function getFruitStock()
    local success, result = pcall(function()
        local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
        if not remotes then
            error("Remotes not found")
        end
        
        local CommF = remotes:WaitForChild("CommF_", 10)
        if not CommF then
            error("CommF_ not found")
        end
        
        return {
            normal = CommF:InvokeServer("GetFruits", false),
            mirage = CommF:InvokeServer("GetFruits", true)
        }
    end)
    
    if success and result then
        return result
    else
        log("ERROR", "Failed to get stock: " .. tostring(result))
        return nil
    end
end

-- Client-side Features
local function setupClientFeatures()
    -- Initialize anti-AFK timing
    local currentTime = os.time()
    State.lastActivity = currentTime
    State.nextAntiAfk = currentTime + math.random(CONFIG.ANTI_AFK_MIN_INTERVAL, CONFIG.ANTI_AFK_MAX_INTERVAL)
    log("INFO", "Enhanced Anti-AFK system initialized")
    
    -- Handle teleport failures
    pcall(function()
        Players.LocalPlayer.OnTeleport:Connect(function(state)
            if state == Enum.TeleportState.Failed then
                log("WARN", "Teleport failed - rejoining...")
                cleanupSession()
                task.wait(3)
                TeleportService:Teleport(game.PlaceId, Players.LocalPlayer)
            end
        end)
    end)
    
    -- Window focus optimization
    pcall(function()
        UserInputService.WindowFocusReleased:Connect(function()
            RunService:Set3dRenderingEnabled(false)
        end)
        
        UserInputService.WindowFocused:Connect(function()
            RunService:Set3dRenderingEnabled(true)
        end)
    end)
end

-- Client-side Cleanup
local function setupCleanupHandlers()
    local heartbeatConnection
    heartbeatConnection = RunService.Heartbeat:Connect(function()
        if not game:IsLoaded() or not Players.LocalPlayer.Parent then
            log("WARN", "Disconnected - cleaning up")
            cleanupSession()
            if heartbeatConnection then
                heartbeatConnection:Disconnect()
            end
        end
    end)
    
    pcall(function()
        Players.PlayerRemoving:Connect(function(player)
            if player == Players.LocalPlayer then
                cleanupSession()
            end
        end)
    end)
end

-- Main Loop
local function startMonitoring()
    State.isRunning = true
    State.lastUpdate = os.time()
    
    log("INFO", "Enhanced Stock Monitor with Advanced Anti-AFK started")
    log("INFO", "Player: " .. Players.LocalPlayer.Name)
    notify("Stock Monitor", "Enhanced Anti-AFK Active!", 5)
    
    local success, _ = makeAPIRequest("GET")
    if success then
        log("INFO", "API connected")
    else
        log("WARN", "API connection failed")
    end
    
    local updateCount = 0
    
    while State.isRunning do
        -- Perform enhanced anti-AFK check
        performAntiAfk()
        
        -- Get and send stock data
        local stockData = getFruitStock()
        
        if stockData then
            local currentHash = generateStockHash(stockData)
            local timeSinceUpdate = os.time() - State.lastUpdate
            
            if currentHash ~= State.lastStockHash or timeSinceUpdate >= 60 then
                if sendStockData(stockData) then
                    State.lastStockHash = currentHash
                    State.lastUpdate = os.time()
                end
            else
                log("DEBUG", "No changes detected")
            end
        else
            log("WARN", "Could not get stock data")
        end
        
        updateCount = updateCount + 1
        if updateCount >= 6 then
            local nextAfkIn = State.nextAntiAfk - os.time()
            local timeSinceActivity = os.time() - State.lastActivity
            log("INFO", string.format("Updates: %d | Next Anti-AFK: %ds | Activity: %ds ago", 
                State.totalUpdates, math.max(0, nextAfkIn), timeSinceActivity))
            updateCount = 0
        end
        
        task.wait(CONFIG.UPDATE_INTERVAL)
    end
    
    log("INFO", "Monitor stopped")
    cleanupSession()
end

-- Initialize
local function initialize()
    log("INFO", "Initializing Enhanced Stock Monitor...")
    
    if not ReplicatedStorage:FindFirstChild("Remotes") then
        log("ERROR", "Not in Blox Fruits game!")
        notify("Error", "Wrong game!", 10)
        return
    end
    
    setupClientFeatures()
    setupCleanupHandlers()
    
    task.spawn(startMonitoring)
end

-- Manual controls
_G.StockMonitor = {
    stop = function()
        State.isRunning = false
        log("INFO", "Manually stopped")
    end,
    
    restart = function()
        State.isRunning = false
        task.wait(2)
        initialize()
    end,
    
    status = function()
        local timeSinceActivity = os.time() - State.lastActivity
        local nextAfkIn = State.nextAntiAfk - os.time()
        
        print("Running:", State.isRunning)
        print("Updates:", State.totalUpdates)
        print("Time since activity:", timeSinceActivity, "seconds")
        print("Next Anti-AFK in:", math.max(0, nextAfkIn), "seconds")
        print("Emergency mode:", State.emergencyMode)
        print("Session:", CONFIG.SESSION_ID:sub(1, 8))
        return State
    end,
    
    forceAntiAfk = function()
        State.nextAntiAfk = 0
        log("INFO", "Forced anti-AFK trigger")
    end,
    
    emergencyTest = function()
        emergencyAntiAfk()
        log("INFO", "Emergency anti-AFK test completed")
    end
}

-- Start everything
initialize()
log("INFO", "Enhanced Anti-AFK prevents 20min kick!")
log("INFO", "Use _G.StockMonitor.emergencyTest() to test emergency mode")
