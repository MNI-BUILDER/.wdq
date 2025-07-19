local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")

-- Configuration
local CONFIG = {
    API_URL = "https://bfdata.vercel.app/api/stocks/bloxfruits",
    AUTH_HEADER = "GAMERSBERGBLOXFRUITS",
    UPDATE_INTERVAL = 10,
    RETRY_DELAY = 5,
    MAX_RETRIES = 3,
    SESSION_ID = HttpService:GenerateGUID(false),
    
    -- Anti-AFK Settings
    ANTI_AFK_MIN_INTERVAL = 60,
    ANTI_AFK_MAX_INTERVAL = 180,
    MOVEMENT_DISTANCE = 15,
    TOOL_USE_CHANCE = 0.7,
    WALK_DURATION = 3,
    EMERGENCY_AFK_TIME = 1080
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
    emergencyMode = false,
    connections = {}
}

-- Safe Logging Functions
local function notify(title, text, duration)
    local success = pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = tostring(title),
            Text = tostring(text),
            Duration = tonumber(duration) or 5
        })
    end)
    if not success then
        print("Notification failed:", title, text)
    end
end

local function log(level, message)
    local success = pcall(function()
        local timestamp = os.date("%H:%M:%S")
        local logMessage = string.format("[%s] [%s] %s", timestamp, tostring(level), tostring(message))
        print(logMessage)
        
        if level == "ERROR" then
            notify("Monitor Error", message, 8)
        elseif level == "INFO" and (string.find(tostring(message), "started") or string.find(tostring(message), "Anti-AFK")) then
            notify("Monitor", message, 5)
        end
    end)
    if not success then
        print("Log failed:", level, message)
    end
end

-- Safe Movement Functions
local function getRandomWalkDirection()
    local success, result = pcall(function()
        local angles = {0, 45, 90, 135, 180, 225, 270, 315}
        local angle = math.rad(angles[math.random(1, #angles)])
        local distance = math.random(5, CONFIG.MOVEMENT_DISTANCE)
        
        return Vector3.new(
            math.cos(angle) * distance,
            0,
            math.sin(angle) * distance
        )
    end)
    
    if success and result then
        return result
    else
        return Vector3.new(5, 0, 5) -- fallback
    end
end

local function performSafeMovement()
    local success = pcall(function()
        local character = Players.LocalPlayer.Character
        if not character then return false end
        
        local humanoid = character:FindFirstChild("Humanoid")
        local rootPart = character:FindFirstChild("HumanoidRootPart")
        
        if not humanoid or not rootPart then return false end
        
        local movementType = math.random(1, 4)
        
        if movementType == 1 then
            -- Simple walk
            local direction = getRandomWalkDirection()
            local targetPosition = rootPart.Position + direction
            humanoid:MoveTo(targetPosition)
            task.wait(math.random(2, CONFIG.WALK_DURATION))
            humanoid:MoveTo(rootPart.Position)
            log("DEBUG", "Anti-AFK: Walk movement")
            
        elseif movementType == 2 then
            -- Jump movement
            humanoid.Jump = true
            task.wait(1)
            local direction = getRandomWalkDirection()
            humanoid:MoveTo(rootPart.Position + direction)
            task.wait(2)
            log("DEBUG", "Anti-AFK: Jump movement")
            
        elseif movementType == 3 then
            -- Rotation
            local currentCFrame = rootPart.CFrame
            local rotation = math.random(-180, 180)
            rootPart.CFrame = currentCFrame * CFrame.Angles(0, math.rad(rotation), 0)
            task.wait(1)
            log("DEBUG", "Anti-AFK: Rotation")
            
        else
            -- Back and forth
            local startPos = rootPart.Position
            local direction = getRandomWalkDirection()
            humanoid:MoveTo(startPos + direction)
            task.wait(2)
            humanoid:MoveTo(startPos)
            task.wait(1)
            log("DEBUG", "Anti-AFK: Back and forth")
        end
        
        return true
    end)
    
    if not success then
        log("WARN", "Movement failed, using fallback")
        return false
    end
    return true
end

local function useSafeTool()
    local success = pcall(function()
        local character = Players.LocalPlayer.Character
        local backpack = Players.LocalPlayer:FindFirstChild("Backpack")
        
        if not character or not backpack then return false end
        
        local humanoid = character:FindFirstChild("Humanoid")
        if not humanoid then return false end
        
        -- Get available tools
        local tools = {}
        for _, item in pairs(backpack:GetChildren()) do
            if item:IsA("Tool") then
                table.insert(tools, item)
            end
        end
        
        if #tools == 0 then return false end
        
        local tool = tools[math.random(1, #tools)]
        
        -- Equip and use tool safely
        humanoid:EquipTool(tool)
        task.wait(math.random(1, 2))
        
        if tool.Parent == character then
            for i = 1, math.random(2, 4) do
                tool:Activate()
                task.wait(math.random(0.5, 1))
            end
            
            task.wait(math.random(2, 5))
            
            if math.random() > 0.5 then
                humanoid:UnequipTools()
            end
            
            log("DEBUG", "Anti-AFK: Used tool " .. tool.Name)
            return true
        end
        
        return false
    end)
    
    return success
end

local function performAntiAfk()
    local success = pcall(function()
        local currentTime = os.time()
        
        -- Emergency mode check
        if currentTime - State.lastActivity >= CONFIG.EMERGENCY_AFK_TIME then
            log("WARN", "Emergency Anti-AFK activated!")
            notify("Anti-AFK", "Emergency mode!", 8)
            
            for i = 1, 3 do
                performSafeMovement()
                task.wait(1)
                useSafeTool()
                task.wait(2)
            end
            
            State.lastActivity = currentTime
            State.emergencyMode = false
            return
        end
        
        -- Regular anti-AFK
        if currentTime < State.nextAntiAfk then return end
        
        log("INFO", "Performing anti-AFK actions...")
        
        -- Movement
        task.spawn(function()
            performSafeMovement()
        end)
        
        -- Tool usage
        if math.random() <= CONFIG.TOOL_USE_CHANCE then
            task.spawn(function()
                task.wait(math.random(1, 3))
                useSafeTool()
            end)
        end
        
        -- Update timers
        State.lastActivity = currentTime
        State.lastAntiAfk = currentTime
        
        local nextInterval = math.random(CONFIG.ANTI_AFK_MIN_INTERVAL, CONFIG.ANTI_AFK_MAX_INTERVAL)
        State.nextAntiAfk = currentTime + nextInterval
        
        log("INFO", string.format("Next anti-AFK in %d seconds", nextInterval))
    end)
    
    if not success then
        log("ERROR", "Anti-AFK failed")
    end
end

-- Data Management Functions
local function validateStockData(stockData)
    if not stockData or type(stockData) ~= "table" then
        return false
    end
    
    if not stockData.normal or not stockData.mirage then
        return false
    end
    
    return true
end

local function formatFruitData(fruits)
    local success, result = pcall(function()
        local formattedFruits = {}
        
        if not fruits or type(fruits) ~= "table" then
            return formattedFruits
        end
        
        for _, fruit in pairs(fruits) do
            if fruit and type(fruit) == "table" and fruit.OnSale and fruit.Name and fruit.Price then
                table.insert(formattedFruits, {
                    name = tostring(fruit.Name),
                    price = tonumber(fruit.Price) or 0,
                    onSale = true
                })
            end
        end
        
        return formattedFruits
    end)
    
    if success and result then
        return result
    else
        log("WARN", "Failed to format fruit data")
        return {}
    end
end

local function generateStockHash(stockData)
    local success, result = pcall(function()
        if not validateStockData(stockData) then
            return ""
        end
        
        local hashString = ""
        for stockType, fruits in pairs(stockData) do
            if fruits and type(fruits) == "table" then
                for _, fruit in pairs(fruits) do
                    if fruit and fruit.OnSale and fruit.Name and fruit.Price then
                        hashString = hashString .. tostring(fruit.Name) .. tostring(fruit.Price)
                    end
                end
            end
        end
        
        return hashString
    end)
    
    if success and result then
        return result
    else
        return ""
    end
end

-- API Functions with Data Cleanup
local function makeAPIRequest(method, data)
    local success, response = pcall(function()
        local requestData = {
            Url = CONFIG.API_URL,
            Method = tostring(method) or "GET",
            Headers = {
                ["Authorization"] = CONFIG.AUTH_HEADER,
                ["Content-Type"] = "application/json",
                ["X-Session-ID"] = CONFIG.SESSION_ID,
                ["X-Replace-Data"] = "true" -- Signal to replace, not append
            }
        }
        
        if data and (method == "POST" or method == "PUT") then
            requestData.Body = HttpService:JSONEncode(data)
        end
        
        local request = http_request or request or (syn and syn.request)
        if not request then
            error("No HTTP request function available")
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

local function cleanupOldData()
    local success = pcall(function()
        -- Delete old session data first
        makeAPIRequest("DELETE", {
            sessionId = CONFIG.SESSION_ID,
            action = "cleanup_old_data",
            timestamp = os.time()
        })
    end)
    
    if success then
        log("DEBUG", "Old data cleanup requested")
    end
end

local function sendStockData(stockData)
    local success, result = pcall(function()
        if not validateStockData(stockData) then
            log("WARN", "Invalid stock data, skipping send")
            return false
        end
        
        local normalStock = formatFruitData(stockData.normal)
        local mirageStock = formatFruitData(stockData.mirage)
        
        -- Clean old data first
        cleanupOldData()
        
        -- Prepare new data payload
        local payload = {
            sessionId = CONFIG.SESSION_ID,
            timestamp = os.time(),
            normalStock = normalStock,
            mirageStock = mirageStock,
            playerName = tostring(Players.LocalPlayer.Name),
            serverId = tostring(game.JobId or "unknown"),
            totalFruits = #normalStock + #mirageStock,
            antiAfkActive = true,
            replaceData = true -- Ensure data replacement
        }
        
        local apiSuccess, responseBody = makeAPIRequest("POST", payload)
        
        if apiSuccess then
            State.totalUpdates = State.totalUpdates + 1
            log("INFO", string.format("Stock data replaced - Normal: %d, Mirage: %d", #normalStock, #mirageStock))
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
    end)
    
    if success and result then
        return result
    else
        log("ERROR", "Failed to send stock data")
        return false
    end
end

local function cleanupSession()
    local success = pcall(function()
        if not State.sessionActive then return end
        
        log("INFO", "Cleaning up session...")
        
        -- Send cleanup request
        makeAPIRequest("DELETE", {
            sessionId = CONFIG.SESSION_ID,
            reason = "client_disconnect",
            timestamp = os.time(),
            cleanupAll = true
        })
        
        State.sessionActive = false
    end)
    
    if success then
        log("INFO", "Session cleanup completed")
    else
        log("WARN", "Session cleanup failed")
    end
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
        
        local normalStock = CommF:InvokeServer("GetFruits", false)
        local mirageStock = CommF:InvokeServer("GetFruits", true)
        
        return {
            normal = normalStock,
            mirage = mirageStock
        }
    end)
    
    if success and result then
        return result
    else
        log("ERROR", "Failed to get stock: " .. tostring(result))
        return nil
    end
end

-- Safe Setup Functions
local function setupClientFeatures()
    local success = pcall(function()
        -- Initialize anti-AFK timing
        local currentTime = os.time()
        State.lastActivity = currentTime
        State.nextAntiAfk = currentTime + math.random(CONFIG.ANTI_AFK_MIN_INTERVAL, CONFIG.ANTI_AFK_MAX_INTERVAL)
        
        -- Teleport handling
        local teleportConnection = Players.LocalPlayer.OnTeleport:Connect(function(state)
            if state == Enum.TeleportState.Failed then
                log("WARN", "Teleport failed - rejoining...")
                cleanupSession()
                task.wait(3)
                TeleportService:Teleport(game.PlaceId, Players.LocalPlayer)
            end
        end)
        table.insert(State.connections, teleportConnection)
        
        -- Window focus optimization
        local focusLostConnection = UserInputService.WindowFocusReleased:Connect(function()
            RunService:Set3dRenderingEnabled(false)
        end)
        table.insert(State.connections, focusLostConnection)
        
        local focusGainedConnection = UserInputService.WindowFocused:Connect(function()
            RunService:Set3dRenderingEnabled(true)
        end)
        table.insert(State.connections, focusGainedConnection)
        
        log("INFO", "Client features initialized")
    end)
    
    if not success then
        log("WARN", "Some client features failed to initialize")
    end
end

local function setupCleanupHandlers()
    local success = pcall(function()
        -- Connection monitor
        local heartbeatConnection = RunService.Heartbeat:Connect(function()
            if not game:IsLoaded() or not Players.LocalPlayer.Parent then
                log("WARN", "Disconnected - cleaning up")
                cleanupSession()
                
                -- Disconnect all connections
                for _, connection in pairs(State.connections) do
                    if connection then
                        connection:Disconnect()
                    end
                end
                State.connections = {}
            end
        end)
        table.insert(State.connections, heartbeatConnection)
        
        log("INFO", "Cleanup handlers initialized")
    end)
    
    if not success then
        log("WARN", "Cleanup handlers failed to initialize")
    end
end

-- Main Loop
local function startMonitoring()
    local success = pcall(function()
        State.isRunning = true
        State.lastUpdate = os.time()
        
        log("INFO", "Error-Free Stock Monitor started")
        log("INFO", "Player: " .. tostring(Players.LocalPlayer.Name))
        notify("Stock Monitor", "Started with data cleanup!", 5)
        
        -- Test API connection
        local apiSuccess, _ = makeAPIRequest("GET")
        if apiSuccess then
            log("INFO", "API connected successfully")
        else
            log("WARN", "API connection failed - will retry")
        end
        
        local updateCount = 0
        
        while State.isRunning do
            -- Perform anti-AFK
            performAntiAfk()
            
            -- Get and send stock data
            local stockData = getFruitStock()
            
            if stockData and validateStockData(stockData) then
                local currentHash = generateStockHash(stockData)
                local timeSinceUpdate = os.time() - State.lastUpdate
                
                -- Send if data changed or forced update
                if currentHash ~= State.lastStockHash or timeSinceUpdate >= 60 then
                    if sendStockData(stockData) then
                        State.lastStockHash = currentHash
                        State.lastUpdate = os.time()
                    end
                else
                    log("DEBUG", "No stock changes detected")
                end
            else
                log("WARN", "Could not get valid stock data")
            end
            
            -- Status logging
            updateCount = updateCount + 1
            if updateCount >= 6 then
                local timeSinceActivity = os.time() - State.lastActivity
                local nextAfkIn = math.max(0, State.nextAntiAfk - os.time())
                log("INFO", string.format("Updates: %d | Activity: %ds ago | Next AFK: %ds", 
                    State.totalUpdates, timeSinceActivity, nextAfkIn))
                updateCount = 0
            end
            
            task.wait(CONFIG.UPDATE_INTERVAL)
        end
        
        log("INFO", "Monitoring stopped")
        cleanupSession()
    end)
    
    if not success then
        log("ERROR", "Critical error in main loop")
        cleanupSession()
    end
end

-- Initialize
local function initialize()
    local success = pcall(function()
        log("INFO", "Initializing Error-Free Monitor...")
        
        -- Validate game
        if not ReplicatedStorage:FindFirstChild("Remotes") then
            log("ERROR", "Not in Blox Fruits game!")
            notify("Error", "Wrong game detected!", 10)
            return
        end
        
        -- Setup features
        setupClientFeatures()
        setupCleanupHandlers()
        
        -- Start monitoring
        task.spawn(startMonitoring)
        
        log("INFO", "Initialization completed successfully")
    end)
    
    if not success then
        log("ERROR", "Initialization failed")
        notify("Error", "Failed to start monitor", 10)
    end
end

-- Manual Controls
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
        local nextAfkIn = math.max(0, State.nextAntiAfk - os.time())
        
        print("=== Stock Monitor Status ===")
        print("Running:", State.isRunning)
        print("Updates sent:", State.totalUpdates)
        print("Time since activity:", timeSinceActivity, "seconds")
        print("Next Anti-AFK in:", nextAfkIn, "seconds")
        print("Session ID:", CONFIG.SESSION_ID:sub(1, 8) .. "...")
        print("Connections:", #State.connections)
        return State
    end,
    
    cleanup = function()
        cleanupSession()
        log("INFO", "Manual cleanup completed")
    end,
    
    testAntiAfk = function()
        State.nextAntiAfk = 0
        log("INFO", "Anti-AFK test triggered")
    end
}

-- Start the monitor
initialize()
log("INFO", "Monitor ready! No data stacking - old data gets replaced!")
log("INFO", "Use _G.StockMonitor.status() for detailed info")
