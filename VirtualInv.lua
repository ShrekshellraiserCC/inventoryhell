---@alias ItemNBT string
---@alias ItemName string

---@class CCItemInfo
---@field name string
---@field nbt string
---@field count number
---@field maxCount number

---@class InventoryCoordinate : string
---@class ItemCoordinate : string

local ID = require("ItemDescriptor")
local coordLib = require("Coordinates")
local shrexpect = require("shrexpect")


---@type table<ItemCoordinate,CCItemInfo>
local detailedDataCache = {}
---@type table<ItemCoordinate,boolean>
local detailedCacheLock = {}

local cacheFinishEvent = "DETAILED_CACHE_FINISH"
local itemLockFreeEvent = "ITEM_LOCK_FREE"
local scanLockFreeEvent = "SCAN_LOCK_FREE"

---Search an array for items which match the given ItemDescriptor
---@param item ItemDescriptor
---@param tab table<ItemCoordinate,VirtualItem>
---@return ItemCoordinate[]
local function searchForItems(item, tab)
    local t = {}
    for k, v in pairs(tab) do
        if item:match(v) then
            t[#t + 1] = k
        end
    end
    return t
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

---@alias InventoryCompatible string

---@param inv InventoryCompatible
---@param fun string
---@param ... any
local function invCall(inv, fun, ...)
    return peripheral.call(inv, fun, ...)
end

---Get the length of a given table
---@param t table
---@return integer
local function getLength(t)
    local c = 0
    for _ in pairs(t) do c = c + 1 end
    return c
end

---Clone a table
---@generic T
---@param t T
---@return T
local function clone(t)
    if type(t) == "table" then
        local nt = {}
        for k, v in pairs(t) do
            nt[k] = clone(v)
        end
        return nt
    end
    return t
end

---Get the getItemDetail info of an item, checking the cache first
---@param itemCoord ItemCoordinate
---@param invCoord InventoryCoordinate?
local function getItemDetailed(itemCoord, invCoord)
    shrexpect({ "string", "string?" }, { itemCoord, invCoord })
    if detailedDataCache[itemCoord] then
        return clone(detailedDataCache[itemCoord])
    end
    if detailedCacheLock[itemCoord] then
        while detailedCacheLock[itemCoord] do
            os.pullEvent(cacheFinishEvent)
        end
        return clone(detailedDataCache[itemCoord])
    end
    if invCoord then
        detailedCacheLock[itemCoord] = true
        local inv, slot = coordLib.splitInventoryCoordinate(invCoord)
        local info = invCall(inv, "getItemDetail", slot)
        detailedDataCache[itemCoord] = info
        detailedCacheLock[itemCoord] = nil
        os.queueEvent(cacheFinishEvent)
        return clone(info)
    end
    error(("getItemDetail, no invCoord, but itemCoord (%s) not in cache!"):format(itemCoord), 2)
end


---














---@class RealItem : CCItemInfo
---@field fullSlots table<InventoryCoordinate,integer>
---@field partSlots table<InventoryCoordinate,integer>
---@field virtSlots table<InventoryCoordinate,integer>

---@class VirtualItem : CCItemInfo
---@field slot InventoryCoordinate

---@class Reserve
---@field items table<ItemCoordinate,VirtualItem>
---@field parent VirtualInv
local Reserve__index = {}
Reserve__index.__type = "Reserve"
local Reserve = { __index = Reserve__index }

---Absorb the contents of another Reserve (emptying it)
---@param r Reserve
function Reserve__index:absorb(r)
    shrexpect({ "Reserve" }, { r })
    self.parent:_absorb(self, r)
end

---Transfer a set amount of items from this reserve to the Reserve to
---@param to Reserve
---@param desc ItemDescriptor
---@param limit integer
---@return integer moved
function Reserve__index:transfer(to, desc, limit)
    shrexpect({ "Reserve", "string", "number" }, { to, desc, limit })
    return self.parent:_transfer(self, to, desc, limit)
end

---Create a new reserve with a set amount of items from this one
--- Returns nil if it is unable to reserve the amount of items requested
---@param desc ItemDescriptor
---@param count integer
---@return Reserve?
function Reserve__index:split(desc, count)
    shrexpect({ "ItemDescriptor", "number" }, { desc, count })
    local new = Reserve.empty(self.parent)
    local moved = self.parent:_transfer(self, new, desc, count)
    if moved < count then
        self:absorb(new)
        return
    end
    return new
end

---Return control of this Reserve's slots back to its parent (from :split())
function Reserve__index:free()
    self.parent:absorb(self)
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
    shrexpect({ "string", "ItemDescriptor", "number?", "number?" }, { to, item, limit, toSlot })
    local matches = searchForItems(item, self.items)
    local moved = 0
    for _, virtSlot in ipairs(matches) do
        moved = moved + self.parent:_pushItems(self, to, virtSlot, limit, toSlot)
        if moved == limit then
            break
        end
    end
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
---@return ItemCoordinate
function Reserve__index:pullItems(from, slot, limit)
    shrexpect({ "string", "number", "number?" }, { from, slot, limit })
    return self.parent:_pullItems(self, from, slot, limit)
end

---Get a printable representation of this Reserve
---@return string
function Reserve__index:toString()
    local s = textutils.serialise(self.items)
    return s
end

---Dump the Reserve to a file
---@param fn string
function Reserve__index:dump(fn)
    local f = assert(fs.open(fn, "w"))
    f.write(self:toString())
    f.close()
end

---Get the count of items matching a given ItemDescriptor
---@param id ItemDescriptor
function Reserve__index:getCount(id)
    local items = searchForItems(id, self.items)
    local count = 0
    for k, v in ipairs(items) do
        count = count + self.items[v].count
    end
    return count
end

---Create an empty Reserve
---@param parent VirtualInv
---@return Reserve
function Reserve.empty(parent)
    local res = setmetatable({}, Reserve)
    res.items = {}
    res.parent = parent
    return res
end

---
















--- TODO follow these rules when modifying the contents of the VirtualInv
--- - If a slot is *losing* items, predict the loss and update the total
--- - If a slot is *gaining* items, make no changes until after the transaction
--- - If a slot is going to be empty, do not add it to the empty cache until afterwards

---@class VirtualInv : Reserve
---@field virtSlots table<InventoryCoordinate,VirtualItem>
---@field realItems table<ItemCoordinate,RealItem>
---@field realSlotList InventoryCoordinate[]
---@field realItemLUT table<InventoryCoordinate,ItemCoordinate>
---@field itemLocks table<ItemCoordinate,boolean>
---@field scanLocks table<InventoryCompatible,boolean>
---@field rootVirtSlotLUT table<ItemCoordinate,InventoryCoordinate>
local VirtualInv__index = setmetatable({}, Reserve)
VirtualInv__index.__type = "VirtualInv"
local VirtualInv = { __index = VirtualInv__index }

---Transfer a set amount of items between Reserves
---@param from Reserve
---@param to Reserve
---@param desc ItemDescriptor
---@param limit integer
---@return integer moved
function VirtualInv__index:_transfer(from, to, desc, limit)
    shrexpect({ "Reserve|VirtualInv", "Reserve|VirtualInv", "ItemDescriptor", "number" }, { from, to, desc, limit })
    local matches = searchForItems(desc, from.items)
    local moved = 0
    for i, itemCoord in ipairs(matches) do
        local fromItem = from.items[itemCoord]
        local toItem = to.items[itemCoord]
        local fromVirt = fromItem.slot
        local toVirt
        local canMove = math.min(fromItem.count, limit - moved)
        if canMove == fromItem.count then
            -- Move the slot directly over
            toItem = fromItem
            toVirt = fromVirt
            from.items[itemCoord] = nil
            to.items[itemCoord] = fromItem
        else
            if not toItem then
                toVirt = self:_newVirtSlot()
                toItem = getItemDetailed(itemCoord) --[[@as VirtualItem]]
                toItem.slot = toVirt
                self.virtSlots[toVirt] = toItem
                to.items[itemCoord] = toItem
            else
                toVirt = toItem.slot
            end
            toItem.count = canMove
            self.realItems[itemCoord].virtSlots[toVirt] = canMove
            fromItem.count = fromItem.count - canMove
            self.realItems[itemCoord].virtSlots[fromVirt] = fromItem.count
            if fromItem.count == 0 then
                from.items[itemCoord] = nil
                self.realItems[itemCoord].virtSlots[fromVirt] = nil
                self.virtSlots[fromVirt] = nil
            end
        end

        moved = moved + canMove
        if moved == limit then break end
    end
    return moved
end

---Absorb from into the Reserve to
---@param to Reserve
---@param from Reserve
function VirtualInv__index:_absorb(to, from)
    shrexpect({ "Reserve|VirtualInv", "Reserve" }, { to, from })
    for itemCoord, virtItem in pairs(from.items) do
        local toVirtItem = to.items[itemCoord]
        if not toVirtItem then
            -- directly transfer the virtual item's ownership
            to.items[itemCoord] = virtItem
            from.items[itemCoord] = nil
        else
            toVirtItem.count = toVirtItem.count + virtItem.count
            local toSlot = toVirtItem.slot
            local fromSlot = virtItem.slot
            local realItem = self.realItems[itemCoord]
            realItem.virtSlots[toSlot] = realItem.virtSlots[toSlot] + virtItem.count
            realItem.virtSlots[fromSlot] = nil
            self.virtSlots[fromSlot] = nil
            from.items[itemCoord] = nil
        end
    end
end

---@alias TransactionInfo {invCoord:InventoryCoordinate,itemCoord:ItemCoordinate,expected:integer,virtCoord:InventoryCoordinate,r:Reserve}

---Start a transaction using the following rules
--- * If expected to lose items, update count immediately
--- * If expected to gain items, don't touch count
---@param realCoord InventoryCoordinate
---@param itemCoord ItemCoordinate
---@param r Reserve
---@param expected integer
---@return TransactionInfo
function VirtualInv__index:_startTransaction(realCoord, itemCoord, r, expected)
    local virtItem = r.items[itemCoord]
    local virtCoord = virtItem.slot
    local virtCount = virtItem.count
    local realItem = self.realItems[itemCoord]
    local slotCount = realItem.partSlots[realCoord] or realItem.fullSlots[realCoord]
    if expected < 0 then
        self:_setSlot(realCoord, itemCoord, slotCount + expected)
        self:_setVirtSlot(r, virtCoord, itemCoord, virtCount + expected)
    end
    return {
        invCoord = realCoord,
        itemCoord = itemCoord,
        expected = expected,
        virtCoord = virtCoord,
        r = r
    }
end

---Complete a transaction
---@param trans TransactionInfo
---@param moved integer
function VirtualInv__index:_endTransaction(trans, moved)
    local r, realCoord, itemCoord, expected, virtCoord = trans.r,
        trans.invCoord, trans.itemCoord, trans.expected, trans.virtCoord
    local virtItem = r.items[itemCoord]
    local virtCount = (virtItem and virtItem.count) or 0
    local realItem = self.realItems[itemCoord]
    local slotCount = realItem and (realItem.partSlots[realCoord] or realItem.fullSlots[realCoord]) or 0
    if expected > 0 then
        self:_setSlot(realCoord, itemCoord, slotCount + moved)
        self:_setVirtSlot(r, virtCoord, itemCoord, virtCount + moved)
    else
        self:_setSlot(realCoord, itemCoord, slotCount - expected + moved)
        self:_setVirtSlot(r, virtCoord, itemCoord, virtCount - expected + moved)
    end
end

---Push items from a reserve
--- * Behaves like Inventory.pushItems
--- * Moves up to a stack of items at once
---@param r Reserve
---@param toInv InventoryCompatible
---@param itemCoord ItemCoordinate
---@param limit integer?
---@param toSlot integer?
---@return integer moved
function VirtualInv__index:_pushItems(r, toInv, itemCoord, limit, toSlot)
    shrexpect({ "Reserve|VirtualInv", "string", "string", "number?", "number?" }, { r, toInv, itemCoord, limit, toSlot })
    local virtItem = r.items[itemCoord]
    -- local itemCoord = coordLib.ItemCoordinate(virtItem.name, virtItem.nbt)
    local realItem = self.realItems[itemCoord]
    limit = math.min(limit or realItem.maxCount, virtItem.count)
    local moved = 0
    while true do
        -- make sure this item isn't being defragged at the moment
        self:_checkItemLock(itemCoord)
        -- make sure the inventory is in a stable state
        self:_checkScanLock()
        local invCoord, slotCount = next(realItem.partSlots)
        if not invCoord then
            invCoord, slotCount = next(realItem.fullSlots)
            if not invCoord then
                self:_checkEmpty(itemCoord)
                break
            end
        end
        local expectedToMove = math.min(slotCount, limit - moved)
        local fromInv, fromSlot = coordLib.splitInventoryCoordinate(invCoord)
        local transaction = self:_startTransaction(invCoord, itemCoord, r, -expectedToMove)
        local actuallyMoved = invCall(fromInv, "pushItems", toInv, fromSlot, expectedToMove, toSlot)
        moved = moved + actuallyMoved
        self:_endTransaction(transaction, -actuallyMoved)
        if actuallyMoved == 0 then
            break
        elseif moved == limit then
            break
        end
    end
    return moved
end

---PUll items into a Reserve
--- * Behaves like Inventory.pullItems
--- * Moves up to a stack of items at once
---@param r Reserve
---@param fromInv InventoryCompatible
---@param fromSlot integer
---@param limit integer?
---@return integer moved
---@return ItemCoordinate
function VirtualInv__index:_pullItems(r, fromInv, fromSlot, limit)
    -- make sure the inventory is in a stable state
    self:_checkScanLock()
    local emptyCoord = self.ess.allocate()
    local emptyInv, emptySlot = coordLib.splitInventoryCoordinate(emptyCoord)
    local moved = invCall(emptyInv, "pullItems", fromInv, fromSlot, limit, emptySlot)
    if moved == 0 then
        self.ess.free(emptyCoord)
        return 0, ""
    end
    local info = invCall(emptyInv, "getItemDetail", emptySlot)
    local itemCoord = coordLib.ItemCoordinate(info.name, info.nbt)
    detailedDataCache[itemCoord] = detailedDataCache[itemCoord] or info
    if moved == info.maxCount then
        self:_setSlot(emptyCoord, itemCoord, moved)
    else
        -- merge with partSlot
        local ritem = self.realItems[itemCoord]
        local toCoord = ritem and next(ritem.partSlots)
        if not toCoord then
            -- No partSlot exists, just leave this in place
            self:_setSlot(emptyCoord, itemCoord, moved)
        else
            local toInv, toSlot = coordLib.splitInventoryCoordinate(toCoord)
            local mergeMoved = invCall(emptyInv, "pushItems", toInv, emptySlot, moved, toSlot)
            self:_setSlot(emptyCoord, itemCoord, moved - mergeMoved)
            local toCount = ritem.partSlots[toCoord] or 0
            self:_setSlot(toCoord, itemCoord, toCount + mergeMoved)
        end
    end
    local vitem = r.items[itemCoord]
    if vitem then
        self:_setVirtSlot(r, vitem.slot, itemCoord, vitem.count + moved)
    else
        local vcoord = self:_newVirtSlot()
        self:_setVirtSlot(r, vcoord, itemCoord, moved)
    end
    return moved, itemCoord
end

---Create a new virtual slot
--- Each virtual slot will contain ONE type of item
--- Multiple virtual slots may contain the same type of item
---@return InventoryCoordinate
function VirtualInv__index:_newVirtSlot()
    self.lastVirtSlot = self.lastVirtSlot + 1
    local newCoord = coordLib.InventoryCoordinate(self.virtName, self.lastVirtSlot)
    return newCoord
end

---Yield if a slot is defrag locked
---@param itemCoord ItemCoordinate
function VirtualInv__index:_checkItemLock(itemCoord)
    while self.itemLocks[itemCoord] do
        os.pullEvent(itemLockFreeEvent)
    end
end

---Check if a slot is currently defrag locked, and yield for it to no longer be
---@param itemCoord ItemCoordinate
function VirtualInv__index:_setItemLock(itemCoord)
    self:_checkItemLock(itemCoord)
    self.itemLocks[itemCoord] = true
end

function VirtualInv__index:_freeItemLock(itemCoord)
    self.itemLocks[itemCoord] = nil
    os.queueEvent(itemLockFreeEvent)
end

---Defrag a given item
---@param itemCoord ItemCoordinate
function VirtualInv__index:_defragItem(itemCoord)
    self:_setItemLock(itemCoord)
    local ritem = self.realItems[itemCoord]
    while getLength(ritem.partSlots) > 1 do
        local fromInvCoord, fromCount = next(ritem.partSlots)
        local toInvCoord, toCount = next(ritem.partSlots, fromInvCoord)
        local fromInv, fromSlot = coordLib.splitInventoryCoordinate(fromInvCoord)
        local toInv, toSlot = coordLib.splitInventoryCoordinate(toInvCoord)
        local moved = invCall(fromInv, "pushItems", toInv, fromSlot, nil, toSlot)
        self:_setSlot(fromInvCoord, itemCoord, fromCount - moved)
        self:_setSlot(toInvCoord, itemCoord, toCount + moved)
    end
    self:_freeItemLock(itemCoord)
end

function VirtualInv__index:getDefragFuncs()
    local f = {}
    for i, v in pairs(self.realItems) do
        f[#f + 1] = function()
            self:_defragItem(i)
        end
    end
    return f
end

---Defrag this VirtualInv
function VirtualInv__index:defrag()
    local f = self:getDefragFuncs()
    batchExecute(f, false, 128)
end

---Check if there are 0 of an item, and delete it if there is
---@param itemCoord ItemCoordinate
function VirtualInv__index:_checkEmpty(itemCoord)
    local ritem = self.realItems[itemCoord]
    if not ritem then return end
    if ritem.count == 0 then
        self.realItems[itemCoord] = nil
    end
end

---@param virtInv VirtualInv
---@param vcoord InventoryCoordinate
local function isInRootReserve(virtInv, vcoord)
    local vitem = virtInv.virtSlots[vcoord]
    local itemCoord = coordLib.ItemCoordinate(vitem.name, vitem.nbt)
    local ritem = virtInv.items[itemCoord]
    if not ritem then return false end
    return ritem.slot == vcoord
end

---Get the total amount reserved of a given item, not including the root unreserved items
---@param itemCoord ItemCoordinate
---@return integer
function VirtualInv__index:_getReservedCount(itemCoord)
    local ritem = self.realItems[itemCoord]
    if not ritem then return 0 end
    local count = 0
    for vcoord, vcount in pairs(ritem.virtSlots) do
        if not isInRootReserve(self, vcoord) then
            count = count + vcount
        end
    end
    return count
end

---Get the root VirtualInv virtual slot for an item
---@param itemCoord ItemCoordinate
---@return InventoryCoordinate
function VirtualInv__index:_getRootVirtSlot(itemCoord)
    if self.rootVirtSlotLUT[itemCoord] then
        return self.rootVirtSlotLUT[itemCoord]
    end
    local virtCoord = self:_newVirtSlot()
    self.rootVirtSlotLUT[itemCoord] = virtCoord
    return virtCoord
end

---Set the contents of a virtual slot directly
---@param reserve Reserve
---@param virtCoord InventoryCoordinate
---@param itemCoord ItemCoordinate?
---@param count integer
function VirtualInv__index:_setVirtSlot(reserve, virtCoord, itemCoord, count)
    shrexpect({ "Reserve|VirtualInv", "string", "string?", "number" }, { reserve, virtCoord, itemCoord, count })
    local vitem = self.virtSlots[itemCoord]
    if not vitem then
        vitem = getItemDetailed(itemCoord, nil) --[[@as VirtualItem]]
        vitem.count = 0
        vitem.slot = virtCoord
    end
    vitem.count = count
    self.virtSlots[virtCoord] = vitem
    if count == 0 or not itemCoord then
        if itemCoord then
            reserve.items[itemCoord] = nil
        end
        self.virtSlots[virtCoord] = nil
        if self.realItems[itemCoord] then
            self.realItems[itemCoord].virtSlots[virtCoord] = nil
        end
        return
    end
    self.realItems[itemCoord].virtSlots[virtCoord] = vitem.count
    reserve.items[itemCoord] = vitem
    self:_calculateTotals(itemCoord)
end

---Remove a slot (set its count to 0, remove from tables)
---@param invCoord InventoryCoordinate
function VirtualInv__index:_emptySlot(invCoord)
    local itemCoord = self.realItemLUT[invCoord]
    if itemCoord then
        self.ess.free(invCoord)
    else
        self.ess.add(invCoord)
    end
    if not itemCoord then return end
    local ritem = self.realItems[itemCoord]
    self.realItemLUT[invCoord] = nil
    if not ritem then return end
    local oldSlotCount = ritem.fullSlots[invCoord] or ritem.partSlots[invCoord] or 0
    ritem.count = ritem.count - oldSlotCount
    ritem.fullSlots[invCoord] = nil
    ritem.partSlots[invCoord] = nil
    self:_checkEmpty(itemCoord)
end

---Recompute the totals for a given item
---@param itemCoord any
function VirtualInv__index:_calculateTotals(itemCoord)
    local totalVirtualCount = 0
    local ritem = self.realItems[itemCoord]
    if not ritem then return end
    for _, v in pairs(ritem.virtSlots) do
        totalVirtualCount = totalVirtualCount + v
    end
    ritem.count = totalVirtualCount
end

---Set the contents of a real slot directly
---@param invCoord InventoryCoordinate
---@param itemCoord ItemCoordinate?
---@param count integer
function VirtualInv__index:_setSlot(invCoord, itemCoord, count)
    shrexpect({ "string", "string?", "number" }, { invCoord, itemCoord, count })
    if count < 0 then
        error(("_setSlot called with negative count (%d)!"):format(count), 2)
    end
    self:_emptySlot(invCoord)
    if itemCoord == nil or count == 0 then
        return
    end
    self.ess.clear(invCoord)
    self.realItemLUT[invCoord] = itemCoord
    local ritem = self.realItems[itemCoord]
    if not ritem then
        ritem = getItemDetailed(itemCoord, invCoord) --[[@as RealItem]]
        ritem.count = 0
        ritem.fullSlots = {}
        ritem.partSlots = {}
        ritem.virtSlots = {}
    end
    ritem.count = ritem.count + count
    if count == ritem.maxCount then
        ritem.fullSlots[invCoord] = count
    else
        ritem.partSlots[invCoord] = count
    end

    -- Go find all virtual slots with this item, and append them to this realItem
    for virtCoord, vitem in pairs(self.virtSlots) do
        local vitemCoord = coordLib.ItemCoordinate(vitem.name, vitem.nbt)
        if vitemCoord == itemCoord then
            ritem.virtSlots[virtCoord] = vitem.count
        end
    end

    local vcoord = self:_getRootVirtSlot(itemCoord)
    self.realItems[itemCoord] = ritem
    self:_setVirtSlot(self, vcoord, itemCoord,
        ritem.count - self:_getReservedCount(itemCoord))
    self:_checkEmpty(itemCoord)
    self:_calculateTotals(itemCoord)
end

function VirtualInv__index:_initRootVirtSlots()
    for itemCoord, ritem in pairs(self.realItems) do
        local vcoord = self:_getRootVirtSlot(itemCoord)
        self:_setVirtSlot(self, vcoord, itemCoord, ritem.count - self:_getReservedCount(itemCoord))
    end
end

---Check if any inventories are being scanned (and if they are, wait until no are!)
function VirtualInv__index:_checkScanLock()
    while next(self.scanLocks) do
        os.pullEvent(scanLockFreeEvent)
    end
end

---Directly set the scan lock for an inventory
---@param inv string
function VirtualInv__index:_setScanLock(inv)
    self.scanLocks[inv] = true
end

---Free a scan lock for an inventory
---@param inv string
function VirtualInv__index:_freeScanLock(inv)
    self.scanLocks[inv] = nil
    os.queueEvent(scanLockFreeEvent)
end

---Get a string representation of the status of this VirtualInventory
---@return string
function VirtualInv__index:toString()
    local s = "realItems = " .. textutils.serialise(self.realItems)
    s = s .. "\n\n\nvirtSlots = " .. textutils.serialise(self.virtSlots)
    s = s .. "\n\n\nitems = " .. Reserve__index.toString(self)
    return s
end

---Scan a given inventory
---@param inv string
---@param slots table<string,number[]>
function VirtualInv__index:_scanInv(inv, slots)
    self:_setScanLock(inv)
    local list = peripheral.call(inv, "list")
    for _, i in ipairs(slots[inv]) do
        local coord = coordLib.InventoryCoordinate(inv, i)
        if list[i] then
            local itemCoord = coordLib.ItemCoordinate(list[i].name, list[i].nbt)
            self:_setSlot(coord, itemCoord, list[i].count)
        else
            self:_setSlot(coord, nil, 0)
        end
    end
    self:_freeScanLock(inv)
end

---Get a list of functions to call in parallel to scan this Reserve
---@return fun()[]
function VirtualInv__index:getScanFuncs()
    local f = {}
    ---@type table<string,boolean>
    local inventories = {}
    ---@type table<string,number[]>
    local slotsPerInventory = {}
    for _, coord in ipairs(self.realSlotList) do
        local inv, slot = coordLib.splitInventoryCoordinate(coord)
        inventories[inv] = true
        slotsPerInventory[inv] = slotsPerInventory[inv] or {}
        slotsPerInventory[inv][#slotsPerInventory[inv] + 1] = slot
    end
    for inv in pairs(inventories) do
        f[#f + 1] = function()
            self:_scanInv(inv, slotsPerInventory)
        end
    end
    return f
end

---Scan all slots this VirtualInv covers
function VirtualInv__index:scan()
    local f = self:getScanFuncs()
    batchExecute(f, false, 128)
end

---@param invs InventoryCompatible[]
---@return VirtualInv
function VirtualInv.new(invs)
    local ess = Reserve.emptySlotStorage()
    ---@diagnostic disable-next-line: missing-fields
    ---@class VirtualInv : Reserve
    local self = setmetatable(Reserve.empty({}), VirtualInv) --[[@as VirtualInv]]
    self.parent = self
    self.lastVirtSlot = 0
    self.virtName = "VIRT"
    self.itemLocks = {}
    self.realSlotList = {}
    for _, inv in ipairs(invs) do
        for slot = 1, invCall(inv, "size") do
            self.realSlotList[#self.realSlotList + 1] = coordLib.InventoryCoordinate(inv, slot)
        end
    end
    self.virtSlots = {}
    self.scanLocks = {}
    self.realItemLUT = {}
    self.ess = ess
    self.rootVirtSlotLUT = {}
    self.realItems = {}

    self:scan()

    return self
end

---



















local lastEssId = 0
---@return EmptySlotStorage
---@param slotlist InventoryCoordinate[]?
function Reserve.emptySlotStorage(slotlist)
    lastEssId = lastEssId + 1
    ---@class EmptySlotStorage
    local ess = {
        id = lastEssId,
        __type = "EmptySlotStorage"
    }
    ---@class EmptySlotStorage
    local ess__index = {}
    ---@type table<InventoryCoordinate,boolean>
    local slots = {}
    ess.slots = slots
    if slotlist then
        for _, slot in ipairs(slotlist) do
            slots[slot] = true
        end
    end
    ---Mark a slot as being free
    ---@param s InventoryCoordinate
    function ess__index.add(s)
        slots[s] = true
    end

    ---Mark a slot as being free
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

    ---Mark a slot as NOT being free
    function ess__index.clear(s)
        slots[s] = nil
    end

    function ess__index.clearAll()
        slots = {}
    end

    -- wanted to make it serializable :)
    return setmetatable(ess, { __index = ess__index })
end

return VirtualInv
