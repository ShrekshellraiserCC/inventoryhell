local lib = require("ACL")
local ID = require("ItemDescriptor")

term.clear()
term.setCursorPos(1, 10)

-- print("Sleeping 3 seconds...")
-- sleep(3)

local chests = { peripheral.find("inventory") }
local chestList = {}
for i, v in ipairs(chests) do
    chestList[i] = peripheral.getName(v)
    print(i, peripheral.getName(v))
end
local inv = lib.wrap(chestList)

local stacks = 15
local stackSize = 12

local cobble = ID.fromName("minecraft:cobblestone")
local cobbleReserve = assert(inv.reserve:split(cobble, stackSize * 8 * stacks), "Not enough cobble!")

cobbleReserve:dump("cobbleReserve.txt")

for i = 1, stacks do
    local ctask = inv.TurtleCraftTask.craft(
        { cobble },
        { 1, 1, 1, 1, nil, 1, 1, 1, 1 },
        stackSize,
        cobbleReserve
    )
    ctask:queue()
end

os.queueEvent("dummy")
inv.run()
