local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")

-- Updated Professional Configuration
local CONFIG = {
    API_URL = "https://bloxfritushit.vercel.app/api/stocks/bloxfruits",
    AUTH_HEADER = "GAMERSBERG",
    UPDATE_INTERVAL = 10,
    RETRY_DELAY = 3,
    MAX_RETRIES = 5,
    SESSION_ID = HttpService:GenerateGUID(false),
    CLEANUP_TIMEOUT = 5,
    
    -- Anti-AFK Professional Settings
    ANTI_AFK_MIN_INTERVAL = 45,
    ANTI_AFK_MAX_INTERVAL = 120,
    MOVEMENT_DISTANCE = 12,
    TOOL_USE_CHANCE = 0.8,
    WALK_DURATION = 4,
    EMERGENCY_AFK_TIME = 900 -- 15 minutes
}

-- Professional State Management
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
    connections = {},
    dataCleanupInProgress = false,
    lastCleanupTime = 0,
    apiHealthy = false
}

-- Professional Logging System
local function safeNotify(title, text, duration)
    spawn(function()
        pcall(function()
            StarterGui:SetCore("SendNotification", {
                Title = "[NEW API] " .. tostring(title),
                Text = tostring(text),
                Duration = tonumber(duration) or 5
            })
        end)
    end)
end

local function professionalLog(level, message, showNotification)
    spawn(function()
        pcall(function()
            local timestamp = os.date("%H:%M:%S")
            local sessionShort = CONFIG.SESSION_ID:sub(1, 6)
            local logMessage = string.format("[%s][%s][%s] %s", timestamp, sessionShort, tostring(level), tostring(message))
            
            print(logMessage)
            
            if showNotification and (level == "ERROR" or level == "CRITICAL") then
                safeNotify("System " .. level, message, 10)
            elseif showNotification and level == "SUCCESS" then
                safeNotify("Success", message, 3)
            end
        end)
    end)
end

-- API Health Check System
local function checkApiHealth()
    local success, result = pcall(function()
        professionalLog("INFO", "Checking new API health...")
        
        local request = http_request or request or (syn and syn.request)
        if not request then
            return false, "No HTTP request function"
        end
        
        local response = request({
            Url = CONFIG.API_URL,
            Method = "GET",
            Headers = {
                ["Authorization"] = CONFIG.AUTH_HEADER,
                ["Content-Type"] = "application/json",
                ["X-Health-Check"] = "true"
            }
        })
        
        if response and response.StatusCode then
            if response.StatusCode == 200 then
                State.apiHealthy = true
                professionalLog("SUCCESS", "New API is healthy and responding", true)
                return true, "API healthy"
            elseif response.StatusCode == 404 then
                State.apiHealthy = false
                professionalLog("WARN", "API endpoint not found (404) - may still be setting up")
                return false, "Endpoint not found"
            else
                State.apiHealthy = false
                professionalLog("WARN", "API returned status: " .. tostring(response.StatusCode))
                return false, "API error: " .. tostring(response.StatusCode)
            end
        else
            State.apiHealthy = false
            return false, "No response from API"
        end
    end)
    
    if success then
        return result
    else
        State.apiHealthy = false
        professionalLog("ERROR", "Health check failed: " .. tostring(result))
        return false, tostring(result)
    end
end

-- Enhanced Data Cleanup for New API
local function executeDataCleanup()
    if State.dataCleanupInProgress then
        professionalLog("WARN", "Cleanup already in progress, skipping")
        return false
    end
    
    State.dataCleanupInProgress = true
    local cleanupSuccess = false
    
    pcall(function()
        professionalLog("INFO", "Starting complete data cleanup on new API...")
        
        local deletePayload = {
            action = "PURGE_SESSION",
            sessionId = CONFIG.SESSION_ID,
            timestamp = os.time(),
            force = true,
            apiVersion = "NEW"
        }
        
        local request = http_request or request or (syn and syn.request)
        if request then
            local deleteResponse = request({
                Url = CONFIG.API_URL,
                Method = "DELETE",
                Headers = {
                    ["Authorization"] = CONFIG.AUTH_HEADER,
                    ["Content-Type"] = "application/json",
                    ["X-Session-ID"] = CONFIG.SESSION_ID,
                    ["X-Action"] = "PURGE_ALL",
                    ["X-API-Version"] = "NEW"
                },
                Body = HttpService:JSONEncode(deletePayload)
            })
            
            if deleteResponse and deleteResponse.StatusCode then
                if deleteResponse.StatusCode < 300 then
                    professionalLog("SUCCESS", "Old data purged from new API")
                    task.wait(1)
                    cleanupSuccess = true
                elseif deleteResponse.StatusCode == 404 then
                    professionalLog("INFO", "No existing data to cleanup (404)")
                    cleanupSuccess = true -- 404 means no data exists, which is fine
                else
                    professionalLog("ERROR", "Cleanup failed: " .. tostring(deleteResponse.StatusCode))
                end
            end
        end
    end)
    
    State.dataCleanupInProgress = false
    State.lastCleanupTime = os.time()
    return cleanupSuccess
end

local function validateAndFormatStockData(stockData)
    local success, result = pcall(function()
        if not stockData or type(stockData) ~= "table" then
            return nil, "Invalid stock data structure"
        end
        
        if not stockData.normal or not stockData.mirage then
            return nil, "Missing normal or mirage stock data"
        end
        
        local function formatFruits(fruits)
            local formatted = {}
            if fruits and type(fruits) == "table" then
                for _, fruit in pairs(fruits) do
                    if fruit and type(fruit) == "table" and fruit.OnSale and fruit.Name and fruit.Price then
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
        
        local processedData = {
            normal = formatFruits(stockData.normal),
            mirage = formatFruits(stockData.mirage),
            totalCount = 0,
            processed = true,
            apiVersion = "NEW"
        }
        
        processedData.totalCount = #processedData.normal + #processedData.mirage
        
        return processedData, nil
    end)
    
    if success and result then
        return result, nil
    else
        return nil, tostring(result)
    end
end

local function professionalDataSend(stockData)
    local success, result = pcall(function()
        -- Check API health first
        if not State.apiHealthy then
            local healthCheck = checkApiHealth()
            if not healthCheck then
                professionalLog("WARN", "API not healthy, skipping data send")
                return false
            end
        end
        
        -- Step 1: Validate data
        local processedData, error = validateAndFormatStockData(stockData)
        if not processedData then
            professionalLog("ERROR", "Data validation failed: " .. tostring(error))
            return false
        end
        
        -- Step 2: Execute cleanup first
        local cleanupSuccess = executeDataCleanup()
        if not cleanupSuccess then
            professionalLog("WARN", "Cleanup failed, proceeding with caution")
        end
        
        -- Step 3: Wait for cleanup to complete
        task.wait(2)
        
        -- Step 4: Send fresh data to new API
        local payload = {
            sessionId = CONFIG.SESSION_ID,
            timestamp = os.time(),
            playerName = tostring(Players.LocalPlayer.Name),
            serverId = tostring(game.JobId or "unknown"),
            
            -- Stock data
            normalStock = processedData.normal,
            mirageStock = processedData.mirage,
            totalFruits = processedData.totalCount,
            
            -- System info
            antiAfkActive = true,
            monitorVersion = "2.0-NEW-API",
            dataFresh = true,
            replaceMode = true,
            apiVersion = "NEW"
        }
        
        local request = http_request or request or (syn and syn.request)
        if not request then
            professionalLog("CRITICAL", "No HTTP request function available")
            return false
        end
        
        local response = request({
            Url = CONFIG.API_URL,
            Method = "POST",
            Headers = {
                ["Authorization"] = CONFIG.AUTH_HEADER,
                ["Content-Type"] = "application/json",
                ["X-Session-ID"] = CONFIG.SESSION_ID,
                ["X-Data-Mode"] = "REPLACE",
                ["X-Timestamp"] = tostring(os.time()),
                ["X-API-Version"] = "NEW"
            },
            Body = HttpService:JSONEncode(payload)
        })
        
        if response and response.StatusCode then
            if response.StatusCode >= 200 and response.StatusCode < 300 then
                State.totalUpdates = State.totalUpdates + 1
                State.apiHealthy = true
                professionalLog("SUCCESS", string.format("Data sent to NEW API - Normal: %d, Mirage: %d (Total: %d)", 
                    #processedData.normal, #processedData.mirage, processedData.totalCount), true)
                return true
            elseif response.StatusCode == 404 then
                State.apiHealthy = false
                professionalLog("ERROR", "New API endpoint not found (404) - check if API is deployed")
                return false
            else
                State.apiHealthy = false
                professionalLog("ERROR", "New API send failed: " .. tostring(response.StatusCode))
                return false
            end
        else
            State.apiHealthy = false
            professionalLog("ERROR", "No response from new API")
            return false
        end
    end)
    
    if success and result then
        State.retryCount = 0
        return true
    else
        State.retryCount = State.retryCount + 1
        professionalLog("ERROR", "Send operation failed: " .. tostring(result))
        
        if State.retryCount >= CONFIG.MAX_RETRIES then
            professionalLog("CRITICAL", "Max retries exceeded - stopping monitor", true)
            State.isRunning = false
        end
        return false
    end
end

-- Professional Anti-AFK System (Same as before)
local function executeMovementPattern()
    pcall(function()
        local character = Players.LocalPlayer.Character
        if not character then return end
        
        local humanoid = character:FindFirstChild("Humanoid")
        local rootPart = character:FindFirstChild("HumanoidRootPart")
        if not humanoid or not rootPart then return end
        
        local patterns = {
            -- Pattern 1: Square walk
            function()
                local startPos = rootPart.Position
                local size = math.random(8, CONFIG.MOVEMENT_DISTANCE)
                local positions = {
                    startPos + Vector3.new(size, 0, 0),
                    startPos + Vector3.new(size, 0, size),
                    startPos + Vector3.new(0, 0, size),
                    startPos
                }
                
                for _, pos in ipairs(positions) do
                    humanoid:MoveTo(pos)
                    task.wait(math.random(2, 4))
                end
                professionalLog("DEBUG", "Square movement pattern completed")
            end,
            
            -- Pattern 2: Random walk with jumps
            function()
                for i = 1, math.random(3, 6) do
                    local angle = math.random() * math.pi * 2
                    local distance = math.random(5, CONFIG.MOVEMENT_DISTANCE)
                    local direction = Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
                    
                    humanoid:MoveTo(rootPart.Position + direction)
                    task.wait(math.random(1, 3))
                    
                    if math.random() > 0.5 then
                        humanoid.Jump = true
                        task.wait(1)
                    end
                end
                professionalLog("DEBUG", "Random walk pattern completed")
            end,
            
            -- Pattern 3: Circular movement
            function()
                local center = rootPart.Position
                local radius = math.random(6, 10)
                
                for i = 1, 12 do
                    local angle = (i / 12) * math.pi * 2
                    local pos = center + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
                    humanoid:MoveTo(pos)
                    task.wait(0.8)
                end
                professionalLog("DEBUG", "Circular movement pattern completed")
            end
        }
        
        local selectedPattern = patterns[math.random(1, #patterns)]
        selectedPattern()
    end)
end

local function executeToolUsage()
    pcall(function()
        local character = Players.LocalPlayer.Character
        local backpack = Players.LocalPlayer:FindFirstChild("Backpack")
        if not character or not backpack then return end
        
        local humanoid = character:FindFirstChild("Humanoid")
        if not humanoid then return end
        
        -- Get all available tools
        local tools = {}
        for _, item in pairs(backpack:GetChildren()) do
            if item:IsA("Tool") then
                table.insert(tools, item)
            end
        end
        
        if #tools == 0 then return end
        
        -- Use multiple tools in sequence
        local toolsToUse = math.min(#tools, math.random(1, 3))
        
        for i = 1, toolsToUse do
            local tool = tools[math.random(1, #tools)]
            
            -- Equip tool
            humanoid:EquipTool(tool)
            task.wait(math.random(1, 2))
            
            if tool.Parent == character then
                -- Use tool multiple times
                for j = 1, math.random(3, 7) do
                    tool:Activate()
                    task.wait(math.random(0.3, 1))
                    
                    -- Move while using
                    if math.random() > 0.6 then
                        local rootPart = character:FindFirstChild("HumanoidRootPart")
                        if rootPart then
                            local angle = math.random() * math.pi * 2
                            local distance = math.random(2, 5)
                            local direction = Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
                            humanoid:MoveTo(rootPart.Position + direction)
                        end
                    end
                end
                
                task.wait(math.random(2, 5))
                
                -- Sometimes keep equipped
                if math.random() > 0.4 then
                    humanoid:UnequipTools()
                end
                
                professionalLog("DEBUG", "Used tool: " .. tool.Name)
            end
            
            task.wait(math.random(1, 3))
        end
    end)
end

local function professionalAntiAfk()
    pcall(function()
        local currentTime = os.time()
        
        -- Emergency mode
        if currentTime - State.lastActivity >= CONFIG.EMERGENCY_AFK_TIME then
            professionalLog("CRITICAL", "Emergency Anti-AFK activated!", true)
            
            for i = 1, 5 do
                spawn(function() executeMovementPattern() end)
                task.wait(2)
                spawn(function() executeToolUsage() end)
                task.wait(3)
            end
            
            State.lastActivity = currentTime
            State.emergencyMode = false
            professionalLog("SUCCESS", "Emergency Anti-AFK completed", true)
            return
        end
        
        -- Regular anti-AFK
        if currentTime < State.nextAntiAfk then return end
        
        professionalLog("INFO", "Executing professional anti-AFK sequence...")
        
        -- Execute movement
        spawn(function()
            executeMovementPattern()
        end)
        
        -- Execute tool usage
        if math.random() <= CONFIG.TOOL_USE_CHANCE then
            spawn(function()
                task.wait(math.random(2, 5))
                executeToolUsage()
            end)
        end
        
        -- Update timers
        State.lastActivity = currentTime
        State.lastAntiAfk = currentTime
        
        local nextInterval = math.random(CONFIG.ANTI_AFK_MIN_INTERVAL, CONFIG.ANTI_AFK_MAX_INTERVAL)
        State.nextAntiAfk = currentTime + nextInterval
        
        professionalLog("SUCCESS", string.format("Anti-AFK completed - Next in %d seconds", nextInterval))
    end)
end

-- Professional Game Data Functions
local function getValidatedStockData()
    local success, result = pcall(function()
        local remotes = ReplicatedStorage:WaitForChild("Remotes", 15)
        if not remotes then
            error("Game remotes not accessible")
        end
        
        local CommF = remotes:WaitForChild("CommF_", 15)
        if not CommF then
            error("CommF_ remote not found")
        end
        
        -- Get stock data with timeout protection
        local normalStock, mirageStock
        
        local normalSuccess = pcall(function()
            normalStock = CommF:InvokeServer("GetFruits", false)
        end)
        
        local mirageSuccess = pcall(function()
            mirageStock = CommF:InvokeServer("GetFruits", true)
        end)
        
        if not normalSuccess or not mirageSuccess then
            error("Failed to retrieve stock data from game")
        end
        
        return {
            normal = normalStock or {},
            mirage = mirageStock or {}
        }
    end)
    
    if success and result then
        return result
    else
        professionalLog("ERROR", "Stock data retrieval failed: " .. tostring(result))
        return nil
    end
end

-- Professional Session Management
local function professionalCleanup()
    pcall(function()
        if not State.sessionActive then return end
        
        professionalLog("INFO", "Executing professional session cleanup...")
        
        -- Cleanup all data
        executeDataCleanup()
        
        -- Disconnect all connections
        for _, connection in pairs(State.connections) do
            if connection and connection.Connected then
                connection:Disconnect()
            end
        end
        State.connections = {}
        
        State.sessionActive = false
        professionalLog("SUCCESS", "Professional cleanup completed")
    end)
end

-- Professional Setup Functions
local function setupProfessionalFeatures()
    pcall(function()
        -- Initialize timing
        local currentTime = os.time()
        State.lastActivity = currentTime
        State.nextAntiAfk = currentTime + math.random(CONFIG.ANTI_AFK_MIN_INTERVAL, CONFIG.ANTI_AFK_MAX_INTERVAL)
        
        -- Teleport handling
        local teleportConnection = Players.LocalPlayer.OnTeleport:Connect(function(state)
            if state == Enum.TeleportState.Failed then
                professionalLog("WARN", "Teleport failed - executing rejoin protocol")
                professionalCleanup()
                task.wait(5)
                TeleportService:Teleport(game.PlaceId, Players.LocalPlayer)
            end
        end)
        table.insert(State.connections, teleportConnection)
        
        -- Window optimization
        local focusLostConnection = UserInputService.WindowFocusReleased:Connect(function()
            RunService:Set3dRenderingEnabled(false)
        end)
        table.insert(State.connections, focusLostConnection)
        
        local focusGainedConnection = UserInputService.WindowFocused:Connect(function()
            RunService:Set3dRenderingEnabled(true)
        end)
        table.insert(State.connections, focusGainedConnection)
        
        -- Connection monitoring
        local heartbeatConnection = RunService.Heartbeat:Connect(function()
            if not game:IsLoaded() or not Players.LocalPlayer.Parent then
                professionalLog("CRITICAL", "Connection lost - emergency cleanup")
                professionalCleanup()
            end
        end)
        table.insert(State.connections, heartbeatConnection)
        
        professionalLog("SUCCESS", "Professional features initialized")
    end)
end

-- Professional Main Loop
local function executeProfessionalMonitoring()
    pcall(function()
        State.isRunning = true
        State.lastUpdate = os.time()
        
        professionalLog("SUCCESS", "Professional Stock Monitor v2.0 NEW API started", true)
        professionalLog("INFO", "Player: " .. tostring(Players.LocalPlayer.Name))
        professionalLog("INFO", "Session: " .. CONFIG.SESSION_ID:sub(1, 8) .. "...")
        professionalLog("INFO", "New API: " .. CONFIG.API_URL)
        
        -- Initial API health check
        checkApiHealth()
        
        -- Initial cleanup
        executeDataCleanup()
        
        local cycleCount = 0
        
        while State.isRunning do
            -- Execute anti-AFK
            professionalAntiAfk()
            
            -- Get and process stock data
            local stockData = getValidatedStockData()
            
            if stockData then
                local currentHash = HttpService:JSONEncode(stockData)
                local timeSinceUpdate = os.time() - State.lastUpdate
                
                -- Send if changed or forced update
                if currentHash ~= State.lastStockHash or timeSinceUpdate >= 60 then
                    if professionalDataSend(stockData) then
                        State.lastStockHash = currentHash
                        State.lastUpdate = os.time()
                    end
                else
                    professionalLog("DEBUG", "No stock changes detected")
                end
            else
                professionalLog("WARN", "Stock data unavailable this cycle")
            end
            
            -- Status reporting
            cycleCount = cycleCount + 1
            if cycleCount >= 6 then
                local timeSinceActivity = os.time() - State.lastActivity
                local nextAfkIn = math.max(0, State.nextAntiAfk - os.time())
                local apiStatus = State.apiHealthy and "HEALTHY" or "UNHEALTHY"
                professionalLog("INFO", string.format("Status: %d updates | Activity: %ds ago | Next AFK: %ds | API: %s", 
                    State.totalUpdates, timeSinceActivity, nextAfkIn, apiStatus))
                cycleCount = 0
            end
            
            task.wait(CONFIG.UPDATE_INTERVAL)
        end
        
        professionalLog("INFO", "Professional monitoring stopped")
        professionalCleanup()
    end)
end

-- Professional Initialization
local function initializeProfessionalMonitor()
    pcall(function()
        professionalLog("INFO", "Initializing Professional Monitor with NEW API...")
        
        -- Validate environment
        if not ReplicatedStorage:FindFirstChild("Remotes") then
            professionalLog("CRITICAL", "Invalid game environment detected!", true)
            return
        end
        
        -- Setup systems
        setupProfessionalFeatures()
        
        -- Start monitoring
        spawn(function()
            executeProfessionalMonitoring()
        end)
        
        professionalLog("SUCCESS", "Professional Monitor with NEW API initialized successfully", true)
    end)
end

-- Professional Control Interface
_G.NewApiStockMonitor = {
    stop = function()
        State.isRunning = false
        professionalLog("INFO", "Professional stop executed")
    end,
    
    restart = function()
        State.isRunning = false
        task.wait(3)
        initializeProfessionalMonitor()
    end,
    
    forceCleanup = function()
        executeDataCleanup()
        professionalLog("SUCCESS", "Force cleanup executed")
    end,
    
    checkHealth = function()
        return checkApiHealth()
    end,
    
    status = function()
        local timeSinceActivity = os.time() - State.lastActivity
        local nextAfkIn = math.max(0, State.nextAntiAfk - os.time())
        local timeSinceCleanup = os.time() - State.lastCleanupTime
        
        print("=== NEW API PROFESSIONAL STOCK MONITOR STATUS ===")
        print("Running:", State.isRunning)
        print("Total Updates:", State.totalUpdates)
        print("API Health:", State.apiHealthy and "HEALTHY" or "UNHEALTHY")
        print("API URL:", CONFIG.API_URL)
        print("Auth Key:", CONFIG.AUTH_HEADER)
        print("Time Since Activity:", timeSinceActivity, "seconds")
        print("Next Anti-AFK:", nextAfkIn, "seconds")
        print("Last Cleanup:", timeSinceCleanup, "seconds ago")
        print("Active Connections:", #State.connections)
        print("Session ID:", CONFIG.SESSION_ID:sub(1, 8) .. "...")
        print("Cleanup In Progress:", State.dataCleanupInProgress)
        print("================================================")
        return State
    end,
    
    emergencyAntiAfk = function()
        State.nextAntiAfk = 0
        professionalLog("INFO", "Emergency Anti-AFK triggered")
    end
}

-- Initialize Professional Monitor with New API
initializeProfessionalMonitor()
professionalLog("SUCCESS", "NEW API PROFESSIONAL MONITOR READY!", true)
professionalLog("INFO", "Use _G.NewApiStockMonitor.checkHealth() to test new API")
professionalLog("INFO", "Use _G.NewApiStockMonitor.status() for detailed status")
