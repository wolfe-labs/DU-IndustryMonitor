--[[
  Coroutine-based Backkground Tasks API for Dual Universe
  by Wolfe Labs
  Version: 0.1.0
]]

-- How much CPU time we're allocating for background tasks, defaults to 20%
local MAX_CPU_TIME = 0.20

-- This is a list of all our tasks
local _tasks = {}

-- This is just a counter to calculate the next task index
local _tasks_index = 0

-- This is a pointer to our current task
local _current_task = nil
local _current_task_index = nil
local _current_task_count = 0

-- Helper function to assert we're inside a task
local function task_assert()
  if not _current_task then
    error('This function must be invoked from inside a running task!')
  end
end

-- Helper function to exit a running task
local function task_exit()
  _tasks[_current_task_index] = nil
  coroutine.yield()
end

-- Helper function to rate-limit inside a task
local yield_limit = system.getInstructionLimit() * MAX_CPU_TIME
local function task_cpu_limit()
  if _current_task then
    if system.getInstructionCount() >= (yield_limit / math.max(_current_task_count, 1)) then
      coroutine.yield()
    end
  end
end

-- Helper function that does task processing
local function task_work()
  -- Gets an updated task count
  _current_task_count = 0
  for _ in pairs(_tasks) do
    _current_task_count = _current_task_count + 1
  end

  -- Processes each of the tasks
  for task_index, task in pairs(_tasks) do
    _current_task = task
    _current_task_index = task_index
    coroutine.resume(task.coroutine)
  end

  -- Clears existing data after done
  _current_task = nil
  _current_task_index = nil
end

---@class Task
local Task = {}

--- Creates a new task
function Task.new(runner)
  -- Calculates the new id for our task
  _tasks_index = _tasks_index + 1
  local task_id = 0 + _tasks_index

  -- Those will store our task callbacks and event handlers
  local resolve_callbacks = {}
  local error_handlers = {}

  -- Initializes the task in memory
  _tasks[task_id] = {
    coroutine = coroutine.create(function()
      local status, ret = pcall(runner)
      if status then
        Task.resolve(ret)
      else
        Task.reject(ret)
      end
    end),
    resolve_callbacks = resolve_callbacks,
    error_handlers = error_handlers,
  }

  -- Pointer to our other pointer
  local self = nil

  -- Creates our Task Pointer API
  ---@class TaskPointer
  local TaskPointer = {}

  function TaskPointer.id()
    return task_id
  end

  function TaskPointer.next(callback)
    table.insert(resolve_callbacks, callback)
    return self
  end

  function TaskPointer.catch(handler)
    table.insert(error_handlers, handler)
    return self
  end

  function TaskPointer.completed()
    return _tasks[task_id] == nil
  end

  -- Assigns our API
  self = setmetatable({}, {
    __index = TaskPointer,
  })

  return self
end

--- Resolves a task with an optional return value
function Task.resolve(return_value)
  task_assert()

  -- Invokes each of the callbacks
  for _, callback in pairs(_current_task.resolve_callbacks) do
    callback(return_value)
  end

  -- Deletes task and stops execution
  task_exit()
end

--- Rejects (reports an error) the current task
function Task.reject(error_message)
  task_assert()

  -- Special case when no error handlers are present
  if #_current_task.error_handlers == 0 then
    system.print(('Unhandled error on task #%d: %s'):format(_current_task_index, tostring(error_message)))
  end

  -- Invokes each of the error handlers
  for _, handler in pairs(_current_task.error_handlers) do
    handler(error_message)
  end

  -- Deletes task and stops execution
  task_exit()
end

--- Iterates over an object using a task (can be used outside tasks, too)
function Task.iterate(object)  
  -- Gets a list of all keys
  local keys = {}
  for key in pairs(object) do
    task_cpu_limit()
    
    table.insert(keys, key)
  end
  table.sort(keys)
  
  -- Now, we can actually iterate over that temporary table
  local index = 0
  return function()
    task_cpu_limit()
    
    -- Increments local iterator, returns value if any
    index = index + 1
    if keys[index] then
      return object[keys[index]], keys[index]
    end

    -- This only happens if we don't have any more items
    return nil
  end
end

--- This makes tasks work, make sure you call this from your system.onUpdate event!
function Task.work()
  task_work()
end

-- Special case for DU Lua CLI users
if system.onEvent then
  system:onEvent('onUpdate', task_work)
  Task.work = function() end
end

-- Returs our public API
return Task