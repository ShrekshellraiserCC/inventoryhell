-- Abstract Crafting Lib?
-- Shrek Inventory Lib
-- Simple Storage Lib
local lib = {}
local expect = require("cc.expect").expect

local TaskLib = require("STL")


lib.Item = require("ItemDescriptor")
local VirtualInv = require("VirtualInv")
lib.Reserve = VirtualInv

function lib.wrap(invList)
    -- Called 'this' to avoid scope conflictions with 'self'
    local this = {}
    this.scheduler = TaskLib.Scheduler()

    local invReserve = VirtualInv.new(invList)
    this.reserve = invReserve
    invReserve:defrag()

    local turtlePort = 7777
    local wmodem = peripheral.find("modem", function(name, wrapped)
        return not wrapped.isWireless()
    end) --[[@as Modem]]
    wmodem.open(turtlePort)

    ---@type table<string,boolean>
    local freeTurtles = {}
    ---@type table<string,boolean>
    local allTurtles = {}
    ---@type table<string,boolean>
    local busyTurtles = {}
    function this.searchForTurtles()
        wmodem.transmit(turtlePort, turtlePort, { "GET_NAME" })
        local tid = os.startTimer(1)
        ---@type table<string,boolean>
        local foundTurtles = {}
        while true do
            local e, side, channel, replyChannel, message = os.pullEvent()
            if e == "modem_message" then
                if type(message) == "table" and message[1] == "NAME" then
                    foundTurtles[message[2]] = true
                    os.cancelTimer(tid)
                    tid = os.startTimer(1)
                end
                print(e)
            elseif e == "timer" and side == tid then
                break
            end
        end
        local foundNew = false
        for k in pairs(foundTurtles) do
            if not allTurtles[k] then
                allTurtles[k] = true
                freeTurtles[k] = true
                foundNew = true
            end
        end
        for k in pairs(allTurtles) do
            if not foundTurtles[k] then
                assert(not busyTurtles[k], "A turtle in use has stopped responding!")
                freeTurtles[k] = nil
                allTurtles[k] = nil
            end
        end
        if foundNew then
            os.queueEvent("turtle_freed")
        end
    end

    this.searchForTurtles()

    ---Reserve a turtle for use
    ---@return string
    local function allocateTurtle()
        local turt = next(freeTurtles)
        if not turt then
            os.pullEvent("turtle_freed")
            return allocateTurtle()
        end
        freeTurtles[turt] = nil
        busyTurtles[turt] = true
        return turt
    end

    local function freeTurtle(turt)
        freeTurtles[turt] = true
        busyTurtles[turt] = nil
        os.queueEvent("turtle_freed")
    end

    local function text(y, s, ...)
        local ox, oy = term.getCursorPos()
        term.setCursorPos(1, y)
        term.clearLine()
        term.write(s:format(...))
        term.setCursorPos(ox, oy)
    end
    local function length(t)
        local c = 0
        for k, v in pairs(t) do c = c + 1 end
        return c
    end
    local function debugOverlay()
        text(3, "fT:%d", length(freeTurtles))
    end

    ---@class QueableTask : Task
    local QueableTask__index = setmetatable({}, TaskLib.Task)
    local QueableTask = { __index = QueableTask__index }

    ---Queue this task
    function QueableTask__index:queue()
        this.scheduler.queueTask(self)
    end

    ---@class PushTask : QueableTask
    ---@field r Reserve?
    local PushTask__index = setmetatable({}, QueableTask)
    local PushTask = { __index = PushTask__index }
    this.PushTask = PushTask

    ---Create a new PushTask using an optional Reserve r
    ---@param r Reserve?
    ---@return PushTask|Task
    function PushTask.new(r)
        local self = setmetatable(TaskLib.Task.new({}), PushTask)
        self.r = r or invReserve
        return self
    end

    ---@alias InventoryProvider fun():InventoryCompatible

    ---Distribue an item to a list of slots, with limit in each slot
    --- * limit items will be placed in each slot unless:
    ---   * no more matching items remain in the storage
    ---   * no more items are accepted in the slots
    ---@param to InventoryCompatible|InventoryProvider
    ---@param item ItemDescriptor
    ---@param slots integer[]
    ---@param limit integer
    ---@return self
    function PushTask__index:distributeToSlots(to, item, slots, limit)
        for i, slot in ipairs(slots) do
            self.funcs[#self.funcs + 1] = function()
                if type(to) == "function" then
                    to = to()
                end
                local moved = self.r:pushItems(to, item, limit, slot)
                return moved
            end
        end
        return self
    end

    ---Push an item to a slot
    --- * limit items will be placed in the slot unless:
    ---   * no more matching items remain in the storage
    ---   * no more items are accepted in the slots
    ---@param to InventoryCompatible|InventoryProvider
    ---@param item ItemDescriptor
    ---@param slot integer
    ---@param limit integer
    ---@return self
    function PushTask__index:toSlot(to, item, slot, limit)
        return self:distributeToSlots(to, item, { slot }, limit)
    end

    ---Perform a (slow) dumb push to an inventory until:
    --- * limit is reached (if a limit is supplied)
    --- * no more matching items are accepted by the inventory
    --- * no more matching items remain in the storage
    ---@param to InventoryCompatible|InventoryProvider
    ---@param item ItemDescriptor
    ---@param limit integer?
    ---@return self
    function PushTask__index:dumbPush(to, item, limit)
        local f = function()
            if type(to) == "function" then
                to = to()
            end
            return self.r:pushItems(to, item, limit)
        end
        self.funcs[#self.funcs + 1] = f
        return self
    end

    ---@class PullTask : QueableTask
    ---@field r Reserve?
    local PullTask__index = setmetatable({}, QueableTask)
    local PullTask = { __index = PullTask__index }
    this.PullTask = PullTask

    ---Pull an item from a slot
    ---@param from InventoryCompatible|InventoryProvider
    ---@param slot integer
    ---@param limit integer?
    ---@param r Reserve?
    ---@return PushTask|Task
    function PullTask.fromSlot(from, slot, limit, r)
        local f = function()
            r = r or invReserve
            if type(from) == "function" then
                from = from()
            end
            return r:pullItems(from, slot, limit)
        end
        return setmetatable(TaskLib.Task.new({ f }), PullTask)
    end

    ---@class TurtleCraftTask : QueableTask
    local TurtleCraftTask__index = setmetatable({}, QueableTask)
    local TurtleCraftTask = { __index = TurtleCraftTask__index }
    this.TurtleCraftTask = TurtleCraftTask

    local turtleSlotList = { 1, 2, 3, 5, 6, 7, 9, 10, 11 }
    ---Create a task to craft a grid recipe using a turtle
    ---@param items ItemDescriptor[]
    ---@param recipe integer[]
    ---@param count integer
    ---@param r Reserve?
    ---@param callback function?
    ---@return TurtleCraftTask
    function TurtleCraftTask.craft(items, recipe, count, r, callback)
        local turt
        local allocateTask = TaskLib.Task.new({ function()
            turt = allocateTurtle()
        end })
        local function getTurtle()
            return turt
        end
        ---@type PushTask
        local pushIngredientsTask = PushTask.new(r):addSubtask(allocateTask)
        for i, v in ipairs(items) do
            local slots = {}
            for slot, item in pairs(recipe) do
                if item == i then
                    slots[#slots + 1] = turtleSlotList[slot]
                end
            end
            pushIngredientsTask:distributeToSlots(getTurtle, v, slots, count)
        end
        local craftingTask = TaskLib.Task.new({ function()
            wmodem.transmit(turtlePort, turtlePort, { "CRAFT", turt })
            while true do
                local e, side, channel, replyChannel, message = os.pullEvent("modem_message")
                if type(message) == "table" and message[1] == "CRAFT_DONE" and message[2] == turt then
                    break
                end
            end
        end }):addSubtask(pushIngredientsTask)
        local pullProductTask = PullTask.fromSlot(getTurtle, 1, count, r):addSubtask(craftingTask)
        local freeTask = TaskLib.Task.new({ function()
            freeTurtle(turt)
        end }):addSubtask(pullProductTask)

        local callbackTask = freeTask
        if callback then
            callbackTask = TaskLib.Task.new({ callback }):addSubtask(freeTask)
        end

        return setmetatable(callbackTask, TurtleCraftTask)
    end

    ---Start this wrapper's coroutine
    ---Does not return, run this in parallel (or another coroutine manager)
    function this.run()
        wmodem.open(turtlePort)
        this.scheduler.queueTask(TaskLib.Task.new({ function()
            while true do
                debugOverlay()
                sleep(0.05)
            end
        end }):setPriority(2))
        this.scheduler.run()
        wmodem.closeAll()
    end

    return this
end

return lib
