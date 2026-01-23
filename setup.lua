local sset = require "libs.sset"
local ui = require "libs.shrekui"

ui.load_global_theme(sset.get(sset.theme))
local win = window.create(term.current(), 1, 1, term.getSize())

local env = {}
env.confirm_screen_text = ""
env.confirm_text = "Continue ->"
env.cancel_text = "Cancel"

local header = {
    type = "Text",
    text = "SSD Setup",
    h = 1,
    theme = {
        { "fill_color", "blue" }
    }
}
---@param s string
---@param ... shrekui.WidgetArgs
local function generic_n_button_screen(s, ...)
    local screen = {
        type = "Screen",
        content = {
            header,
            {
                type = "Text",
                y = 2,
                h = "h-2",
                text = s,
                theme = {
                    { "padding", 1 }
                }
            },
        }
    }
    local t = { ... }
    local n = #t
    for i, v in ipairs(t) do
        local b = {
            type = "Button",
            x = ("(w/%d)*(%d-1)+1"):format(n, i),
            y = "h",
            w = ("(w/%d)"):format(n),
            h = 1,
            text = v.text
        }
        screen.content[#screen.content + 1] = b
        for k, v2 in pairs(v) do
            b[k] = v2
        end
    end
    return screen
end
local confirm_screen_r = generic_n_button_screen("$confirm_screen_text$",
    { text = "$cancel_text$", on_click = "$self:get_root():stop(false)$" },
    { text = "$confirm_text$", on_click = "$self:get_root():stop(true)$" })
confirm_screen_r.env = env
local confirm_screen = ui.load_screen(confirm_screen_r)
local function show_confirm_screen(text, confirm, cancel)
    env.confirm_screen_text = text
    env.confirm_text = confirm or env.confirm_text
    env.cancel_text = cancel or env.cancel_text
    return confirm_screen:run(win)
end

local ok = show_confirm_screen([[
This computer has been booted on a network with SSD installed.

Click Continue or press Enter to proceed with SSD setup.

This will overwrite startup and may delete local files. Click Cancel or press Tab to exit.
]])

local function exit_message(s)
    term.clear()
    term.setCursorPos(1, 1)
    print(s or "Cancelled SSD setup.")
end

if not ok then
    exit_message()
    return
end

local general_host_prompt = [[


You can also run a terminal alongside the host software by selecting the Host + Term option.
]]

local function prompt_host(no_host)
    local s = no_host and "There is no SSD host configured, would you like to use this computer as the SSD host?" or
        "An SSD host already exists. By continuing you will be overwriting the global settings for the SSD host. Are you sure you want to do this?"
    local raw = generic_n_button_screen(s .. general_host_prompt,
        { text = "No", on_click = "$self:get_root():stop(false)$" },
        { text = "Yes (+Term)", on_click = "$self:get_root():stop('host+term')$" },
        { text = "Yes", on_click = "$self:get_root():stop('host')$" })
    raw.env = env
    return ui.load_screen(raw):run(win)
end

local function apply_startup_files()
    if fs.exists("startup.lua") then
        if show_confirm_screen("The file startup.lua already exists, do you want to overwrite this?", "Yes", "No") then
            fs.delete("startup.lua")
        end
    end
    if not fs.exists("startup.lua") then
        fs.copy(sset.getInstalledPath "pstartup.lua", "startup.lua")
    end
    os.reboot()
end

local function apply_host_setting(h)
    sset.set(sset.program, h)
    sset.set(sset.hid, os.getComputerID())
    local modem
    while not (modem and modem.getNameLocal()) do
        modem = peripheral.find("modem", function(name, wrapped)
            return not wrapped.isWireless()
        end) --[[@as WiredModem?]]
        if not modem then
            if not show_confirm_screen(
                    "The SSD host must be attached to the wired network, please right click the wired modem adjacent to this computer and press continue.") then
                return false
            end
        end
    end
    sset.set(sset.hmn, modem.getNameLocal())
    apply_startup_files()
end

local function apply_term_settings()
    sset.set(sset.program, "term")
    apply_startup_files()
end

local option_str = [[What purpose should this computer serve?]]

local all_options_r = {
    type = "Screen",
    content = {
        header,
        {
            type = "Text",
            text = option_str,
            y = 2,
            h = "(h-2)/2",
        },
        {
            type = "Frame",
            y = "(h-2)/2+2",
            h = "(h-3)/2",
            layout = "hbox",
            content = {}
        },
        {
            type = "Button",
            text = "Cancel",
            y = "h",
            h = 1,
            on_click = "$self:get_root():stop(false)$"
        }
    }
}


local option_select = {
    host = function()
        local h = prompt_host(sset.get(sset.hid) == nil)
        if h then
            apply_host_setting(h) -- reboots on success
            exit_message()
            return
        end
    end,
    term = apply_term_settings
}

local function option_button_selected(self)
    self:get_root():stop(self.meta)
end

local function add_option(label, meta)
    local ctable = all_options_r.content[3].content
    ctable[#ctable + 1] = {
        type = "Button",
        text = label,
        meta = meta,
        on_click = option_button_selected
    }
end
add_option("Term", "term")
add_option("Host", "host")

if sset.get(sset.hid) == nil then
    option_select.host()
    -- passthrough if they cancelled, maybe the user wants to access the rest of the options?
end

local options_screen = ui.load_screen(all_options_r)
while true do
    local option = options_screen:run(win)
    if not option then break end
    option_select[option]()
end
term.clear()
term.setCursorPos(1, 1)
print("Cancelled SSD Setup.")
