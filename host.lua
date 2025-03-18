local acl = require("libs.ACL")
local ID = require("libs.ItemDescriptor")
local stl = require("libs.STL")

local protocol = require("libs.clientlib").protocol
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

---Try to call a function, returns nil on error
---@param f function
---@param args any[]?
---@param self boolean
local function tryCall(f, args, self)
    args = args or {}
    local pf
    if self then
        pf = function()
            return f(f, table.unpack(args, 1, args.n))
        end
    else
        pf = function()
            return f(table.unpack(args, 1, args.n))
        end
    end
    local result = table.pack(pcall(pf))
    if not result[1] then
        error(result[2])
    end
    return table.unpack(result, 2, result.n)
end

---@param msg table
local function parseMessage(msg)
    if type(msg) ~= "table" then return end
    if msg.side == "server" then return end
    if msg.type == "list" then
        return inv.reserve:list()
    elseif msg.type == "getSlotUsage" then
        return inv.reserve:getSlotUsage()
    elseif msg.type == "pushItems" then
        -- return tryCall(inv.reserve.pushItems, msg.args, true)
        return inv.reserve:pushItems(
            msg.to,
            ID.unserialize(msg.item),
            msg.limit,
            msg.toSlot)
        -- return tryCall(inv.reserve.pushItems, {
        --     msg.to,
        --     ID.unserialize(msg.item),
        --     msg.limit,
        --     msg.toSlot
        -- }, true)
    elseif msg.type == "pullItems" then
        return inv.reserve:pullItems(msg.from, msg.slot, msg.limit)
    end
end

local function onChanged(self)
    rednet.broadcast({
        type = "inventoryChange",
        list = self:list()
    }, protocol)
end
inv.reserve:setChangedCallback(onChanged)
onChanged(inv.reserve)

local messageQueuedEvent = "message_queued"

---@type {message:table,sender:number}[]
local messageQueue = {}
local function processMessageThread()
    while true do
        local msg = table.remove(messageQueue, 1)
        if msg then
            local response = table.pack(parseMessage(msg.message))
            print("got message from", msg.sender)
            if msg.message and #response > 0 then
                rednet.send(msg.sender, { result = response, type = msg.message.type, side = "server" }, protocol)
            end
        else
            os.pullEvent(messageQueuedEvent)
        end
    end
end

local f = { function()
    while true do
        local sender, message, prot = rednet.receive(protocol)
        if type(message) == "table" then
            messageQueue[#messageQueue + 1] = { message = message, sender = sender }
            print("Queued message from", sender)
            os.queueEvent(messageQueuedEvent)
            rednet.send(sender, { type = "ACK", ftype = message.type, side = "server" }, protocol)
        end
    end
end }

for i = 1, 1 do
    f[#f + 1] = processMessageThread
end

local hostTask = stl.Task.new(f, "Host")
inv.scheduler.queueTask(hostTask)

inv.reserve:dump("test.txt")

inv.run()
