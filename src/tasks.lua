--[[
  Very basic implementation of background tasks
]]

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

local g_iteractions = 0
local function count_iteration(limit)
  g_iteractions = g_iteractions + 1
  if g_iteractions % limit == 0 then
    coroutine.yield()
  end
end
local function iterate(value, yield_every)
  -- This is how ofter we want to yield the iteration
  yield_every = yield_every or 1000

  -- Gets a list of all keys
  local keys = {}
  for k in pairs(value) do
    -- Rate limiting
    count_iteration(yield_every)
    
    table.insert(keys, k)
  end
  table.sort(keys)
  
  -- Now, we can actually iterate over that temporary table
  local i = 0
  return function()
    -- Rate limiting
    count_iteration(yield_every)
    
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