local sset = require("libs.sset")

if sset.get(sset.isCrafter) then
    print("Starting as crafter...")
    shell.run("disk/crafter")
elseif sset.get(sset.isTerm) then
    shell.run("disk/term")
end
