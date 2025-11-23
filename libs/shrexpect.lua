local getType
local typesMatch

---Check if a table is an array, and check if values are consistent
---@param arr table
---@return string?
local function getArrayType(arr)
    local t
    if #arr > 0 then
        -- seems like an array
        t = getType(arr[1])
        for i = 1, math.min(#arr, 10) do
            if not typesMatch(getType(arr[i]), t) then
                -- not a consistent array
                return
            end
        end
        return t
    end
end

---Get the type of a given value
---@param v any
---@return string
function getType(v)
    local t = type(v)
    if t == "table" then
        local arrayType = getArrayType(v)
        if arrayType then
            return arrayType .. "[]"
        end
        if v.__type then
            return v.__type
        end
        return "table"
    end
    return type(v)
end

---Check if two types match
---@param a string
---@param b string
---@return boolean
function typesMatch(a, b)
    if a == b then return true end
    if a:match("%[%]%??$") then
        if b == "table" then
            return true
        elseif b:match("^table%[%]") then
            return typesMatch(a:sub(1, #a - 2), b:sub(1, #b - 2))
        end
    end
    return false
end

---Take a string of types (e.g. "number|string[]?") and
--- split it into its components {"number", "string", "nil"}
---@param s string
---@return string[]
local function split(s)
    local values = {}
    for w in s:gmatch("([^|]+)") do
        if w:match("?$") then
            w = w:sub(1, #w - 1)
            values[#values + 1] = "nil"
        end
        values[#values + 1] = w
    end
    return values
end

---@param expected string long-form multi-type (e.g. "string|number?")
---@param actual string
local function checkType(expected, actual)
    local types = split(expected)
    for i, v in ipairs(types) do
        if typesMatch(actual, v) then
            return true
        end
    end
    return false
end

---Assert that the given values match the expected types
---@param types string[] Array of LLS-style types (e.g."string|number?")
---@param values any[]
local function shrexpect(types, values)
    for i = 1, #types do
        local expectedType = types[i]
        local actualType = getType(values[i])
        if not checkType(expectedType, actualType) then
            error(("Bad argument #%d: Expected %s, got %s")
                :format(i, expectedType, actualType), 3)
        end
    end
end

return shrexpect
