-- Never invoke metamethods on values supplied by game code while formatting them.
local function sanitize(value, depth, seen, budget)
    budget.remaining -= 1
    if budget.remaining < 0 then return "<output limit>" end
    local kind = typeof(value)
    if kind == "Instance" then
        local ok, name = pcall(function() return value:GetFullName() end)
        return if ok then string.sub(name, 1, 500) else "<Instance>"
    end
    if kind == "string" then return if #value > 500 then value:sub(1, 500) .. "… [truncated]" else value end
    if kind == "number" or kind == "boolean" or kind == "nil" then return value end
    if kind ~= "table" then return "<" .. kind .. ">" end
    if depth >= 8 then return "<max depth>" end
    if seen[value] then return "<repeated table>" end
    seen[value] = true
    local result = {}
    local count = 0
    for itemKey, itemValue in next, value do
        count += 1
        if count > 60 or budget.remaining <= 0 then
            result.__omitted = "more entries omitted"
            break
        end
        local keyKind = type(itemKey)
        local key = if keyKind == "string" then itemKey:sub(1, 500)
            elseif keyKind == "number" then itemKey else "<" .. keyKind .. " key " .. count .. ">"
        result[key] = sanitize(itemValue, depth + 1, seen, budget)
    end
    return result
end

local function serialize(value)
    local kind = type(value)
    if kind == "string" then return string.format("%q", value) end
    if kind == "number" or kind == "boolean" then return tostring(value) end
    if kind == "nil" then return "nil" end
    local parts = {}
    for key, item in next, value do
        parts[#parts + 1] = "[" .. serialize(key) .. "] = " .. serialize(item)
    end
    return "{" .. table.concat(parts, ", ") .. "}"
end

return {
    Format = function(value)
        local clean = sanitize(value, 0, {}, { remaining = 2048 })
        return serialize(if type(clean) == "table" then clean else { clean })
    end,
    Error = function(value)
        local kind = type(value)
        return if kind == "string" then value:sub(1, 1000)
            elseif kind == "number" or kind == "boolean" then tostring(value)
            else "<" .. kind .. " error>"
    end,
}
