local json = require('json')
local Task = require('tasks')

-- Public options
Include_3D_Printers = true --export
Include_Assembly_Lines = true --export
Include_Chemical_Industries = true --export
Include_Electronics_Industries = true --export
Include_Glass_Furnaces = true --export
Include_Honeycomb_Refiners = true --export
Include_Metalwork_Industries = true --export
Include_Recyclers = true --export
Include_Refiners = true --export
Include_Smelters = true --export
Include_Transfer_Units = true --export

-- Ensures a core is linked
local core = library.getCoreUnit()
if not core then
  system.print('ERROR: Core Unit not connected!')
  return unit.exit()
end

-- Gets connected screens
local screens = library.getLinksByClass('Screen', true) ---@type table<number,Screen>

-- Bootstrap
system.print('[ Wolfe Labs Industry Monitor v1.0 ]')

-- General definitions
local industry_states = {
  [0] = 'Loading',
  [1] = 'Stopped',
  [2] = 'Running',
  [3] = 'No Ingredients',
  [4] = 'Output Full',
  [5] = 'No Output',
  [6] = 'Pending',
  [7] = 'Missing',
}

-- Creates industry groups
local industry_group_search = {}
if Include_3D_Printers then industry_group_search['3D Printer'] = '3D Printers' end
if Include_Transfer_Units then industry_group_search['Transfer Unit'] = 'Transfer Units' end
if Include_Assembly_Lines then industry_group_search['Assembly Line'] = 'Assembly Lines' end
if Include_Chemical_Industries then industry_group_search['Chemical Industry'] = 'Chemical Industries' end
if Include_Refiners then industry_group_search['Refiner'] = 'Refiners' end
if Include_Electronics_Industries then industry_group_search['Electronics Industry'] = 'Electronics Industries' end
if Include_Smelters then industry_group_search['Smelter'] = 'Smelters' end
if Include_Recyclers then industry_group_search['Recycler'] = 'Recyclers' end
if Include_Glass_Furnaces then industry_group_search['Glass Furnace'] = 'Glass Furnaces' end
if Include_Honeycomb_Refiners then industry_group_search['Honeycomb Refiner'] = 'Honeycomb Refineries' end
if Include_Metalwork_Industries then industry_group_search['Metalwork Industry'] = 'Metalwork Industries' end

local industry_groups = {}
for _, name in pairs(industry_group_search) do
  industry_group_search[_] = _
  industry_groups[_] = {
    name = name,
    items = {
      [1] = {},
      [2] = {},
      [3] = {},
      [4] = {},
      [5] = {},
    },
  }
end

-- Utility to merge arrays
local function array_merge(array, ...)
  local arrays = {...}
  local result = { table.unpack(array) }
  for _, array in pairs(arrays) do
    for _, value in pairs(array) do
      table.insert(result, value)
    end
  end
  return result
end

-- Utility to get world position
local function local_to_world(pos)
  return vec3(construct.getWorldPosition())
    + vec3(construct.getWorldRight()) * pos.x
    + vec3(construct.getWorldForward()) * pos.y
    + vec3(construct.getWorldUp()) * pos.z
end

-- Utility to set a destination
local function set_waypoint(pos)
  system.setWaypoint(('::pos{0,0,%.4f,%.4f,%.4f}'):format(pos.x, pos.y, pos.z))
end

-- Utility to split a command in spaces
local function split(str)
  local tokens = {}
  for token in string.gmatch(str, "[^%s]+") do
    table.insert(tokens, token)
  end
  return tokens
end

-- Gets items by id with caching
local item_cache = {}
local function getItem(id)
  if not item_cache[id] then
    item_cache[id] = system.getItem(id)
  end
  return item_cache[id]
end

-- Loads all present industry in construct
local industry_count = 0
local industry = {}
local item_cache = {}
local task_industry = Task(function(task)
  local ids = core.getElementIdList()
  table.sort(ids)

  for local_id in task.iterate(ids) do
    if 'Industry' == core.getElementClassById(local_id):sub(1, 8) then
      industry_count = industry_count + 1

      -- Let's have a cache of industry info to speed-up bootstrap
      local item_id = core.getElementItemIdById(local_id)

      -- Let's extract current industry info
      local item = getItem(item_id)

      -- Let's get the industry group
      for group_id, search in task.iterate(industry_group_search) do
        if nil ~= item.displayName:lower():find(search:lower()) then
          local industry_data = {
            id = local_id,
            num = industry_count,
            tier = item.tier,
            state = 'Loading',
            state_code = 0,
            item = nil,
          }
          
          industry[tostring(industry_count)] = industry_data
          table.insert(industry_groups[group_id].items[item.tier], industry_data)
          break
        end
      end
    end
  end
end)

task_industry.next(function()
  -- Main render loop
  local task_render = nil
  local function render()
    if (not task_render) or task_render.completed() then
      task_render = Task(function(task)
        -- Creates main listing, sorts by tier
        local entries = {}
        for group in task.iterate(industry_groups) do
          local items = {}

          -- Adds title
          table.insert(items, group.name)

          -- Adds items
          for tier_items in task.iterate(group.items) do
            for industry_unit in task.iterate(tier_items) do
              local is_running = industry_unit.state_code == 2 or industry_unit.state == 6

              table.insert(items, {
                industry_unit.num,
                industry_unit.tier,
                is_running,
                industry_unit.state_code,
                industry_unit.state,
                industry_unit.item or '',
                industry_unit.completed,
                industry_unit.schematic or '',
                industry_unit.maintain,
              })
            end
          end

          if #items > 1 then
            entries = array_merge(entries, items)
          end
        end

        -- Create pagination
        local pages = {}
        local page_size = 204
        local current_page = 0
        local current_page_size = page_size
        for entry in task.iterate(entries) do
          if current_page_size == page_size then
            current_page = current_page + 1
            current_page_size = 0
            pages[current_page] = {}
          end
          current_page_size = current_page_size + 1
          
          table.insert(pages[current_page], entry)
        end
      
        for screen, page_number in task.iterate(screens) do
          local industry_for_page = {}
      
          screen.setRenderScript(
            table.concat({
              ("data = require('json').decode('%s')"):format(json.encode(pages[page_number] or {})),
              library.embedFile('render.lua'),
            }, '\n')
          )
          screen.activate()
        end
      end)
    end
  end

  -- This runs only after first status update
  local is_first_update = true
  local function first_update()
    if not is_first_update then
      return
    end
    is_first_update = false
    Task(function(task)
      local errors = {}

      local missing_schematics = {}
      local is_missing_schematics = false
      for industry_unit in task.iterate(industry) do
        if industry_unit.state_code == 7 then
          is_missing_schematics = true
          missing_schematics[industry_unit.schematic] = true
        end
      end

      -- Adds missing schematics
      if is_missing_schematics then
        local err = {'Missing Schematics:'}
        for _, schematic in task.iterate(missing_schematics) do
          table.insert(err, ' - ' .. schematic)
        end
        table.insert(errors, err)
      end
      
      -- Renders errors
      if #errors > 0 then
        for error in task.iterate(errors) do
          system.print('')
          
          if 'string' == type(error) then
            system.print(error)
          else
            for line in task.iterate(error) do
              system.print(line)
            end
          end
        end
      else
        system.print('No errors have been found!')
      end
      system.print('')
      system.print('Commands:')
      system.print(' - find [code]: sets waypoint to industry unit with matching code')
    end)
  end

  -- Main update loop
  local task_update = nil
  local function update()
    if (not task_update) or task_update.completed() then
      task_update = Task(function(task)
        -- Updates industry information
        for industry_unit, industry_number in task.iterate(industry) do
          local info = core.getElementIndustryInfoById(industry_unit.id)

          -- Produced item information
          local main_product = info.currentProducts[1]
          local main_product_item = nil
          if main_product then
            main_product_item = getItem(main_product.id)
          end
          local itemName = (main_product_item and main_product_item.displayName) or ''
          local itemSize = (main_product_item and main_product_item.size) or ''
          industry[industry_number].item = ('%s %s'):format(itemName, itemSize:upper())

          -- Schematic information
          local schematic = nil
          if #info.requiredSchematicIds > 0 then
            schematic = getItem(info.requiredSchematicIds[1]).displayName
          end
          industry[industry_number].schematic = schematic

          -- Basic informations
          industry[industry_number].state = industry_states[info.state]
          industry[industry_number].state_code = info.state

          -- Single batch has been completed?
          local is_completed = false
          if industry[industry_number].state_code == 1 and info and info.unitsProduced > 0 and info.batchesRemaining < 1 then
            is_completed = true
          end
          industry[industry_number].completed = (is_completed and info.unitsProduced) or false

          -- Maintain: off, X amount, forever
          industry[industry_number].maintain = false
          if info.maintainProductAmount > 0 then
            industry[industry_number].maintain = info.maintainProductAmount
          elseif 1 ~= industry[industry_number].state_code and info.unitsProduced > 0 and info.batchesRemaining < 0 then
            industry[industry_number].maintain = true
          end
        end
      end).next(render).next(first_update)
    end
  end

  -- Setup our refresh loop
  unit:onEvent('onTimer', update)
  unit.setTimer('refresh', 5)
  update()

  -- Setup command
  system:onEvent('onInputText', function(_, text)
    local parsed = split(text)
    local command = parsed[1]

    if 'find' == command then
      local id = parsed[2]
      local industry_unit = industry[id]

      if industry_unit then
        local pos = vec3(core.getElementPositionById(industry_unit.id))
        set_waypoint(
          local_to_world(pos)
        )
        system.print('Set waypoint to requested industry unit!')
      else
        system.print('Industry unit not found!')
      end
    end
  end)
end)