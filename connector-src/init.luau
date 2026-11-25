local channelName = __relapse_mcp_channel
if not game:IsLoaded() then game.Loaded:Wait() end
local env = getgenv()
local key = "__relapse_mcp_" .. channelName
-- Only a presence marker is shared. Channels, callbacks and index state stay local.
if rawget(env, key) then return end

local cloneref = cloneref or function(value) return value end
local HttpService = cloneref(game:GetService("HttpService"))
local LogService = cloneref(game:GetService("LogService"))
local Players = cloneref(game:GetService("Players"))
local MarketplaceService = cloneref(game:GetService("MarketplaceService"))
local RobloxReplicatedStorage = cloneref(game:GetService("RobloxReplicatedStorage"))
local CoreGui = cloneref(game:GetService("CoreGui"))
local CorePackages = cloneref(game:GetService("CorePackages"))
local ScriptContext = cloneref(game:GetService("ScriptContext"))
local VirtualInputManager = cloneref(Instance.new("VirtualInputManager"))

local Output = require("./output")
local state = { peers = {}, closed = false }
local channel = RelapseChannel.new(channelName)
local Bridge = { Callbacks = {}, RawCallbacks = {} }
function Bridge:BindToType(kind, callback) self.Callbacks[kind] = callback end
function Bridge:BindToTypeRaw(kind, callback)
    self.Callbacks[kind] = callback
    self.RawCallbacks[kind] = true
end
local function send(peer, payload)
    if state.closed or not peer.Connected then return false end
    local ok = pcall(peer.Send, peer, payload)
    -- A slow peer must reconnect and replay the cache instead of silently
    -- missing source updates or making us accumulate an unbounded send queue.
    if not ok then pcall(peer.Close, peer) end
    return ok
end
function Bridge:Send(payload, target)
    if target then return send(target, payload) end
    for peer, ready in state.peers do
        if ready then send(peer, payload) end
    end
    return true
end
function Bridge:HandleMessage(message, peer)
    if state.closed or state.peers[peer] ~= true then return end
    if type(message) ~= "table" or type(message.type) ~= "string" or type(message.id) ~= "string" then return end
    local callback = self.Callbacks[message.type]
    if not callback then
        send(peer, { id = message.id, error = "Unknown command: " .. message.type })
        return
    end
    task.spawn(function()
        local ok, result = pcall(callback, message)
        if not peer.Connected or state.closed then return end
        if not ok then
            send(peer, { id = message.id, error = Output.Error(result) })
        elseif result ~= nil then
            local output = if self.RawCallbacks[message.type] then result else Output.Format(result)
            if type(output) ~= "string" then
                send(peer, { id = message.id, error = "Handler returned an invalid text result." })
            elseif #output > 7 * 1024 * 1024 then
                send(peer, { id = message.id, error = "Result exceeds the Relapse channel limit. Request a smaller range or result." })
            else
                send(peer, { id = message.id, output = output })
            end
        end
    end)
end

local function isScript(instance)
    return instance:IsA("LuaSourceContainer") and
        (not instance:IsA("Script") or instance.RunContext == Enum.RunContext.Client) and
        not instance.RobloxLocked and not instance:IsDescendantOf(CoreGui) and
        not instance:IsDescendantOf(CorePackages) and not instance:IsDescendantOf(ScriptContext)
end
local index = require("./script-index")({
    HttpService = HttpService,
    IsScript = isScript,
    Send = function(payload, peer) return Bridge:Send(payload, peer) end,
    Error = Output.Error,
})
local context = {
    LogService = LogService,
    MarketplaceService = MarketplaceService,
    RobloxReplicatedStorage = RobloxReplicatedStorage,
    VirtualInputManager = VirtualInputManager,
    GetScriptByDebugId = index.GetScriptByDebugId,
    DecompileScriptSource = index.DecompileScriptSource,
}
for _, registrar in {
    require("./bridge/handlers/core"),
    require("./bridge/handlers/scripts"),
    require("./bridge/handlers/instances"),
    require("./bridge/handlers/remote-spy/logs"),
    require("./bridge/handlers/remote-spy/control"),
    require("./bridge/handlers/input"),
} do registrar(context, Bridge) end


local function close()
    if state.closed then return end
    state.closed = true
    index.Stop()
    channel:Close()
    pcall(function() VirtualInputManager:Destroy() end)
    rawset(env, key, nil)
end
channel.Connected:Connect(function(peer)
    if state.closed then peer:Close() return end
    state.peers[peer] = false
    peer.Disconnected:Connect(function()
        state.peers[peer] = nil
        if not next(state.peers) then close() end
    end)
    peer.MessageReceived:Connect(function(message) Bridge:HandleMessage(message, peer) end)
    local player = Players.LocalPlayer
    local placeName = "Unknown"
    pcall(function() placeName = MarketplaceService:GetProductInfo(game.PlaceId).Name end)
    if not send(peer, { type = "hello", client = {
        username = player and player.Name or "Unknown",
        userId = player and player.UserId or 0,
        placeId = game.PlaceId, jobId = game.JobId, placeName = placeName,
    } }) then return end
    state.peers[peer] = true
    index.Start()
    index.Sync(peer)
end)
rawset(env, key, true)
-- Hold the channel until a peer connects, and clean up failed bootstrap attempts.
task.delay(20, function()
    if not next(state.peers) then close() end
end)
