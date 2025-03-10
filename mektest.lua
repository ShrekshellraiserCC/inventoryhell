local lib = require("ACL")
local ID = require("ItemDescriptor")


local chests = { peripheral.find("inventory") }
local chestList = {}
for i, v in ipairs(peripheral.getNames()) do
    if v:match("minecraft:chest") then
        chestList[#chestList + 1] = v
    end
end
local inv = lib.wrap(chestList)

local infuser = "metallurgicInfuser_0"
local iron = ID.fromName("minecraft:iron_ingot")
local reds = ID.fromName("minecraft:redstone")
local diamond = ID.fromName("minecraft:diamond")
local enrichedRedstone = ID.fromName("mekanism:enriched_redstone")

inv.craft.newMachineType("infuser", { { 1, 1 }, { 2, 1 } }, { 3, 1 })
inv.craft.registerMachine("infuser", infuser,
    { "minecraft:hopper_0", "minecraft:hopper_1", "minecraft:dropper_0" })

inv.craft.newMachineType("enricher", { { 1, 1 } }, { 2, 1 })
inv.craft.registerMachine("enricher", "enricher_0", { "minecraft:hopper_2", "minecraft:dropper_3" })
inv.craft.registerMachine("enricher", "enricher_1", { "minecraft:hopper_3", "minecraft:dropper_4" })

local enrichTask = inv.craft.generic(1)
    :reserveMachine("enricher")
    :setRecipe({ reds }, { 1 }, 1)
    :build()

local diamondEnrichTask = inv.craft.generic(1)
    :reserveMachine("enricher")
    :setRecipe({ diamond }, { 1 }, 1)
    :build()
    :setPriority(2)
    :queue()

local infuseTask = inv.craft.generic(1)
    :reserveMachine("infuser")
    :setRecipe({ iron, enrichedRedstone }, { { 1, 8 }, 2 }, 8)
    :build()

infuseTask:addSubtask(enrichTask)
infuseTask:queue()

inv:run()
