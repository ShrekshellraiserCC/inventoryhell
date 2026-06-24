local shrexpect = require "libs.shrexpect"
local args = { ... }
local enable_host
local enable_debug

package.path = package.path .. ";libs/?.lua"

local ui = require "libs.shrekui"
local clientlib = require "libs.clientlib"
local sset = require "libs.sset"
local STL = require "libs.STL"
local ID = require "libs.ItemDescriptor"
local slogger = require "libs.slogger"

local logger = slogger.new("CLIENT", "clientlog.txt")
local clog = logger.logger("clib")

for i, v in ipairs(args) do
    if v == "+host" then
        enable_host = true
        clog.info("Enabled host.")
    elseif v == "+debug" then
        enable_debug = true
    end
end

clientlib.setLogger(clog)
if sset.get(sset.debug) then
    enable_debug = true
    clog.info("Enabled debug.")
end

clientlib.open()
local lname = turtle and assert(clientlib.modem.getNameLocal(), "This device is not connected via this modem!")
local invName = sset.get(sset.termInventory)

local expectingItems = false
local debounceDelay = sset.get(sset.debounceDelay)
local debounceTid = os.startTimer(debounceDelay)

---@class SSDTermAPI
local tapi = {
    sset = sset,
}
tapi.logger = logger
local scheduler = STL.Scheduler(logger.logger("STL"))
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
    os.queueEvent("turtle_inventory")
end

function tapi.inventory_size()
    if turtle then
        return 16
    elseif invName then
        return peripheral.call(invName, "size")
    end
    return 0
end

function tapi.list_inventory()
    if turtle then
        local list = {}
        for i = 1, 16 do
            if turtle.getItemCount(i) > 0 then
                list[i] = turtle.getItemDetail(i, true)
            end
        end
        return list
    elseif invName then
        local l = peripheral.call(invName, "list")
        for i, v in pairs(l) do
            l[i] = peripheral.call(invName, "getItemDetail", i)
        end
        return l
    end
    return {}
end

function tapi.empty_inventory()
    if turtle then
        emptyTurtleInventory()
    elseif invName then
        emptyExternalInventory()
    end
end

local tw, th = term.getSize()
local win = window.create(term.current(), 1, 1, tw, th)
term.clear()

---@class SSDTermPluginENV
local env = setmetatable({
    back_icon = "\27",
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
    debug_overlay = false,
}, { __index = _ENV })

---@class BackButtonTemplateArgs : shrekui.ButtonArgs
---@field text string?

---@param override BackButtonTemplateArgs?
---@return shrekui.ButtonArgs
function tapi.back_button_template(override)
    local t = {
        type = "Button",
        h = 1,
        w = 2,
        text = "\27",
        key = "tab",
        on_click = "$tapi.back$",
        horizontal_alignment = "left",
        id = "back-button",
        class = "heading"
    }
    if override then
        for k, v in pairs(override) do
            t[k] = v
        end
    end
    return t
end

env.back_button_template = tapi.back_button_template -- BACK COMPAT TODO REPLACE THIS

---@param text string
---@param override BackButtonTemplateArgs?
function tapi.header_template(text, override)
    local t = {
        type = "Text",
        class = "heading",
        h = 1,
        text = text
    }
    if override then
        for k, v in pairs(override) do
            t[k] = v
        end
    end
    return t
end

---@param item CCItemInfo
function tapi.request(item, count)
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

function env.craft()
    turtle.craft()
end

function env.depot()
    lockedTurtleSlots = {}
    emptyTurtleInventory()
end

local w, h = term.getSize()
env.notification_w = w - 6
env.notification_hidden = true
env.notification_show_time = 0
env.notification_timeout = 0
local notification_timout_timer
---@param type string
---@param s string
local function show_notification(type, s)
    env.notification_w = term.getSize() - 6
    env.notification_hidden = false
    env.notification_type = type
    env.notification_text = s
    local t = os.epoch("utc")
    env.notification_show_time = t
    env.notification_timeout = sset.get(sset.notificationTimeout)
    notification_timout_timer = os.startTimer(env.notification_timeout / 1000)
end
local function dismiss_notification()
    env.notification_hidden = true
end
local function notification_timeout_thread()
    while true do
        local e, id = os.pullEvent("timer")
        if id == notification_timout_timer then
            dismiss_notification()
        end
    end
end
---@param type string
---@param text string
---@param ... any
function tapi.notification(type, text, ...)
    show_notification(type, text:format(...))
end

---@type table<string,shrekui.Screen>
local screens = {}
---@type table<string,function>
local screenCallbacks = {}
---@type string[]
local screenList = {}
---@param name string
---@param screen shrekui.Screen
---@param callback function?
local function register_screen_raw(name, screen, callback)
    screens[name] = screen
    screen.meta = name
    screenList[#screenList + 1] = name
    screenCallbacks[name] = callback
    return screen
end

local status_str_lookup = {
    UNKNOWN = "???",
    MISSING = "gone...",
    CONNECTED = "OK"
}

function tapi.get_status_string()
    local info = env.capi.getStatus()
    local infostr = status_str_lookup[info.state] or info.string
    local arrow = env.status_dropdown and "\x1e" or "\x1f"
    if info.state == "STARTING" then
        return info.string .. arrow
    end
    local etc = expectingItems and "L" or " "
    return ("%s [%s]%s%s"):format(infostr, etc, info.throbber, arrow)
end

env.status_dropdown = false
local apply_screen_template
do
    local status_text = {
        type = "Button",
        x = "w+1-" .. env.capi.statusWidth,
        y = 1,
        w = env.capi.statusWidth,
        h = 1,
        z = 1,
        class = "heading",
        id = "status-dropdown-button",
        horizontal_alignment = "right",
        text = "$tapi.get_status_string()$",
        on_click = function(self)
            env.status_dropdown = not env.status_dropdown
        end,
        toggle = true
    }
    local status_dropdown = {
        type = "Frame",
        x = "w+1-" .. env.capi.statusWidth,
        y = 2,
        h = 5,
        border_thickness = 1,
        z = 15,
        lz_offset = 100,
        content = {
            {
                type = "Checkbox",
                text = "Lock Import",
                h = 1,
                id = "lock-import-checkbox",
                on_click = function(self)
                    tapi.lock_inventory(not expectingItems)
                end
            },
            {
                type = "Button",
                text = "Clear Import",
                h = 1,
                y = 2,
                on_click = function(self)
                    tapi.clear_locked_slots()
                end
            }
        },
        hidden = "$not status_dropdown$"
    }
    local heading_fill = {
        type = "Text",
        x = 1,
        y = 1,
        w = "w",
        h = 1,
        z = -1,
        class = "heading",
        text = ""
    }
    local notification_frame = {
        type = "Frame",
        x = 3,
        y = "h-4",
        w = "w-4",
        h = 3,
        lz_offset = 100,
        z = 100,
        content = {
            {
                type = "Text",
                y = 1,
                h = 1,
                w = "w-3",
                text = "$notification_type$",
                class = "notification"
            },
            {
                type = "Text",
                y = 2,
                h = 1,
                w = "w-3",
                text = "$notification_text$",
                class = "notification"
            },
            {
                type = "Text",
                y = 3,
                h = 1,
                w = "w-3",
                text =
                "$('\x7f'):rep(math.min(notification_w,math.floor(notification_w * (os.epoch'utc'-notification_show_time)/notification_timeout)))$",
                id = "notification-progress",
                class = "notification",
                horizontal_alignment = "left"
            },
            {
                type = "Button",
                y = 1,
                h = 3,
                x = "w-2",
                w = 3,
                text = "X",
                class = "notification",
                on_click = dismiss_notification
            }
        },
        hidden = "$notification_hidden$",
        class = "notification"
    }
    function apply_screen_template(content)
        content[#content + 1] = status_text
        content[#content + 1] = status_dropdown
        content[#content + 1] = heading_fill
        content[#content + 1] = notification_frame
    end
end

---@param name string
---@param layout table
---@param callback function? Called when the screen is opened
---@param penv table? Parent environment, shadows the normal screen environment.
---@see SSDTermAPI
local function register_screen(name, layout, callback, penv)
    apply_screen_template(layout.content)
    local senv = penv and setmetatable(penv, {
        __index = env,
        __newindex = function(t, k, v)
            if env[k] ~= nil then
                env[k] = v
            end
            rawset(penv, k, v)
        end
    }) or env
    local screen = ui.load_screen(layout, senv)
    return register_screen_raw(name, screen, callback)
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
        env.back_button_template(),
        {
            type = "Button",
            y = "h",
            on_click = function()
                tapi.notification("john", "This is a notification...")
            end
        }
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
            z = 3,
            lz_offset = 1
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
            lz_offset = 2,
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
                    on_click = function()
                        env.utils.confirm_screen("Reboot All",
                            "Are you sure you want to reboot all computers on the network?", env.capi.rebootAll)
                    end,
                    class = "warning-button"
                },
                {
                    type = "Button",
                    x = 1,
                    y = 4,
                    h = 3,
                    w = "w",
                    text = "Force Reboot Server",
                    on_click = function()
                        env.utils.confirm_screen("Force Reboot",
                            "Are you sure you want to force reboot the host computer?", env.capi.forceRebootServer)
                    end,
                    class = "danger-button"
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
---@return shrekui.ButtonArgs
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

local function update_button_status(screen)
    local status = screen:get_widget_by_id("status-dropdown-button")
    if status then
        status:set_pressed(env.status_dropdown)
    end
    local lock_import = screen:get_widget_by_id("lock-import-checkbox")
    if lock_import then
        lock_import:set_pressed(expectingItems)
    end
end

---@type shrekui.Screen
local current_screen
---@type shrekui.Screen[]
local screen_stack = {}
---@param name string
function tapi.open_screen(name)
    shrexpect({ "string" }, { name })
    current_screen:reset_held()
    screen_stack[#screen_stack + 1] = current_screen.meta
    current_screen = screens[name]
    assert(current_screen, ("No screen with ID %s"):format(name))
    update_button_status(current_screen)
    if screenCallbacks[name] then
        screenCallbacks[name](current_screen)
    end
end

function tapi.back()
    current_screen:reset_held()
    local top = table.remove(screen_stack)
    if top then
        current_screen = screens[top]
        update_button_status(current_screen)
    end
end

local function ui_event_loop()
    while true do
        local e = table.pack(os.pullEvent())
        if e[1] == "term_resize" then
            win.reposition(1, 1, term.getSize())
            current_screen:calculate_shape()
        end
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
        win.setTextColor(colors.white)
        win.setBackgroundColor(colors.blue)
        win.setVisible(true)
        repeat until select(2, os.pullEvent("timer")) == tid
    end
end

if turtle then
    scheduler.queueTask(STL.Task.new({
        turtleInventoryPoll,
        emptyTurtleThread
    }, "Turtle", true))
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
    }, "External I/O", true))
end
local function init()
    if invName and peripheral.wrap(invName) then
        clientlib.removeInventory(invName)
    end
    server_tasks = clientlib.listTasks()
end

local function load_screen(fn)
    local f = assert(fs.open(sset.getInstalledPath(fn), "r"))
    local s = f.readAll()
    f.close()
    assert(load(s, fn, "t", env))()
end

load_screen("tscreens/utils.lua")
load_screen("tscreens/listing.lua")
load_screen("tscreens/tasks.lua")
load_screen("tscreens/settings.lua")
load_screen("tscreens/about.lua")
load_screen("tscreens/help.lua")
load_screen("tscreens/log.lua")
load_screen("tscreens/crafting.lua")

local host
if enable_host then
    host = require("host")
    scheduler.queueTask(STL.Task.new({ host.run }, "Host", true))
    host.screen:add_widget(ui.classes.Button:new(env.back_button_template {
        on_click = env.tapi.back
    }))
    register_screen_raw("host", host.screen)
    register_menu_button(1, "Host", "host")
end

if sset.get(sset.quitButton) then
    local quit = register_menu_button(3, "Quit")
    quit.on_click = env.quit
end
-- right align whatever button is furthest right
do
    local row = menu_layout.content[3].content
    row[#row].horizontal_alignment = "right"
end

register_screen("menu", menu_layout)
current_screen = screens.menu

clientlib.subscribeTo({
    start = init,
    tasks = function(l)
        server_tasks = l
    end,
    notifications = function(type, text)
        tapi.notification(type, text)
    end
})

scheduler.queueTask(STL.Task.new({
    ui_event_loop, ui_render_loop, notification_timeout_thread
}, "UI", true))
scheduler.queueTask(STL.Task.new({
    clientlib.run
}, "Clientlib", true))
scheduler.queueTask(STL.Task.new({
    sset.checkForChangesThread
}, "Settings", true))
scheduler.queueTask(STL.Task.new({
    tapi.logger.thread
}, "Logger", true))
scheduler.queueTask(STL.Task.new({
    init
}, "Init", true))


local ok, err = pcall(scheduler.run)
-- TODO get the error out better!!!
tapi.logger.flush()
win.clear()
win.setVisible(true)
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
