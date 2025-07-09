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
    
    -- Anti-AFK Settings
    ANTI_AFK_MIN_INTERVAL = 120, -- 2 minutes minimum
    ANTI_AFK_MAX_INTERVAL = 300, -- 5 minutes maximum
    MOVEMENT_DISTANCE = 5, -- studs to move
    TOOL_USE_CHANCE = 0.3 -- 30% chance to use tool
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
    nextAntiAfk = 0
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
    elseif level == "INFO" and (string.find(message, "started") or string.find(message, "successful")) then
        notify("Stock Monitor", message, 5)
    end
end

-- Advanced Anti-AFK System
local function getRandomMovementVector()
    local angle = math.random() * math.pi * 2
    local distance = math.random(2, CONFIG.MOVEMENT_DISTANCE)
    return Vector3.new(
        math.cos(angle) * distance,
        0,
        math.sin(angle) * distance
    )
end

local function getRandomTool()
    local backpack = Players.LocalPlayer:FindFirstChild("Backpack")
    if not backpack then return nil end
    
    local tools = {}
    for _, item in pairs(backpack:GetChildren()) do
        if item:IsA("Tool") then
            table.insert(tools, item)
        end
    end
    
    if #tools > 0 then
        return tools[math.random(1, #tools)]
    end
    return nil
end

local function performNaturalMovement()
    local character = Players.LocalPlayer.Character
    if not character then return false end
    
    local humanoid = character:FindFirstChild("Humanoid")
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    
    if not humanoid or not rootPart then return false end
    
    -- Random movement pattern
    local movementType = math.random(1, 4)
    
    if movementType == 1 then
        -- Small walk in random direction
        local moveVector = getRandomMovementVector()
        local targetPosition = rootPart.Position + moveVector
        humanoid:MoveTo(targetPosition)
        log("DEBUG", "Anti-AFK: Walking to new position")
        
    elseif movementType == 2 then
        -- Jump in place
        humanoid.Jump = true
        log("DEBUG", "Anti-AFK: Jumping")
        
    elseif movementType == 3 then
        -- Turn around (rotate)
        local currentCFrame = rootPart.CFrame
        local randomRotation = math.random(-180, 180)
        rootPart.CFrame = currentCFrame * CFrame.Angles(0, math.rad(randomRotation), 0)
        log("DEBUG", "Anti-AFK: Rotating")
        
    elseif movementType == 4 then
        -- Crouch (if possible)
        pcall(function()
            humanoid.PlatformStand = true
            task.wait(0.5)
            humanoid.PlatformStand = false
        end)
        log("DEBUG", "Anti-AFK: Crouching")
    end
    
    return true
end

local function useRandomTool()
    if math.random() > CONFIG.TOOL_USE_CHANCE then return false end
    
    local tool = getRandomTool()
    if not tool then return false end
    
    local character = Players.LocalPlayer.Character
    if not character then return false end
    
    local humanoid = character:FindFirstChild("Humanoid")
    if not humanoid then return false end
    
    pcall(function()
        -- Equip tool
        humanoid:EquipTool(tool)
        log("DEBUG", "Anti-AFK: Equipped " .. tool.Name)
        
        -- Wait a bit then activate it
        task.wait(math.random(1, 3))
        
        if tool.Parent == character then
            tool:Activate()
            log("DEBUG", "Anti-AFK: Used " .. tool.Name)
            
            -- Wait then unequip
            task.wait(math.random(2, 5))
            humanoid:UnequipTools()
            log("DEBUG", "Anti-AFK: Unequipped tool")
        end
    end)
    
    return true
end

local function performAntiAfk()
    local currentTime = os.time()
    
    -- Check if it's time for anti-AFK
    if currentTime < State.nextAntiAfk then return end
    
    log("INFO", "Performing anti-AFK actions...")
    
    -- Perform movement
    local movementSuccess = performNaturalMovement()
    
    -- Sometimes use a tool
    task.spawn(function()
        task.wait(math.random(1, 3)) -- Random delay
        useRandomTool()
    end)
    
    -- Update timing for next anti-AFK
    State.lastAntiAfk = currentTime
    local nextInterval = math.random(CONFIG.ANTI_AFK_MIN_INTERVAL, CONFIG.ANTI_AFK_MAX_INTERVAL)
    State.nextAntiAfk = currentTime + nextInterval
    
    log("INFO", string.format("Next anti-AFK in %d seconds", nextInterval))
    
    return movementSuccess
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
        totalFruits = #normalStock + #mirageStock
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

-- Client-side Features (UPDATED)
local function setupClientFeatures()
    -- Initialize anti-AFK timing
    local currentTime = os.time()
    State.nextAntiAfk = currentTime + math.random(CONFIG.ANTI_AFK_MIN_INTERVAL, CONFIG.ANTI_AFK_MAX_INTERVAL)
    log("INFO", "Anti-AFK system initialized")
    
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
    
    log("INFO", "Stock Monitor with Advanced Anti-AFK started")
    log("INFO", "Player: " .. Players.LocalPlayer.Name)
    notify("Stock Monitor", "Started with Anti-AFK!", 5)
    
    local success, _ = makeAPIRequest("GET")
    if success then
        log("INFO", "API connected")
    else
        log("WARN", "API connection failed")
    end
    
    local updateCount = 0
    
    while State.isRunning do
        -- Perform anti-AFK check
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
            log("INFO", string.format("Updates: %d | Next Anti-AFK: %ds", 
                State.totalUpdates, math.max(0, nextAfkIn)))
            updateCount = 0
        end
        
        task.wait(CONFIG.UPDATE_INTERVAL)
    end
    
    log("INFO", "Monitor stopped")
    cleanupSession()
end

-- Initialize
local function initialize()
    log("INFO", "Initializing Advanced Stock Monitor...")
    
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
        print("Running:", State.isRunning)
        print("Updates:", State.totalUpdates)
        print("Next Anti-AFK:", State.nextAntiAfk - os.time(), "seconds")
        print("Session:", CONFIG.SESSION_ID:sub(1, 8))
        return State
    end,
    
    forceAntiAfk = function()
        State.nextAntiAfk = 0
        log("INFO", "Forced anti-AFK trigger")
    end
}

-- Start everything
initialize()
log("INFO", "Use _G.StockMonitor.forceAntiAfk() to test anti-AFK")
