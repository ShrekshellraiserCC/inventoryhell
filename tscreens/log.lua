---@class SSDTermPluginENV
_ENV = _ENV

local log_screen = tapi.register_screen("log", {
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
        tapi.back_button_template()
    }
})

local log = log_screen:get_widget_by_class("log", 1) --[[@as shrekui.Log]]
tapi.logger.addTarget(function(s)
    log:log(s)
end)
tapi.register_menu_button(3, "Log", "log")
