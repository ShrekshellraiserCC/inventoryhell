local Reserve = require("Reserve")


local function dump(fn, d)
    local f = assert(fs.open(fn, "w"))
    f.write(textutils.serialise(d))
    f.close()
end

local r = Reserve.fromInventories({ "minecraft:chest_1" })
dump("pre.txt", r)

r:defrag()
local Item = require("ItemDescriptor")
local d = Item.fromName("minecraft:cobblestone")
local b = r:split(d, 16)

dump("post.txt", r)
dump("split.txt", b)
