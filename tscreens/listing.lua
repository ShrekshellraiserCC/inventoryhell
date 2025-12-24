_ENV = _ENV --[[@as SSDTermPluginENV]]

local function item_select(self, item, idx)
    ---@cast self Screen
    _ENV.item = item
    _ENV.item.detail = nil
    _ENV.item.detail = textutils.serialize(item)
    _ENV.tapi.open_screen("request")
end


local function toggle_craft_button(self)
    _ENV.tapi.lock_inventory(_ENV.craft_active)
    if not _ENV.craft_active then
        _ENV.tapi.clear_reserved_slots()
        _ENV.tapi.lock_inventory(false)
    end
end

return {
    type = "Screen",
    content = {
        {
            type = "Dropdown",
            x = 1,
            y = 1,
            w = 10,
            h = 1,
            value = "All",
            options = { "All", "Stored", "Craftables" }
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
            type = "Button",
            x = 2,
            y = "h",
            w = 3,
            h = 1,
            text = "  >",
            toggle = true,
            pressed = "$search_options$"
        },
        {
            type = "Input",
            x = 5,
            y = "h",
            h = 1,
            w = "w-((turtle and turtle.craft) and 10 or 4)",
            ignore_focus = true,
            always_update = true,
            on_change = "$search_change$",
            value = "$search_bar$"
        },
        {
            type = "Frame",
            x = 1,
            y = "h-5",
            w = "w-((turtle and turtle.craft) and 11 or 0)",
            h = "5",
            hidden = "$not search_options$",
            z = 3,
            content = {
                {
                    type = "Button",
                    text = "FUCK"
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
}
