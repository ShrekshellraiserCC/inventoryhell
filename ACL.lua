-- Abstract Crafting Lib?
-- Shrek Inventory Lib
-- Simple Storage Lib
local lib            = {}
local ItemDescriptor = require("ItemDescriptor")
local shrexpect      = require("shrexpect")
local coord          = require("Coordinates")

local TaskLib        = require("STL")


lib.Item = require("ItemDescriptor")
local VirtualInv = require("VirtualInv")
lib.Reserve = VirtualInv

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

---Wrap a list of inventories
---@param invList string[]
---@param wmodem Modem?
function lib.wrap(invList, wmodem)
    -- Called 'this' to avoid scope conflictions with 'self'
    local this = {}
    this.scheduler = TaskLib.Scheduler()

    local invReserve = VirtualInv.new(invList)
    this.reserve = invReserve
    invReserve:defrag()

    local turtlePort = 7777
    wmodem = wmodem or peripheral.find("modem", function(name, wrapped)
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
    local PushTask__index = setmetatable({}, QueableTask)
    local PushTask = { __index = PushTask__index }
    this.PushTask = PushTask

    ---Create a new PushTask using an optional Reserve r
    ---@param r Reserve?
    ---@param name string?
    ---@return PushTask|Task
    function PushTask.new(r, name)
        local self = setmetatable(TaskLib.Task.new({}, name), PushTask)
        self.reserve = r
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
                local moved = (self.reserve or this.reserve):pushItems(to, item, limit, slot)
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
            return (self.reserve or this.reserve):pushItems(to, item, limit)
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
    function PullTask__index:fromSlot(from, slot, limit)
        local f = function()
            local r = self.reserve or invReserve
            if type(from) == "function" then
                from = from()
            end
            return r:pullItems(from, slot, limit)
        end
        self.funcs[#self.funcs + 1] = f
        return self
    end

    ---@param r Reserve?
    ---@param name string?
    ---@return PullTask|Task
    function PullTask.new(r, name)
        local self = setmetatable(TaskLib.Task.new({}, name), PullTask)
        self.reserve = r
        return self
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

    ---@class RegisteredRecipe
    ---@field type "grid"|string machine type
    ---@field items ItemDescriptor[]
    ---@field recipe integer[]|{[1]:integer,[2]:integer}[]
    ---@field produces integer
    ---@field product ItemCoordinate

    ---@type table<ItemCoordinate,RegisteredRecipe[]>
    local registeredRecipes = {}

    this.craft = {}

    ---Register a recipe
    ---@param mtype string
    ---@param items ItemDescriptor[]
    ---@param recipe integer[]|{[1]:integer,[2]:integer}[]
    ---@param product ItemCoordinate
    ---@param produces integer
    function this.craft.registerRecipe(mtype, items, recipe, product, produces)
        ---@type RegisteredRecipe
        local r = {
            items = items,
            type = mtype,
            recipe = recipe,
            product = product,
            produces = produces,
        }
        registeredRecipes[product] = registeredRecipes[product] or {}
        table.insert(registeredRecipes[product], r)
    end

    ---@param recipe RegisteredRecipe
    ---@param count integer
    ---@param jobItemCounts table<string,integer>
    ---@return MachineCraftTask|TurtleCraftTask?
    ---@return table<string,integer> jobItemCounts
    local function tryCraft(recipe, count, jobItemCounts)
        -- TODO auto split count into multiple crafts
        --  * For example, I ask for 128 furnaces, split it into two 64 furnace craft tasks.
        --  * For furnaces, this depends on the fuel used, but for coal split 64 glass into 8 glass per furnace
        --    Make this behavior optional, per machine type. Choose to prioritize distribution versus centralization.
        ---@type MachineCraftTask|TurtleCraftTask
        local task, craftCount
        if recipe.type == "grid" then
            task = this.craft.grid(recipe.items, recipe.recipe, math.ceil(count / recipe.produces))
            craftCount = math.ceil(count / recipe.produces)
        else
            task, craftCount = this.craft.generic(count)
                :reserveMachine(recipe.type)
                :setRecipe(recipe.items, recipe.recipe, recipe.produces)
                :build()
        end
        jobItemCounts = jobItemCounts or {}
        local taskItemCounts = {}
        for _, item in ipairs(recipe.recipe) do
            if type(item) == "number" then
                local id = recipe.items[item]:serialize()
                jobItemCounts[id] = (jobItemCounts[id] or 0) + 1 * craftCount
                taskItemCounts[id] = (taskItemCounts[id] or 0) + 1 * craftCount
            else
                local id = recipe.items[item[1]]:serialize()
                jobItemCounts[id] = (jobItemCounts[id] or 0) + item[2] * craftCount
                taskItemCounts[id] = (taskItemCounts[id] or 0) + item[2] * craftCount
            end
        end
        local craftSubtasks = {}
        for sid, need in pairs(taskItemCounts) do
            local id = ItemDescriptor.unserialize(sid)
            local have = this.reserve:getCount(id) - (jobItemCounts[sid] - taskItemCounts[sid])
            if have < need then
                local task, newJobItemCounts = this.craft.craft(id, need - have, jobItemCounts)
                if not task then
                    -- There's not enough items in this inventory to satisfy this!
                    return nil, jobItemCounts
                end
                craftSubtasks[#craftSubtasks + 1] = task
                newJobItemCounts[sid] = newJobItemCounts[sid] - (have - need)
                jobItemCounts = newJobItemCounts
            end
        end
        for _, stask in ipairs(craftSubtasks) do
            task:addSubtask(stask)
        end
        return task, jobItemCounts
    end

    -- TODO by default craft.craft should accept the first option that works
    -- add an argument to choose the second, or third, etc, option instead
    -- allows for the user to scroll through possible crafts until they find
    -- one that isn't broken

    ---@param item ItemDescriptor|ItemCoordinate
    ---@param count integer
    ---@param itemCounts table<string,integer>?
    ---@return MachineCraftTask|TurtleCraftTask?
    ---@return table<string,integer> ItemDescriptor string, integer
    function this.craft.craft(item, count, itemCounts)
        itemCounts = itemCounts or {}
        if type(item) == "table" and item:toCoord() then
            item = item:toCoord()
        end
        if type(item) == "table" then
            -- ItemDescriptor
            error("NYI")
        end
        local craftOptions = {}
        local task
        for i, v in pairs(registeredRecipes[item] or {}) do
            local craftCount = clone(itemCounts)
            task, craftCount = tryCraft(v, count, craftCount)
            if task then
                craftOptions[#craftOptions + 1] = craftCount
                break -- this is where to TODO that TODO
            end
        end
        return task, craftOptions[1]
    end

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
        end }, "TurtleReserve")
        local function getTurtle()
            return turt
        end
        ---@type PushTask
        local pushIngredientsTask = PushTask.new(r, "TurtlePush"):addSubtask(allocateTask)
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
        end }, "TurtleCraft"):addSubtask(pushIngredientsTask)
        local pullProductTask = PullTask.new(r, "TurtlePull"):fromSlot(getTurtle, 16, count):addSubtask(craftingTask)
        local freeTask = TaskLib.Task.new({ function()
            freeTurtle(turt)
        end }, "TurtleFree"):addSubtask(pullProductTask)

        ---@type TurtleCraftTask
        local callbackTask = freeTask
        if callback then
            callbackTask = TaskLib.Task.new({ callback }, "TurtleCallback"):addSubtask(freeTask)
        end
        callbackTask.rootTask = allocateTask

        return setmetatable(callbackTask, TurtleCraftTask)
    end

    ---@alias SlotMap {[1]:integer,[2]:integer}

    ---@class RegisteredMachine
    ---@field invs string[]
    ---@field mtype string
    ---@field ptype string?

    ---@alias MachineProcess fun(craft:integer,invs:{[1]:string,[2]:integer}[]):function

    ---@class RegisteredMachineType
    ---@field slots SlotMap[]
    ---@field output SlotMap
    ---@field ptype string?
    ---@field round (fun(n:integer):integer)? Round to most efficient processing interval
    ---@field process MachineProcess? Function ran alongside item i/o functions

    local function machineRoundType(mtype, n, produces)
        local round = registeredMachineTypes[mtype].round
        if round then
            return round(n)
        end
        return math.ceil(n / produces)
    end
    local function machineRound(machine, n, produces)
        local m = registeredMachines[machine]
        return machineRoundType(m.mtype, n, produces)
    end

    ---@param callback fun():string,integer,{[1]:string,[2]:integer}[]
    local function machineProcess(callback)
        return function()
            local t = table.pack(callback())
            local machine = t[1]
            local m = registeredMachines[machine]
            if not registeredMachineTypes[m.mtype].process then
                return
            end
            registeredMachineTypes[m.mtype].process(table.unpack(t, 2))
        end
    end

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
        local rmtype = rmachine.mtype
        for i, v in ipairs(registeredMachineTypes[rmtype].slots) do
            slotlut[i] = { rmachine.invs[v[1]], v[2] }
        end
        local outputInfo = registeredMachineTypes[rmtype].output
        local output = {
            rmachine.invs[outputInfo[1]], outputInfo[2]
        }
        return machine, slotlut, output
    end

    ---Free a machine that was previously in use
    ---@param machine string
    function this.craft.freeMachine(machine)
        local mtype = registeredMachines[machine].mtype
        local ptype = registeredMachines[machine].ptype
        freeMachines[ptype or mtype][machine] = true
        busyMachines[ptype or mtype][machine] = nil
        os.queueEvent("machine_freed")
    end

    ---Define a new type of machine
    ---@param mtype string
    ---@param slotmap SlotMap[] inv index, slot
    ---@param outputSlot SlotMap inv index, slot
    ---@param round (fun(n:integer):integer)? Round to most efficient processing interval
    ---@param process MachineProcess? Function ran alongside item i/o functions
    function this.craft.newMachineType(mtype, slotmap, outputSlot, round, process)
        registeredMachineTypes[mtype] = {
            slots = slotmap,
            output = outputSlot,
            round = round,
            process = process
        }
        busyMachines[mtype] = {}
        freeMachines[mtype] = {}
    end

    ---Add a machine with the type mtype, which handles crafting via ptype recipes
    ---@param mtype string
    ---@param ptype string
    ---@param slotmap SlotMap[]
    ---@param outputslot SlotMap
    ---@param process MachineProcess? Function ran alongside item i/o functions
    function this.craft.newAlternativeMachineType(mtype, ptype, slotmap, outputslot, process)
        registeredMachineTypes[mtype] = {
            slots = slotmap,
            output = outputslot,
            ptype = ptype,
            process = process
        }
    end

    ---Register a machine of a given type
    ---@param mtype string
    ---@param name string
    ---@param invs string[]?
    function this.craft.registerMachine(mtype, name, invs)
        invs = invs or { name }
        local ptype = registeredMachineTypes[mtype].ptype
        registeredMachines[name] = { invs = invs, mtype = mtype, ptype = ptype }
        freeMachines[ptype or mtype][name] = true
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
    ---@return MachineCraftTask
    ---@return integer craftCount
    function MachineCraftTaskFactory__index:build()
        local checkTime = 0.5
        local machine, slotlut, output
        local mtype = self.machine
        local doAllocate = self.machine
        local allocateTask
        local craftCount = machineRoundType(mtype, self.count, self.produces)
        allocateTask = TaskLib.Task.new({ function()
            machine, slotlut, output = this.craft.allocateMachine(self.machine)
        end }, "MachineAllocate:" .. mtype)
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
                        local reserve = self.r or this.reserve
                        local toInv, toSlot = table.unpack(slotlut[slot])
                        local toMove = icount * craftCount
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
            local reserve = self.r or this.reserve
            local fromInv, fromSlot = table.unpack(output)
            local moved = 0
            local toMove = self.produces * craftCount
            while moved < toMove do
                local movedIter = reserve:pullItems(fromInv, fromSlot, toMove - moved)
                moved = moved + movedIter
                if moved < toMove then
                    sleep(checkTime)
                end
            end
        end
        moveFuncs[#moveFuncs + 1] = machineProcess(function()
            return machine, craftCount, slotlut
        end)
        local moveTask = TaskLib.Task.new(moveFuncs, "MachineMove:" .. mtype)
        if doAllocate then
            moveTask:addSubtask(allocateTask)
        end
        local freeTask = TaskLib.Task.new({ function()
            this.craft.freeMachine(machine)
        end }, "MachineFree:" .. mtype):addSubtask(moveTask)

        ---@diagnostic disable-next-line: inject-field
        freeTask.rootTask = allocateTask
        return setmetatable(freeTask, MachineCraftTask), craftCount
    end

    local function registerFurnaces()
        this.craft.newMachineType("furnace", { { 1, 1 } }, { 1, 3 }, function(n)
            return math.ceil(n / 8) * 8
        end, function(count, invs)
            local moved = 0
            local toMove = math.ceil(count / 8)
            local coal = ItemDescriptor.fromName("minecraft:coal")
            local inv = invs[1][1]
            while true do
                local m = this.reserve:pushItems(inv, coal, toMove - moved, 2)
                moved = moved + m
                if moved == toMove then
                    break
                end
            end
        end)
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
        -- this.scheduler.queueTask(TaskLib.Task.new({ function()
        --     while true do
        --         debugOverlay()
        --         sleep(0.05)
        --     end
        -- end }):setPriority(2))
        this.scheduler.run()
        wmodem.closeAll()
    end

    return this
end

return lib
