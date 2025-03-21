local ui = require "libs.ui"
local sset = require "libs.sset"

--- Settings Menu plugin
---@param tlib TermLib
return function(tlib)
    local wrap    = ui.tableGuiWrapper(
        tlib.win.list, sset.settingList,
        function(v)
            local name = v.device .. ":" .. v.name
            local value = sset.get(v)
            if value ~= nil and value == v.default then
                value = tostring(value) .. "*"
            else
                value = tostring(value)
            end
            return { name, value, v.desc }
        end, { "Name", "Value", "Description" }, function(i, v)
            ui.changeSetting(tlib.win.main, v)
        end
    )
    local draw    = function()
        wrap.draw()
        ui.footer(tlib.win.main, ui.icons.back)
    end
    local onEvent = function(e)
        wrap.onEvent(e)
    end
    tlib.registerUI("Settings", draw, onEvent, nil, wrap.restartTicker)
end
