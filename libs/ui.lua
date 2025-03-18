local ui = {}

local scrollDelay = 0.15

-- Credit to Sammy for this palette
local GNOME = {
    ["black"]     = 0x171421,
    ["blue"]      = 0x2A7BDE,
    ["brown"]     = 0xA2734C,
    ["cyan"]      = 0x2AA1B3,
    ["gray"]      = 0x5E5C64,
    ["green"]     = 0x26A269,
    ["lightBlue"] = 0x33C7DE,
    ["lightGray"] = 0xD0CFCC,
    ["lime"]      = 0x33D17A,
    ["magenta"]   = 0xC061CB,
    ["orange"]    = 0xE9AD0C,
    ["pink"]      = 0xF66151,
    ["purple"]    = 0xA347BA,
    ["red"]       = 0xC01C28,
    ["white"]     = 0xFFFFFF,
    ["yellow"]    = 0xF3F03E
}

function ui.applyPallete(dev)
    for color, code in pairs(GNOME) do
        dev.setPaletteColor(colors[color], code)
    end
end

---Set the colors of a device
---@param dev Window|term
---@param fg color?
---@param bg color?
---@return color ofg
---@return color obg
function ui.color(dev, fg, bg)
    local ofg, obg = dev.getTextColor(), dev.getBackgroundColor()
    if fg then
        dev.setTextColor(fg)
    end
    if bg then
        dev.setBackgroundColor(bg)
    end
    return ofg, obg
end

---Set the cursor position on a device
---@param dev Window|term
---@param x integer?
---@param y integer?
---@return integer ox
---@return integer oy
function ui.cursor(dev, x, y)
    local ox, oy = dev.getCursorPos()
    dev.setCursorPos(x or ox, y or oy)
    return ox, oy
end

local colmap = {
    headerBg = colors.blue,
    headerFg = colors.white,
    listBg = colors.black,
    listFg = colors.white,
    selectedBg = colors.orange,
    selectedFg = colors.black
}

ui.colmap = colmap


---@param s string
---@param w integer
---@param tick integer
local function scrollingText(s, w, tick)
    if #s > w then
        local first = (tick - 1) % (#s + 2) + 1
        local last = first + w
        if last > #s then
            s = s .. " - " .. s
        end
        s = s:sub(first, last - 3) .. ".."
    end
    return s
end

---@generic T
---@param win Window
---@param t T[]
---@param selected integer?
---@param start integer?
---@param getStr fun(v:T):string[]
---@param columns string[]
---@param tick integer
---@param minWidth table<integer,number>?
---@return integer start
local function drawTable(win, t, selected, start, getStr, columns, tick, minWidth)
    minWidth = minWidth or {}
    local w, h = win.getSize()
    w = w - 1
    h = h - 1
    if selected and not start then
        start = selected - math.floor(h / 2)
        start = math.max(1, math.min(#t - h + 1, start))
    end
    assert(start, "Expecting either start or selected!")
    local stop = math.min(#t, start + h - 1)
    local s = {}
    local maxima = {}
    local columnCount = #columns
    for i = 1, #t do
        local v = t[i]
        s[i] = getStr(v)
        for j = 1, columnCount do
            maxima[j] = math.max(maxima[j] or #columns[j], #s[i][j])
        end
    end
    local maxColumnWidth = math.floor(w / columnCount)
    local totalStringWidth = 0
    for j = 1, columnCount do
        maxima[j] = maxima[j] or #columns[j]
        totalStringWidth = totalStringWidth + maxima[j]
    end
    local colWidths = {}
    local totalAllocatedWidth = 0
    for j = 1, columnCount do
        -- Allow a configurable minimum width for each column
        colWidths[j] = math.min(
            math.max(math.floor(w * maxima[j] / totalStringWidth) + 1, minWidth[j] or 0),
            maxColumnWidth)
        totalAllocatedWidth = totalAllocatedWidth + colWidths[j]
    end
    local remaining = w - totalAllocatedWidth
    local split = math.floor(remaining / columnCount)
    for j = 1, columnCount do
        colWidths[j] = colWidths[j] + split
        remaining = remaining - split
        totalAllocatedWidth = totalAllocatedWidth + split
        split = math.min(remaining, split)
        if split == 0 then break end
    end
    -- Give left over space to last column
    colWidths[columnCount] = colWidths[columnCount] + w - totalAllocatedWidth
    local x = 1
    win.setBackgroundColor(colmap.headerBg)
    win.setTextColor(colmap.headerFg)
    win.setCursorPos(1, 1)
    win.clearLine()
    for j = 1, columnCount do
        win.setCursorPos(x, 1)
        win.write(columns[j])
        x = x + colWidths[j]
    end
    win.setBackgroundColor(colmap.listBg)
    win.setTextColor(colmap.listFg)
    for i = start, stop do
        local x = 1
        if i == selected then
            win.setBackgroundColor(colmap.selectedBg)
            win.setTextColor(colmap.selectedFg)
            win.setCursorPos(1, i - start + 2)
            win.clearLine()
        end
        for j = 1, columnCount do
            win.setCursorPos(x, i - start + 2)
            local colStr = scrollingText(s[i][j], colWidths[j], 1)
            if i == selected then
                colStr = scrollingText(s[i][j], colWidths[j], tick)
            end
            win.write(colStr)
            x = x + colWidths[j]
        end
        win.setBackgroundColor(colmap.listBg)
        win.setTextColor(colmap.listFg)
    end
    if start > 1 then
        win.setCursorPos(w + 1, 2)
        win.write("\30")
    end
    if stop < #t then
        win.setCursorPos(w + 1, h + 1)
        win.write("\31")
    end
    return start
end
ui.drawTable = drawTable

---@generic T
---@param win Window
---@param t T[]
---@param getStr fun(v:T):string[]
---@param columns string[]
---@param onSelect fun(i:integer,v:T)
---@param minWidth table<integer,number>?
---@param unlockMouse boolean?
local function tableGuiWrapper(win, t, getStr, columns, onSelect, minWidth, unlockMouse)
    local selected = 1
    local start = 1
    local tick = 0
    ---@type "key"|"scroll"
    local lastInteract = "key"
    local function wrapBounds()
        selected = math.max(1, math.min(selected, #t))
        start = math.max(1, math.min(start, #t))
    end
    local wrapper = {}
    function wrapper.setTable(nt)
        t = nt
        wrapBounds()
    end

    local tid = os.startTimer(scrollDelay)
    function wrapper.onEvent(e)
        if e[1] == "key" then
            local key = e[2]
            if key == keys.down then
                selected = selected + 1
                lastInteract = "key"
                wrapBounds()
                tick = 0
                os.cancelTimer(tid)
                tid = os.startTimer(scrollDelay)
                return true
            elseif key == keys.up then
                selected = selected - 1
                lastInteract = "key"
                wrapBounds()
                tick = 0
                os.cancelTimer(tid)
                tid = os.startTimer(scrollDelay)
                return true
            elseif key == keys.enter then
                wrapBounds()
                onSelect(selected, t[selected])
                return true
            end
        elseif e[1] == "mouse_scroll" then
            if unlockMouse then
                start = start + e[2]
            else
                selected = selected + e[2]
            end
            lastInteract = "scroll"
            os.cancelTimer(tid)
            tid = os.startTimer(scrollDelay)
            wrapBounds()
            tick = 0
            return true
        elseif e[1] == "timer" and e[2] == tid then
            tick = tick + 1
            tid = os.startTimer(scrollDelay)
            return true
        end
    end

    function wrapper.draw()
        win.setVisible(false)
        win.clear()
        local b
        if lastInteract == "scroll" and unlockMouse then
            b = start
        end
        start = drawTable(win, t, selected, b, getStr, columns, tick, minWidth)
        win.setVisible(true)
    end

    return wrapper
end
ui.tableGuiWrapper = tableGuiWrapper

local keyMultipliers = {
    a = 1,
    s = 2,
    d = 4,
    f = 8
}
local order = {
    "a", "s", "d", "f"
}

---@param win Window
---@param item CCItemInfo
---@param mult integer
---@param tick integer
local function renderGetItemCount(win, item, mult, tick)
    mult = mult or 1
    local w, h = win.getSize()
    win.setBackgroundColor(ui.colmap.listBg)
    win.setTextColor(ui.colmap.listFg)
    win.setVisible(false)
    win.clear()
    local c = "x" .. tostring(item.count)
    win.setCursorPos(w - #c, 3)
    win.write(c)
    local name = scrollingText(item.displayName, w - 4 - #c, tick)
    win.setCursorPos(2, 3)
    win.write(name)
    win.setCursorPos(3, 4)
    win.write(scrollingText(item.name, w - 8, tick))
    win.setCursorPos(w - 4, 4)
    win.write(string.sub(item.nbt or "", 1, 4))
    local y = 5
    if item.enchantments then
        win.setCursorPos(3, y)
        win.write("Enchantments")
        y = y + 1
        for i, v in ipairs(item.enchantments) do
            win.setCursorPos(4, y + i - 1)
            win.write(scrollingText(v.displayName, w - 5, tick))
        end
    end
    win.setCursorPos(1, 1)
    win.setBackgroundColor(ui.colmap.headerBg)
    win.setTextColor(ui.colmap.headerFg)
    win.clearLine()
    win.write("Item Request")
    win.setBackgroundColor(ui.colmap.selectedBg)
    win.setTextColor(ui.colmap.selectedFg)
    win.setCursorPos(1, h)
    win.clearLine()
    local x = 4
    win.write("\27Q")
    for i, v in ipairs(order) do
        win.setCursorPos(x, h)
        win.write(("[%s %3d]"):format(v:upper(), mult * keyMultipliers[v]))
        x = x + 8
    end
    win.setBackgroundColor(ui.colmap.listBg)
    win.setTextColor(ui.colmap.listFg)
    win.setVisible(true)
end

---@param win Window
---@param item CCItemInfo
---@return integer?
local function getItemCount(win, item)
    local heldKeys = {}
    local mult = 8
    local tick = 0
    local tid = os.startTimer(scrollDelay)
    while true do
        renderGetItemCount(win, item, mult, tick)
        local e = { os.pullEvent() }
        if e[1] == "key" then
            heldKeys[e[2]] = true
            if e[2] == keys.enter then
                return item.maxCount
            elseif keyMultipliers[keys.getName(e[2])] then
                return keyMultipliers[keys.getName(e[2])] * mult
            elseif e[2] == keys.q then
                return
            end
        elseif e[1] == "key_up" then
            heldKeys[e[2]] = nil
        elseif e[1] == "timer" and e[2] == tid then
            tid = os.startTimer(scrollDelay)
            tick = tick + 1
        end
        mult = heldKeys[keys.leftShift] and 64
            or heldKeys[keys.leftCtrl] and 1
            or 8
    end
end
ui.getItemCount = getItemCount

return ui
