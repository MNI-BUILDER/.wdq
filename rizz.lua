local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

-- ULTRA CLEAN CONFIGURATION (NO MOVEMENT CODE)
local CONFIG = {
    API_URL = "http://45.76.31.158:3000/api/stocks/bloxfruits",
    AUTH_HEADER = "GAMERSBERGGAG",
    UPDATE_INTERVAL = 10,
    HEARTBEAT_INTERVAL = 25,
    PING_INTERVAL = 20,
    RETRY_DELAY = 3,
    MAX_RETRIES = 3,
    SESSION_ID = HttpService:GenerateGUID(false)
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
    lastValidStock = nil,
    startTime = os.time()
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
                Title = "[ULTRA CLEAN] " .. level,
                Text = tostring(message),
                Duration = 6
            })
        elseif level == "SUCCESS" then
            StarterGui:SetCore("SendNotification", {
                Title = "[ULTRA CLEAN] SUCCESS",
                Text = tostring(message),
                Duration = 3
            })
        end
    end)
end

-- HTTP REQUEST FUNCTION
local function makeHTTPRequest(method, data, requestType)
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

-- FRUIT DATA EXTRACTION
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

-- STOCK DATA RETRIEVAL
local function getStockData()
    local success, result = pcall(function()
        log("DEBUG", "Getting stock data from game...")
        
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        if not remotes then
            error("Remotes folder not found")
        end
        
        local CommF = remotes:FindFirstChild("CommF_")
        if not CommF then
            error("CommF_ remote not found")
        end
        
        local normalStock, mirageStock = {}, {}
        
        -- Get normal stock
        local normalSuccess, normalResult = pcall(function()
            return CommF:InvokeServer("GetFruits", false)
        end)
        
        if normalSuccess and normalResult then
            normalStock = normalResult
        else
            log("WARN", "Failed to get normal stock")
        end
        
        -- Get mirage stock
        local mirageSuccess, mirageResult = pcall(function()
            return CommF:InvokeServer("GetFruits", true)
        end)
        
        if mirageSuccess and mirageResult then
            mirageStock = mirageResult
        else
            log("WARN", "Failed to get mirage stock")
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
        
        log("INFO", string.format("Stock retrieved - Normal: %d, Mirage: %d", 
            #formattedNormal, #formattedMirage))
        
        return stockData
    end)
    
    if success and result then
        State.lastValidStock = result
        return result
    else
        log("ERROR", "Stock retrieval failed: " .. tostring(result))
        if State.lastValidStock then
            log("WARN", "Using cached stock data")
            return State.lastValidStock
        end
        return nil
    end
end

-- SEND STOCK DATA TO API
local function sendStockData(stockData)
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
        ultraCleanMode = true,
        noMovement = true,
        uptime = os.time() - State.startTime,
        totalUpdates = State.totalUpdates
    }
    
    log("INFO", string.format("Sending stock data - Normal: %d, Mirage: %d", 
        #stockData.normal, #stockData.mirage))
    
    local success, response, statusCode = makeHTTPRequest("POST", payload, "data")
    
    if success then
        State.totalUpdates = State.totalUpdates + 1
        State.retryCount = 0
        log("SUCCESS", string.format("Stock data sent! Total updates: %d", State.totalUpdates))
        return true
    else
        State.retryCount = State.retryCount + 1
        log("ERROR", string.format("Failed to send data (%d/%d): %s", 
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
    
    local stockData = getStockData()
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
            ultraCleanMode = true,
            uptime = currentTime - State.startTime
        }
        
        local success = makeHTTPRequest("POST", heartbeatData, "heartbeat")
        
        if success then
            State.lastHeartbeat = currentTime
            log("DEBUG", "Heartbeat sent")
        else
            log("WARN", "Heartbeat failed")
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
        status = "monitoring_only",
        uptime = currentTime - State.startTime,
        totalUpdates = State.totalUpdates,
        ultraCleanMode = true,
        noMovement = true
    }
    
    local success = makeHTTPRequest("PUT", pingData, "ping")
    
    if success then
        State.lastPing = currentTime
        log("DEBUG", "Status ping sent")
    else
        log("WARN", "Status ping failed")
    end
end

-- CLEANUP FUNCTION
local function cleanup()
    log("INFO", "Cleaning up...")
    
    -- Send cleanup signal to API
    makeHTTPRequest("POST", {
        sessionId = CONFIG.SESSION_ID,
        action = "CLEANUP",
        timestamp = os.time(),
        ultraCleanMode = true
    })
    
    State.sessionActive = false
    log("SUCCESS", "Cleanup completed")
end

-- MAIN MONITORING LOOP
local function startUltraCleanMonitoring()
    State.isRunning = true
    State.lastUpdate = os.time()
    State.lastHeartbeat = 0
    State.lastPing = 0
    
    log("SUCCESS", "ULTRA CLEAN STOCK MONITOR STARTED!")
    log("INFO", "Player: " .. tostring(Players.LocalPlayer.Name))
    log("INFO", "Session: " .. CONFIG.SESSION_ID:sub(1, 8) .. "...")
    log("INFO", "ZERO MOVEMENT CODE - 100% Security Safe!")
    
    local cycleCount = 0
    
    while State.isRunning do
        pcall(function()
            -- Send heartbeat to keep API alive
            sendHeartbeat()
            
            -- Send status ping
            sendStatusPing()
            
            -- Get current stock data
            local currentStock = getStockData()
            
            if currentStock then
                -- Generate hash to detect changes
                local currentHash = HttpService:JSONEncode(currentStock)
                local timeSinceUpdate = os.time() - State.lastUpdate
                
                -- Send if data changed OR every 60 seconds to keep API alive
                if currentHash ~= State.lastStockHash or timeSinceUpdate >= 60 then
                    log("INFO", "Stock data update detected...")
                    
                    if sendStockData(currentStock) then
                        State.lastStockHash = currentHash
                        State.lastUpdate = os.time()
                        State.retryCount = 0
                    else
                        if State.retryCount >= CONFIG.MAX_RETRIES then
                            log("ERROR", "Max retries reached - continuing monitoring")
                            State.retryCount = 0 -- Reset to continue trying
                        end
                    end
                else
                    log("DEBUG", "No stock changes - heartbeat active")
                end
            else
                log("WARN", "No stock data available - sending heartbeat")
                sendHeartbeat()
            end
            
            -- Status logging every minute
            cycleCount = cycleCount + 1
            if cycleCount >= 6 then
                local uptime = os.time() - State.startTime
                log("INFO", string.format("Status: %d updates | %ds uptime | Ultra clean monitoring", 
                    State.totalUpdates, uptime))
                cycleCount = 0
            end
        end)
        
        task.wait(CONFIG.UPDATE_INTERVAL)
    end
    
    log("INFO", "Ultra clean monitoring stopped")
    cleanup()
end

-- INITIALIZE
local function initializeUltraCleanMonitor()
    log("INFO", "Initializing Ultra Clean Stock Monitor...")
    
    if not ReplicatedStorage:FindFirstChild("Remotes") then
        log("ERROR", "Not in Blox Fruits game!")
        return
    end
    
    spawn(function()
        startUltraCleanMonitoring()
    end)
    
    log("SUCCESS", "Ultra Clean Stock Monitor initialized!")
end

-- CONTROL INTERFACE
_G.UltraCleanStockMonitor = {
    stop = function()
        State.isRunning = false
        log("INFO", "Monitor stopped manually")
    end,
    
    restart = function()
        State.isRunning = false
        task.wait(3)
        initializeUltraCleanMonitor()
    end,
    
    forceUpdate = function()
        State.lastStockHash = ""
        State.lastUpdate = 0
        log("INFO", "Forced update triggered")
    end,
    
    forceHeartbeat = function()
        State.lastHeartbeat = 0
        sendHeartbeat()
        log("INFO", "Forced heartbeat sent")
    end,
    
    testStock = function()
        local stock = getStockData()
        if stock then
            print("=== ULTRA CLEAN STOCK TEST ===")
            print("Normal fruits:", #stock.normal)
            print("Mirage fruits:", #stock.mirage)
            print("Total fruits:", stock.totalCount)
            for i, fruit in ipairs(stock.normal) do
                print(string.format("Normal %d: %s - %d beli", i, fruit.name, fruit.price))
            end
            for i, fruit in ipairs(stock.mirage) do
                print(string.format("Mirage %d: %s - %d beli", i, fruit.name, fruit.price))
            end
            print("=============================")
        else
            print("Failed to get stock data")
        end
        return stock
    end,
    
    status = function()
        local uptime = os.time() - State.startTime
        
        print("=== ULTRA CLEAN MONITOR STATUS ===")
        print("Running:", State.isRunning)
        print("Uptime:", uptime, "seconds")
        print("Total Updates:", State.totalUpdates)
        print("Last Heartbeat:", os.time() - State.lastHeartbeat, "seconds ago")
        print("Last Ping:", os.time() - State.lastPing, "seconds ago")
        print("Session ID:", CONFIG.SESSION_ID:sub(1, 8) .. "...")
        print("Movement Code:", "COMPLETELY REMOVED")
        print("CFrame Usage:", "ZERO")
        print("Security Risk:", "NONE")
        print("==================================")
        return State
    end
}

-- START ULTRA CLEAN MONITOR
initializeUltraCleanMonitor()
log("SUCCESS", "ULTRA CLEAN MONITOR READY!")
log("INFO", "ZERO movement code - 100% security safe!")
log("INFO", "Pure stock monitoring only!")
log("INFO", "Use _G.UltraCleanStockMonitor.testStock() to test fruit detection")
log("INFO", "Use _G.UltraCleanStockMonitor.status() for monitor status")
