local ui = require "libs.ui"
local sset = require "libs.sset"

--- Settings Menu plugin
---@param tlib TermLib
return function(tlib)
    local w, h         = tlib.win.main.getSize()
    local wrap         = ui.tableGuiWrapper(
        tlib.win.list, sset.settingList,
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
        end
    )
    local reread       = ui.reread(tlib.win.input, 3, 1, w - 2)
    local filteredList = {}
    local function filter()
        filteredList = {}
        local ok = pcall(string.match, reread.buffer, reread.buffer)
        if not ok then
            filteredList = sset.settingList
        end
        for k, v in ipairs(sset.settingList) do
            if v.name:match(reread.buffer) then
                filteredList[#filteredList + 1] = v
            end
        end
    end
    local draw    = function()
        wrap.setTable(filteredList)
        wrap.draw()
        ui.preset(tlib.win.input, ui.presets.input)
        tlib.win.input.clear()
        ui.preset(tlib.win.input, ui.presets.footer)
        ui.cursor(tlib.win.input, 1, 1)
        tlib.win.input.write(ui.icons.back)
        ui.preset(tlib.win.input, ui.presets.input)
        tlib.win.input.write(">")
        reread:render()
        tlib.win.list.setVisible(true)
        tlib.win.input.setVisible(true)
    end
    local onEvent = function(e)
        if not wrap.onEvent(e) then
            reread:onEvent(e)
            filter()
        end
    end
    tlib.registerUI("Settings", draw, onEvent, nil, wrap.restartTicker)
end
