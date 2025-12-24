local sset = require("libs.sset")

local prog = sset.get(sset.program)
---@param fg string
local function run(fg, ...)
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
    error("No longer supporting host+term mode!")
    run(sset.getInstalledPath "term", sset.getInstalledPath "host")
elseif prog == "nterm" then
    run(sset.getInstalledPath "nterm")
elseif prog == "host+nterm" then
    -- run(sset.getInstalledPath "nterm", sset.getInstalledPath "host")
    shell.run("bg", sset.getInstalledPath "host")
    shell.run(sset.getInstalledPath "nterm")
else
    run(sset.getInstalledPath "setup")
end
