---@class SSDTermPluginENV
_ENV = _ENV --[[@as SSDTermPluginENV]]

local cenv = {
    selected_setting = {},
    selected_setting_evalue_g = "",
    selected_setting_evalue_l = ""
}

cenv.serialize = _ENV.utils.serialize
local settings_list = {}
local sset = tapi.sset
local function create_settings_list()
    settings_list = {}
    for i, v in ipairs(sset.settingList) do
        local value = sset.get(v)
        if value ~= nil and value == v.default then
            value = cenv.serialize(value) .. "*"
        else
            value = cenv.serialize(value)
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
    cenv.settings = sort
end
create_settings_list()
apply_settings_sort("")

local function setting_search_change(self, value)
    apply_settings_sort(value)
end
local function setting_select(self, item, idx)
    cenv.selected_setting = item
    local raw = item.raw --[[@as RegisteredSetting]]
    local value = sset.get(item.raw)
    if value ~= nil and value == item.default then
        value = tostring(value) .. "*"
    else
        value = tostring(value)
    end
    cenv.selected_setting_evalue_g = raw.gvalue == nil and "nil" or raw.gvalue
    cenv.selected_setting_evalue_l = raw.lvalue == nil and "nil" or raw.lvalue
    tapi.open_screen("setting_edit")
end

tapi.sset.onChangedCallback(function()
    create_settings_list()
    apply_settings_sort(cenv.setting_search_bar)
end)

tapi.register_screen("settings", {
    type = "Screen",
    content = {
        {
            type = "Text",
            h = 1,
            text = "Settings",
            class = "heading"
        },
        back_button_template(),
        {
            type = "Input",
            x = 1,
            y = "h",
            h = 1,
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
}, nil, cenv)



local function save_setting(self)
    local setting = cenv.selected_setting.raw --[[@as RegisteredSetting]]
    if setting.side ~= "global" then
        ---@type string?
        local evalue_l = cenv.selected_setting_evalue_l
        if evalue_l == "nil" then evalue_l = nil end
        tapi.sset.set(setting, evalue_l, true)
    end
    ---@type string?
    local evalue_g = cenv.selected_setting_evalue_g
    if evalue_g == "nil" then evalue_g = nil end
    tapi.sset.set(setting, evalue_g)
    tapi.sset.checkForChanges()
    tapi.back()
    if setting.requiresReboot then
        tapi.open_screen("setting_reboot")
    end
end
local function default_setting(self)
    cenv[self.meta] = "nil"
end

local setting_edit_args = {
    type = "Screen",
    content = {
        {
            type = "Text",
            h = 1,
            text = "Edit Setting",
            class = "heading"
        },
        back_button_template(),
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
                    type = "Button",
                    x = "w-1",
                    y = 4,
                    w = 1,
                    h = 1,
                    text = "x",
                    hidden = "$selected_setting.raw.side == 'local'$",
                    meta = "selected_setting_evalue_g",
                    on_click = default_setting,
                    class = "danger-button"
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
                    type = "Button",
                    x = "w-1",
                    y = 5,
                    w = 1,
                    h = 1,
                    text = "x",
                    hidden = "$selected_setting.raw.side == 'global'$",
                    meta = "selected_setting_evalue_l",
                    on_click = default_setting,
                    class = "danger-button"
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
                    text = "$serialize(selected_setting.value)$",
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
                    text = "$serialize(selected_setting.raw.default)$",
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
            on_click = "$tapi.back$",
            horizontal_alignment = "left",
            class = "warning-button"
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
local function clone(t)
    if type(t) == "table" then
        local nt = {}
        for k, v in pairs(t) do
            nt[k] = clone(v)
        end
        return nt
    end
    return t
end
local setting_edit_content = setting_edit_args.content[3].content
local function add_setting_edit_field(y, vstr, hstr)
    local w = "w-13"
    local x = 12
    setting_edit_content[#setting_edit_content + 1] = {
        type = "Input",
        x = x,
        y = y,
        w = w,
        h = 1,
        value = vstr,
        hidden =
            "$selected_setting.raw.options or (selected_setting.raw.type ~= 'string' and selected_setting.raw.type ~= 'number') or " ..
            hstr
    }
    setting_edit_content[#setting_edit_content + 1] = {
        type = "Dropdown",
        x = x,
        y = y,
        w = w,
        h = 1,
        options = "$selected_setting.raw.options or {}$",
        value = vstr,
        hidden = "$not selected_setting.raw.options or " .. hstr
    }
    setting_edit_content[#setting_edit_content + 1] = {
        type = "Dropdown",
        x = x,
        y = y,
        w = w,
        h = 1,
        options = { true, false },
        value = vstr,
        hidden = "$selected_setting.raw.type ~= 'boolean' or " .. hstr
    }
    local vidx = vstr:sub(2, -2)
    setting_edit_content[#setting_edit_content + 1] = {
        type = "Button",
        x = x,
        y = y,
        w = w,
        h = 1,
        text = "$serialize(" .. vidx .. ")$",
        hidden = "$not (selected_setting.raw.type:match('%[%]') or selected_setting.raw.type == 'table') or " .. hstr,
        on_click = function()
            local v = cenv[vidx]
            if v == "nil" then
                local raw = cenv.selected_setting.raw --[[@as RegisteredSetting]]
                if raw.default then
                    v = clone(raw.default)
                else
                    v = {}
                end
            end
            if cenv.selected_setting.raw.type == "table" then
                utils.edit_table(v, cenv.selected_setting.raw.name, function(t)
                    cenv[vidx] = t
                end)
            else
                utils.edit_array(v, function(t)
                    cenv[vidx] = t
                end, function(s)
                    return pcall(string.match, s, s)
                end, "inventory")
            end
        end
    }
end
add_setting_edit_field(4, "$selected_setting_evalue_g$", "selected_setting.raw.side == 'local'$")
add_setting_edit_field(5, "$selected_setting_evalue_l$", "selected_setting.raw.side == 'global'$")
tapi.register_screen("setting_edit", setting_edit_args, nil, cenv)

cenv.selected_setting = { raw = { side = "global" } }
local function smart_reboot()
    if cenv.selected_setting.raw.side ~= "global" then
        reboot()
    end
    capi.rebootAll()
end

tapi.register_screen("setting_reboot", {
    type = "Screen",
    content = {
        back_button_template(),
        {
            type = "Text",
            h = 1,
            text = "Reboot?",
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
            on_click = "$tapi.back$"
        },
        {
            type = "Button",
            x = "w/2+1",
            y = "h",
            w = "(selected_setting and selected_setting.raw.side ~= 'both') and (w/2) or (w/4)",
            h = 1,
            text = "Yes",
            key = "enter",
            on_click = smart_reboot,
            class = "danger-button"
        },
        {
            type = "Button",
            x = "3*w/4+2",
            y = "h",
            w = "w/4",
            h = 1,
            text = "All",
            key = "enter",
            hidden = "$selected_setting.raw.side ~= 'both'$",
            on_click = capi.rebootAll,
            class = "danger-button"
        }
    }
}, nil, cenv)


tapi.register_menu_button(2, "Settings", "settings")
