local network = {}

local port = 7778
---@type ccTweaked.peripherals.Modem
local modem
local side

local id = os.getComputerID()

---@param m string
function network.open(m)
    side = m
    modem = peripheral.wrap(side) --[[@as ccTweaked.peripherals.Modem]]
    modem.open(port)
end

local function validate(rmsg)
    if type(rmsg) ~= "table" then return end
    if rmsg.type ~= "SSD" then return end
    if type(rmsg.data) ~= "table" then return end
    if type(rmsg.source) ~= "number" then return end
    if rmsg.destination == id then
        return true
    end
    if rmsg.destination == "*" then
        return true
    end
end

---@param timeout number?
function network.receive(timeout)
    local tid = timeout and os.startTimer(timeout)
    while true do
        local e, s, channel, rchannel, rmsg = os.pullEvent()
        if e == "modem_message" then
            if validate(rmsg) then
                return rmsg.source, rmsg.data
            end
        elseif e == "timer" and tid == s then
            return
        end
    end
end

local function wrap(destination, data)
    return {
        type = "SSD",
        data = data,
        source = id,
        destination = destination,
    }
end

local function loopback(data)
    os.queueEvent("modem_message", "loopback", port, port, wrap(id, data))
end

function network.send(to, data)
    if to == id then
        loopback(data)
    else
        modem.transmit(port, port, wrap(to, data))
    end
end

function network.broadcast(data)
    loopback(data)
    modem.transmit(port, port, wrap("*", data))
end

function network.lookup()
    network.broadcast({ type = "ping" })
    while true do
        local rid, response = network.receive(0.5)
        if rid == nil or response == nil then return end
        if response.type == "ping" then
            return rid
        end
    end
end

return network
