local clientlib = require("clientlib")
local ID = require("ItemDescriptor")
clientlib.open()
local ui = require("ui")
ui.applyPallete(term)

local lname = clientlib.modem.getNameLocal()
local list = clientlib.list()


local mainWindow = window.create(term.current(), 1, 1, term.getSize())
local listWindow = window.create(mainWindow, 1, 1, mainWindow.getSize())

local expectingItems = false
local debounceTid = os.startTimer(0.2)

---@type table<number,boolean>
local lockedSlots = {}

local function lockUsedSlots()
    for i = 1, 16 do
        lockedSlots[i] = turtle.getItemCount(i) > 0
    end
end

local function emptyInventory()
    for i = 1, 16 do
        local c = turtle.getItemCount(i)
        if not lockedSlots[i] and c > 0 then
            clientlib.pullItems(lname, i)
        elseif lockedSlots[i] and c == 0 then
            lockedSlots[i] = false
        end
    end
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
end, { "Count", "Name", "Extra" }, function(i, v)
    local want = ui.getItemCount(mainWindow, v)
    if not want then return end
    expectingItems = true
    clientlib.pushItems(lname, ID.fromName(v.name, v.nbt), want)
    lockUsedSlots()
    expectingItems = false
end)
local function render()
    wrap.setTable(list)
    wrap.draw()
    clientlib.renderThrobber(term)
end

local function emptyThread()
    while true do
        local e = table.pack(os.pullEvent())
        if e[1] == "timer" and e[2] == debounceTid then
            emptyInventory()
        end
    end
end

local function main()
    while true do
        render()
        local e = table.pack(os.pullEvent())
        if not wrap.onEvent(e) then
            if e[1] == "turtle_inventory" and not expectingItems then
                os.cancelTimer(debounceTid)
                debounceTid = os.startTimer(0.2)
            end
        end
    end
end
parallel.waitForAny(function()
    clientlib.subscribeToChanges(function(l)
        list = l
    end)
end, main, emptyThread)
