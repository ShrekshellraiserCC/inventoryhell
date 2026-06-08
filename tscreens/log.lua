---@class SSDTermPluginENV
_ENV = _ENV

local log_screen = _ENV.tapi.register_screen("log", {
    type = "Screen",
    content = {
        {
            type = "Text",
            h = 1,
            text = "Log",
            class = "heading"
        },
        {
            type = "Log",
            y = 2,
            h = "h-1",
            class = "log"
        },
        _ENV.back_button_template()
    }
})

local log = log_screen:get_widget_by_class("log", 1) --[[@as shrekui.Log]]
_ENV.capi.setLogger(function(s, ...)
    log:flog(s, ...)
end)
_ENV.logger = log
_ENV.tapi.register_menu_button(3, "c.log", "log")
