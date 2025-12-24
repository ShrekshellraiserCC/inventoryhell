_ENV = _ENV --[[@as SSDTermPluginENV]]


local function save_setting(self)
    local setting = _ENV.selected_setting.raw --[[@as RegisteredSetting]]
    if setting.side ~= "global" then
        ---@type string?
        local evalue_l = _ENV.selected_setting_evalue_l
        if evalue_l == "nil" then evalue_l = nil end
        _ENV.tapi.sset.set(setting, evalue_l, true)
    end
    ---@type string?
    local evalue_g = _ENV.selected_setting_evalue_g
    if evalue_g == "nil" then evalue_g = nil end
    _ENV.tapi.sset.set(setting, evalue_g)
    _ENV.tapi.sset.checkForChanges()
    _ENV.tapi.back()
    if setting.requiresReboot then
        _ENV.tapi.open_screen("setting_reboot")
    end
end
local function default_setting(self)
    _ENV[self.meta] = "nil"
end

return {
    type = "Screen",
    content = {
        {
            type = "Text",
            h = 1,
            text = "Edit Setting",
            horizontal_alignment = "left",
            id = "header",
            theme = {
                { "fill_color", "blue" }
            }
        },
        {
            type = "Frame",
            x = 1,
            y = 2,
            w = "w",
            h = "h-2",
            content = {
                {
                    type = "Text",
                    x = 1,
                    y = 1,
                    w = 10,
                    h = 1,
                    text = "Name |",
                    horizontal_alignment = "right"
                },
                {
                    type = "Text",
                    x = 12,
                    y = 1,
                    w = "w-12",
                    h = 1,
                    text = "$selected_setting.name$",
                    horizontal_alignment = "left"
                },
                {
                    type = "Text",
                    x = 1,
                    y = 2,
                    w = 10,
                    h = 1,
                    text = "Type |",
                    horizontal_alignment = "right"
                },
                {
                    type = "Text",
                    x = 12,
                    y = 2,
                    w = "w-12",
                    h = 1,
                    text = "$selected_setting.raw.type$",
                    horizontal_alignment = "left"
                },
                {
                    type = "Text",
                    x = 1,
                    y = 3,
                    w = 10,
                    h = 1,
                    text = "Side |",
                    horizontal_alignment = "right"
                },
                {
                    type = "Text",
                    x = 12,
                    y = 3,
                    w = "w-12",
                    h = 1,
                    text = "$selected_setting.raw.side$",
                    horizontal_alignment = "left"
                },
                {
                    type = "Text",
                    x = 1,
                    y = 4,
                    w = 10,
                    h = 1,
                    text = "Global |",
                    horizontal_alignment = "right"
                },
                {
                    type = "Input",
                    x = 12,
                    y = 4,
                    w = "w-13",
                    h = 1,
                    value = "$selected_setting_evalue_g$",
                    hidden = "$selected_setting.raw.options or selected_setting.raw.side == 'local'$"
                },
                {
                    type = "Dropdown",
                    x = 12,
                    y = 4,
                    w = "w-13",
                    h = 1,
                    options = "$selected_setting.raw.options or {}$",
                    value = "$selected_setting_evalue_g$",
                    hidden = "$not selected_setting.raw.options or selected_setting.raw.side == 'local'$"
                },
                {
                    type = "Button",
                    x = "w-1",
                    y = 4,
                    w = 1,
                    h = 1,
                    text = "x",
                    hidden = "$selected_setting.raw.side == 'local'$",
                    meta = "selected_setting_evalue_g",
                    on_click = default_setting
                },
                {
                    type = "Text",
                    x = 1,
                    y = 5,
                    w = 10,
                    h = 1,
                    text = "Local |",
                    horizontal_alignment = "right"
                },
                {
                    type = "Input",
                    x = 12,
                    y = 5,
                    w = "w-13",
                    h = 1,
                    value = "$selected_setting_evalue_l$",
                    hidden = "$selected_setting.raw.options or selected_setting.raw.side == 'global'$"
                },
                {
                    type = "Dropdown",
                    x = 12,
                    y = 5,
                    w = "w-13",
                    h = 1,
                    options = "$selected_setting.raw.options or {}$",
                    value = "$selected_setting_evalue_l$",
                    hidden = "$not selected_setting.raw.options or selected_setting.raw.side == 'global'$"
                },
                {
                    type = "Button",
                    x = "w-1",
                    y = 5,
                    w = 1,
                    h = 1,
                    text = "x",
                    hidden = "$selected_setting.raw.side == 'global'$",
                    meta = "selected_setting_evalue_l",
                    on_click = default_setting
                },
                {
                    type = "Text",
                    x = 1,
                    y = 6,
                    w = 10,
                    h = 1,
                    text = "Value |",
                    horizontal_alignment = "right"
                },
                {
                    type = "Text",
                    x = 12,
                    y = 6,
                    w = "w-12",
                    h = 1,
                    text = "$selected_setting.value$",
                    horizontal_alignment = "left"
                },
                {
                    type = "Text",
                    x = 1,
                    y = 7,
                    w = 10,
                    h = 1,
                    text = "Default |",
                    horizontal_alignment = "right"
                },
                {
                    type = "Text",
                    x = 12,
                    y = 7,
                    w = "w-12",
                    h = 1,
                    text = "$tostring(selected_setting.raw.default)$",
                    horizontal_alignment = "left"
                },
                {
                    type = "Text",
                    x = 1,
                    y = 8,
                    h = 1,
                    text = "--- Description ---"
                },
                {
                    type = "Text",
                    x = 1,
                    y = 9,
                    h = "h-8",
                    text = "$selected_setting.desc$",
                    horizontal_alignment = "left",
                    scrollbar = true,
                },
            },
            theme = {
                { "border_thickness", 0 }
            }
        },
        {
            type = "Button",
            x = 1,
            y = "h",
            h = 1,
            w = "w/2",
            text = "$'\\27 Cancel'$",
            key = "tab",
            on_click = "$tapi.back$",
            horizontal_alignment = "left"
        },
        {
            type = "Button",
            x = "w/2+1",
            y = "h",
            w = "w/2",
            h = 1,
            text = "Save",
            on_click = save_setting
        }
    }
}
