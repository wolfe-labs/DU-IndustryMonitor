--[[
  Very basic implementation of background tasks
]]

-- Makes sure we only ever use 20% of the instruction limit before yielding
local MAX_CPU_TIME = 0.20

local tasks = {}
local iTasks = 0

---@class Task
local Task = {}
---Emits a signal telling the task is complete along with its return value
function Task.resolve(result) end
---Emits a signal telling the task is errored
function Task.reject(error) end
---@param value table The value being iterated over
---@param yield_every number How often we should yield
function Task.iterate(value, yield_every) end

---@param runner fun(task:Task)
local function task(runner)
  iTasks = iTasks + 1
  local id = 0 + iTasks -- We need this here to prevent reference issues
  local self = {}

  local callbacks = {}
  local handlers = {}

  tasks[id] = {
    co = coroutine.create(function(task)
      local status, ret = pcall(runner, task)
      if status then
        task.resolve(ret)
      else
        task.reject(ret)
      end
    end),
    cb = callbacks,
    eh = handlers,
  }

  function self.next(callback)
    table.insert(callbacks, callback)
    return self
  end

  function self.catch(handler)
    table.insert(handlers, handler)
    return self
  end

  function self.completed()
    return tasks[id] == nil
  end

  function self.id()
    return id
  end

  return self
end

local function resolve(_, data, value)
  -- Resolves the task
  for _, callback in pairs(data.cb) do
    callback(value)
  end
  tasks[_] = nil

  -- Stops executing
  coroutine.yield()
end

local function reject(_, data, err)
  if #data.eh == 0 then
    system.print(('Unhandled error on task #%d: %s'):format(_, err))
  end

  -- Rejects the task
  for _, handler in pairs(data.eh) do
    handler(err)
  end
  tasks[_] = nil

  -- Stops executing
  coroutine.yield()
end

local active_task_count = 0
local yield_limit = system.getInstructionLimit() * MAX_CPU_TIME
local function do_rate_limiting()
  if system.getInstructionCount() >= (yield_limit / math.max(active_task_count, 1)) then
    coroutine.yield()
  end
end
local function iterate(value)
  -- Gets a list of all keys
  local keys = {}
  for k in pairs(value) do
    do_rate_limiting()
    
    table.insert(keys, k)
  end
  table.sort(keys)
  
  -- Now, we can actually iterate over that temporary table
  local i = 0
  return function()
    do_rate_limiting()
    
    -- Increments local iterator, returns value if any
    i = i + 1
    if keys[i] then
      return value[keys[i]], keys[i]
    end

    -- This only happens if we don't have any more items
    return nil
  end
end

system:onEvent('onUpdate', function()
  -- Gets an updated task count
  active_task_count = 0
  for _ in pairs(tasks) do
    active_task_count = active_task_count + 1
  end

  -- Processes each of the tasks
  for _, data in pairs(tasks) do
    coroutine.resume(data.co, {
      resolve = function(value)
        resolve(_, data, value)
      end,
      reject = function(err)
        reject(_, data, err)
      end,
      iterate = iterate,
    })
  end
end)

return task