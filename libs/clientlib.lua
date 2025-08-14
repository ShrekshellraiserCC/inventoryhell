local ui = require "libs.ui"
local sset = require "libs.sset"
local clientlib = {}

clientlib.protocol = "SHREKSTORAGE"

local hid, modem
hid = sset.get(sset.hid)

local logger
local function log(s, ...)
    if logger then
        logger(s, ...)
    end
end

function clientlib.setLogger(l)
    logger = l
end

local throbberStates = { "\129", "\130", "\132", "\136" }
local ackThrobberStates = throbberStates
-- local ackThrobberStates = { "\x85", "\x83", "\x8a", "\x8c" }
--{ "\x8d", "\x85", "\x87", "\x83", "\x8b", "\x8a", "\x8e", "\x8c" }
--{ "\3", "\4", "\5", "\6" }
--{ "\186", "\7" }
--{ "|", "/", "-", "\\" }
local rednetTimeout = 0.3
local maxTimeouts = 10     -- 10 * 0.2 = 3 seconds
local maxAckTimeouts = 100 -- 100 * 0.2 = 30 seconds

clientlib.throbberState = " "
clientlib.throbberFg = ui.colmap.headerFg

local function getThrobberChar(i, gotAck)
    return gotAck and ackThrobberStates[(i % #ackThrobberStates) + 1]
        or throbberStates[(i % #throbberStates) + 1]
end

---Show an activity throbber in the corner
local function showThrobber(i, gotAck)
    clientlib.throbberState = getThrobberChar(i, gotAck)
    clientlib.throbberFg = gotAck and ui.colmap.headerFg or ui.colmap.errorFg
    clientlib.renderThrobber(term)
end
function clientlib.renderThrobber(win)
    local w, h = win.getSize()
    local ox, oy = ui.cursor(win, w, 1)
    local ofg, obg = ui.color(win, clientlib.throbberFg, ui.colmap.headerBg)
    win.write(clientlib.throbberState)
    ui.color(win, ofg, obg)
    ui.cursor(win, ox, oy)
end

local throbberTick = 0
local throbberInterval = 0.3
local function tickThrobber()
    while true do
        sleep(throbberInterval)
        throbberTick = throbberTick + 1
    end
end
local uid = 0
local function getUid()
    uid = uid + 1
    return uid
end

local function sendAndRecieve(msg)
    local id = getUid()
    msg.id = id
    log("Sent request %d type=%s", id, msg.type)
    rednet.send(hid, msg, clientlib.protocol)
    local tries = 0
    local r = 0
    local gotAck = false
    while true do
        showThrobber(throbberTick, gotAck)
        local sender, response = rednet.receive(clientlib.protocol, rednetTimeout)
        if sender == hid and type(response) == "table"
            and response.side == "server" and response.id == id then
            if response.type == msg.type then
                clientlib.throbberState = " "
                log("Got response for %d", id)
                return response.result
            elseif response.type == "ACK" and response.ftype == msg.type then
                gotAck = true
                log("Got ACK for %d", id)
            elseif response.type == "ERROR" then
                error(("Got error from server while processing request:\n%s"):format(response.error), 0)
            end
        elseif sender == nil then
            tries = tries + 1
        end
        if tries > maxTimeouts and not gotAck then
            r = r + 1
            tries = 0
            log("Resending request %d", id)
            rednet.send(hid, msg, clientlib.protocol)
        elseif tries > maxAckTimeouts and gotAck then
            gotAck = false
            log("ACK expired for %d", id)
        end
    end
end

---List out items in this storage
---@return CCItemInfo[]
function clientlib.list()
    return sendAndRecieve({ type = "list", side = "client" })[1]
end

---List out the Recipes this storage has
---@return RecipeInfo[]
function clientlib.listRecipes()
    return sendAndRecieve({ type = "listRecipes", side = "client" })[1]
end

---Get the usage of each real slot in the inventory as a percentage [0,1]. Non-stackable items have a value of 2.
---@return FragMap
function clientlib.getFragMap()
    return sendAndRecieve({ type = "getFragMap", side = "client" })[1]
end

---Remove an inventory from the system's cache
---@param inv string
function clientlib.removeInventory(inv)
    return sendAndRecieve({ type = "removeInventory", side = "client", inv = inv })
end

---Push items into some inventory
---@param to string
---@param item ItemDescriptor
---@param limit integer?
---@param toSlot integer?
---@return integer
function clientlib.pushItems(to, item, limit, toSlot)
    return sendAndRecieve({
        type = "pushItems",
        side = "client",
        to = to,
        item = item:serialize(),
        limit = limit,
        toSlot = toSlot
    })
end

---@param from string
---@param slot integer
---@param limit integer?
---@return integer
---@return ItemCoordinate
function clientlib.pullItems(from, slot, limit)
    local res = sendAndRecieve({
        type = "pullItems",
        side = "client",
        from = from,
        slot = slot,
        limit = limit
    })
    return res[1], res[2]
end

---@return TaskListInfo[]
function clientlib.listThreads()
    local res = sendAndRecieve({ type = "listThreads" })
    return res[1]
end

function clientlib.rebootAll()
    rednet.broadcast({ type = "rebootAll" }, clientlib.protocol)
    os.reboot()
end

---Import a JSON recipe into this storage
function clientlib.importJSON(json)
    sendAndRecieve({ type = "importJSON", json = json })
end

function clientlib.saveRecipes()
    sendAndRecieve({ type = "saveRecipes" })
end

function clientlib.open()
    modem = peripheral.find("modem", function(name, wrapped)
        return not wrapped.isWireless()
    end) --[[@as WiredModem]]
    clientlib.modem = modem
    rednet.open(peripheral.getName(modem))
    local i = 0
    local ofg, obg = ui.color(term, ui.colmap.listFg, ui.colmap.listBg)
    term.clear()
    term.setCursorPos(1, 1)
    ui.color(term, ui.colmap.headerFg, ui.colmap.headerBg)
    term.clearLine()
    term.write("Searching for Storage")
    parallel.waitForAny(function()
        while not hid do
            hid = rednet.lookup(clientlib.protocol)
        end
    end, function()
        while true do
            throbberTick = throbberTick + 1
            showThrobber(throbberTick)
            sleep(throbberInterval)
        end
    end)
    ui.color(term, ui.colmap.headerFg, ui.colmap.headerBg)
    term.setCursorPos(1, 1)
    term.clearLine()
    term.write("Found Storage")
    ui.color(term, ofg, obg)
end

---@param f fun(l:CCItemInfo[],fragMap:FragMap)
function clientlib.subscribeToChanges(f)
    while true do
        local sender, msg = rednet.receive(clientlib.protocol)
        if sender == hid and type(msg) == "table" and msg.type == "inventoryChange" then
            f(msg.list, msg.fragMap)
        end
    end
end

---@param f fun(l:TaskListInfo[])
function clientlib.subscribeToTasks(f)
    while true do
        local sender, msg = rednet.receive(clientlib.protocol)
        if sender == hid and type(msg) == "table" and msg.type == "taskUpdate" then
            f(msg.list)
        end
    end
end

function clientlib.close()
    modem.closeAll()
end

---Update the throbber animation state
clientlib.run = function()
    parallel.waitForAny(tickThrobber, function()
        while true do
            local sender, message = rednet.receive(clientlib.protocol)
            if type(message) == "table" and message.type == "rebootAll" then
                os.reboot()
            end
        end
    end)
end

return clientlib
