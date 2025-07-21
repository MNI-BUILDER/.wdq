local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")

-- Configuration
local CONFIG = {
    API_URL = "https://bloxfritushit.vercel.app/api/stocks/bloxfruits",
    AUTH_HEADER = "GAMERSBERG",
    UPDATE_INTERVAL = 10,
    SESSION_ID = HttpService:GenerateGUID(false),
    
    -- AUTOMATIC MOVEMENT & TOOL SETTINGS
    AUTO_MOVEMENT_ENABLED = true,
    AUTO_TOOL_ENABLED = true,
    MOVEMENT_INTERVAL = 45,      -- Move every 45 seconds
    TOOL_INTERVAL = 60,          -- Use tool every 60 seconds
    MOVEMENT_DISTANCE = 20,      -- How far to move
    TOOL_USE_DURATION = 8,       -- How long to use tools
    EMERGENCY_INTERVAL = 900     -- 15 minutes emergency trigger
}

-- State
local State = {
    running = false,
    lastUpdate = 0,
    sessionActive = true,
    lastHash = "",
    updateCount = 0,
    
    -- AUTOMATIC MOVEMENT & TOOL TRACKING
    lastMovement = 0,
    lastToolUse = 0,
    lastActivity = os.time(),
    movementCount = 0,
    toolUseCount = 0,
    autoSystemActive = true
}

-- Logging with Movement/Tool indicators
local function log(level, msg)
    local time = os.date("%H:%M:%S")
    print(string.format("[%s][%s] %s", time, level, msg))
    
    if level == "MOVEMENT" or level == "TOOL" or level == "ERROR" then
        pcall(function()
            StarterGui:SetCore("SendNotification", {
                Title = level == "MOVEMENT" and "Auto Movement" or level == "TOOL" and "Auto Tool" or "Monitor Error",
                Text = msg,
                Duration = level == "ERROR" and 8 or 4
            })
        end)
    end
end

-- AUTOMATIC MOVEMENT SYSTEM
local function performAutoMovement()
    local success = pcall(function()
        local character = Players.LocalPlayer.Character
        if not character then return false end
        
        local humanoid = character:FindFirstChild("Humanoid")
        local rootPart = character:FindFirstChild("HumanoidRootPart")
        if not humanoid or not rootPart then return false end
        
        local currentPos = rootPart.Position
        local movementPattern = math.random(1, 5)
        
        if movementPattern == 1 then
            -- CIRCLE WALK
            log("MOVEMENT", "Starting circle walk pattern")
            local center = currentPos
            for i = 1, 8 do
                local angle = (i / 8) * math.pi * 2
                local radius = math.random(8, CONFIG.MOVEMENT_DISTANCE)
                local targetPos = center + Vector3.new(
                    math.cos(angle) * radius, 
                    0, 
                    math.sin(angle) * radius
                )
                humanoid:MoveTo(targetPos)
                task.wait(1.5)
            end
            
        elseif movementPattern == 2 then
            -- RANDOM WALK
            log("MOVEMENT", "Starting random walk pattern")
            for i = 1, 6 do
                local angle = math.random() * math.pi * 2
                local distance = math.random(5, CONFIG.MOVEMENT_DISTANCE)
                local direction = Vector3.new(
                    math.cos(angle) * distance,
                    0,
                    math.sin(angle) * distance
                )
                humanoid:MoveTo(currentPos + direction)
                task.wait(math.random(2, 4))
                currentPos = rootPart.Position
            end
            
        elseif movementPattern == 3 then
            -- JUMP WALK
            log("MOVEMENT", "Starting jump walk pattern")
            for i = 1, 4 do
                humanoid.Jump = true
                task.wait(0.5)
                local angle = math.random() * math.pi * 2
                local distance = math.random(8, CONFIG.MOVEMENT_DISTANCE)
                local direction = Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
                humanoid:MoveTo(rootPart.Position + direction)
                task.wait(2)
            end
            
        elseif movementPattern == 4 then
            -- SPIN WALK
            log("MOVEMENT", "Starting spin walk pattern")
            for i = 1, 6 do
                -- Spin
                local rotation = math.random(-180, 180)
                rootPart.CFrame = rootPart.CFrame * CFrame.Angles(0, math.rad(rotation), 0)
                task.wait(0.5)
                
                -- Walk
                local angle = math.random() * math.pi * 2
                local distance = math.random(6, CONFIG.MOVEMENT_DISTANCE)
                local direction = Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
                humanoid:MoveTo(rootPart.Position + direction)
                task.wait(2)
            end
            
        else
            -- BACK AND FORTH
            log("MOVEMENT", "Starting back and forth pattern")
            local startPos = currentPos
            for i = 1, 3 do
                local angle = math.random() * math.pi * 2
                local distance = math.random(10, CONFIG.MOVEMENT_DISTANCE)
                local direction = Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
                
                -- Go forward
                humanoid:MoveTo(startPos + direction)
                task.wait(3)
                
                -- Go back
                humanoid:MoveTo(startPos - direction)
                task.wait(3)
                
                -- Return to start
                humanoid:MoveTo(startPos)
                task.wait(2)
            end
        end
        
        State.movementCount = State.movementCount + 1
        State.lastMovement = os.time()
        State.lastActivity = os.time()
        
        log("MOVEMENT", string.format("Auto movement #%d completed!", State.movementCount))
        return true
    end)
    
    if not success then
        log("ERROR", "Auto movement failed")
        return false
    end
    return true
end

-- AUTOMATIC TOOL USAGE SYSTEM
local function performAutoToolUse()
    local success = pcall(function()
        local character = Players.LocalPlayer.Character
        local backpack = Players.LocalPlayer:FindFirstChild("Backpack")
        
        if not character or not backpack then 
            log("TOOL", "No character or backpack found")
            return false 
        end
        
        local humanoid = character:FindFirstChild("Humanoid")
        if not humanoid then 
            log("TOOL", "No humanoid found")
            return false 
        end
        
        -- Get all available tools
        local availableTools = {}
        for _, item in pairs(backpack:GetChildren()) do
            if item:IsA("Tool") then
                table.insert(availableTools, item)
            end
        end
        
        -- Also check equipped tools
        for _, item in pairs(character:GetChildren()) do
            if item:IsA("Tool") then
                table.insert(availableTools, item)
            end
        end
        
        if #availableTools == 0 then
            log("TOOL", "No tools available in inventory")
            return false
        end
        
        log("TOOL", string.format("Found %d tools, starting auto tool usage", #availableTools))
        
        -- Use multiple tools in sequence
        local toolsUsed = 0
        local maxTools = math.min(3, #availableTools) -- Use up to 3 tools
        
        for i = 1, maxTools do
            local tool = availableTools[math.random(1, #availableTools)]
            
            -- Equip tool
            if tool.Parent ~= character then
                humanoid:EquipTool(tool)
                task.wait(math.random(1, 2))
            end
            
            if tool.Parent == character then
                log("TOOL", "Using tool: " .. tool.Name)
                
                -- Use tool multiple times with movement
                for useCount = 1, math.random(3, 6) do
                    tool:Activate()
                    task.wait(math.random(0.5, 1.5))
                    
                    -- Sometimes move while using tool
                    if math.random() > 0.6 then
                        local rootPart = character:FindFirstChild("HumanoidRootPart")
                        if rootPart then
                            local angle = math.random() * math.pi * 2
                            local distance = math.random(2, 8)
                            local direction = Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
                            humanoid:MoveTo(rootPart.Position + direction)
                        end
                    end
                end
                
                toolsUsed = toolsUsed + 1
                log("TOOL", string.format("Finished using %s (%d/%d)", tool.Name, toolsUsed, maxTools))
                
                -- Wait before next tool
                task.wait(math.random(2, 4))
                
                -- Sometimes unequip, sometimes keep equipped
                if math.random() > 0.4 then
                    humanoid:UnequipTools()
                    task.wait(1)
                end
            end
        end
        
        State.toolUseCount = State.toolUseCount + 1
        State.lastToolUse = os.time()
        State.lastActivity = os.time()
        
        log("TOOL", string.format("Auto tool usage #%d completed! Used %d tools", State.toolUseCount, toolsUsed))
        return true
    end)
    
    if not success then
        log("ERROR", "Auto tool usage failed")
        return false
    end
    return true
end

-- AUTOMATIC SYSTEM CONTROLLER
local function runAutoSystems()
    if not State.autoSystemActive then return end
    
    local currentTime = os.time()
    
    -- EMERGENCY MODE (15 minutes of inactivity)
    if currentTime - State.lastActivity >= CONFIG.EMERGENCY_INTERVAL then
        log("MOVEMENT", "🚨 EMERGENCY AUTO SYSTEMS ACTIVATED! 🚨")
        
        -- Intensive automatic actions
        for i = 1, 3 do
            log("MOVEMENT", string.format("Emergency cycle %d/3", i))
            
            -- Movement
            task.spawn(performAutoMovement)
            task.wait(2)
            
            -- Tool usage
            task.spawn(performAutoToolUse)
            task.wait(3)
        end
        
        State.lastActivity = currentTime
        log("MOVEMENT", "Emergency auto systems completed!")
        return
    end
    
    -- AUTOMATIC MOVEMENT CHECK
    if CONFIG.AUTO_MOVEMENT_ENABLED and (currentTime - State.lastMovement) >= CONFIG.MOVEMENT_INTERVAL then
        log("MOVEMENT", "⚡ Starting automatic movement...")
        task.spawn(performAutoMovement)
    end
    
    -- AUTOMATIC TOOL USAGE CHECK
    if CONFIG.AUTO_TOOL_ENABLED and (currentTime - State.lastToolUse) >= CONFIG.TOOL_INTERVAL then
        log("TOOL", "🔧 Starting automatic tool usage...")
        task.spawn(performAutoToolUse)
    end
end

-- Data Management (No Stacking)
local function clearOldData()
    pcall(function()
        local clearRequest = {
            Url = CONFIG.API_URL,
            Method = "DELETE",
            Headers = {
                ["Authorization"] = CONFIG.AUTH_HEADER,
                ["Content-Type"] = "application/json",
                ["X-Session-ID"] = CONFIG.SESSION_ID,
                ["X-Action"] = "CLEAR_ALL"
            },
            Body = HttpService:JSONEncode({
                sessionId = CONFIG.SESSION_ID,
                action = "CLEAR_SESSION_DATA",
                timestamp = os.time(),
                force = true
            })
        }
        
        local request = http_request or request or (syn and syn.request)
        if request then
            local response = request(clearRequest)
            if response and response.StatusCode == 200 then
                log("INFO", "Old data cleared successfully")
            end
        end
    end)
end

local function sendFreshData(stockData)
    local success = pcall(function()
        if not stockData or not stockData.normal or not stockData.mirage then
            return false
        end
        
        local normalFruits = {}
        local mirageFruits = {}
        
        if stockData.normal then
            for _, fruit in pairs(stockData.normal) do
                if fruit and fruit.OnSale and fruit.Name and fruit.Price then
                    table.insert(normalFruits, {
                        name = tostring(fruit.Name),
                        price = tonumber(fruit.Price),
                        onSale = true
                    })
                end
            end
        end
        
        if stockData.mirage then
            for _, fruit in pairs(stockData.mirage) do
                if fruit and fruit.OnSale and fruit.Name and fruit.Price then
                    table.insert(mirageFruits, {
                        name = tostring(fruit.Name),
                        price = tonumber(fruit.Price),
                        onSale = true
                    })
                end
            end
        end
        
        clearOldData()
        task.wait(0.5)
        
        local freshPayload = {
            sessionId = CONFIG.SESSION_ID,
            timestamp = os.time(),
            playerName = Players.LocalPlayer.Name,
            serverId = game.JobId or "unknown",
            stockData = {
                normal = normalFruits,
                mirage = mirageFruits,
                totalCount = #normalFruits + #mirageFruits,
                lastUpdate = os.time()
            },
            autoSystemStats = {
                movementCount = State.movementCount,
                toolUseCount = State.toolUseCount,
                lastActivity = State.lastActivity
            },
            replaceMode = true,
            clearFirst = true,
            freshData = true
        }
        
        local sendRequest = {
            Url = CONFIG.API_URL,
            Method = "PUT",
            Headers = {
                ["Authorization"] = CONFIG.AUTH_HEADER,
                ["Content-Type"] = "application/json",
                ["X-Session-ID"] = CONFIG.SESSION_ID,
                ["X-Action"] = "REPLACE_DATA",
                ["X-Replace-Mode"] = "true"
            },
            Body = HttpService:JSONEncode(freshPayload)
        }
        
        local request = http_request or request or (syn and syn.request)
        if not request then
            return false
        end
        
        local response = request(sendRequest)
        
        if response and response.StatusCode >= 200 and response.StatusCode < 300 then
            State.updateCount = State.updateCount + 1
            log("INFO", string.format("FRESH DATA SENT - Normal: %d, Mirage: %d", #normalFruits, #mirageFruits))
            return true
        else
            log("ERROR", "Failed to send fresh data")
            return false
        end
    end)
    
    return success
end

-- Game Data
local function getStockData()
    local success, result = pcall(function()
        local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
        if not remotes then return nil end
        
        local CommF = remotes:WaitForChild("CommF_", 10)
        if not CommF then return nil end
        
        return {
            normal = CommF:InvokeServer("GetFruits", false),
            mirage = CommF:InvokeServer("GetFruits", true)
        }
    end)
    
    return success and result or nil
end

local function generateHash(data)
    if not data then return "" end
    
    local hashStr = ""
    for stockType, fruits in pairs(data) do
        if fruits then
            for _, fruit in pairs(fruits) do
                if fruit and fruit.OnSale then
                    hashStr = hashStr .. tostring(fruit.Name) .. tostring(fruit.Price)
                end
            end
        end
    end
    return hashStr
end

-- Session Cleanup
local function cleanupSession()
    pcall(function()
        if not State.sessionActive then return end
        
        log("INFO", "Cleaning up session...")
        
        local cleanupRequest = {
            Url = CONFIG.API_URL,
            Method = "DELETE",
            Headers = {
                ["Authorization"] = CONFIG.AUTH_HEADER,
                ["Content-Type"] = "application/json",
                ["X-Session-ID"] = CONFIG.SESSION_ID,
                ["X-Action"] = "FINAL_CLEANUP"
            },
            Body = HttpService:JSONEncode({
                sessionId = CONFIG.SESSION_ID,
                reason = "session_end",
                timestamp = os.time(),
                clearAll = true
            })
        }
        
        local request = http_request or request or (syn and syn.request)
        if request then
            request(cleanupRequest)
        end
        
        State.sessionActive = false
        log("INFO", "Session cleanup completed")
    end)
end

-- Main Loop
local function startMonitor()
    State.running = true
    State.lastUpdate = os.time()
    State.lastActivity = os.time()
    State.lastMovement = os.time()
    State.lastToolUse = os.time()
    
    log("INFO", "🚀 AUTO MOVEMENT + TOOL MONITOR STARTED! 🚀")
    log("INFO", "Player: " .. Players.LocalPlayer.Name)
    log("MOVEMENT", "✅ Automatic Movement: ENABLED")
    log("TOOL", "✅ Automatic Tool Usage: ENABLED")
    
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = "Auto Systems Active",
            Text = "Movement + Tool usage automated!",
            Duration = 8
        })
    end)
    
    local cycleCount = 0
    
    while State.running do
        -- RUN AUTOMATIC SYSTEMS
        runAutoSystems()
        
        -- Get and send stock data
        local stockData = getStockData()
        
        if stockData then
            local currentHash = generateHash(stockData)
            local timeSinceUpdate = os.time() - State.lastUpdate
            
            if currentHash ~= State.lastHash or timeSinceUpdate >= 60 then
                if sendFreshData(stockData) then
                    State.lastHash = currentHash
                    State.lastUpdate = os.time()
                end
            end
        end
        
        -- Status update
        cycleCount = cycleCount + 1
        if cycleCount >= 6 then
            local timeSinceMovement = os.time() - State.lastMovement
            local timeSinceToolUse = os.time() - State.lastToolUse
            local timeSinceActivity = os.time() - State.lastActivity
            
            log("INFO", string.format("📊 Updates: %d | Movements: %d | Tools: %d | Activity: %ds ago", 
                State.updateCount, State.movementCount, State.toolUseCount, timeSinceActivity))
            log("INFO", string.format("⏰ Next Movement: %ds | Next Tool: %ds", 
                math.max(0, CONFIG.MOVEMENT_INTERVAL - timeSinceMovement),
                math.max(0, CONFIG.TOOL_INTERVAL - timeSinceToolUse)))
            cycleCount = 0
        end
        
        task.wait(CONFIG.UPDATE_INTERVAL)
    end
    
    cleanupSession()
    log("INFO", "Monitor stopped")
end

-- Initialize
local function init()
    pcall(function()
        log("INFO", "Initializing AUTO MOVEMENT + TOOL monitor...")
        
        if not ReplicatedStorage:FindFirstChild("Remotes") then
            log("ERROR", "Not in Blox Fruits!")
            return
        end
        
        RunService.Heartbeat:Connect(function()
            if not game:IsLoaded() or not Players.LocalPlayer.Parent then
                cleanupSession()
            end
        end)
        
        task.spawn(startMonitor)
        
        log("INFO", "🎯 AUTO SYSTEMS READY!")
    end)
end

-- Controls
_G.StockMonitor = {
    stop = function()
        State.running = false
        State.autoSystemActive = false
        log("INFO", "Monitor and auto systems stopped")
    end,
    
    restart = function()
        State.running = false
        task.wait(2)
        init()
    end,
    
    status = function()
        print("=== AUTO MOVEMENT + TOOL MONITOR ===")
        print("Running:", State.running)
        print("Auto Systems Active:", State.autoSystemActive)
        print("Updates sent:", State.updateCount)
        print("Movements performed:", State.movementCount)
        print("Tools used:", State.toolUseCount)
        print("Last activity:", os.time() - State.lastActivity, "seconds ago")
        print("Last movement:", os.time() - State.lastMovement, "seconds ago")
        print("Last tool use:", os.time() - State.lastToolUse, "seconds ago")
        return State
    end,
    
    forceMovement = function()
        State.lastMovement = 0
        log("MOVEMENT", "Forced movement triggered")
    end,
    
    forceTool = function()
        State.lastToolUse = 0
        log("TOOL", "Forced tool usage triggered")
    end,
    
    toggleAutoSystems = function()
        State.autoSystemActive = not State.autoSystemActive
        log("INFO", "Auto systems " .. (State.autoSystemActive and "ENABLED" or "DISABLED"))
    end
}

-- Start
init()
log("INFO", "🎮 AUTOMATIC MOVEMENT + TOOL USAGE ACTIVE!")
log("INFO", "Movement every 45s | Tools every 60s | Emergency at 15min")
log("INFO", "Use _G.StockMonitor.status() for detailed info")
