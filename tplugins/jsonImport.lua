local ui = require "libs.ui"
local sset = require "libs.sset"

--- Settings Menu plugin
---@param tlib TermLib
return function(tlib)
    local importedTime
    local importedTotal = 0
    local importedSuccess = 0
    local function render()
        local w, h = tlib.win.main.getSize()
        ui.header(tlib.win.main, "Import JSON Recipes")
        ui.preset(tlib.win.main, ui.presets.list)
        ui.cursor(tlib.win.main, 2, 3)
        tlib.win.main.write("Drag+Drop JSON recipe files here!")
        if importedTime then
            if os.epoch("utc") - importedTime > 1000 then
                importedTime = nil
            end
            local istr = ("Imported %d/%d"):format(importedSuccess, importedTotal)
            ui.cursor(tlib.win.main, w - #istr, h - 2)
            -- ui.preset(tlib.win.main, ui.presets.selected)
            tlib.win.main.write(istr)
        end
        ui.footer(tlib.win.main, ui.icons.back .. "[S Save]")
    end
    local function onEvent(e)
        if e[1] == "file_transfer" then
            importedTotal = 0
            importedSuccess = 0
            for _, file in ipairs(e[2].getFiles()) do
                importedTotal = importedTotal + 1
                if tlib.clientlib.importJSON(file.readAll()) then
                    importedSuccess = importedSuccess + 1
                end
                file.close()
            end
            importedTime = os.epoch("utc")
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
