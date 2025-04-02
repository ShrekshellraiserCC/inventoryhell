local sset = require("libs.sset")

local prog = sset.get(sset.program)
print(prog)
if prog == "host" then
    shell.run("disk/host")
elseif prog == "crafter" then
    shell.run("disk/crafter")
elseif prog == "term" then
    shell.run("disk/term")
elseif prog == "host+term" then
    shell.run("bg", "disk/host")
    shell.run("disk/term")
else
    shell.run("disk/setup")
end
