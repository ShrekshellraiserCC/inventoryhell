---@alias ItemNBT string
---@alias ItemName string

---@class CCItemInfo
---@field name string
---@field nbt string
---@field count number
---@field maxCount number

---@class InventoryCoordinate : string
---@class ItemCoordinate : string

local Item = require("ItemDescriptor")

local coordLib = require("Coordinates")

---@class ReserveItem
---@field info CCItemInfo
---@field total integer
---@field slotCounts table<InventoryCoordinate,number>
---@field fullSlots InventoryCoordinate[]
---@field partSlots InventoryCoordinate[]

---@class Reserve
---@field _transactions table<number,table>
---@field items table<ItemCoordinate,ReserveItem>
---@field emptySlots EmptySlotStorage
---@field allSlots table<InventoryCoordinate,boolean>
---@field defragLocks table<ItemCoordinate,boolean>
---@field inventoryLUT table<InventoryCoordinate,ItemCoordinate>
local Reserve__index = {}
local Reserve = { __index = Reserve__index }

---@alias InventoryCompatible string

---@type table<ItemCoordinate,CCItemInfo>
local detailedDataCache = {}

---Remove a value from an array
---@generic T
---@param t T[]
---@param v T
local function removeValueFromArray(t, v)
    for i, v1 in ipairs(t) do
        if v1 == v then
            table.remove(t, i)
            return
        end
    end
end

---Completely remove a slot from this Reserve
---@param coord InventoryCoordinate
function Reserve__index:_removeSlot(coord)
    -- check if free
    self.emptySlots.clear(coord)
    self.allSlots[coord] = nil
    self.inventoryLUT[coord] = nil
    -- iterate all items
    for icoord, v in pairs(self.items) do
        local count = v.slotCounts[coord]
        if count then
            -- this slot used to contain this item
            removeValueFromArray(v.fullSlots, coord)
            removeValueFromArray(v.partSlots, coord)
            v.slotCounts[coord] = nil
            v.total = v.total - count
            return
        end
    end
end

---Initialize a possibly empty ReserveItem
---@param ritem ReserveItem
---@param ditem CCItemInfo
---@param count integer
function Reserve__index:_initReservedItem(ritem, ditem, count)
    ritem.info = ritem.info or ditem
    ritem.total = (ritem.total or 0) + count
    ritem.slotCounts = ritem.slotCounts or {}
    ritem.partSlots = ritem.partSlots or {}
    ritem.fullSlots = ritem.fullSlots or {}
end

---Set a specific slot to the data provided
---@param coord InventoryCoordinate
---@param data CCItemInfo?
function Reserve__index:_setSlot(coord, data)
    self:_removeSlot(coord)
    self.allSlots[coord] = true
    if data == nil then
        self.emptySlots.free(coord)
        return
    end
    local name = data.name
    local nbt = data.nbt or Item.NO_NBT
    local itemCoord = coordLib.ItemCoordinate(name, nbt)
    self.inventoryLUT[coord] = itemCoord
    local ritem = self.items[itemCoord] or {}
    local ditem = detailedDataCache[itemCoord]
    if not ditem then
        local periph, slot = coordLib.splitInventoryCoordinate(coord)
        ditem = peripheral.call(periph, "getItemDetail", slot)
        detailedDataCache[itemCoord] = ditem
    end
    self:_initReservedItem(ritem, ditem, data.count)
    ritem.slotCounts[coord] = data.count
    if data.count == ditem.maxCount then
        ritem.fullSlots[#ritem.fullSlots + 1] = coord
    else
        ritem.partSlots[#ritem.partSlots + 1] = coord
    end
    self.items[itemCoord] = ritem
    if ritem.total == 0 then
        self.items[itemCoord] = nil
    end
end

---Get a list of functions to call in parallel to scan this Reserve
---@return fun()[]
function Reserve__index:getScanFuncs()
    local f = {}
    ---@type table<string,boolean>
    local inventories = {}
    ---@type table<string,number[]>
    local slotsPerInventory = {}
    for coord in pairs(self.allSlots) do
        local inv, slot = coordLib.splitInventoryCoordinate(coord)
        inventories[inv] = true
        slotsPerInventory[inv] = slotsPerInventory[inv] or {}
        slotsPerInventory[inv][#slotsPerInventory[inv] + 1] = slot
    end
    for inv in pairs(inventories) do
        f[#f + 1] = function()
            local list = peripheral.call(inv, "list")
            for _, i in ipairs(slotsPerInventory[inv]) do
                local coord = coordLib.InventoryCoordinate(inv, i)
                self:_setSlot(coord, list[i])
            end
        end
    end
    return f
end

---Defrag a given item
---@param ritem ReserveItem
function Reserve__index:_defragItem(ritem)
    local itemCoord = coordLib.ItemCoordinate(ritem.info.name, ritem.info.nbt)
    if self.defragLocks[itemCoord] then return end
    self.defragLocks[itemCoord] = true
    while #ritem.partSlots > 1 do
        local from = ritem.partSlots[1]
        local fromCount = ritem.slotCounts[from]
        local to = ritem.partSlots[2]
        local toCount = ritem.slotCounts[to]
        local fperiph, fslot = coordLib.splitInventoryCoordinate(from)
        local tperiph, tslot = coordLib.splitInventoryCoordinate(to)
        local maxCount = ritem.info.maxCount
        local predMove = math.min(fromCount, maxCount - toCount)
        local fid = self:_startTransaction(from, itemCoord, -predMove)
        local tid = self:_startTransaction(to, itemCoord, predMove)
        local moved = peripheral.call(fperiph, "pushItems", tperiph, fslot, nil, tslot)
        self:_endTransaction(fid, -moved)
        self:_endTransaction(tid, moved)
    end
    self.defragLocks[itemCoord] = nil
end

---Get a list of functions to execute in parallel to defrag the slots this Reserve contains
---@return fun()[]
function Reserve__index:getDefragFuncs()
    local f = {}
    for coord, v in pairs(self.items) do
        f[#f + 1] = function()
            self:_defragItem(v)
        end
    end
    return f
end

---Clear all slots from this Reserve
function Reserve__index:clear()
    self.allSlots = {}
    self.items = {}
    self.inventoryLUT = {}
    self.defragLocks = {}
end

---Merge contents of from into to to, without duplicates
---@generic T
---@param to T[]
---@param from T[]
local function mergeIntoArray(from, to)
    local n = #to
    for i, v in pairs(from) do
        removeValueFromArray(to, v) -- Horribly inefficient, TODO rethink this
        to[n + 1] = v
        n = n + 1
    end
end

---Merge contents of from into to to
---@generic K
---@generic V
---@param to table<K,V>
---@param from table<K,V>
local function mergeIntoTable(from, to)
    for k, v in pairs(from) do
        to[k] = v
    end
end


---Absorb the contents of another Reserve (emptying it)
---@param r Reserve
function Reserve__index:absorb(r)
    for coord in pairs(r.allSlots) do
        r:_transferSlot(coord, self)
    end
    r:clear()
end

---Search an array for items which match the given ItemDescriptor
---@param item ItemDescriptor
---@param tab table<ItemCoordinate,ReserveItem>
---@return ItemCoordinate[]
local function searchForItems(item, tab)
    local t = {}
    for k, v in pairs(tab) do
        if item:match(v.info) then
            t[#t + 1] = k
        end
    end
    return t
end

---Yield for a free slot to be available
---@return InventoryCoordinate
function Reserve__index:_allocateSlot()
    return self.emptySlots.allocate()
end

---Remove a set of values from an array
---@param t any[]
---@param vs any[]
local function removeValuesFromArray(t, vs)
    for _, v in ipairs(vs) do
        removeValueFromArray(t, v)
    end
end

---Hand over a slot under this Reserve's control to another Reserve
---@param slot InventoryCoordinate
---@param to Reserve
function Reserve__index:_transferSlot(slot, to)
    local itemcoord = assert(self.inventoryLUT[slot], ("Cannot transfer slot %s not in this Reserve!"):format(slot))
    local ritem = self.items[itemcoord]
    local info = ritem.info
    local count = ritem.slotCounts[slot]
    self:_removeSlot(slot)
    info.count = count
    to:_setSlot(slot, info)
end

---@param to Reserve
---@param icoord InventoryCoordinate
---@param limit integer
---@return integer
function Reserve__index:_doOneTransferIter(to, icoord, limit)
    local ritem = self.items[icoord]
    if not ritem then return 0 end
    if limit >= ritem.info.maxCount then
        local fslot = ritem.fullSlots[1]
        if fslot then
            self:_transferSlot(fslot, to)
            return ritem.info.maxCount
        end
        local pslot = ritem.partSlots[1]
        local slotCount = ritem.slotCounts[pslot]
        self:_transferSlot(pslot, to)
        return slotCount
    end
    local invCoord = ritem.fullSlots[1] or ritem.partSlots[1]
    local inv, slot = coordLib.splitInventoryCoordinate(invCoord)
    local slotCount = ritem.slotCounts[invCoord]
    local predMove = math.min(slotCount, limit)
    local toCoord = to:_allocateSlot()
    local tinv, tslot = coordLib.splitInventoryCoordinate(toCoord)
    local sid = self:_startTransaction(invCoord, icoord, -predMove)
    local tid = to:_startTransaction(toCoord, icoord, predMove)
    local moved = peripheral.call(inv, "pushItems", tinv, slot, limit, tslot)
    self:_endTransaction(sid, -moved)
    to:_endTransaction(tid, moved)
    return moved
end

---Transfer a set amount of items from this reserve to the Reserve to
---@param to Reserve
---@param desc ItemDescriptor
---@param limit integer
---@return integer moved
function Reserve__index:transfer(to, desc, limit)
    local matches = searchForItems(desc, self.items)
    local moved = 0
    for _, match in ipairs(matches) do
        repeat
            local imoved = self:_doOneTransferIter(to, match, limit - moved)
            moved = moved + imoved
        until imoved == 0 or moved == limit
        if moved == limit then break end
    end
    return moved
end

---Create a new reserve with a set amount of items from this one
--- Returns nil if it is unable to reserve the amount of items requested
---@param desc ItemDescriptor
---@param count integer
---@return Reserve?
function Reserve__index:split(desc, count)
    local r = Reserve.empty(self.emptySlots)
    local moved = self:transfer(r, desc, count)
    if moved ~= count then
        self:absorb(r)
        return
    end
    return r
end

---Return control of this Reserve's slots back to its parent (from :split())
function Reserve__index:free()

end

---Find a slot in this reserve that is full of matching items
---@param itemList ItemCoordinate[]
---@return ItemCoordinate? itemCoord
---@return InventoryCoordinate? invCoord
function Reserve__index:_findFullSlot(itemList)
    for _, itemCoord in ipairs(itemList) do
        local ritem = self.items[itemCoord]
        local _, fullCoord = next(ritem.fullSlots)
        if fullCoord then
            return itemCoord, fullCoord
        end
    end
end

---Find a slot in this reserve that has at least count of matching items
---@param itemList ItemCoordinate[]
---@param count integer
---@return ItemCoordinate itemCoord
---@return InventoryCoordinate invCoord
---@return integer count
function Reserve__index:_findSlotWithClosestCount(itemList, count)
    local maxFound
    local maxItem
    local maxCount = 0
    for _, itemCoord in ipairs(itemList) do
        local ritem = self.items[itemCoord]
        for _, partCoord in ipairs(ritem.partSlots) do
            local icount = ritem.slotCounts[partCoord]
            if icount >= count then
                return itemCoord, partCoord, count
            elseif icount > maxCount then
                maxFound = partCoord
                maxCount = icount
                maxItem = itemCoord
            end
        end
    end
    return maxItem, maxFound, maxCount
end

--- TODO follow these rules when modifying the contents of the Reserve
--- - If a slot is *losing* items, predict the loss and update the total
--- - If a slot is *gaining* items, make no changes until after the transaction
--- - If a slot is going to be empty, do not add it to the empty cache until afterwards

local lastTransactionID = 0
---Start a loss transaction over a slot
---@param invCoord InventoryCoordinate
---@param itemCoord ItemCoordinate
---@param predMove integer
---@return integer tid
function Reserve__index:_startTransaction(invCoord, itemCoord, predMove)
    local ritem = self.items[itemCoord]
    lastTransactionID = lastTransactionID + 1
    local tid = lastTransactionID
    local transaction = {
        predMove = 0,
        invCoord = invCoord,
        itemCoord = itemCoord
    }
    self._transactions[tid] = transaction
    local slotCount = 0
    if ritem then
        slotCount = ritem.slotCounts[invCoord] or 0
    end
    if predMove > 0 then
        -- gain transaction, only update afterwards
        return tid
    end
    transaction.predMove = predMove
    -- loss transaction, guess the loss
    local predTotal = slotCount + predMove
    if predTotal == 0 then
        self:_removeSlot(invCoord)
    else
        detailedDataCache[itemCoord].count = predTotal
        self:_setSlot(invCoord, detailedDataCache[itemCoord])
    end
    return tid
end

---End a loss transaction over a slot
---@param tid integer
---@param realMove integer
function Reserve__index:_endTransaction(tid, realMove)
    local transaction = self._transactions[tid]
    if not transaction then
        error(("Invalid transaction ID %s"):format(tid), 1)
    end
    local itemCoord, invCoord = transaction.itemCoord, transaction.invCoord
    self._transactions[tid] = nil
    local predMove = transaction.predMove
    local oldCount = 0
    local ritem = self.items[itemCoord]
    if ritem then
        oldCount = ritem.slotCounts[invCoord] or oldCount
    end
    local realCount = oldCount - predMove + realMove
    if realCount == 0 then
        -- make sure the empty slot is now part of the emptySlot list
        self:_setSlot(invCoord, nil)
    else
        local info = detailedDataCache[itemCoord]
        info.count = realCount
        self:_setSlot(invCoord, info)
    end
end

---Push items from this Reserve into some inventory
--- * Behaves like Inventory.pushItems
--- * Moves up to a stack of items at once
---@param to string
---@param item ItemDescriptor
---@param limit integer?
---@param toSlot integer?
---@return integer
function Reserve__index:pushItems(to, item, limit, toSlot)
    local matches = searchForItems(item, self.items)
    if #matches == 0 then
        return 0
    end
    -- check for a full slot to push from
    local itemCoord, fullCoord = self:_findFullSlot(matches)
    local inv, slot, slotCount
    if fullCoord then
        inv, slot = coordLib.splitInventoryCoordinate(fullCoord)
        slotCount = self.items[itemCoord].info.maxCount
    else
        itemCoord, fullCoord, slotCount = self:_findSlotWithClosestCount(matches, limit or 64)
        inv, slot = coordLib.splitInventoryCoordinate(fullCoord)
    end
    local ritem = self.items[itemCoord]
    local predictedMove = math.min(limit, slotCount)
    local tid = self:_startTransaction(fullCoord, itemCoord, -predictedMove)
    local moved = peripheral.call(inv, "pushItems", to, slot, limit, toSlot)
    self:_endTransaction(tid, -moved)
    self:_defragItem(ritem)
    return moved
end

---Pull Items from an inventory into this reserve
--- * Same behavior as Inventory.pullItems
--- * As long as an empty slot is available
---   a whole stack (or limit) will be pulled.
---@param from string
---@param slot integer
---@param limit integer?
---@return integer
function Reserve__index:pullItems(from, slot, limit)
    local emptySlot = self:_allocateSlot()
    local inv, tSlot = coordLib.splitInventoryCoordinate(emptySlot)
    local moved = peripheral.call(inv, "pullItems", from, slot, limit, tSlot)
    local info = peripheral.call(inv, "getItemDetail", tSlot)
    self:_setSlot(emptySlot, info)
    self:_defragItem(self.items[coordLib.ItemCoordinate(info.name, info.nbt)])
    return moved
end

---Execute a table of functions in batches
---@param func function[]
---@param skipPartial? boolean Only do complete batches and skip the remainder.
---@param limit integer
---@return function[] skipped Functions that were skipped as they didn't fit.
local function batchExecute(func, skipPartial, limit)
    local batches = #func / limit
    batches = skipPartial and math.floor(batches) or math.ceil(batches)
    for batch = 1, batches do
        local start = ((batch - 1) * limit) + 1
        local batch_end = math.min(start + limit - 1, #func)
        parallel.waitForAll(table.unpack(func, start, batch_end))
    end
    return table.pack(table.unpack(func, 1 + limit * batches))
end

---Defrag this Reserve
function Reserve__index:defrag()
    local f = self:getDefragFuncs()
    batchExecute(f, false, 128)
end

---Scan all slots this Reserve covers
--- Populates the freeSlots and items contents
function Reserve__index:scan()
    local f = self:getScanFuncs()
    batchExecute(f, false, 128)
end

---Add inventories to this Reserve, without scanning the contents of the slots
--- The slots will not be usable until they are scanned!
---@param invs any
function Reserve__index:addInventories(invs)
    for _, inv in ipairs(invs) do
        for i = 1, peripheral.call(inv, "size") do
            self.allSlots[coordLib.InventoryCoordinate(inv, i)] = true
        end
    end
end

---Create a reserve from a list of inventories (freshly scanning its contents)
---@param invs InventoryCompatible[]
---@return Reserve
function Reserve.fromInventories(invs)
    local res = Reserve.empty()
    res:addInventories(invs)
    res:scan()
    return res
end

---Create an empty Reserve
---@param ess EmptySlotStorage?
---@return Reserve
function Reserve.empty(ess)
    local res = setmetatable({}, Reserve)
    res.allSlots = {}
    res.emptySlots = ess or Reserve.emptySlotStorage()
    res.items = {}
    res.defragLocks = {}
    res.inventoryLUT = {}
    res._transactions = {}
    return res
end

local lastEssId = 0
---@return EmptySlotStorage
function Reserve.emptySlotStorage()
    lastEssId = lastEssId + 1
    ---@class EmptySlotStorage
    local ess = {
        id = lastEssId
    }
    ---@class EmptySlotStorage
    local ess__index = {}
    ---@type table<InventoryCoordinate,boolean>
    local slots = {}
    ess.slots = slots

    ---@param s InventoryCoordinate
    function ess__index.free(s)
        slots[s] = true
        os.queueEvent("ess_slot_freed", ess.id)
    end

    ---Get a free slot that is currently available,
    --- or yield until one is available
    ---@return InventoryCoordinate
    function ess__index.allocate()
        local slot = next(slots)
        if slot then
            slots[slot] = nil
            return slot
        end
        while true do
            local _, id = os.pullEvent("ess_slot_freed")
            if id == ess.id then break end
        end
        return ess.allocate()
    end

    function ess__index.clear(s)
        slots[s] = nil
    end

    function ess__index.clearAll()
        slots = {}
    end

    -- wanted to make it serializable :)
    return setmetatable(ess, { __index = ess__index })
end

return Reserve
