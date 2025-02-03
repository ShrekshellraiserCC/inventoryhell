local blacklist = {
    char = true,
    mouse_click = true,
    mouse_scroll = true,
    mouse_drag = true,
    mouse_up = true,
    key = true,
    key_up = true,
    task_complete = true,
}

local i = 0
while true do
    local e = { os.pullEvent() }
    if not blacklist[e[1]] then
        print(i, table.unpack(e))
    end
    i = i + 1
end
