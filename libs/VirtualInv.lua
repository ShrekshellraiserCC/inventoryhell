---@alias ItemNBT string
---@alias ItemName string

---@class CCItemInfo
---@field name string
---@field displayName string
---@field nbt string?
---@field count number
---@field maxCount number
---@field enchantments {level:number,name:string,displayName:string}[]?

---@class InventoryCoordinate : string
---@class ItemCoordinate : string

local coordLib = require("libs.Coordinates")
local shrexpect = require("libs.shrexpect")


---@type table<ItemCoordinate,CCItemInfo>
local detailedDataCache = {}
---@type table<ItemCoordinate,boolean>
local detailedCacheLock = {}

---@type table<string,string> [name] -> displayName
local displayNameCache = {}

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
    table.sort(t, function(a, b)
        return a.count > b.count
    end)
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

-- Credit to @FatBoyChummy
-- Parallelism handler: parallelizes certain peripheral calls.
local function newParallelismHandler(limit)
    ---@class ParallelismHandler
    local parallelismHandler = {
        tasks = {},
        limit = limit or 128,
        n = 0
    }

    --- Add a task to the parallelism handler.
    --- This method respects the task limit, and will execute the tasks if the limit is reached.
    ---@param task function The task to add.
    ---@param ... any The arguments to pass to the task
    function parallelismHandler:addTask(task, ...)
        self.n = self.n + 1
        self.tasks[self.n] = {
            task = task,
            args = table.pack(...),
        }

        if self.n >= self.limit then
            self:execute()
        end
    end

    --- Execute all tasks in parallel.
    function parallelismHandler:execute()
        local _tasks = {}
        local _results = {}
        for i, task in ipairs(self.tasks) do
            _tasks[i] = function()
                _results[i] = task.task(table.unpack(task.args, 1, task.args.n))
            end
        end

        self.tasks = {}
        self.n = 0
        parallel.waitForAll(table.unpack(_tasks))
        return _results
    end

    return parallelismHandler
end


---@alias InventoryCompatible string

---@param inv InventoryCompatible
---@param fun string
---@param ... any
local function invCall(inv, fun, ...)
    return peripheral.call(inv, fun, ...)
end

---@param inv string
---@param slot integer
---@return CCItemInfo
local function invGetItemDetail(inv, slot)
    return invCall(inv, "getItemDetail", slot)
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
        ---@type CCItemInfo
        local info = invGetItemDetail(inv, slot)
        detailedDataCache[itemCoord] = clone(info)
        detailedCacheLock[itemCoord] = nil
        -- Prioritize the displayName of items without NBT in the cache
        if info.nbt then
            displayNameCache[info.name] = displayNameCache[info.name] or info.displayName
        else
            displayNameCache[info.name] = info.displayName
        end
        os.queueEvent(cacheFinishEvent)
        return info
    end
    error(("getItemDetail, no invCoord, but itemCoord (%s) not in cache!"):format(itemCoord), 2)
end

local function log(verbose, s, ...)
    if verbose then
        print(s:format(...))
    end
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

---List out items in this reserve
---@return CCItemInfo[]
function Reserve__index:list()
    local list = {}
    for k, v in pairs(self.items) do
        list[#list + 1] = clone(v)
        list[#list].slot = nil
    end
    table.sort(list, function(a, b)
        return a.count > b.count
    end)
    return list
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
















---@class VirtualInv : Reserve
---@field virtSlots table<InventoryCoordinate,VirtualItem>
---@field virtSlotByItem table<ItemCoordinate,table<InventoryCoordinate,VirtualItem>>
---@field realItems table<ItemCoordinate,RealItem>
---@field invSizes table<string,integer>
---@field realSlotList InventoryCoordinate[]
---@field realItemLUT table<InventoryCoordinate,ItemCoordinate>
---@field itemLocks table<ItemCoordinate,boolean>
---@field scanLocks table<InventoryCompatible,integer>
---@field rootVirtSlotLUT table<ItemCoordinate,InventoryCoordinate>
---@field changedCallback fun(self:VirtualInv)
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
    if from == self or to == self then
        self:_callChangedCallback()
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
    if from == self or to == self then
        self:_callChangedCallback()
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
    self:_callChangedCallback()
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
    local info = invGetItemDetail(emptyInv, emptySlot)
    local itemCoord = coordLib.ItemCoordinate(info.name, info.nbt)
    detailedDataCache[itemCoord] = detailedDataCache[itemCoord] or clone(info)
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
    if r ~= self then
        local vitem = r.items[itemCoord]
        if vitem then
            self:_setVirtSlot(r, vitem.slot, itemCoord, vitem.count + moved)
        else
            local vcoord = self:_newVirtSlot()
            self:_setVirtSlot(r, vcoord, itemCoord, moved)
        end
    end
    self:_callChangedCallback()
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

---@param executor ParallelismHandler
---@param tracker ScanTracker?
function VirtualInv__index:executeDefrag(executor, tracker)
    tracker = tracker or VirtualInv.defaultTracker()
    for i, v in pairs(self.realItems) do
        tracker.totalItems = tracker.totalItems + 1
    end
    for i, v in pairs(self.realItems) do
        executor:addTask(function()
            self:_defragItem(i)
            tracker.itemsDefragged = tracker.itemsDefragged + 1
        end)
    end
end

---Defrag this VirtualInv
---@param verbose boolean?
---@param tracker ScanTracker?
function VirtualInv__index:defrag(verbose, tracker)
    local executor = newParallelismHandler()
    log(verbose, "Defragging...")
    local t0 = os.epoch("utc")
    self:executeDefrag(executor, tracker)
    executor:execute()
    local t1 = os.epoch("utc")
    log(verbose, "Done [%.2f]", (t1 - t0) / 1000)
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
            if self.virtSlotByItem[itemCoord] then
                self.virtSlotByItem[itemCoord][virtCoord] = nil
                if not next(self.virtSlotByItem[itemCoord]) then
                    self.virtSlotByItem[itemCoord] = nil
                end
            end
        end
        self.virtSlots[virtCoord] = nil
        if self.realItems[itemCoord] then
            self.realItems[itemCoord].virtSlots[virtCoord] = nil
        end
        return
    end
    self.virtSlotByItem[itemCoord] = self.virtSlotByItem[itemCoord] or {}
    self.virtSlotByItem[itemCoord][virtCoord] = vitem
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

---Remove an inventory from this VirtualInventory
---@param inv string
function VirtualInv__index:removeInventory(inv)
    local coords = {}
    for i = 1, invCall(inv, "size") do
        local icoord = coordLib.InventoryCoordinate(inv, i)
        self:_emptySlot(icoord)
        self.ess.clear(icoord)
        coords[icoord] = true
    end
    for i = #self.realSlotList, 1, -1 do
        if coords[self.realSlotList[i]] then
            table.remove(self.realSlotList, i)
        end
    end
end

---Add an inventory to this VirtualInventory and scan it
---Scan occurs sequentially, so this only uses one event
---@param inv string
function VirtualInv__index:addInventory(inv)
    local slots = {}
    for i = 1, invCall(inv, "size") do
        slots[i] = i
    end
    local executor = newParallelismHandler(1)
    self:_scanInv(inv, invCall(inv, "list"), slots, executor)
    executor:execute()
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
        ritem = self.realItems[itemCoord] or ritem -- fix a race condition here by just double checking
    end
    ritem.count = ritem.count + count
    if count == ritem.maxCount then
        ritem.fullSlots[invCoord] = count
    else
        ritem.partSlots[invCoord] = count
    end

    -- Go find all virtual slots with this item, and append them to this realItem
    for virtCoord, vitem in pairs(self.virtSlotByItem[itemCoord] or {}) do
        ritem.virtSlots[virtCoord] = vitem.count
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
    self.scanLocks[inv] = (self.scanLocks[inv] or 0) + 1
end

---Free a scan lock for an inventory
---@param inv string
function VirtualInv__index:_freeScanLock(inv)
    self.scanLocks[inv] = self.scanLocks[inv] - 1
    if self.scanLocks[inv] == 0 then
        self.scanLocks[inv] = nil
        os.queueEvent(scanLockFreeEvent)
    end
end

---Get a string representation of the status of this VirtualInventory
---@return string
function VirtualInv__index:toString()
    local s = "realItems = " .. textutils.serialise(self.realItems)
    s = s .. "\n\n\nvirtSlots = " .. textutils.serialise(self.virtSlots)
    s = s .. "\n\n\nitems = " .. Reserve__index.toString(self)
    s = s .. "\n\n\nrealSlotList = " .. textutils.serialise(self.realSlotList)
    return s
end

---Get the display name of an item based off it's name
---Returns nil if no displayName is cached.
---@param name string
---@return string?
function VirtualInv__index:getDisplayName(name)
    return displayNameCache[name]
end

---Initialize an empty tracker
---@return ScanTracker
local function defaultTracker()
    ---@class ScanTracker
    ---@field totalInvs integer
    ---@field invsScanned integer
    ---@field totalSlots integer
    ---@field slotsScanned integer
    ---@field totalItems integer
    ---@field itemsDefragged integer
    return {
        totalInvs = 0,
        invsScanned = 0,
        totalSlots = 0,
        slotsScanned = 0,
        totalItems = 0,
        itemsDefragged = 0,
    }
end
VirtualInv.defaultTracker = defaultTracker

---Scan a given inventory
---@param inv string
---@param list table<integer,CCItemInfo>
---@param slots number[]
---@param executor ParallelismHandler
---@param tracker ScanTracker?
function VirtualInv__index:_scanInv(inv, list, slots, executor, tracker)
    tracker = tracker or defaultTracker()
    for _, i in ipairs(slots) do
        local coord = coordLib.InventoryCoordinate(inv, i)
        if list[i] then
            local itemCoord = coordLib.ItemCoordinate(list[i].name, list[i].nbt)
            if detailedDataCache[itemCoord] then
                self:_setSlot(coord, itemCoord, list[i].count)
                tracker.slotsScanned = tracker.slotsScanned + 1
            else
                local f = function()
                    self:_setScanLock(inv)
                    self:_setSlot(coord, itemCoord, list[i].count)
                    self:_freeScanLock(inv)
                    tracker.slotsScanned = tracker.slotsScanned + 1
                end
                executor:addTask(f)
            end
        else
            tracker.slotsScanned = tracker.slotsScanned + 1
            self:_setSlot(coord, nil, 0)
        end
    end
end

local scanRatio = 2
local scanMax = 128
---Get a list of functions to call in parallel to scan this Reserve
---This uses multiple threads to list the contents of each inventory!
---@param verbose boolean?
---@param tracker ScanTracker?
function VirtualInv__index:executeScan(verbose, tracker)
    tracker = tracker or defaultTracker()
    ---@type table<string,boolean>
    local inventories = {}
    ---@type table<string,number[]>
    local slotsPerInventory = {}
    for _, coord in ipairs(self.realSlotList) do
        local inv, slot = coordLib.splitInventoryCoordinate(coord)
        if not inventories[inv] then
            tracker.totalInvs = tracker.totalInvs + 1
        end
        tracker.totalSlots = tracker.totalSlots + 1
        inventories[inv] = true
        slotsPerInventory[inv] = slotsPerInventory[inv] or {}
        slotsPerInventory[inv][#slotsPerInventory[inv] + 1] = slot
    end
    log(verbose, "Discovered %d slots across %d inventories.", tracker.totalSlots, tracker.totalInvs)
    log(verbose, ".list() Contents...")
    local t0 = os.epoch("utc")
    local listings = {}
    local invExecutor = newParallelismHandler()
    for inv in pairs(inventories) do
        invExecutor:addTask(function()
            listings[inv] = invCall(inv, "list")
            tracker.invsScanned = tracker.invsScanned + 1
        end)
    end
    invExecutor:execute()
    local t1 = os.epoch("utc")
    log(verbose, "Done [%.2f]", (t1 - t0) / 1000)
    t0 = t1
    log(verbose, "Detailed Scan...")
    local slotExecutor = newParallelismHandler()
    for inv in pairs(inventories) do
        self:_scanInv(inv, listings[inv], slotsPerInventory[inv], slotExecutor, tracker)
    end
    slotExecutor:execute()
    t1 = os.epoch("utc")
    log(verbose, "Done [%.2fs]", (t1 - t0) / 1000)
end

---Scan all slots this VirtualInv covers
function VirtualInv__index:scan(verbose)
    local tracker = defaultTracker()

    local function throbber()
        local t0 = os.epoch("utc")
        local _, y = term.getCursorPos()
        while true do
            local ox, oy = term.getCursorPos()
            term.setCursorPos(1, 1)
            term.clearLine()
            local t1 = os.epoch("utc")
            local remaining = (tracker.totalSlots - tracker.slotsScanned)
            local percentage = tracker.slotsScanned / tracker.totalSlots
            local eta = (t1 - t0) * (1 / (percentage) - 1)
            term.setTextColor(colors.white)
            log(verbose, "%d slots remain (%.2f%%). ETA: %.2fs", remaining, percentage * 100, eta / 1000)
            term.setCursorPos(ox, oy)
            sleep(0.2)
        end
    end
    local function run()
        self:executeScan(verbose, tracker)
    end
    log(verbose, "Detailed Cache Build...")
    if verbose then
        parallel.waitForAny(throbber, run)
    else
        run()
    end
    self:_callChangedCallback()
end

---@class FragMap
---@field [number] number 'slot' -> percentage [0,1]
---@field nostack table<number,boolean> slots containing non-stacking items
---@field invs table<string,number[]> inventory -> 'slot'[]

---Get a table of each slots usage expressed as a percentage [0,1]. Non-stackable items have a value of 2.
---@return FragMap
function VirtualInv__index:getFragMap()
    ---@type FragMap
    local usage = {
        nostack = {},
        invs = {}
    }
    for i, coord in ipairs(self.realSlotList) do
        local item = self.realItemLUT[coord]
        local inv, slot = coordLib.splitInventoryCoordinate(coord)
        usage.invs[inv] = usage.invs[inv] or {}
        usage.invs[inv][#usage.invs[inv] + 1] = i
        if not item then
            usage[i] = 0
        else
            local ritem = self.realItems[item]
            local count = ritem.fullSlots[coord] or ritem.partSlots[coord]
            if ritem.maxCount == 1 then
                usage.nostack[i] = true
            end
            usage[i] = count / ritem.maxCount
        end
    end
    return usage
end

---Get a table containing information about this VirtualInv's slots
---@return {total:integer,used:integer}
function VirtualInv__index:getSlotInfo()
    local totalSlots = #self.realSlotList
    local usedSlots = 0
    for invCoord, itemCoord in pairs(self.realItemLUT) do
        usedSlots = usedSlots + 1
    end
    return {
        total = totalSlots,
        used = usedSlots
    }
end

---Call a function when any of the contents in this inventory change
---@param f fun(self:VirtualInv)
function VirtualInv__index:setChangedCallback(f)
    self.changedCallback = f
end

function VirtualInv__index:_callChangedCallback()
    if self.changedCallback then
        self.changedCallback(self)
    end
end

---@param invs InventoryCompatible[]
---@param tracker ScanTracker?
---@return VirtualInv
function VirtualInv.new(invs, tracker)
    local ess = Reserve.emptySlotStorage()
    ---@diagnostic disable-next-line: missing-fields
    ---@class VirtualInv : Reserve
    local self = setmetatable(Reserve.empty({}), VirtualInv) --[[@as VirtualInv]]
    self.parent = self
    self.lastVirtSlot = 0
    self.virtName = "VIRT"
    self.itemLocks = {}
    self.realSlotList = {}
    self.invSizes = {}
    local f = {}
    local verbose = true
    log(verbose, "Gathering inventory sizes... ")
    local t0 = os.epoch("utc")
    for _, inv in ipairs(invs) do
        f[#f + 1] = function()
            self.invSizes[inv] = invCall(inv, "size")
        end
    end
    batchExecute(f, false, 128)
    local t1 = os.epoch("utc")
    log(verbose, "Done [%.2fs]", (t1 - t0) / 1000)
    log(verbose, "Generating Coordinates... ")
    t0 = t1
    for _, inv in ipairs(invs) do
        for slot = 1, self.invSizes[inv] do
            local coord = coordLib.InventoryCoordinate(inv, slot)
            self.realSlotList[#self.realSlotList + 1] = coord
        end
    end
    t1 = os.epoch("utc")
    log(verbose, "Done [%.2fs]", (t1 - t0) / 1000)


    self.virtSlots = {}
    self.virtSlotByItem = {}
    self.scanLocks = {}
    self.realItemLUT = {}
    self.ess = ess
    self.rootVirtSlotLUT = {}
    self.realItems = {}

    if tracker then
        self:executeScan(verbose, tracker)
    else
        self:scan(verbose)
    end

    self:defrag(verbose, tracker)

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
    ---@param s InventoryCoordinate
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
