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
