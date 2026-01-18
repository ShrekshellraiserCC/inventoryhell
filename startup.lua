local sset = require("libs.sset")

local prog = sset.get(sset.program)
---@param fg string
local function run(fg, ...)
    print(fg)
    local f = assert(loadfile(shell.resolveProgram(fg), "t", _ENV))
    f(...)
end
if prog == "host" then
    run(sset.getInstalledPath "host")
elseif prog == "crafter" then
    run(sset.getInstalledPath "crafter")
elseif prog == "term" then
    run(sset.getInstalledPath "term")
elseif prog == "host+term" then
    run(sset.getInstalledPath "term", "+host")
else
    run(sset.getInstalledPath "setup")
end
