local sset = require "libs.sset"
local ItemDescriptor = require "libs.ItemDescriptor"
---@class SSDTermPluginENV
_ENV = _ENV

local debug_ignore_listing_updates = true

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

local listing_raw = {
    { name = "minecraft:cobblestone", displayName = "Cobblestone", count = 1280, maxCount = 64 },
    { name = "foo:bar",               displayName = "FOOBAR",      count = 0,    tags = { "foo" }, maxCount = 1 }
}
local sort = {}
local category_id = ItemDescriptor.nop()
local function apply_sort(filter)
    sort = {}
    local ok, id = false, nil
    if _ENV.enable_item_descriptors then
        ok, id = pcall(ItemDescriptor.unserialize, filter)
    end
    local match
    if ok then
        assert(id, "ItemDescriptor.unserialize succeded, but ID is nil!")
        match = function(v)
            return id:match(v)
        end
        _ENV.search_state_color = "green"
    else
        match = function(v)
            return v.name:find(filter, nil, true)
        end
        _ENV.search_state_color = "white"
    end
    if _ENV.enable_item_descriptors and not ok then
        _ENV.search_state_color = "red"
    end
    for i, v in ipairs(listing_raw) do
        if category_id:match(v) and match(v) then
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
    if not debug_ignore_listing_updates then
        listing_raw = capi.list()
    end
    apply_sort("")
end

local function submit_request(self)
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

local function submit_request_input(self)
    local f = load("return " .. self.value, "input_count", "t", {
        math = math
    })
    local ok, v = pcall(f)
    if ok and type(v) == "number" then
        tapi.request(_ENV.item, math.floor(v))
        tapi.back()
    end
end

_ENV.search_state_color = "white"

_ENV.capi.subscribeTo({
    changes = function(l, fm)
        if not debug_ignore_listing_updates then
            listing_raw = l
        end
        apply_sort(_ENV.search_bar)
    end,
    start = init
})

---@type [string,string][]
local listing_category_setting = sset.get(sset.termListingCategories)

---@type string[]
local listing_categories = {}
for i, v in ipairs(listing_category_setting) do
    listing_categories[i] = v[1]
end

-- TODO implement in UI editing
-- listing_categories[#listing_categories + 1] = "+"

local function listing_category_change(self, v, i)
    if v == "+" then
        -- TODO
        return
    end
    local id_str = listing_category_setting[i][2]
    local id = ItemDescriptor.unserialize(id_str)
    category_id = id
    apply_sort(_ENV.search_bar)
end

local function use_id_change()
    apply_sort(_ENV.search_bar)
end

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
            options = listing_categories,
            class = "heading",
            on_change = listing_category_change
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
            pressed = "$search_options$",
            text_color = "$search_state_color$"
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
            y = "h-5",
            w = "w-((turtle and turtle.craft) and 11 or 0)",
            h = "5",
            hidden = "$not search_options$",
            z = 1.5,
            class = "submenu",
            content = {
                {
                    type = "Checkbox",
                    text = "Enable ItemDescriptors",
                    pressed = "$enable_item_descriptors$",
                    w = "w-3",
                    on_click = use_id_change
                },
                {
                    type = "Button",
                    text = "?",
                    on_click = "$tapi.open_screen('help_itemdescriptors')$",
                    x = "w-2",
                    w = 3
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
            z = 1.4, -- Get events before the focused Input
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


local request_screen_args = {
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
    }
}

if sset.get(sset.requestScreenType) == "chord" then
    ---@type shrekui.FrameArgs
    request_screen_args.content[#request_screen_args.content + 1] = {
        type = "Frame",
        content = {
            {
                type = "Button",
                x = 1,
                w = 7,
                text =
                "$self:is_held(keys.leftShift) and '[A  64]' or self:is_held(keys.leftCtrl) and '[A   1]' or '[A   8]'$",
                meta = 1,
                on_click = submit_request,
                key = "a"
            },
            {
                type = "Button",
                x = 8,
                w = 7,
                text =
                "$self:is_held(keys.leftShift) and '[S 128]' or self:is_held(keys.leftCtrl) and '[S   2]' or '[S  16]'$",
                meta = 2,
                on_click = submit_request,
                key = "s"
            },
            {
                type = "Button",
                x = 15,
                w = 7,
                text =
                "$self:is_held(keys.leftShift) and '[D 256]' or self:is_held(keys.leftCtrl) and '[D   4]' or '[D  32]'$",
                meta = 4,
                on_click = submit_request,
                key = "d"
            },
            {
                type = "Button",
                x = 22,
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
                w = 7,
                text = "[Enter]",
                meta = 8,
                on_click = submit_request,
                key = "enter"
            }
        },
        x = 2,
        y = "h",
        w = "w-1",
        h = 1
    }
else -- input type
    ---@type shrekui.FrameArgs
    local frame = {
        type = "Frame",
        content = {
            {
                x = 7,
                w = "w-6",
                type = "Input",
                ignore_focus = true,
                id = "item_count_input",
                on_change = submit_request_input
            },
            {
                type = "Text",
                w = 6,
                text = "Count>"
            },
        },
        x = 2,
        y = "h",
        w = "w-1",
        h = 1,
    }
    table.insert(request_screen_args.content, 1, frame)
end


local request_screen_callback_content
-- Well this is a terrible catch-22 isn't it?
-- I need to set the request screen's input box back to a default value when it is opened
-- But to do that, I need a reference to the Input object, but I only get that after providing the callback.
-- Oh boy.
local request_screen = _ENV.tapi.register_screen("request", request_screen_args, function()
    if request_screen_callback_content then
        request_screen_callback_content()
    end
end)
if sset.get(sset.requestScreenType) == "input" then
    local input = request_screen:get_widget_by_id("item_count_input") --[[@as shrekui.Input]]
    request_screen_callback_content = function()
        input:set_value(tostring(_ENV.item.maxCount))
    end
end


_ENV.tapi.register_menu_button(1, "Listing", "listing")
