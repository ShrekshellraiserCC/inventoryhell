local ui = require "libs.ui"
local sset = require "libs.sset"

--- Settings Menu plugin
---@param tlib TermLib
return function(tlib)
    local function filter(t, s)
        local filteredList = {}
        local ok = pcall(string.match, s, s)
        if not ok then
            filteredList = t
        end
        for k, v in ipairs(t) do
            if v.name:match(s) then
                filteredList[#filteredList + 1] = v
            end
        end
        return filteredList
    end
    local wrap = ui.tableGuiWrapper(
        tlib.win.list,
        sset.settingList,
        function(v)
            local name = v.name
            local value = sset.get(v)
            if value ~= nil and value == v.default then
                value = tostring(value) .. "*"
            else
                value = tostring(value)
            end
            return { name, value, v.desc }
        end, { "Name", "Value", "Description" }, function(i, v)
            tlib.win.input.setCursorBlink(false)
            ui.changeSetting(tlib.win.main, v)
        end, nil, sset.get(sset.unlockMouse))
    local swrap = ui.searchableTableGUIWrapper(
        tlib.win.main,
        tlib.win.list,
        tlib.win.input,
        filter,
        wrap
    )
    tlib.registerUI("Settings", swrap.draw, swrap.onEvent, nil, swrap.restartTicker)
end
