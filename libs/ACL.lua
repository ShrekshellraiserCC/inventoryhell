-- Abstract Crafting Lib?
-- Shrek Inventory Lib
-- Simple Storage Lib
local lib            = {}
local ItemDescriptor = require("libs.ItemDescriptor")
local coordLib       = require("libs.Coordinates")
local shrexpect      = require("libs.shrexpect")
local sset           = require("libs.sset")
local Coordinates    = require("libs.Coordinates")

local TaskLib        = require("libs.STL")


lib.Item = require("libs.ItemDescriptor")
local VirtualInv = require("libs.VirtualInv")
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
lib.clone = clone

---Wrap a list of inventories
---@param invList string[]
---@param wmodem Modem?
---@param tracker ScanTracker?
---@param provider ssd.libs.slogger.LogProvider
---@param registry ssd.libs.registry
---@return ACL
function lib.wrap(invList, wmodem, tracker, provider, registry)
    -- Called 'this' to avoid scope conflictions with 'self'
    ---@class ACL
    local this = {}
    this.scheduler = TaskLib.Scheduler()

    for k, v in ipairs(invList) do
        registry.mark_used(v, "Storage")
    end
    local logger = provider.logger("ACL")
    local invReserve = VirtualInv.new(invList, tracker, provider)
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
        local tid = os.startTimer(0.5)
        ---@type table<string,boolean>
        local foundTurtles = {}
        while true do
            local e, side, channel, replyChannel, message = os.pullEvent()
            if e == "modem_message" then
                if type(message) == "table" and message[1] == "NAME" then
                    foundTurtles[message[2]] = true
                    os.cancelTimer(tid)
                    tid = os.startTimer(0.5)
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
        logger.finfo("Allocated turtle %s", turt)
        freeTurtles[turt] = nil
        busyTurtles[turt] = true
        return turt
    end

    local function freeTurtle(turt)
        freeTurtles[turt] = true
        busyTurtles[turt] = nil
        os.queueEvent("turtle_freed")
        logger.finfo("Freed turtle %s", turt)
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

    ---@param from InventoryCompatible|InventoryProvider
    ---@param slotA integer
    ---@param slotB integer
    ---@param limit integer?
    function PullTask__index:fromRange(from, slotA, slotB, limit)
        for i = slotA, slotB do
            local f = function()
                local r = self.reserve or invReserve
                if type(from) == "function" then
                    from = from()
                end
                return r:pullItems(from, i)
            end
            self.funcs[#self.funcs + 1] = f
        end
        return self
    end

    ---@param r Reserve?
    ---@param name string?
    ---@return PullTask
    function PullTask.new(r, name)
        local self = setmetatable(TaskLib.Task.new({}, name), PullTask)
        self.reserve = r
        return self --[[@as PullTask]]
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
    ---@type table<integer,string>
    local machineTypeLut = {}
    local lastMachineTypeID = 1
    ---@type table<string,RegisteredMachine>
    local registeredMachines = {}

    ---@class RegisteredRecipe
    ---@field id integer
    ---@field type "grid"|string machine type
    ---@field items ItemDescriptor[]
    ---@field recipe table<integer,integer|pair>
    ---@field produces integer
    ---@field product ItemCoordinate

    machineTypeLut[1] = "grid"
    registeredMachineTypes.grid = {
        id = 1,
        output = { 0, 0 },
        slots = {},
        mtype = "grid"
    }
    local lastRecipeID = 0
    ---@type table<ItemCoordinate,RegisteredRecipe[]>
    local registeredRecipes = {}
    ---@type RegisteredRecipe[]
    local recipesByID = {}

    this.craft = {}
    ---@type string[]
    local IDCacheList = {}
    ---@type table<string,integer>
    local IDCacheLUT = {}
    ---@param id ItemDescriptor|string
    ---@return integer
    local function cacheID(id)
        if type(id) == "table" then
            id = id:serialize()
        end
        if IDCacheLUT[id] then
            return IDCacheLUT[id]
        end
        id = id --[[@as string]] -- this is dumb
        local idx = #IDCacheList + 1
        IDCacheLUT[id] = idx
        IDCacheList[idx] = id
        return idx
    end
    ---@param m RegisteredMachine
    ---@return string
    local function serializeMachine(m)
        local mid = registeredMachineTypes[m.mtype].id
        local pid = m.ptype and registeredMachineTypes[m.ptype].id
        local s = {}
        s[#s + 1] = "M"
        s[#s + 1] = mid
        s[#s + 1] = "P"
        s[#s + 1] = pid or nil
        s[#s + 1] = "N"
        s[#s + 1] = "'"
        s[#s + 1] = m.name
        s[#s + 1] = "'"
        s[#s + 1] = "I"
        s[#s + 1] = #m.invs
        s[#s + 1] = "="
        for i, v in ipairs(m.invs) do
            s[#s + 1] = v
            s[#s + 1] = ","
        end
        s[#s] = ";"
        return table.concat(s, "")
    end
    ---@param r RegisteredRecipe
    local function serializeRecipe(r)
        local s = {}
        s[#s + 1] = "R"
        s[#s + 1] = cacheID(ItemDescriptor.fromCoord(r.product))
        s[#s + 1] = "T"
        s[#s + 1] = registeredMachineTypes[r.type].id
        s[#s + 1] = "P"
        s[#s + 1] = r.produces
        s[#s + 1] = "I"
        s[#s + 1] = #r.items
        s[#s + 1] = "="
        for i, v in ipairs(r.items) do
            s[#s + 1] = cacheID(v)
            s[#s + 1] = ","
        end
        if s[#s] == "," then
            s[#s] = ";" -- remove trailing comma
        elseif s[#s] == "=" then
            s[#s + 1] = ";"
        end
        local recipeSize = 0
        for i in pairs(r.recipe) do
            recipeSize = math.max(recipeSize, i)
        end
        s[#s + 1] = "r"
        s[#s + 1] = recipeSize
        s[#s + 1] = ":"
        for i = 1, recipeSize do
            local v = r.recipe[i]
            if type(v) == "number" then
                s[#s + 1] = v
            elseif type(v) == "table" then
                s[#s + 1] = "{"
                s[#s + 1] = v[1]
                s[#s + 1] = ","
                s[#s + 1] = v[2]
                s[#s + 1] = "}"
            end
            s[#s + 1] = ","
        end
        if recipeSize == 0 then
            s[#s + 1] = ";"
        end
        s[#s] = ";"
        return table.concat(s, "")
    end
    ---@param t RegisteredMachineType
    ---@return string
    local function serializeMachineType(t)
        local s = {}
        s[#s + 1] = "T"
        s[#s + 1] = t.mtype
        s[#s + 1] = ";I"
        s[#s + 1] = t.id
        s[#s + 1] = "O{"
        s[#s + 1] = t.output[1]
        s[#s + 1] = ","
        s[#s + 1] = t.output[2]
        s[#s + 1] = "}"
        s[#s + 1] = "P"
        s[#s + 1] = t.ptype
        s[#s + 1] = ";"
        local n = #t.slots
        s[#s + 1] = "N"
        s[#s + 1] = n
        s[#s + 1] = ":"
        for i = 1, n do
            local v = t.slots[i]
            s[#s + 1] = "{"
            s[#s + 1] = v[1]
            s[#s + 1] = ","
            s[#s + 1] = v[2]
            s[#s + 1] = "}"
            s[#s + 1] = ","
        end
        s[#s] = ";"
        return table.concat(s, "")
    end
    ---@param s string
    ---@return RegisteredMachineType
    local function unserializeMachineType(s)
        local t = {}
        local p = "T([%a_%d]+);I(%d+)O{(%d+),(%d*)}P([%a_%d]*);N(%d+)[:;]"
        local start, finish = s:find(p)
        local mtype, id, out1, out2, ptype, slots = s:match(p)
        t.mtype = mtype
        t.output = { tonumber(out1), tonumber(out2) }
        t.ptype = ptype
        t.id = tonumber(id)
        t.slots = {}
        local idx = finish + 1
        for i = 1, tonumber(slots) do
            local p = "{(%d+),(%d+)}([,;])"
            local _, last = s:find(p, idx)
            local n1, n2, e = s:match(p, idx)
            idx = last + 1
            t.slots[i] = { tonumber(n1), tonumber(n2) }
        end
        return t
    end


    ---@param s string
    ---@param idx integer
    ---@return integer
    ---@return integer|pair?
    ---@return string
    local function parseRecipePart(s, idx)
        if s:sub(idx, idx) == "{" then
            local p = "{(%d+),(%d+)}([,;])"
            local _, last = s:find(p, idx)
            local n1, n2, e = s:match(p, idx)
            return last + 1, { tonumber(n1), tonumber(n2) }, e
        elseif s:sub(idx, idx):match("[;,]") then
            return idx + 1, nil, ","
        end
        local p = "([%d]+)([,;])"
        local _, last = s:find(p, idx)
        local n, e = s:match(p, idx)
        return last + 1, tonumber(n), e
    end
    ---@param s string
    ---@return RegisteredRecipe
    local function unserializeRecipe(s)
        local firstPattern = "R(%d+)T(%d+)P(%d+)I(%d+)="
        local start, finish = s:find(firstPattern)
        if not finish then
            error(("Invalid pattern: %s"):format(s))
        end
        local productID, rtype, produces, itemCount = s:match(firstPattern)
        local idx = finish + 1
        local r = {
            items = {},
            produces = tonumber(produces),
            product = coordLib.ItemCoordinate(IDCacheList[tonumber(productID)]:sub(2)),
            recipe = {},
            type = machineTypeLut[tonumber(rtype)]
        }
        for i = 1, itemCount do
            ---@type integer|pair?
            local itemID = 0
            idx, itemID = parseRecipePart(s, idx)
            r.items[i] = ItemDescriptor.unserialize(IDCacheList[itemID])
        end
        local recipeCount = s:match("(%d+):", idx)
        idx = idx + #recipeCount + 2
        recipeCount = tonumber(recipeCount)
        for i = 1, recipeCount do
            idx, r.recipe[i] = parseRecipePart(s, idx)
        end
        return r
    end
    ---@param s string
    ---@return RegisteredMachine
    local function unserializeMachine(s)
        local p = "M(%d+)P(%d*)N'([%a_%d:]+)'I(%d+)="
        local start, finish = s:find(p)
        local machineID, pmachineID, name, inventoryCount = s:match(p)
        ---@type RegisteredMachine
        local m = {
            invs = {},
            mtype = machineTypeLut[tonumber(machineID)],
            ptype = pmachineID ~= "" and machineTypeLut[tonumber(pmachineID)] or nil,
            name = name
        }
        local idx = finish + 1
        for i = 1, inventoryCount do
            local inv = s:match("([%a_%d:]+)[,;]", idx)
            idx = idx + #inv + 1
            m.invs[i] = inv
        end
        return m
    end
    local function saveFile(fn, s)
        local path = fs.combine(sset.get(sset.recipeCacheDir), fn)
        local t = textutils.serialize(s)
        local f = assert(fs.open(path, "w"))
        f.write(t)
        f.close()
    end
    local function readFromFile(fn)
        local path = fs.combine(sset.get(sset.recipeCacheDir), fn)
        local f = assert(fs.open(path, "r"))
        local s = f.readAll() --[[@as string]] -- does this EVEN return nil?
        f.close()
        return textutils.unserialise(s)
    end
    local recipeFN = "recipes.txt"
    local machinesFN = "machines.txt"
    local machineTypesFN = "machine_types.txt"
    local itemCacheFN = "item_cache.txt"
    local function saveRecipes()
        local seenRecipes = {}
        local sreps = {}
        for ic, recipes in pairs(registeredRecipes) do
            for _, recipe in ipairs(recipes) do
                local sr = serializeRecipe(recipe)
                if not seenRecipes[sr] then
                    sreps[#sreps + 1] = sr -- remove duplicates
                    seenRecipes[sr] = true
                end
            end
        end
        local smachines = {}
        for n, m in pairs(registeredMachines) do
            local sm = serializeMachine(m)
            smachines[#smachines + 1] = sm
        end
        local stypes = {}
        for n, mt in pairs(registeredMachineTypes) do
            local sm = serializeMachineType(mt)
            stypes[#stypes + 1] = sm
        end
        saveFile(recipeFN, sreps)
        saveFile(machinesFN, smachines)
        saveFile(machineTypesFN, stypes)
        saveFile(itemCacheFN, IDCacheList)
        logger.info("Saved recipes.")
    end
    this.craft.saveRecipes = saveRecipes

    local function loadRecipes()
        if not (fs.exists(recipeFN) and fs.exists(itemCacheFN)
                and fs.exists(machinesFN) and fs.exists(machineTypesFN)) then
            return
        end
        local sreps = readFromFile(recipeFN) --[[@as string[] ]]
        IDCacheList = readFromFile(itemCacheFN) --[[@as string[] ]]
        IDCacheLUT = {}
        for i, v in ipairs(IDCacheList) do
            IDCacheLUT[v] = i
        end
        local smachines = readFromFile(machinesFN) --[[@as string[] ]]
        local stypes = readFromFile(machineTypesFN) --[[@as string[] ]]
        registeredMachineTypes = {}
        machineTypeLut = {}
        lastMachineTypeID = 1
        freeMachines = {}
        busyMachines = {}
        for i, v in ipairs(stypes) do
            local st = unserializeMachineType(v)
            lastMachineTypeID = math.max(lastMachineTypeID, st.id)
            machineTypeLut[st.id] = st.mtype
            registeredMachineTypes[st.mtype] = {
                id = st.id,
                mtype = st.mtype,
                output = st.output,
                slots = st.slots
            }
            if st.ptype ~= "" then
                this.craft.newAlternativeMachineType(st.mtype, st.ptype, st.slots, st.output)
            else
                this.craft.newMachineType(st.mtype, st.slots, st.output)
            end
        end
        registeredMachines = {}
        for i, v in ipairs(smachines) do
            local m = unserializeMachine(v)
            this.craft.registerMachine(m.mtype, m.name, m.invs)
        end
        registeredRecipes = {}
        recipesByID = {}
        lastRecipeID = 0
        for i, v in ipairs(sreps) do
            local r = unserializeRecipe(v)
            this.craft.registerRecipe(r.type, r.items, r.recipe, r.product, r.produces)
        end
    end
    this.craft.loadRecipes = loadRecipes

    ---Register a recipe
    ---@param mtype string
    ---@param items ItemDescriptor[]
    ---@param recipe integer[]|pair[]
    ---@param product ItemCoordinate
    ---@param produces integer
    ---@param _id integer?
    ---@return integer recipeID
    function this.craft.registerRecipe(mtype, items, recipe, product, produces, _id)
        local id
        if _id then
            id = _id
        else
            lastRecipeID = lastRecipeID + 1
            id = lastRecipeID
        end
        ---@type RegisteredRecipe
        local r = recipesByID[id] or {}
        r.id = id
        r.type = mtype
        r.items = items
        r.recipe = recipe
        r.product = product
        r.produces = produces
        recipesByID[id] = r
        registeredRecipes[product] = registeredRecipes[product] or {}
        if not _id then
            table.insert(registeredRecipes[product], r)
        end
        return id
    end

    ---@param id integer
    function this.craft.deleteRecipe(id)
        local recipe = recipesByID[id]
        if not recipe then return false end
        recipesByID[id] = nil
        local recipes = registeredRecipes[recipe.product]
        for i, v in ipairs(recipes) do
            if v == recipe then
                table.remove(recipes, i)
                if #recipes == 0 then
                    registeredRecipes[recipe.product] = nil
                end
                return true
            end
        end
    end

    ---@param id integer
    ---@return RegisteredRecipe?
    function this.craft.getRecipeInfo(id)
        return recipesByID[id]
    end

    ---@param mtype string
    ---@return RegisteredMachineType?
    function this.craft.getMachineTypeInfo(mtype)
        return registeredMachineTypes[mtype]
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
        for _, item in pairs(recipe.recipe) do
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
    ---@param alternative integer?
    ---@return MachineCraftTask|TurtleCraftTask?
    ---@return table<string,integer> ItemDescriptor string, integer
    function this.craft.craft(item, count, itemCounts, alternative)
        shrexpect({ "string|ItemDescriptor", "number", "table?", "number?" },
            { item, count, itemCounts, alternative })
        itemCounts = itemCounts or {}
        alternative = alternative or 1
        if type(item) == "table" then
            item = item:toCoord() or item
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
                if #craftOptions == alternative then
                    break
                end
            end
        end
        return task, craftOptions[(alternative - 1) % #craftOptions + 1]
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
        local pushIngredientsTask = PushTask.new(r, "TurtlePush"):addSubtask(allocateTask) --[[@as PushTask]]
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
        local pullProductTask = PullTask.new(r, "TurtlePull"):fromRange(getTurtle, 1, 16):addSubtask(craftingTask)
        local freeTask = TaskLib.Task.new({ function()
            freeTurtle(turt)
        end }, "TurtleFree"):addSubtask(pullProductTask)

        ---@type TurtleCraftTask
        local callbackTask = freeTask --[[@as TurtleCraftTask]] -- I LOVE LLS
        if callback then
            callbackTask = TaskLib.Task.new({ callback }, "TurtleCallback"):addSubtask(freeTask) --[[@as TurtleCraftTask]]
        end
        callbackTask.rootTask = allocateTask

        return setmetatable(callbackTask, TurtleCraftTask)
    end

    ---@alias pair {[1]:integer,[2]:integer}
    ---@alias SlotMap pair

    ---@class RegisteredMachine
    ---@field invs string[]
    ---@field mtype string
    ---@field ptype string?
    ---@field name string

    ---@alias MachineProcess fun(craft:integer,invs:{[1]:string,[2]:integer}[]):function

    ---@class RegisteredMachineType
    ---@field slots SlotMap[]
    ---@field id integer
    ---@field output {[1]:integer,[2]:integer,[3]:integer?}
    ---@field mtype string
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
    ---@return SlotMap[]
    ---@return {[1]:string,[2]:integer,[3]:integer?}
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
        logger.finfo("Allocated Machine %s %s", mtype, machine)
        return machine, slotlut, output
    end

    ---Free a machine that was previously in use
    ---@param machine string
    function this.craft.freeMachine(machine)
        local mtype = registeredMachines[machine].mtype
        local ptype = registeredMachines[machine].ptype
        freeMachines[ptype or mtype][machine] = true
        busyMachines[ptype or mtype][machine] = nil
        logger.finfo("Freed Machine %s %s", mtype, machine)
        os.queueEvent("machine_freed")
    end

    ---Define a new type of machine
    ---@param mtype string
    ---@param slotmap SlotMap[] inv index, slot
    ---@param outputSlot {[1]:integer,[2]:integer,[3]:integer?} inv index, slot
    ---@param round (fun(n:integer):integer)? Round to most efficient processing interval
    ---@param process MachineProcess? Function ran alongside item i/o functions
    function this.craft.newMachineType(mtype, slotmap, outputSlot, round, process)
        shrexpect({ "string", "table", "table", "function?", "function?" },
            { mtype, slotmap, outputSlot, round, process })
        local idx
        if registeredMachineTypes[mtype] then
            idx = registeredMachineTypes[mtype].id
        else
            lastMachineTypeID = lastMachineTypeID + 1
            idx = lastMachineTypeID
        end
        machineTypeLut[idx] = mtype
        registeredMachineTypes[mtype] = {
            slots = slotmap,
            output = outputSlot,
            round = round,
            process = process,
            id = idx,
            mtype = mtype,
        }
        busyMachines[mtype] = busyMachines[mtype] or {}
        freeMachines[mtype] = freeMachines[mtype] or {}
    end

    ---Add a machine with the type mtype, which handles crafting via ptype recipes
    ---@param mtype string
    ---@param ptype string
    ---@param slotmap SlotMap[]
    ---@param outputslot {[1]:integer,[2]:integer,[3]:integer?}
    ---@param process MachineProcess? Function ran alongside item i/o functions
    function this.craft.newAlternativeMachineType(mtype, ptype, slotmap, outputslot, process)
        shrexpect({ "string", "string", "integer[][]", "integer[]", "function?" },
            { mtype, ptype, slotmap, outputslot, process })
        local idx = lastMachineTypeID
        if machineTypeLut[mtype] then
            idx = machineTypeLut[mtype]
        else
            lastMachineTypeID = lastMachineTypeID + 1
            idx = lastMachineTypeID
        end
        if not registeredMachineTypes[mtype] then
            machineTypeLut[idx] = mtype
            registeredMachineTypes[mtype] = {
                slots = slotmap,
                output = outputslot,
                ptype = ptype,
                process = process,
                id = idx,
                mtype = mtype
            }
        end
    end

    ---@param machine RegisteredMachine
    local function machineRegisterTask(machine)
        local f = {}
        local machineValid = true
        for i, v in ipairs(machine.invs) do
            f[i] = function()
                local ok, l = pcall(peripheral.call, v, "list")
                if not ok then
                    logger.fwarn("Machine '%s' has non-inventory '%s' assigned.", machine.name, v)
                    machineValid = false
                    return
                end
                for slot in pairs(l) do
                    this.reserve:pullItems(v, slot)
                end
            end
        end
        local clearTask = TaskLib.Task.new(f, "MachineClean:" .. machine.name)
        local t = TaskLib.Task.new({
            function()
                if machineValid then
                    this.craft.freeMachine(machine.name)
                end
            end
        }, "MachineRegister:" .. machine.name)
        clearTask:addSubtask(t)
        this.scheduler.queueTask(clearTask)
    end

    ---Register a machine of a given type
    ---@param mtype string
    ---@param name string
    ---@param invs string[]?
    function this.craft.registerMachine(mtype, name, invs)
        shrexpect({ "string", "string", "string[]?" }, { mtype, name, invs })
        if registeredMachines[name] then
            if busyMachines[mtype][name] then
                logger.ferror("Cannot edit the machine '%s' while in use.", name)
                return false
            end
            freeMachines[mtype][name] = nil
        end
        invs = invs or { name }
        local label = "Machine@" .. name
        for i, v in ipairs(invs) do
            registry.mark_used(v, label)
            invReserve:removeInventory(v)
        end
        local ptype = registeredMachineTypes[mtype].ptype
        local m = { invs = invs, mtype = mtype, ptype = ptype, name = name }
        registeredMachines[name] = m
        machineRegisterTask(m)
    end

    ---@param name string
    function this.craft.deleteMachine(name)
        shrexpect({ "string" }, { name })
        local machine = registeredMachines[name]
        if not machine then return false end
        if busyMachines[machine.mtype][name] then
            return false -- machine is in use.
        end
        for i, v in ipairs(machine.invs) do
            registry.mark_free(v)
        end
        freeMachines[machine.mtype][name] = nil
        registeredMachines[name] = nil
        return true
    end

    ---@param mtype string
    function this.craft.deleteMachineType(mtype)
        error("TODO") -- TODO
    end

    ---@return RegisteredMachineType[]
    function this.craft.listMachineTypes()
        local listing = {}
        for k, v in pairs(registeredMachineTypes) do
            listing[#listing + 1] = v
        end
        return listing
    end

    ---@param mtype string?
    ---@return RegisteredMachine[]
    function this.craft.listMachines(mtype)
        local l = {}
        local i = 1
        for k, v in pairs(registeredMachines) do
            if mtype == nil or v.mtype == mtype then
                l[i] = v
                i = i + 1
            end
        end
        return l
    end

    ---@class MachineCraftTaskFactory
    ---@field machine string?
    ---@field slotLookup InventoryCoordinate[]
    ---@field r Reserve?
    ---@field produces integer
    ---@field recipe integer[]|SlotMap[]
    ---@field count integer
    local MachineCraftTaskFactory__index = setmetatable({}, QueableTask) --[[@as MachineCraftTaskFactory]]
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
    ---@param recipe integer[]|pair[] {item,count}
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
        if self.machine == nil then
            error("Cannot build MachineCraftTaskFactory without a machine target.", 1)
        end
        local checkTime = 0.5
        local machine, slotlut, output
        local mtype = self.machine
        local craftCount = machineRoundType(mtype, self.count, self.produces)
        local allocateTask = TaskLib.Task.new({ function()
            machine, slotlut, output = this.craft.allocateMachine(self.machine)
        end }, "MachineAllocate:" .. mtype)
        local cleanTask = TaskLib.Task.new({
            function()
                local reserve = self.r or this.reserve
                -- clear input slots
                local invs = registeredMachines[machine].invs
                for _, info in pairs(slotlut) do
                    reserve:pullItems(invs[info[1]], info[2])
                end
            end,
            function()
                local reserve = self.r or this.reserve
                -- clear output slots
                local inv = output[1]
                local ok, list = pcall(peripheral.call, inv, "list")
                for i = output[2], output[3] or output[2] do
                    if ok and list[i] or not ok then
                        reserve:pullItems(inv, i)
                    end
                end
            end
        }, "MachineClean:" .. mtype)
        cleanTask:addSubtask(allocateTask)
        -- Clear the machine for safety
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
        moveTask:addSubtask(cleanTask)
        local freeTask = TaskLib.Task.new({ function()
            this.craft.freeMachine(machine)
        end }, "MachineFree:" .. mtype):addSubtask(moveTask)

        ---@diagnostic disable-next-line: inject-field
        freeTask.rootTask = allocateTask
        return setmetatable(freeTask, MachineCraftTask) --[[@as MachineCraftTask]], craftCount
    end

    local recipeParsers = {}
    ---@param parse fun(input:table)
    function this.craft.registerJSONParser(type, parse)
        recipeParsers[type] = parse
    end

    local function parseShaped(input)
        local key = {}
        local items = {}
        for k, v in pairs(input.key) do
            items[#items + 1] = ItemDescriptor.parseJSON(v)
            key[k] = #items
        end
        local recipe = {}
        for row, s in ipairs(input.pattern) do
            for col = 1, #s do
                local idx = (row - 1) * 3 + col
                local ch = s:sub(col, col)
                if ch ~= " " then
                    recipe[idx] = key[ch]
                end
            end
        end
        local product = coordLib.ItemCoordinate(input.result.item)
        local produces = input.result.count or 1
        this.craft.registerRecipe("grid", items, recipe, product, produces)
    end
    this.craft.registerJSONParser("minecraft:crafting_shaped", parseShaped)

    local function parseShapeless(input)
        local items = {}
        local seenItems = {}
        local recipe = {}
        for i, v in ipairs(input.ingredients) do
            local id = ItemDescriptor.parseJSON(v)
            local ids = id:serialize()
            if not seenItems[ids] then
                items[#items + 1] = id
                seenItems[ids] = #items
            end
            recipe[i] = seenItems[ids]
        end
        local product = coordLib.ItemCoordinate(input.result.item)
        local produces = input.result.count or 1
        this.craft.registerRecipe("grid", items, recipe, product, produces)
    end
    this.craft.registerJSONParser("minecraft:crafting_shapeless", parseShapeless)

    ---@param s string
    function this.craft.importJSON(s)
        local json = textutils.unserialiseJSON(s)
        if not json then return end
        local parser = recipeParsers[json.type]
        if not parser then return end
        parser(json)
    end

    this.craft.loadRecipes()
    local function loadPlugins(dir)
        local list = fs.list(dir)
        for i, v in ipairs(list) do
            logger.finfo("Loading Plugin: %s", v)
            loadfile(fs.combine(dir, v), "t", _ENV)()(this)
        end
    end
    loadPlugins(sset.getInstalledPath "cplugins")

    ---@class RecipeInfo
    ---@field name string
    ---@field displayName string?
    ---@field coord ItemCoordinate
    ---@field type string
    ---@field id integer

    ---@return RecipeInfo[]
    function this.craft.listRecipes()
        ---@type RecipeInfo[]
        local r = {}
        for i, v in pairs(registeredRecipes) do
            local name, nbt = coordLib.splitItemCoordinate(i)
            local displayName = this.reserve:getDisplayName(name) or name
            for _, recipe in ipairs(v) do
                r[#r + 1] = {
                    name = name,
                    coord = i,
                    type = recipe.type,
                    displayName = displayName,
                    id = recipe.id
                }
            end
        end
        return r
    end

    -- local function debugParseJSONs()
    --     local list = fs.list("disk/recipes/")
    --     for i, v in ipairs(list) do
    --         local f = assert(fs.open(fs.combine("disk/recipes/", v), "r"))
    --         local s = f.readAll()
    --         f.close()
    --         this.craft.importJSON(s)
    --     end
    -- end
    -- debugParseJSONs()

    function this.list()
        local listing = this.reserve:list()
        local lookup = {}
        for i, v in ipairs(listing) do
            local coord = Coordinates.ItemCoordinate(v.name, v.nbt)
            lookup[coord] = v
        end
        for k, v in pairs(registeredRecipes) do
            if lookup[k] then
                lookup[k].craftable = true
            else
                local name, nbt = Coordinates.splitItemCoordinate(k)
                listing[#listing + 1] = {
                    name = name,
                    nbt = nbt,
                    count = 0,
                    craftable = true,
                    displayName = this.reserve:getDisplayName(name) or name,
                    maxCount = 64
                }
            end
        end
        return listing
    end

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
