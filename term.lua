local clientlib = require("libs.clientlib")
local ID = require("libs.ItemDescriptor")
local sset = require("libs.sset")
local STL = require("libs.STL")
local scheduler = STL.Scheduler()
local ui = require("libs.ui")
ui.applyPallete(term)


local mainWindow = window.create(term.current(), 1, 1, term.getSize())
local w, h = mainWindow.getSize()
local listWindow = window.create(mainWindow, 1, 1, w, h - 1)
local inputWindow = window.create(mainWindow, 1, h, w, 1)
local logWindow = window.create(mainWindow, 1, 2, w, h - 2)
---@class TermLib
local tlib = {
    win = {
        main = mainWindow,
        list = listWindow,
        input = inputWindow,
        log = logWindow
    },
    clientlib = clientlib
}
tlib.scheduler = scheduler
tlib.STL = STL
tlib.fullList = {}
function tlib.log(s, ...)
    local old = term.redirect(logWindow)
    print(os.date("[%T]"), s:format(...))
    term.redirect(old)
end

clientlib.setLogger(tlib.log)
clientlib.open()
local lname = clientlib.modem.getNameLocal()

function tlib.hideAllWin()
    for n, v in pairs(tlib.win) do
        v.setVisible(false)
        v.setCursorBlink(false)
    end
end

local expectingItems = false
local debounceDelay = sset.get(sset.debounceDelay)
local debounceTid = os.startTimer(debounceDelay)

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
    registerUI("main", function()
        mainList.draw()
        ui.footer(mainWindow, "SHREK STORAGE SYSTEM WIP")
    end, mainList.onEvent)
    uiList[1] = nil
    setUI("main")
end

do
    local columns = { "Count", "Name" }
    if not sset.get(sset.hideExtra) then
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
    end, columns, function(i, v)
        tlib.win.input.setCursorBlink(false)
        local want = ui.getItemCount(mainWindow, v)
        if not want then return end
        expectingItems = true
        clientlib.pushItems(lname, ID.fromName(v.name, v.nbt), want)
        lockUsedSlots()
        expectingItems = false
    end, { true }, nil, { "r" })
    local reread = ui.reread(tlib.win.input, 3, 1, w - 2)
    local filteredList = {}
    ---@type "ID"|"Pattern"|"Invalid"
    local parseStatus = "ID"
    local function filter()
        local ok, id = pcall(ID.unserialize, reread.buffer)
        if ok then
            filteredList = id:matchList(tlib.fullList)
            parseStatus = "ID"
            return
        end
        ok, id = pcall(ID.fromPattern, reread.buffer)
        if ok and id then
            filteredList = id:matchList(tlib.fullList)
            parseStatus = "Pattern"
            return
        end
        parseStatus = "Invalid"
        filteredList = tlib.fullList
    end
    local function onEvent(e)
        if wrap.onEvent(e) then return true end
        return reread:onEvent(e)
    end
    local function mrender()
        filter()
        wrap.setTable(filteredList)
        wrap.draw()
        ui.preset(tlib.win.input, ui.presets.input)
        tlib.win.input.clear()
        ui.preset(tlib.win.input, ui.presets.footer)
        ui.cursor(tlib.win.input, 1, 1)
        tlib.win.input.write(ui.icons.back)
        ui.preset(tlib.win.input, ui.presets.input)
        if parseStatus == "ID" then
            ui.color(tlib.win.input, colors.green)
        elseif parseStatus == "Invalid" then
            ui.color(tlib.win.input, colors.red)
        end
        tlib.win.input.write(">")
        ui.color(tlib.win.input, ui.colmap.inputFg, ui.colmap.inputBg)
        reread:render()
        tlib.win.list.setVisible(true)
        tlib.win.input.setVisible(true)
    end

    registerUI("Storage", mrender, onEvent, function(search)
        reread:setValue(search)
    end, wrap.restartTicker)
end

tlib.fragMap = {
    invs = {},
    nostack = {}
}


tlib.registerUI = registerUI

local function loadPlugins(dir)
    local list = fs.list(dir)
    for i, v in ipairs(list) do
        print("Loading Plugin:", v)
        loadfile(fs.combine(dir, v), "t", _ENV)()(tlib)
    end
end
loadPlugins("disk/tplugins")

do
    local function render()
        ui.header(mainWindow, "Log")
        ui.footer(mainWindow, ui.icons.back)
        logWindow.setVisible(true)
        logWindow.setVisible(false)
    end
    local function onEvent()
    end
    registerUI("Log", render, onEvent)
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
    clientlib.renderThrobber(tlib.win.main)
    tlib.win.main.setVisible(true)
end

local function main()
    while true do
        render()
        local e = table.pack(os.pullEvent())
        if not activeUI.onEvent(e, tlib) then
            if e[1] == "turtle_inventory" and not expectingItems then
                os.cancelTimer(debounceTid)
                debounceTid = os.startTimer(debounceDelay)
            elseif e[1] == "key" and e[2] == keys.tab then
                setUI("main")
            end
        end
    end
end
local function init()
    tlib.fullList = clientlib.list()
    tlib.fragMap = clientlib.getFragMap()
    tlib.log("Client Init Done")
end

scheduler.queueTask(STL.Task.new({
    main, emptyThread,
    clientlib.run, sset.checkForChangesThread, init,
    function()
        clientlib.subscribeToChanges(function(l, fm)
            tlib.fullList = l
            tlib.fragMap = fm
        end)
    end
}, "Main"))
scheduler.run()
