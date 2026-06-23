local acl            = require("libs.ACL")
local ID             = require("libs.ItemDescriptor")
local stl            = require("libs.STL")
local sset           = require("libs.sset")
local shrekui        = require("libs.shrekui")
local VirtualInv     = require("libs.VirtualInv")
local ItemDescriptor = require("libs.ItemDescriptor")
local registry       = require("libs.registry")
local Coordinates    = require("libs.Coordinates")
local slogger        = require("libs.slogger")
local network        = require("libs.network")

local protocol       = require("libs.clientlib").protocol
local hostname       = "HOST_TEST"

local id             = os.getComputerID()
local function broadcast(m)
    network.broadcast(m)
end

local chestList = {}
local patternAllowList = sset.get(sset.inventoryAllowPatterns)
for i, v in ipairs({ peripheral.find("inventory") }) do
    local name = peripheral.getName(v)
    local good = false
    for _, pattern in ipairs(patternAllowList) do
        if name:match(pattern) then
            good = true
            break
        end
    end
    if good then
        chestList[#chestList + 1] = name
    end
end


local args = { ... }
local beingRequired = #args == 2 and type(package.loaded[args[1]]) == "table" and not next(package.loaded[args[1]])

local w, h = term.getSize()
local wenv = {
    fstr = "Initial Setup..."
}
shrekui.load_global_theme(sset.get(sset.theme))
local win = window.create(term.current(), 1, 1, w, h)


local screenArgs = {
    type = "Screen",
    content = {
        {
            type = "Text",
            h = 1,
            class = "heading",
            text = "ShrekStorageDrive INDEV"
        },
        {
            type = "Log",
            y = 2,
            h = "h-2",
            class = "log"
        },
        {
            type = "Text",
            h = 1,
            y = "h",
            class = "heading",
            text = "$fstr$",
            horizontal_alignment = "left"
        }
    }
}
local screen = shrekui.load_screen(screenArgs, wenv)
local log = screen:get_widget_by_class("log", 1) --[[@as shrekui.Log]]



local function getTenths(n)
    local ten = n * 10
    return ten - math.floor(ten)
end
---Draw a progress bar
---@param w integer
---@param p number [0,1] percentage
local function progressBar(w, p)
    if p ~= p then p = 0 end
    w = w - 2
    local s = ("\127"):rep(math.floor(w * p))
    if p < 1 and getTenths(p) > 0.5 then
        s = s .. "\149"
    end
    s = s .. (" "):rep(w - #s)
    return s
end

local logProvider = slogger.new("HOST", "hostlog.txt")
logProvider.addTarget(function(s)
    log:log(s)
end)
local function main(standalone)
    local logger = logProvider.logger("Host")
    -- Central host process for the storage system
    ---@alias Modem ccTweaked.peripherals.Modem
    local modem = peripheral.find("modem", function(name, wrapped)
        return not wrapped.isWireless()
    end) --[[@as ccTweaked.peripherals.Modem]]
    local modemName = peripheral.getName(modem)
    network.open(modemName)
    rednet.host(protocol, hostname) -- TODO change this with custom impl
    logger.finfo("Opened modem %s.", modemName)

    local t0 = os.epoch("utc")
    local tracker = VirtualInv.defaultTracker()
    ---@type ACL
    local inv

    local funcs = {
        function()
            inv = acl.wrap(chestList, modem, tracker, logProvider, registry)
        end,
        function()
            while true do
                local t1 = os.epoch("utc")
                local invScanning = tracker.totalInvs ~= tracker.invsScanned
                local total = tracker.totalSlots
                local scanned = tracker.slotsScanned
                local stage = "2/3"
                if tracker.totalInvs ~= tracker.invsScanned then
                    -- We are scanning inventories
                    stage = "1/3"
                    total = tracker.totalInvs
                    scanned = tracker.invsScanned
                elseif tracker.totalSlots == 0 then
                    -- We haven't started processing yet
                    stage = "0/3"
                elseif tracker.totalSlots == tracker.slotsScanned then
                    -- We are currently defragging!
                    stage = "3/3"
                    total = tracker.totalItems
                    scanned = tracker.itemsDefragged
                end
                local remaining = (total - scanned)
                if total == 0 then total = 1 end
                local percentage = scanned / total
                local eta = math.ceil((t1 - t0) * (1 / (percentage) - 1) / 1000)
                local etaStr = ("%s:%3ss"):format(stage, eta)
                if eta > 1000 then
                    etaStr = ("%s:---s"):format(stage)
                end
                wenv.fstr = etaStr .. progressBar(w - #etaStr, percentage)
                -- ui.cursor(footerWin, 1, 1)
                -- footerWin.write(etaStr)
                -- ui.progressBar(footerWin, sw + 2, 1, w - sw + 1, percentage)
                broadcast({
                    type = "scanProgress",
                    stage = stage,
                    total = total,
                    scanned = scanned,
                    eta = eta,
                    etaStr = etaStr
                })
                sleep(0)
            end
        end }
    if standalone then
        table.insert(funcs, 1, function()
            screen:run(win)
        end)
    end
    parallel.waitForAny(table.unpack(funcs))
    wenv.fstr = "Initialization Complete"
    local initTime = os.epoch("utc") - t0
    local info = inv.reserve:getSlotInfo()
    log:flog("SSD initialized %d used (of %d total) slots in %.2f seconds", info.used, info.total, initTime / 1000)


    local messageHandlers = {}
    local hapi = {}

    local function registerMessageHandler(type, handle)
        messageHandlers[type] = handle
    end
    hapi.registerMessageHandler = registerMessageHandler
    ---@param type string
    ---@param text string
    ---@param destination integer?
    function hapi.notification(type, text, destination)
        destination = destination or "*"
        network.send(destination, {
            type = "notification",
            ntype = type,
            text = text
        })
    end

    inv.scheduler.setErrorCallback(function(name, id)
        logger.trace("setErrorCallback")
        hapi.notification("Thread Error", ("Thread (%s) on host errored! Check host log for details."):format(name))
    end)

    registerMessageHandler("ping", function(msg)
        return {
            id = id,
        }
    end)
    registerMessageHandler("list", function(msg)
        return inv.list()
    end)
    registerMessageHandler("getFragMap", function(msg)
        return inv.reserve:getFragMap()
    end)
    registerMessageHandler("pushItems", function(msg)
        return inv.reserve:pushItems(
            msg.to,
            ID.unserialize(msg.item),
            msg.limit,
            msg.toSlot)
    end)
    registerMessageHandler("pullItems", function(msg)
        return inv.reserve:pullItems(msg.from, msg.slot, msg.limit)
    end)
    registerMessageHandler("rebootAll", function(msg)
        os.reboot()
    end)
    registerMessageHandler("listThreads", function(msg)
        return inv.scheduler.list()
    end)
    registerMessageHandler("removeInventory", function(msg)
        inv.reserve:removeInventory(msg.inv)
        registry.mark_used(msg.inv, msg.label)
        return true
    end)
    registerMessageHandler("listRecipes", function(msg)
        return inv.craft.listRecipes()
    end)
    registerMessageHandler("importJSON", function(msg)
        inv.craft.importJSON(msg.json)
        return true
    end)
    registerMessageHandler("saveRecipes", function()
        inv.craft.saveRecipes()
        return true
    end)
    registerMessageHandler("listMachineTypes", function()
        return inv.craft.listMachineTypes()
    end)
    registerMessageHandler("setMachineType", function(msg)
        if msg.ptype then
            inv.craft.newAlternativeMachineType(msg.mtype, msg.ptype, msg.slotmap, msg.outputmap)
        else
            inv.craft.newMachineType(msg.mtype, msg.slotmap, msg.outputmap)
        end
        inv.craft.saveRecipes()
        return true
    end)
    registerMessageHandler("deleteMachineType", function(msg)
        inv.craft.deleteMachineType(msg.mtype)
        inv.craft.saveRecipes()
    end)
    registerMessageHandler("listMachines", function(msg)
        return inv.craft.listMachines(msg.mtype)
    end)
    registerMessageHandler("setMachine", function(msg)
        inv.craft.registerMachine(msg.mtype, msg.name, msg.invs)
        inv.craft.saveRecipes()
    end)
    registerMessageHandler("deleteMachine", function(msg)
        inv.craft.deleteMachine(msg.name)
        inv.craft.saveRecipes()
    end)
    registerMessageHandler("newRecipe", function(msg)
        local items = {}
        for i, v in ipairs(msg.items) do
            items[i] = ItemDescriptor.unserialize(v)
        end
        local rid = inv.craft.registerRecipe(msg.mtype, items, msg.recipe, msg.product, msg.produces)
        inv.craft.saveRecipes()
        return rid
    end)
    registerMessageHandler("editRecipe", function(msg)
        local items = {}
        for i, v in ipairs(msg.items) do
            items[i] = ItemDescriptor.unserialize(v)
        end
        local rid = inv.craft.registerRecipe(msg.mtype, items, msg.recipe, msg.product, msg.produces, msg.rid)
        inv.craft.saveRecipes()
        return rid
    end)
    registerMessageHandler("deleteRecipe", function(msg)
        inv.craft.deleteRecipe(msg.rid)
        inv.craft.saveRecipes()
    end)
    ---@class ssd.host.RecipeInfo : RegisteredRecipe
    ---@field items string[]
    registerMessageHandler("getRecipeInfo", function(msg)
        local inforaw = inv.craft.getRecipeInfo(msg.rid)
        if not inforaw then return end
        local info = acl.clone(inforaw) --[[@as ssd.host.RecipeInfo]]
        for i, v in ipairs(inforaw.items) do
            info.items[i] = v:serialize()
        end
        return info
    end)
    registerMessageHandler("getMachineTypeInfo", function(msg)
        return inv.craft.getMachineTypeInfo(msg.mtype)
    end)
    registerMessageHandler("listPeripherals", function(msg)
        return registry.list()
    end)

    local lastCraftID = 0
    local craftRequestCache = {}
    registerMessageHandler("requestCraft", function(msg)
        local coord = Coordinates.ItemCoordinate(msg.name)
        local task, required = inv.craft.craft(coord, msg.count)
        if task then
            lastCraftID = lastCraftID + 1
            craftRequestCache[lastCraftID] = task
            return lastCraftID, required
        end
    end)
    registerMessageHandler("startCraft", function(msg)
        local task = craftRequestCache[msg.cid]
        if task then
            task:queue()
            return true
        end
    end)

    ---@param msg table
    local function parseMessage(msg)
        if type(msg) ~= "table" then return end
        if msg.side == "server" then return end
        if messageHandlers[msg.type] then
            return pcall(messageHandlers[msg.type], msg)
        end
    end

    local inventoryDirty = false
    local taskDirty = false
    local peripheralDirty = false
    local function broadcastChange()
        broadcast({
            type = "inventoryChange",
            list = inv.list(),
            fragMap = inv.reserve:getFragMap()
        })
    end

    local function onChanged(self)
        inventoryDirty = true
    end
    inv.reserve:setChangedCallback(onChanged)
    onChanged(inv.reserve)

    local function onTaskChanged(self)
        taskDirty = true
    end
    inv.scheduler.setChangedCallback(onTaskChanged)
    onTaskChanged(inv.scheduler)

    local messageQueuedEvent = "message_queued"

    ---@type {message:table,sender:number}[]
    local messageQueue = {}
    local function processMessageThread()
        while true do
            local msg = table.remove(messageQueue, 1)
            wenv.fstr = ("Q:%d"):format(#messageQueue)
            if msg then
                local result = table.pack(parseMessage(msg.message))
                if #result > 0 then
                    local response = table.pack(table.unpack(result, 2))
                    if result[1] then
                        network.send(msg.sender, {
                            result = response,
                            type = msg.message.type,
                            side = "server",
                            id = msg.message.id
                        })
                    else
                        network.send(msg.sender, {
                            type = "ERROR",
                            error = result[2],
                            side = "server",
                            id = msg.message.id
                        })
                        log:flog("Error processing client request %s.\n%s", textutils.serialise(msg.message), result[2])
                    end
                end
            else
                os.pullEvent(messageQueuedEvent)
            end
        end
    end

    local function receieveMessageThread()
        while true do
            local sender, message, prot = network.receive()
            if type(message) == "table" and message.side ~= "server" then
                messageQueue[#messageQueue + 1] = { message = message, sender = sender }
                os.queueEvent(messageQueuedEvent)
                network.send(sender, {
                    type = "ACK",
                    ftype = message.type,
                    side = "server",
                    id = message.id
                })
            end
        end
    end

    local function inventoryChangeThread()
        while true do
            sleep(sset.get(sset.changeBroadcastInterval))
            if inventoryDirty then
                inventoryDirty = false
                broadcastChange()
            end
        end
    end

    local function sendTaskUpdateThread()
        while true do
            sleep(sset.get(sset.taskBroadcastInterval))
            if taskDirty then
                taskDirty = false
                broadcast({
                    type = "taskUpdate",
                    list = inv.scheduler.list(),
                })
            end
        end
    end

    local function peripheralUpdateThread()
        while true do
            sleep(sset.get(sset.peripheralBroadcastInterval))
            if peripheralDirty then
                peripheralDirty = false
                broadcast({
                    type = "peripheralUpdate",
                    peripherals = registry.list()
                })
            end
        end
    end

    local function registryThread()
        while true do
            if registry.on_event { os.pullEvent() } then
                peripheralDirty = true
            end
        end
    end

    if standalone then
        inv.scheduler.queueTask(stl.Task.new({ function()
            screen:run(win)
        end }, "Screen", true))
    end

    local f = {
        receieveMessageThread,
        inventoryChangeThread,
        sset.checkForChangesThread,
        sendTaskUpdateThread,
        peripheralUpdateThread,
        registryThread,
        logProvider.thread
    }
    local hostTask = stl.Task.new(f, "Host", true)
    inv.scheduler.queueTask(hostTask)

    local mf = {}
    for i = 1, 1 do
        mf[#mf + 1] = processMessageThread
    end
    local messageTask = stl.Task.new(mf, "Messages", true)

    inv.scheduler.queueTask(messageTask)

    inv.run()
end

if beingRequired then
    -- running in return
    return {
        run = main,
        screen = screen
    }
end

-- Running from commandline
local ok, err = pcall(main, true)
logProvider.flush()

win.clear()
win.setVisible(true)
if not ok and err ~= "Terminated" then
    shrekui.load_screen {
        type = "Screen",
        content = {
            {
                type = "Text",
                x = 1,
                y = 1,
                w = "w",
                h = 1,
                text = "Oops, SSD crashed!",
                theme = {
                    { "fill_color", "red" }
                }
            },
            {
                type = "Text",
                x = 1,
                y = 2,
                w = "w",
                h = "h-2",
                text = err,
                scrollbar = true,
                horizontal_alignment = "left",
                theme = {
                    { "text_color", "red" },
                    { "padding",    { 1, 1, 0, 1 } }
                }
            },
            {
                type = "Button",
                x = 1,
                y = "h",
                w = "w/2",
                h = 1,
                text = "Reboot",
                on_click = function(self)
                    os.reboot()
                end
            },
            {
                type = "Button",
                x = "w/2",
                y = "h",
                w = "w/2",
                h = 1,
                text = "Quit",
                on_click = function(self)
                    self:get_root():stop()
                end
            }
        }
    }:run(win)
end
term.clear()
term.setCursorPos(1, 1)
