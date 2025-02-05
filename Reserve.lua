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
---@field items table<ItemCoordinate,ReserveItem>
---@field freeSlots InventoryCoordinate[]
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
    removeValueFromArray(self.freeSlots, coord)
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
        self.freeSlots[#self.freeSlots + 1] = coord
        return
    end
    local name = data.name
    local nbt = data.nbt or Item.NO_NBT
    local icoord = coordLib.ItemCoordinate(name, nbt)
    self.inventoryLUT[coord] = icoord
    local ritem = self.items[icoord] or {}
    local ditem = detailedDataCache[icoord]
    if not ditem then
        local periph, slot = coordLib.splitInventoryCoordinate(coord)
        ditem = peripheral.call(periph, "getItemDetail", slot)
        detailedDataCache[icoord] = ditem
    end
    self:_initReservedItem(ritem, ditem, data.count)
    ritem.slotCounts[coord] = data.count
    if data.count == ditem.maxCount then
        ritem.fullSlots[#ritem.fullSlots + 1] = coord
    else
        ritem.partSlots[#ritem.partSlots + 1] = coord
    end
    self.items[icoord] = ritem
    if ritem.total == 0 then
        self.items[icoord] = nil
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
        self:_startTransaction(from, itemCoord, fromCount - predMove)
        self:_startTransaction(to, itemCoord, toCount + predMove)
        local moved = peripheral.call(fperiph, "pushItems", tperiph, fslot, nil, tslot)
        self:_endTransaction(from, itemCoord, fromCount - moved)
        self:_endTransaction(to, itemCoord, toCount + moved)
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
    self.freeSlots = {}
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
    mergeIntoArray(r.freeSlots, self.freeSlots)
    mergeIntoArray(r.allSlots, self.allSlots)
    for coord, src in pairs(r.items) do
        local ditem = src.info
        self:_initReservedItem(src, ditem, 0)
        local dst = self.items[coord]
        mergeIntoTable(src.slotCounts, dst.slotCounts)
        mergeIntoArray(src.fullSlots, dst.fullSlots)
        mergeIntoArray(src.partSlots, dst.partSlots)
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
function Reserve__index:_reserveFreeSlot()
    if self.freeSlots[1] then
        self.allSlots[self.freeSlots[1]] = nil
        return table.remove(self.freeSlots, 1)
    end
    error("No slots free!")
    os.pullEvent("slot_freed") -- TODO change this
    return self:_reserveFreeSlot()
end

---Remove a set of values from an array
---@param t any[]
---@param vs any[]
local function removeValuesFromArray(t, vs)
    for _, v in ipairs(vs) do
        removeValueFromArray(t, v)
    end
end

---Transfer a slot from this Reserve to another
--- Does NOT remove from partSlots or fullSlots on the source Reserve
---@param srcItem ReserveItem
---@param dstItem ReserveItem
---@param r Reserve
---@param slot InventoryCoordinate
---@param count integer
function Reserve__index:_transferSlot(srcItem, dstItem, r, slot, count)
    removeValueFromArray(srcItem.partSlots, slot)
    removeValueFromArray(srcItem.fullSlots, slot)
    if count < srcItem.info.maxCount then
        -- Update partSlots
        dstItem.partSlots[#dstItem.partSlots + 1] = slot
    else
        dstItem.fullSlots[#dstItem.fullSlots + 1] = slot
    end
    -- Update counts
    srcItem.total = srcItem.total - count
    dstItem.total = dstItem.total + count
    -- Update allSlots
    self.allSlots[slot] = nil
    r.allSlots[slot] = true
    -- Update slotCounts
    srcItem.slotCounts[slot] = nil
    dstItem.slotCounts[slot] = count
end

---Transfer count of item from this Reserve to reserve r
--- Returns actual count transferred
---@param icoord ItemCoordinate
---@param count integer
---@param r Reserve
---@return integer
function Reserve__index:_transfer(icoord, count, r)
    local srcItem = self.items[icoord]
    if not srcItem then return 0 end
    local transferred = 0
    local dstItem = r.items[icoord] or {}
    r.items[icoord] = dstItem
    r:_initReservedItem(dstItem, srcItem.info, 0)
    while transferred < count do
        local _, partial = next(srcItem.partSlots)
        if not partial then break end
        local slotCount = srcItem.slotCounts[partial]
        if slotCount <= count then
            -- This slot can directly be transferred over
            -- keep track of these slots so they can be removed correctly
            transferred = transferred + count
            self:_transferSlot(srcItem, dstItem, r, partial, slotCount)
        else
            -- This slot contains too many items and must be broken up
            local free = self:_reserveFreeSlot()
            local freeInv, freeSlot = coordLib.splitInventoryCoordinate(free)
            local srcInv, srcSlot = coordLib.splitInventoryCoordinate(partial)
            local i = peripheral.call(srcInv, "pushItems", freeInv, srcSlot, transferred - count, freeSlot)
            self:_transferSlot(srcItem, dstItem, r, free, i)
        end
    end
    while transferred < count do
        local _, full = next(srcItem.fullSlots)
        if not full then break end
        local slotCount = srcItem.slotCounts[full]
        -- keep track of these slots so they can be removed correctly
        if slotCount <= count then
            -- This slot can directly be transferred over
            transferred = transferred + count
            self:_transferSlot(srcItem, dstItem, r, full, slotCount)
        else
            -- This slot contains too many items and must be broken up\
            local free = self:_reserveFreeSlot()
            local freeInv, freeSlot = coordLib.splitInventoryCoordinate(free)
            local srcInv, srcSlot = coordLib.splitInventoryCoordinate(full)
            local i = peripheral.call(srcInv, "pushItems", freeInv, srcSlot, count - transferred, freeSlot)
            self:_transferSlot(srcItem, dstItem, r, free, i)
            srcItem.partSlots[#srcItem.partSlots + 1] = full
        end
    end
    return transferred
end

---Create a new reserve with a set amount of items from this one
--- Returns nil if it is unable to reserve the amount of items requested
---@param desc ItemDescriptor
---@param count integer
---@return Reserve?
function Reserve__index:split(desc, count)
    local matches = searchForItems(desc, self.items)
    local r = Reserve.empty()
    local transferred = 0
    for _, item in ipairs(matches) do
        transferred = transferred + self:_transfer(item, count - transferred, r)
        if transferred == count then
            return r
        end
    end
    self:absorb(r)
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

---Start a loss transaction over a slot
---@param invCoord InventoryCoordinate
---@param itemCoord ItemCoordinate
---@param predCount integer
function Reserve__index:_startTransaction(invCoord, itemCoord, predCount)
    local ritem = self.items[itemCoord]
    local slotCount = ritem.slotCounts[invCoord] or 0
    local diff = predCount - slotCount
    if diff > 0 then
        -- gain transaction, only update afterwards
        return
    end
    -- loss transaction, guess the loss
    if predCount == 0 then
        self:_removeSlot(invCoord)
    else
        ritem.info.count = predCount
        self:_setSlot(invCoord, ritem.info)
    end
end

---End a loss transaction over a slot
---@param invCoord InventoryCoordinate
---@param itemCoord ItemCoordinate
---@param realCount integer
function Reserve__index:_endTransaction(invCoord, itemCoord, realCount)
    local ritem = self.items[itemCoord]
    if realCount == 0 then
        -- make sure the empty slot is now part of the emptySlot list
        self:_setSlot(invCoord, nil)
    else
        ritem.info.count = realCount
        self:_setSlot(invCoord, ritem.info)
    end
end

---Push items from this Reserve into some inventory
---@param to string
---@param item ItemDescriptor
---@param limit integer?
---@param toSlot integer?
---@return integer
function Reserve__index:pushItems(to, item, limit, toSlot)
    local matches = searchForItems(item, self.items)
    if #matches == 0 then
        print("No matches?")
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
    local startCount = ritem.slotCounts[fullCoord]
    local predictedMove = math.min(limit, slotCount)
    local newCount = startCount - predictedMove
    self:_startTransaction(fullCoord, itemCoord, newCount)
    local moved = peripheral.call(inv, "pushItems", to, slot, limit, toSlot)
    local realNewCount = startCount - moved
    self:_endTransaction(fullCoord, itemCoord, realNewCount)
    self:_defragItem(ritem)
    return moved
end

---Pull Items from an inventory into this reserve
---@param from string
---@param slot integer
---@param limit integer?
---@return integer
function Reserve__index:pullItems(from, slot, limit)
    local emptySlot = self:_reserveFreeSlot()
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
---@param stale boolean? Do not scan the inventory contents upon creation
---@return Reserve
function Reserve.fromInventories(invs, stale)
    local res = Reserve.empty()
    res:addInventories(invs)
    if not stale then
        res:scan()
    end
    return res
end

---Create an empty Reserve
---@return Reserve
function Reserve.empty()
    local res = setmetatable({}, Reserve)
    res.allSlots = {}
    res.freeSlots = {}
    res.items = {}
    res.defragLocks = {}
    res.inventoryLUT = {}
    return res
end

return Reserve
