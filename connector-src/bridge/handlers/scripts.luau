return function(context, Bridge)
    Bridge:BindToTypeRaw("get-script-content", function(data)
        local scriptInstance
        if data.debugId then
            scriptInstance = context.GetScriptByDebugId(data.debugId)
            assert(scriptInstance, "No live script instance found for DebugId: " .. tostring(data.debugId))
        else
            setthreadidentity(8)
            scriptInstance = loadstring(data.source)()
            assert(typeof(scriptInstance) == "Instance", "Script instance is not an instance.")
            assert(scriptInstance:IsA("LuaSourceContainer"), "Script instance is not a LuaSourceContainer.")
            assert(not (scriptInstance:IsA("Script") and scriptInstance.RunContext ~= Enum.RunContext.Client),
                "Script instance is server-only.")
        end
        local source, failure = context.DecompileScriptSource(scriptInstance)
        assert(source, failure or "Failed to decompile script.")
        -- Count and slice directly: an on-demand decompilation may be much
        -- larger than the automatic cache, so don't allocate a table per line.
        local total, cursor = 1, 1
        while true do
            local newline = string.find(source, "\n", cursor, true)
            if not newline then break end
            total += 1
            cursor = newline + 1
        end
        local maxLines = math.max(1, math.min(tonumber(data.maxLines) or 80, 2000))
        local startLine = math.max(1, math.min(tonumber(data.startLine) or 1, total))
        local requestedEnd = math.max(startLine, math.min(tonumber(data.endLine) or total, total))
        local endLine = math.min(requestedEnd, startLine + maxLines - 1)
        cursor = 1
        for _ = 1, startLine - 1 do cursor = string.find(source, "\n", cursor, true) + 1 end
        local first, last = cursor, #source
        for line = startLine, endLine do
            local newline = string.find(source, "\n", cursor, true)
            if line == endLine then last = if newline then newline - 1 else #source end
            if newline then cursor = newline + 1 end
        end
        -- Leave room for JSON escaping within the 8 MiB channel frame.
        local maxRangeBytes = 1024 * 1024
        local byteLimitHit = last - first + 1 > maxRangeBytes
        local footer = if endLine < requestedEnd then
            "\n-- Output truncated to " .. maxLines .. " lines. Rerun with startLine=" .. (endLine + 1) .. "."
            else ""
        if byteLimitHit then footer = "\n-- Output truncated to 1 MiB. Request a smaller line range." end
        return "-- Lines " .. startLine .. "-" .. endLine .. " of " .. total .. "\n" ..
            string.sub(source, first, math.min(last, first + maxRangeBytes - 1)) .. footer
    end)
end
