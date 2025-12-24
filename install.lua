local author = "ShrekshellraiserCC"
local repo = "inventoryhell"
local branch = "main"


local test = true

local function get(url)
    if test then
        sleep(0)
        return ""
    end
    local h, err, eh = http.get(url)
    if err or eh then
        local s = ("Error fetching %s.\n%s"):format(url, eh and eh.readAll() or err)
        if eh then eh.close() end
        error(s, 0)
        return
    end
    assert(h, "???")
    local s = h.readAll()
    h.close()
    return s
end

local function get_hash()
    local api_url = ("https://api.github.com/repos/%s/%s/commits/%s"):format(author, repo, branch)
    local s = get(api_url)
    local t = assert(textutils.unserialiseJSON(s))
    return t.sha
end

local inst_dir = "disk"
local always_overwrite = false
local function file_exists_warning(path)
    if always_overwrite then return true end
    while true do
        printError(("WARNING: File %s exists! Overwrite? [N/y/a]"):format(path))
        local s = read()
        local c = s:sub(1, 1):lower()
        if c == "a" then
            always_overwrite = true
            return true
        elseif c == "y" then
            return true
        elseif c == "n" or c == "" then
            return false
        end
    end
end
local function install_file(path, url, write)
    if write then write(("Downloading \31%s"):format(path)) end
    local abs_path = fs.combine(inst_dir, path)
    if fs.exists(abs_path) then
        if not file_exists_warning(abs_path) then return false end
    end
    local s = get(url)
    if write then write((" Installing \21%s"):format(path)) end
    if test then return end
    local f = assert(fs.open(abs_path, "w"))
    f.write(s)
    f.close()
end

local raw_url = ("https://raw.githubusercontent.com/%s/%s/refs/heads/%s/"):format(author, repo, branch)
local function install_dir(path, t, write)
    for k, v in pairs(t) do
        if type(k) == "number" then
            -- Assume the filename matches the file path in the repository.
            local full_path = fs.combine(path, v)
            install_file(full_path, raw_url .. full_path, write)
        elseif type(v) == "string" then
            local full_path = fs.combine(path, k)
            install_file(full_path, v, write)
        elseif type(v) == "table" then
            local root_path = fs.combine(path, k)
            install_dir(root_path, v, write)
        end
    end
end

local api = {}

local manifest
function api.set_manifest(man)
    manifest = man
end

function api.set_install_dir(dir)
    inst_dir = dir
end

local function load_manifest(str)
    manifest = load(str, "manifest", "t", {})()
end

function api.fetch_manifest()
    local manifest_url = raw_url .. "manifest.lua"
    local manifest_str = get(manifest_url)
    load_manifest(manifest_str)
end

function api.set_overwrite(overwrite)
    always_overwrite = overwrite
end

function api.do_install(write)
    assert(type(manifest) == "table", "Invalid Manifest!")
    install_dir("", manifest, write)
end

api.get_hash = get_hash

local args = { ... }
if #args == 2 and type(package.loaded[args[1]]) == "table" and not next(package.loaded[args[1]]) then
    return api
end

-- running from commandline
term.clear()
term.setCursorPos(1, 1)
print("This is the installer for SSD.")
print("Please attach a disk drive and insert a computer or floppy with at least 1MB of total capacity.")
print("Press enter to continue.")
repeat until select(2, os.pullEvent('key')) == keys.enter
repeat
    print("Enter installation directory, or leave blank for /disk/")
    inst_dir = read()
    if inst_dir == "" then inst_dir = "disk" end
    if not fs.exists(inst_dir) then
        printError(("The directory %s does not exist!"):format(inst_dir))
    end
until fs.exists(inst_dir)

print("Fetching Manifest...")
if test then
    local f = assert(fs.open("manifest.lua", "r"))
    local s = f.readAll()
    f.close()
    load_manifest(s)
else
    api.fetch_manifest()
end
api.do_install(print)
