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
}
