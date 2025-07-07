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
    AUTH_HEADER = "GAMERSBERG",
    UPDATE_INTERVAL = 10,
    RETRY_DELAY = 5,
    MAX_RETRIES = 3,
    SESSION_ID = HttpService:GenerateGUID(false)
}

-- State Management
local State = {
    isRunning = false,
    lastUpdate = 0,
    retryCount = 0,
    sessionActive = true,
    lastStockHash = "",
    totalUpdates = 0
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
        
        -- Try different HTTP request methods for different executors
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
        -- Wait for remotes to load
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

-- Client-side Features (FIXED)
local function setupClientFeatures()
    -- Anti-idle
    pcall(function()
        local VirtualUser = game:GetService("VirtualUser")
        Players.LocalPlayer.Idled:Connect(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
            log("DEBUG", "Anti-idle activated")
        end)
    end)
    
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

-- Client-side Cleanup (FIXED - removed BindToClose)
local function setupCleanupHandlers()
    -- Monitor for disconnection
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
    
    -- Player leaving detection
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
    
    log("INFO", "Stock Monitor started")
    log("INFO", "Player: " .. Players.LocalPlayer.Name)
    notify("Stock Monitor", "Started successfully!", 5)
    
    -- Test API
    local success, _ = makeAPIRequest("GET")
    if success then
        log("INFO", "API connected")
    else
        log("WARN", "API connection failed")
    end
    
    local updateCount = 0
    
    while State.isRunning do
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
        if updateCount >= 6 then -- Every 60 seconds
            log("INFO", string.format("Updates: %d | Running: %ds", 
                State.totalUpdates, os.time() - State.lastUpdate))
            updateCount = 0
        end
        
        task.wait(CONFIG.UPDATE_INTERVAL)
    end
    
    log("INFO", "Monitor stopped")
    cleanupSession()
end

-- Initialize
local function initialize()
    log("INFO", "Initializing...")
    
    -- Check if in Blox Fruits
    if not ReplicatedStorage:FindFirstChild("Remotes") then
        log("ERROR", "Not in Blox Fruits game!")
        notify("Error", "Wrong game!", 10)
        return
    end
    
    setupClientFeatures()
    setupCleanupHandlers()
    
    -- Start in new thread
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
        print("Session:", CONFIG.SESSION_ID:sub(1, 8))
        return State
    end
}

-- Start everything
initialize()
log("INFO", "Use _G.StockMonitor.stop() to stop")
