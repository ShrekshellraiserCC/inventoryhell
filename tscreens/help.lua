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

tapi.register_screen("help_itemdescriptors", {
    type = "Screen",
    content = {
        {
            type = "Text",
            h = 1,
            text = "ItemDescriptors Help",
            horizontal_alignment = "left",
            class = "heading"
        },
        {
            type = "Text",
            h = "h-2",
            y = 2,
            text = itemdescriptors_help_string,
            horizontal_alignment = "left",
            scrollbar = true
        },
        _ENV.back_button_template {
            w = "w"
        }
    }
})
