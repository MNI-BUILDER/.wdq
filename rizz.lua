local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local UserInputService = game:GetService("UserInputService")

-- Configuration
local CONFIG = {
    API_URL = "https://bfdata.vercel.app/api/stocks/bloxfruits",
    AUTH_HEADER = "GAMERSBERGBLOXFRUITS",
    UPDATE_INTERVAL = 10, -- seconds
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
    lastStockHash = ""
}

-- Utility Functions
local function log(level, message)
    local timestamp = os.date("%H:%M:%S")
    print(string.format("[%s] [%s] %s", timestamp, level, message))
end

local function generateStockHash(stockData)
    local hashString = ""
    for stockType, fruits in pairs(stockData) do
        for _, fruit in pairs(fruits) do
            if fruit and fruit.OnSale then
                hashString = hashString .. fruit.Name .. fruit.Price
            end
        end
    end
    return HttpService:JSONEncode({hash = hashString})
end

local function formatFruitData(fruits)
    local formattedFruits = {}
    for _, fruit in pairs(fruits) do
        if fruit and fruit.OnSale and fruit.Name and fruit.Price then
            table.insert(formattedFruits, {
                name = fruit.Name,
                price = fruit.Price,
                onSale = fruit.OnSale
            })
        end
    end
    return formattedFruits
end

-- API Communication
local function makeAPIRequest(method, data)
    local success, response = pcall(function()
        local requestData = {
            Url = CONFIG.API_URL,
            Method = method,
            Headers = {
                ["Authorization"] = CONFIG.AUTH_HEADER,
                ["Content-Type"] = "application/json",
                ["X-Session-ID"] = CONFIG.SESSION_ID
            }
        }
        
        if data and (method == "POST" or method == "PUT") then
            requestData.Body = HttpService:JSONEncode(data)
        end
        
        local request = (syn and syn.request) or http_request or request
        return request(requestData)
    end)
    
    if success and response then
        if response.StatusCode >= 200 and response.StatusCode < 300 then
            State.retryCount = 0
            return true, response.Body
        else
            log("ERROR", "API request failed with status: " .. tostring(response.StatusCode))
            return false, response.Body
        end
    else
        log("ERROR", "Request failed: " .. tostring(response))
        return false, nil
    end
end

local function sendStockData(stockData)
    local payload = {
        sessionId = CONFIG.SESSION_ID,
        timestamp = os.time(),
        normalStock = formatFruitData(stockData.normal),
        mirageStock = formatFruitData(stockData.mirage),
        playerName = Players.LocalPlayer.Name,
        serverId = game.JobId
    }
    
    local success, responseBody = makeAPIRequest("POST", payload)
    
    if success then
        log("INFO", "Stock data sent successfully")
        return true
    else
        State.retryCount = State.retryCount + 1
        log("WARN", string.format("Failed to send data (attempt %d/%d)", State.retryCount, CONFIG.MAX_RETRIES))
        
        if State.retryCount >= CONFIG.MAX_RETRIES then
            log("ERROR", "Max retries reached, stopping monitor")
            State.isRunning = false
        end
        return false
    end
end

local function cleanupSession()
    if not State.sessionActive then return end
    
    log("INFO", "Cleaning up session...")
    local success, _ = makeAPIRequest("DELETE", {
        sessionId = CONFIG.SESSION_ID,
        reason = "disconnect"
    })
    
    if success then
        log("INFO", "Session cleanup successful")
    else
        log("WARN", "Session cleanup failed")
    end
    
    State.sessionActive = false
end

-- Game Data Functions
local function getFruitStock()
    local success, result = pcall(function()
        local CommF = ReplicatedStorage.Remotes.CommF_
        return {
            normal = CommF:InvokeServer("GetFruits", false),
            mirage = CommF:InvokeServer("GetFruits", true)
        }
    end)
    
    if success then
        return result
    else
        log("ERROR", "Failed to get fruit stock: " .. tostring(result))
        return nil
    end
end

-- Performance Optimization
local function setupPerformanceFeatures()
    -- Anti-idle
    local VirtualUser = game:GetService("VirtualUser")
    Players.LocalPlayer.Idled:Connect(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
        log("INFO", "Anti-idle triggered")
    end)
    
    -- Auto-rejoin on teleport failure
    Players.LocalPlayer.OnTeleport:Connect(function(state)
        if state == Enum.TeleportState.Failed then
            log("INFO", "Teleport failed, rejoining...")
            cleanupSession()
            task.wait(5)
            TeleportService:Teleport(game.PlaceId, Players.LocalPlayer)
        end
    end)
    
    -- Performance optimization when window loses focus
    UserInputService.WindowFocusReleased:Connect(function()
        RunService:Set3dRenderingEnabled(false)
        log("INFO", "Rendering disabled (window unfocused)")
    end)
    
    UserInputService.WindowFocused:Connect(function()
        RunService:Set3dRenderingEnabled(true)
        log("INFO", "Rendering enabled (window focused)")
    end)
end

-- Cleanup Handlers
local function setupCleanupHandlers()
    -- Handle game shutdown
    game:BindToClose(function()
        log("INFO", "Game closing, cleaning up...")
        cleanupSession()
        task.wait(2) -- Give time for cleanup request
    end)
    
    -- Handle player leaving
    Players.PlayerRemoving:Connect(function(player)
        if player == Players.LocalPlayer then
            cleanupSession()
        end
    end)
    
    -- Handle connection loss
    local heartbeatConnection
    heartbeatConnection = RunService.Heartbeat:Connect(function()
        if not game:GetService("NetworkClient"):IsConnected() then
            log("WARN", "Connection lost, cleaning up...")
            cleanupSession()
            heartbeatConnection:Disconnect()
        end
    end)
end

-- Main Monitoring Loop
local function startMonitoring()
    State.isRunning = true
    log("INFO", "Stock monitor started")
    log("INFO", "Session ID: " .. CONFIG.SESSION_ID)
    
    -- Initial API ping
    local success, _ = makeAPIRequest("GET")
    if not success then
        log("ERROR", "Failed to connect to API, retrying...")
    end
    
    while State.isRunning do
        local stockData = getFruitStock()
        
        if stockData then
            local currentHash = generateStockHash(stockData)
            
            -- Only send if data changed or it's been more than 60 seconds
            if currentHash ~= State.lastStockHash or (os.time() - State.lastUpdate) >= 60 then
                if sendStockData(stockData) then
                    State.lastStockHash = currentHash
                    State.lastUpdate = os.time()
                end
            else
                log("DEBUG", "No stock changes detected")
            end
        else
            log("WARN", "Failed to retrieve stock data")
        end
        
        task.wait(CONFIG.UPDATE_INTERVAL)
    end
    
    log("INFO", "Monitoring stopped")
    cleanupSession()
end

-- Initialize and Start
local function initialize()
    log("INFO", "Initializing Blox Fruits Stock Monitor v2.0")
    
    setupPerformanceFeatures()
    setupCleanupHandlers()
    
    -- Start monitoring in a separate thread
    task.spawn(startMonitoring)
end

-- Start the monitor
initialize()
