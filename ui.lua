local ui = {}


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

for color, code in pairs(GNOME) do
    term.setPaletteColor(colors[color], code)
end
local colmap = {
    headerBg = colors.blue,
    headerFg = colors.white,
    listBg = colors.black,
    listFg = colors.white,
    selectedBg = colors.orange,
    selectedFg = colors.black
}

---@generic T
---@param win Window
---@param t T[]
---@param selected integer?
---@param start integer?
---@param getStr fun(v:T):string[]
---@param columns string[]
---@return integer start
local function drawTable(win, t, selected, start, getStr, columns)
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
    local totalStringWidth = 0
    for j = 1, columnCount do
        maxima[j] = maxima[j] or #columns[j]
        totalStringWidth = totalStringWidth + maxima[j]
    end
    local colWidths = {}
    local totalAllocatedWidth = 0
    for j = 1, columnCount do
        colWidths[j] = math.floor(w * maxima[j] / totalStringWidth) + 1
        totalAllocatedWidth = totalAllocatedWidth + colWidths[j]
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
            win.write(s[i][j])
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
local function tableGuiWrapper(win, t, getStr, columns)
    local selected = 1
    local start = 1
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

    function wrapper.onEvent(e)
        if e[1] == "key" then
            local key = e[2]
            if key == keys.down then
                selected = selected + 1
                lastInteract = "key"
                wrapBounds()
                return true
            elseif key == keys.up then
                selected = selected - 1
                lastInteract = "key"
                wrapBounds()
                return true
            end
        elseif e[1] == "mouse_scroll" then
            selected = selected + e[2]
            lastInteract = "scroll"
            wrapBounds()
            return true
        end
    end

    function wrapper.draw()
        win.setVisible(false)
        win.clear()
        local b
        -- if lastInteract == "scroll" then
        --     b = start
        -- end
        start = drawTable(win, t, selected, b, getStr, columns)
        win.setVisible(true)
    end

    return wrapper
end
ui.tableGuiWrapper = tableGuiWrapper

return ui
