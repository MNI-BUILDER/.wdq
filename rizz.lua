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
    
    -- Print to console
    print(logMessage)
    
    -- Send important messages as notifications
    if level == "ERROR" then
        notify("Stock Monitor Error", message, 8)
    elseif level == "INFO" and (string.find(message, "started") or string.find(message, "successful")) then
        notify("Stock Monitor", message, 5)
    end
end

local function logStats()
    local uptime = os.time() - State.lastUpdate
    log("STATS", string.format("Updates sent: %d | Uptime: %ds | Session: %s", 
        State.totalUpdates, uptime, CONFIG.SESSION_ID:sub(1, 8)))
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
                ["X-Session-ID"] = CONFIG.SESSION_ID,
                ["User-Agent"] = "BloxFruits-Monitor/2.0"
            }
        }
        
        if data and (method == "POST" or method == "PUT") then
            requestData.Body = HttpService:JSONEncode(data)
        end
        
        -- Client-side HTTP request
        local request = http_request or request or HttpPost or syn.request
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
            local statusCode = response.StatusCode or "Unknown"
            log("ERROR", "API request failed - Status: " .. tostring(statusCode))
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
        log("INFO", string.format("Stock data sent - Normal: %d, Mirage: %d fruits", 
            #normalStock, #mirageStock))
        return true
    else
        State.retryCount = State.retryCount + 1
        log("WARN", string.format("Send failed (attempt %d/%d)", State.retryCount, CONFIG.MAX_RETRIES))
        
        if State.retryCount >= CONFIG.MAX_RETRIES then
            log("ERROR", "Max retries reached - stopping monitor")
            notify("Stock Monitor", "Too many failures, stopping...", 10)
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
        reason = "client_disconnect",
        timestamp = os.time()
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
        local CommF = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CommF_")
        return {
            normal = CommF:InvokeServer("GetFruits", false),
            mirage = CommF:InvokeServer("GetFruits", true)
        }
    end)
    
    if success and result then
        return result
    else
        log("ERROR", "Failed to get fruit stock: " .. tostring(result))
        return nil
    end
end

-- Client-side Performance Features
local function setupClientFeatures()
    -- Anti-idle for client
    local VirtualUser = game:GetService("VirtualUser")
    Players.LocalPlayer.Idled:Connect(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
        log("DEBUG", "Anti-idle activated")
    end)
    
    -- Handle teleport failures
    Players.LocalPlayer.OnTeleport:Connect(function(state)
        if state == Enum.TeleportState.Failed then
            log("WARN", "Teleport failed - attempting rejoin")
            cleanupSession()
            task.wait(3)
            TeleportService:Teleport(game.PlaceId, Players.LocalPlayer)
        end
    end)
    
    -- Window focus optimization
    UserInputService.WindowFocusReleased:Connect(function()
        RunService:Set3dRenderingEnabled(false)
        log("DEBUG", "Rendering disabled (unfocused)")
    end)
    
    UserInputService.WindowFocused:Connect(function()
        RunService:Set3dRenderingEnabled(true)
        log("DEBUG", "Rendering enabled (focused)")
    end)
end

-- Client-side Cleanup Handlers
local function setupCleanupHandlers()
    -- Handle game closing
    game:BindToClose(function()
        log("INFO", "Game closing - cleaning up...")
        cleanupSession()
        task.wait(1)
    end)
    
    -- Monitor connection status
    local connectionMonitor
    connectionMonitor = RunService.Heartbeat:Connect(function()
        if not workspace.Parent then
            log("WARN", "Lost connection - cleaning up")
            cleanupSession()
            connectionMonitor:Disconnect()
        end
    end)
end

-- Main Monitoring Loop
local function startMonitoring()
    State.isRunning = true
    State.lastUpdate = os.time()
    
    log("INFO", "Stock Monitor v2.0 started")
    log("INFO", "Player: " .. Players.LocalPlayer.Name)
    log("INFO", "Session: " .. CONFIG.SESSION_ID:sub(1, 8) .. "...")
    notify("Stock Monitor", "Started successfully!", 5)
    
    -- Test API connection
    local success, _ = makeAPIRequest("GET")
    if success then
        log("INFO", "API connection established")
    else
        log("WARN", "API connection failed - will retry")
    end
    
    -- Stats logging interval
    local statsCounter = 0
    
    while State.isRunning do
        local stockData = getFruitStock()
        
        if stockData then
            local currentHash = generateStockHash(stockData)
            local timeSinceUpdate = os.time() - State.lastUpdate
            
            -- Send if data changed or forced update (every 60 seconds)
            if currentHash ~= State.lastStockHash or timeSinceUpdate >= 60 then
                if sendStockData(stockData) then
                    State.lastStockHash = currentHash
                    State.lastUpdate = os.time()
                end
            else
                log("DEBUG", "No changes detected")
            end
        else
            log("WARN", "Could not retrieve stock data")
        end
        
        -- Log stats every 30 seconds
        statsCounter = statsCounter + 1
        if statsCounter >= 3 then
            logStats()
            statsCounter = 0
        end
        
        task.wait(CONFIG.UPDATE_INTERVAL)
    end
    
    log("INFO", "Monitoring stopped")
    notify("Stock Monitor", "Stopped", 5)
    cleanupSession()
end

-- Initialize Everything
local function initialize()
    log("INFO", "Initializing client-side stock monitor...")
    
    -- Check if required services are available
    if not ReplicatedStorage:FindFirstChild("Remotes") then
        log("ERROR", "Game remotes not found - wrong game?")
        notify("Error", "Not in Blox Fruits game!", 10)
        return
    end
    
    setupClientFeatures()
    setupCleanupHandlers()
    
    -- Start monitoring
    task.spawn(startMonitoring)
    
    log("INFO", "Initialization complete")
end

-- Auto-start
initialize()

-- Manual control functions (for debugging)
_G.StockMonitor = {
    stop = function()
        State.isRunning = false
        log("INFO", "Manual stop requested")
    end,
    
    restart = function()
        State.isRunning = false
        task.wait(2)
        initialize()
    end,
    
    status = function()
        logStats()
        return State
    end,
    
    forceUpdate = function()
        State.lastStockHash = ""
        log("INFO", "Forced update requested")
    end
}

log("INFO", "Use _G.StockMonitor.stop() to stop manually")
