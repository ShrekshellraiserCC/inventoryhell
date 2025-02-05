local lib = require("ACL")
local ID = require("ItemDescriptor")

sleep(3)
local inv = lib.wrap({ "minecraft:chest_1" }, {}, {})

local turtle = "turtle_0"

term.clear()
term.setCursorPos(1, 10)


-- return TaskLib.Task.new({ function()
--     local f = assert(fs.open("test.txt", "w"))
--     f.write(textutils.serialise(self))
--     f.close()
-- end }):addSubtask(TaskLib.Task.new(f))

local ctask = inv.TurtleCraftTask.craft(
    { ID.fromName("minecraft:cobblestone") },
    { 1, 1, 1, 1, nil, 1, 1, 1, 1 },
    64
)
ctask:queue()

os.queueEvent("dummy")
inv.run()
