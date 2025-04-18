local ui             = {}

local sset           = require("libs.sset")
local scrollDelay    = sset.get(sset.scrollDelay)
local shrexpect      = require("libs.shrexpect")

local defaultPalette = {}
for k, v in pairs(colors) do
    if type(v) == "number" then
        defaultPalette[k] = colors.packRGB(term.nativePaletteColor(v))
    end
end
local themePalette  = defaultPalette
local defaultColmap = {
    headerBg = colors.blue,
    headerFg = colors.white,
    listBg = colors.black,
    listFg = colors.white,
    selectedBg = colors.orange,
    selectedFg = colors.black,
    inputBg = colors.lightGray,
    inputFg = colors.black,
    footerBg = colors.gray,
    footerFg = colors.white,
    errorFg = colors.red,
    fullColor = colors.blue,
    partColor = colors.lightBlue,
    emptyColor = colors.white,
    nonStackColor = colors.red
}
local colmap        = defaultColmap
ui.colmap           = colmap

local defaultIcons  = {
    up = "\30",
    down = "\31",
    back = "\27"
}
ui.icons            = defaultIcons

local function applyTheme(theme)
    theme.palette = theme.palette or {}
    themePalette = {}
    for k, v in pairs(defaultPalette) do
        themePalette[k] = theme.palette[k] or v
    end
    theme.colmap = theme.colmap or {}
    colmap = {}
    for k, v in pairs(defaultColmap) do
        colmap[k] = theme.colmap[k] or v
    end
    ui.colmap = colmap
    theme.icons = theme.icons or {}
    ui.icons = {}
    for k, v in pairs(defaultIcons) do
        ui.icons[k] = theme.icons[k] or v
    end
end

function ui.loadTheme(fn)
    local f = fs.open(fn, "r")
    if not f then return false end
    local s = f.readAll()
    f.close()
    local func = load(s, nil, nil, { colors = colors })
    if not func then return false end
    local theme = func()
    if not theme then return false end
    applyTheme(theme)
    return true
end

function ui.applyPallete(dev)
    for color, code in pairs(themePalette) do
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

---Draw a header at the top of the window
---@param win Window
---@param s string
function ui.header(win, s)
    ui.preset(win, ui.presets.header)
    ui.clearLine(win, 1)
    win.write(s)
end

---Draw a footer at the bottom of the window
---@param win Window
---@param s string
function ui.footer(win, s)
    local _, h = win.getSize()
    ui.preset(win, ui.presets.footer)
    ui.clearLine(win, h)
    win.write(s)
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

function ui.clearLine(dev, y)
    dev.setCursorPos(1, y)
    dev.clearLine()
end

local function newPreset(name)
    return { name .. "Fg", name .. "Bg" }
end
ui.presets = {
    header = newPreset("header"),
    list = newPreset("list"),
    selected = newPreset("selected"),
    input = newPreset("input"),
    footer = newPreset("footer")
}

function ui.preset(win, preset)
    ui.color(win, colmap[preset[1]], colmap[preset[2]])
end

---@param s string
---@param w integer
---@param tick integer
local function scrollingText(s, w, tick)
    if #s > w then
        local first = tick % (#s + 2) + 1
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
---@param lockWidth table<integer,boolean>?
---@param align table<integer,"r">
---@return integer start
local function drawTable(win, t, selected, start, getStr, columns, tick, lockWidth, align)
    shrexpect(
        { "table", "table", "number?", "number?", "function", "string[]", "number", "table?", "table" },
        { win, t, selected, start, getStr, columns, tick, lockWidth, align }
    )
    lockWidth = lockWidth or {}
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
        colWidths[j] = math.min(math.floor(w * maxima[j] / totalStringWidth) + 1, maxColumnWidth)
        if lockWidth[j] then
            colWidths[j] = maxima[j] + 1
        end
        totalAllocatedWidth = totalAllocatedWidth + colWidths[j]
    end
    local remaining = w - totalAllocatedWidth
    local iter = 1
    while remaining > 0 do
        local split = math.ceil(remaining / columnCount)
        for j = 1, columnCount do
            colWidths[j] = colWidths[j] + split
            local splitted = split
            if lockWidth[j] then
                colWidths[j] = maxima[j] + 1
                splitted = 0
            end
            remaining = remaining - splitted
            totalAllocatedWidth = totalAllocatedWidth + splitted
            split = math.min(remaining, split)
            if split == 0 then break end
        end
        iter = iter + 1
        if iter == 5 then break end
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
            local colStr = scrollingText(s[i][j], colWidths[j], 0)
            if i == selected then
                colStr = scrollingText(s[i][j], colWidths[j], tick)
            end
            local tx = x
            if align[j] == "r" then
                tx = tx + colWidths[j] - #colStr - 1
            end
            win.setCursorPos(tx, i - start + 2)
            win.write(colStr)
            x = x + colWidths[j]
        end
        win.setBackgroundColor(colmap.listBg)
        win.setTextColor(colmap.listFg)
    end
    if start > 1 then
        win.setCursorPos(w + 1, 2)
        win.write(ui.icons.up)
    end
    if stop < #t then
        win.setCursorPos(w + 1, h + 1)
        win.write(ui.icons.down)
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
---@param lockWidth table<integer,boolean>?
---@param unlockMouse boolean?
---@param align table<integer,"r">?
---@return TableGUIWrapper
local function tableGuiWrapper(win, t, getStr, columns, onSelect, lockWidth, unlockMouse, align)
    shrexpect({ "table", "table", "function", "string[]", "function", "boolean[]?", "boolean?", "string[]?" },
        { win, t, getStr, columns, onSelect, lockWidth, unlockMouse, align })
    local selected = 1
    local start = 1
    local tick = 0
    align = align or {}
    ---@type "key"|"scroll"
    local lastInteract = "key"
    local function wrapBounds()
        selected = math.max(1, math.min(selected, #t))
        start = math.max(1, math.min(start, #t))
    end
    ---@class TableGUIWrapper
    local wrapper = {}
    function wrapper.setTable(nt)
        shrexpect({ "table" }, { nt })
        t = nt
        wrapBounds()
    end

    local tid = os.startTimer(scrollDelay)
    function wrapper.restartTicker()
        tick = 0
        os.cancelTimer(tid)
        tid = os.startTimer(scrollDelay)
    end

    function wrapper.getTable()
        return t
    end

    function wrapper.onEvent(e)
        if e[1] == "key" then
            local key = e[2]
            if key == keys.down then
                selected = selected + 1
                lastInteract = "key"
                wrapBounds()
                wrapper.restartTicker()
                return true
            elseif key == keys.up then
                selected = selected - 1
                lastInteract = "key"
                wrapBounds()
                wrapper.restartTicker()
                return true
            elseif key == keys.enter then
                wrapBounds()
                if t[selected] then
                    onSelect(selected, t[selected])
                end
                return true
            end
        elseif e[1] == "mouse_click" then
            local wx, wy = win.getPosition()
            local x, y = e[3] - wx, e[4] - wy
            local idx = start + y - 1
            local ww, wh = win.getSize()
            if y >= wh or y < 1 then
                return
            end
            if selected == idx then
                if t[idx] then
                    onSelect(idx, t[idx])
                end
            end
            selected = idx
            wrapBounds()
            wrapper.restartTicker()
            lastInteract = "scroll"
            return true
        elseif e[1] == "mouse_scroll" then
            if unlockMouse then
                start = start + e[2]
            else
                selected = selected + e[2]
            end
            lastInteract = "scroll"
            wrapBounds()
            wrapper.restartTicker()
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
        start = drawTable(win, t, selected, b, getStr, columns, tick, lockWidth, align)
        win.setVisible(true)
    end

    return wrapper
end
ui.tableGuiWrapper = tableGuiWrapper

---@param win Window
---@param title string
---@param options string[]
---@param cancelable boolean?
---@return string?
---@return integer
function ui.chooser(win, title, options, cancelable)
    local running = true
    local selected, idx
    local wrap = tableGuiWrapper(win, options, function(v)
        return { v }
    end, { title }, function(i, v)
        idx, selected = i, v
        running = false
    end)
    ui.preset(win, ui.presets.list)
    while running do
        wrap.draw()
        local e = { os.pullEvent() }
        if not wrap.onEvent(e) then
            if e[1] == "key" and e[2] == keys.tab and cancelable then
                running = false
            end
        end
    end
    return selected, idx
end

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
---@param mult integer
---@param selected string?
local function renderGetItemCountButtons(win, mult, selected)
    local x = 2
    local w, h = win.getSize()
    for i, v in ipairs(order) do
        win.setCursorPos(x, h)
        ui.preset(win, ui.presets.footer)
        if order[i] == selected then
            ui.preset(win, ui.presets.selected)
        end
        win.write(("[%s %3d]"):format(v:upper(), mult * keyMultipliers[v]))
        x = x + 7
    end

    ui.preset(win, ui.presets.footer)
    if "enter" == selected then
        ui.preset(win, ui.presets.selected)
    end
    win.setCursorPos(x, h)
    win.write("[Enter]")
end

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
    ui.preset(win, ui.presets.footer)
    win.setCursorPos(1, h)
    win.clearLine()
    win.write(ui.icons.back)
    renderGetItemCountButtons(win, mult)
    ui.preset(win, ui.presets.list)
    win.setVisible(true)
end

local function clenseEvents()
    -- make sure user inputs aren't carried to a different screen
    os.queueEvent("event_clense")
    os.pullEvent("event_clense")
end

---@param win Window
---@param item CCItemInfo
---@return integer?
local function getItemCount(win, item)
    local heldKeys = {}
    local mult = 8
    local tick = 0
    local tid = os.startTimer(scrollDelay)
    local w, h = win.getSize()
    while true do
        renderGetItemCount(win, item, mult, tick)
        local e = { os.pullEvent() }
        if e[1] == "key" then
            heldKeys[e[2]] = true
            if e[2] == keys.enter then
                clenseEvents()
                renderGetItemCountButtons(win, mult, "enter")
                return item.maxCount
            elseif keyMultipliers[keys.getName(e[2])] then
                clenseEvents()
                renderGetItemCountButtons(win, mult, keys.getName(e[2]))
                return keyMultipliers[keys.getName(e[2])] * mult
            elseif e[2] == keys.tab then
                clenseEvents()
                return
            end
        elseif e[1] == "key_up" then
            heldKeys[e[2]] = nil
        elseif e[1] == "timer" and e[2] == tid then
            tid = os.startTimer(scrollDelay)
            tick = tick + 1
        elseif e[1] == "mouse_click" then
            if e[3] == 1 and e[4] == h then
                return
            end
        end
        mult = heldKeys[keys.leftShift] and 64
            or heldKeys[keys.leftCtrl] and 1
            or 8
    end
end
ui.getItemCount = getItemCount

---@class ResumableRead
---@field win Window|Redirect|term
---@field buffer string
---@field cursor integer
---@field x integer
---@field x_end integer
---@field w integer
---@field y integer
---@field offset integer
local reread__index = {}
local reread_meta = { __index = reread__index }

function reread__index:_updateOffset()
    local offset = 1
    local hw = math.floor(self.w / 2)
    if #self.buffer > self.w - 1 then
        offset = math.max(math.min(self.cursor - hw + 1, #self.buffer - self.w + 2), 1)
    end
    self.offset = offset
    return offset
end

function reread__index:setCursor(i)
    self.cursor = math.max(math.min(i, #self.buffer + 1), 1)
    self:_updateOffset()
    return self
end

function reread__index:offsetCursor(i)
    self:setCursor(self.cursor + i)
    return self
end

function reread__index:onEvent(e)
    if e[1] == "char" then
        self.buffer = self.buffer:sub(1, self.cursor - 1) .. e[2]
            .. self.buffer:sub(self.cursor)
        self:offsetCursor(1)
        return true
    elseif e[1] == "key" then
        if e[2] == keys.backspace and self.cursor > 1 then
            self.buffer = self.buffer:sub(1, self.cursor - 2) .. self.buffer:sub(self.cursor)
            self:offsetCursor(-1)
            return true
        elseif e[2] == keys.delete then
            self.buffer = self.buffer:sub(1, self.cursor - 1) .. self.buffer:sub(self.cursor + 1)
            self:offsetCursor(0)
            return true
        elseif e[2] == keys.left then
            self:offsetCursor(-1)
            return true
        elseif e[2] == keys.right then
            self:offsetCursor(1)
            return true
        elseif e[2] == keys.leftCtrl then
            self.controlHeld = true
        elseif e[2] == keys.u and self.controlHeld then
            self:setValue("")
        end
    elseif e[1] == "key_up" and e[2] == keys.leftCtrl then
        self.controlHeld = false
        return true
    elseif e[1] == "mouse_click" then
        local wx, wy = self.win.getPosition()
        local cx, cy = e[3] - wx + 1, e[4] - wy + 1
        if cx > 1 and cx <= self.w and cy == 1 and e[2] == 2 then
            self:setValue("")
            return true
        end
    elseif e[1] == "paste" then
        self.buffer = self.buffer:sub(1, self.cursor - 1) .. e[2]
            .. self.buffer:sub(self.cursor)
        self:offsetCursor(#e[2])
        return true
    end
end

function reread__index:render()
    self.win.setCursorPos(self.x, self.y)
    local blank = (" "):rep(self.w)
    self.win.write(blank)
    self.win.setCursorPos(self.x, self.y)
    self.win.write(self.buffer:sub(self.offset))
    self.win.setCursorPos(self.x + self.cursor - self.offset, self.y)
    self.win.setCursorBlink(true)
end

function reread__index:setValue(s)
    self.buffer = s
    self:setCursor(#s + 1)
    return self
end

function reread__index:run(allowCancel)
    while true do
        self:render()
        local e = { os.pullEvent() }
        if not self:onEvent(e) then
            if e[1] == "key" and e[2] == keys.enter then
                return self.buffer
            elseif e[1] == "key" and self.controlHeld and e[2] == keys.c and allowCancel then
                return
            elseif e[1] == "key" and e[2] == keys.tab and allowCancel then
                return
            end
        end
    end
end

---@param win Window|term
---@param x integer
---@param y integer
---@param w integer?
---@return ResumableRead
local function reread(win, x, y, w)
    ---@class ResumableRead
    local r = setmetatable({}, reread_meta)
    r.win = win
    r.buffer = ""
    r.cursor = 1
    r.x, r.y = x, y
    r.x_end = w and x + w or win.getSize() - x
    r.w = r.x_end - r.x + 1
    r.offset = 1

    return r
end
ui.reread = reread

---@param usage FragMap
---@param idxLut number[]?
---@param sy integer
---@param w integer
---@param scroll integer
---@return integer height
local function drawFragMapList(box, usage, idxLut, sy, w, scroll)
    local lasty = 0
    for i, v in ipairs(idxLut or usage) do
        local percent = v
        local idx = i
        if idxLut then
            percent = usage[v]
            idx = v
        end
        local x = (i - 1) % w + 1
        local y = math.floor((i - 1) / w) + math.floor(sy * 1.5) - scroll
        local color = colmap.partColor
        if percent == 1 then
            color = colmap.fullColor
        elseif percent == 0 then
            color = colmap.emptyColor
        end
        if usage.nostack[idx] then
            color = colmap.nonStackColor
        end
        lasty = math.ceil(y / 1.5)
        -- lasty = y
        if y >= sy then
            box:set_pixel(x, y, color)
        end
    end
    return lasty - sy + scroll + 1
end
---Draw a FragMap
---@param pwin Window
---@param usage FragMap
---@param sx integer
---@param sy integer
---@param w integer
---@param h integer
---@param labels boolean Show slot usage by inventory
---@param scroll integer? 0 indexed scroll start
function ui.drawFragMap(pwin, usage, sx, sy, w, h, labels, scroll)
    local bixelbox = require("libs.bixelbox")
    local win = window.create(pwin, sx, sy, w, h, true)
    local box = bixelbox.new(win, colors.black)
    scroll = scroll or 0
    win.setBackgroundColor(colors.black)
    box:clear(colors.black)
    local fh = 0
    if labels then
        local y = 1 - scroll
        local invStart = {}
        local invList = {}
        for inv, idxLut in pairs(usage.invs) do
            invList[#invList + 1] = inv
            invStart[inv] = y
            local lh = drawFragMapList(box, usage, idxLut, y + 1, w, 0) + 1
            y = y + lh
            fh = fh + lh
        end
        box:render()
        ui.color(win, ui.colmap.listFg, ui.colmap.listBg)
        for i, inv in ipairs(invList) do
            local y = invStart[inv]
            win.setCursorPos(1, y)
            win.write(inv)
        end
    else
        fh = drawFragMapList(box, usage, nil, 1, w, scroll)
        box:render()
    end
    return fh
end

---Show a screen to modify a setting
---@param win Window
---@param s RegisteredSetting
function ui.changeSetting(win, s)
    local w, h = win.getSize()
    local tick = 0
    local scroll = 0
    local maxScroll
    local function render()
        win.setVisible(false)
        ui.color(win, ui.colmap.listFg, ui.colmap.listBg)
        win.clear()
        ui.cursor(win, 2, 3 - scroll)
        win.write(s.name)
        local y = 4
        maxScroll = 5 - h
        local function writeField(s, d)
            ui.cursor(win, 3, y - scroll)
            y = y + 1
            maxScroll = maxScroll + 1
            win.write(s)
            win.write(scrollingText(tostring(d), w - 3 - #s, tick))
        end
        writeField("Side: ", s.side)
        writeField("Type: ", s.type)
        if s.lvalue ~= nil then
            writeField("Local: ", s.lvalue)
        end
        if s.gvalue ~= nil then
            writeField("Global: ", s.gvalue)
        end

        if s.default ~= nil then
            writeField("Default: ", s.default)
        end
        if s.requiresReboot then
            writeField("Reboot Required", "")
        end
        local split = require("cc.strings").wrap(s.desc, w - 3)
        for i, v in ipairs(split) do
            ui.cursor(win, 2, y - scroll)
            y = y + 1
            maxScroll = maxScroll + 1
            win.write(v)
        end
        if scroll > 0 then
            win.setCursorPos(w, 2)
            win.write(ui.icons.up)
        end
        if scroll < maxScroll then
            win.setCursorPos(w, h - 1)
            win.write(ui.icons.down)
        end
        ui.color(win, ui.colmap.headerFg, ui.colmap.headerBg)
        ui.cursor(win, 1, 1)
        win.clearLine()
        win.write("Modifying Setting")
        ui.cursor(win, 1, h)
        ui.preset(win, ui.presets.footer)
        if not s.options then
            ui.color(win, ui.colmap.inputFg, ui.colmap.inputBg)
        end
        win.clearLine()
        ui.preset(win, ui.presets.footer)
        win.write(ui.icons.back)
        if s.options then
            win.write(" [Enter] to change value")
        else
            ui.color(win, ui.colmap.inputFg, ui.colmap.inputBg)
            win.write(">")
        end
        win.setVisible(true)
    end
    render()
    local cvalue = sset.get(s, true)
    if cvalue == nil then cvalue = "" else cvalue = tostring(cvalue) end
    local value
    local function adjustScroll(i)
        scroll = math.max(0, math.min(scroll + i, maxScroll))
    end
    local r = reread(win, 3, h, w - 3)
    parallel.waitForAny(function()
        if s.options then
            while true do
                local e = { os.pullEvent("key") }
                if e[2] == keys.enter then
                    value = true
                    return
                elseif e[2] == keys.tab then
                    return
                end
            end
        else
            value = r:setValue(cvalue):run(true)
        end
    end, function()
        while true do
            render()
            if not s.options then
                r:render()
            end
            local e = { os.pullEvent() }
            if e[1] == "key" then
                if e[2] == keys.up then
                    adjustScroll(-1)
                elseif e[2] == keys.down then
                    adjustScroll(1)
                end
            elseif e[1] == "mouse_scroll" then
                adjustScroll(e[2])
            end
        end
    end, function()
        while true do
            sleep(scrollDelay)
            tick = tick + 1
        end
    end)
    win.setCursorBlink(false)
    if s.options and value then
        value = ui.chooser(win, "Setting", s.options)
    end
    if value ~= nil then
        if value == "" then
            value = nil
        end
        local loc = s.side == "local"
        if s.side == "both" then
            local side = ui.chooser(win, "Change which side?", { "local", "global" })
            loc = side == "local"
        end
        sset.set(s, value, loc)
        if s.requiresReboot then
            local choices = { "Yes - All", "Yes", "No" }
            if loc then
                choices = { "Yes", "No" }
            end
            local reboot = ui.chooser(win, "Reboot to apply?", choices)
            if reboot == "Yes" then
                os.reboot()
            elseif reboot == "Yes - All" then
                require("libs.clientlib").rebootAll()
            end
        end
    end
    ui.color(win, ui.colmap.listFg, ui.colmap.listBg)
end

---Create a searchable tableGUIWrapper
---@param win Window
---@param lwin Window
---@param iwin Window
---@generic T
---@param filter fun(t:T[],s:string):T[]
---@param wrap TableGUIWrapper
function ui.searchableTableGUIWrapper(win, lwin, iwin, filter, wrap)
    local w, h        = win.getSize()
    local rer         = ui.reread(iwin, 3, 1, w - 2)
    local oldSetTable = wrap.setTable
    local oldDraw     = wrap.draw
    local oldOnEvent  = wrap.onEvent
    function wrap.draw()
        oldDraw()
        ui.preset(iwin, ui.presets.input)
        iwin.clear()
        ui.preset(iwin, ui.presets.footer)
        ui.cursor(iwin, 1, 1)
        iwin.write(ui.icons.back)
        ui.preset(iwin, ui.presets.input)
        iwin.write(">")
        rer:render()
        lwin.setVisible(true)
        iwin.setVisible(true)
    end

    local t = wrap.getTable()

    function wrap.setTable(nt)
        t = nt
        oldSetTable(filter(t, rer.buffer))
    end

    function wrap.onEvent(e)
        if oldOnEvent(e) then
            return true
        end
        if rer:onEvent(e) then
            oldSetTable(filter(t, rer.buffer))
            return true
        end
    end

    return wrap
end

local function getTenths(n)
    local ten = n * 10
    return ten - math.floor(ten)
end

---Draw a progress bar
---@param dev term|Window
---@param x integer
---@param y integer
---@param w integer
---@param p number [0,1] percentage
function ui.progressBar(dev, x, y, w, p)
    if p ~= p then p = 0 end
    w = w - 2
    local s = ("\127"):rep(math.floor(w * p))
    if p < 1 and getTenths(p) > 0.5 then
        s = s .. "\149"
    end
    s = s .. (" "):rep(w - #s)
    local ox, oy = ui.cursor(dev, x, y)
    dev.write(s)
    ui.cursor(dev, ox, oy)
end

return ui
