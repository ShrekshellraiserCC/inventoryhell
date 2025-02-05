--- Shrek Task Lib

---@alias TaskID number
---@alias TaskFunction fun():number
---@alias TaskCallback fun(moved:integer)

---@class TaskThreadDescriptor
---@field call TaskFunction
---@field thread thread
---@field id TaskID
---@field depends TaskID[]
---@field filter string?
---@field priority number
---@field callback TaskCallback?

---@class Task
---@field id TaskID
---@field funcs TaskFunction[]
---@field subtasks Task[]
---@field priority number?
---@field callback TaskCallback?
local Task__index = {}
local Task = { __index = Task__index }


---Run a function after this task completes
---  Callback is provided with total # of items moved during the task
---@param f TaskCallback
---@return self
function Task__index:setCallback(f)
    self.callback = f
    return self
end

---Queue and wait for this task to execute
function Task__index:await()

end

---Assert that all operations in this task move the expected amount of items
---@return self
function Task__index:critical()
    return self
end

---Get a list of functions to be executed to complete this task
---@return TaskThreadDescriptor[]
function Task__index:_getThreads()
    -- error("Calling Task:_getThreads on default Task! Overwrite this function!")
    local t = {}
    for i, v in ipairs(self.funcs) do
        t[i] = {
            call = v,
            id = self.id,
            depends = self:_getDependencyIDs(),
            priority = self.priority or 1,
            callback = self.callback,
        }
    end
    return t
end

---Set the item reserve this task should interface with
---@param r Reserve
---@return self
function Task__index:setReserve(r)
    return self
end

---Set the priority of this task (and its subtasks)
---@param p number
---@return self
function Task__index:setPriority(p)
    self.priority = p
    for _, v in ipairs(self.subtasks) do
        v:setPriority(self.priority)
    end
    return self
end

---Add a subtask to this task
---@param t Task
---@return self
function Task__index:addSubtask(t)
    t:setPriority(self.priority)
    self.subtasks[#self.subtasks + 1] = t
    return self
end

---Get a list of all dependencies this task has, by ID
---@return TaskID[]
function Task__index:_getDependencyIDs()
    local ids = {}
    for i, v in ipairs(self.subtasks) do
        ids[i] = v.id
    end
    return ids
end

local lastid = 1
---@param funcs function[]
function Task.new(funcs)
    local self = setmetatable({}, Task)
    self.id = lastid
    self.subtasks = {}
    lastid = lastid + 1
    self.funcs = funcs
    return self
end

---Perform table.remove from tab using the idx table as indicies
---@param idx integer[]
---@param tab any[]
local function removeIndiciesFromTable(idx, tab)
    table.sort(idx, function(a, b)
        return a > b
    end)
    for _, i in ipairs(idx) do
        table.remove(tab, i)
    end
end

local TASK_LIMIT = 128
local function Scheduler()
    ---@type TaskThreadDescriptor[]
    local executingThreads = {}
    ---@type TaskThreadDescriptor[]
    local queuedThreads = {}
    ---Number of threads with a given TaskID, decrement when threads die
    ---@type table<TaskID,number>
    local taskThreadCounts = {}
    ---Number of items moved by a given TaskID
    ---@type table<TaskID,number>
    local taskMovedItems = {}
    local run = {}

    ---Add a thread to the queuedTasks
    ---@param t TaskThreadDescriptor
    local function queue(t)
        queuedThreads[#queuedThreads + 1] = t
        taskThreadCounts[t.id] = (taskThreadCounts[t.id] or 0) + 1
        taskMovedItems[t.id] = 0
    end

    ---Queue a task's subtasks to be ran
    ---@param t Task
    local function queueSubtasks(t)
        for _, v in ipairs(t.subtasks) do
            run.queueTask(v)
        end
    end

    ---Queue a task to be ran
    ---@param t Task
    function run.queueTask(t)
        queueSubtasks(t)
        local threads = t:_getThreads()
        for _, v in ipairs(threads) do
            queue(v)
        end
    end

    ---Check if the depends of a task are met
    ---@param t TaskThreadDescriptor
    ---@return boolean
    local function areDependsMet(t)
        for i, v in ipairs(t.depends) do
            if taskThreadCounts[v] ~= 0 then
                return false
            end
        end
        return true
    end

    ---@param t TaskThreadDescriptor
    local function makeTaskActive(t)
        t.thread = coroutine.create(t.call)
        local ok, filter = coroutine.resume(t.thread)
        t.filter = filter
        if ok and coroutine.status(t.thread) == "dead" then
            -- coroutine instant exited, L+ratio
            taskThreadCounts[t.id] = taskThreadCounts[t.id] - 1
            taskMovedItems[t.id] = taskMovedItems[t.id] + (filter or 0)
            if taskThreadCounts[t.id] == 0 then
                if t.callback then
                    t.callback(taskMovedItems[t.id])
                end
            end
            return 0
        elseif not ok then
            error(filter)
        end
        executingThreads[#executingThreads + 1] = t
        return 1
    end

    ---Pull ready-to-execute tasks from the queue
    local function pollQueue()
        table.sort(queuedThreads, function(a, b)
            if a.priority == b.priority then
                return a.id < b.id
            end
            return a.priority > b.priority
        end)
        local taskCount = #executingThreads
        ---@type number[]
        local toAdd = {}
        for i, v in ipairs(queuedThreads) do
            if taskCount >= TASK_LIMIT then
                break
            end
            if areDependsMet(v) then
                taskCount = taskCount + makeTaskActive(v)
                toAdd[#toAdd + 1] = i
            end
        end
        removeIndiciesFromTable(toAdd, queuedThreads)
    end

    ---Remove a task from the execution list
    ---@param filter number
    ---@param task TaskThreadDescriptor
    local function taskNormalExit(filter, task)
        filter = filter or 0
        if type(filter) ~= "number" then
            error(("Task Thread returned type %s, expected number!"):format(type(filter)))
        end

        taskThreadCounts[task.id] = taskThreadCounts[task.id] - 1
        taskMovedItems[task.id] = taskMovedItems[task.id] + filter
        if taskThreadCounts[task.id] == 0 then
            if task.callback then
                task.callback(taskMovedItems[task.id])
            end
        end
    end

    local function text(y, s, ...)
        local ox, oy = term.getCursorPos()
        term.setCursorPos(1, y)
        term.clearLine()
        term.write(s:format(...))
        term.setCursorPos(ox, oy)
    end
    local function debugOverlay()
        text(1, "E:%d,Q:%d", #executingThreads, #queuedThreads)
        text(2, "tTC[%s]", table.concat(taskThreadCounts, " "))
    end

    ---Tick the task list
    ---@param e any[]
    local function tick(e)
        -- print("PRE", #queuedThreads)
        ---@type number[]
        local deadTasks = {}
        -- print("START", #executingThreads, #queuedThreads)
        for i, task in ipairs(executingThreads) do
            if task.filter == nil or e[1] == "terminate" or e[1] == task.filter then
                local ok, filter = coroutine.resume(task.thread, table.unpack(e))
                if not ok then
                    error(debug.traceback(task.thread, filter), 0) -- TODO make error handling better
                end
                task.filter = filter
                local status = coroutine.status(task.thread)
                if status == "dead" then
                    -- print("Removing the dead!", i)
                    deadTasks[#deadTasks + 1] = i
                    taskNormalExit(filter, task)
                end
            end
        end
        removeIndiciesFromTable(deadTasks, executingThreads)
        pollQueue()
        -- print("POST", #executingThreads)
    end

    function run.run()
        while true do
            debugOverlay()
            local e = table.pack(os.pullEvent())
            tick(e)
        end
    end

    return run
end

return {
    Task = Task,
    Scheduler = Scheduler
}
