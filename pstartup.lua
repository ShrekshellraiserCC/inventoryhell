term.clear()
term.setCursorPos(1, 1)
print("This computer is part of an SSD system.")
print("However, it booted without an attached disk.")
print("Waiting for the disk...")

local reboot_events = {
    peripheral = true,
    disk = true
}

while true do
    local e = os.pullEvent()
    if reboot_events[e] then
        os.reboot()
    end
end
