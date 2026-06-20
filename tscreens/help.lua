_ENV = _ENV --[[@as SSDTermPluginENV]]

local itemdescriptors_help_string = [[
ItemDescriptors are a string representation of complex item filters. Here is a list of valid ItemDescriptor selectors. Text between <> is descriptive, and should be replaced.

 !<statement> - Inverts the ItemDescriptor in statement
 N<name> - selects items by absolute name
 T<tag> - selects items by absolute tag
 P<pattern> - matches item names using Lua patterns
 * - wildcard, matches all items
 #<op><count> - matches items by count. <op> can be <, >, ==, >=, or <=
 S - matches items that can stack (maxCount>1)

You can also create compound statements with ItemDescriptors, supporting OR/AND operations.
 (<a>&<b>) - ands the matches of A and B
 (<a>|<b>) - ors the matches of A and B

ItemDescriptors can contain as many specifiers as required. For example

 ((Tminecraft:log&#>100)&!Nminecraft:jungle_log)

will select any logs that have a count > 100, and are not Jungle Logs.
]]

tapi.register_screen("help:itemdescriptors", {
    type = "Screen",
    content = {
        _ENV.back_button_template(),
        {
            type = "Text",
            h = 1,
            text = "ItemDescriptors Help",
            class = "heading"
        },
        {
            type = "Text",
            y = 2,
            text = itemdescriptors_help_string,
            horizontal_alignment = "left",
            scrollbar = true,
            padding = 1
        },
    }
})

local edit_recipe_help_string = [[
Recipes consist of a list of items, and a list of SlotMaps.

On the left is your list of items, you can click the +/- buttons to create new and delete items.
Click on an item in the list to select it
Then use the input box or + button to the right to input an ItemDescriptor.

Once you have your items prepared, select a recipe slot in the right list.
Use the dropdown to select one of the items for the slot, and the input to set the quantity.
Click the red x to clear that slot.
]]

tapi.register_screen("help:edit_recipe", {
    type = "Screen",
    content = {
        _ENV.back_button_template(),
        {
            type = "Text",
            h = 1,
            text = "Recipe Help",
            class = "heading"
        },
        {
            type = "Text",
            y = 2,
            text = edit_recipe_help_string,
            horizontal_alignment = "left",
            scrollbar = true,
            padding = 1
        },
    }
})
