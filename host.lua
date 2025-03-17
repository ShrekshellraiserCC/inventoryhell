local acl = require("ACL")
local ID = require("ItemDescriptor")
local coord = require("Coordinates")
local stl = require("STL")

local protocol = require("clientlib").protocol
local hostname = "HOST_TEST"
-- Central host process for the storage system
local modem = peripheral.find("modem", function(name, wrapped)
    return not wrapped.isWireless()
end)
rednet.open(peripheral.getName(modem))
rednet.host(protocol, hostname)

local chestList = {}
for i, v in ipairs(peripheral.getNames()) do
    if v:match("minecraft:chest") then
        chestList[#chestList + 1] = v
    end
end
local inv = acl.wrap(chestList, modem)

---@param msg table
---@return table?
local function parseMessage(msg)
    if type(msg) ~= "table" then return end
    if msg.side == "server" then return end
    if msg.type == "list" then
        return inv.reserve:list()
    elseif msg.type == "getSlotUsage" then
        return inv.reserve:getSlotUsage()
    end
end

local hostTask = stl.Task.new({ function()
    while true do
        local sender, message, prot = rednet.receive(protocol)
        local response = parseMessage(message)
        print("got message from", sender)
        if message and response then
            rednet.send(sender, { result = response, type = message.type, side = "server" }, protocol)
        end
    end
end }, "Host")
inv.scheduler.queueTask(hostTask)

inv.reserve:dump("test.txt")

inv.run()
