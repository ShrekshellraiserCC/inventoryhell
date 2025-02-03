local lib = {}
local Item = require("ItemDescriptor")

---@param periph string
---@param slot integer
---@return InventoryCoordinate
function lib.InventoryCoordinate(periph, slot)
    return periph .. "$" .. slot
end

---@param name string
---@param nbt string?
---@return ItemCoordinate
function lib.ItemCoordinate(name, nbt)
    return name .. "$" .. (nbt or Item.NO_NBT)
end

---@param coord InventoryCoordinate|ItemCoordinate
---@return string
---@return string
local function splitCoordinate(coord)
    return coord:match("^(.-)%$([%a%d]+)$")
end
---@param coord InventoryCoordinate
---@return string
---@return integer
function lib.splitInventoryCoordinate(coord)
    local inv, slot = splitCoordinate(coord)
    assert(inv, ("Unable to get inventory from InventoryCoordinate: %s"):format(coord))
    assert(tonumber(slot), ("Invalid slot in InventoryCoordinate: %s"):format(coord))
    return inv, tonumber(slot)
end

---@param coord ItemCoordinate
---@return string
---@return string
function lib.splitItemCoordinate(coord)
    local name, nbt = splitCoordinate(coord)
    assert(name, ("Unable to get name from ItemCoordinate: %s"):format(coord))
    assert(nbt, ("Unable to get slot from ItemCoordinate: %s"):format(coord))
    return name, nbt
end

return lib
