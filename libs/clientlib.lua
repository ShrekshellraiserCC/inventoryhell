local ui = require "libs.ui"
local clientlib = {}

clientlib.protocol = "SHREKSTORAGE"

local hid, modem

local throbberStates = { "\129", "\130", "\132", "\136" }
local ackThrobberStates = { "\x85", "\x83", "\x8a", "\x8c" }
--{ "\x8d", "\x85", "\x87", "\x83", "\x8b", "\x8a", "\x8e", "\x8c" }
--{ "\3", "\4", "\5", "\6" }
--{ "\186", "\7" }
--{ "|", "/", "-", "\\" }
local maxTimeouts = 10

clientlib.throbberState = " "

local function getThrobberChar(i, gotAck)
    return gotAck and ackThrobberStates[(i % #ackThrobberStates) + 1]
        or throbberStates[(i % #throbberStates) + 1]
end

---Show an activity throbber in the corner
local function showThrobber(i, gotAck)
    clientlib.throbberState = getThrobberChar(i, gotAck)
    clientlib.renderThrobber(term)
end
function clientlib.renderThrobber(win)
    local w, h = win.getSize()
    local ox, oy = ui.cursor(win, w, 1)
    local ofg, obg = ui.color(win, ui.colmap.headerFg, ui.colmap.headerBg)
    win.write(clientlib.throbberState)
    ui.color(win, ofg, obg)
    ui.cursor(win, ox, oy)
end

local function sendAndRecieve(msg)
    rednet.send(hid, msg, clientlib.protocol)
    local i = 0
    local r = 0
    local gotAck = false
    while true do
        showThrobber(i, gotAck)
        local sender, response = rednet.receive(clientlib.protocol, 0.2)
        if sender == hid and type(response) == "table" and response.side == "server" then
            if response.type == msg.type then
                clientlib.throbberState = " "
                return response.result
            elseif response.type == "ACK" and response.ftype == msg.type then
                gotAck = true
            end
        elseif sender == nil then
            i = i + 1
        end
        if i > maxTimeouts and not gotAck then
            r = r + 1
            i = 0
            rednet.send(hid, msg, clientlib.protocol)
        end
    end
end

---List out items in this storage
---@return CCItemInfo[]
function clientlib.list()
    return sendAndRecieve({ type = "list", side = "client" })[1]
end

---Get the usage of each real slot in the inventory as a percentage [0,1]. Non-stackable items have a value of 2.
---@return FragMap
function clientlib.getFragMap()
    return sendAndRecieve({ type = "getFragMap", side = "client" })[1]
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

function clientlib.open()
    modem = peripheral.find("modem", function(name, wrapped)
        return not wrapped.isWireless()
    end)
    clientlib.modem = modem
    rednet.open(peripheral.getName(modem))
    local i = 0
    local ofg, obg = ui.color(term, ui.colmap.listFg, ui.colmap.listBg)
    term.clear()
    term.setCursorPos(1, 1)
    ui.color(term, ui.colmap.headerFg, ui.colmap.headerBg)
    term.clearLine()
    term.write("Searching for Storage")
    while not hid do
        showThrobber(i)
        hid = rednet.lookup(clientlib.protocol)
        -- hid = 0
        i = i + 1
    end
    ui.color(term, ui.colmap.headerFg, ui.colmap.headerBg)
    term.setCursorPos(1, 1)
    term.clearLine()
    term.write("Found Storage")
    ui.color(term, ofg, obg)
end

---@param f fun(l:CCItemInfo[])
function clientlib.subscribeToChanges(f)
    while true do
        local sender, msg = rednet.receive(clientlib.protocol)
        if sender == hid and type(msg) == "table" and msg.type == "inventoryChange" then
            f(msg.list)
        end
    end
end

function clientlib.close()
    modem.closeAll()
end

return clientlib
