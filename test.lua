local lib = require("ACL")
local ID = require("ItemDescriptor")

local inv = lib.wrap({ "minecraft:chest_1" })

term.clear()
term.setCursorPos(1, 10)

local cobble = ID.fromName("minecraft:cobblestone")
local cobbleReserve = assert(inv.reserve:split(cobble, 64 * 8), "Not enough cobble!")

cobbleReserve:dump("cobbleReserve.txt")

local ctask = inv.TurtleCraftTask.craft(
    { cobble },
    { 1, 1, 1, 1, nil, 1, 1, 1, 1 },
    64,
    cobbleReserve,
    function()
        inv.reserve:dump("POSTCRAFT.txt")
        cobbleReserve:free()
    end
)
ctask:queue()

os.queueEvent("dummy")
inv.run()
