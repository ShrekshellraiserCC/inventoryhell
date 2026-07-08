local ItemDescriptor = require "libs.ItemDescriptor"
---@class SSDTermPluginENV
_ENV = _ENV

local cenv = {}

---@class ssd.term.plugin.utils.button

---@class ssd.term.plugin.utils
_ENV.utils = {}
---@param title string
---@param body string
---@param confirm_callback function?
---@param confirm_text string?
---@param cancel_callback function?
---@param cancel_text string?
function _ENV.utils.confirm_screen(title, body, confirm_callback, confirm_text, cancel_callback, cancel_text)
    cenv.title = title
    cenv.body = body
    cenv.cancel_callback = cancel_callback
    cenv.confirm_callback = confirm_callback
    cenv.confirm_text = confirm_text or "Confirm"
    cenv.cancel_text = cancel_text or "Cancel"
    _ENV.tapi.open_screen("utils:confirm_screen")
end

_ENV.tapi.register_screen("utils:confirm_screen", {
    type = "Screen",
    content = {
        _ENV.tapi.header_template("$title$"),
        _ENV.tapi.back_button_template({
            on_click = function()
                if cenv.cancel_callback then
                    cenv.cancel_callback()
                end
                _ENV.tapi.back()
            end
        }),
        {
            type = "Text",
            text = "$body$",
            y = 2,
            h = "h-2"
        },
        {
            type = "Button",
            text = "$cancel_text$",
            y = "h",
            w = "w/2",
            on_click = function()
                if cenv.cancel_callback then
                    cenv.cancel_callback()
                end
                _ENV.tapi.back()
            end
        },
        {
            type = "Button",
            text = "$confirm_text$",
            y = "h",
            x = "w/2+1",
            on_click = function()
                if cenv.confirm_callback then
                    cenv.confirm_callback()
                end
                _ENV.tapi.back()
            end,
            class = "danger-button"
        }
    }
}, nil, cenv)

function _ENV.utils.info_screen(title, body)
    cenv.title = title
    cenv.body = body
    _ENV.tapi.open_screen("utils:info_screen")
end

_ENV.tapi.register_screen("utils:info_screen", {
    type = "Screen",
    content = {
        _ENV.tapi.header_template("$title$"),
        _ENV.tapi.back_button_template(),
        {
            type = "Text",
            text = "$body$",
            y = 2,
            h = "h-2"
        },
        {
            type = "Button",
            text = "Okay",
            y = "h",
            w = "w/2",
            on_click = _ENV.tapi.back
        },
    }
}, nil, cenv)

local function generate_itemdescriptor_options(info)
    local l = {}
    if info.name == "" then return l end
    l[1] = { ItemDescriptor.fromName(info.name):serialize() }
    if info.nbt then
        l[#l + 1] = { ItemDescriptor.fromName(info.name, info.nbt):serialize() }
    end
    if info.tags then
        for k, v in pairs(info.tags) do
            l[#l + 1] = { ItemDescriptor.hasTag(k):serialize() }
        end
    end
    return l
end

local function sanitize_listing(l)
    local size = tapi.inventory_size()
    local list = {}
    for i = 1, size do
        list[i] = l[i] or { name = "", count = 0, displayName = "" }
    end
    return list
end

---Display a list of the term's inventory. Allow the user to pick out an item descriptor based off the item.
---Locks the inventory when opened, but does not unlock it.
---@param callback fun(ID:string)
function _ENV.utils.item_picker(callback)
    -- Disable inventory importing
    _ENV.tapi.lock_inventory(true)
    _ENV.tapi.open_screen("utils:item_picker")
    cenv.picker_listing = sanitize_listing(_ENV.tapi.list_inventory())
    cenv.picker_callback = callback
    cenv.id_input = ""
    if cenv.picker_listing[1] then
        cenv.picker_itemdescriptors = generate_itemdescriptor_options(cenv.picker_listing[1])
    else
        cenv.picker_itemdescriptors = {}
    end
    -- Renable inventory importing once this screen exits
end

_ENV.tapi.register_screen("utils:item_picker", {
    type = "Screen",
    content = {
        _ENV.tapi.back_button_template(),
        _ENV.tapi.header_template("Item Picker"),
        {
            type = "Frame",
            y = 2,
            content = {
                {
                    type = "Input",
                    h = 1,
                    id = "ID-input",
                    value = "$id_input$"
                },
                {
                    type = "Table",
                    y = 2,
                    w = "w/2",
                    h = "h-2",
                    list = "$picker_listing$",
                    columns = { { "displayName", "w", "Name" } },
                    instant_select = true,
                    on_select = function(self, selected)
                        cenv.picker_itemdescriptors = generate_itemdescriptor_options(selected)
                    end
                },
                {
                    type = "Table",
                    y = 2,
                    x = "w/2+1",
                    h = "h-2",
                    list = "$picker_itemdescriptors$",
                    columns = { { 1, "w", "ID" } },
                    instant_select = true,
                    on_select = function(self, v)
                        local r = self:get_root()
                        r:get_widget_by_id("ID-input"):set_value(v[1])
                    end
                },
                {
                    type = "Button",
                    y = "h",
                    w = "w/2",
                    text = "Refresh",
                    on_click = function()
                        cenv.picker_listing = sanitize_listing(_ENV.tapi.list_inventory())
                    end
                },
                {
                    type = "Button",
                    y = "h",
                    x = "w/2+1",
                    text = "Submit",
                    on_click = function()
                        cenv.picker_callback(cenv.id_input)
                        tapi.back()
                    end
                }
            }
        }
    }
}, nil, cenv)

cenv.inventory_list = nil
cenv.inventory_filter = ""
cenv.filtered_inventory_list = {}
local function filter_inventory(filter)
    cenv.filtered_inventory_list = {}
    for k, v in ipairs(cenv.inventory_list) do
        if v.side:find(filter, nil, true) then
            cenv.filtered_inventory_list[#cenv.filtered_inventory_list + 1] = v
        end
    end
end
_ENV.capi.subscribeTo({
    peripherals = function(l)
        cenv.inventory_list = l
        filter_inventory(cenv.inventory_filter)
    end
})
---@param callback fun(side:string)
function _ENV.utils.inventory_picker(callback)
    tapi.open_screen("utils:inventory_picker")
    cenv.picker_callback = callback
end

_ENV.tapi.register_screen("utils:inventory_picker", {
    type = "Screen",
    content = {
        _ENV.tapi.header_template("Inv Picker"),
        _ENV.tapi.back_button_template(),
        {
            type = "Table",
            y = 2,
            h = "h-2",
            list = "$filtered_inventory_list$",
            columns = {
                { "label",   10,    "Used" },
                { "side",    "w/2", "Side" },
                { "missing", nil,   "Missing" },
            },
            on_select = function(self, v)
                cenv.picker_callback(v.side)
                _ENV.tapi.back()
            end
        },
        {
            type = "Input",
            value = "$inventory_filter$",
            y = "h",
            ignore_focus = true,
            on_change = function(self, value)
                filter_inventory(value)
            end,
            always_update = true
        }
    }
}, function()
    if not cenv.inventory_list then
        cenv.inventory_list = _ENV.capi.listPeripherals()
    end
    cenv.inventory_filter = ""
    filter_inventory("")
end, cenv)

do
    ---@generic K : string|integer
    ---@param t table<K,string>
    ---@param callback fun(t:table<K,string>)
    ---@param validate (fun(v:string):boolean)?
    ---@param picker "inventory"|"item"?
    function _ENV.utils.edit_array(t, callback, validate, picker)
        cenv.edit_array = {}
        for k, v in pairs(t) do
            cenv.edit_array[#cenv.edit_array + 1] = {
                k,
                v
            }
        end
        cenv.table_callback = callback
        cenv.value_validate = validate
        cenv.picker_type = picker
        tapi.open_screen("utils:edit_array")
    end

    ---@param self shrekui.Widget
    ---@param i integer
    local function set_selected_entry(self, _, i)
        cenv.selected_entry = i
        local root = self:get_root()
        local list = root:get_widget_by_id("table-list") --[[@as shrekui.Table]]
        list:set_selected(i)
        local input = root:get_widget_by_id("value-input") --[[@as shrekui.Input]]
        input:set_value(cenv.edit_array[i][2])
    end

    ---@param self shrekui.Input|shrekui.Button
    ---@param v string
    local function set_entry_value(self, v)
        if cenv.selected_entry then
            if cenv.value_validate and not cenv.value_validate(v) then
                return
            end
            cenv.edit_array[cenv.selected_entry][2] = v
            set_selected_entry(self, nil, cenv.selected_entry)
        end
    end

    ---@param self shrekui.Button
    local function delete_selected_entry(self)
        if cenv.selected_entry then
            table.remove(cenv.edit_array, cenv.selected_entry)
            for i, v in ipairs(cenv.edit_array) do
                if type(v[1]) == "number" and v[1] > cenv.selected_entry then
                    v[1] = v[1] - 1
                end
            end
            cenv.selected_entry = math.min(#cenv.edit_array, cenv.selected_entry)
            if cenv.selected_entry <= 0 then
                cenv.selected_entry = nil
            end
        end
    end

    ---@param self shrekui.Button
    local function add_entry(self)
        local i = #cenv.edit_array + 1
        cenv.edit_array[i] = { i, "" }
        set_selected_entry(self, nil, i)
    end

    local function save_array()
        local nt = {}
        for i, v in ipairs(cenv.edit_array) do
            nt[v[1]] = v[2]
        end
        cenv.table_callback(nt)
        tapi.back()
    end


    tapi.register_screen("utils:edit_array", {
        type = "Screen",
        content = {
            {
                type = "Frame",
                y = 2,
                h = "h-2",
                padding = 1,
                content = {
                    {
                        type = "Input",
                        h = 1,
                        w = "picker_type and w-1 or w",
                        id = "value-input",
                        on_change = set_entry_value
                    },
                    {
                        type = "Button",
                        x = "w",
                        h = 1,
                        text = "+",
                        hidden = "$picker_type$",
                        on_click = function(self)
                            if cenv.picker_type == "inventory" then
                                utils.inventory_picker(function(side)
                                    set_entry_value(self, side)
                                end)
                            elseif cenv.picker_type == "item" then
                                utils.item_picker(function(ID)
                                    set_entry_value(self, ID)
                                end)
                            end
                        end
                    },
                    {
                        type = "Table",
                        list = "$edit_array$",
                        id = "table-list",
                        columns = {
                            { 1, 3,   "k" },
                            { 2, nil, "v" }
                        },
                        y = 2,
                        h = "h-2",
                        on_select = set_selected_entry,
                        allow_sort = false,
                        instant_select = true
                    },
                    {
                        type = "Button",
                        text = "-",
                        y = "h",
                        w = "w/2",
                        on_click = delete_selected_entry
                    },
                    {
                        type = "Button",
                        text = "+",
                        y = "h",
                        x = "w/2+1",
                        on_click = add_entry
                    }
                }
            },
            {
                type = "Button",
                w = "w/2",
                y = "h",
                text = "Cancel",
                class = "warning-button",
                on_click = tapi.back
            },
            {
                type = "Button",
                x = "w/2+1",
                y = "h",
                text = "Save",
                on_click = save_array
            },
            tapi.back_button_template(),
            tapi.header_template("Edit Table")
        }
    }, nil, cenv)
end


local function serialize(v)
    if type(v) == "table" then
        local s = { "{" }
        for i, j in ipairs(v) do
            if type(j) == "table" then
                s[#s + 1] = serialize(j)
            else
                s[#s + 1] = '"'
                s[#s + 1] = tostring(j)
                s[#s + 1] = '"'
            end
            s[#s + 1] = ","
        end
        if s[#s] == "," then
            s[#s] = nil
        end
        s[#s + 1] = "}"
        return table.concat(s)
    end
    return tostring(v)
end
local logger = tapi.logger.logger("utils")
utils.serialize = serialize
do
    local env = {
        rtable = {},
        path = {},
        etable = {},
        selected_entry = nil
    }
    ---@param self shrekui.Widget
    ---@param i integer
    local function set_selected_entry(self, _, i)
        local root = self:get_root()
        local list = root:get_widget_by_id("table-list") --[[@as shrekui.Table]]
        list:set_selected(i)
        local input = root:get_widget_by_id("value-input") --[[@as shrekui.Input]]
        local key_input = root:get_widget_by_id("key-input") --[[@as shrekui.Input]]
        local edit_button = root:get_widget_by_id("edit-table-value") --[[@as shrekui.Button]]
        local edata = env.etable[i] or { "", "" }
        local is_table = edata[3]
        input:set_value(edata[2])
        key_input:set_value(edata[1])
        edit_button.text = edata[2]
        input:set_hidden(is_table)
        edit_button:set_hidden(not is_table)
        if env.etable[i] then
            env.selected_entry = i
        else
            env.selected_entry = nil
        end
    end

    ---@param self shrekui.Input|shrekui.Button
    ---@param v string
    local function set_entry_value(self, v)
        if env.selected_entry then
            if env.value_validate and not env.value_validate(v) then
                return
            end
            env.etable[env.selected_entry][2] = tonumber(v) or v
            set_selected_entry(self, nil, env.selected_entry)
        end
    end

    local function set_entry_key(self, v)
        if env.selected_entry then
            env.etable[env.selected_entry][1] = tonumber(v) or v
            set_selected_entry(self, nil, env.selected_entry)
        end
    end

    ---@param self shrekui.Button
    local function delete_selected_entry(self)
        if env.selected_entry then
            table.remove(env.etable, env.selected_entry)
            for i, v in ipairs(env.etable) do
                if type(v[1]) == "number" and v[1] > env.selected_entry then
                    v[1] = v[1] - 1
                end
            end
            env.selected_entry = math.min(#env.etable, env.selected_entry)
            if env.selected_entry <= 0 then
                env.selected_entry = nil
            end
        end
    end

    ---@param self shrekui.Button
    local function add_entry(self)
        local i = #env.etable + 1
        if self.meta == "table" then
            env.etable[i] = { i, "[]", {} }
        else
            env.etable[i] = { i, "" }
        end
        set_selected_entry(self, nil, i)
    end

    local function update_table_path(path)
        env.selected_entry = nil
        local rt = env.rtable
        for i, v in ipairs(env.path) do
            rt = rt[v]
        end
        for _, v in ipairs(env.etable) do
            rt[v[1]] = v[3] or v[2]
        end
        local t = env.rtable
        for i, v in ipairs(path) do
            if not t[v] then return end
            t = t[v]
        end
        env.path = path
        env.full_path = env.table_label
        if #path > 0 then
            env.full_path = env.full_path .. "[" .. table.concat(path, "][") .. "]"
        end
        env.etable = {}
        for k, v in pairs(t) do
            env.etable[#env.etable + 1] = { k, serialize(v), type(v) == "table" and v }
        end
    end

    ---@param self shrekui.Widget
    local function up(self)
        if #env.path > 0 then
            update_table_path({ table.unpack(env.path, 1, #env.path - 1) })
            set_selected_entry(self, nil, 1)
            return true
        end
        return false
    end

    local function traverse(p)
        local path = { table.unpack(env.path) }
        path[#path + 1] = p
        update_table_path(path)
    end

    local function save_table(self)
        update_table_path({})
        set_selected_entry(self, nil, 1)
        if env.validate then
            local ok, issue = env.validate(env.rtable)
            if not ok then
                tapi.notification("INVALID", issue)
                logger.fwarn("Cannot save editing table, validation failed %s", issue)
                return
            end
        end
        env.callback(env.rtable)
        tapi.back()
    end

    ---@param t table
    ---@param label string
    ---@param callback fun(t:table)
    ---@param validate nil|fun(t:table):boolean,string?
    function _ENV.utils.edit_table(t, label, callback, validate)
        env.rtable = t
        env.callback = callback
        env.table_label = label
        env.validate = validate
        update_table_path({})
        tapi.open_screen("utils:edit_table")
    end

    env.serialize = utils.serialize
    tapi.register_screen("utils:edit_table", {
        type = "Screen",
        content = {
            tapi.back_button_template {
                on_click = function(self)
                    if #env.path > 0 then
                        up(self)
                    else
                        tapi.back()
                    end
                end
            },
            tapi.header_template("Edit Table"),
            {
                type = "Frame",
                y = 2,
                h = "h-2",
                content = {
                    {
                        type = "Text",
                        y = 1,
                        h = 1,
                        w = "w-3",
                        text = "$full_path$",
                        horizontal_alignment = "left"
                    },
                    {
                        type = "Button",
                        y = 1,
                        h = 1,
                        x = "w-2",
                        w = 3,
                        text = "\30",
                        on_click = up
                    },
                    {
                        type = "Frame",
                        y = 2,
                        h = 2,
                        w = "w/2-1",
                        content = {
                            {
                                type = "Text",
                                h = 1,
                                text = "Key"
                            },
                            {
                                type = "Input",
                                h = 1,
                                y = 2,
                                id = "key-input",
                                on_change = set_entry_key
                            }
                        }
                    },
                    {
                        type = "Frame",
                        h = 2,
                        y = 2,
                        x = "w/2+1",
                        content = {
                            {
                                type = "Text",
                                h = 1,
                                text = "Value"
                            },
                            {
                                type = "Button",
                                y = 2,
                                id = "edit-table-value",
                                on_click = function()
                                    if env.selected_entry then
                                        local k = env.etable[env.selected_entry][1]
                                        traverse(k)
                                    end
                                end
                            },
                            {
                                type = "Input",
                                y = 2,
                                h = 1,
                                id = "value-input",
                                on_change = set_entry_value
                            },
                        }
                    },
                    {
                        type = "Table",
                        list = "$etable$",
                        id = "table-list",
                        columns = {
                            { 1, nil, "k" },
                            { 2, nil, "v" }
                        },
                        y = 4,
                        h = "h-4",
                        on_select = set_selected_entry,
                        allow_sort = false,
                        instant_select = true
                    },
                    {
                        type = "Button",
                        text = "-",
                        y = "h",
                        w = "w/3",
                        on_click = delete_selected_entry
                    },
                    {
                        type = "Button",
                        text = "+",
                        y = "h",
                        x = "w/3+1",
                        w = "w/3",
                        on_click = add_entry
                    },
                    {
                        type = "Button",
                        text = "+T",
                        y = "h",
                        x = "2*w/3+1",
                        on_click = add_entry,
                        meta = "table"
                    }
                }
            },
            {
                type = "Button",
                w = "w/2",
                y = "h",
                text = "Cancel",
                class = "warning-button",
                on_click = tapi.back
            },
            {
                type = "Button",
                x = "w/2+1",
                y = "h",
                text = "Save",
                on_click = save_table
            },
        },
    }, function(self)
        set_selected_entry(self, nil, 0)
    end, env)
end
