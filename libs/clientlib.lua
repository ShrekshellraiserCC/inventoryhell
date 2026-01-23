local sset = require "libs.sset"
local clientlib = {}

clientlib.protocol = "SHREKSTORAGE"

local hid, modem, hmn
hid = sset.get(sset.hid)
hmn = sset.get(sset.hmn)

local logger
local function log(s, ...)
    if logger then
        logger(s, ...)
    end
end

function clientlib.setLogger(l)
    logger = l
end

local serverStates = {
    MISSING = "MISSING",
    UNKNOWN = "UNKNOWN",
    CONNECTED = "CONNECTED",
    STARTING = "STARTING"
}
local serverState = serverStates.UNKNOWN
local scanStatus = {}
local throbberStates = { "\129", "\130", "\132", "\136" }
local ackThrobberStates = throbberStates
-- local ackThrobberStates = { "\x85", "\x83", "\x8a", "\x8c" }
--{ "\x8d", "\x85", "\x87", "\x83", "\x8b", "\x8a", "\x8e", "\x8c" }
--{ "\3", "\4", "\5", "\6" }
--{ "\186", "\7" }
--{ "|", "/", "-", "\\" }
local rednetTimeout = 0.3
local maxTimeouts = 2      -- 2 * 0.2 = 0.4 seconds
local maxRounds = 3        -- 3 failures before giving up.
local maxAckTimeouts = 100 -- 100 * 0.2 = 30 seconds

local throbberState = " "
clientlib.statusString = "UNKNOWN"


local function getThrobberChar(i, gotAck)
    return gotAck and ackThrobberStates[(i % #ackThrobberStates) + 1]
        or throbberStates[(i % #throbberStates) + 1]
end


local function getTenths(n)
    local ten = n * 10
    return ten - math.floor(ten)
end

clientlib.statusWidth = 16
local function updateStatusString()
    local s = "MISSING"
    if serverState == serverStates.STARTING then
        s = "SCANNING"
        local p = scanStatus.scanned / scanStatus.total
        local w = clientlib.statusWidth - 8
        local ps = ("\127"):rep(math.floor(w * p))
        if p < 1 and getTenths(p) > 0.5 then
            ps = ps .. "\149"
        end
        ps = ps .. (" "):rep(w - #ps)
        s = scanStatus.stage .. ("[%s]"):format(ps)
    elseif serverState == serverStates.CONNECTED then
        s = "CONNNECTED"
    elseif serverState == serverStates.UNKNOWN then
        s = "UNKNOWN"
    end
    clientlib.statusString = (s .. throbberState):sub(-clientlib.statusWidth)
end

---Show an activity throbber in the corner
local function updateThrobberStatus(i, gotAck)
    throbberState = getThrobberChar(i, gotAck)
    updateStatusString()
end

local throbberTick = 0
local throbberInterval = 0.3
local function tickThrobber()
    while true do
        sleep(throbberInterval)
        throbberTick = throbberTick + 1
    end
end
local uid = 0
local function getUid()
    uid = uid + 1
    return uid
end

---@return table|number|boolean?
local function sendAndRecieve(msg)
    local id = getUid()
    msg.id = id
    log("Sent request %d type=%s", id, msg.type)
    rednet.send(hid, msg, clientlib.protocol)
    local timeouts = 0
    local rounds = 0
    local gotAck = false
    while true do
        -- showThrobber(throbberTick, gotAck)
        local sender, response = rednet.receive(clientlib.protocol, rednetTimeout)
        throbberTick = throbberTick + 1
        updateThrobberStatus(throbberTick)
        if sender == hid and type(response) == "table"
            and response.side == "server" and response.id == id then
            serverState = serverStates.CONNECTED
            if response.type == msg.type then
                throbberState = " "
                log("Got response for %d", id)
                updateStatusString()
                return response.result
            elseif response.type == "ACK" and response.ftype == msg.type then
                gotAck = true
                log("Got ACK for %d", id)
            elseif response.type == "ERROR" then
                error(("Got error from server while processing request:\n%s"):format(response.error), 0)
            end
        elseif sender == nil then
            timeouts = timeouts + 1
        end
        if timeouts > maxTimeouts and not gotAck then
            rounds = rounds + 1
            if rounds > maxRounds then
                serverState = serverStates.MISSING
                throbberState = "?"
                updateStatusString()
                log("Gave up sending request %d", id)
                return
            end
            timeouts = 0
            log("Resending request %d", id)
            rednet.send(hid, msg, clientlib.protocol)
        elseif timeouts > maxAckTimeouts and gotAck then
            gotAck = false
            -- TODO recognize server crashes?
            if serverState == serverStates.MISSING then
                updateStatusString()
                return
            end
            serverState = serverStates.MISSING
            log("ACK expired for %d", id)
        end
        updateStatusString()
    end
end

---List out items in this storage
---@return CCItemInfo[]
function clientlib.list()
    return (sendAndRecieve({ type = "list", side = "client" }) or { {} })[1]
end

---List out the Recipes this storage has
---@return RecipeInfo[]
function clientlib.listRecipes()
    return (sendAndRecieve({ type = "listRecipes", side = "client" }) or { {} })[1]
end

---Get the usage of each real slot in the inventory as a percentage [0,1]. Non-stackable items have a value of 2.
---@return FragMap
function clientlib.getFragMap()
    return (sendAndRecieve({ type = "getFragMap", side = "client" }) or { {} })[1]
end

---Remove an inventory from the system's cache
---@param inv string
function clientlib.removeInventory(inv)
    return sendAndRecieve({ type = "removeInventory", side = "client", inv = inv })
end

---Push items into some inventory
---@param to string
---@param item ItemDescriptor
---@param limit integer?
---@param toSlot integer?
---@return integer
function clientlib.pushItems(to, item, limit, toSlot)
    return sendAndRecieve({
        type = "pushItems",
        side = "client",
        to = to,
        item = item:serialize(),
        limit = limit,
        toSlot = toSlot
    }) or 0
end

---@param from string
---@param slot integer
---@param limit integer?
---@return integer
---@return ItemCoordinate
function clientlib.pullItems(from, slot, limit)
    local res = sendAndRecieve({
        type = "pullItems",
        side = "client",
        from = from,
        slot = slot,
        limit = limit
    }) or { 0, "" }
    return res[1], res[2]
end

---@return TaskListInfo[]
function clientlib.listTasks()
    local res = sendAndRecieve({ type = "listThreads" }) or { {} }
    return res[1]
end

function clientlib.rebootAll()
    rednet.broadcast({ type = "rebootAll" }, clientlib.protocol)
    os.reboot()
end

function clientlib.forceRebootServer()
    if hmn then
        local c = peripheral.wrap(hmn)
        if not c then
            error(("Could not force reboot the server, peripheral %s does not exist."):format(hmn))
        end
        c.reboot()
        serverState = serverStates.UNKNOWN
    else
        error("Cannot call forceRebootServer without knowing the server's attachment name.")
    end
end

---Import a JSON recipe into this storage
function clientlib.importJSON(json)
    return sendAndRecieve({ type = "importJSON", json = json })
end

function clientlib.saveRecipes()
    return sendAndRecieve({ type = "saveRecipes" })
end

function clientlib.ping()
    return sendAndRecieve({ type = "ping" })
end

function clientlib.open()
    modem = peripheral.find("modem", function(name, wrapped)
        return not wrapped.isWireless()
    end) --[[@as WiredModem]]
    clientlib.modem = modem
    rednet.open(peripheral.getName(modem))
    clientlib.statusString = "Searching..."
    local serverAlive = false
    parallel.waitForAny(function()
        while not hid do
            hid = rednet.lookup(clientlib.protocol)
            serverAlive = hid ~= nil
        end
    end, function()
        while true do
            throbberTick = throbberTick + 1
            updateThrobberStatus(throbberTick)
            sleep(throbberInterval)
        end
    end)
    clientlib.statusString = "Found!"
    serverState = serverAlive and serverStates.CONNECTED or serverStates.UNKNOWN
end

---@class ClientSubscriptions
---@field changes fun(l:CCItemInfo[],fragMap:FragMap)? Called when the inventory contents change
---@field start fun(l:CCItemInfo[],fragMap:FragMap)? Called when the server finishes starting
---@field tasks fun(l:TaskListInfo[])? Called when the s erver publishes a list of running tasks
---@field progress fun(stage:string,total:integer,scanned:integer,eta:number,etaStr:string)? Called while the server is starting with progress information

local subscriptions = {
    changes = {},
    start = {},
    tasks = {},
    progress = {}
}

---Register a subscriber to various messages published by the server
---@param subs ClientSubscriptions
function clientlib.subscribeTo(subs)
    if subs.changes then
        subscriptions.changes[#subscriptions.changes + 1] = subs.changes
    end
    if subs.start then
        subscriptions.start[#subscriptions.start + 1] = subs.start
    end
    if subs.progress then
        subscriptions.progress[#subscriptions.progress + 1] = subs.progress
    end
    if subs.tasks then
        subscriptions.tasks[#subscriptions.tasks + 1] = subs.tasks
    end
end

function clientlib.close()
    modem.closeAll()
end

---@param t function[]
---@param ... any
local function callAll(t, ...)
    for i, v in ipairs(t) do
        v(...)
    end
end
local function processSubscriptions(msg)
    if msg.type == "inventoryChange" then
        callAll(subscriptions.changes, msg.list, msg.fragMap)
    elseif msg.type == "serverStart" then
        callAll(subscriptions.start, msg.list, msg.fragMap)
    elseif msg.type == "taskUpdate" then
        callAll(subscriptions.tasks, msg.list)
    elseif msg.type == "scanProgress" then
        callAll(subscriptions.progress, msg.stage, msg.total, msg.scanned, msg.eta, msg.etaStr)
    end
end

---Update the throbber animation state
clientlib.run = function()
    parallel.waitForAny(tickThrobber, function()
        while true do
            local sender, message = rednet.receive(clientlib.protocol)
            if type(message) == "table" then
                if message.type == "rebootAll" then
                    os.reboot()
                elseif message.type == "scanProgress" then
                    serverState = serverStates.STARTING
                    scanStatus.stage = message.stage --[[@as string]]
                    scanStatus.total = message.total --[[@as integer]]
                    scanStatus.scanned = message.scanned --[[@as integer]]
                    scanStatus.eta = message.eta --[[@as number]]
                    scanStatus.etaStr = message.etaStr --[[@as number]]
                elseif message.type == "serverStart" then
                    serverState = serverStates.CONNECTED
                elseif message.type == "inventoryChange" or message.type == "taskUpdate" then
                    -- heartbeat of the server
                    serverState = serverStates.CONNECTED
                end
                processSubscriptions(message)
            end
        end
    end)
end

return clientlib
