local sset = require "libs.sset"
local ItemDescriptor = require "libs.ItemDescriptor"
---@class SSDTermPluginENV
_ENV = _ENV

local debug_ignore_listing_updates = false
local cenv = {}

local function generate_item_description(item)
    local s = {}
    s[#s + 1] = "Display Name: " .. item.displayName
    s[#s + 1] = "Count: " .. item.count
    s[#s + 1] = "Name: " .. item.name
    if item.nbt then
        s[#s + 1] = "NBT: " .. item.nbt
    end
    if item.durability then
        s[#s + 1] = ("Durability: %.2f%%"):format(item.durability)
    end
    if item.potionEffects then
        s[#s + 1] = "\nPotion:"
        for k, v in ipairs(item.potionEffects) do
            s[#s + 1] = "\7 " .. v.displayName or v.name
        end
    end
    if item.enchantments then
        s[#s + 1] = "\nEnchantments:"
        for k, v in ipairs(item.enchantments) do
            s[#s + 1] = "\7 " .. v.displayName or v.name
        end
    end
    if item.tags then
        s[#s + 1] = "\nTags:"
        for k in pairs(item.tags) do
            s[#s + 1] = "\7 " .. k
        end
    end
    if item.itemGroups and #item.itemGroups > 0 then
        s[#s + 1] = "\nItem Groups:"
        for k, v in ipairs(item.itemGroups) do
            s[#s + 1] = "\7 " .. v.displayName or v.name
        end
    end
    return table.concat(s, "\n")
end

local function item_select(self, item, idx)
    ---@cast self shrekui.Screen
    cenv.item = item
    cenv.item.detail = nil
    cenv.item.detail = generate_item_description(item)
    if (self:is_held(keys.leftCtrl) or item.count == 0) and item.craftable then
        tapi.open_screen("listing:request_craft")
    else
        tapi.open_screen("listing:request")
    end
end


local function toggle_craft_button(self)
    tapi.lock_inventory(cenv.craft_active)
    if not cenv.craft_active then
        tapi.clear_locked_slots()
        tapi.lock_inventory(false)
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
    if cenv.enable_item_descriptors then
        ok, id = pcall(ItemDescriptor.unserialize, filter)
    end
    local match
    if ok then
        assert(id, "ItemDescriptor.unserialize succeded, but ID is nil!")
        match = function(v)
            return id:match(v)
        end
        cenv.search_state_color = "green"
    else
        match = function(v)
            return v.name:find(filter, nil, true)
        end
        cenv.search_state_color = "white"
    end
    if cenv.enable_item_descriptors and not ok then
        cenv.search_state_color = "red"
    end
    for i, v in ipairs(listing_raw) do
        if category_id:match(v) and match(v) then
            sort[#sort + 1] = v
        end
    end
    cenv.listing = sort
end
apply_sort("")
local function search_change(self, value)
    apply_sort(value)
end

local has_init = false
local function init(list, fragmap)
    if not debug_ignore_listing_updates then
        listing_raw = list
    end
    apply_sort("")
    has_init = true
end

tapi.register_screen("listing:craft_overview", {
    type = "Screen",
    content = {
        tapi.back_button_template(),
        tapi.header_template("Craft Request"),
        {
            type = "Text",
            y = 2,
            h = 2,
            text = "$request_info_string$"
        },
        {
            type = "Table",
            y = 4,
            list = "$required_item_list$",
            h = "h-5",
            columns = {
                { "name",  "w-10", "Name" },
                { "count", nil,    "Count" }
            }
        },
        {
            type = "Button",
            text = "Craft",
            x = "w/2+1",
            y = "h",
            on_click = function(self)
                capi.startCraft(cenv.cid)
                tapi.back()
            end
        },
        {
            type = "Button",
            text = "Cancel",
            w = "w/2",
            y = "h",
            on_click = "$tapi.back$"
        }
    }
}, nil, cenv)

local function submit_craft_request(toCraft)
    cenv.request_info_string = ("Requesting to craft %dx %s."):format(toCraft, cenv.item.name)
    local cid, required = capi.requestCraft(cenv.item.name, toCraft)
    if cid then
        cenv.cid = cid
        cenv.required_item_list = {}
        for k, v in pairs(required) do
            cenv.required_item_list[#cenv.required_item_list + 1] = {
                name = k,
                count = v
            }
        end
        tapi.open_screen("listing:craft_overview")
    end
end

local function submit_request(count)
    tapi.request(cenv.item, count)
    tapi.back()
    if cenv.item.count < count and cenv.item.craftable and cenv.craft_excess then
        local toCraft = count - cenv.item.count
        submit_craft_request(toCraft)
    end
end

local function submit_request_chord(self)
    local mul = 8
    if self:is_held(keys.leftShift) then
        mul = 64
    elseif self:is_held(keys.leftCtrl) then
        mul = 1
    end
    local count = self.meta * mul
    submit_request(count)
end

cenv.search_state_color = "white"

capi.subscribeTo({
    changes = function(l, fm)
        if not debug_ignore_listing_updates then
            listing_raw = l
        end
        apply_sort(cenv.search_bar)
        has_init = true
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
    apply_sort(cenv.search_bar)
end

local function use_id_change()
    apply_sort(cenv.search_bar)
end

tapi.register_screen("listing:listing", {
    type = "Screen",
    content = {
        tapi.back_button_template(),
        {
            type = "Dropdown",
            x = 3,
            y = 1,
            w = 10,
            h = 1,
            value = "All",
            options = listing_categories,
            class = "heading",
            on_change = listing_category_change
        },
        {
            type = "Button",
            x = 1,
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
            x = 4,
            y = "h",
            h = 1,
            w = "w-((turtle and turtle.craft) and 9 or 3)",
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
            h = 4,
            hidden = "$not search_options$",
            z = 1.5,
            class = "submenu",
            lz_offset = 2,
            content = {
                {
                    type = "Checkbox",
                    text = "Enable ItemDescriptors",
                    pressed = "$enable_item_descriptors$",
                    w = "w-3",
                    h = 1,
                    on_click = use_id_change
                },
                {
                    type = "Button",
                    text = "?",
                    on_click = "$tapi.open_screen('help:itemdescriptors')$",
                    x = "w-2",
                    h = 1
                },
                {
                    type = "Checkbox",
                    text = "Craft excess",
                    pressed = "$craft_excess$",
                    y = 2,
                    h = 1,
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
            y = "h-4",
            w = 11,
            h = 4,
            z = 2,
            lz_offset = 2,
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
}, function()
    if not has_init then
        init(capi.list())
    end
end, cenv)


local request_screen_args = {
    type = "Screen",
    content = {
        tapi.header_template("Request"),
        tapi.back_button_template(),
        {
            type = "Text",
            x = 1,
            y = 2,
            w = "w",
            h = "h-2",
            text = "$item.detail$",
            horizontal_alignment = "left",
            vertical_alignment = "top",
            scrollbar = true,
            padding = 1
        }
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
                on_click = submit_request_chord,
                key = "a"
            },
            {
                type = "Button",
                x = 8,
                w = 7,
                text =
                "$self:is_held(keys.leftShift) and '[S 128]' or self:is_held(keys.leftCtrl) and '[S   2]' or '[S  16]'$",
                meta = 2,
                on_click = submit_request_chord,
                key = "s"
            },
            {
                type = "Button",
                x = 15,
                w = 7,
                text =
                "$self:is_held(keys.leftShift) and '[D 256]' or self:is_held(keys.leftCtrl) and '[D   4]' or '[D  32]'$",
                meta = 4,
                on_click = submit_request_chord,
                key = "d"
            },
            {
                type = "Button",
                x = 22,
                w = 7,
                text =
                "$self:is_held(keys.leftShift) and '[F 512]' or self:is_held(keys.leftCtrl) and '[F   8]' or '[F  64]'$",
                meta = 8,
                on_click = submit_request_chord,
                key = "f"
            },
            {
                type = "Button",
                x = "w-6",
                w = 7,
                text = "[Enter]",
                meta = 8,
                on_click = submit_request_chord,
                key = "enter"
            }
        },
        y = "h"
    }
else -- input type
    ---@type shrekui.FrameArgs
    local frame = {
        type = "Frame",
        content = {
            {
                type = "Input",
                y = "h",
                id = "request-amount-input",
                on_change = function(self)
                    cenv.update_amount_calc(self)
                    if cenv.valid_request_amount then
                        submit_request(cenv.valid_request_amount)
                    end
                end,
                ignore_focus = true
            },
            {
                type = "Text",
                y = "h-1",
                h = 1,
                horizontal_alignment = "left",
                text = "$update_amount_calc(self)$"
            },
        },
        y = "h",
    }
    table.insert(request_screen_args.content, 1, frame)
end

local logger = tapi.logger.logger("listing")
cenv.request_amount_result = "64"
cenv.valid_request_amount = nil
local last_value
function cenv.update_amount_calc(self)
    ---@type shrekui.Input
    local input = self:get_root():get_widget_by_id("request-amount-input")
    local value = input:get_value()
    if value == last_value then return cenv.request_amount_result end
    last_value = value
    local f, str = load("return ceil(" .. value .. ")", nil, "t", {
        max = math.max,
        min = math.min,
        floor = math.floor,
        ceil = math.ceil
    })
    cenv.valid_request_amount = nil
    if not f then
        cenv.request_amount_result = str
    else
        local ok, r = pcall(f)
        cenv.request_amount_result = r or "nil"
        if ok and type(r) == "number" then
            cenv.valid_request_amount = r
        end
    end
    return cenv.request_amount_result
end

tapi.register_screen("listing:request_craft", {
    type = "Screen",
    content = {
        tapi.header_template("Crafting"),
        tapi.back_button_template(),
        {
            type = "Text",
            x = 1,
            y = 2,
            w = "w",
            h = "h-2",
            text = "$item.detail$",
            horizontal_alignment = "left",
            vertical_alignment = "top",
            scrollbar = true,
            padding = 1
        },
        {
            type = "Input",
            y = "h",
            id = "request-amount-input",
            on_change = function(self)
                cenv.update_amount_calc(self)
                if cenv.valid_request_amount then
                    tapi.back()
                    submit_craft_request(cenv.valid_request_amount)
                end
            end,
            ignore_focus = true
        },
        {
            type = "Text",
            y = "h-1",
            h = 1,
            horizontal_alignment = "left",
            text = "$update_amount_calc(self)$",
            class = "warning-button"
        }
    }
}, function(self)
    local input = self:get_root():get_widget_by_id("request-amount-input")
    input:set_value(tostring(cenv.item.maxCount))
end, cenv)


tapi.register_screen("listing:request", request_screen_args, function(self)
    if sset.get(sset.requestScreenType) == "input" then
        self:get_widget_by_id("request-amount-input"):set_value(tostring(cenv.item.maxCount))
    end
end, cenv)


tapi.register_menu_button(1, "Listing", "listing:listing")
