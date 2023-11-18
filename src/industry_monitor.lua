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

local version_string = '1.0.4'

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
    print('ERROR: Core Unit not connected!')
    return unit.exit()
  end

  -- Ensures at least one screen is linked
  if #screens == 0 then
    print('ERROR: No screen not connected!')
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

  -- Utility to merge objects
  local function object_merge(target, ...)
    local arrays = {...}
    for _, object in pairs(arrays) do
      for key, value in pairs(object) do
        target[key] = value
      end
    end
    return target
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
    local name = item
    local size = ''
    if 'table' == type(item) then
      name = item.displayName
      size = item.size or ''
    end

    return ('%s %s'):format(
      name
        -- Abbreviates some names
        :gsub('Atmospheric', 'Atmo.')
        :gsub('Expanded', 'Exp.')
        :gsub('Uncommon', 'Unc.')
        :gsub('Advanced', 'Adv.'),
      size:upper()
    )
      -- Trims empty spaces at end of name
      :gsub('^%s+', '')
      :gsub('%s+$', '')
  end

  -- Gets items by id with caching
  local item_cache = {}
  local function get_item(id)
    if not item_cache[id] then
      item_cache[id] = system.getItem(id)
    end
    return item_cache[id]
  end

  -- Gets the main recipe of something
  local function get_main_recipe(task, id)
    local recipes = system.getRecipes(id)

    local largest_recipe = { 0, nil }
    for recipe in task.iterate(recipes) do
      for product in task.iterate(recipe.products) do
        if product.id == id then
          if product.quantity > largest_recipe[1] then
            largest_recipe = { product.quantity, recipe }
          end
        end
      end
    end

    return largest_recipe[2]
  end

  -- Gets industry base information
  local industry_ids = {}
  local industry_numbers = {}
  local function get_industry_information(task, local_id)
    -- If the industry unit does not exist, stop here
    if not industry_numbers[local_id] then
      return nil
    end

    -- Let's have a cache of industry info to speed-up bootstrap
    local item_id = core.getElementItemIdById(local_id)

    -- Let's extract current industry info
    local item = get_item(item_id)

    -- Gets custom industry unit name
    local industry_custom_name = core.getElementNameById(local_id)
    if industry_custom_name == ('%s [%d]'):format(item.displayNameWithSize, local_id) then
      industry_custom_name = nil
    end

    -- Let's get the industry group
    local group = nil
    for group_id, search in task.iterate(industry_group_search) do
      if nil ~= item.displayName:lower():find(search:lower()) and (search:lower() ~= 'refiner' or nil == item.displayName:lower():find('honeycomb')) then
        group = group_id
        break
      end
    end
    
    -- Returns final information
    return {
      id = local_id,
      num = industry_numbers[local_id],
      name = item.displayName,
      group_id = group,
      custom_name = industry_custom_name,
      is_transfer_unit = 'number' == type(item.displayName:lower():find('transfer unit')),
      tier = item.tier,
    }
  end

  -- Loads all present industry in construct
  local industry_count = 0
  local industry_range_last = 0
  local industry_total = 0
  local industry = {}
  local task_industry = Task(function(task)
    local ids = core.getElementIdList()
    table.sort(ids)

    local limit_reached = false
    for local_id in task.iterate(ids) do
      if 'Industry' == core.getElementClassById(local_id):sub(1, 8) then
        -- Generates a identifier
        industry_count = industry_count + 1
        industry_ids[industry_count] = local_id
        industry_numbers[local_id] = industry_count

        -- Only does extra processing inside our "processing window"
        if not limit_reached then
          -- Let's have a cache of industry info to speed-up bootstrap
          local item_id = core.getElementItemIdById(local_id)

          -- Let's extract current industry info
          local item = get_item(item_id)

          -- Counts up until limit_reached == true, this will determine our max number
          industry_range_last = industry_range_last + 1

          -- Fetches the unit's information
          local industry_data = get_industry_information(task, local_id)

          -- If we have a valid group, let's assign it
          if industry_data.group_id then
            if industry_count >= Range_Start and industry_tiers_allowed[item.tier] then
              industry_total = industry_total + 1 

              industry[industry_count] = industry_data
              table.insert(industry_groups[industry_data.group_id].items[item.tier], industry_data)
            end
          end

          -- Handles limit of industry across all screens
          if industry_count >= industry_max then
            limit_reached = true
          end
        end
      end
    end
  end)

  -- Gets industry status
  local function get_industry_unit_status(task, industry_number, industry_unit)
    -- Loads industry unit information (if none is provided)
    industry_unit = industry_unit or industry[industry_number] or get_industry_information(task, industry_ids[industry_number])

    -- Safety check
    if not industry_unit then
      return nil
    end

    local info = core.getElementIndustryInfoById(industry_unit.id)
    local industry_status = {}

    -- Produced item information
    local main_product = info.currentProducts[1]
    local main_product_item = nil
    if main_product then
      main_product_item = get_item(main_product.id)
    end
    local itemName = (main_product_item and item_name(main_product_item)) or 'No item selected'
    industry_status.item = itemName
    industry_status.item_id = (main_product_item and main_product_item.id) or nil

    -- I/O information
    local inputs = 0
    local outputs = 0
    local output_element_id = nil
    for plug in task.iterate(core.getElementInPlugsById(industry_unit.id)) do
      if plug.elementId then
        inputs = inputs + 1
      end
    end
    for plug in task.iterate(core.getElementOutPlugsById(industry_unit.id)) do
      if plug.elementId then
        outputs = outputs + 1
        output_element_id = plug.elementId
      end
    end

    -- For oxygen or hydrogen, override inputs to 1 so we don't see errors
    if itemName:lower() == 'pure hydrogen' or itemName:lower() == 'pure oxygen' then
      inputs = 1
    end

    industry_status.num_inputs = inputs
    industry_status.num_outputs = outputs

    -- Schematic information
    local schematic = nil
    if #info.requiredSchematicIds > 0 then
      schematic = get_item(info.requiredSchematicIds[1]).displayName
    end
    industry_status.schematic = schematic

    -- Basic informations
    industry_status.state = industry_states[info.state]
    industry_status.state_code = info.state
    industry_status.is_stuck = false

    -- Single batch has been completed?
    local is_completed = false
    if industry_status.state_code == 1 and info and info.batchesRequested > 0 and info.batchesRemaining < 1 then
      is_completed = true
    end
    industry_status.completed = (is_completed and info.unitsProduced) or false

    -- Maintain: off, X amount, forever
    industry_status.maintain = false
    if info.maintainProductAmount > 0 then
      industry_status.maintain = info.maintainProductAmount

      -- Handles special case when industry gets "stuck" on "pending"
      if info.state == 6 then
        -- Estimates how much mass there should be in that container
        local output_mass_empty = get_item(core.getElementItemIdById(output_element_id)).unitMass
        local output_mass_current = core.getElementMassById(output_element_id)
        local target_mass = output_mass_empty + (main_product_item.unitMass * info.maintainProductAmount) * 0.75

        -- Handles possibly stuck states
        if target_mass - output_mass_current > 0.0000001 then
          industry_status.is_stuck = true
        end
      end
    elseif 1 ~= industry_status.state_code and info.unitsProduced > 0 and info.batchesRemaining < 0 then
      industry_status.maintain = true
    end

    -- Single Batch
    industry_status.single_batch = false
    if false == industry_status.maintain and (1 ~= industry_status.state_code or industry_status.completed) then
      industry_status.single_batch = info.unitsProduced + math.max(info.batchesRemaining, 0)
    end

    -- Special state handling when no inputs or no outputs are provided
    if industry_status.is_stuck then
      industry_status.state_code = 5
    elseif outputs == 0 and industry_status.state_code ~= 5 then
      industry_status.state = 'No Linked Output'
      industry_status.state_code = 3
    elseif inputs == 0 then
      industry_status.state = 'No Linked Input'
      industry_status.state_code = 3
    end

    -- Creates a proper label string
    local label = ('%s: %s'):format(industry_status.state, industry_status.item)
    if industry_status.is_stuck then
      -- Batches completed
      label = ('Stuck: %s'):format(industry_status.state)
    elseif nil ~= industry_status.completed and false ~= industry_status.completed then
      -- Batches completed
      label = ('Ready: %dx %s'):format(industry_status.completed, industry_status.item)
    elseif industry_status.state_code == 7 then
      -- Missing schematic
      label = ('%s: %s'):format(industry_status.state, industry_status.schematic)
    elseif (industry_status.state_code == 4 or industry_status.state_code == 6) and 'number' == type(industry_status.maintain) then
      -- Maintain full, fixed amount
      label = ('Maintain: %dx %s'):format(industry_status.maintain, industry_status.item)
    elseif industry_status.state_code == 4 and true == industry_status.maintain then
      -- Maintain full, forever
      label = ('Maintain: %s'):format(industry_status.item)
    end
    industry_status.state_label = label

    return industry_status, industry_unit
  end

  -- Gets industry providing input materials
  local function get_industry_provider_ids(task, industry_number)
    local industry_unit = industry[industry_number] or get_industry_information(task, industry_ids[industry_number])

    -- Safety check
    if not industry_unit then
      return nil
    end

    -- Gets unit current status (for the schematic)
    local industry_status = get_industry_unit_status(task, industry_number)

    -- This is out output
    local industry_providers = {}
    local container_providers = {}

    -- Gets schematic information
    if industry_status.item_id then
      -- Fills in the ingredients
      for recipe in task.iterate(system.getRecipes(industry_status.item_id)) do
        if industry_unit.is_transfer_unit then
          for product in task.iterate(recipe.products) do
            industry_providers[product.id] = {}
          end
        else
          for ingredient in task.iterate(recipe.ingredients) do
            industry_providers[ingredient.id] = {}
          end
        end
      end

      -- Loops through each of the connected containers
      for plug_current_industry in task.iterate(core.getElementInPlugsById(industry_unit.id)) do
        if plug_current_industry.elementId then
          -- Saves the current container
          table.insert(container_providers, plug_current_industry.elementId)

          -- Loop through each of the inputs for each container
          for plug_container in task.iterate(core.getElementInPlugsById(plug_current_industry.elementId)) do
            -- Check if we have a valid industry connected
            if plug_container.elementId and industry_numbers[plug_container.elementId] then
              -- Pull the information from that industry unit
              local provider_unit = get_industry_information(task, plug_container.elementId)
              local provider_status = get_industry_unit_status(task, provider_unit.num)

              -- Maps the industry
              if provider_status.item_id and industry_providers[provider_status.item_id] then
                table.insert(industry_providers[provider_status.item_id], provider_unit.num)
              end
            end
          end
        end
      end
    end

    -- Clean-up
    for providers, ingredient_id in task.iterate(industry_providers) do
      if #providers == 0 then
        industry_providers[ingredient_id] = nil
      end
    end

    return industry_providers, container_providers
  end

  -- This function will be called when the above task gets completed, it will set-up update and rendering tasks, along with any commands
  task_industry.next(function()
    local industry_number_digits = string.len(industry_count)

    -- Setup text-mode
    local text_output = {}
    local is_activated_via_plug = unit.getSignalIn('in') == 1

    -- Main render loop
    local task_render = nil
    local function is_rendering()
      return task_render and not task_render.completed()
    end
    local function render()
      if not is_rendering() then
        task_render = Task(function(task)
          -- Detects text mode
          local is_text_mode = is_activated_via_plug and #text_output > 0

          -- Creates main listing, sorts by tier
          local entries = {}
          if is_text_mode then
            entries = text_output
          else
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
                  embed_json({
                    digits = industry_number_digits,
                    rows = pages[page_number] or {},
                    text_mode = is_text_mode,
                  }),
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
    
    -- Text-mode toggles
    local function print(...)
      local strings = {}
      for _, value in pairs({ ... }) do
        table.insert(strings, tostring(value))
      end

      if is_activated_via_plug then
        table.insert(text_output, table.concat(strings, ' '))

        if not is_rendering() then
          render()
        end
      else
        system.print(table.concat(strings, ' '))
      end
    end
    local function printf(fmt, ...)
      print(fmt:format(...))
    end

    -- When in text-mode, hijack the system.print so we can output to the screen
    if is_activated_via_plug then
      system.print = print
    end

    -- Setup commands
    local commands = {}

    function commands.about()
      print('')
      if is_activated_via_plug then
        printf('System version: v%s', version_string)
      end
      printf('Registered %d industry units out of %d max', industry_total, industry_max)
      printf('Showing range %d to %d, out of %d total units on construct', Range_Start, industry_range_last, industry_count)
      print('You can customize this range with the Range Start option')
    end

    function commands.help()
      print('')
      print('Commands:')
      print(' - help: prints list of commands')
      print(' - about: shows information about the script and current range')
      print(' - find [code]: sets waypoint to industry unit with matching code')
      print(' - info [code]: views information and status for an industry unit')
      print(' - trace [code]: runs complete error check on an industry unit')
      print(' - error_check: re-runs the error check above')

      if is_activated_via_plug then
        print(' - clear: clears text mode and goes back to industry view')
      end
    end

    function commands.find(industry_number)
      industry_number = tonumber(industry_number)
      local industry_unit = industry[industry_number]

      print('')
      if industry_unit then
        local pos = vec3(core.getElementPositionById(industry_unit.id))
          -- The position will always be on the bottom of the industry unit, so let's position it 0.5m into it to make it easier to find
          + vec3(core.getElementUpById(industry_unit.id)) * 0.5

        local wp = get_waypoint(local_to_world(pos))
        set_waypoint(wp)

        printf('Found industry unit #%d:', industry_number)
        printf(' - Element ID: %d', industry_unit.id)
        printf(' - Element Type: %s', core.getElementDisplayNameById(industry_unit.id))
        printf(' - Element Name: %s', industry_unit.custom_name or core.getElementNameById(industry_unit.id))
        printf(' - Position: %s', wp)
        print('Set waypoint to requested industry unit!')
      else
        print('Industry unit not found!')
      end
    end

    function commands.error_check()
      return Task(function(task)
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
            print('')
            
            if 'string' == type(error) then
              print(error)
            else
              for line in task.iterate(error) do
                print(line)
              end
            end
          end
        else
          print('')
          print('No errors have been found!')
        end
      end)
    end

    function commands.info(industry_number)
      Task(function(task)
        industry_number = tonumber(industry_number)
        
        local industry_status, industry_unit = get_industry_unit_status(task, industry_number)

        print('')
        if industry_status then
          printf('Status for industry #%d:', industry_number)
          printf(' - Element ID: %d', industry_unit.id)
          printf(' - Element Type: %s', core.getElementDisplayNameById(industry_unit.id))
          printf(' - Element Name: %s', industry_unit.custom_name or core.getElementNameById(industry_unit.id))

          -- Prints batch type
          if industry_status.maintain == true then
            print(' - Batch Type: Run Indefinitely')
          elseif 'number' == type(industry_status.maintain) then
            printf(' - Batch Type: Maintain', industry_status.maintain)
          elseif industry_status.single_batch then
            printf(' - Batch Type: Single Batch', industry_status.single_batch)
          end

          printf(' = %s', industry_status.state_label)
        else
          print('Industry unit not found!')
        end
      end)
    end

    function commands.trace(industry_number)
      Task(function(task)
        industry_number = tonumber(industry_number)

        local industry_status, industry_unit = get_industry_unit_status(task, industry_number)
        
        print('')
        if industry_status then
          printf('Checking industry for errors: #%d', industry_number)

          local function test_industry_status(industry_status)
            -- Test for some common status codes
            local code = industry_status.state_code
            if industry_status.is_stuck then
              return false, 'This industry unit seems stuck!'
            elseif code == 7 then
              return false, 'This industry unit is missing schematics!'
            elseif industry_status.num_inputs == 0 then
              return false, 'This industry unit is missing inputs!'
            elseif industry_status.num_outputs == 0 or code == 5 then
              return false, 'This industry unit is missing outputs!'
            elseif not industry_status.item_id then
              return false, 'This industry unit has no selected item!'
            elseif code == 1 then
              return false, 'This industry unit is stopped!'
            elseif code == 2 or industry_status.state_code == 4 or code == 6 then
              return true, 'This industry unit seems to be okay!'
            end

            -- Might require further investigation
            return nil
          end

          -- This function recurses into an unit's providers to find for errors
          local function find_upstream_issues(industry_unit, errors)
            local industry_status = get_industry_unit_status(task, industry_unit.num)
            local industry_providers, container_providers = get_industry_provider_ids(task, industry_unit.num)
            local provider_count = 0
            local ingredient_ids = {}
            for providers, ingredient_id in task.iterate(industry_providers) do
              -- Marks ingredient as present
              ingredient_ids[ingredient_id] = true

              for provider_id in task.iterate(providers) do
                provider_count = provider_count + 1

                local provider_status, provider_unit = get_industry_unit_status(task, provider_id)
                local result, message = test_industry_status(provider_status)
                
                -- Checks if something failed
                if not result then
                  if 'boolean' == type(result) then
                    -- Checks for easy fixes
                    table.insert(errors, ('%s [%d]: %s (makes %s)'):format(item_name(provider_unit.name), provider_unit.num, message, item_name(provider_status.item)))
                  else
                    -- We'll need to recurse further
                    find_upstream_issues(provider_unit, errors)
                  end
                end
              end
            end

            if provider_count == 0 and #container_providers == 0 then
              local industry_status = get_industry_unit_status(task, industry_unit.num)
              table.insert(errors, ('%s [%d]: has no providers (%s)'):format(item_name(industry_unit.name), industry_unit.num, industry_status.state_label))
            elseif industry_status.item_id ~= nil then
              local recipe = get_main_recipe(task, industry_status.item_id)
              for ingredient in task.iterate(recipe.ingredients) do
                if not ingredient_ids[ingredient.id] then
                  table.insert(errors, ('%s [%d]: missing ingredient (%s)'):format(item_name(industry_unit.name), industry_unit.num, item_name(get_item(ingredient.id))))
                end
              end
            end
          end

          -- Tests current industry
          local result, message = test_industry_status(industry_status)

          -- We have a simple fix
          if 'boolean' == type(result) then
            if result then
              return print(message)
            else
              print('Found issue with the industry unit:')
              printf(' - %s', message)
              return
            end
          end

          -- No simple fix, let's use recursion (this will happen when ingredients are missing)
          print('Industry unit has the following status:')
          printf(' - %s', industry_status.state_label)
          print('Checking upstream industry for clues...')
          local errors = {}
          find_upstream_issues(industry_unit, errors)

          -- Prints all errors
          if #errors > 0 then
            print('Found possible causes for the issue:')
            for error in task.iterate(errors) do
              printf(' - %s', error)
            end
          else
            print('Found no issues with upstream industry!')
          end
        else
          print('Industry unit not found!')
        end
      end)
    end

    function commands.clear(skip_render)
      text_output = {}

      if not skip_render then
        render()
      end
    end

    -- This runs only after first status update
    local is_first_update = true
    local function first_update()
      if not is_first_update or is_activated_via_plug then
        return
      end
      is_first_update = false

      commands.about()
      commands.error_check()
        .next(commands.help)
    end

    -- Main update loop
    local task_update = nil
    local function update()
      if (not task_update) or task_update.completed() then
        task_update = Task(function(task)
          -- Updates industry information
          for industry_unit, industry_number in task.iterate(industry) do
            object_merge(industry[industry_number], get_industry_unit_status(task, industry_number, industry_unit))
          end
        end).next(render).next(first_update)
      end
    end

    -- Setup our refresh loop
    unit:onEvent('onTimer', update)
    unit.setTimer('refresh', Refresh_Interval)
    update()

    -- Monitors chat for commands
    system:onEvent('onInputText', function(_, text)
      local parsed = split(text)
      local command = parsed[1]
      
      -- Parses arguments
      local arguments = {}
      for i = 2, #parsed do
        table.insert(arguments, parsed[i])
      end

      -- Invokes the command
      if 'function' == type(commands[command]) then
        -- Special handler for text mode
        if is_activated_via_plug then
          commands.clear(true)
          printf('> %s', text)
        end

        commands[command](table.unpack(arguments))
      end
    end)
  end)

  return {
    version = version_string,
  }
end

return IndustryMonitor