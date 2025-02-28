local expect = require("cc.expect").expect

local Item = {}
Item.WILDCARD = "*"
Item.NO_NBT = "NONE"

---@class ItemDescriptor
---@field type "FROM_NAME"
local ItemDescriptor__index = { __type = "ItemDescriptor" }
local ItemDescriptor = { __index = ItemDescriptor__index }

---Check if NBT matches item's NBT
---@param nbt string
---@param item table
---@return boolean
local function matchNBT(nbt, item)
    return nbt == item.nbt or (nbt == Item.NO_NBT and item.nbt == nil) or nbt == Item.WILDCARD
end

local itemDescriptorTypes = {
    FROM_NAME = function(self, item)
        return item.name == self.name and matchNBT(self.nbt, item)
    end,
    FROM_PATTERN = function(self, item)
        local res = self.pattern:match(item.name)
        return not not res
    end,
    AND = function(self, item)
        return self.A:match(item) and self.B:match(item)
    end,
    OR = function(self, item)
        return self.A:match(item) or self.B:match(item)
    end,
    NOT = function(self, item)
        return not self.A:match(item)
    end
}

---Check if a given item matches this ItemDescriptor
---@param item table
---@return boolean
function ItemDescriptor__index:match(item)
    assert(itemDescriptorTypes[self.type], ("Invalid ItemDescriptor type %s"):format(self.type))
    return itemDescriptorTypes[self.type](self, item)
end

---Match items by their specific name
---  * NO_NBT assumed!
---@param name string
---@param nbt string?
---@return ItemDescriptor
function Item.fromName(name, nbt)
    expect(1, name, "string")
    expect(2, nbt, "string", "nil")
    nbt = nbt or Item.NO_NBT
    return setmetatable({ name = name, nbt = nbt, type = "FROM_NAME" }, ItemDescriptor)
end

---Match items by matching their name to a lua pattern
---  * NO_NBT assumed!
---@param pattern string
---@param nbt string?
---@return ItemDescriptor
function Item.fromPattern(pattern, nbt)
    expect(1, pattern, "string")
    expect(2, nbt, "string", "nil")
    nbt = nbt or Item.NO_NBT
    local ok, res = pcall(string.match, pattern, "test_1234:item_name")
    if not ok then
        error(res, 1)
    end
    return setmetatable({ pattern = pattern, nbt = nbt, type = "FROM_PATTERN" }, ItemDescriptor)
end

---Match items using an AND operation
---@param a ItemDescriptor
---@param b ItemDescriptor
---@return ItemDescriptor
function Item.gateAnd(a, b)
    expect(1, a, "table")
    expect(2, b, "table")
    return setmetatable({ A = a, B = b, type = "AND" }, ItemDescriptor)
end

---Match items using an OR operation
---@param a ItemDescriptor
---@param b ItemDescriptor
---@return ItemDescriptor
function Item.gateOr(a, b)
    expect(1, a, "table")
    expect(2, b, "table")
    return setmetatable({ A = a, B = b, type = "OR" }, ItemDescriptor)
end

---Match items using an OR operation
---@param a ItemDescriptor
---@return ItemDescriptor
function Item.gateNot(a, b)
    expect(1, a, "table")
    return setmetatable({ A = a, type = "NOT" }, ItemDescriptor)
end

return Item
