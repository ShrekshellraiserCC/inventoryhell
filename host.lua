local acl = require("libs.ACL")
local ID = require("libs.ItemDescriptor")
local stl = require("libs.STL")
local sset = require("libs.sset")
local ui = require("libs.ui")
local VirtualInv = require("libs.VirtualInv")

local protocol = require("libs.clientlib").protocol
local hostname = "HOST_TEST"
-- Central host process for the storage system
local modem = peripheral.find("modem", function(name, wrapped)
    return not wrapped.isWireless()
end)
rednet.open(peripheral.getName(modem))
rednet.host(protocol, hostname)

local id = os.getComputerID()
local function broadcast(m)
    rednet.broadcast(m, protocol)
    rednet.send(id, m, protocol)
end

local chestList = {}
for i, v in ipairs(peripheral.getNames()) do
    if v:match("minecraft:chest") then
        chestList[#chestList + 1] = v
    end
end
local t0 = os.epoch("utc")
local tracker = VirtualInv.defaultTracker()
---@type ACL
local inv

local w, h = term.getSize()
ui.loadTheme(sset.get(sset.theme))
ui.applyPallete(term)
local headWin = window.create(term.current(), 1, 1, w, 1)
local logWin = window.create(term.current(), 1, 2, w, h - 2)
local footerWin = window.create(term.current(), 1, h, w, 1)

ui.preset(headWin, ui.presets.header)
ui.preset(logWin, ui.presets.list)
ui.preset(footerWin, ui.presets.footer)
logWin.clear()
logWin.setCursorPos(1, 1)
term.redirect(logWin)

ui.header(headWin, "ShrekStorageDrive INDEV")
parallel.waitForAny(
    function()
        inv = acl.wrap(chestList, modem, tracker)
    end,
    function()
        while true do
            footerWin.clear()
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
            local percentage = scanned / total
            local eta = math.ceil((t1 - t0) * (1 / (percentage) - 1) / 1000)
            local etaStr = ("%s:%3ds"):format(stage, eta)
            if eta > 1000 then
                etaStr = ("%s:---s"):format(stage)
            end
            local sw = #etaStr
            ui.cursor(footerWin, 1, 1)
            footerWin.write(etaStr)
            ui.progressBar(footerWin, sw + 2, 1, w - sw + 1, percentage)
            sleep(0)
        end
    end
)
local initTime = os.epoch("utc") - t0
local info = inv.reserve:getSlotInfo()
print(("SSD initialized %d used (of %d total) slots in %.2f seconds")
    :format(info.used, info.total, initTime / 1000))


local messageHandlers = {}

local function registerMessageHandler(type, handle)
    messageHandlers[type] = handle
end
registerMessageHandler("list", function(msg)
    return inv.reserve:list()
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
local function broadcastChange()
    broadcast({
        type = "inventoryChange",
        list = inv.reserve:list(),
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
        if msg then
            local result = table.pack(parseMessage(msg.message))
            if #result > 0 then
                local response = table.pack(table.unpack(result, 2))
                if result[1] then
                    rednet.send(msg.sender, {
                            result = response,
                            type = msg.message.type,
                            side = "server",
                            id = msg.message.id
                        },
                        protocol)
                else
                    rednet.send(msg.sender, {
                        type = "ERROR",
                        error = result[2],
                        side = "server",
                        id = msg.message.id
                    }, protocol)
                    print(("Error processing client request %s.\n%s")
                        :format(textutils.serialise(msg.message), result[2]))
                end
            end
        else
            os.pullEvent(messageQueuedEvent)
        end
    end
end

local function receieveMessageThread()
    while true do
        local sender, message, prot = rednet.receive(protocol)
        if type(message) == "table" and message.side ~= "server" then
            messageQueue[#messageQueue + 1] = { message = message, sender = sender }
            os.queueEvent(messageQueuedEvent)
            rednet.send(sender, {
                type = "ACK",
                ftype = message.type,
                side = "server",
                id = message.id
            }, protocol)
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

local f = {
    receieveMessageThread,
    inventoryChangeThread,
    sset.checkForChangesThread,
    sendTaskUpdateThread
}
local hostTask = stl.Task.new(f, "Host")
inv.scheduler.queueTask(hostTask)
inv.scheduler.queueTask(stl.Task.new({
    function()
        while true do
            ui.footer(footerWin, ("Q:%d"):format(#messageQueue))
            sleep(0)
        end
    end
}, "Footer Display"))

local mf = {}
for i = 1, 1 do
    mf[#mf + 1] = processMessageThread
end
local messageTask = stl.Task.new(mf, "Messages")

inv.scheduler.queueTask(messageTask)

inv.run()
