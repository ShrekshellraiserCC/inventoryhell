local sset = require("libs.sset")

local prog = sset.get(sset.program)
if prog == "host" then
    shell.run("disk/host")
elseif prog == "crafter" then
    shell.run("disk/crafter")
elseif prog == "term" then
    shell.run("disk/term")
end
