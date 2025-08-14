local lib = {}
local Item = require("libs.ItemDescriptor")
local expect = require("cc.expect").expect

---@param periph string
---@param slot integer
---@return InventoryCoordinate
function lib.InventoryCoordinate(periph, slot)
    expect(1, periph, "string")
    expect(2, slot, "number")
    return periph .. "@" .. slot
end

---@param name string
---@param nbt string?
---@return ItemCoordinate
function lib.ItemCoordinate(name, nbt)
    expect(1, name, "string")
    expect(2, nbt, "string", "nil")
    return name .. "$" .. (nbt or Item.NO_NBT)
end

---@param coord InventoryCoordinate
---@return string
---@return integer
function lib.splitInventoryCoordinate(coord)
    expect(1, coord, "string")
    local inv, slot = coord:match("^(.-)@([%a%d]+)$")
    assert(inv, ("Unable to get inventory from InventoryCoordinate: %s"):format(coord))
    local n = tonumber(slot)
    assert(n, ("Invalid slot in InventoryCoordinate: %s"):format(coord))
    return inv, n
end

---@param coord ItemCoordinate
---@return string
---@return string
function lib.splitItemCoordinate(coord)
    expect(1, coord, "string")
    local name, nbt = coord:match("^(.-)%$([%a%d]+)$")
    assert(name, ("Unable to get name from ItemCoordinate: %s"):format(coord))
    assert(nbt, ("Unable to get slot from ItemCoordinate: %s"):format(coord))
    return name, nbt
end

return lib
