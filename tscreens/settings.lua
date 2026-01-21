---@class SSDTermPluginENV
_ENV = _ENV --[[@as SSDTermPluginENV]]

_ENV.selected_setting = {}
_ENV.selected_setting_evalue_l = ""
_ENV.selected_setting_evalue_g = ""
local settings_list = {}
local sset = _ENV.tapi.sset
local function create_settings_list()
    settings_list = {}
    for i, v in ipairs(sset.settingList) do
        local value = sset.get(v)
        if value ~= nil and value == v.default then
            value = tostring(value) .. "*"
        else
            value = tostring(value)
        end
        settings_list[i] = {
            name = v.name,
            desc = v.desc,
            value = value,
            raw = v
        }
    end
end
local sort = {}
local function apply_settings_sort(s)
    sort = {}
    for i, v in ipairs(settings_list) do
        if v.name:match(s) then
            sort[#sort + 1] = v
        end
    end
    _ENV.settings = sort
end
create_settings_list()
apply_settings_sort("")

local function setting_search_change(self, value)
    apply_settings_sort(value)
end
local function setting_select(self, item, idx)
    _ENV.selected_setting = item
    local value = sset.get(item.raw)
    if value ~= nil and value == item.default then
        value = tostring(value) .. "*"
    else
        value = tostring(value)
    end
    _ENV.selected_setting_evalue_g = tostring(item.raw.gvalue)
    _ENV.selected_setting_evalue_l = tostring(item.raw.lvalue)
    tapi.open_screen("setting_edit")
end

_ENV.tapi.sset.onChangedCallback(function()
    create_settings_list()
    apply_settings_sort(_ENV.setting_search_bar)
end)

_ENV.tapi.register_screen("settings", {
    type = "Screen",
    content = {
        {
            type = "Text",
            h = 1,
            text = "nterm",
            horizontal_alignment = "left",
            class = "heading"
        },
        _ENV.back_button_template(),
        {
            type = "Input",
            x = 2,
            y = "h",
            h = 1,
            w = "w-1",
            ignore_focus = true,
            always_update = true,
            on_change = setting_search_change,
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
                    "w/3",
                    "Name"
                },
                {
                    "value",
                    "w/3",
                    "Value"
                },
                {
                    "desc",
                    "w/3",
                    "Description"
                }
            },
            on_select = setting_select
        }
    }
})



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

_ENV.tapi.register_screen("setting_edit", {
    type = "Screen",
    content = {
        {
            type = "Text",
            h = 1,
            text = "Edit Setting",
            horizontal_alignment = "left",
            class = "heading"
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
                    class = "clear",
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
                    class = "clear",
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
            horizontal_alignment = "left",
            id = "back-button"
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
})


local function smart_reboot()
    if _ENV.selected_setting.raw.side == "local" then
        _ENV.reboot()
    end
    _ENV.capi.rebootAll()
end

_ENV.tapi.register_screen("setting_reboot", {
    type = "Screen",
    content = {
        {
            type = "Text",
            h = 1,
            text = "Reboot?",
            horizontal_alignment = "left",
            class = "heading"
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
            on_click = "$tapi.back$",
            id = "back-button"
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
})


_ENV.tapi.register_menu_button(2, "Settings", "settings")
