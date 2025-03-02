local Reserve = require("VirtualInv")


local function dump(fn, d)
    local f = assert(fs.open(fn, "w"))
    f.write(textutils.serialise(d))
    f.close()
end

local function wait(s, d)
    if d then
        dump("last.txt", d)
    end
    print("Press <Enter>")
    read()
    print(s)
end

local r = Reserve.fromInventories({ "minecraft:chest_1" })

wait("Defrag", r)
r:defrag()
local Item = require("ItemDescriptor")
local cobble = Item.fromName("minecraft:cobblestone")
local b = r:split(cobble, 16)
