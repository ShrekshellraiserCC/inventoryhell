local invs = { peripheral.find("inventory") }

print(#invs)

---Execute a table of functions in batches
---@param func function[]
---@param skipPartial? boolean Only do complete batches and skip the remainder.
---@param limit integer
---@return function[] skipped Functions that were skipped as they didn't fit.
local function batchExecute(func, skipPartial, limit)
    local batches = #func / limit
    batches = skipPartial and math.floor(batches) or math.ceil(batches)
    for batch = 1, batches do
        local start = ((batch - 1) * limit) + 1
        local batch_end = math.min(start + limit - 1, #func)
        parallel.waitForAll(table.unpack(func, start, batch_end))
    end
    return table.pack(table.unpack(func, 1 + limit * batches))
end

local function getRandomDestination(depth)
    depth = depth or 0
    if depth == 5 then
        return
    end
    local tperiph = invs[math.random(#invs)]
    local size = tperiph.size()
    local tlist = tperiph.list()
    if #tlist == size then return getRandomDestination(depth + 1) end
    local tslot
    repeat
        tslot = math.random(size)
    until not tlist[tslot]
    local limit = math.random(1, 5)
    return peripheral.getName(tperiph), tslot, limit
end

local function scrambleInv(inv)
    local f = {}
    local fname = peripheral.getName(inv)
    for fslot in pairs(inv.list()) do
        for i = 1, math.random(1, 10) do
            f[#f + 1] = function()
                local tperiph, tslot, limit = getRandomDestination()
                if tperiph == nil then return end
                print(fname, tperiph, fslot, limit, tslot)
                inv.pushItems(tperiph, fslot, limit, tslot)
            end
        end
    end
    batchExecute(f, false, 128)
end

local function scrambleAll()
    for _, inv in ipairs(invs) do
        scrambleInv(inv)
    end
end

scrambleAll()
