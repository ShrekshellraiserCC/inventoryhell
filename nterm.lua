local listing = {
    { name = "minecraft:cobblestone", displayName = "Cobblestone", count = 1200 },
    { name = "minecraft:stone_sword", displayName = "Stone Sword", count = 15 }
}

package.path = package.path .. ";libs/?.lua"

local ui = require "libs.shrekui"
local clientlib = require "libs.clientlib"
local sset = require "libs.sset"
local STL = require "libs.STL"
local ID = require "libs.ItemDescriptor"
local scheduler = STL.Scheduler()

clientlib.open()
local lname = turtle and assert(clientlib.modem.getNameLocal(), "This device is not connected via this modem!")
local invName = sset.get(sset.termInventory)

local expectingItems = false
local debounceDelay = sset.get(sset.debounceDelay)
local debounceTid = os.startTimer(debounceDelay)

---@class SSDTermAPI
local tapi = {}
tapi.scheduler = scheduler

if turtle then
    turtle.select(16)
end

local theme               = {
    { "Frame/border_thickness", 1 },
    { "Frame/border_layer",     "px" },
    { "fill_color:pressed",     "orange" },
    { "Dropdown/fill_color",    "blue" },
}

---@type table<number,boolean>
local lockedTurtleSlots   = {}
---@type table<number,boolean>
local lockedExternalSlots = {}

local function lockUsedTurtleSlots()
    if not turtle then return end
    for i = 1, 16 do
        lockedTurtleSlots[i] = turtle.getItemCount(i) > 0
    end
end

local function emptyTurtleInventory()
    for i = 1, 16 do
        local c = turtle.getItemCount(i)
        if not lockedTurtleSlots[i] and c > 0 then
            clientlib.pullItems(lname, i)
        elseif lockedTurtleSlots[i] and c == 0 then
            lockedTurtleSlots[i] = false
        end
    end
end

local function lockUsedExternalSlots()
    local list = peripheral.call(invName, "list")
    local size = peripheral.call(invName, "size")
    for i = 1, size do
        lockedExternalSlots[i] = list[i] ~= nil
    end
end

local function emptyExternalInventory()
    local list = peripheral.call(invName, "list")
    local size = peripheral.call(invName, "size")
    for i = 1, size do
        if not lockedExternalSlots[i] and list[i] then
            clientlib.pullItems(invName, i)
        elseif lockedExternalSlots[i] and not list[i] then
            lockedExternalSlots[i] = false
        end
    end
end


local function emptyTurtleThread()
    while true do
        local e = table.pack(os.pullEvent())
        if e[1] == "timer" and e[2] == debounceTid then
            emptyTurtleInventory()
        end
    end
end

local function turtleInventoryPoll()
    while true do
        os.pullEvent("turtle_inventory")
        if not expectingItems then
            os.cancelTimer(debounceTid)
            debounceTid = os.startTimer(debounceDelay)
        end
    end
end

local tw, th = term.getSize()
local win = window.create(term.current(), 1, 1, tw, th)
term.clear()


local env = {
    item = listing[1],
    back_icon = "\27",
    listing = listing,
    search_bar = "",
    setting_search_bar = "",
    turtle = turtle,
    tapi = tapi,
    task_category = "Server",
    settings = {}
}

local sort = {}
env.open_screen_button = function(self)
    tapi.open_screen(self.meta)
end
local function apply_sort(filter)
    sort = {}
    for i, v in ipairs(listing) do
        if v.name:match(filter) then
            sort[#sort + 1] = v
        end
    end
    env.listing = sort
end
apply_sort("")
env.search_change = function(self, value)
    apply_sort(value)
end
local settings_list = {}
local function create_settings_list()
    settings_list = {}
    for i, v in ipairs(sset.settingList) do
        local value = sset.get(v)
        if value ~= nil and value == v.default then
            value = tostring(value) .. "*"
        else
            value = tostring(value)
        end
        settings_list[i] = {
            name = v.name,
            desc = v.desc,
            value = value
        }
    end
end
local function apply_settings_sort(s)
    sort = {}
    for i, v in ipairs(settings_list) do
        if v.name:match(s) then
            sort[#sort + 1] = v
        end
    end
    env.settings = sort
end
env.setting_search_change = function(self, value)
    apply_settings_sort(value)
end
env.item_select = function(self, item, idx)
    ---@cast self Screen
    env.item = item
    env.item.detail = nil
    env.item.detail = textutils.serialize(item)
    tapi.open_screen("request")
end
env.open_craft_button = function(self)
    expectingItems = env.craft_active
    if not expectingItems then
        lockedTurtleSlots = {}
        emptyTurtleInventory()
    end
end

local function request(item, count)
    expectingItems = true
    local target = invName or lname
    if target then
        clientlib.pushItems(target, ID.fromName(item.name, item.nbt), count)
        if invName then
            lockUsedExternalSlots()
        else
            lockUsedTurtleSlots()
        end
    end
    if not env.craft_active then
        expectingItems = false
    end
end
function env.submit_request(self)
    local mul = 8
    if self:is_held(keys.leftShift) then
        mul = 64
    elseif self:is_held(keys.leftCtrl) then
        mul = 1
    end
    local count = self.meta * mul
    request(env.item, count)
    self:get_root():stop()
end

function env.craft()
    turtle.craft()
end

function env.depot()
    lockedTurtleSlots = {}
    emptyTurtleInventory()
end

---@type table<string,Screen>
local screens = {}
---@param name string
---@param path string
local function register_screen(name, path)
    local screen = ui.load_screen_lua(sset.getInstalledPath(path), env)
    screens[name] = screen
    screen.meta = name
    screen._theme:append(theme)
    return screen
end

local current_screen
local screen_stack = {}
function tapi.open_screen(name)
    screen_stack[#screen_stack + 1] = current_screen.meta
    current_screen = screens[name]
end

function tapi.back()
    local top = table.remove(screen_stack)
    if top then
        current_screen = screens[top]
    end
end

local function ui_event_loop()
    while true do
        local e = table.pack(os.pullEvent())
        current_screen:on_event_raw(e)
    end
end
local server_tasks = {}
local function ui_render_loop()
    while true do
        if env.task_category == "Server" then
            env.tasks = server_tasks
        else
            env.tasks = scheduler.list()
        end
        win.setVisible(false)
        win.clear()
        current_screen:render_to(win)
        win.setVisible(true)
        sleep(0.05)
    end
end


if turtle then
    scheduler.queueTask(STL.Task.new({
        turtleInventoryPoll,
        emptyTurtleThread
    }, "Turtle"))
end
local function externalInventoryPoll()
    while true do
        sleep(sset.get(sset.termInventoryPoll))
        emptyExternalInventory()
    end
end

if invName then
    scheduler.queueTask(STL.Task.new({
        externalInventoryPoll
    }, "External I/O"))
end
local function init()
    if invName then
        clientlib.removeInventory(invName)
    end
    -- listing = clientlib.list()
    server_tasks = clientlib.listTasks()
    create_settings_list()
    apply_settings_sort("")
    apply_sort("")
end

register_screen("listing", "tscreens/listing.lua")
register_screen("request", "tscreens/request.lua")
register_screen("tasks", 'tscreens/tasks.lua')
register_screen("settings", "tscreens/settings.lua")
register_screen("menu", "tscreens/menu.lua")
current_screen = screens.menu

scheduler.queueTask(STL.Task.new({
    ui_event_loop, ui_render_loop
}, "UI"))
scheduler.queueTask(STL.Task.new({
    clientlib.run,
    function()
        clientlib.subscribeToChanges(function(l, fm)
            -- listing = l
            apply_sort(env.search_bar)
        end)
        clientlib.subscribeToServerStart(init)
        clientlib.subscribeToTasks(function(l)
            server_tasks = l
        end)
    end
}, "Clientlib"))
sset.onChangedCallback(function()

end)
scheduler.queueTask(STL.Task.new({
    sset.checkForChangesThread, init,
}, "Settings"))

local ok, err = pcall(scheduler.run)
-- TODO get the error out better!!!
if not ok and err ~= "Terminated" then
    ui.load_screen {
        type = "Screen",
        content = {
            {
                type = "Text",
                x = 1,
                y = 1,
                w = "w",
                h = 1,
                text = "Oops, nterm crashed!",
                theme = {
                    { "fill_color", "red" }
                }
            },
            {
                type = "Text",
                x = 1,
                y = 2,
                w = "w",
                h = "h-2",
                text = err,
                scrollbar = true,
                horizontal_alignment = "left",
                theme = {
                    { "text_color", "red" },
                    { "padding",    { 1, 1, 0, 1 } }
                }
            },
            {
                type = "Button",
                x = 1,
                y = "h",
                w = "w/2",
                h = 1,
                text = "Reboot",
                on_click = function(self)
                    os.reboot()
                end
            },
            {
                type = "Button",
                x = "w/2",
                y = "h",
                w = "w/2",
                h = 1,
                text = "Quit",
                on_click = function(self)
                    self:get_root():stop()
                end
            }
        }
    }:run(win)
end
term.clear()
term.setCursorPos(1, 1)
