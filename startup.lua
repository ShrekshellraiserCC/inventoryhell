local sset = require("libs.sset")

local prog = sset.get(sset.program)
print(prog)
if prog == "host" then
    shell.run(sset.getInstalledPath "host")
elseif prog == "crafter" then
    shell.run(sset.getInstalledPath "crafter")
elseif prog == "term" then
    shell.run(sset.getInstalledPath "term")
elseif prog == "host+term" then
    shell.run("bg", sset.getInstalledPath "host")
    shell.run(sset.getInstalledPath "term")
elseif prog == "nterm" then
    shell.run(sset.getInstalledPath "nterm")
else
    shell.run(sset.getInstalledPath "setup")
end
