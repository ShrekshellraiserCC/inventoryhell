-- Dumb program to run on turtles to act as simple crafters
---@type Modem
local modem = peripheral.find("modem", function(name, wrapped)
    return not wrapped.isWireless()
end)
modem.open(7777)

term.clear()
local w, h = term.getSize()
local t = "<CRAFTER>"
term.setCursorPos((w - #t) / 2, h / 2)
term.write(t)

local localName = modem.getNameLocal()

while true do
    local e, side, channel, replyChannel, message = os.pullEvent("modem_message")
    if type(message) == "table" then
        if message[1] == "CRAFT" and message[2] == localName then
            turtle.craft()
            modem.transmit(replyChannel, channel, { "CRAFT_DONE", localName })
        end
    end
end
