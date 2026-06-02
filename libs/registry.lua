---@class ssd.libs.registry
local registry = {}

---@class ssd.libs.registry.entry
---@field side string
---@field label string
---@field used boolean
---@field busy boolean
---@field missing boolean

---@type table<string,ssd.libs.registry.entry>
local registered = {}

-- TODO maybe route all inventory calls through this, just to track when each inventory is in use??

---@return ssd.libs.registry.entry[]
function registry.list()
    local t = {}
    for k, v in pairs(registered) do
        t[#t + 1] = v
    end
    return t
end

local function get_registry(side)
    local t = registered[side] or {
        busy = false,
        label = "",
        used = false,
        side = side,
        missing = false
    }
    registered[side] = t
    return t
end

function registry.on_event(e)
    if e[1] == "peripheral" and peripheral.hasType(e[2], "inventory") then
        local t = get_registry(e[2])
        t.missing = false
        return true
    elseif e[1] == "peripheral_detach" and registered[e[1]] then
        local t = get_registry(e[2])
        t.missing = true
        return true
    end
end

---@param side string
---@param label string
function registry.mark_used(side, label)
    local t = get_registry(side)
    -- TODO maybe assert that this peripheral wasn't already used?
    t.busy = true
    t.label = label
end

---@param side string
function registry.mark_free(side)
    local t = get_registry(side)
    t.busy = false
    t.label = ""
end

return registry
