local sset = require "libs.sset"
local update = require "libs.update"
_ENV = _ENV --[[@as SSDTermPluginENV]]

local hash = _ENV.tapi.sset.get(_ENV.tapi.sset.version)
local nhash = "NOTGOTTENYET"
local about_str = ([[
ShrekStorageDrive Preview
Commit: %s
This is an EARLY preview of SSD and may not represent the final product.
I am looking for UI/UX feedback and suggestions.
Report bugs to the inventoryhell repo.
]]):format(hash)


local function check_for_update()
    nhash = update.get_hash()
    if hash == nhash then
        _ENV.tapi.open_screen("no_update")
    else
        _ENV.tapi.open_screen("update_available")
    end
end

local about_layout = {
    type = "Screen",
    content = {
        {
            type = "Text",
            h = 1,
            text = "About",
            class = "heading"
        },
        {
            type = "Text",
            y = 2,
            h = "h-2",
            scrollbar = true,
            text = about_str,
            horizontal_alignment = "left",
        },
        {
            type = "Button",
            h = 1,
            y = "h",
            x = 2,
            w = "w-1",
            text = "Check for Update",
            on_click = check_for_update
        },
        _ENV.back_button_template()
    }
}
_ENV.tapi.register_screen("about", about_layout)
_ENV.tapi.register_menu_button(3, "About", "about")



---@type Log
local log
---@type Button
local back_button
local function do_update()
    back_button.hidden = true
    _ENV.tapi.open_screen("updating")
    update.set_install_dir(sset.get(sset.installDir))
    update.do_install(function(s) log:log(s) end)
    back_button.hidden = false
end

_ENV.tapi.register_screen("no_update", {
    type = "Screen",
    content = {
        {
            type = "Text",
            y = 2,
            h = "h-2",
            text = "You have the latest version of SSD published."
        },
        _ENV.back_button_template {
            w = "w/2"
        },
        {
            type = "Button",
            y = "h",
            h = 1,
            x = "w/2+1",
            w = "w/2",
            text = "Force Install",
            horizontal_alignment = "right",
            on_click = do_update
        }
    }
})

_ENV.tapi.register_screen("update_available", {
    type = "Screen",
    content = {
        {
            type = "Text",
            y = 2,
            h = "h-2",
            text = "There is an update available, do you want to install it?"
        },
        _ENV.back_button_template {
            w = "w/2",
            text = "Cancel"
        },
        {
            type = "Button",
            y = "h",
            h = 1,
            x = "w/2+1",
            w = "w/2",
            text = "Install",
            horizontal_alignment = "right",
            on_click = do_update
        }
    }
})


local screen = _ENV.tapi.register_screen("updating", {
    type = "Screen",
    content = {
        {
            type = "Text",
            h = 1,
            text = "SSD Updating..."
        },
        {
            type = "Log",
            y = 2,
            h = "h-2",
            id = "update-log"
        },
        _ENV.back_button_template {
            hidden = true,
            w = "w",
            text = "Reboot All",
            on_click = _ENV.capi.rebootAll
        }
    }
})
log = screen:get_widget_by_id("update-log") --[[@as Log]]
back_button = screen:get_widget_by_id("back-button") --[[@as Button]]
