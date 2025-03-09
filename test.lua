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

inv.reserve:dump("test.txt")

local stacks = 15
local stackSize = 12

local cobble = ID.fromName("minecraft:cobblestone")
local coal = ID.fromName("minecraft:coal")
-- local cobbleReserve = assert(inv.reserve:split(cobble, stackSize * 8 * stacks), "Not enough cobble!")

-- cobbleReserve:dump("cobbleReserve.txt")
local produced = 8
local pullSlot = 3
local count = 2
local ctask = inv.MachineCraftTask.generic(2)
    :reserveMachine("furnace")
    :setRecipe({ cobble, coal }, { 1, { 2, 8 } }, 8)
    :build()

ctask:queue()

os.queueEvent("dummy")
inv.run()
