local clientlib = {}

clientlib.protocol = "SHREKSTORAGE"

local hid, modem

local throbberStates = { "|", "/", "-", "\\" }
local maxTimeouts = 10
local maxRetries = 3

---Show an activity throbber in the corner
local function showThrobber(i)
    local ox, oy = term.getCursorPos()
    term.setCursorPos(1, 1)
    term.write(throbberStates[(i % #throbberStates) + 1])
    term.setCursorPos(ox, oy)
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
    return sendAndRecieve({ type = "list", side = "client" })
end

---Get the usage of each real slot in the inventory as a percentage [0,1]. Non-stackable items have a value of 2.
---@return number[]
function clientlib.getSlotUsage()
    return sendAndRecieve({ type = "getSlotUsage", side = "client" })
end

function clientlib.open()
    modem = peripheral.find("modem", function(name, wrapped)
        return not wrapped.isWireless()
    end)
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

function clientlib.close()
    modem.closeAll()
end

return clientlib
