_ENV = _ENV --[[@as SSDTermPluginENV]]
_ENV.tapi.register_screen("menu", {
    type = "Screen",
    content = {
        {
            type = "Text",
            h = 1,
            text = "nterm",
            horizontal_alignment = "left",
            class = "heading"
        },
        {
            type = "Button",
            w = "w",
            h = "h/2-1",
            y = 2,
            text = "Listing",
            on_click = "$tapi.open_screen('listing')$"
        },
        {
            type = "Button",
            w = "w/2",
            h = "h/2-2",
            x = "w/2+1",
            y = "h/2+1",
            text = "Settings",
            on_click = "$tapi.open_screen('settings')$"
        },
        {
            type = "Button",
            w = "w/2",
            h = "h/2-2",
            y = "h/2+1",
            text = "Tasks",
            on_click = "$tapi.open_screen('tasks')$"
        },
        {
            type = "Button",
            w = 6,
            h = 1,
            x = "w-5",
            y = "h",
            text = "Quit",
            on_click = "$quit$"
        },
        {
            type = "Button",
            w = 6,
            h = 1,
            x = 1,
            y = "h",
            z = 3,
            text = "Power",
            pressed = "$power_menu_open$",
            toggle = true,
            key = "tab"
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
        },
        {
            type = "Frame",
            x = "w-9",
            y = 2,
            w = 8,
            h = 3,
            z = 1.9,
            hidden = true,
            layout = "h",
            content = {
                {
                    type = "Button",
                    text = "Debug Overlay",
                    on_click = "$function() capi.list() end$"
                }
            }
        }
    }
})
