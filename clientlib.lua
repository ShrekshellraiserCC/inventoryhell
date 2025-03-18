local ID = require "ItemDescriptor"
local ui = require "ui"
local clientlib = {}

clientlib.protocol = "SHREKSTORAGE"

local hid, modem

local throbberStates = { "|", "/", "-", "\\" }
local maxTimeouts = 10
local maxRetries = 3

---Show an activity throbber in the corner
local function showThrobber(i)
    local w, h = term.getSize()
    local ox, oy = ui.cursor(term, w, 1)
    local ofg, obg = ui.color(term, ui.colmap.headerFg, ui.colmap.headerBg)
    term.write(throbberStates[(i % #throbberStates) + 1])
    ui.color(term, ofg, obg)
    ui.cursor(term, ox, oy)
end

local function sendAndRecieve(msg)
    rednet.send(hid, msg, clientlib.protocol)
    local i = 0
    local r = 0
    while true do
        showThrobber(i)
        local sender, response = rednet.receive(clientlib.protocol, 0.2)
        if sender == hid and type(response) == "table" and response.type == msg.type and response.side == "server" then
            return response.result
        elseif sender == nil then
            i = i + 1
        end
        if i > maxTimeouts then
            r = r + 1
            if r > maxRetries then
                error("Connection to server timed out!", 0)
            end
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
---@return number[]
function clientlib.getSlotUsage()
    return sendAndRecieve({ type = "getSlotUsage", side = "client" })[1]
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
    while not hid do
        showThrobber(i)
        -- hid = rednet.lookup(clientlib.protocol)
        hid = 0
        i = i + 1
        if i > maxRetries then
            error("Failed to find a host!", 0)
        end
    end
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
