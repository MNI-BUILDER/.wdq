-- FIXED SIMPLE BLOX FRUITS STOCK MONITOR - NO DELETE ENDPOINT
print("🍎 FIXED Blox Fruits Monitor Starting...")

-- Configuration
local API_ENDPOINT = "https://gagdata.vercel.app/stock/bloxfruits"
local API_KEY = "GAMERSBERGXBLOXFRUITS"
local CHECK_INTERVAL = 1
local PING_INTERVAL = 10

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

print("Session ID: " .. Cache.sessionId)

-- Get fruit stock
local function getFruitStock()
    print("🔍 Getting fruit stock...")
    local success, result = pcall(function()
        local CommF = ReplicatedStorage.Remotes.CommF_
        return {
            normal = CommF:InvokeServer("GetFruits", false),
            mirage = CommF:InvokeServer("GetFruits", true)
        }
    end)
    
    if success then
        print("✅ Got fruit stock successfully")
        return result
    else
        print("❌ Failed to get fruit stock:", result)
        return {normal = {}, mirage = {}}
    end
end

-- Process fruits (simple)
local function processFruits(fruits)
    local processed = {}
    local count = 0
    
    for _, fruit in pairs(fruits) do
        if fruit and fruit.OnSale and fruit.Name and fruit.Price then
            table.insert(processed, {
                name = fruit.Name,
                price = fruit.Price
            })
            count = count + 1
        end
    end
    
    print("📊 Processed " .. count .. " fruits")
    return processed
end

-- Collect data
local function collectData()
    print("📦 Collecting data...")
    local stock = getFruitStock()
    
    local normalFruits = processFruits(stock.normal)
    local mirageFruits = processFruits(stock.mirage)
    
    local data = {
        sessionId = Cache.sessionId,
        timestamp = os.time(),
        updateNumber = Cache.updateCounter + 1,
        playerName = Players.LocalPlayer.Name,
        normalStock = normalFruits,
        mirageStock = mirageFruits
    }
    
    print("📦 Data collected - Normal: " .. #normalFruits .. ", Mirage: " .. #mirageFruits)
    return data
end

-- Send to API
local function sendToAPI(data)
    print("📤 Sending to API...")
    
    local success, response = pcall(function()
        Cache.updateCounter = Cache.updateCounter + 1
        data.updateNumber = Cache.updateCounter
        
        local jsonStr = HttpService:JSONEncode(data)
        print("📤 JSON Data: " .. string.sub(jsonStr, 1, 200) .. "...")
        
        local request = (syn and syn.request) or http_request or request
        local result = request({
            Url = API_ENDPOINT,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json",
                ["Authorization"] = API_KEY,
                ["X-Session-ID"] = Cache.sessionId,
                ["Cache-Control"] = "no-cache"
            },
            Body = jsonStr
        })
        
        print("📤 API Response Status: " .. tostring(result.StatusCode))
        return result
    end)
    
    if success then
        print("✅ API request successful!")
        return true
    else
        print("❌ API request failed:", response)
        return false
    end
end

-- Send ping
local function sendPing()
    print("📡 Sending ping...")
    
    local success, response = pcall(function()
        Cache.pingCounter = Cache.pingCounter + 1
        
        local pingData = {
            sessionId = Cache.sessionId,
            status = "ALIVE",
            timestamp = os.time(),
            pingNumber = Cache.pingCounter,
            game = "BloxFruits"
        }
        
        local request = (syn and syn.request) or http_request or request
        local result = request({
            Url = API_ENDPOINT .. "/ping",
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json",
                ["Authorization"] = API_KEY,
                ["X-Session-ID"] = Cache.sessionId
            },
            Body = HttpService:JSONEncode(pingData)
        })
        
        print("📡 Ping Response Status: " .. tostring(result.StatusCode))
        return result
    end)
    
    if success then
        print("✅ Ping #" .. Cache.pingCounter .. " sent successfully!")
        return true
    else
        print("❌ Ping failed:", response)
        return false
    end
end

-- Check for changes
local function hasChanges(oldNormal, oldMirage, newNormal, newMirage)
    if #oldNormal ~= #newNormal or #oldMirage ~= #newMirage then
        print("🔄 Stock count changed!")
        return true
    end
    
    for i, newFruit in ipairs(newNormal) do
        local oldFruit = oldNormal[i]
        if not oldFruit or oldFruit.name ~= newFruit.name or oldFruit.price ~= newFruit.price then
            print("🔄 Normal stock changed: " .. newFruit.name)
            return true
        end
    end
    
    for i, newFruit in ipairs(newMirage) do
        local oldFruit = oldMirage[i]
        if not oldFruit or oldFruit.name ~= newFruit.name or oldFruit.price ~= newFruit.price then
            print("🔄 Mirage stock changed: " .. newFruit.name)
            return true
        end
    end
    
    return false
end

-- Anti-AFK
local function setupAntiAFK()
    local VirtualUser = game:GetService("VirtualUser")
    Players.LocalPlayer.Idled:Connect(function()
        print("🔄 Anti-AFK triggered")
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
end

-- Main function
local function startMonitoring()
    print("🚀 FIXED Monitor Started!")
    print("📋 Session: " .. Cache.sessionId)
    print("📋 Player: " .. Players.LocalPlayer.Name)
    print("📋 API: " .. API_ENDPOINT)
    
    setupAntiAFK()
    
    -- Initial data
    local initialData = collectData()
    Cache.normalStock = initialData.normalStock
    Cache.mirageStock = initialData.mirageStock
    Cache.lastPing = os.time()
    
    -- Send initial data
    print("📤 Sending initial data...")
    if sendToAPI(initialData) then
        print("✅ Initial data sent successfully!")
    else
        print("❌ Failed to send initial data!")
    end
    
    -- Send initial ping
    print("📡 Sending initial ping...")
    if sendPing() then
        print("✅ Initial ping sent successfully!")
    else
        print("❌ Failed to send initial ping!")
    end
    
    print("🔄 Starting main loop...")
    
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
                print("🔄 Changes detected, sending update...")
                if sendToAPI(currentData) then
                    Cache.normalStock = currentData.normalStock
                    Cache.mirageStock = currentData.mirageStock
                    print("✅ Update #" .. Cache.updateCounter .. " sent!")
                    print("📊 Normal: " .. #currentData.normalStock .. " fruits")
                    print("📊 Mirage: " .. #currentData.mirageStock .. " fruits")
                else
                    print("❌ Failed to send update!")
                end
            end
            
            -- Send ping every 10 seconds
            if (currentTime - Cache.lastPing) >= PING_INTERVAL then
                if sendPing() then
                    Cache.lastPing = currentTime
                else
                    print("❌ Ping failed, will retry...")
                end
            end
            
        else
            print("❌ Error in main loop:", currentData)
            break
        end
        
        wait(CHECK_INTERVAL)
    end
end

-- Start with error handling
local success, error = pcall(startMonitoring)
if not success then
    print("💥 CRITICAL ERROR:", error)
end
