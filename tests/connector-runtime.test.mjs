import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { test } from "node:test";

const prelude = String.raw`
local environment = {}
getgenv = function() return environment end
setthreadidentity = function() end
local now, scheduled = 0, {}
os = table.clone(os)
os.clock = function() return now end
local function resume(thread, ...)
    local ok, delay = coroutine.resume(thread, ...)
    assert(ok, delay)
    if coroutine.status(thread) ~= "dead" then
        scheduled[#scheduled + 1] = { at = now + (delay or 0.01), thread = thread }
    end
end
task = {}
function task.spawn(fn, ...)
    local thread = coroutine.create(fn)
    resume(thread, ...)
    return thread
end
function task.wait(delay) return coroutine.yield(delay or 0.01) end
function task.delay(delay, fn)
    local thread = coroutine.create(fn)
    scheduled[#scheduled + 1] = { at = now + delay, thread = thread }
    return thread
end
function task.defer(fn) return task.delay(0, fn) end
local function advance(seconds)
    local untilTime = now + seconds
    local steps = 0
    while true do
        local first
        for i, event in scheduled do
            if event.at <= untilTime and (not first or event.at < scheduled[first].at) then first = i end
        end
        if not first then break end
        local event = table.remove(scheduled, first)
        now = math.max(now, event.at)
        resume(event.thread)
        steps += 1
        assert(steps < 100000, "Runaway task scheduling")
    end
    now = math.max(now, untilTime)
end
local function signal()
    local self = { callbacks = {} }
    function self:Connect(callback)
        self.callbacks[#self.callbacks + 1] = callback
        return { Disconnect = function()
            for i, value in self.callbacks do
                if value == callback then table.remove(self.callbacks, i) break end
            end
        end }
    end
    function self:Fire(...)
        for _, callback in table.clone(self.callbacks) do task.spawn(callback, ...) end
    end
    return self
end
local prototype = {}
function prototype:IsA(class) return class == "LuaSourceContainer" or class == "LocalScript" end
function prototype:GetDebugId() return self.id end
function prototype:GetFullName() return "game." .. self.id end
function prototype:IsDescendantOf() return self.internal == true end
local function script(id) return setmetatable({ id = id }, { __index = prototype }) end
local scriptInstance = script("debug-1")
local internalScript = script("internal")
internalScript.internal = true
local lockedScript = script("locked")
lockedScript.RobloxLocked = true
local allScripts = { internalScript, lockedScript, scriptInstance }
local nilScripts = { scriptInstance }
local decompilations, queries, nilQueries = 0, 0, 0
local decompileTimes = {}
decompile = function(instance)
    assert(not instance.internal and not instance.RobloxLocked, "Do not decompile Roblox internal scripts")
    decompilations += 1
    decompileTimes[#decompileTimes + 1] = now
    return instance.source or "return 42"
end
getscriptbytecode = function(instance) return instance.bytecode or "test bytecode" end
getnilinstances = function() nilQueries += 1 return table.clone(nilScripts) end
Enum = { RunContext = { Client = "Client" } }
local createdInputs, destroyedInputs = 0, 0
Instance = { new = function()
    createdInputs += 1
    return { Destroy = function() destroyedInputs += 1 end }
end }
local services = {
    HttpService = { GenerateGUID = function() return "mapping-guid" end },
    LogService = { GetLogHistory = function() return {} end },
    Players = { LocalPlayer = { Name = "Tester", UserId = 1 } },
    MarketplaceService = { GetProductInfo = function() return { Name = "Test Game" } end },
    RobloxReplicatedStorage = {}, CoreGui = {}, CorePackages = {}, ScriptContext = {},
}
game = { PlaceId = 42, JobId = "job-1", DescendantAdded = signal(), DescendantRemoving = signal() }
function game:GetService(name) return services[name] end
function game:IsLoaded() return true end
function game:QueryDescendants() queries += 1 return table.clone(allScripts) end
local channels = 0
RelapseChannel = {}
function RelapseChannel.new(name)
    assert(name == "relapse.mcp.test")
    channels += 1
    testChannel = { Connected = signal(), IsPublished = true }
    function testChannel:Close() self.IsPublished = false end
    return testChannel
end
local function peer()
    local result = { Connected = true, MessageReceived = signal(), Disconnected = signal(), messages = {} }
    function result:Send(payload) self.messages[#self.messages + 1] = payload end
    function result:Close() self.Connected = false self.Disconnected:Fire() end
    return result
end
local function latestSources(p)
    for i = #p.messages, 1, -1 do
        if p.messages[i].type == "script-sources" then return p.messages[i] end
    end
    error("No source status received")
end
local function response(p, id)
    for _, message in p.messages do if message.id == id then return message end end
    error("No response for " .. id)
end
local function mapped(p)
    local result = {}
    for _, message in p.messages do
        if message.type ~= "script-sources" then continue end
        for _, id in message.removedScriptIds or {} do result[id] = nil end
        for _, entry in message.scripts do result[entry.debugId] = entry.source end
    end
    return result
end
local testPeer = peer()
`;

function run(t, assertions, setup = "") {
  const probe = spawnSync("luau", ["--help"], { encoding: "utf8" });
  if (probe.error?.code === "ENOENT") { t.skip("Luau CLI is unavailable"); return; }
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "relapse-mcp-luau-"));
  const file = path.join(dir, "connector.test.luau");
  try {
    const connector = fs.readFileSync("connector.luau", "utf8");
    fs.writeFileSync(file, `${prelude}\n${setup}\nlocal function inject()\nlocal __relapse_mcp_channel = "relapse.mcp.test"\n${connector}\nend\ninject()\n${assertions}`);
    const result = spawnSync("luau", [file], { encoding: "utf8", timeout: 10000 });
    assert.equal(result.status, 0, result.stderr || result.stdout);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

test("connector automatically indexes, handles requests, and cleans up", (t) => run(t, String.raw`
testChannel.Connected:Fire(testPeer)
assert(testPeer.messages[1].type == "hello")
assert(decompilations == 0, "Join should have a grace period")
advance(3)
assert(decompilations == 1, "Deduplicate descendants and nil instances")
assert(latestSources(testPeer).sourcesToMap == 1)
assert(latestSources(testPeer).hasFinishedMapping)
assert(mapped(testPeer)["debug-1"] == "return 42")
testPeer.MessageReceived:Fire({ id = "one", type = "get-data-by-code", source = "return 42" })
local decoded = loadstring("return " .. response(testPeer, "one").output)()
assert(decoded[1] == 42 and decoded.n == 1)
testPeer.MessageReceived:Fire({ id = "two", type = "get-script-content", debugId = "debug-1" })
assert(string.find(response(testPeer, "two").output, "return 42", 1, true))
assert(decompilations == 1, "Explicit reads should reuse cached sources")
testPeer.MessageReceived:Fire({ id = "three", type = "get-data-by-code",
    source = "return { [12] = 'sparse', [0] = 'zero', key = true }" })
local sparse = loadstring("return " .. response(testPeer, "three").output)()[1]
assert(sparse[12] == "sparse" and sparse[0] == "zero" and sparse.key == true)
testPeer:Close()
advance(30)
assert(not testChannel.IsPublished)
assert(next(environment) == nil)
assert(#game.DescendantAdded.callbacks == 0 and #game.DescendantRemoving.callbacks == 0)
assert(destroyedInputs == 1)
`));

test("multiple agents share the worker and receive incremental changes", (t) => run(t, String.raw`
testChannel.Connected:Fire(testPeer)
advance(3)
inject()
local second = peer()
testChannel.Connected:Fire(second)
advance(1)
assert(channels == 1 and createdInputs == 1)
assert(decompilations == 1 and queries == 1 and nilQueries == 1)
assert(mapped(second)["debug-1"] == "return 42", "Replay sources without decompiling again")
for _, value in environment do assert(type(value) == "boolean", "Keep internal state private") end
local added = script("debug-2")
for i = 1, 100 do game.DescendantAdded:Fire(added) end
advance(1)
assert(decompilations == 2 and queries == 1, "Additions must not restart a full scan")
assert(mapped(testPeer)["debug-2"] and mapped(second)["debug-2"])
game.DescendantRemoving:Fire(added)
game.DescendantAdded:Fire(added)
advance(1)
assert(decompilations == 2, "Coalesce reparenting without redecompilation")
game.DescendantRemoving:Fire(added)
advance(1)
assert(mapped(testPeer)["debug-2"] == nil and mapped(second)["debug-2"] == nil)
assert(latestSources(second).sourcesToMap == 1)
testPeer:Close()
assert(testChannel.IsPublished, "Keep the shared service until its final peer leaves")
second:Close()
advance(30)
assert(not testChannel.IsPublished and next(environment) == nil)
assert(decompilations == 2 and destroyedInputs == 1)
`));

test("automatic size limits skip oversized scripts but explicit reads can decompile them", (t) => run(t, String.raw`
testChannel.Connected:Fire(testPeer)
advance(4)
assert(decompilations == 2, "Oversized bytecode must not reach the decompiler")
assert(latestSources(testPeer).hasFinishedMapping)
assert(latestSources(testPeer).skippedSources == 2)
assert(mapped(testPeer)["small"] == "return 42")
assert(mapped(testPeer)["large-source"] == nil)
assert(decompileTimes[2] - decompileTimes[1] >= 0.25)
testPeer.MessageReceived:Fire({ id = "input", type = "get-script-content", debugId = "large-input" })
assert(string.find(response(testPeer, "input").output, "return 42", 1, true))
assert(decompilations == 3, "An explicit read must bypass the automatic bytecode limit")
testPeer.MessageReceived:Fire({ id = "cooldown", type = "get-script-content", debugId = "large-source" })
assert(string.find(response(testPeer, "cooldown").error, "cooling down", 1, true))
assert(decompilations == 3, "Explicit oversized reads must still respect the shared gate")
advance(0.25)
testPeer.MessageReceived:Fire({ id = "source", type = "get-script-content", debugId = "large-source",
    startLine = 262145, endLine = 262146 })
assert(response(testPeer, "source").output == "-- Lines 262145-262146 of 262147\nx\ntail")
assert(decompilations == 4, "Explicit reads must bypass the automatic source limit")
advance(0.25)
testPeer.MessageReceived:Fire({ id = "trailing", type = "get-script-content", debugId = "large-source",
    startLine = 262147 })
assert(response(testPeer, "trailing").output == "-- Lines 262147-262147 of 262147\n")
assert(decompilations == 5, "Oversized results must not be retained in the automatic cache")
assert(mapped(testPeer)["large-input"] == nil and mapped(testPeer)["large-source"] == nil)
assert(latestSources(testPeer).skippedSources == 2)
`, String.raw`
local bigInput, bigOutput, small = script("large-input"), script("large-source"), script("small")
bigInput.bytecode = string.rep("x", 128 * 1024 + 1)
bigOutput.source = string.rep("x\n", 262145) .. "tail\n"
allScripts, nilScripts = { bigInput, bigOutput, small }, {}
`));

test("explicit reads need no bytecode preflight and cap very long output lines", (t) => run(t, String.raw`
testChannel.Connected:Fire(testPeer)
advance(3)
assert(decompilations == 0 and latestSources(testPeer).skippedSources == 1)
testPeer.MessageReceived:Fire({ id = "long", type = "get-script-content", debugId = "debug-1" })
local output = response(testPeer, "long").output
assert(output == "-- Lines 1-1 of 1\n" .. string.rep("x", 1024 * 1024) ..
    "\n-- Output truncated to 1 MiB. Request a smaller line range.")
assert(decompilations == 1 and mapped(testPeer)["debug-1"] == nil)
`, String.raw`
getscriptbytecode = nil
scriptInstance.source = string.rep("x", 1024 * 1024 + 32)
`));

test("source cache and discovery queue have finite limits", (t) => {
  run(t, String.raw`
testChannel.Connected:Fire(testPeer)
advance(14)
assert(latestSources(testPeer).hasFinishedMapping)
assert(decompilations == 32, "Stop decompiling once the 16 MiB source cache is full")
assert(latestSources(testPeer).skippedSources == 3)
`, String.raw`
allScripts, nilScripts = {}, {}
local source = string.rep("x", 512 * 1024)
for i = 1, 35 do
    local item = script("cache-" .. i)
    item.source = source
    allScripts[i] = item
end
`);
  run(t, String.raw`
testChannel.Connected:Fire(testPeer)
advance(4)
assert(latestSources(testPeer).sourcesToMap == 10001, "10,000 entries plus an omitted-work marker")
assert(latestSources(testPeer).skippedSources >= 1)
testPeer:Close()
local previous = decompilations
advance(30)
assert(decompilations == previous, "Stop queued work on disconnect")
`, String.raw`
allScripts, nilScripts = {}, {}
for i = 1, 10010 do allScripts[i] = script("queue-" .. i) end
`);
});

test("slow decompilation never overlaps across peers and explicit reads", (t) => run(t, String.raw`
testChannel.Connected:Fire(testPeer)
advance(2.1)
assert(active == 1)
local second = peer()
inject()
testChannel.Connected:Fire(second)
second.MessageReceived:Fire({ id = "busy", type = "get-script-content", debugId = "debug-2" })
assert(string.find(response(second, "busy").error, "busy", 1, true))
advance(2)
assert(decompilations == 1 and peak == 1)
advance(7.8)
assert(decompilations == 1, "A 2-second call needs an 8-second cooldown")
advance(0.2)
assert(decompilations == 2 and peak == 1)
testPeer:Close()
second:Close()
advance(30)
assert(decompilations == 2 and active == 0)
`, String.raw`
local active, peak = 0, 0
allScripts, nilScripts = { scriptInstance, script("debug-2"), script("debug-3") }, {}
decompile = function()
    decompilations += 1
    active += 1
    peak = math.max(peak, active)
    task.wait(2)
    active -= 1
    return "return 42"
end
`));

test("formatter never executes game metamethods and bounds shared graphs", (t) => run(t, String.raw`
testChannel.Connected:Fire(testPeer)
trapCalls = 0
testPeer.MessageReceived:Fire({ id = "meta", type = "get-data-by-code", source = [[
    local function trap() trapCalls += 1 error("Game callback executed") end
    local key = setmetatable({}, { __tostring = trap })
    return setmetatable({ [key] = true, data = "ok" }, { __iter = trap })
]] })
assert(response(testPeer, "meta").output and trapCalls == 0)
testPeer.MessageReceived:Fire({ id = "error", type = "get-data-by-code", source = [[
    error(setmetatable({}, { __tostring = function() trapCalls += 1 return "unsafe" end }))
]] })
assert(response(testPeer, "error").error == "<table error>" and trapCalls == 0)
testPeer.MessageReceived:Fire({ id = "graph", type = "get-data-by-code", source = [[
    local graph = { value = true }
    for i = 1, 7 do graph = table.create(60, graph) end
    return graph
]] })
assert(#response(testPeer, "graph").output < 20000, "Do not expand shared subtrees exponentially")
`));

test("an injected connector without a peer expires", (t) => run(t, String.raw`
advance(21)
assert(not testChannel.IsPublished and next(environment) == nil)
assert(decompilations == 0 and destroyedInputs == 1)
`));
