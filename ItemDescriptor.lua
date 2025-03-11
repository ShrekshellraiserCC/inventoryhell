local expect = require("cc.expect").expect

local Item = {}
Item.WILDCARD = "*"
Item.NO_NBT = "NONE"

---@class ItemDescriptor
---@field type string
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
    end,
    HAS_TAG = function(self, item)
        return (item.tags or {})[self.tag]
    end
}

---Check if a given item matches this ItemDescriptor
---@param item table
---@return boolean
function ItemDescriptor__index:match(item)
    assert(itemDescriptorTypes[self.type], ("Invalid ItemDescriptor type %s"):format(self.type))
    return itemDescriptorTypes[self.type](self, item)
end

function ItemDescriptor__index:serialize()
    local s = ""
    if self.type == "FROM_NAME" then
        s = "N" .. self.name
        if self.nbt ~= Item.NO_NBT then
            s = s .. "$" .. self.nbt
        end
    elseif self.type == "FROM_PATTERN" then
        s = "P" .. self.pattern
    elseif self.type == "AND" then
        s = ("(%s&%s)"):format(self.A:serialize(), self.B:serialize())
    elseif self.type == "OR" then
        s = ("(%s|%s)"):format(self.A:serialize(), self.B:serialize())
    elseif self.type == "NOT" then
        s = ("!%s"):format(self.A:serialize())
    elseif self.type == "HAS_TAG" then
        s = "T" .. self.tag
    else
        error(("Serialization not implemented for type %s!"):format(self.type))
    end
    return s
end

---If possible, convert this ItemDescriptor to an ItemCoordinate
---@return ItemCoordinate?
function ItemDescriptor__index:toCoord()
    if self.type == "FROM_NAME" and self.nbt ~= Item.WILDCARD then
        local coord = require("Coordinates")
        return coord.ItemCoordinate(self.name, self.nbt)
    end
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
---@return ItemDescriptor
function Item.fromPattern(pattern)
    expect(1, pattern, "string")
    local ok, res = pcall(string.match, pattern, "test_1234:item_name")
    if not ok then
        error(res, 1)
    end
    return setmetatable({ pattern = pattern, type = "FROM_PATTERN" }, ItemDescriptor)
end

---@param tag string
---@return ItemDescriptor
function Item.hasTag(tag)
    expect(1, tag, "string")
    return setmetatable({ tag = tag, type = "HAS_TAG" }, ItemDescriptor)
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
function Item.gateNot(a)
    expect(1, a, "table")
    return setmetatable({ A = a, type = "NOT" }, ItemDescriptor)
end

---@param s string
---@param c string
local function splitByChar(s, c)
    local idx = string.find(s, c, nil, true)
    if idx then
        return s:sub(1, idx - 1), s:sub(idx + 1)
    end
    return s
end

local function splitAndGetOperator(s)
    local level = 0
    local splitIdx, op
    for i = 1, #s do
        local ch = s:sub(i, i)
        if ch == "(" then
            level = level + 1
        elseif ch == ")" then
            level = level - 1
        elseif (ch == "|" or ch == "&") and level == 1 then
            splitIdx = i
            op = ch
            break
        end
    end
    return op, s:sub(2, splitIdx - 1), s:sub(splitIdx + 1, #s - 1)
end

---Unserialize a string into an ItemDescriptor
---@param s string
---@return ItemDescriptor
function Item.unserialize(s)
    expect(1, s, "string")
    local ch = s:sub(1, 1)
    if ch == "(" then
        -- Search for operator
        local op, a, b = splitAndGetOperator(s)
        if op == "|" then
            return Item.gateOr(Item.unserialize(a), Item.unserialize(b))
        elseif op == "&" then
            return Item.gateAnd(Item.unserialize(a), Item.unserialize(b))
        end
    elseif ch == "!" then
        local a = Item.unserialize(s:sub(2))
        return Item.gateNot(a)
    elseif ch == "N" then
        local name, nbt = splitByChar(s:sub(2), "$")
        return Item.fromName(name, nbt)
    elseif ch == "T" then
        local tag = s:sub(2)
        return Item.hasTag(tag)
    elseif ch == "P" then
        local pattern = s:sub(2)
        return Item.fromPattern(pattern)
    end
    error("Could not unserialize ItemDescriptor!")
end

return Item
