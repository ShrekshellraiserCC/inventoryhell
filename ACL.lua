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
    ---@field rootTask Task
    local TurtleCraftTask__index = setmetatable({}, QueableTask)
    local TurtleCraftTask = { __index = TurtleCraftTask__index }
    this.TurtleCraftTask = TurtleCraftTask

    function TurtleCraftTask__index:addSubtask(t)
        self.rootTask:addSubtask(t)
    end

    ---@type table<string,table<string,boolean>>
    local freeMachines = {}
    ---@type table<string,table<string,boolean>>
    local busyMachines = {}
    ---@type table<string,RegisteredMachineType> inv index,slot
    local registeredMachineTypes = {}
    ---@type table<string,RegisteredMachine>
    local registeredMachines = {}

    this.craft = {}

    local turtleSlotList = { 1, 2, 3, 5, 6, 7, 9, 10, 11 }
    ---Create a task to craft a grid recipe using a turtle
    ---@param items ItemDescriptor[]
    ---@param recipe integer[]
    ---@param count integer
    ---@param r Reserve?
    ---@param callback function?
    ---@return TurtleCraftTask
    function this.craft.grid(items, recipe, count, r, callback)
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

        ---@type TurtleCraftTask
        local callbackTask = freeTask
        if callback then
            callbackTask = TaskLib.Task.new({ callback }):addSubtask(freeTask)
        end
        callbackTask.rootTask = allocateTask

        return setmetatable(callbackTask, TurtleCraftTask)
    end

    ---@alias SlotMap {[1]:integer,[2]:integer}
    ---@alias RegisteredMachine {invs:string[],mtype:string}
    ---@alias RegisteredMachineType {slots:SlotMap[],output:SlotMap}

    ---Reserve a machine for use
    ---@param mtype string
    ---@return string
    ---@return {[1]:string,[2]:integer}[]
    ---@return {[1]:string,[2]:integer}
    function this.craft.allocateMachine(mtype)
        local machine = next(freeMachines[mtype])
        if not machine then
            os.pullEvent("machine_freed")
            return this.craft.allocateMachine(mtype)
        end
        freeMachines[mtype][machine] = nil
        busyMachines[mtype][machine] = true
        -- make slot lookup
        local slotlut = {}
        local rmachine = registeredMachines[machine]
        for i, v in ipairs(registeredMachineTypes[mtype].slots) do
            slotlut[i] = { rmachine.invs[v[1]], v[2] }
        end
        local outputInfo = registeredMachineTypes[mtype].output
        local output = {
            rmachine.invs[outputInfo[1]], outputInfo[2]
        }
        return machine, slotlut, output
    end

    ---Free a machine that was previously in use
    ---@param machine string
    function this.craft.freeMachine(machine)
        local mtype = registeredMachines[machine].mtype
        freeMachines[mtype][machine] = true
        busyMachines[mtype][machine] = nil
        os.queueEvent("machine_freed")
    end

    ---Define a new type of machine
    ---@param mtype string
    ---@param slotmap SlotMap[] inv index, slot
    ---@param outputSlot SlotMap inv index, slot
    function this.craft.newMachineType(mtype, slotmap, outputSlot)
        registeredMachineTypes[mtype] = { slots = slotmap, output = outputSlot }
        busyMachines[mtype] = {}
        freeMachines[mtype] = {}
    end

    ---Register a machine of a given type
    ---@param mtype string
    ---@param name string
    ---@param invs string[]?
    function this.craft.registerMachine(mtype, name, invs)
        invs = invs or { name }
        registeredMachines[name] = { invs = invs, mtype = mtype }
        freeMachines[mtype][name] = true
    end

    ---@class MachineCraftTaskFactory
    ---@field machine string?
    ---@field slotLookup InventoryCoordinate[]
    ---@field r Reserve?
    ---@field produces integer
    ---@field recipe integer[]|SlotMap[]
    ---@field count integer
    local MachineCraftTaskFactory__index = setmetatable({}, QueableTask)
    local MachineCraftTaskFactory = { __index = MachineCraftTaskFactory__index }
    this.MachineCraftTask = MachineCraftTaskFactory


    ---@class MachineCraftTask : QueableTask
    ---@field rootTask Task
    local MachineCraftTask__index = setmetatable({}, QueableTask)
    local MachineCraftTask = { __index = MachineCraftTask__index }

    function MachineCraftTask__index:addSubtask(t)
        self.rootTask:addSubtask(t)
    end

    ---@param count integer
    ---@return MachineCraftTaskFactory
    function this.craft.generic(count)
        return setmetatable({ count = count }, MachineCraftTaskFactory)
    end

    ---Use the machine reserve system to automatically get machine inventories
    ---@param machine string
    ---@return self
    function MachineCraftTaskFactory__index:reserveMachine(machine)
        self.machine = machine
        return self
    end

    ---Directly provide the slot lookup to use
    --- This bypasses the machine allocation system.
    ---@param lut InventoryCoordinate[]
    ---@return self
    function MachineCraftTaskFactory__index:setSlotLookup(lut)
        self.slotLookup = lut
        return self
    end

    ---Set the reserve to use for all inventory operations
    ---@param r any
    ---@return self
    function MachineCraftTaskFactory__index:setReserve(r)
        self.r = r
        return self
    end

    ---Set the recipe
    ---@param items ItemDescriptor[]
    ---@param recipe integer[]|{[1]:integer,[2]:integer}[] {item,count}
    ---@param produces integer
    ---@return self
    function MachineCraftTaskFactory__index:setRecipe(items, recipe, produces)
        self.recipe = recipe
        self.items = items
        self.produces = produces
        return self
    end

    ---Build the constructed machine task
    ---@return QueableTask
    function MachineCraftTaskFactory__index:build()
        local checkTime = 0.5
        local machine, slotlut, output
        local doAllocate = self.machine
        local allocateTask
        if doAllocate then
            allocateTask = TaskLib.Task.new { function()
                machine, slotlut, output = this.craft.allocateMachine(self.machine)
            end }
        else
            slotlut = assert(self.slotLookup, "No machine or slot lookup set on MachineCraftTask build!")
        end
        local reserve = self.r or this.reserve
        local moveFuncs = {}
        -- Setup pushItem calls
        for i, v in ipairs(self.items) do
            for slot, item in pairs(self.recipe) do
                local icount = 1
                if type(item) == "table" then
                    item, icount = item[1], item[2]
                end
                if item == i then
                    moveFuncs[#moveFuncs + 1] = function()
                        local toInv, toSlot = table.unpack(slotlut[slot])
                        local toMove = icount
                        local moved = 0
                        while moved < toMove do
                            local movedIter = reserve:pushItems(toInv, v, toMove - moved, toSlot)
                            moved = moved + movedIter
                            if moved < toMove then
                                sleep(checkTime)
                            end
                        end
                    end
                end
            end
        end
        -- Setup pullItems calls
        moveFuncs[#moveFuncs + 1] = function()
            local fromInv, fromSlot = table.unpack(output)
            local moved = 0
            local toMove = self.produces
            while moved < toMove do
                local movedIter = reserve:pullItems(fromInv, fromSlot, toMove - moved)
                moved = moved + movedIter
                if moved < toMove then
                    sleep(checkTime)
                end
            end
        end
        local moveTask = TaskLib.Task.new(moveFuncs)
        if doAllocate then
            moveTask:addSubtask(allocateTask)
        end
        local freeTask
        if doAllocate then
            freeTask = TaskLib.Task.new({ function()
                this.craft.freeMachine(machine)
            end }):addSubtask(moveTask)
        end
        local tailTask = freeTask or moveTask
        tailTask.rootTask = allocateTask or moveTask
        return setmetatable(tailTask, MachineCraftTask)
    end

    local function registerFurnaces()
        this.craft.newMachineType("furnace", { { 1, 1 }, { 1, 2 } }, { 1, 3 })
        for _, v in ipairs(peripheral.getNames()) do
            if v:match("minecraft:furnace") then
                this.craft.registerMachine("furnace", v)
            end
        end
    end
    registerFurnaces()

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
