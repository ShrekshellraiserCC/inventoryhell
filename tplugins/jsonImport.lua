local ui = require "libs.ui"
local sset = require "libs.sset"

--- Settings Menu plugin
---@param tlib TermLib
return function(tlib)
    local function render()
        ui.header(tlib.win.main, "Import JSON Recipes")
        ui.preset(tlib.win.main, ui.presets.list)
        ui.cursor(tlib.win.main, 2, 3)
        tlib.win.main.write("Drag+Drop JSON recipe files here!")
        ui.footer(tlib.win.main, ui.icons.back .. "[S Save]")
    end
    local function onEvent(e)
        if e[1] == "file_transfer" then
            for _, file in ipairs(e[2].getFiles()) do
                tlib.clientlib.importJSON(file.readAll())
                file.close()
            end
        elseif e[1] == "key" and e[2] == keys.s then
            local w, h = tlib.win.main.getSize()
            ui.preset(tlib.win.main, ui.presets.selected)
            tlib.win.main.setCursorPos(2, h)
            tlib.win.main.write("[S Save]")
            tlib.clientlib.saveRecipes()
        end
    end
    tlib.registerUI("Import JSON", render, onEvent)
end
