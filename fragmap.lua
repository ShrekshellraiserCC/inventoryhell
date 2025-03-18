-- Emulate the style of old windows 9x defrag windows, showing the content of the storage
local clientlib = require("libs.clientlib")
local bixelbox = require("libs.bixelbox")
local ui = require("libs.ui")
clientlib.open()

local fullColor = colors.blue
local partColor = colors.cyan
local emptyColor = colors.white
local nonStackColor = colors.red

local mon = peripheral.wrap("top") --[[@as Monitor]]
ui.applyPallete(mon)
mon.setTextScale(0.5)
local mw, mh = mon.getSize()
local win = window.create(mon, 2, 2, mw - 2, mh - 2)
local box = bixelbox.new(win, colors.black)

local usage = clientlib.getSlotUsage()
local function render()
    local w, h = win.getSize()
    win.setBackgroundColor(colors.black)
    win.clear()
    h = h * 1.5
    box:clear(colors.black)
    local sy = 1
    win.setCursorPos(1, sy)
    win.write("Slots:")
    for i, v in ipairs(usage) do
        local x = (i - 1) % w + 1
        local y = math.floor((i - 1) / w) + sy
        local color = partColor
        if v == 1 then
            color = fullColor
        elseif v == 0 then
            color = emptyColor
        elseif v == 2 then
            color = nonStackColor
        end
        box:set_pixel(x, y, color)
    end
    sy = sy + #usage
    box:render()
end

render()
clientlib.subscribeToChanges(function(l)
    usage = clientlib.getSlotUsage()
    render()
end)
