assert(fs.open("log.txt", "w")).close()

local function log(...)
    local f = assert(fs.open("log.txt", "a"))
    f.write(...)
    f.write("\n")
    f.close()
end
while true do
    log(os.pullEvent())
end
