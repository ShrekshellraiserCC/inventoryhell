local ui   = require "libs.ui"
local sset = require "libs.sset"

local w, h = term.getSize()
local win  = window.create(term.current(), 1, 1, w, h)
ui.applyPallete(win)
local lwin = window.create(win, 1, 1, w, h - 1)
local iwin = window.create(win, 1, h, w, 1)

local tlib = {
    win = {
        list = lwin,
        main = win,
        input = iwin
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
            if e[1] == "key" and e[2] == keys.tab then
                setUI("Setup")
            end
        end
    end
end

loadfile("disk/tplugins/settings.lua", "t", _ENV)()(tlib)
do
    local options = {}
    local bootOptions = {
        Host = "host",
        ["Host (* Replaces Existing!)"] = "host",
        ["Host + Term"] = "host+term",
        ["Host + Term (* Replaces Existing!)"] = "host+term",
        Term = "term",
        Crafter = "crafter"
    }
    local hostOptions = {
        host = true,
        ["host+term"] = true
    }
    local hostExists = sset.get(sset.hid)
    if not hostExists then
        options[#options + 1] = "Host"
        options[#options + 1] = "Host + Term"
    end
    options[#options + 1] = "Term"
    if turtle then
        options[#options + 1] = "Crafter"
    end
    if hostExists then
        options[#options + 1] = "Host (* Replaces Existing!)"
        options[#options + 1] = "Host + Term (* Replaces Existing!)"
    end

    options[#options + 1] = "Edit Settings"
    local wrap = ui.tableGuiWrapper(tlib.win.main,
        options, function(v)
            return { v }
        end, { "Setup" }, function(i, v)
            if v == "Edit Settings" then
                setUI("Settings")
            elseif bootOptions[v] then
                sset.set(sset.program, bootOptions[v])
                if hostOptions[bootOptions[v]] then
                    sset.set(sset.hid, os.getComputerID())
                end
                os.reboot()
            end
        end, nil, sset.get(sset.unlockMouse))
    registerUI("Setup", wrap.draw, wrap.onEvent)
end
setUI("Setup")

main()
