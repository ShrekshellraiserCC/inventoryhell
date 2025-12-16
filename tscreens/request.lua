return {
    type = "Screen",
    content = {
        {
            type = "Text",
            h = 1,
            text = "nterm",
            horizontal_alignment = "left",
            id = "header",
            theme = {
                { "fill_color", "blue" }
            }
        },
        {
            type = "Button",
            x = 1,
            y = "h",
            h = 1,
            w = 1,
            text = "$back_icon$",
            key = "tab",
            on_click = "$tapi.back$"
        },
        {
            type = "Text",
            x = 1,
            y = 2,
            h = 1,
            w = "w-8",
            text = "$item.displayName$",
            horizontal_alignment = "left"
        },
        {
            type = "Text",
            x = "w-7",
            y = 2,
            h = 1,
            w = "8",
            text = "$item.count$"
        },
        {
            type = "Text",
            x = 1,
            y = 3,
            w = "w",
            h = "h-3",
            text = "$item.detail$",
            horizontal_alignment = "left",
            scrollbar = true,
            theme = {
                { "padding", 1 }
            }
        },
        {
            type = "Button",
            x = 2,
            y = "h",
            h = 1,
            w = 7,
            text =
            "$self:is_held(keys.leftShift) and '[A  64]' or self:is_held(keys.leftCtrl) and '[A   1]' or '[A   8]'$",
            meta = 1,
            on_click = "$submit_request$",
            key = "a"
        },
        {
            type = "Button",
            x = 9,
            y = "h",
            h = 1,
            w = 7,
            text =
            "$self:is_held(keys.leftShift) and '[S 128]' or self:is_held(keys.leftCtrl) and '[S   2]' or '[S  16]'$",
            meta = 2,
            on_click = "$submit_request$",
            key = "s"
        },
        {
            type = "Button",
            x = 16,
            y = "h",
            h = 1,
            w = 7,
            text =
            "$self:is_held(keys.leftShift) and '[D 256]' or self:is_held(keys.leftCtrl) and '[D   4]' or '[D  32]'$",
            meta = 4,
            on_click = "$submit_request$",
            key = "d"
        },
        {
            type = "Button",
            x = 23,
            y = "h",
            h = 1,
            w = 7,
            text =
            "$self:is_held(keys.leftShift) and '[F 512]' or self:is_held(keys.leftCtrl) and '[F   8]' or '[F  64]'$",
            meta = 8,
            on_click = "$submit_request$",
            key = "f"
        },
        {
            type = "Button",
            x = "w-6",
            y = "h",
            h = 1,
            w = 7,
            text = "[Enter]",
            meta = 8,
            on_click = "$submit_request$",
            key = "enter"
        }
    }
}
