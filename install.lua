local author = "ShreksHellraiserCC"
local repo = "inventoryhell"
local branch = "main"


local test = fs.exists("ideas.txt") -- jank to avoid running the installer in my dev environment

local function get(url)
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
    if test then
        print((" FakeInstal \21%s"):format(path))
        return
    end
    local s = get(url)
    if write then write((" Installing \21%s"):format(path)) end
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
    local sset = require "libs.sset"
    sset.set(sset.version, api.get_hash())
    settings.set("shell.allow_disk_startup", true)
end

api.get_hash = get_hash

local args = { ... }
if #args == 2 and type(package.loaded[args[1]]) == "table" and not next(package.loaded[args[1]]) then
    return api
end

local function fake_screen(heading, text, footer)
    term.clear()
    term.setCursorPos(1, 1)
    term.setBackgroundColor(colors.blue)
    term.clearLine()
    print(heading)
    term.setBackgroundColor(colors.black)
    print(text)
    local _, h = term.getSize()
    term.setCursorPos(1, h)
    if footer then
        term.setTextColor(colors.yellow)
        term.write(footer)
    end
    term.setTextColor(colors.white)
end

local function wait_for_key(k)
    repeat until select(2, os.pullEvent("key")) == k
end

-- running from commandline
fake_screen("SSD Install Disclaimer",
    [[This is a PREVIEW of an EARLY in development storage system and may not represent the final product.

The purpose of this preview is to get UI/UX feedback, if you have any, please message @ShreksHellraiser.

If you find bugs/crashes, please INSTEAD report them to the github repo inventoryhell.]], "Press [ Y ] to continue.")
wait_for_key(keys.y)


if not term.isColor() then
    fake_screen("SSD Install Warning",
        "This version of SSD lacks extensive keyboard navigation and does not support basic computers.",
        "Press [ Enter ] to continue anyways.")
    wait_for_key(keys.enter)
end

fake_screen("SSD Installer",
    [[An SSD network consists of
* A disk with the program files and global configuration
* A computer configured as a host
* Any number of computers/turtles configured as terminals
* NYI* - Any number of crafting turtles

This program will install the necessary files to a directory of your choosing.
]], "Press [ Enter ] to continue.")
wait_for_key(keys.enter)

fake_screen("SSD Installer",
    "Please attach a disk drive and insert a computer or floppy with at least 1MB of total capacity.",
    "Press [ Enter ] to continue.")
wait_for_key(keys.enter)
repeat
    fake_screen("SSD Installer", "Enter installation directory, or leave blank for /disk/", "Dir [/disk/]? ")
    inst_dir = read()
    if inst_dir == "" then inst_dir = "disk" end
    if not fs.exists(inst_dir) then
        printError(("The directory %s does not exist!"):format(inst_dir))
        sleep(1)
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

fake_screen("SSD Installed!", "SSD has finished installing!", "Press [ Enter ] to reboot.")
wait_for_key(keys.enter)
os.reboot()
