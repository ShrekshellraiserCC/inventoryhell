return {
    type = "Screen",
    content = {
        {
            type = "Button",
            x = 1,
            y = "h",
            h = 1,
            w = 1,
            text = "$'\\27'$",
            key = "tab",
            on_click = "$tapi.back$"
        },
        {
            type = "Input",
            x = 2,
            y = "h",
            h = 1,
            w = "w-1",
            ignore_focus = true,
            always_update = true,
            on_change = "$setting_search_change$",
            value = "$setting_search_bar$"
        },
        {
            type = "Table",
            x = 1,
            y = 2,
            w = "w",
            h = "h-2",
            z = 1.1,
            list = "$settings$",
            columns = {
                {
                    "name",
                    "w-11",
                    "Name"
                },
                {
                    "value",
                    "10",
                    "Value"
                }
            },
        }
    }
}
