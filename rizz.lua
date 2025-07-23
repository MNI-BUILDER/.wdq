local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")

-- WORKING PROFESSIONAL CONFIGURATION
local CONFIG = {
    API_URL = "https://bloxfritushit.vercel.app/api/stocks/bloxfruits",
    AUTH_HEADER = "GAMERSBERG",
    UPDATE_INTERVAL = 10,
    PING_INTERVAL = 30,
    RETRY_DELAY = 3,
    MAX_RETRIES = 5,
    SESSION_ID = HttpService:GenerateGUID(false),
    
    -- Anti-AFK Settings
    ANTI_AFK_MIN_INTERVAL = 30,
    ANTI_AFK_MAX_INTERVAL = 90,
    MOVEMENT_DISTANCE = 10,
    TOOL_USE_CHANCE = 0.9,
    WALK_DURATION = 3,
    EMERGENCY_AFK_TIME = 600
}

-- STATE MANAGEMENT
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
    connections = {}
}

-- LOGGING SYSTEM
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
local function makeHTTPRequest(method, data, headers)
    local success, result = pcall(function()
        local request = http_request or request or (syn and syn.request)
        if not request then
            error("No HTTP request function available")
        end
        
        local defaultHeaders = {
            ["Authorization"] = CONFIG.AUTH_HEADER,
            ["Content-Type"] = "application/json",
            ["X-Session-ID"] = CONFIG.SESSION_ID
        }
        
        -- Merge custom headers
        if headers then
            for key, value in pairs(headers) do
                defaultHeaders[key] = value
            end
        end
        
        local requestData = {
            Url = CONFIG.API_URL,
            Method = method or "GET",
            Headers = defaultHeaders
        }
        
        if data and (method == "POST" or method == "PUT" or method == "PATCH") then
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
        log("ERROR", "HTTP Request failed: " .. tostring(result))
        return false, tostring(result), 0
    end
end

-- FIXED FRUIT DATA EXTRACTION
local function extractFruitData(fruits)
    local extractedFruits = {}
    
    if not fruits or type(fruits) ~= "table" then
        return extractedFruits
    end
    
    for i, fruit in pairs(fruits) do
        if fruit and type(fruit) == "table" then
            -- Check different possible structures
            local fruitName = fruit.Name or fruit.name or fruit.Fruit
            local fruitPrice = fruit.Price or fruit.price or fruit.Cost
            local isOnSale = fruit.OnSale or fruit.onSale or fruit.InStock
            
            if fruitName and fruitPrice and isOnSale then
                table.insert(extractedFruits, {
                    name = tostring(fruitName),
                    price = tonumber(fruitPrice) or 0,
                    onSale = true,
                    index = i
                })
                log("DEBUG", string.format("Found fruit: %s - %d beli", fruitName, fruitPrice))
            end
        end
    end
    
    return extractedFruits
end

-- FIXED STOCK DATA RETRIEVAL
local function getGameStockData()
    local success, result = pcall(function()
        log("DEBUG", "Attempting to get stock data from game...")
        
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        if not remotes then
            error("Remotes folder not found")
        end
        
        local CommF = remotes:FindFirstChild("CommF_")
        if not CommF then
            error("CommF_ remote not found")
        end
        
        log("DEBUG", "Found game remotes, requesting fruit data...")
        
        -- Get normal stock
        local normalSuccess, normalStock = pcall(function()
            return CommF:InvokeServer("GetFruits", false)
        end)
        
        -- Get mirage stock
        local mirageSuccess, mirageStock = pcall(function()
            return CommF:InvokeServer("GetFruits", true)
        end)
        
        if not normalSuccess then
            log("WARN", "Failed to get normal stock: " .. tostring(normalStock))
            normalStock = {}
        end
        
        if not mirageSuccess then
            log("WARN", "Failed to get mirage stock: " .. tostring(mirageStock))
            mirageStock = {}
        end
        
        log("DEBUG", string.format("Raw normal stock type: %s, count: %d", 
            type(normalStock), normalStock and #normalStock or 0))
        log("DEBUG", string.format("Raw mirage stock type: %s, count: %d", 
            type(mirageStock), mirageStock and #mirageStock or 0))
        
        -- Extract and format fruit data
        local formattedNormal = extractFruitData(normalStock)
        local formattedMirage = extractFruitData(mirageStock)
        
        log("INFO", string.format("Extracted - Normal: %d fruits, Mirage: %d fruits", 
            #formattedNormal, #formattedMirage))
        
        return {
            normal = formattedNormal,
            mirage = formattedMirage,
            totalCount = #formattedNormal + #formattedMirage
        }
    end)
    
    if success and result then
        return result
    else
        log("ERROR", "Stock data retrieval failed: " .. tostring(result))
        return nil
    end
end

-- CLEAR OLD DATA FROM API
local function clearOldSessionData()
    log("INFO", "Clearing old session data...")
    
    local success, response, statusCode = makeHTTPRequest("DELETE", {
        action = "CLEAR_SESSION",
        sessionId = CONFIG.SESSION_ID,
        timestamp = os.time(),
        force = true
    }, {
        ["X-Action"] = "CLEAR_SESSION",
        ["X-Force"] = "true"
    })
    
    if success then
        log("SUCCESS", "Old session data cleared")
        task.wait(1) -- Wait for server processing
        return true
    else
        log("WARN", "Failed to clear old data: " .. tostring(response))
        return false
    end
end

-- SEND FRESH STOCK DATA
local function sendStockDataToAPI(stockData)
    if not stockData then
        log("ERROR", "No stock data to send")
        return false
    end
    
    -- Clear old data first
    clearOldSessionData()
    
    -- Prepare payload
    local payload = {
        sessionId = CONFIG.SESSION_ID,
        timestamp = os.time(),
        playerName = tostring(Players.LocalPlayer.Name),
        serverId = tostring(game.JobId or "unknown"),
        normalStock = stockData.normal,
        mirageStock = stockData.mirage,
        totalFruits = stockData.totalCount,
        antiAfkActive = true,
        dataFresh = true,
        replaceMode = true
    }
    
    log("INFO", string.format("Sending stock data - Normal: %d, Mirage: %d", 
        #stockData.normal, #stockData.mirage))
    
    local success, response, statusCode = makeHTTPRequest("POST", payload, {
        ["X-Data-Mode"] = "REPLACE",
        ["X-Fresh-Data"] = "true"
    })
    
    if success then
        State.totalUpdates = State.totalUpdates + 1
        log("SUCCESS", string.format("Stock data sent successfully! Total updates: %d", State.totalUpdates))
        return true
    else
        log("ERROR", "Failed to send stock data: " .. tostring(response))
        return false
    end
end

-- KEEP ALIVE PING
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
        totalUpdates = State.totalUpdates
    }
    
    local success = makeHTTPRequest("PATCH", pingData, {
        ["X-Ping"] = "true",
        ["X-Keep-Alive"] = "true"
    })
    
    if success then
        State.lastPing = currentTime
        log("DEBUG", "Keep-alive ping sent")
    else
        log("WARN", "Keep-alive ping failed")
    end
end

-- FIXED ANTI-AFK SYSTEM
local function performMovement()
    pcall(function()
        local character = Players.LocalPlayer.Character
        if not character then return end
        
        local humanoid = character:FindFirstChild("Humanoid")
        local rootPart = character:FindFirstChild("HumanoidRootPart")
        if not humanoid or not rootPart then return end
        
        local moveType = math.random(1, 4)
        
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
            -- Rotate
            local rotation = math.random(-180, 180)
            rootPart.CFrame = rootPart.CFrame * CFrame.Angles(0, math.rad(rotation), 0)
            task.wait(1)
            
        else
            -- Back and forth
            local startPos = rootPart.Position
            local angle = math.random() * math.pi * 2
            local distance = math.random(5, 8)
            local direction = Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
            
            humanoid:MoveTo(startPos + direction)
            task.wait(2)
            humanoid:MoveTo(startPos)
            task.wait(1)
        end
        
        log("DEBUG", "Movement executed")
    end)
end

local function useRandomTool()
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
        
        local tool = tools[math.random(1, #tools)]
        
        humanoid:EquipTool(tool)
        task.wait(math.random(1, 2))
        
        if tool.Parent == character then
            for i = 1, math.random(3, 6) do
                tool:Activate()
                task.wait(math.random(0.5, 1))
            end
            
            task.wait(math.random(2, 4))
            
            if math.random() > 0.3 then
                humanoid:UnequipTools()
            end
            
            log("DEBUG", "Used tool: " .. tool.Name)
        end
    end)
end

local function executeAntiAfk()
    local currentTime = os.time()
    
    -- Emergency mode
    if currentTime - State.lastActivity >= CONFIG.EMERGENCY_AFK_TIME then
        log("ERROR", "EMERGENCY ANTI-AFK ACTIVATED!")
        
        for i = 1, 3 do
            spawn(function() performMovement() end)
            task.wait(2)
            spawn(function() useRandomTool() end)
            task.wait(3)
        end
        
        State.lastActivity = currentTime
        log("SUCCESS", "Emergency anti-AFK completed")
        return
    end
    
    -- Regular anti-AFK
    if currentTime < State.nextAntiAfk then return end
    
    log("INFO", "Executing anti-AFK...")
    
    spawn(function() performMovement() end)
    
    if math.random() <= CONFIG.TOOL_USE_CHANCE then
        spawn(function()
            task.wait(math.random(1, 3))
            useRandomTool()
        end)
    end
    
    State.lastActivity = currentTime
    State.lastAntiAfk = currentTime
    
    local nextInterval = math.random(CONFIG.ANTI_AFK_MIN_INTERVAL, CONFIG.ANTI_AFK_MAX_INTERVAL)
    State.nextAntiAfk = currentTime + nextInterval
    
    log("SUCCESS", string.format("Anti-AFK completed - Next in %d seconds", nextInterval))
end

-- SETUP CONNECTIONS
local function setupConnections()
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
    
    log("SUCCESS", "Connections established")
end

-- CLEANUP
local function cleanup()
    log("INFO", "Cleaning up...")
    
    makeHTTPRequest("DELETE", {
        sessionId = CONFIG.SESSION_ID,
        action = "CLEANUP_SESSION",
        timestamp = os.time()
    })
    
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
    
    log("SUCCESS", "WORKING PROFESSIONAL MONITOR STARTED!")
    log("INFO", "Player: " .. tostring(Players.LocalPlayer.Name))
    log("INFO", "Session: " .. CONFIG.SESSION_ID:sub(1, 8) .. "...")
    
    local cycleCount = 0
    
    while State.isRunning do
        -- Execute anti-AFK
        executeAntiAfk()
        
        -- Send keep-alive ping
        sendKeepAlivePing()
        
        -- Get current stock data
        local currentStock = getGameStockData()
        
        if currentStock and currentStock.totalCount >= 0 then
            -- Generate hash to detect changes
            local currentHash = HttpService:JSONEncode(currentStock)
            
            -- Send if data changed or first time
            if currentHash ~= State.lastStockHash then
                log("INFO", "Stock data changed - sending update...")
                
                if sendStockDataToAPI(currentStock) then
                    State.lastStockHash = currentHash
                    State.lastUpdate = os.time()
                    State.retryCount = 0
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
            log("WARN", "Could not retrieve valid stock data")
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
    log("INFO", "Initializing Working Professional Monitor...")
    
    if not ReplicatedStorage:FindFirstChild("Remotes") then
        log("ERROR", "Not in Blox Fruits game!")
        return
    end
    
    setupConnections()
    
    spawn(function()
        startMonitoring()
    end)
    
    log("SUCCESS", "Working Professional Monitor initialized!")
end

-- CONTROL INTERFACE
_G.WorkingStockMonitor = {
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
    
    testStock = function()
        local stock = getGameStockData()
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
        local timeSincePing = os.time() - State.lastPing
        
        print("=== WORKING PROFESSIONAL MONITOR STATUS ===")
        print("Running:", State.isRunning)
        print("Total Updates:", State.totalUpdates)
        print("Time Since Activity:", timeSinceActivity, "seconds")
        print("Next Anti-AFK:", nextAfkIn, "seconds")
        print("Last Ping:", timeSincePing, "seconds ago")
        print("Active Connections:", #State.connections)
        print("Session ID:", CONFIG.SESSION_ID:sub(1, 8) .. "...")
        print("==========================================")
        return State
    end
}

-- START THE MONITOR
initialize()
log("SUCCESS", "WORKING MONITOR READY!")
log("INFO", "Use _G.WorkingStockMonitor.testStock() to test fruit data extraction")
log("INFO", "Use _G.WorkingStockMonitor.status() for full status")
