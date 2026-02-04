-- Shrek Settings
local sset = {}
package.path = package.path .. ";libs/?.lua"

---@class RegisteredSetting
---@field desc string
---@field type type
---@field gvalue any
---@field lvalue any
---@field default any
---@field name string
---@field requiresReboot boolean?
---@field side "global"|"local"|"both"
---@field options any[]?

---@type table<string,RegisteredSetting>
sset.registeredSettings = {}
---@type RegisteredSetting[]
sset.settingList = {}

local lsettingLoadTime = os.epoch("utc")
local lsettingFn = "shreksettings.txt"
local gsettingLoadTime = os.epoch("utc")

local cwd = fs.combine(arg[0], "..")
if not fs.exists(fs.combine(cwd, "libs/sset.lua")) then
    error(
        "SSET cannot automatically determine the installation path when required from a program not in the SSD installation path.")
end
local gsettingFn = fs.combine(cwd, "shreksettings_g.txt")

local function writeToFile(fn, t)
    local f = assert(fs.open(fn, "w"))
    f.write(t)
    f.close()
end

local function clone(t)
    local nt = {}
    for k, v in pairs(t) do
        nt[k] = v
    end
    return nt
end

local function pruneSetting(set, value)
    local s = clone(set)
    s.gvalue = nil
    s.lvalue = nil
    s.name = nil
    s.value = value
    return s
end

local function saveSettings()
    local gsettings = {}
    local lsettings = {}
    for k, v in pairs(sset.registeredSettings) do
        if v.gvalue ~= nil or v.side ~= "local" then
            gsettings[k] = pruneSetting(v, v.gvalue)
        end
        if v.lvalue ~= nil then
            lsettings[k] = pruneSetting(v, v.lvalue)
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

local function isIn(t, v)
    for _, tv in pairs(t) do
        if tv == v then
            return true
        end
    end
end

---@param name string|RegisteredSetting
---@param value any
---@param loc boolean? Local setting
---@param lset table? Loaded setting table
---@return boolean
local function setraw(name, value, loc, lset)
    local s = (type(name) == "string" and sset.registeredSettings[name]) or (type(name) == "table" and name)
    if not s and lset then
        s = lset
        lset.value = nil
        lset.name = name
        sset.registeredSettings[name] = lset
        sset.settingList[#sset.settingList + 1] = lset
    elseif not s then
        error(("Failed to set non existant setting %s!"):format(name), 0)
    end
    local placeholder = {}
    ---@type any
    local svalue = placeholder
    if s.type == "number" and type(value) == "string" and tonumber(value) then
        value = tonumber(value)
    elseif s.type == "boolean" and type(value) == "string" then
        value = value:lower() == "true" or value:lower() == "t"
    end
    if s.options then
        -- Intentionally a separate if-statement
        if isIn(s.options, value) then
            svalue = value
        elseif value == nil then
            svalue = value
        end
    elseif type(value) == s.type or value == nil then
        svalue = value
    end
    if svalue ~= placeholder then
        if s.side == "local" or (s.side == "both" and loc) then
            s.lvalue = svalue
        else
            s.gvalue = svalue
        end
        return true
    end
    return false
end

local function loadSettings()
    lsettingLoadTime = os.epoch("utc")
    gsettingLoadTime = os.epoch("utc")
    local gsettings = textutils.unserialize(readFromFile(gsettingFn) or "{}") --[[@as table]]
    local lsettings = textutils.unserialize(readFromFile(lsettingFn) or "{}") --[[@as table]]
    for k, v in pairs(gsettings) do
        setraw(k, v.value, false, v)
    end
    for k, v in pairs(lsettings) do
        setraw(k, v.value, true, v)
    end
end

---Get a setting value
---@param name string|RegisteredSetting
---@param noDefault boolean?
function sset.get(name, noDefault)
    local s = (type(name) == "string" and sset.registeredSettings[name]) or (type(name) == "table" and name)
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

---Set a settings' value, ignores invalid values. Settings can be set to nil.
---@param name string|RegisteredSetting
---@param value any
---@param loc boolean? Local setting
function sset.set(name, value, loc)
    if setraw(name, value, loc) then
        saveSettings()
    end
end

---@alias fileAttributes ccTweaked.fs.fileAttributes
---@param attr fileAttributes
local function hasUpdated(attr, last)
    return attr.modified > last
end

---@type function?
local onChangedCallback
---Register a function to be called when settings are changed.
---@param f function
function sset.onChangedCallback(f)
    onChangedCallback = f
end

---Checks the config files to see if they have been modified since last loaded
---If so, reload them
function sset.checkForChanges()
    local hasChanged
    if fs.exists(lsettingFn) then
        local lattr = fs.attributes(lsettingFn)
        hasChanged = hasUpdated(lattr, lsettingLoadTime)
    end
    if fs.exists(gsettingFn) then
        local gattr = fs.attributes(gsettingFn)
        hasChanged = hasChanged or hasUpdated(gattr, gsettingLoadTime)
    end
    if hasChanged then
        loadSettings()
        if onChangedCallback then
            onChangedCallback()
        end
    end
end

function sset.checkForChangesThread()
    while true do
        sleep(sset.get(sset.settingChangeCheckInterval))
        sset.checkForChanges()
    end
end

function sset.getInstalledPath(fn)
    return fs.combine(sset.get(sset.installDir), fn)
end

---Register a new type of setting
---@param name string
---@param desc string
---@param dType type
---@param default any
---@param requiresReboot boolean?
---@param side "global"|"local"|"both"?
---@param options any[]?
local function registerSetting(name, desc, dType, default, requiresReboot, side, options)
    if side == nil then side = "both" end
    local a = sset.registeredSettings[name]
    ---@type RegisteredSetting
    local s = a or {
        type = dType,
        name = name,
        side = side,
    }
    s.desc = desc
    s.default = default
    s.requiresReboot = requiresReboot
    s.options = options
    if not a then
        sset.registeredSettings[name] = s
        sset.settingList[#sset.settingList + 1] = s
    end
    return s
end
sset.register = registerSetting

sset.version = registerSetting(
    "sset:version", "The version of SSD last installed to this system. Do not modify.", "string", nil, true, "global"
)
sset.debug = registerSetting("sset:debug", "Debug mode.", "boolean", false, true, "both")
sset.program = registerSetting(
    "boot:program", "What function does this computer serve?", "string", nil, true, "local",
    { "host", "term", "crafter", "host+term" })
sset.hid = registerSetting("boot:hid", "Storage Host ID", "number", nil, true, "global")
sset.hmn = registerSetting("boot:hmn", "Storage Host Modem Name", "string", nil, true, "global")
sset.installDir = registerSetting("boot:installDir", "Installation directory", "string", cwd, true, "global")

sset.debounceDelay = registerSetting("term:debounceDelay", "Debounce turtle_inventory by waiting this long.", "number",
    0.2, true)
sset.termInventory = registerSetting("term:inventory", "Which inventory to use for I/O for this term.", "string", nil,
    true, "local")
sset.termInventoryPoll = registerSetting("term:inventoryPoll",
    "How frequently to poll the configured inventory for changes", "number", 1, true, "local")
sset.termListingCategories = registerSetting("term:listingCategories",
    "Preset categories for filtering items.", "table", {
        { "All",          "*" },
        { "Stored",       "#>0" },
        { "Craftables",   "#=0" }, -- TODO implement craftable ItemDescriptor
        { "Non-stacking", "!S" }
    }, true, "both")
sset.requestScreenType = registerSetting("term:requestScreenType",
    "Whether to use the new key-chord based item request screen, or a simple count input box.", "string",
    "chord", true, "both", { "chord", "input" })

sset.theme = registerSetting("ui:theme", [[
Color theme to use for UIs as path to .lua theme file.
Invalid paths reset to default palette.
Paths are absolute.
]], "string", sset.getInstalledPath "themes/gnome.sthm", true, "both")

sset.settingChangeCheckInterval = registerSetting("sset:settingChangeCheckInterval",
    "Delay between checking whether the config files have been updated.", "number", 5, nil, "global")

sset.changeBroadcastInterval = registerSetting("host:changeBroadcastInterval",
    "Delay between inventory update packets are broadcast.", "number", 0.2, nil, "global")
sset.taskBroadcastInterval = registerSetting("host:taskBroadcastInterval", "Delay between task update packets.", "number",
    0.2, true, "global")
sset.recipeCacheDir = registerSetting("host:recipeCacheDir",
    "What directory should the recipes be saved in. WARNING: Make sure to save your recipes after changing this!",
    "string", "/", true, "global")

sset.craftRotate = registerSetting("crafter:rotate", [[
Should crafters rotate to indicate they have crafted an item.
]], "boolean", true, false, "global")
sset.craftDelay = registerSetting("crafter:delay", [[
How long should be waited between frames on the crafter
]], "number", 0.1, false, "global")
sset.craftVisualizer = registerSetting("crafter:visualizer", [[
What visualizer to use for rendering on crafters.
]], "string", "DVD", true, "global", { "DVD", "Bouncy", "None", "Random" })
sset.craftMax = registerSetting("crafter:max", [[
Maximum 'particles' to display on the crafter at any time.
]], "number", 100, false, "global")
sset.craftKeep = registerSetting("crafter:keepCount", [[
Whether the crafter should keep count of how many items it has crafted through reboots.
]], "boolean", true, true, "global")

loadSettings()

return sset
