local chestn = "minecraft:chest_0"
local chestn2 = "minecraft:chest_1"

local function run(threads, iterations)
    print(("Running %d threads for %d iterations"):format(threads, iterations))
    local listCalls = 0
    local listCalls2 = 0
    local f = {}
    for i = 1, threads do
        f[i] = function()
            for iter = 1, iterations do
                peripheral.call(chestn, "pushItems", chestn2, i, nil, i)
                local listing = peripheral.call(chestn, "list")
                listCalls = listCalls + 1
                assert(listing, ("%s.list() call returned nil!"):format(chestn))

                peripheral.call(chestn2, "pushItems", chestn, i, nil, i)
                listing = peripheral.call(chestn2, "list")
                listCalls2 = listCalls2 + 1
                assert(listing, ("%s.list() call returned nil!"):format(chestn2))
            end
        end
    end

    local ok, err = pcall(parallel.waitForAll, table.unpack(f))
    if not ok then
        print(("There were %d/%d list calls before .list() returned nil!"):format(listCalls, listCalls2))
        return false, (listCalls + listCalls2) / 2 / threads
    end
    print(("Ran %d iterations on %d threads okay! There were %d/%d list calls."):format(threads, iterations,
        listCalls, listCalls2))
    return true, (listCalls + listCalls2) / 2 / threads
end

local function writeCsv(datapoints)
    local f = assert(fs.open("run.csv", "w"))
    for i, v in ipairs(datapoints) do
        f.writeLine(v)
    end
    f.close()
end

run(27, 1000)

-- local datapoints = {}
-- local runs = 30
-- local failures = 0
-- local failureRateTotal = 0
-- local total = 0
-- for i = 1, runs do
--     local ok, rate = run(100, 1000)
--     if not ok then
--         failures = failures + 1
--         failureRateTotal = failureRateTotal + rate
--         datapoints[#datapoints + 1] = rate
--     end
--     total = total + 1
-- end
-- print(("Ran %d tests, %d%% failed after %.2f iterations on average"):format(total, failures / total * 100,
--     failureRateTotal / failures))
-- writeCsv(datapoints)
