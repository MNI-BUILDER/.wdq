-- BLOX FRUITS STOCK MONITOR - PROPER API STRUCTURE
print("🍎 Blox Fruits Monitor Starting - PROPER API VERSION...")

-- Configuration
local API_ENDPOINT = "https://gagdata.vercel.app/stock/bloxfruits"
local API_KEY = "GAMERSBERGXBLOXFRUITS"
local CHECK_INTERVAL = 1
local PING_INTERVAL = 10
local STATUS_CHECK_INTERVAL = 30

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
    lastStatusCheck = 0,
    normalStock = {},
    mirageStock = {},
    apiOnline = false
}

print("🚀 Session ID: " .. Cache.sessionId)
print("🚀 Player: " .. Players.LocalPlayer.Name)
print("🚀 API Endpoint: " .. API_ENDPOINT)

-- GET API Status
local function getAPIStatus()
    print("📡 Checking API status...")
    
    local success, response = pcall(function()
        local request = (syn and syn.request) or http_request or request
        local result = request({
            Url = API_ENDPOINT,
            Method = "GET",
            Headers = {
                ["Authorization"] = API_KEY,
                ["X-Session-ID"] = Cache.sessionId
            }
        })
        
        print("📡 GET Status Code: " .. tostring(result.StatusCode))
        
        if result.StatusCode == 200 then
            local data = HttpService:JSONDecode(result.Body)
            print("📡 API Response: " .. result.Body)
            return data
        else
            print("❌ GET Request failed with status: " .. tostring(result.StatusCode))
            return nil
        end
    end)
    
    if success and response then
        Cache.apiOnline = response.success or false
        print("✅ API Status: " .. (Cache.apiOnline and "ONLINE" or "OFFLINE"))
        if response.meta then
            print("📊 Server Time: " .. tostring(response.meta.serverTime))
            print("📊 Data Version: " .. tostring(response.meta.dataVersion))
            print("📊 Last Update: " .. tostring(response.meta.lastUpdateTime))
        end
        return response
    else
        print("❌ Failed to get API status:", response)
        Cache.apiOnline = false
        return nil
    end
end

-- Get fruit stock from game
local function getFruitStock()
    print("🔍 Getting fruit stock from game...")
    local success, result = pcall(function()
        local CommF = ReplicatedStorage.Remotes.CommF_
        local normalStock = CommF:InvokeServer("GetFruits", false)
        local mirageStock = CommF:InvokeServer("GetFruits", true)
        
        print("🔍 Raw Normal Stock: " .. tostring(#(normalStock or {})) .. " items")
        print("🔍 Raw Mirage Stock: " .. tostring(#(mirageStock or {})) .. " items")
        
        return {
            normal = normalStock or {},
            mirage = mirageStock or {}
        }
    end)
    
    if success then
        print("✅ Successfully retrieved fruit stock from game")
        return result
    else
        print("❌ Failed to get fruit stock from game:", result)
        return {normal = {}, mirage = {}}
    end
end

-- Process fruits for API
local function processFruits(fruits, stockType)
    print("📊 Processing " .. stockType .. " fruits...")
    local processed = {}
    local count = 0
    
    for _, fruit in pairs(fruits) do
        if fruit and fruit.OnSale and fruit.Name and fruit.Price then
            local fruitData = {
                name = fruit.Name,
                price = fruit.Price,
                onSale = fruit.OnSale,
                stockType = stockType
            }
            table.insert(processed, fruitData)
            count = count + 1
            print("🍎 " .. stockType .. ": " .. fruit.Name .. " - $" .. tostring(fruit.Price))
        end
    end
    
    print("📊 Processed " .. count .. " " .. stockType .. " fruits")
    return processed
end

-- Collect all data
local function collectAllData()
    print("📦 Collecting all data...")
    local stock = getFruitStock()
    
    local normalFruits = processFruits(stock.normal, "normal")
    local mirageFruits = processFruits(stock.mirage, "mirage")
    
    local data = {
        sessionId = Cache.sessionId,
        timestamp = os.time(),
        updateNumber = Cache.updateCounter + 1,
        playerName = Players.LocalPlayer.Name,
        userId = Players.LocalPlayer.UserId,
        game = "BloxFruits",
        
        -- Stock data
        normalStock = normalFruits,
        mirageStock = mirageFruits,
        
        -- Metadata
        totalNormalFruits = #normalFruits,
        totalMirageFruits = #mirageFruits,
        totalFruits = #normalFruits + #mirageFruits
    }
    
    print("📦 Data collected:")
    print("   - Normal fruits: " .. #normalFruits)
    print("   - Mirage fruits: " .. #mirageFruits)
    print("   - Total fruits: " .. data.totalFruits)
    
    return data
end

-- POST data to API
local function postDataToAPI(data)
    print("📤 Posting data to API...")
    
    local success, response = pcall(function()
        Cache.updateCounter = Cache.updateCounter + 1
        data.updateNumber = Cache.updateCounter
        
        local jsonStr = HttpService:JSONEncode(data)
        print("📤 JSON Size: " .. string.len(jsonStr) .. " characters")
        print("📤 JSON Preview: " .. string.sub(jsonStr, 1, 300) .. "...")
        
        local request = (syn and syn.request) or http_request or request
        local result = request({
            Url = API_ENDPOINT,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json",
                ["Authorization"] = API_KEY,
                ["X-Session-ID"] = Cache.sessionId,
                ["X-Update-Number"] = tostring(Cache.updateCounter),
                ["Cache-Control"] = "no-cache, no-store, must-revalidate"
            },
            Body = jsonStr
        })
        
        print("📤 POST Status Code: " .. tostring(result.StatusCode))
        print("📤 POST Response: " .. tostring(result.Body))
        
        return result
    end)
    
    if success and response then
        if response.StatusCode == 200 or response.StatusCode == 201 then
            print("✅ Data posted successfully!")
            return true
        else
            print("❌ POST failed with status: " .. tostring(response.StatusCode))
            return false
        end
    else
        print("❌ POST request failed:", response)
        return false
    end
end

-- Send ping to API
local function sendPingToAPI()
    print("📡 Sending ping to API...")
    
    local success, response = pcall(function()
        Cache.pingCounter = Cache.pingCounter + 1
        
        local pingData = {
            sessionId = Cache.sessionId,
            status = "ALIVE",
            timestamp = os.time(),
            pingNumber = Cache.pingCounter,
            game = "BloxFruits",
            playerName = Players.LocalPlayer.Name
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
        
        print("📡 PING Status Code: " .. tostring(result.StatusCode))
        print("📡 PING Response: " .. tostring(result.Body))
        
        return result
    end)
    
    if success and response then
        if response.StatusCode == 200 or response.StatusCode == 201 then
            print("✅ Ping #" .. Cache.pingCounter .. " sent successfully!")
            return true
        else
            print("❌ Ping failed with status: " .. tostring(response.StatusCode))
            return false
        end
    else
        print("❌ Ping request failed:", response)
        return false
    end
end

-- Check for stock changes
local function hasStockChanged(oldNormal, oldMirage, newNormal, newMirage)
    print("🔍 Checking for stock changes...")
    
    -- Count check
    if #oldNormal ~= #newNormal or #oldMirage ~= #newMirage then
        print("🔄 Stock count changed!")
        print("   - Normal: " .. #oldNormal .. " -> " .. #newNormal)
        print("   - Mirage: " .. #oldMirage .. " -> " .. #newMirage)
        return true
    end
    
    -- Content check for normal stock
    for i, newFruit in ipairs(newNormal) do
        local oldFruit = oldNormal[i]
        if not oldFruit or oldFruit.name ~= newFruit.name or oldFruit.price ~= newFruit.price then
            print("🔄 Normal stock changed: " .. newFruit.name .. " ($" .. newFruit.price .. ")")
            return true
        end
    end
    
    -- Content check for mirage stock
    for i, newFruit in ipairs(newMirage) do
        local oldFruit = oldMirage[i]
        if not oldFruit or oldFruit.name ~= newFruit.name or oldFruit.price ~= newFruit.price then
            print("🔄 Mirage stock changed: " .. newFruit.name .. " ($" .. newFruit.price .. ")")
            return true
        end
    end
    
    print("✅ No stock changes detected")
    return false
end

-- Anti-AFK system
local function setupAntiAFK()
    print("🔄 Setting up Anti-AFK...")
    local VirtualUser = game:GetService("VirtualUser")
    Players.LocalPlayer.Idled:Connect(function()
        print("🔄 Anti-AFK triggered - preventing idle kick")
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
    print("✅ Anti-AFK setup complete")
end

-- Main monitoring function
local function startMonitoring()
    print("🚀 Starting Blox Fruits Stock Monitor...")
    print("=" .. string.rep("=", 50))
    
    setupAntiAFK()
    
    -- Initial API status check
    print("🔍 Performing initial API status check...")
    getAPIStatus()
    
    -- Initial data collection
    print("📦 Collecting initial data...")
    local initialData = collectAllData()
    Cache.normalStock = initialData.normalStock
    Cache.mirageStock = initialData.mirageStock
    Cache.lastPing = os.time()
    Cache.lastStatusCheck = os.time()
    
    -- Send initial data
    print("📤 Sending initial data to API...")
    if postDataToAPI(initialData) then
        print("✅ Initial data sent successfully!")
    else
        print("❌ Failed to send initial data!")
    end
    
    -- Send initial ping
    print("📡 Sending initial ping...")
    if sendPingToAPI() then
        print("✅ Initial ping sent successfully!")
    else
        print("❌ Failed to send initial ping!")
    end
    
    print("🔄 Starting main monitoring loop...")
    print("=" .. string.rep("=", 50))
    
    -- MAIN MONITORING LOOP
    while true do
        local success, currentData = pcall(collectAllData)
        
        if success then
            local currentTime = os.time()
            
            -- Check for stock changes
            local hasChanges = hasStockChanged(
                Cache.normalStock, Cache.mirageStock,
                currentData.normalStock, currentData.mirageStock
            )
            
            -- Send data if changes detected
            if hasChanges then
                print("🔄 Stock changes detected - sending update...")
                if postDataToAPI(currentData) then
                    Cache.normalStock = currentData.normalStock
                    Cache.mirageStock = currentData.mirageStock
                    print("✅ Update #" .. Cache.updateCounter .. " sent successfully!")
                else
                    print("❌ Failed to send update #" .. Cache.updateCounter)
                end
            end
            
            -- Send ping every 10 seconds
            if (currentTime - Cache.lastPing) >= PING_INTERVAL then
                print("📡 Time for ping (" .. PING_INTERVAL .. "s interval)")
                if sendPingToAPI() then
                    Cache.lastPing = currentTime
                else
                    print("❌ Ping failed, will retry next cycle")
                end
            end
            
            -- Check API status every 30 seconds
            if (currentTime - Cache.lastStatusCheck) >= STATUS_CHECK_INTERVAL then
                print("📡 Time for status check (" .. STATUS_CHECK_INTERVAL .. "s interval)")
                getAPIStatus()
                Cache.lastStatusCheck = currentTime
            end
            
        else
            print("❌ Error in main monitoring loop:", currentData)
            print("💥 Stopping monitor due to critical error")
            break
        end
        
        wait(CHECK_INTERVAL)
    end
end

-- Start monitoring with error handling
print("🍎 Initializing Blox Fruits Stock Monitor...")
local success, error = pcall(startMonitoring)
if not success then
    print("💥 CRITICAL ERROR in monitor:", error)
    print("🔄 Monitor stopped")
end
