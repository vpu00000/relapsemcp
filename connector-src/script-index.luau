-- One index and one decompiler gate shared by every peer on this connector.
-- These limits bound our work/cache, not allocations inside a native decompiler.
local MAX_SCRIPTS = 10000
local MAX_AUTO_BYTECODE = 128 * 1024
local MAX_AUTO_SOURCE = 512 * 1024
local MAX_CACHE = 16 * 1024 * 1024
local TICK = 0.25
local BATCH_BYTES = 128 * 1024
local BATCH_COUNT = 16

return function(context)
    local records = {}
    local instances = setmetatable({}, { __mode = "v" })
    local changes = {}
    local queue, head, tail = {}, 1, 0
    local total, processed, skipped, cacheBytes = 0, 0, 0, 0
    local limitHit = false
    local running, started, discovered, busy = false, false, false, false
    local nextDecompileAt = 0
    local addedConnection, removingConnection
    local revision = 0
    local mappingId = context.HttpService:GenerateGUID(false)
    local mappingStartedAt = os.time() * 1000
    local statusDirty = true
    local nativeDecompile, readBytecode = decompile, getscriptbytecode

    local function finished()
        return discovered and head > tail and not busy
    end

    local function emit(sources, removed, peer, begin)
        revision += 1
        return context.Send({ type = "script-sources", scripts = sources, removedScriptIds = removed,
            sourcesToMap = total + (if limitHit then 1 else 0),
            processedSources = processed + (if limitHit then 1 else 0),
            skippedSources = skipped + (if limitHit then 1 else 0),
            hasFinishedMapping = finished(), mappingSessionId = mappingId,
            mappingSessionStartedAt = mappingStartedAt, mappingRevision = revision,
            beginMappingSession = begin == true }, peer)
    end

    local function scriptId(instance)
        local ok, id = pcall(function() return instance:GetDebugId() end)
        return if ok and type(id) == "string" and #id <= 256 then id else nil
    end

    local function pathOf(instance)
        local ok, path = pcall(function() return instance:GetFullName() end)
        return if ok and type(path) == "string" then path:sub(1, 2048) else "<script>"
    end

    local function add(instance)
        if not running then return end
        local ok, selected = pcall(context.IsScript, instance)
        if not ok or not selected then return end
        local id = scriptId(instance)
        if not id then return end
        local record = records[id]
        if record then
            record.removed = false
            record.path = pathOf(instance)
            instances[id] = instance
            changes[id] = record
            return
        end
        if total >= MAX_SCRIPTS or tail - head + 1 >= MAX_SCRIPTS then
            limitHit = true
            statusDirty = true
            return
        end
        -- Pending jobs keep their wrapper alive until processed. The completed
        -- registry is weak, so indexed scripts are not pinned by their cache.
        record = { debugId = id, path = pathOf(instance), status = "queued", pendingInstance = instance }
        records[id] = record
        instances[id] = instance
        total += 1
        tail += 1
        queue[tail] = record
        statusDirty = true
    end

    local function remove(instance)
        local ok, selected = pcall(context.IsScript, instance)
        if not ok or not selected then return end
        local id = scriptId(instance)
        local record = id and records[id]
        if not record then return end
        -- Defer the change to the worker, coalescing reparenting and event bursts.
        record.removed = true
        changes[id] = record
    end

    local function sourceEntry(record)
        return { debugId = record.debugId, path = record.path, source = record.source }
    end

    local function flush()
        local batch, removed, bytes, count = {}, {}, 0, 0
        for id, record in changes do
            changes[id] = nil
            if record.removed then
                records[id] = nil
                instances[id] = nil
                total -= 1
                if record.status ~= "queued" then processed -= 1 end
                if record.status == "skipped" then skipped -= 1 end
                if record.source then cacheBytes -= #record.source end
                record.source = nil
                record.pendingInstance = nil
                removed[#removed + 1] = id
            elseif record.source then
                batch[#batch + 1] = sourceEntry(record)
                bytes += #record.source + #record.path + #id + 256
            end
            count += 1
            if count >= BATCH_COUNT or bytes >= BATCH_BYTES then break end
        end
        if statusDirty or count > 0 then
            statusDirty = false
            emit(batch, removed)
        end
    end

    local function readSource(instance, automatic)
        local id = scriptId(instance)
        local record = id and records[id]
        if record and record.source and not record.removed then return record.source end
        if busy or os.clock() < nextDecompileAt then
            return nil, "Decompiler is busy or cooling down. Try again shortly."
        end
        if automatic and type(readBytecode) ~= "function" then
            return nil, "getscriptbytecode is required to enforce the automatic indexing input limit."
        end
        busy = true
        local startedAt = os.clock()
        local ok, source, failure = pcall(function()
            if automatic then
                local bytecode = readBytecode(instance)
                if type(bytecode) ~= "string" or #bytecode == 0 then return nil, "Script bytecode is unavailable." end
                if #bytecode > MAX_AUTO_BYTECODE then return nil, "Script exceeds the 128 KiB automatic indexing bytecode limit." end
            end
            local result = nativeDecompile(instance)
            if type(result) ~= "string" or #result == 0 then return nil, "Failed to decompile script." end
            if automatic and #result > MAX_AUTO_SOURCE then return nil, "Script exceeds the 512 KiB automatic indexing source limit." end
            return result
        end)
        -- Wait at least four times the work duration: at most ~20% duty cycle
        -- across automatic indexing AND explicit reads, even with many agents.
        nextDecompileAt = os.clock() + math.max(TICK, (os.clock() - startedAt) * 4)
        busy = false
        if not ok then return nil, context.Error(source) end
        return source, failure
    end

    local function discover()
        local function collect(list)
            for index, instance in list do
                list[index] = nil
                if not running then return end
                add(instance)
                if index % 128 == 0 then task.wait() end
            end
        end
        collect(game:QueryDescendants("LuaSourceContainer"))
        if running and type(getnilinstances) == "function" then
            local ok, list = pcall(getnilinstances)
            if ok and type(list) == "table" then collect(list) end
        end
    end

    local function work()
        while head <= tail do
            local record = queue[head]
            if record and not record.removed and records[record.debugId] == record then
                if busy or os.clock() < nextDecompileAt then return end
                local instance = record.pendingInstance
                local source
                if instance and cacheBytes < MAX_CACHE then source = readSource(instance, true) end
                if not running then return end
                if records[record.debugId] == record and not record.removed then
                    if source and cacheBytes + #source <= MAX_CACHE then
                        record.source = source
                        cacheBytes += #source
                        record.status = "mapped"
                        changes[record.debugId] = record
                    else
                        record.status = "skipped"
                        skipped += 1
                    end
                    processed += 1
                end
                queue[head] = nil
                record.pendingInstance = nil
                head += 1
                statusDirty = true
                break
            end
            queue[head] = nil
            head += 1
            statusDirty = true
        end
        if head > tail then
            queue, head, tail = {}, 1, 0
        elseif head > MAX_SCRIPTS then
            local compact = {}
            for i = head, tail do compact[#compact + 1] = queue[i] end
            queue, head, tail = compact, 1, #compact
        end
    end

    return {
        Start = function()
            if started then return end
            started, running = true, true
            addedConnection = game.DescendantAdded:Connect(add)
            removingConnection = game.DescendantRemoving:Connect(remove)
            task.spawn(function()
                setthreadidentity(8)
                task.wait(2) -- Let the join settle before starting automatic work.
                if not running then return end
                local ok = pcall(discover)
                if not running then return end
                if not ok then limitHit = true end
                discovered, statusDirty = true, true
                while running do
                    flush()
                    work()
                    flush()
                    task.wait(TICK)
                end
            end)
        end,
        Sync = function(peer)
            emit({}, {}, peer, true)
            task.spawn(function()
                -- Copy only bounded IDs; look up live entries after each yield so
                -- a removal cannot be resurrected by an old snapshot batch.
                local ids = {}
                for id in records do ids[#ids + 1] = id end
                local batch, bytes = {}, 0
                for _, id in ids do
                    if not running or not peer.Connected then return end
                    local record = records[id]
                    if record and record.source and not record.removed then
                        batch[#batch + 1] = sourceEntry(record)
                        bytes += #record.source + #record.path + #id + 256
                        if #batch >= BATCH_COUNT or bytes >= BATCH_BYTES then
                            if not emit(batch, {}, peer) then return end
                            batch, bytes = {}, 0
                            task.wait(TICK)
                        end
                    end
                end
                if running and peer.Connected then emit(batch, {}, peer) end
            end)
        end,
        GetScriptByDebugId = function(id) return instances[id] end,
        -- Explicit reads can inspect scripts skipped by automatic indexing.
        -- Return the source only to the caller; do not grow the shared cache.
        DecompileScriptSource = function(instance) return readSource(instance, false) end,
        Stop = function()
            running = false
            if addedConnection then addedConnection:Disconnect() end
            if removingConnection then removingConnection:Disconnect() end
            table.clear(records)
            table.clear(instances)
            table.clear(changes)
            table.clear(queue)
        end,
    }
end
