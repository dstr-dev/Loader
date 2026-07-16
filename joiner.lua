-- ============================================================
--              MM2 AUTO‑JOINER (Ultra Simple)
-- ============================================================
-- Set these before running:
--   bottoken = "your_token"
--   chanelid = "your_channel"
--   tradesbeforenext = 1   (optional)
-- ============================================================

if getgenv().__mm2_autojoiner_loaded then return end
getgenv().__mm2_autojoiner_loaded = true

bottoken = bottoken or ""
chanelid = chanelid or ""
tradesbeforenext = tradesbeforenext or 1

repeat task.wait() until game:IsLoaded()
if game.PlaceId ~= 142823291 then return end

local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local LocalPlayer = game.Players.LocalPlayer

-- Anti‑AFK
for _, b in ipairs(getconnections(LocalPlayer.Idled)) do b:Disable() end
task.spawn(function()
    while true do
        task.wait(60)
        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
            local h = LocalPlayer.Character.Humanoid
            h:Move(Vector3.new(1,0,0), true); task.wait(0.1)
            h:Move(Vector3.new(-1,0,0), true); task.wait(0.1)
            h:Move(Vector3.new(0,0,0), true)
        end
    end
end)

-- Auto‑accept trades (super simple)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
ReplicatedStorage.Trade.UpdateTrade.OnClientEvent:Connect(function(nub)
    if nub.LastOffer then
        local last = nub.LastOffer
        while true do
            if nub.LastOffer ~= last then break end
            ReplicatedStorage.Trade.AcceptTrade:FireServer(game.PlaceId * 3, nub.LastOffer)
            task.wait(0.1)
        end
    end
end)
task.spawn(function()
    while true do
        local status = ReplicatedStorage.Trade.GetTradeStatus:InvokeServer()
        if status == "ReceivingRequest" then
            ReplicatedStorage.Trade.AcceptRequest:FireServer()
        end
        task.wait(0.1)
    end
end)

-- Popup handler
task.spawn(function()
    local gui = LocalPlayer.PlayerGui:WaitForChild("DeviceSelect", 60)
    if gui then
        while gui.Parent do
            pcall(function() firesignal(gui.Container.Phone.Button.MouseButton1Click) end)
            task.wait(0.1)
        end
    end
end)

-- ========== ROBUST UUID EXTRACTION ==========
local function extractUUID(text)
    if not text then return nil end
    -- UUID pattern: 8-4-4-4-12 hex digits
    local uuid = string.match(text, "%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x")
    return uuid
end

local function getJobIdFromMessage(msg)
    -- 1. Check content
    local content = msg.content or ""
    local uuid = extractUUID(content)
    if uuid then return uuid end

    -- 2. Check embeds
    if msg.embeds then
        for _, embed in ipairs(msg.embeds) do
            if embed.description then
                uuid = extractUUID(embed.description)
                if uuid then return uuid end
            end
            if embed.fields then
                for _, field in ipairs(embed.fields) do
                    if field.value then
                        uuid = extractUUID(field.value)
                        if uuid then return uuid end
                    end
                end
            end
        end
    end
    return nil
end

-- ========== TELEPORT FUNCTION ==========
local function teleportToJob(jobId, msgId)
    print("[Teleport] Attempting to join:", jobId)
    local ok, err = pcall(function()
        TeleportService:TeleportToPlaceInstance(142823291, jobId, LocalPlayer)
    end)
    if ok then
        print("[Teleport] Success – teleport initiated.")
        if msgId then
            -- React ✅ if we have the message ID
            pcall(function()
                local url = "https://discord.com/api/v10/channels/"..chanelid.."/messages/"..msgId.."/reactions/%E2%9C%85/@me"
                request({Url = url, Method = "PUT", Headers = {["Authorization"] = "Bot "..bottoken}})
            end)
        end
    else
        print("[Teleport] Failed:", err)
        if msgId then
            pcall(function()
                local url = "https://discord.com/api/v10/channels/"..chanelid.."/messages/"..msgId.."/reactions/%E2%9D%8C/@me"
                request({Url = url, Method = "PUT", Headers = {["Authorization"] = "Bot "..bottoken}})
            end)
        end
    end
end

-- ========== PROCESS MESSAGES ==========
local processed = {} -- avoid duplicates

local function handleMessage(msg)
    if msg.channel_id ~= chanelid then return end
    if processed[msg.id] then return end
    processed[msg.id] = true

    local jobId = getJobIdFromMessage(msg)
    if not jobId then
        print("[Debug] No UUID found in message.")
        return
    end

    print("[Debug] Found job ID:", jobId)

    -- If we're already in that server, skip
    if jobId == game.JobId then
        print("[Debug] Already in this server.")
        return
    end

    -- Teleport immediately
    teleportToJob(jobId, msg.id)
end

-- ========== DISCORD GATEWAY (minimal) ==========
local socket, seq, sessionId, resumeUrl, shouldResume = nil, nil, nil, nil, false
local connId = 0

function send(op, d)
    if not socket then return end
    pcall(function() socket:Send(HttpService:JSONEncode({op = op, d = d})) end)
end

function connect()
    if bottoken == "" then print("[Gateway] No token, exiting."); return end
    connId = connId + 1
    local myId = connId
    local url = "wss://gateway.discord.gg/?v=10&encoding=json"
    if shouldResume and resumeUrl then url = resumeUrl .. "/?v=10&encoding=json" end

    socket = WebSocket.connect(url)
    socket.OnMessage:Connect(function(message)
        if connId ~= myId then return end
        local data = HttpService:JSONDecode(message)
        if data.s then seq = data.s end

        if data.op == 10 then
            local heartbeat = data.d.heartbeat_interval / 1000
            if shouldResume and sessionId and seq then
                send(6, {token = bottoken, session_id = sessionId, seq = seq})
            else
                send(2, {token = bottoken, intents = 33280, properties = {os = "linux", browser = "opsec", device = "desktop"}})
            end
            task.spawn(function()
                while connId == myId and socket do
                    task.wait(heartbeat)
                    if connId ~= myId then break end
                    send(1, seq)
                end
            end)
        end

        if data.op == 0 then
            if data.t == "READY" then
                sessionId = data.d.session_id
                resumeUrl = data.d.resume_gateway_url
                shouldResume = true
                print("[Gateway] Ready")
            elseif data.t == "RESUMED" then
                print("[Gateway] Resumed")
            elseif data.t == "MESSAGE_CREATE" then
                handleMessage(data.d)
            end
        end

        if data.op == 7 then shouldResume = true; pcall(function() if socket then socket:Close() end end) end
        if data.op == 9 then
            shouldResume = (data.d == true)
            if not shouldResume then sessionId = nil end
            task.wait(math.random(1,5))
            pcall(function() if socket then socket:Close() end end)
        end
    end)

    socket.OnClose:Connect(function()
        if connId ~= myId then return end
        socket = nil
        if sessionId and seq then shouldResume = true end
        task.wait(5 + math.random()*5)
        if connId == myId then connect() end
    end)

    -- Watchdog
    task.spawn(function()
        task.wait(6)
        if connId == myId and not socket then connect() end
    end)
end

connect()
print("[AutoJoiner] Running. Waiting for messages with a job ID (UUID).")
