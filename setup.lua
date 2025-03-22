local ui   = require "libs.ui"
local sset = require "libs.sset"

local w, h = term.getSize()
local win  = window.create(term.current(), 1, 1, w, h)
ui.applyPallete(win)
local lwin = window.create(win, 1, 1, w, h - 1)

local tlib = {
    win = {
        list = lwin,
        main = win
    }
}
function tlib.hideAllWin()
    for n, v in pairs(tlib.win) do
        v.setVisible(false)
        v.setCursorBlink(false)
    end
end

---@type table<string,RegisteredClientUI>
local registeredUIs = {}
local uiList = {}
---Register a UI screen
---@param name string
---@param render fun()
---@param onEvent fun(e:any[]):boolean
---@param setValue fun(...)?
---@param onSet fun()?
local function registerUI(name, render, onEvent, setValue, onSet)
    registeredUIs[name] = {
        render = render,
        onEvent = onEvent,
        setValue = setValue,
        onSet = onSet
    }
    uiList[#uiList + 1] = name
end
tlib.registerUI = registerUI
---@type RegisteredClientUI
local activeUI
local function setUI(name)
    activeUI = registeredUIs[name]
    -- make sure user inputs aren't carried to a different screen
    os.queueEvent("event_clense")
    os.pullEvent("event_clense")
    if activeUI.onSet then
        activeUI.onSet()
    end
end
tlib.setUI = setUI

local function render()
    tlib.hideAllWin()
    ui.color(tlib.win.main, ui.colmap.listFg, ui.colmap.listBg)
    tlib.win.main.clear()
    activeUI.render(tlib)
    tlib.win.main.setVisible(true)
end

local function main()
    while true do
        render()
        local e = table.pack(os.pullEvent())
        if not activeUI.onEvent(e, tlib) then
        end
    end
end

loadfile("disk/tplugins/settings.lua", "t", _ENV)()(tlib)
setUI("Settings")

main()
