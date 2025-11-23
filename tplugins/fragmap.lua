local ui = require "libs.ui"

---@param tlib TermLib
return function(tlib)
    local labels = false
    local scroll = 0
    local maxScroll
    local fragMapDraw = function()
        ui.header(tlib.win.main, "FragMap View")
        local w, h = tlib.win.main.getSize()
        local fh = ui.drawFragMap(tlib.win.main, tlib.fragMap, 2, 3, w - 3, h - 4, labels, scroll)
        ui.color(tlib.win.main, ui.colmap.listFg, ui.colmap.listBg)
        if scroll > 0 then
            tlib.win.main.setCursorPos(w, 2)
            tlib.win.main.write(ui.icons.up)
        end
        maxScroll = fh - (h - 4)
        if scroll < maxScroll then
            tlib.win.main.setCursorPos(w, h - 1)
            tlib.win.main.write(ui.icons.down)
        elseif scroll > maxScroll then
            scroll = maxScroll
        end
        ui.footer(tlib.win.main, ui.icons.back .. " [M mode]")
    end
    local fragMapOnEvent = function(e)
        if e[1] == "key" then
            if e[2] == keys.m then
                labels = not labels
            elseif e[2] == keys.up then
                scroll = math.max(0, scroll - 1)
            elseif e[2] == keys.down then
                scroll = math.min(scroll + 1, maxScroll)
            end
        elseif e[1] == "mouse_scroll" then
            scroll = math.min(math.max(scroll + e[2], 0), maxScroll)
        end
    end
    tlib.registerUI("FragMap", fragMapDraw, fragMapOnEvent)
end
