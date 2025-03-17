local clientlib = require("clientlib")
clientlib.open()
local ui = require("ui")

local list = clientlib.list()

local win = window.create(term.current(), 1, 1, term.getSize())
local wrap = ui.tableGuiWrapper(win, {}, function(v)
    return { tostring(v.count), v.displayName }
end, { "Count", "Name" })
local function render()
    wrap.setTable(list)
    wrap.draw()
end

local function main()
    while true do
        render()
        local e = table.pack(os.pullEvent())
        wrap.onEvent(e)
    end
end
main()
