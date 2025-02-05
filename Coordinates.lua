local lib = {}
local Item = require("ItemDescriptor")
local expect = require("cc.expect").expect

---@param periph string
---@param slot integer
---@return InventoryCoordinate
function lib.InventoryCoordinate(periph, slot)
    expect(1, periph, "string")
    expect(2, slot, "number")
    return periph .. "$" .. slot
end

---@param name string
---@param nbt string?
---@return ItemCoordinate
function lib.ItemCoordinate(name, nbt)
    expect(1, name, "string")
    expect(2, nbt, "string", "nil")
    return name .. "$" .. (nbt or Item.NO_NBT)
end

---@param coord InventoryCoordinate|ItemCoordinate
---@return string
---@return string
local function splitCoordinate(coord)
    expect(1, coord, "string")
    return coord:match("^(.-)%$([%a%d]+)$")
end
---@param coord InventoryCoordinate
---@return string
---@return integer
function lib.splitInventoryCoordinate(coord)
    expect(1, coord, "string")
    local inv, slot = splitCoordinate(coord)
    assert(inv, ("Unable to get inventory from InventoryCoordinate: %s"):format(coord))
    assert(tonumber(slot), ("Invalid slot in InventoryCoordinate: %s"):format(coord))
    return inv, tonumber(slot)
end

---@param coord ItemCoordinate
---@return string
---@return string
function lib.splitItemCoordinate(coord)
    expect(1, coord, "string")
    local name, nbt = splitCoordinate(coord)
    assert(name, ("Unable to get name from ItemCoordinate: %s"):format(coord))
    assert(nbt, ("Unable to get slot from ItemCoordinate: %s"):format(coord))
    return name, nbt
end

return lib
