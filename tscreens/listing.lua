---@class SSDTermPluginENV
_ENV = _ENV

local function item_select(self, item, idx)
    ---@cast self shrekui.Screen
    _ENV.item = item
    _ENV.item.detail = nil
    _ENV.item.detail = textutils.serialize(item)
    _ENV.tapi.open_screen("request")
end


local function toggle_craft_button(self)
    _ENV.tapi.lock_inventory(_ENV.craft_active)
    if not _ENV.craft_active then
        _ENV.tapi.clear_locked_slots()
        _ENV.tapi.lock_inventory(false)
    end
end

local listing_raw = {}
local sort = {}
local function apply_sort(filter)
    sort = {}
    for i, v in ipairs(listing_raw) do
        if v.name:match(filter) then
            sort[#sort + 1] = v
        end
    end
    _ENV.listing = sort
end
apply_sort("")
local function search_change(self, value)
    apply_sort(value)
end

local function init(list, fragmap)
    listing_raw = capi.list()
    apply_sort("")
end

function _ENV.submit_request(self)
    local mul = 8
    if self:is_held(keys.leftShift) then
        mul = 64
    elseif self:is_held(keys.leftCtrl) then
        mul = 1
    end
    local count = self.meta * mul
    tapi.request(_ENV.item, count)
    tapi.back()
end

_ENV.capi.subscribeTo({
    changes = function(l, fm)
        listing_raw = l
        apply_sort(_ENV.search_bar)
    end,
    start = init
})

_ENV.tapi.register_screen("listing", {
    type = "Screen",
    content = {
        {
            type = "Dropdown",
            x = 1,
            y = 1,
            w = 10,
            h = 1,
            value = "All",
            options = { "All", "Stored", "Craftables", "+" },
            class = "heading"
        },
        _ENV.back_button_template {
            z = 1.3,
        },
        {
            type = "Button",
            x = 2,
            y = "h",
            w = 3,
            h = 1,
            text = "  >",
            z = 1.3,
            toggle = true,
            pressed = "$search_options$"
        },
        {
            type = "Input",
            x = 5,
            y = "h",
            h = 1,
            w = "w-((turtle and turtle.craft) and 10 or 4)",
            z = 1.3,
            ignore_focus = true,
            always_update = true,
            on_change = search_change,
            value = "$search_bar$"
        },
        {
            type = "Frame",
            x = 1,
            y = "h-4",
            w = "w-((turtle and turtle.craft) and 11 or 0)",
            h = "5",
            hidden = "$not search_options$",
            z = 1.2,
            class = "submenu",
            content = {
                {
                    type = "Checkbox",
                    text = "Enable ItemDescriptors",
                    pressed = "$enable_item_descriptors$"
                }
            }
        },
        {
            type = "Button",
            x = "w-5",
            y = "h",
            h = 1,
            w = 6,
            z = 3,
            text = "Craft",
            toggle = true,
            pressed = "$craft_active$",
            on_click = toggle_craft_button,
            hidden = "$not (turtle and turtle.craft)$"
        },
        {
            type = "Table",
            x = 1,
            y = 2,
            w = "w",
            h = "h-2",
            z = 1.1, -- Get events before the focused Input
            list = "$listing$",
            columns = {
                {
                    "count",
                    6,
                    "Count"
                },
                {
                    "displayName",
                    "w-6",
                    "Name"
                }
            },
            on_select = item_select
        },
        {
            type = "Frame",
            x = "w-10",
            y = "h-3",
            w = 11,
            h = 4,
            z = 2,
            class = "submenu",
            hidden = "$not craft_active$",
            content = {
                {
                    type = "Button",
                    x = 1,
                    y = 1,
                    h = 1,
                    w = "w",
                    text = "Craft",
                    on_click = "$craft$"
                },
                {
                    type = "Button",
                    x = 1,
                    y = 2,
                    h = 1,
                    w = "w",
                    text = "Depot",
                    on_click = "$depot$"
                }
            }
        }
    }
})


_ENV.tapi.register_screen("request", {
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
            scrollbar = true
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
            on_click = submit_request,
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
            on_click = submit_request,
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
            on_click = submit_request,
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
            on_click = submit_request,
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
            on_click = submit_request,
            key = "enter"
        }
    }
})


_ENV.tapi.register_menu_button(1, "Listing", "listing")
