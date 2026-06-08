local ItemDescriptor = require "libs.ItemDescriptor"
local coordLib = require "libs.Coordinates"

---Furnace recipe provider
---@param acl ACL
return function(acl)
    acl.craft.newMachineType("furnace", { { 1, 1 } }, { 1, 3 }, function(n)
        return math.ceil(n / 8) * 8
    end)
    for _, v in ipairs(peripheral.getNames()) do
        if v:match("minecraft:furnace") then
            acl.craft.registerMachine("furnace", v)
        end
    end
    acl.craft.registerJSONParser("minecraft:smelting", function(input)
        local items = { ItemDescriptor.parseJSON(input.ingredient) }
        local product = coordLib.ItemCoordinate(input.result)
        acl.craft.registerRecipe("furnace", items, { 1 }, product, 1)
    end)
end
