-- Dumb program to run on turtles to act as simple crafters
---@alias WiredModem ccTweaked.peripherals.WiredModem
---@type WiredModem
local modem = peripheral.find("modem", function(name, wrapped)
    return not wrapped.isWireless()
end) --[[@as WiredModem]]
local sset = require "libs.sset"
local ui = require "libs.ui"
local clientlib = require "libs.clientlib"

modem.open(7777)
clientlib.open()
turtle.select(16)

local win = window.create(term.current(), 1, 1, term.getSize())
ui.loadTheme(sset.get(sset.theme))
ui.applyPallete(win)
local tw, th = term.getSize()
local twin = window.create(win, 1, 2, tw, th - 2)
term.redirect(twin)
term.clear()
local w, h = twin.getSize()
local t = "\2"
local tcolors = {}
for i = 0, 14 do
    tcolors[i] = 2 ^ i
end
local si = 1

local localName = modem.getNameLocal()

local counter = 0
if fs.exists(".crafted") and sset.get(sset.craftKeep) then
    local f = assert(fs.open(".crafted", "r"))
    counter = tonumber(f.readAll()) --[[@as integer]]
    f.close()
end

local things = {}

local function newThing()
    local tx = math.random(1, w - #t)
    local ty = math.random(1, h)
    local dx = math.random(-10, 10)
    local dy = math.random(-5, 5)
    if dx == 0 then dx = 1 end
    if dy == 0 then dy = 1 end
    local ci = si
    si = (si + 1) % (#tcolors + 1)
    return {
        tx = tx,
        ty = ty,
        dx = dx,
        dy = dy,
        ci = ci
    }
end

local function increment()
    counter = counter + 1
    if sset.get(sset.craftKeep) then
        local f = assert(fs.open(".crafted", "w"))
        f.write(("%d"):format(counter))
        f.close()
    end
    things[#things + 1] = newThing()
end

local function tickThingDVD(thing, delta)
    local tx, ty = thing.tx, thing.ty
    local dx, dy = thing.dx, thing.dy
    local ci = thing.ci
    tx, ty = tx + dx * delta, ty + dy * delta
    if tx < 1 or tx + #t - 1 > w then
        tx = math.max(math.min(tx, w - #t), 1)
        dx = -dx + (math.random() - 0.5) * 4
        ci = (ci + 1) % (#tcolors + 1)
    end
    if ty < 1 or ty > h then
        ty = math.max(math.min(ty, h), 1)
        dy = -dy + (math.random() - 0.5) * 4
        ci = (ci + 1) % (#tcolors + 1)
    end
    thing.tx, thing.ty = tx, ty
    thing.dx, thing.dy = dx, dy
    thing.ci = ci
end

local function tickThingBouncy(thing, delta)
    local tx, ty = thing.tx, thing.ty
    local dx, dy = thing.dx, thing.dy
    local ci = thing.ci
    tx, ty = tx + dx * delta, ty + dy * delta
    if tx < 1 or tx + #t - 1 > w then
        tx = math.max(math.min(tx, w - #t), 1)
        dx = -1 * dx
        ci = (ci + 1) % (#tcolors + 1)
    end
    if ty < 1 then
        ty = 1
        dy = -1 * dy
        ci = (ci + 1) % (#tcolors + 1)
    elseif ty > h then
        ty = h
        dy = -(0.8 * dy) - math.random(0, 5)
        dx = dx + math.random(-3, 3)
        ci = (ci + 1) % (#tcolors + 1)
    end
    dy = dy + 9 * delta
    thing.tx, thing.ty = tx, ty
    thing.dx, thing.dy = dx, dy
    thing.ci = ci
end

local function tickThingRandom(thing, delta)
    local dir = math.random(1, 4)
    if dir == 1 then
        thing.tx = math.min(thing.tx + 1, w)
    elseif dir == 2 then
        thing.tx = math.max(thing.tx - 1, 1)
    elseif dir == 3 then
        thing.ty = math.min(thing.ty + 1, h)
    else
        thing.ty = math.max(thing.ty - 1, 1)
    end
end

local tickThing = tickThingBouncy
local visualizer = sset.get(sset.craftVisualizer)
if visualizer == "DVD" then
    tickThing = tickThingDVD
elseif visualizer == "None" then
    tickThing = function() end
elseif visualizer == "Random" then
    tickThing = tickThingRandom
end

local function renderThing(thing)
    local tx, ty = thing.tx, thing.ty
    local ci = thing.ci
    term.setTextColor(tcolors[ci])
    term.setCursorPos(tx, ty)
    term.write(t)
end

local function render()
    for i = 1, math.min(counter, sset.get(sset.craftMax)) do
        things[i] = newThing()
    end
    while true do
        local delay = sset.get(sset.craftDelay)
        sleep(delay)
        win.setVisible(false)
        win.clear()
        ui.preset(twin, ui.presets.list)
        twin.clear()
        ui.header(win, "SSD Crafter")
        ui.footer(win, ("I have crafted %d things!"):format(counter))
        for i, v in ipairs(things) do
            tickThing(v, delay)
            renderThing(v)
        end
        win.setVisible(true)
    end
end

local function getUsedSlots()
    local c = 0
    for i = 1, 15 do
        if not turtle.getItemDetail(i) then
            break
        end
        c = i
    end
    return c
end

local function crafter()
    while true do
        local e, side, channel, replyChannel, message = os.pullEvent("modem_message")
        if type(message) == "table" then
            if message[1] == "CRAFT" and message[2] == localName then
                turtle.craft()
                if sset.get(sset.craftRotate) then
                    turtle.turnRight()
                    turtle.turnLeft()
                end
                increment()
                modem.transmit(replyChannel, channel, { "CRAFT_DONE", localName, getUsedSlots() })
            elseif message[1] == "GET_NAME" then
                modem.transmit(replyChannel, channel, { "NAME", localName })
            end
        end
    end
end

parallel.waitForAny(
    render, crafter, sset.checkForChangesThread, clientlib.run
)
