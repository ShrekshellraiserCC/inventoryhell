local ui = require "libs.ui"
local sset = require "libs.sset"

--- Settings Menu plugin
---@param tlib TermLib
return function(tlib)
    local hostTasks = {}
    local showLocal = false
    local wrap = ui.tableGuiWrapper(
        tlib.win.list,
        hostTasks,
        function(v)
            return {
                v.name or "",
                tostring(v.running),
                tostring(v.count),
                tostring(v.id)
            }
        end,
        { "Name", "Running", "Count" },
        function(i, v)

        end, nil, sset.get(sset.unlockMouse)
    )
    local function render()
        if showLocal then
            wrap.setTable(tlib.scheduler.list())
        else
            wrap.setTable(hostTasks)
        end
        wrap.draw()
        ui.preset(tlib.win.input, ui.presets.footer)
        tlib.win.input.clear()
        ui.cursor(tlib.win.input, 1, 1)
        local s = (" [M %s]"):format(showLocal and "Local" or "Global")
        tlib.win.input.write(ui.icons.back .. s)
        tlib.win.list.setVisible(true)
        tlib.win.input.setVisible(true)
    end
    local function onEvent(e)
        if not wrap.onEvent(e) then
            if e[1] == "key" and e[2] == keys.m then
                showLocal = not showLocal
            end
        end
    end
    local function onUpdate(l)
        hostTasks = l
    end
    tlib.scheduler.queueTask(tlib.STL.Task.new({
        function()
            tlib.clientlib.subscribeToTasks(onUpdate)
        end,
        function()
            onUpdate(tlib.clientlib.listTasks())
        end
    }, "TaskUpdater"))
    tlib.registerUI("Tasks", render, onEvent)
end
