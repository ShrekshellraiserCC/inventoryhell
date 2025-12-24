_ENV = _ENV --[[@as SSDTermPluginENV]]

local function smart_reboot()
    if _ENV.selected_setting.raw.side == "local" then
        _ENV.reboot()
    end
    _ENV.capi.rebootAll()
end

return {
    type = "Screen",
    content = {
        {
            type = "Text",
            h = 1,
            text = "Reboot?",
            horizontal_alignment = "left",
            id = "header",
            theme = {
                { "fill_color", "blue" }
            }
        },
        {
            type = "Text",
            y = 2,
            h = "h-2",
            text = "The setting you changed requires a reboot, would you like to reboot now?"
        },
        {
            type = "Button",
            x = 1,
            y = "h",
            w = "w/2",
            h = 1,
            text = "No",
            key = "tab",
            on_click = "$tapi.back$r"
        },
        {
            type = "Button",
            x = "w/2+1",
            y = "h",
            w = "w/2",
            h = 1,
            text = "Yes",
            key = "enter",
            on_click = smart_reboot
        }
    }
}
