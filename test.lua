local lib = require("ACL")

-- sleep(3)
local inv = lib.wrap({ "minecraft:chest_0", "minecraft:chest_1" }, {}, {})

local turtle = "turtle_0"

term.clear()
term.setCursorPos(1, 10)


-- return TaskLib.Task.new({ function()
--     local f = assert(fs.open("test.txt", "w"))
--     f.write(textutils.serialise(self))
--     f.close()
-- end }):addSubtask(TaskLib.Task.new(f))

os.queueEvent("dummy")
inv.run()
