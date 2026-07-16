-- ============================================================
--              MM2 AUTO‑JOINER (Debug + Embed Support)
-- ============================================================

if getgenv().__mm2_autojoiner_loaded then return end
getgenv().__mm2_autojoiner_loaded = true

bottoken = bottoken or ""
chanelid = chanelid or ""
tradesbeforenext = tradesbeforenext or 1

print("[DEBUG] bottoken:", bottoken ~= "" and "set" or "missing")
print("[DEBUG] chanelid:", chanelid ~= "" and "set" or "missing")
print("[DEBUG] tradesbeforenext:", tradesbeforenext)

repeat task.wait() until game:IsLoaded()
print("[DEBUG] Game loaded, PlaceId:", game.PlaceId)
if game.PlaceId ~= 142823291 then 
    print("[DEBUG] Not MM2, exiting")
    return 
end

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
print("[DEBUG] Services loaded")

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

-- ========== DISCORD HELPERS ==========
local function react(msgid, emoji)
    if bottoken == "" then return end
    pcall(function()
        request({
            Url = "https://discord.com/api/v10/channels/"..chanelid.."/messages/"..msgid.."/reactions/"..HttpService:UrlEncode(emoji).."/@me",
            Method = "PUT",
            Headers = {["Authorization"] = "Bot "..bottoken}
        })
    end)
end

-- ========== TRADE AUTO‑ACCEPT ==========
local tradesDone = 0
local lastActivity = tick()
local function resetActivity() lastActivity = tick() end

ReplicatedStorage.Trade.UpdateTrade.OnClientEvent:Connect(function(nub)
    if nub.LastOffer then
        local last = nub.LastOffer
        while true do
            if nub.LastOffer ~= last then break end
            ReplicatedStorage.Trade.AcceptTrade:FireServer(game.PlaceId * 3, nub.LastOffer)
            resetActivity()
            task.wait(0.1)
        end
    end
end)

task.spawn(function()
    while true do
        local status = ReplicatedStorage.Trade.GetTradeStatus:InvokeServer()
        if status == "ReceivingRequest" then
            ReplicatedStorage.Trade.AcceptRequest:FireServer()
            resetActivity()
        end
        task.wait(0.1)
    end
end)

task.spawn(function()
    while true do
        local status = ReplicatedStorage.Trade.GetTradeStatus:InvokeServer()
        if status == "StartTrade" then
            local timer = 0
            repeat
                timer = timer + task.wait(0.1)
                if timer >= 7 then
                    ReplicatedStorage.Trade.DeclineTrade:FireServer()
                    break
                end
            until ReplicatedStorage.Trade.GetTradeStatus:InvokeServer() ~= "StartTrade"
            tradesDone = tradesDone + 1
            resetActivity()
        end
        task.wait(0.1)
    end
end)

-- ========== IDLE HOP LOGIC ==========
local currentJobMsgId = nil
local IDLE_TIMEOUT = 3
local MIN_STAY = 3

task.spawn(function()
    while true do
        task.wait(2)
        if not currentJobMsgId then continue end
        if tick() - lastActivity < MIN_STAY then continue end
        local tradeUI = LocalPlayer.PlayerGui:FindFirstChild("Trade")
        if (not tradeUI and (tick() - lastActivity >= IDLE_TIMEOUT)) or tradesDone >= tradesbeforenext then
            print("[DEBUG] Idle hop triggered, reacting ✅")
            react(currentJobMsgId, "✅")
            currentJobMsgId = nil
            tradesDone = 0
        end
    end
end)

-- ========== POPUP HANDLERS ==========
task.spawn(function()
    local gui = LocalPlayer.PlayerGui:WaitForChild("DeviceSelect", 60)
    if gui then
        while gui.Parent do
            pcall(function() firesignal(gui.Container.Phone.Button.MouseButton1Click) end)
            task.wait(0.1)
        end
    end
end)

task.spawn(function()
    while true do
        task.wait(0.5)
        local gui = LocalPlayer.PlayerGui
        if not gui then continue end
        local popup = gui:FindFirstChild("JoinFriends") or gui:FindFirstChild("FriendJoin") or gui:FindFirstChild("ConfirmJoin")
        if popup and popup.Visible then
            local btn = popup:FindFirstChild("Play", true) or popup:FindFirstChild("Join", true) or popup:FindFirstChild("ButtonPlay", true)
            if btn and btn:IsA("GuiButton") then
                pcall(function()
                    btn:Fire("MouseButton1Click")
                    if btn:FindFirstChild("RemoteEvent") then btn.RemoteEvent:FireServer() end
                end)
            end
        end
    end
end)

-- ========== FILE‑BASED QUEUE ==========
if not isfile("jnubs.txt") then writefile("jnubs.txt", "[]") end
if not isfile("queue.txt") then writefile("queue.txt", "[]") end

local function readlist(file)
    local ok, t = pcall(function() return HttpService:JSONDecode(readfile(file)) end)
    return ok and type(t)=="table" and t or {}
end
local function writelist(file, t)
    pcall(function() writefile(file, HttpService:JSONEncode(t)) end)
end
local function inlist(file, value)
    for _, v in ipairs(readlist(file)) do if v == value then return true end end
    return false
end
local function addtolist(file, value)
    local t = readlist(file)
    for _, v in ipairs(t) do if v == value then return end end
    table.insert(t, value)
    writelist(file, t)
end

-- ========== TELEPORT FUNCTION ==========
local teleporting = false
local currentTarget = nil

function teleportTo(placeId, jobId, msgid)
    print("[DEBUG] teleportTo called with placeId:", placeId, "jobId:", jobId, "msgid:", msgid)
    currentTarget = { placeId = tonumber(placeId), jobId = jobId, msgid = msgid }
    if teleporting then 
        print("[DEBUG] Already teleporting, skipping")
        return 
    end
    teleporting = true

    task.spawn(function()
        local failed = false
        local conn = TeleportService.TeleportInitFailed:Connect(function(player)
            if player == LocalPlayer then failed = true; print("[DEBUG] TeleportInitFailed fired") end
        end)

        while teleporting do
            local target = currentTarget
            failed = false
            print("[DEBUG] Attempting teleport to:", target.placeId, target.jobId)
            local ok, err = pcall(function()
                TeleportService:TeleportToPlaceInstance(target.placeId, target.jobId, LocalPlayer)
            end)
            if ok and target.msgid then
                print("[DEBUG] Teleport initiated successfully")
                addtolist("jnubs.txt", target.msgid)
                currentJobMsgId = target.msgid
                resetActivity()
                tradesDone = 0
            else
                print("[DEBUG] Teleport failed:", err)
                if target.msgid then react(target.msgid, "❌") end
                currentJobMsgId = nil
            end

            local t = 0
            while t < 5 and not failed and currentTarget == target do
                task.wait(0.5); t = t + 0.5
            end
            if currentTarget == target then
                print("[DEBUG] Retrying after 2s")
                task.wait(2)
            else
                print("[DEBUG] Target changed, breaking loop")
                break
            end
        end
        if conn then conn:Disconnect() end
        teleporting = false
        print("[DEBUG] Teleport loop ended")
    end)
end

-- ========== EMBED / CONTENT PARSING ==========
local function extractJobIdFromMessage(msg)
    local content = msg.content or ""
    -- Try content first
    local placeId, jobId = string.match(content, "(%d+),%s*'([^']+)'")
    if not (placeId and jobId) then
        placeId, jobId = string.match(content, 'TeleportToPlaceInstance%s*%(%s*"(%d+)"%s*,%s*"([^"]+)"')
    end
    if placeId and jobId then
        return placeId, jobId
    end

    -- If not found, check embeds
    if msg.embeds then
        for _, embed in ipairs(msg.embeds) do
            local desc = embed.description or ""
            placeId, jobId = string.match(desc, "(%d+),%s*'([^']+)'")
            if not (placeId and jobId) then
                placeId, jobId = string.match(desc, 'TeleportToPlaceInstance%s*%(%s*"(%d+)"%s*,%s*"([^"]+)"')
            end
            if not (placeId and jobId) then
                -- Also check fields
                if embed.fields then
                    for _, field in ipairs(embed.fields) do
                        local val = field.value or ""
                        placeId, jobId = string.match(val, "(%d+),%s*'([^']+)'")
                        if not (placeId and jobId) then
                            placeId, jobId = string.match(val, 'TeleportToPlaceInstance%s*%(%s*"(%d+)"%s*,%s*"([^"]+)"')
                        end
                        if placeId and jobId then break end
                    end
                end
            end
            if placeId and jobId then break end
        end
    end
    return placeId, jobId
end

-- ========== PROCESS DISCORD MESSAGES ==========
local function processJoinMessage(msg)
    if not msg or not msg.author then 
        print("[DEBUG] processJoinMessage: no msg or author")
        return 
    end
    if msg.channel_id and msg.channel_id ~= chanelid then 
        print("[DEBUG] Wrong channel:", msg.channel_id)
        return 
    end
    local content = msg.content or ""
    print("[DEBUG] Processing message content:", content)
    -- Check if this is an embed message without content
    if content == "" and msg.embeds then
        print("[DEBUG] Message has embeds, will parse those.")
    end

    local placeId, jobId = extractJobIdFromMessage(msg)
    if not (placeId and jobId) then
        print("[DEBUG] Could not parse placeId/jobId from message or embeds.")
        return
    end
    print("[DEBUG] Parsed -> placeId:", placeId, "jobId:", jobId)
    if tonumber(placeId) ~= 142823291 then 
        print("[DEBUG] Not MM2 place, ignoring")
        return 
    end

    react(msg.id, "👀")
    if inlist("jnubs.txt", msg.id) then 
        print("[DEBUG] Already processed this message, ignoring")
        return 
    end
    if jobId == game.JobId then 
        print("[DEBUG] JobId matches current server, ignoring")
        return 
    end

    local q = readlist("queue.txt")
    for _, j in ipairs(q) do 
        if j.msgid == msg.id then 
            print("[DEBUG] Already in queue, ignoring")
            return 
        end 
    end
    table.insert(q, { placeId = placeId, jobId = jobId, msgid = msg.id, author = msg.author.username })
    writelist("queue.txt", q)
    print("[DEBUG] Added to queue, queue size:", #q)
end

-- ========== QUEUE PROCESSOR ==========
task.spawn(function()
    while true do
        task.wait(1)
        if not teleporting then
            local q = readlist("queue.txt")
            if #q > 0 then
                local job = table.remove(q, 1)
                writelist("queue.txt", q)
                print("[DEBUG] Queue processor picked job:", job.placeId, job.jobId)
                if job and job.msgid and not inlist("jnubs.txt", job.msgid) and job.jobId ~= game.JobId then
                    teleportTo(job.placeId, job.jobId, job.msgid)
                else
                    print("[DEBUG] Skipping job – already done or same server")
                end
            end
        end
    end
end)

-- ========== DISCORD GATEWAY ==========
local socket, sequenceNumber, sessionId, resumeUrl, shouldResume = nil, nil, nil, nil, false
local connectionId = 0
local readyConnId, helloConnId = 0, 0

function sendPayload(op, d)
    if not socket then return end
    pcall(function() socket:Send(HttpService:JSONEncode({ op = op, d = d })) end)
end

function connectgateway()
    if bottoken == "" then print("[Gateway] No token – skipping."); return end
    connectionId = connectionId + 1
    local myId = connectionId
    local url = "wss://gateway.discord.gg/?v=10&encoding=json"
    if shouldResume and resumeUrl then url = resumeUrl .. "/?v=10&encoding=json" end

    socket = WebSocket.connect(url)
    socket.OnMessage:Connect(function(msg)
        if connectionId ~= myId then return end
        local data = HttpService:JSONDecode(msg)
        if data.s then sequenceNumber = data.s end

        if data.op == 10 then
            helloConnId = myId
            local heartbeat = data.d.heartbeat_interval / 1000
            if shouldResume and sessionId and sequenceNumber then
                sendPayload(6, { token = bottoken, session_id = sessionId, seq = sequenceNumber })
            else
                sendPayload(2, { token = bottoken, intents = 33280, properties = { os = "linux", browser = "opsec", device = "desktop" } })
            end
            task.spawn(function()
                while connectionId == myId and socket do
                    task.wait(heartbeat)
                    if connectionId ~= myId then break end
                    sendPayload(1, sequenceNumber)
                end
            end)
        end

        if data.op == 0 then
            if data.t == "READY" then
                sessionId = data.d.session_id
                resumeUrl = data.d.resume_gateway_url
                shouldResume = true
                readyConnId = myId
                print("[Gateway] Ready")
            elseif data.t == "RESUMED" then
                readyConnId = myId
                print("[Gateway] Resumed")
            elseif data.t == "MESSAGE_CREATE" then
                local msg = data.d
                if msg.channel_id == chanelid then
                    processJoinMessage(msg)
                end
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
        if connectionId ~= myId then return end
        socket = nil
        if sessionId and sequenceNumber then shouldResume = true end
        task.wait(5 + math.random()*5)
        if connectionId == myId then connectgateway() end
    end)

    task.spawn(function()
        task.wait(6)
        if connectionId == myId and helloConnId ~= myId then
            pcall(function() if socket then socket:Close() end end)
            if connectionId == myId then socket = nil; connectgateway() end
            return
        end
        if connectionId ~= myId then return end
        task.wait(8)
        if connectionId == myId and readyConnId ~= myId then
            pcall(function() if socket then socket:Close() end end)
            task.wait(3 + math.random()*4)
            if connectionId == myId then socket = nil; connectgateway() end
        end
    end)
end

connectgateway()
print("[MM2 Autojoiner] Debug with embed support started.")
