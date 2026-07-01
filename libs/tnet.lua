local tnet = {}

local turtlePort = 7777

local modem, localName, mname
---@param m WiredModem
function tnet.open(m)
    modem = m
    m.open(turtlePort)
    mname = peripheral.getName(m)
    localName = m.getNameLocal()
end

local function getUsedSlots()
    local c = {}
    for i = 1, 16 do
        if turtle.getItemCount(i) > 0 then
            c[i] = true
        end
    end
    return c
end

---@alias ssd.libs.tnet.tmtype "NAME"|"CRAFT_DONE"|"ITEMS"|"EMPTY"
---@alias ssd.libs.tnet.tmsg [ssd.libs.tnet.tmtype,string,table]

---@type ssd.libs.slogger.Logger
local logger = setmetatable({}, { __index = function() return function() end end })
---@param l ssd.libs.slogger.Logger
function tnet.logger(l)
    logger = l
end

tnet.turtle = {}
tnet.turtle.getUsedSlots = getUsedSlots


---@param mtype ssd.libs.tnet.tmtype?
---@param slots table?
function tnet.turtle.broadcast(mtype, slots)
    modem.transmit(turtlePort, turtlePort, { mtype or "NAME", localName, slots or getUsedSlots() })
end

---@param filter ssd.libs.tnet.hmtype?
---@return ssd.libs.tnet.hmsg
function tnet.turtle.receive(filter)
    while true do
        local e, side, channel, replyChannel, message = os.pullEvent("modem_message")
        if e == "modem_message" and side == mname and channel == turtlePort and type(message) == "table" then
            if filter and message[1] ~= filter then goto continue end
            if message[1] == "GET_NAME" then
                message[2] = message[2] or localName
            end
            if message[2] ~= localName then goto continue end
            return message
        end
        ::continue::
    end
end

tnet.host = {}


---@alias ssd.libs.tnet.hmtype "CRAFT"|"GET_NAME"|"ACK"
---@alias ssd.libs.tnet.hmsg [ssd.libs.tnet.hmtype,string]

---@param to string
---@param mtype ssd.libs.tnet.hmtype
function tnet.host.send(to, mtype)
    modem.transmit(turtlePort, turtlePort, { mtype, to })
end

function tnet.host.lookup()
    modem.transmit(turtlePort, turtlePort, { "GET_NAME" })
end

---@param filter ssd.libs.tnet.tmtype?
---@param from string?
---@param tid integer?
---@return ssd.libs.tnet.tmsg
function tnet.host.receive(filter, from, tid)
    while true do
        local e, side, channel, replyChannel, message = os.pullEvent()
        if e == "modem_message" and side == mname and channel == turtlePort and type(message) == "table" then
            if from and message[2] ~= from then goto continue end
            if filter and message[1] ~= filter then goto continue end
            return message
        elseif e == "timer" and side == tid then
            ---@diagnostic disable-next-line: missing-return-value
            return
        end
        ::continue::
    end
end

return tnet
