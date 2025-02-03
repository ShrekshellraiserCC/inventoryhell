local Reserve = require("Reserve")

local r = Reserve.fromInventories({ "minecraft:chest_1" })

local function dump(fn, d)
    local f = assert(fs.open(fn, "w"))
    f.write(textutils.serialise(d))
    f.close()
end

dump("pre.txt", r)

local Item = require("ItemDescriptor")
local d = Item.fromName("minecraft:stone")
local b = r:split(d, 10)

dump("post.txt", r)
dump("split.txt", b)
