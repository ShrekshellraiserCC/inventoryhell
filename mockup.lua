local inventories = { "chest_1", "chest_2", "chest_3" }

-- Make this take names or peripherals interchangably
local inventory = InventoryCluster.new(inventories)

local cobble = ItemDescriptor.fromName("minecraft:cobblestone")

local reserve = assert(inventory.reserve({
  [cobble] = 8
}))

local turtle = "turtle_0"
inventory.pullTask(turtle):fromSlot(1)
    :addSubtask(
      inventory.pushTask(turtle)
      :setReserve(reserve)
      :distributeToSlots(cobble, { 1, 2, 3, 5, 6, 7, 9, 10, 11 }, 1)
    ):queue()


local sword = ItemDescriptor.fromPattern("minecraft:.-_sword", ItemDescriptor.WILDCARD)
local trashTurtle = "turtle_1"
inventory.pushTask(trashTurtle):dumbPush(sword):setRepeat(true):queue()
