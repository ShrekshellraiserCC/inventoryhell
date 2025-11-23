local lib = require("libs.ACL")
local ID = require("libs.ItemDescriptor")

term.clear()
term.setCursorPos(1, 10)

local test = ID.gateOr(ID.gateAnd(ID.gateNot(ID.fromPattern("minecraft:")), ID.hasTag("minecraft:logs")),
    ID.fromName("minecraft:stone", ID.WILDCARD))

print(test:serialize())
print(ID.unserialize(test:serialize()):serialize())

local test2 = ID.fromName("minecraft:stone")

print(test2:serialize())
print(ID.unserialize(test2:serialize()):serialize())
