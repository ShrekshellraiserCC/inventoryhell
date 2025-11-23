local ui = require "libs.ui"
local sset = require "libs.sset"

--- Settings Menu plugin
---@param tlib TermLib
return function(tlib)
    ---@type RecipeInfo[]
    local list = {}
    ---@param t RecipeInfo[]
    local function filter(t, s)
        local nt = t
        local ok = pcall(string.match, s, s)
        if ok then
            nt = {}
            for k, v in ipairs(t) do
                if v.name:match(s) or v.type:match(s) then
                    nt[#nt + 1] = v
                end
            end
        end
        return nt
    end
    local wrap = ui.tableGuiWrapper(
        tlib.win.list,
        list,
        function(v)
            return { v.displayName or v.name, v.type }
        end, { "Name", "Type" }, function(i, v)

        end, nil, sset.get(sset.unlockMouse))
    local swrap = ui.searchableTableGUIWrapper(
        tlib.win.main,
        tlib.win.list,
        tlib.win.input,
        filter,
        wrap
    )
    local function render()
        swrap.draw()
        tlib.win.list.setVisible(true)
        tlib.win.input.setVisible(true)
    end
    local function onEvent(e)
        swrap.onEvent(e)
    end
    local function onSet()
        list = tlib.clientlib.listRecipes()
        swrap.setTable(list)
    end
    tlib.registerUI("Recipes", render, onEvent, nil, onSet)
end
