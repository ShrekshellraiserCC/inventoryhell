-- Dumb program to run on turtles to act as simple crafters
---@type Modem
local modem = peripheral.find("modem", function(name, wrapped)
    return not wrapped.isWireless()
end)
modem.open(7777)

term.clear()
local w, h = term.getSize()
local t = "<CRAFTER>"
local tx, ty = (w - #t) / 2, h / 2
local dx, dy = 1, 1
local tcolors = {}
for i = 0, 14 do
    tcolors[i] = 2 ^ i
end
local ci = 1
term.setCursorPos(tx, ty)
term.write(t)

local localName = modem.getNameLocal()

parallel.waitForAny(
    function()
        while true do
            local e, side, channel, replyChannel, message = os.pullEvent("modem_message")
            if type(message) == "table" then
                if message[1] == "CRAFT" and message[2] == localName then
                    turtle.craft()
                    turtle.turnRight()
                    modem.transmit(replyChannel, channel, { "CRAFT_DONE", localName })
                elseif message[1] == "GET_NAME" then
                    modem.transmit(replyChannel, channel, { "NAME", localName })
                end
            end
        end
    end,
    function()
        while true do
            sleep(0.5)
            tx, ty = tx + dx, ty + dy
            if tx < 1 or tx + #t - 1 > w then
                tx = math.max(math.min(tx, w - #t), 1)
                dx = (dx > 0 and -1 or 1) * math.random(1, 3)
                ci = (ci + 1) % (#tcolors + 1)
                term.setTextColor(tcolors[ci])
                term.clear()
            end
            if ty < 1 or ty > h then
                ty = math.max(math.min(ty, h), 1)
                dy = dy * -1
                ci = (ci + 1) % (#tcolors + 1)
                term.setTextColor(tcolors[ci])
                term.clear()
            end
            term.setCursorPos(tx, ty)
            term.write(t)
        end
    end
)
