local lib = require("libs.ACL")
local ID = require("libs.ItemDescriptor")
local coord = require("libs.Coordinates")

term.clear()
term.setCursorPos(1, 5)

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
local enrichedDiamond = ID.fromName("mekanism:enriched_diamond")
local enrichedCarbon = ID.fromName("mekanism:enriched_carbon")
local enrichedIron = ID.fromName("mekanism:enriched_iron")
local steelDust = ID.fromName("mekanism:dust_steel")
local infusedAlloy = ID.fromName("mekanism:alloy_infused")
local reinforcedAlloy = ID.fromName("mekanism:alloy_reinforced")
local glass = ID.fromName("minecraft:glass")
local sand = ID.fromName("minecraft:sand")
local coal = ID.fromName("minecraft:coal")
local steel = ID.fromName("mekanism:ingot_steel")
local steelCasing = ID.fromName("mekanism:steel_casing")
local osmium = ID.fromName("mekanism:ingot_osmium")
local circuit = ID.fromName("mekanism:basic_control_circuit")
local smelter = ID.fromName("mekanism:energized_smelter")

inv.craft.newAlternativeMachineType("efurnace", "furnace", { { 1, 1 } }, { 2, 1 })
inv.craft.registerMachine("efurnace", "efurnace_0", { "minecraft:hopper_4", "minecraft:dropper_5" })

inv.craft.registerRecipe("furnace", { sand }, { 1 }, glass:toCoord(), 1)
inv.craft.registerRecipe("furnace", { steelDust }, { 1 }, steel:toCoord(), 1)
inv.craft.registerRecipe("grid", { steel, glass, osmium }, { 1, 2, 1, 2, 3, 2, 1, 2, 1 }, steelCasing:toCoord(), 1)
inv.craft.registerRecipe("grid", { reds, circuit, glass, steelCasing }, { 1, 2, 1, 3, 4, 3, 1, 2, 1 }, smelter:toCoord(),
    1)

inv.craft.newMachineType("infuser", { { 1, 1 }, { 2, 1 } }, { 3, 1 })
-- Extra, Item
inv.craft.registerMachine("infuser", infuser,
    { "minecraft:hopper_0", "minecraft:hopper_1", "minecraft:dropper_0" })

inv.craft.registerRecipe("infuser", { enrichedRedstone, iron }, { 1, { 2, 8 } }, infusedAlloy:toCoord(), 8)
inv.craft.registerRecipe("infuser", { enrichedDiamond, infusedAlloy }, { 1, { 2, 4 } }, reinforcedAlloy:toCoord(), 4)
inv.craft.registerRecipe("infuser", { enrichedCarbon, iron }, { 1, { 2, 8 } }, enrichedIron:toCoord(), 8)
inv.craft.registerRecipe("infuser", { enrichedCarbon, enrichedIron }, { 1, { 2, 8 } }, steelDust:toCoord(), 8)
inv.craft.registerRecipe("infuser", { enrichedRedstone, osmium }, { 1, { 2, 4 } }, circuit:toCoord(), 4)

inv.craft.newMachineType("enricher", { { 1, 1 } }, { 2, 1 })
inv.craft.registerMachine("enricher", "enricher_0", { "minecraft:hopper_2", "minecraft:dropper_3" })
inv.craft.registerMachine("enricher", "enricher_1", { "minecraft:hopper_3", "minecraft:dropper_4" })


inv.craft.registerRecipe("enricher", { diamond }, { 1 }, enrichedDiamond:toCoord(), 1)
inv.craft.registerRecipe("enricher", { reds }, { 1 }, enrichedRedstone:toCoord(), 1)
inv.craft.registerRecipe("enricher", { coal }, { 1 }, enrichedCarbon:toCoord(), 1)

inv.craft.saveRecipes()

-- local task = assert(inv.craft.craft(smelter, 1), "Not enough items!")

-- print(task:toString())
-- task:queue()

-- inv:run()
