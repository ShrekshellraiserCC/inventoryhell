-- Emulate the style of old windows 9x defrag windows, showing the content of the storage
local clientlib = require("libs.clientlib")
local ui = require("libs.ui")
clientlib.open()

local mon = peripheral.wrap("top") --[[@as Monitor]]
ui.applyPallete(mon)
mon.setTextScale(0.5)
local mw, mh = mon.getSize()
local win = window.create(mon, 1, 1, mw, mh)

local usage = clientlib.getFragMap()
local function render()
    ui.drawFragMap(win, usage, 2, 2, mw - 2, mh - 2, false)
end
render()
parallel.waitForAny(clientlib.subscribeToChanges(function(l, fm)
    usage = fm
    render()
end), clientlib.run)
