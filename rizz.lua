-- SIMPLE BLOX FRUITS STOCK MONITOR - WITH 10 SECOND PINGS
print("🍎 Simple Blox Fruits Monitor Starting...")

-- Configuration
local API_ENDPOINT = "https://gagdata.vercel.app/stock/bloxfruits"
local DELETE_ENDPOINT = "https://gagdata.vercel.app/api/delete/bloxfruits"
local API_KEY = "GAMERSBERGXBLOXFRUITS"
local CHECK_INTERVAL = 1
local PING_INTERVAL = 10  -- Send ping every 10 seconds

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

-- Cache
local Cache = {
    sessionId = tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999)),
    updateCounter = 0,
    pingCounter = 0,
    lastPing = 0,
    normalStock = {},
    mirageStock = {}
}

-- AUTO-DELETE on crash
local function autoDeleteOnCrash()
    pcall(function()
        local request = (syn and syn.request) or http_request or request
        request({
            Url = DELETE_ENDPOINT,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json",
                ["Authorization"] = API_KEY,
                ["X-Session-ID"] = Cache.sessionId
            },
            Body = HttpService:JSONEncode({
                action = "DELETE_ALL",
                sessionId = Cache.sessionId,
                timestamp = os.time()
            })
        })
    end)
end

-- Get fruit stock
local function getFruitStock()
    local success, result = pcall(function()
        local CommF = ReplicatedStorage.Remotes.CommF_
        return {
            normal = CommF:InvokeServer("GetFruits", false),
            mirage = CommF:InvokeServer("GetFruits", true)
        }
    end)
    
    return success and result or {normal = {}, mirage = {}}
end

-- Process fruits (simple)
local function processFruits(fruits)
    local processed = {}
    for _, fruit in pairs(fruits) do
        if fruit and fruit.OnSale and fruit.Name and fruit.Price then
            table.insert(processed, {
                name = fruit.Name,
                price = fruit.Price
            })
        end
    end
    return processed
end

-- Collect data
local function collectData()
    local stock = getFruitStock()
    
    return {
        sessionId = Cache.sessionId,
        timestamp = os.time(),
        updateNumber = Cache.updateCounter + 1,
        playerName = Players.LocalPlayer.Name,
        normalStock = processFruits(stock.normal),
        mirageStock = processFruits(stock.mirage)
    }
end

-- Send to API
local function sendToAPI(data)
    local success = pcall(function()
        Cache.updateCounter = Cache.updateCounter + 1
        data.updateNumber = Cache.updateCounter
        
        local request = (syn and syn.request) or http_request or request
        request({
            Url = API_ENDPOINT .. "?t=" .. os.time(),
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json",
                ["Authorization"] = API_KEY,
                ["X-Session-ID"] = Cache.sessionId
            },
            Body = HttpService:JSONEncode(data)
        })
    end)
    
    return success
end

-- Send ping every 10 seconds
local function sendPing()
    local success = pcall(function()
        Cache.pingCounter = Cache.pingCounter + 1
        
        local request = (syn and syn.request) or http_request or request
        request({
            Url = API_ENDPOINT .. "/ping",
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json",
                ["Authorization"] = API_KEY,
                ["X-Session-ID"] = Cache.sessionId
            },
            Body = HttpService:JSONEncode({
                sessionId = Cache.sessionId,
                status = "ALIVE",
                timestamp = os.time(),
                pingNumber = Cache.pingCounter,
                game = "BloxFruits"
            })
        })
    end)
    
    if success then
        print("📡 Ping #" .. Cache.pingCounter .. " sent")
    else
        print("❌ Ping failed")
    end
    
    return success
end

-- Check for changes
local function hasChanges(oldNormal, oldMirage, newNormal, newMirage)
    if #oldNormal ~= #newNormal or #oldMirage ~= #newMirage then
        return true
    end
    
    for i, newFruit in ipairs(newNormal) do
        local oldFruit = oldNormal[i]
        if not oldFruit or oldFruit.name ~= newFruit.name or oldFruit.price ~= newFruit.price then
            return true
        end
    end
    
    for i, newFruit in ipairs(newMirage) do
        local oldFruit = oldMirage[i]
        if not oldFruit or oldFruit.name ~= newFruit.name or oldFruit.price ~= newFruit.price then
            return true
        end
    end
    
    return false
end

-- Setup crash detection
local function setupCrashDetection()
    Players.LocalPlayer.AncestryChanged:Connect(function()
        if not Players.LocalPlayer.Parent then
            autoDeleteOnCrash()
        end
    end)
    
    UserInputService.WindowFocusReleased:Connect(function()
        sendPing()  -- Send ping when window loses focus
    end)
end

-- Anti-AFK
local function setupAntiAFK()
    local VirtualUser = game:GetService("VirtualUser")
    Players.LocalPlayer.Idled:Connect(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
end

-- Main function
local function startMonitoring()
    print("Monitor Started | Session: " .. Cache.sessionId)
    print("📡 Pings will be sent every " .. PING_INTERVAL .. " seconds")
    
    setupAntiAFK()
    setupCrashDetection()
    
    -- Initial data
    local initialData = collectData()
    Cache.normalStock = initialData.normalStock
    Cache.mirageStock = initialData.mirageStock
    Cache.lastPing = os.time()
    
    sendToAPI(initialData)
    sendPing()  -- Send initial ping
    
    -- Main loop
    while true do
        local success, currentData = pcall(collectData)
        
        if success then
            local currentTime = os.time()
            
            -- Check for changes
            local changes = hasChanges(
                Cache.normalStock, Cache.mirageStock,
                currentData.normalStock, currentData.mirageStock
            )
            
            -- Send if changes detected
            if changes then
                if sendToAPI(currentData) then
                    Cache.normalStock = currentData.normalStock
                    Cache.mirageStock = currentData.mirageStock
                    
                    print("Update #" .. Cache.updateCounter .. " - Changes detected")
                    print("Normal: " .. #currentData.normalStock .. " fruits")
                    print("Mirage: " .. #currentData.mirageStock .. " fruits")
                end
            end
            
            -- Send ping every 10 seconds
            if (currentTime - Cache.lastPing) >= PING_INTERVAL then
                sendPing()
                Cache.lastPing = currentTime
            end
            
        else
            print("Error:", currentData)
            autoDeleteOnCrash()
            break
        end
        
        wait(CHECK_INTERVAL)
    end
end

startMonitoring()
