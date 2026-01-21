local args = { ... }
local enable_host
local enable_debug

for i, v in ipairs(args) do
    if v == "+host" then
        enable_host = true
    elseif v == "+debug" then
        enable_debug = true
    end
end

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
local tapi = {
    sset = sset
}
tapi.scheduler = scheduler

if turtle then
    turtle.select(16)
end

ui.load_global_theme(sset.get(sset.theme))

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
    local list = peripheral.call(invName, "list") or {}
    local size = peripheral.call(invName, "size") or 0
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

function tapi.lock_inventory(state)
    expectingItems = state
end

function tapi.clear_locked_slots()
    lockedTurtleSlots = {}
end

function tapi.empty_inventory()
    emptyTurtleInventory()
end

local tw, th = term.getSize()
local win = window.create(term.current(), 1, 1, tw, th)
term.clear()

---@class SSDTermPluginENV
local env = {
    item = listing[1],
    back_icon = "\27",
    listing = listing,
    search_bar = "",
    setting_search_bar = "",
    turtle = turtle,
    tapi = tapi,
    capi = clientlib,
    task_category = "Server",
    settings = {},
    reboot = os.reboot,
    quit = function()
        scheduler.stop()
    end,
    selected_setting = {},
    textutils = textutils,
    tostring = tostring,
    ipairs = ipairs,
    pairs = pairs,
    debug_overlay = false,
    type = type,
    require = require
}

---@class BackButtonTemplateArgs : ButtonArgs
---@field text string?

---@param override BackButtonTemplateArgs?
---@return ButtonArgs
env.back_button_template = function(override)
    local t = {
        type = "Button",
        x = 1,
        y = "h",
        h = 1,
        w = 1,
        text = "\27",
        key = "tab",
        on_click = "$tapi.back$",
        horizontal_alignment = "left",
        id = "back-button"
    }
    if override then
        for k, v in pairs(override) do
            t[k] = v
        end
    end
    return t
end

env.open_screen_button = function(self)
    tapi.open_screen(self.meta)
end
local sort = {}
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
---@type string[]
local screenList = {}
---@param name string
---@param screen Screen
local function register_screen_raw(name, screen)
    screens[name] = screen
    screen.meta = name
    screenList[#screenList + 1] = name
    return screen
end
---@param name string
---@param layout table
local function register_screen(name, layout)
    layout.content[#layout.content + 1] = {
        type = "Text",
        x = "w+1-" .. env.capi.statusWidth,
        y = 1,
        w = env.capi.statusWidth,
        h = 1,
        z = 1,
        class = "heading",
        horizontal_alignment = "right",
        text = "$capi.statusString$"
    }
    layout.content[#layout.content + 1] = {
        type = "Text",
        x = 1,
        y = 1,
        w = "w",
        h = 1,
        z = -1,
        class = "heading",
        text = ""
    }
    local screen = ui.load_screen(layout, env)
    return register_screen_raw(name, screen)
end
tapi.register_screen = register_screen

register_screen("debug", {
    type = "Screen",
    content = {
        {
            type = "Text",
            h = 1,
            text = "Debug",
            class = "heading"
        },
        {
            type = "Table",
            x = 1,
            y = 2,
            w = "w",
            h = "h-2",
            z = 1.1, -- Get events before the focused Input
            list = screenList,
            columns = {
                {
                    ".",
                    "w",
                    "Name"
                },
            },
            on_select = function(self, value)
                tapi.open_screen(value)
            end
        },
        env.back_button_template()
    }
})

local menu_layout = {
    type = "Screen",
    content = {
        {
            type = "Frame",
            content = {},
            layout = "hbox",
            w = "w",
            h = "h/2-1",
            y = 2,
            z = 0.9
        },
        {
            type = "Frame",
            content = {},
            layout = "hbox",
            h = "h/2-2",
            y = "h/2+1",
            z = 0.9
        },
        {
            type = "Frame",
            content = {},
            layout = "hbox",
            h = 1,
            y = "h",
            z = 3
        },
        {
            type = "Text",
            h = 1,
            text = "nterm",
            horizontal_alignment = "left",
            class = "heading"
        },
        {
            type = "Frame",
            x = 1,
            y = "h-10",
            w = "w",
            h = 11,
            z = 2,
            class = "submenu",
            hidden = "$not power_menu_open$",
            content = {
                {
                    type = "Button",
                    x = 1,
                    y = 1,
                    h = 3,
                    w = "w",
                    text = "Reboot All",
                    on_click = "$capi.rebootAll$"
                },
                {
                    type = "Button",
                    x = 1,
                    y = 4,
                    h = 3,
                    w = "w",
                    text = "Force Reboot Server",
                    on_click = "$capi.forceRebootServer$"
                },
                {
                    type = "Button",
                    x = 1,
                    y = 7,
                    h = 3,
                    w = "w",
                    text = "Reboot This",
                    on_click = "$reboot$"
                }
            }
        }
    }
}

---Add a button to the Menu screen on the row y.
---This MUST be called before the Menu screen gets initialized.
---@param y integer
---@param label string
---@param screen string?
---@return ButtonArgs
local function register_menu_button(y, label, screen)
    assert(y >= 1 and y <= 3, "y out of range.")
    local t = menu_layout.content[y].content
    t[#t + 1] = {
        type = "Button",
        text = label,
        on_click = screen and ("$tapi.open_screen('%s')$"):format(screen)
    }
    return t[#t]
end
tapi.register_menu_button = register_menu_button

do
    local power_menu = register_menu_button(3, "Power")
    power_menu.horizontal_alignment = "left"
    power_menu.pressed = "$power_menu_open$"
    power_menu.toggle = true
    power_menu.key = "tab"

    if enable_debug then
        register_menu_button(3, "Debug", "debug")
    end
end

---@type Screen
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
        local tid = os.startTimer(0.05)
        if env.task_category == "Server" then
            env.tasks = server_tasks
        else
            env.tasks = scheduler.list()
        end
        win.setVisible(false)
        win.clear()
        current_screen:render_to(win)
        -- local b = current_screen._box
        -- b.overlay = env.debug_overlay
        -- b.profiler.collapse("shrekbox", false)
        win.setTextColor(colors.white)
        win.setBackgroundColor(colors.blue)
        win.setVisible(true)
        -- b.profiler.start_yield("sleep")
        repeat until select(2, os.pullEvent("timer")) == tid
        -- b.profiler.end_yield("sleep")
    end
end

clientlib.setLogger(function(s, ...)
    env.logged = s:format(...)
end)

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
    if invName and peripheral.wrap(invName) then
        clientlib.removeInventory(invName)
    end
    listing = clientlib.list()
    server_tasks = clientlib.listTasks()
    apply_sort("")
end

local function load_screen(fn)
    local f = assert(fs.open(sset.getInstalledPath(fn), "r"))
    local s = f.readAll()
    f.close()
    assert(load(s, fn, "t", env))()
end

load_screen("tscreens/listing.lua")
load_screen("tscreens/tasks.lua")
load_screen("tscreens/settings.lua")
load_screen("tscreens/about.lua")

if enable_host then
    local host = require("host")
    scheduler.queueTask(STL.Task.new({ host.run }, "Host"))
    host.screen:add_widget(ui.classes.Button:new {
        x = 1,
        y = "h",
        h = 1,
        w = 1,
        text = "\27",
        key = "tab",
        on_click = tapi.back,
        horizontal_alignment = "left",
        id = "back-button"
    })
    register_screen_raw("host", host.screen)
    register_menu_button(1, "Host", "host")
end

do
    local quit = register_menu_button(3, "Quit")
    quit.horizontal_alignment = "right"
    quit.on_click = env.quit
end

register_screen("menu", menu_layout)
current_screen = screens.menu


scheduler.queueTask(STL.Task.new({
    init
}, "Init"))
scheduler.queueTask(STL.Task.new({
    ui_event_loop, ui_render_loop
}, "UI"))
scheduler.queueTask(STL.Task.new({
    clientlib.run,
    function()
        clientlib.subscribeTo({
            changes = function(l, fm)
                listing = l
                apply_sort(env.search_bar)
            end,
            start = init,
            tasks = function(l)
                server_tasks = l
            end
        })
    end
}, "Clientlib"))
scheduler.queueTask(STL.Task.new({
    sset.checkForChangesThread
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
