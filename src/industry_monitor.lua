-- Public options exposed to Dual Universe
Refresh_Interval = 5 --export: How often to refresh the screen, in seconds
Range_Start = 1 --export: Only starts displaying after a certain number of industry
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
Show_Tier_1 = true --export
Show_Tier_2 = true --export
Show_Tier_3 = true --export
Show_Tier_4 = true --export
Show_Industry_Name = false --export: Shows industry name instead of item name

Range_Start = math.max(1, Range_Start)

local json = require('json')
local Task = require('tasks')

local function embed_json(data)
  return ("data = require('json').decode('%s')")
    :format(
      json.encode(data)
        :gsub('\\', '\\\\')
        :gsub('\'', '\\\'')
    )
end

---@param screens table<number,Screen> The screens where everything is going to be rendered
---@param page_size number How many lines are supported per page by the render script
---@param ui_render_script string The render script
local function IndustryMonitor(screens, page_size, ui_render_script)
  -- Hide widget
  unit.hideWidget()

  -- Ensures a core is linked
  local core = library.getCoreUnit()
  if not core then
    system.print('ERROR: Core Unit not connected!')
    return unit.exit()
  end

  -- Ensures at least one screen is linked
  if #screens == 0 then
    system.print('ERROR: No screen not connected!')
    return unit.exit()
  end

  -- List of included tiers
  local industry_tiers_allowed = {
    [1] = Show_Tier_1,
    [2] = Show_Tier_2,
    [3] = Show_Tier_3,
    [4] = Show_Tier_4,
  }

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

  -- How many industry we can keep in memory
  local headers_max = 0
  for _ in pairs(industry_group_search) do
    headers_max = headers_max + 1
  end
  local industry_max = #screens * page_size - headers_max

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

  -- Utility to get a destination ::pos string
  local function get_waypoint(pos)
    return ('::pos{0,0,%.4f,%.4f,%.4f}'):format(pos.x, pos.y, pos.z)
  end

  -- Utility to set a destination
  local function set_waypoint(pos)
    system.setWaypoint(('string' == type(pos) and pos) or get_waypoint(pos))
  end

  -- Utility to split a command in spaces
  local function split(str)
    local tokens = {}
    for token in string.gmatch(str, "[^%s]+") do
      table.insert(tokens, token)
    end
    return tokens
  end

  -- Utility to print an item name
  local function item_name(item)
    return ('%s %s'):format(
      item.displayName
        :gsub('Atmospheric', 'Atmo.')
        :gsub('Expanded', 'Exp.')
        :gsub('Uncommon', 'Unc.')
        :gsub('Advanced', 'Adv.'),
      (item.size or ''):upper()
    )
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
  local industry_total = 0
  local industry = {}
  local task_industry = Task(function(task)
    local ids = core.getElementIdList()
    table.sort(ids)

    local limit_reached = false
    for local_id in task.iterate(ids) do
      if 'Industry' == core.getElementClassById(local_id):sub(1, 8) then
        -- Let's have a cache of industry info to speed-up bootstrap
        local item_id = core.getElementItemIdById(local_id)

        -- Let's extract current industry info
        local item = getItem(item_id)

        -- Generates a identifier
        industry_count = industry_count + 1

        -- Let's get the industry group
        for group_id, search in task.iterate(industry_group_search) do
          if nil ~= item.displayName:lower():find(search:lower()) and (search:lower() ~= 'refiner' or nil == item.displayName:lower():find('honeycomb')) then
            if industry_count >= Range_Start and industry_tiers_allowed[item.tier] then
              -- Handles limit of industry across all screens
              if industry_total >= industry_max then
                limit_reached = true
                break
              end
              industry_total = industry_total + 1 

              -- Gets custom industry unit name
              local industry_custom_name = core.getElementNameById(local_id)
              if industry_custom_name == ('%s [%d]'):format(item.displayNameWithSize, local_id) then
                industry_custom_name = nil
              end

              local industry_data = {
                id = local_id,
                num = industry_count,
                name = item.displayName,
                custom_name = industry_custom_name,
                tier = item.tier,
                state = 'Loading',
                state_code = 0,
                item = nil,
              }
              
              industry[industry_count] = industry_data
              table.insert(industry_groups[group_id].items[item.tier], industry_data)
            end
            break
          end
        end

        -- Stops processing after limit
        if limit_reached then
          break
        end
      end
    end
  end)

  -- This function will be called when the above task gets completed, it will set-up update and rendering tasks, along with any commands
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

                -- Should we show the industry unit name instead of the item?
                local display_name = industry_unit.item or ''
                if Show_Industry_Name and industry_unit.custom_name then
                  display_name = industry_unit.custom_name
                end

                table.insert(items, {
                  industry_unit.num,
                  industry_unit.tier,
                  is_running,
                  industry_unit.state_code,
                  industry_unit.state,
                  display_name,
                  industry_unit.completed,
                  industry_unit.schematic or '',
                  industry_unit.maintain,
                })
              end
            end

            -- If we have any items (other than the category heading) let's add it to the render queue
            if #items > 1 then
              entries = array_merge(entries, items)
            end
          end

          -- Create pagination
          local pages = {}
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
        
          -- Goes through each of the pages and renders their respective pages
          for screen, page_number in task.iterate(screens) do
            if pages[page_number] then
              screen.setRenderScript(
                table.concat({
                  embed_json(pages[page_number] or {}),
                  ui_render_script,
                }, '\n')
              )
              screen.activate()
            else
              screen.setRenderScript('')
              screen.deactivate()
            end
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

        local missing_inputs = {}
        local missing_outputs = {}
        local stuck = {}
        for industry_unit in task.iterate(industry) do
          if industry_unit.state_code == 7 then
            is_missing_schematics = true
            missing_schematics[industry_unit.schematic] = true
          end

          if industry_unit.num_inputs == 0 then
            table.insert(missing_inputs, industry_unit)
          end
          if industry_unit.num_outputs == 0 then
            table.insert(missing_outputs, industry_unit)
          end

          if industry_unit.is_stuck then
            table.insert(stuck, industry_unit)
          end
        end

        system.print(('Registered %d industry units out of %d max'):format(industry_total, industry_max))
        system.print(('Showing range %d to %d'):format(Range_Start, industry_count - 1))
        system.print('You can customize this range with the Range Start option')

        -- Adds missing schematics
        if is_missing_schematics then
          local err = {'Missing Schematics:'}
          for _, schematic in task.iterate(missing_schematics) do
            table.insert(err, ' - ' .. schematic)
          end
          table.insert(errors, err)
        end

        -- Adds missing inputs or outputs
        if #missing_inputs > 0 then
          local err = {'Inputs not connected:'}
          for industry_unit in task.iterate(missing_inputs) do
            table.insert(err, (' - [%d] %s'):format(industry_unit.num, industry_unit.name))
          end
          table.insert(errors, err)
        end
        if #missing_outputs > 0 then
          local err = {'Outputs not connected:'}
          for industry_unit in task.iterate(missing_outputs) do
            table.insert(err, (' - [%d] %s'):format(industry_unit.num, industry_unit.name))
          end
          table.insert(errors, err)
        end

        -- Adds stuck machines
        if #stuck > 0 then
          local err = {'Possibly stuck industry:'}
          for industry_unit in task.iterate(stuck) do
            table.insert(err, (' - [%d] %s'):format(industry_unit.num, industry_unit.name))
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
            local itemName = (main_product_item and item_name(main_product_item)) or 'No item selected'
            industry[industry_number].item = itemName

            -- I/O information
            local inputs = 0
            local outputs = 0
            local output_element_id = nil
            for plug in task.iterate(core.getElementInPlugsById(industry[industry_number].id)) do
              if plug.elementId then
                inputs = inputs + 1
              end
            end
            for plug in task.iterate(core.getElementOutPlugsById(industry[industry_number].id)) do
              if plug.elementId then
                outputs = outputs + 1
                output_element_id = plug.elementId
              end
            end

            -- For oxygen or hydrogen, override inputs to 1 so we don't see errors
            if itemName:lower():gmatch('pure hydrogen') or itemName:lower():gmatch('pure oxygen') then
              inputs = 1
            end

            industry[industry_number].num_inputs = inputs
            industry[industry_number].num_outputs = outputs

            -- Schematic information
            local schematic = nil
            if #info.requiredSchematicIds > 0 then
              schematic = getItem(info.requiredSchematicIds[1]).displayName
            end
            industry[industry_number].schematic = schematic

            -- Basic informations
            industry[industry_number].state = industry_states[info.state]
            industry[industry_number].state_code = info.state
            industry[industry_number].is_stuck = false

            -- Single batch has been completed?
            local is_completed = false
            if industry[industry_number].state_code == 1 and info and info.batchesRequested > 0 and info.batchesRemaining < 1 then
              is_completed = true
            end
            industry[industry_number].completed = (is_completed and info.unitsProduced) or false

            -- Maintain: off, X amount, forever
            industry[industry_number].maintain = false
            if info.maintainProductAmount > 0 then
              industry[industry_number].maintain = info.maintainProductAmount

              -- Handles special case when industry gets "stuck" on "pending"
              if info.state == 6 then
                -- Estimates how much mass there should be in that container
                local output_mass_empty = getItem(core.getElementItemIdById(output_element_id)).unitMass
                local output_mass_current = core.getElementMassById(output_element_id)
                local target_mass = (output_mass_empty + main_product_item.unitMass * info.maintainProductAmount) * 0.75

                -- Handles possibly stuck states
                if output_mass_current < target_mass then
                  industry[industry_number].is_stuck = true
                end
              end
            elseif 1 ~= industry[industry_number].state_code and info.unitsProduced > 0 and info.batchesRemaining < 0 then
              industry[industry_number].maintain = true
            end

            -- Special state handling when no inputs or no outputs are provided
            if industry[industry_number].is_stuck then
              industry[industry_number].state_code = 5
            elseif outputs == 0 and industry[industry_number].state_code ~= 5 then
              industry[industry_number].state = 'No Linked Output'
              industry[industry_number].state_code = 3
            elseif inputs == 0 then
              industry[industry_number].state = 'No Linked Input'
              industry[industry_number].state_code = 3
            end
          end
        end).next(render).next(first_update)
      end
    end

    -- Setup our refresh loop
    unit:onEvent('onTimer', update)
    unit.setTimer('refresh', Refresh_Interval)
    update()

    -- Setup command
    system:onEvent('onInputText', function(_, text)
      local parsed = split(text)
      local command = parsed[1]

      if 'find' == command then
        local id = tonumber(parsed[2])
        local industry_unit = industry[id]

        if industry_unit then
          local pos = vec3(core.getElementPositionById(industry_unit.id))
            -- The position will always be on the bottom of the industry unit, so let's position it 0.5m into it to make it easier to find
            + vec3(core.getElementUpById(industry_unit.id)) * 0.5

          local wp = get_waypoint(local_to_world(pos))
          set_waypoint(wp)

          system.print('')
          system.print(('Found industry unit #%d:'):format(id))
          system.print((' - Element ID: %d'):format(industry_unit.id))
          system.print((' - Element Type: %s'):format(core.getElementDisplayNameById(industry_unit.id)))
          system.print((' - Element Name: %s'):format(industry_unit.custom_name or core.getElementNameById(industry_unit.id)))
          system.print((' - Position: %s'):format(wp))
          system.print('Set waypoint to requested industry unit!')
        else
          system.print('Industry unit not found!')
        end
      end
    end)
  end)

  return {
    version = '1.0.3',
  }
end

return IndustryMonitor