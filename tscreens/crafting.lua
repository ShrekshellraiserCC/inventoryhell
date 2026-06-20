local Coordinates = require "libs.Coordinates"
local ItemDescriptor = require "libs.ItemDescriptor"
---@class SSDTermPluginENV
_ENV = _ENV

---@class ssd.term.plugin.crafting.env
---@field machine_types_list RegisteredMachineType[]
---@field selected_machine_type RegisteredMachineType
local cenv = {
    new_machine_type_name = "",
    new_machine_type_pname = "",
    new_machine_type_slots = "",
    machine_type_recipe_slot_inventory = "1",
    selected_machine_mtype = "grid"
}

_ENV.tapi.register_screen("crafting:machine_types_list", {
    type = "Screen",
    content = {
        {
            type = "Text",
            h = 1,
            text = "MachineTypes List",
            class = "heading"
        },
        {
            type = "Table",
            h = "h-2",
            y = 2,
            columns = {
                { "id",    4,      "ID" },
                { "mtype", "w-12", "Type" },
                { "ptype", 8,      "Parent" }
            },
            list = "$machine_types_list$",
            on_select = function(self, v, idx)
                if v.mtype == "grid" then
                    return
                end
                cenv.selected_machine_type = v
                _ENV.tapi.open_screen("crafting:edit_machine_type")
            end,
            id = "machine-type-list"
        },
        {
            type = "Button",
            y = "h",
            w = "w/3",
            text = "Delete",
            class = "danger-button",
            on_click = function(self)
                cenv.selected_machine_type = self:get_root()
                    :get_widget_by_id("machine-type-list"):get_highlighted()
                cenv.selected_machine_mtype = cenv.selected_machine_type.mtype
                if cenv.selected_machine_mtype == "grid" or cenv.selected_machine_mtype == "furnace" then
                    return
                end
                _ENV.utils.confirm_screen("Delete Machine Type?",
                    ("Are you sure you want to delete the machine type %s? This cannot be undone and will delete all associated machines and recipes.")
                    :format(cenv.selected_machine_mtype),
                    function()
                        _ENV.capi.deleteMachineType(cenv.selected_machine_mtype)
                    end)
            end
        },
        {
            type = "Button",
            y = "h",
            x = "w/3+1",
            w = "w/3",
            text = "Edit Machines",
            on_click = function(self)
                cenv.selected_machine_type = self:get_root()
                    :get_widget_by_id("machine-type-list"):get_highlighted()
                cenv.selected_machine_mtype = cenv.selected_machine_type.mtype
                if cenv.selected_machine_mtype == "grid" then
                    return
                end
                _ENV.tapi.open_screen("crafting:machine_list")
            end
        },
        {
            type = "Button",
            y = "h",
            x = "w/3*2+2",
            text = "New",
            on_click = function(self)
                _ENV.tapi.open_screen("crafting:new_machine_type")
            end
        },
        _ENV.tapi.back_button_template()
    }
}, function()
    cenv.machine_types_list = _ENV.capi.listMachineTypes()
end, cenv)

_ENV.tapi.register_screen("crafting:edit_machine_type", {
    type = "Screen",
    content = {
        {
            type = "Text",
            h = 1,
            text = "Editing Machine Type",
            class = "heading"
        },
        {
            type = "Text",
            y = 2,
            h = 1,
            w = "w/2",
            text = "Type Name |",
            horizontal_alignment = "right"
        },
        {
            type = "Text",
            y = 2,
            h = 1,
            w = "w/2",
            x = "w/2+1",
            text = "$selected_machine_type.mtype$",
            horizontal_alignment = "left"
        },
        {
            type = "Text",
            y = 3,
            h = 1,
            w = "w/2",
            text = "Parent Type Name |",
            horizontal_alignment = "right"
        },
        {
            type = "Text",
            y = 3,
            h = 1,
            w = "w/2",
            x = "w/2+1",
            text = "$selected_machine_type.ptype or 'nil'$",
            horizontal_alignment = "left"
        },
        {
            type = "Frame",
            y = 4,
            w = "w/2",
            h = "h-4",
            padding = { 1, 0 },
            content = {
                {
                    type = "Text",
                    h = 1,
                    text = "Slot Map"
                },
                {
                    type = "Table",
                    y = 2,
                    columns = {
                        { "n", 3,   "i" },
                        { 1,   6,   "Inv" },
                        { 2,   nil, "Slot" }
                    },
                    allow_sort = false,
                    list = "$selected_machine_type.slots$",
                    on_select = function(self, v, idx)
                        cenv.selected_recipe_slot = v
                        cenv.machine_type_recipe_slot_inventory = tostring(v[1])
                        local r = self:get_root()
                        r:get_widget_by_id("slot-number-input"):set_value(tostring(v[2]))
                        r:get_widget_by_id("inventory-number-input"):set_value(tostring(v[1]))
                    end,
                    instant_select = true
                },
            }
        },
        {
            type = "Frame",
            x = "w/2+1",
            y = 4,
            h = "h-4",
            padding = { 1, 0 },
            content = {
                {
                    type = "Text",
                    y = 1,
                    h = 1,
                    text = "$('Input Slot %d'):format(selected_recipe_slot.n)$"
                },
                {
                    type = "Text",
                    y = 2,
                    h = 1,
                    text = "Inventory",
                    horizontal_alignment = "left"
                },
                {
                    type = "Input",
                    y = 3,
                    h = 1,
                    on_change = function(self, v)
                        local n = tonumber(v)
                        if n and n > 0 then
                            cenv.selected_recipe_slot[1] = n
                        end
                    end,
                    id = "inventory-number-input"
                },
                {
                    type = "Text",
                    y = 4,
                    h = 1,
                    w = 5,
                    text = "Slot",
                    horizontal_alignment = "left"
                },
                {
                    type = "Input",
                    y = 4,
                    h = 1,
                    x = 6,
                    on_change = function(self, v)
                        local n = tonumber(v)
                        if n and n > 0 then
                            cenv.selected_recipe_slot[2] = n
                        end
                    end,
                    id = "slot-number-input"
                },
                {
                    type = "Text",
                    y = 6,
                    h = 1,
                    text = "Output Slot(s)"
                },
                {
                    type = "Text",
                    y = 7,
                    h = 1,
                    text = "Inventory",
                    horizontal_alignment = "left"
                },
                {
                    type = "Input",
                    y = 8,
                    h = 1,
                    on_change = function(self, v)
                        local n = tonumber(v)
                        if n and n > 0 then
                            cenv.selected_machine_type.output[1] = n
                        end
                    end,
                    id = "inventory-number-output"
                },
                {
                    type = "Text",
                    y = 9,
                    h = 1,
                    w = 4,
                    text = "Slot",
                    horizontal_alignment = "left"
                },
                {
                    type = "Input",
                    y = 9,
                    h = 1,
                    x = 6,
                    w = 3,
                    on_change = function(self, v)
                        local n = tonumber(v)
                        if n and n > 0 then
                            cenv.selected_machine_type.output[2] = n
                        end
                    end,
                    id = "slot-number-output"
                },
                {
                    type = "Text",
                    y = 9,
                    h = 1,
                    w = 1,
                    x = 10,
                    text = "-"
                },
                {
                    type = "Input",
                    y = 9,
                    h = 1,
                    x = 12,
                    w = 3,
                    on_change = function(self, v)
                        local n = tonumber(v)
                        if n and n > 0 then
                            cenv.selected_machine_type.output[3] = n
                        end
                    end,
                    id = "slot-number-end-output"
                },
            },
        },
        {
            type = "Button",
            y = "h",
            w = "w/2",
            text = "Cancel",
            on_click = tapi.back,
            class = "warning-button"
        },
        {
            type = "Button",
            y = "h",
            x = "w/2+1",
            w = "w/2",
            text = "Save",
            on_click = function()
                local machine_type = cenv.selected_machine_type
                _ENV.capi.setMachineType(machine_type.mtype, machine_type.slots, machine_type.output, machine_type.ptype)
                _ENV.tapi.back()
            end
        },
        _ENV.tapi.back_button_template()
    }
}, function(self)
    for i, v in ipairs(cenv.selected_machine_type.slots) do
        ---@diagnostic disable-next-line: inject-field
        v.n = i
    end
    local root = self:get_root()
    local output = cenv.selected_machine_type.output
    local v = cenv.selected_machine_type.slots[1]
    cenv.selected_recipe_slot = v
    cenv.machine_type_recipe_slot_inventory = tostring(v[1])
    local r = self:get_root()
    r:get_widget_by_id("slot-number-input"):set_value(tostring(v[2]))
    r:get_widget_by_id("inventory-number-input"):set_value(tostring(v[1]))
    root:get_widget_by_id("inventory-number-output"):set_value(output[1])
    root:get_widget_by_id("slot-number-output"):set_value(output[2])
    root:get_widget_by_id("slot-number-end-output"):set_value(output[3] or "")
end, cenv)

local function save_new_machine_type()
    local name = cenv.new_machine_type_name
    ---@type string?
    local pname = cenv.new_machine_type_pname
    local slots = tonumber(cenv.new_machine_type_slots)
    if pname == "" then pname = nil end
    if name == "" or slots == nil or slots < 1 then
        return
    end
    local slotmap = {}
    for i = 1, slots do
        slotmap[i] = { 1, 1 }
    end
    _ENV.capi.setMachineType(name, slotmap, { 1, 1 }, pname)
    _ENV.tapi.back()
    cenv.machine_types_list = _ENV.capi.listMachineTypes()
end
_ENV.tapi.register_screen("crafting:new_machine_type", {
    type = "Screen",
    content = {
        {
            type = "Text",
            h = 1,
            text = "New Machine Type",
            class = "heading"
        },
        {
            type = "Frame",
            y = 2,
            h = "(h-2)/3",
            content = {
                {
                    type = "Text",
                    y = 1,
                    h = 1,
                    w = "w/2",
                    text = "Type Name |",
                    horizontal_alignment = "right"
                },
                {
                    type = "Input",
                    y = 1,
                    h = 1,
                    w = "w/2",
                    x = "w/2+1",
                    value = "$new_machine_type_name$"
                },
                {
                    type = "Text",
                    y = 2,
                    vertical_alignment = "top",
                    text =
                    "Name identifier for this machine type. Make it something simple and memorable as this cannot be changed."
                }
            },
            padding = 1
        },
        {
            type = "Frame",
            h = "(h-2)/3",
            y = "(h-2)/3+2",
            content = {
                {
                    type = "Text",
                    y = 1,
                    h = 1,
                    w = "w/2",
                    text = "Parent Type |",
                    horizontal_alignment = "right"
                },
                {
                    type = "Input",
                    y = 1,
                    h = 1,
                    w = "w/2",
                    x = "w/2+1",
                    value = "$new_machine_type_pname$"
                },
                {
                    type = "Text",
                    y = 2,
                    vertical_alignment = "top",
                    text =
                    "Type name of an existing parent machine type. Optional, use to register an alternative machine that can take the same recipes."
                }
            },
            padding = 1
        },
        {
            type = "Frame",
            h = "(h-2)/3",
            y = "(h-2)*2/3+3",
            content = {
                {
                    type = "Text",
                    y = 1,
                    h = 1,
                    w = "w/2",
                    text = "Input Slot Count |",
                    horizontal_alignment = "right"
                },
                {
                    type = "Input",
                    y = 1,
                    h = 1,
                    w = "w/2",
                    x = "w/2+1",
                    value = "$new_machine_type_slots$"
                },
                {
                    type = "Text",
                    y = 2,
                    vertical_alignment = "top",
                    text = "Number of input slots this machine's recipes use. This cannot be changed later."
                }
            },
            padding = 1
        },
        {
            type = "Button",
            y = "h",
            w = "w/2",
            text = "Cancel",
            on_click = _ENV.tapi.back,
            class = "warning-button"
        },
        {
            type = "Button",
            y = "h",
            x = "w/2+1",
            w = "w/2",
            text = "Save",
            on_click = save_new_machine_type
        },
        _ENV.tapi.back_button_template()
    }
}, function()
    cenv.new_machine_type_name = ""
    cenv.new_machine_type_pname = ""
    cenv.new_machine_type_slots = "1"
end, cenv)

_ENV.tapi.register_screen("crafting:machine_list", {
    type = "Screen",
    content = {
        {
            type = "Text",
            h = 1,
            text = "$'Machine List ' .. selected_machine_mtype$",
            class = "heading"
        },
        _ENV.tapi.back_button_template(),
        {
            type = "Table",
            list = "$machine_list$",
            columns = { { "name", "w/2", "Name" }, { "mtype", nil, "Type" } },
            id = "machine-list",
            y = 2,
            h = "h-2",
            on_select = function(self, v)
                cenv.selected_machine = v --[[@as RegisteredMachine]]
                _ENV.tapi.open_screen("crafting:edit_machine")
            end
        },
        {
            type = "Button",
            y = "h",
            w = "w/2",
            text = "Delete",
            class = "danger-button",
            on_click = function(self)
                ---@type RegisteredMachine
                local machine = self:get_root():get_widget_by_id("machine-list"):get_highlighted()
                if not machine then return end
                _ENV.utils.confirm_screen("Delete Machine?",
                    ("Are you sure you want to delete the machine %s? This cannot be undone."):format(machine.name),
                    function()
                        _ENV.capi.deleteMachine(machine.name)
                    end)
            end
        },
        {
            type = "Button",
            y = "h",
            x = "w/2+1",
            text = "New",
            on_click = function(self)
                cenv.selected_machine = nil
                _ENV.tapi.open_screen("crafting:new_machine")
            end
        }
    }
}, function()
    cenv.machine_list = _ENV.capi.listMachines(cenv.selected_machine_mtype)
end, cenv)

local picker_open = false
local machine_inventory_edit_content = {
    {
        type = "Input",
        h = 1,
        w = "w-1",
        id = "machine-inventory-input",
        on_change = function(self, v)
            -- TODO peripheral validation
            cenv.editing_inventory[1] = v
        end
    },
    {
        type = "Button",
        h = 1,
        x = "w",
        text = "+",
        on_click = function(self)
            local w = self:get_root():get_widget_by_id("machine-inventory-input")
            picker_open = true
            _ENV.utils.inventory_picker(function(side)
                w:set_value(side)
                cenv.editing_inventory[1] = side
            end)
        end
    },
    {
        type = "Table",
        list = "$machine_inventory_list$",
        y = 2,
        columns = {
            { "n", 3,   "idx" },
            { 1,   nil, "Inventory" }
        },
        allow_sort = false,
        on_select = function(self, v)
            local r = self:get_root()
            r:get_widget_by_id("machine-inventory-input"):set_value(v[1])
            cenv.editing_inventory = v
        end,
        instant_select = true
    }
}

local function reset_machine_inventory_edit_content(self)
    local r = self:get_root()
    cenv.machine_inventory_list = {}
    local max = cenv.selected_machine_type.output[1]
    for k, v in pairs(cenv.selected_machine_type.slots) do
        max = math.max(max, v[1])
    end
    for i = 1, max do
        cenv.machine_inventory_list[i] = { n = i }
        if cenv.selected_machine then
            cenv.machine_inventory_list[i][1] = cenv.selected_machine.invs[i]
        end
    end
    cenv.editing_inventory = cenv.machine_inventory_list[1] or {}
    r:get_widget_by_id("machine-inventory-input"):set_value(cenv.editing_inventory[1] or "")
end

_ENV.tapi.register_screen("crafting:edit_machine", {
    type = "Screen",
    content = {
        {
            type = "Text",
            h = 1,
            text = "$'Editing ' .. selected_machine.name$",
            class = "heading"
        },
        _ENV.tapi.back_button_template(),
        {
            type = "Frame",
            y = 2,
            h = "h-2",
            content = machine_inventory_edit_content
        },
        {
            type = "Button",
            y = "h",
            w = "w/2",
            text = "Cancel",
            class = "warning-button",
            on_click = _ENV.tapi.back
        },
        {
            type = "Button",
            y = "h",
            x = "w/2+1",
            text = "Save",
            on_click = function()
                local name = cenv.selected_machine.name
                local invs = {}
                for i, v in ipairs(cenv.machine_inventory_list) do
                    invs[i] = v[1]
                    if v[1] == nil then
                        return false
                    end
                end
                _ENV.capi.setMachine(cenv.selected_machine_mtype, name, invs)
                _ENV.tapi.back()
            end
        }
    }
}, function(self)
    if picker_open then
        picker_open = false
        return
    end
    reset_machine_inventory_edit_content(self)
end, cenv)
_ENV.tapi.register_screen("crafting:new_machine", {
    type = "Screen",
    content = {
        {
            type = "Text",
            h = 1,
            text = "$'Creating new ' .. selected_machine_type.mtype$",
            class = "heading"
        },
        _ENV.tapi.back_button_template(),
        {
            type = "Frame",
            y = 2,
            h = 4,
            padding = 1,
            content = {
                {
                    type = "Text",
                    text = "Name |",
                    h = 1,
                    w = "w/2",
                    horizontal_alignment = "right"
                },
                {
                    type = "Input",
                    h = 1,
                    w = "w/2",
                    x = "w/2+1",
                    id = "machine-name-input",
                    value = "$machine_name_input$"
                },
                {
                    type = "Text",
                    y = 2,
                    text = "Unique name for this specific machine.",
                    vertical_alignment = "top"
                }
            }
        },
        {
            type = "Frame",
            y = 6,
            h = "h-6",
            padding = 1,
            content = machine_inventory_edit_content
        },
        {
            type = "Button",
            y = "h",
            w = "w/2",
            text = "Cancel",
            on_click = _ENV.tapi.back,
            class = "warning-button"
        },
        {
            type = "Button",
            y = "h",
            w = "w/2",
            x = "w/2+1",
            text = "Confirm",
            on_click = function(self)
                local name = cenv.machine_name_input
                if name == "" then
                    name = cenv.machine_inventory_list[1][1]
                end
                local invs = {}
                for i, v in ipairs(cenv.machine_inventory_list) do
                    invs[i] = v[1]
                    if v[1] == nil then
                        return false
                    end
                end
                _ENV.capi.setMachine(cenv.selected_machine_mtype, name, invs)
                _ENV.tapi.back()
                cenv.machine_list = _ENV.capi.listMachines(cenv.selected_machine_mtype)
            end
        }
    }
}, function(self)
    if picker_open then
        picker_open = false
        return
    end
    reset_machine_inventory_edit_content(self)
    local r = self:get_root()
    r:get_widget_by_id("machine-name-input"):set_value("")
    cenv.machine_name_input = ""
end, cenv)

_ENV.tapi.register_screen("crafting:recipes", {
    type = "Screen",
    content = {
        tapi.header_template("Recipes"),
        tapi.back_button_template(),
        {
            type = "Table",
            y = 2,
            h = "h-2",
            columns = { { "id", 4, "RID" }, { "type", 8, "Type" }, { "displayName", nil, "Name" } },
            list = "$recipes$",
            id = "recipe-list",
            on_select = function(self, v)
                ---@type ssd.host.RecipeInfo
                cenv.editing_recipe = capi.getRecipeInfo(v.id)
                _ENV.tapi.open_screen("crafting:edit_recipe")
            end
        },
        {
            type = "Button",
            y = "h",
            w = "w/2",
            text = "Delete",
            class = "danger-button",
            on_click = function(self)
                ---@type RecipeInfo?
                local hovered = self:get_root():get_widget_by_id("recipe-list"):get_highlighted()
                if not hovered then return end
                local id = hovered.id
                _ENV.utils.confirm_screen("Delete Recipe?",
                    ("Are you sure you want to delete the recipe for %s (id %d)? This cannot be undone."):format(
                        hovered.name, id),
                    function()
                        capi.deleteRecipe(id)
                        cenv.recipes = capi.listRecipes()
                    end)
            end
        },
        {
            type = "Button",
            y = "h",
            x = "w/2+1",
            text = "New",
            on_click = function()
                _ENV.tapi.open_screen("crafting:new_recipe_type_select")
            end
        }
    }
}, function()
    cenv.recipes = capi.listRecipes()
end, cenv)

_ENV.tapi.register_screen("crafting:new_recipe_type_select", {
    type = "Screen",
    content = {
        _ENV.tapi.header_template("Select Type"),
        _ENV.tapi.back_button_template(),
        {
            type = "Table",
            y = 2,
            columns = {
                { "id",    4,      "ID" },
                { "mtype", "w-12", "Type" },
                { "ptype", 8,      "Parent" }
            },
            list = "$machine_types_list$",
            on_select = function(self, v, idx)
                cenv.recipe_mtype = v.mtype
                if cenv.recipe_mtype == "grid" and turtle and turtle.craft then
                    _ENV.tapi.open_screen("crafting:new_recipe_grid")
                else
                    _ENV.tapi.open_screen("crafting:new_recipe")
                end
            end,
            id = "machine-type-list"
        }
    }
}, function()
    cenv.machine_types_list = _ENV.capi.listMachineTypes()
end, cenv)

local turtle_slots = { 1, 2, 3, 5, 6, 7, 9, 10, 11 }
---@param listing table<integer,CCItemInfo>
---@param output CCItemInfo
local function add_grid_recipe_from_turtle_inv(listing, output)
    local items = {}
    local recipe = {}
    local seen_items = {}
    for i, v in ipairs(turtle_slots) do
        local item = listing[v]
        if item then
            local id = ItemDescriptor.fromName(item.name, item.nbt):serialize()
            if not seen_items[id] then
                items[#items + 1] = id
                seen_items[id] = #items
            end
            recipe[i] = seen_items[id]
        end
    end

    local product = Coordinates.ItemCoordinate(output.name, output.nbt)
    local produces = output.count
    _ENV.capi.newRecipe("grid", items, recipe, product, produces)
end

_ENV.tapi.register_screen("crafting:new_recipe_grid", {
    type = "Screen",
    content = {
        _ENV.tapi.back_button_template {
            on_click = function(self)
                tapi.lock_inventory(false)
                tapi.clear_locked_slots()
                tapi.back()
            end
        },
        _ENV.tapi.header_template("Grid Setup"),
        {
            type = "Text",
            y = 2,
            h = "h-2",
            text =
            "Place the recipe you want to teach in the top left 9 squares of the turltle's inventory. Press continue to have the turtle craft and learn the recipe."
        },
        {
            type = "Button",
            y = "h",
            w = "w/2",
            text = "Cancel",
            on_click = function()
                tapi.lock_inventory(false)
                tapi.clear_locked_slots()
                tapi.back()
            end
        },
        {
            type = "Button",
            y = "h",
            x = "w/2+1",
            text = "Continue",
            class = "warning-button",
            on_click = function()
                local listing = tapi.list_inventory()
                local ok, err = turtle.craft()
                if not ok then
                    _ENV.utils.info_screen("Invalid",
                        ("Something went wrong when trying to craft this recipe. (%s)"):format(err or ""))
                    return
                end
                local info = turtle.getItemDetail() --[[@as CCItemInfo]]
                tapi.lock_inventory(false)
                tapi.clear_locked_slots()
                add_grid_recipe_from_turtle_inv(listing, info)
                tapi.back()
                tapi.back() -- go back to crafting:list_recipes
                cenv.recipes = capi.listRecipes()
            end
        }
    }
}, function()
    tapi.lock_inventory(true) -- need to unlock inventory upon leaving
end, cenv)

_ENV.tapi.register_screen("crafting:new_recipe", {
    type = "Screen",
    content = {
        _ENV.tapi.back_button_template(),
        _ENV.tapi.header_template("New Recipe"),
        {
            type = "Text",
            y = 2,
            text = "What item does this recipe produce?",
            h = 3
        },
        {
            type = "Frame",
            y = 5,
            h = 1,
            padding = { 1, 0 },
            content = {
                {
                    type = "Input",
                    w = "w-1",
                    id = "recipe-product-input",
                    value = "$recipe_product$"
                },
                {
                    type = "Button",
                    x = "w",
                    text = "+",
                    on_click = function(self)
                        local input = self:get_root():get_widget_by_id("recipe-product-input")
                        _ENV.utils.item_picker(function(ID)
                            local coord = ItemDescriptor.unserialize(ID):toCoord()
                            if coord then
                                local name, nbt = Coordinates.splitItemCoordinate(coord)
                                input:set_value(name)
                            end
                        end)
                    end
                }
            }
        },
        {
            type = "Button",
            y = "h",
            w = "w/2",
            text = "Cancel",
            on_click = tapi.back
        },
        {
            type = "Button",
            y = "h",
            x = "w/2+1",
            text = "Next",
            on_click = function(self)
                local r = {
                    id = -1,
                    items = {},
                    produces = 1,
                    product = Coordinates.ItemCoordinate(cenv.recipe_product),
                    recipe = {},
                    type = cenv.recipe_mtype
                }
                cenv.editing_recipe = r
                local id = capi.newRecipe(r.type, r.items, r.recipe, r.product, r.produces)
                r.id = id
                tapi.back()
                tapi.open_screen("crafting:edit_recipe")
            end
        }
    }
}, function(self)
    cenv.recipe_product = ""
    self:get_root():get_widget_by_id("recipe-product-input"):set_value("")
end, cenv)

local function refresh_editing_recipe()
    cenv.editing_recipe_items = {}
    cenv.recipe_item_list = {}
    for i, v in ipairs(cenv.editing_recipe.items) do
        cenv.editing_recipe_items[i] = { v, n = i }
        cenv.recipe_item_list[i] = v
    end
    local machine_type = capi.getMachineTypeInfo(cenv.editing_recipe.type)
    if not machine_type then
        error("Trying to edit recipe for invalid machine type.")
    end
    cenv.editing_recipe_recipe = {}
    local recipe = cenv.editing_recipe
    local n = #machine_type.slots
    if cenv.editing_recipe.type == "grid" then
        n = 9
    end
    for i = 1, n do
        local index = recipe.recipe[i]
        local count = 1
        if type(index) == "table" then count = index[2] end
        if type(index) == "table" then index = index[1] end
        cenv.editing_recipe_recipe[i] = {
            index = index or "-",
            item = recipe.items[index] or "",
            count = index and count or "",
            slot = i
        }
    end
end

local function remove_recipe_item(index)
    for i, v in pairs(cenv.editing_recipe.recipe) do
        local n = v
        if type(v) == "table" then
            n = v[1]
        end
        if n == index then
            cenv.editing_recipe.recipe[i] = nil
        elseif n > index then
            if type(v) == "table" then
                v[1] = n - 1
            else
                cenv.editing_recipe.recipe[i] = n - 1
            end
        end
    end
    table.remove(cenv.editing_recipe.items, index)
    refresh_editing_recipe()
end

_ENV.tapi.register_screen("crafting:edit_recipe", {
    type = "Screen",
    content = {
        _ENV.tapi.back_button_template(),
        _ENV.tapi.header_template("Edit Recipe"),
        {
            type = "Text",
            h = 1,
            y = 2,
            text =
            "$('RID: %d. Produces %d of %s.'):format(editing_recipe.id, editing_recipe.produces, editing_recipe.product)$"
        },
        {
            type = "Text",
            y = 3,
            h = 1,
            w = "w/2",
            horizontal_alignment = "right",
            text = "Produces |"
        },
        {
            type = "Input",
            y = 3,
            h = 1,
            x = "w/2+1",
            id = "produces-input",
            on_change = function(self, v)
                local n = tonumber(v)
                if n then
                    cenv.editing_recipe.produces = n
                    refresh_editing_recipe()
                end
            end
        },
        {
            type = "Frame",
            y = 4,
            h = "h-4",
            w = "w/2",
            content = {
                {
                    type = "Text",
                    h = 1,
                    text = "Items"
                },
                {
                    type = "Input",
                    h = 1,
                    y = 2,
                    w = "w-1",
                    id = "itemdescriptor-input",
                    on_change = function(self, v)
                        local ok, id = pcall(ItemDescriptor.unserialize, v)
                        if not (ok and id) then return end
                        if cenv.selected_item_slot then
                            cenv.editing_recipe.items[cenv.selected_item_slot] = v
                            refresh_editing_recipe()
                        end
                    end
                },
                {
                    type = "Button",
                    x = "w",
                    h = 1,
                    y = 2,
                    text = "+",
                    on_click = function(self)
                        local item_input = self:get_root():get_widget_by_id("itemdescriptor-input")
                        utils.item_picker(function(ID)
                            item_input:set_value(ID)
                        end)
                    end
                },
                {
                    type = "Table",
                    list = "$editing_recipe_items$",
                    id = "recipe-items",
                    columns = {
                        { "n", 3,   "n" },
                        { 1,   nil, "Item" }
                    },
                    y = 3,
                    h = "h-3",
                    on_select = function(self, v, i)
                        cenv.selected_item_slot = i
                        self:get_root():get_widget_by_id("itemdescriptor-input"):set_value(v[1])
                    end,
                    allow_sort = false,
                    instant_select = true
                },
                {
                    type = "Button",
                    text = "-",
                    y = "h",
                    w = "w/2",
                    on_click = function(self)
                        if cenv.selected_item_slot then
                            remove_recipe_item(cenv.selected_item_slot)
                            cenv.selected_item_slot = nil
                        end
                    end
                },
                {
                    type = "Button",
                    text = "+",
                    y = "h",
                    x = "w/2+1",
                    on_click = function(self)
                        cenv.editing_recipe.items[#cenv.editing_recipe.items + 1] = "*"
                        refresh_editing_recipe()
                    end
                }
            }
        },
        {
            type = "Frame",
            y = 4,
            h = "h-5",
            x = "w/2+1",
            content = {
                {
                    type = "Text",
                    h = 1,
                    text = "Recipe"
                },
                {
                    type = "Dropdown",
                    y = 2,
                    h = 1,
                    w = "w-5",
                    options = "$recipe_item_list$",
                    id = "recipe-item-dropdown",
                    on_change = function(self, v, idx)
                        local h = self:get_root():get_widget_by_id("recipe-slot-list"):get_highlighted()
                        if h then
                            local slot = h.slot
                            local recipe = cenv.editing_recipe
                            local item = recipe.recipe[slot]
                            if type(item) == "table" then
                                item[1] = idx
                            else
                                recipe.recipe[slot] = idx
                            end
                            refresh_editing_recipe()
                        end
                    end
                },
                {
                    type = "Text",
                    y = 2,
                    w = 1,
                    h = 1,
                    x = "w-4",
                    text = "*"
                },
                {
                    type = "Input",
                    y = 2,
                    w = 3,
                    h = 1,
                    x = "w-3",
                    id = "recipe-item-count",
                    on_change = function(self, v)
                        local count = tonumber(v)
                        local h = self:get_root():get_widget_by_id("recipe-slot-list"):get_highlighted()
                        if count and h then
                            local slot = h.slot
                            local recipe = cenv.editing_recipe
                            local item = recipe.recipe[slot]
                            if type(item) == "table" then
                                item[2] = count
                            else
                                recipe.recipe[slot] = { item, count }
                            end
                            refresh_editing_recipe()
                        end
                    end
                },
                {
                    type = "Button",
                    y = 2,
                    x = "w",
                    h = 1,
                    text = "x",
                    class = "danger-button",
                    on_click = function(self)
                        self:get_root():get_widget_by_id("recipe-item-dropdown"):set_value("")
                        self:get_root():get_widget_by_id("recipe-item-count"):set_value("")
                        local h = self:get_root():get_widget_by_id("recipe-slot-list"):get_highlighted()
                        if h then
                            local slot = h.slot
                            local recipe = cenv.editing_recipe
                            recipe.recipe[slot] = nil
                            refresh_editing_recipe()
                        end
                    end
                },
                {
                    type = "Table",
                    y = 3,
                    columns = {
                        { "slot",  3,   "s" },
                        { "index", 3,   "n" },
                        { "count", 3,   "#" },
                        { "item",  nil, "Item" }
                    },
                    allow_sort = false,
                    instant_select = true,
                    list = "$editing_recipe_recipe$",
                    id = "recipe-slot-list",
                    on_select = function(self, v)
                        self:get_root():get_widget_by_id("recipe-item-dropdown"):set_value(v.item)
                        self:get_root():get_widget_by_id("recipe-item-count"):set_value(tostring(v.count or 1))
                    end
                }
            }
        },
        {
            type = "Button",
            y = "h-1",
            x = "w/2+1",
            h = 1,
            text = "HELP",
            on_click = function()
                tapi.open_screen("help:edit_recipe")
            end
        },
        {
            type = "Button",
            y = "h",
            w = "w/2",
            text = "Cancel",
            on_click = tapi.back
        },
        {
            type = "Button",
            y = "h",
            x = "w/2+1",
            text = "Save",
            on_click = function(self)
                local recipe = cenv.editing_recipe
                capi.editRecipe(recipe.id, recipe.type, recipe.items, recipe.recipe, recipe.product, recipe.produces)
                tapi.back() -- recipe list
                tapi.back() -- Machines/Recipes screen
            end
        }
    }
}, function(self)
    refresh_editing_recipe()
    self:get_widget_by_id("produces-input"):set_value(cenv.editing_recipe.produces)
end, cenv)

_ENV.tapi.register_screen("crafting:menu", {
    type = "Screen",
    content = {
        {
            type = "Text",
            h = 1,
            text = "Crafting",
            class = "heading"
        },
        _ENV.tapi.back_button_template(),
        {
            type = "Button",
            text = "Machines",
            on_click = function()
                _ENV.tapi.open_screen("crafting:machine_types_list")
            end,
            w = "w/2",
            y = 2
        },
        {
            type = "Button",
            text = "Recipes",
            x = "w/2+1",
            y = 2,
            on_click = function()
                _ENV.tapi.open_screen("crafting:recipes")
            end
        }
    }
}, nil, cenv)
_ENV.tapi.register_menu_button(2, "Crafting", "crafting:menu")
