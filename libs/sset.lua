-- Shrek Settings
local sset = {}

---@class RegisteredSetting
---@field desc string
---@field type type
---@field gvalue any
---@field lvalue any
---@field default any
---@field name string
---@field device string
---@field requiresReboot boolean?
---@field hasGlobal boolean?

---@type table<string,RegisteredSetting>
sset.registeredSettings = {}
---@type RegisteredSetting[]
sset.settingList = {}

local lsettingFn = "shreksettings.txt"
local gsettingFn = "disk/shreksettings_g.txt"

local function writeToFile(fn, t)
    local f = assert(fs.open(fn, "w"))
    f.write(t)
    f.close()
end

local function saveSettings()
    local gsettings = {}
    local lsettings = {}
    for k, v in pairs(sset.registeredSettings) do
        if v.gvalue ~= nil and v.hasGlobal then
            gsettings[k] = v.gvalue
        end
        if v.lvalue ~= nil then
            lsettings[k] = v.lvalue
        end
    end
    writeToFile(lsettingFn, textutils.serialize(lsettings))
    writeToFile(gsettingFn, textutils.serialize(gsettings))
end

local function readFromFile(fn)
    if not fs.exists(fn) then
        return
    end
    local f = assert(fs.open(fn, "r"))
    local s = f.readAll()
    f.close()
    return s
end

local function loadSettings()
    local gsettings = textutils.unserialize(readFromFile(gsettingFn) or "{}")
    local lsettings = textutils.unserialize(readFromFile(lsettingFn) or "{}")
    for k, v in pairs(gsettings) do
        sset.set(k, v)
    end
    for k, v in pairs(lsettings) do
        sset.set(k, v, true)
    end
end

---Get a setting value
---@param name string|RegisteredSetting
---@param noDefault boolean?
function sset.get(name, noDefault)
    local s = type(name) == "string" and sset.registeredSettings[name] or name
    if not s then
        error(("Failed to get non existant setting %s!"):format(name), 0)
    end
    if s.lvalue ~= nil then
        return s.lvalue
    elseif s.gvalue ~= nil then
        return s.gvalue
    elseif not noDefault then
        return s.default
    end
end

---Set a settings' value, ignores invalid values
---@param name string|RegisteredSetting
---@param value any
---@param loc boolean? Local setting
function sset.set(name, value, loc)
    local s = type(name) == "string" and sset.registeredSettings[name] or name
    if not s then
        error(("Failed to set non existant setting %s!"):format(name), 0)
    end
    local placeholder = {}
    ---@type any
    local svalue = placeholder
    if type(value) == s.type or value == nil then
        svalue = value
    elseif s.type == "number" and type(value) == "string" then
        if tonumber(value) then
            svalue = tonumber(value)
        end
    elseif s.type == "boolean" and type(value) == "string" then
        svalue = value:lower() == "true" or value:lower() == "t"
    end
    if svalue ~= placeholder then
        if loc or not s.hasGlobal then
            s.lvalue = svalue
        else
            s.gvalue = svalue
        end
        saveSettings()
    end
end

---Register a new type of setting
---@param device string
---@param name string
---@param desc string
---@param dType type
---@param default any
---@param requiresReboot boolean?
---@param hasGlobal boolean?
local function setting(device, name, desc, dType, default, requiresReboot, hasGlobal)
    if hasGlobal == nil then hasGlobal = true end
    ---@type RegisteredSetting
    local s = {
        desc = desc,
        type = dType,
        default = default,
        name = name,
        device = device,
        requiresReboot = requiresReboot,
        hasGlobal = hasGlobal
    }
    sset.registeredSettings[device .. ":" .. name] = s
    sset.settingList[#sset.settingList + 1] = s
    return s
end

sset.isTerm = setting("boot", "isTerm", "Is this device a terminal?", "boolean", not not turtle, true, false)
sset.isCrafter = setting("boot", "isCrafter", "Is this device a crafter?", "boolean", not not turtle, true, false)

sset.searchBarOnTop = setting("term", "searchBarOnTop", "Search Bar on Top", "boolean", false, true)
sset.hideExtra = setting("term", "hideExtra", "Hide NBT and other data", "boolean", true, true)

loadSettings()

return sset
