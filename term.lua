local clientlib = require("libs.clientlib")
local ID = require("libs.ItemDescriptor")
clientlib.open()
local ui = require("libs.ui")
ui.applyPallete(term)

local lname = clientlib.modem.getNameLocal()
local fullList = clientlib.list()

local searchBarOnTop = false
local displayExtra = false

local mainWindow = window.create(term.current(), 1, 1, term.getSize())
local w, h = mainWindow.getSize()
local listWindow = window.create(mainWindow, 1, 1, w, h - 1)
local inputWindow = window.create(mainWindow, 1, h, w, 1)
if searchBarOnTop then
    listWindow.reposition(1, 2, w, h - 1)
    inputWindow.reposition(1, 1, w, 1)
end
---@class TermLib
local tlib = {
    win = {
        main = mainWindow,
        list = listWindow,
        input = inputWindow
    }
}
function tlib.hideAllWin()
    for n, v in pairs(tlib.win) do
        v.setVisible(false)
        v.setCursorBlink(false)
    end
end

local expectingItems = false
local debounceTid = os.startTimer(0.2)

---@type table<number,boolean>
local lockedSlots = {}

local function lockUsedSlots()
    if not turtle then return end
    for i = 1, 16 do
        lockedSlots[i] = turtle.getItemCount(i) > 0
    end
end

local function emptyInventory()
    if not turtle then return end
    for i = 1, 16 do
        local c = turtle.getItemCount(i)
        if not lockedSlots[i] and c > 0 then
            clientlib.pullItems(lname, i)
        elseif lockedSlots[i] and c == 0 then
            lockedSlots[i] = false
        end
    end
end

---@class RegisteredClientUI
---@field render fun(tlib:TermLib)
---@field onEvent fun(e:any[],tlib:TermLib):boolean
---@field setValue fun(...)?
---@field onSet fun()?

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

do
    local mainList = ui.tableGuiWrapper(
        mainWindow,
        uiList,
        function(v)
            return { v }
        end,
        { "Main Menu" },
        function(i, v)
            setUI(v)
        end
    )
    registerUI("main", mainList.draw, mainList.onEvent)
    uiList[1] = nil
    setUI("main")
end

do
    local columns = { "Count", "Name" }
    if not displayExtra then
        columns[#columns + 1] = "Extra"
    end
    local wrap = ui.tableGuiWrapper(listWindow, {} --[[@as table<integer,CCItemInfo>]], function(v)
        local es = ""
        if v.enchantments then
            for i, e in ipairs(v.enchantments) do
                es = es .. e.displayName .. ","
            end
            es = es:sub(1, #es - 1)
        end
        return { tostring(v.count), v.displayName, es }
    end, { "Count", "Name" }, function(i, v)
        tlib.win.input.setCursorBlink(false)
        local want = ui.getItemCount(mainWindow, v)
        if not want then return end
        expectingItems = true
        clientlib.pushItems(lname, ID.fromName(v.name, v.nbt), want)
        lockUsedSlots()
        expectingItems = false
    end)
    local reread = ui.reread(tlib.win.input, 2, 1, w - 2)
    local filteredList = {}
    local function filter()
        local ok, id = pcall(ID.unserialize, reread.buffer)
        if ok then
            filteredList = id:matchList(fullList)
            return
        end
        ok, id = pcall(ID.fromPattern, reread.buffer)
        if ok then
            filteredList = id:matchList(fullList)
            return
        end
        filteredList = fullList
    end
    local function onEvent(e)
        if wrap.onEvent(e) then return true end
        return reread:onEvent(e)
    end
    local function mrender()
        filter()
        wrap.setTable(filteredList)
        wrap.draw()
        ui.color(tlib.win.input, ui.colmap.inputFg, ui.colmap.inputBg)
        tlib.win.input.clear()
        ui.cursor(tlib.win.input, 1, 1)
        tlib.win.input.write(">")
        reread:render()
        clientlib.renderThrobber(term)
        tlib.win.list.setVisible(true)
        tlib.win.input.setVisible(true)
    end

    registerUI("Storage", mrender, onEvent, function(search)
        reread:setValue(search)
    end)
end

local fragMap = clientlib.getFragMap()
do
    local fragMapDraw = function()
        ui.color(tlib.win.main, ui.colmap.headerFg, ui.colmap.headerBg)
        ui.cursor(tlib.win.main, 1, 1)
        tlib.win.main.clearLine()
        tlib.win.main.write("FragMap View")
        clientlib.renderThrobber(tlib.win.main)
        ui.drawFragMap(tlib.win.main, fragMap, 2, 3, w - 3, h - 3, true)
    end
    local fragMapOnEvent = function(e)

    end
    registerUI("FragMap", fragMapDraw, fragMapOnEvent)
end

local function emptyThread()
    while true do
        local e = table.pack(os.pullEvent())
        if e[1] == "timer" and e[2] == debounceTid then
            emptyInventory()
        end
    end
end

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
            if e[1] == "turtle_inventory" and not expectingItems then
                os.cancelTimer(debounceTid)
                debounceTid = os.startTimer(0.2)
            elseif e[1] == "key" and e[2] == keys.tab then
                setUI("main")
            end
        end
    end
end
parallel.waitForAny(function()
    clientlib.subscribeToChanges(function(l)
        fullList = l
        fragMap = clientlib.getFragMap()
    end)
end, main, emptyThread)
