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
Stuck_After_X_Hours_Jammed = false --export: Marks units as potentially stuck after being jammed for X hours
Stuck_Detection_Hours = 36 --export: How many hours in jammed status until an unit is considered stuck

Range_Start = math.max(1, Range_Start)

Color_Default = { 0.10, 0.10, 0.10 } --export
Color_Stopped = { 0.15, 0.15, 0.15 } --export
Color_Pending = { 0.05, 0.15, 0.20 } --export
Color_Running = { 0.08, 0.20, 0.05 } --export
Color_Warning = { 1.00, 0.50, 0.00 } --export
Color_Error = { 1.00, 0.00, 0.00 } --export

local IndustryMonitor = require('industry_monitor')

-- Gets connected screens
local screens = library.getLinksByClass('Screen', true) ---@type table<number,Screen>

-- How many industry per page we have
local page_size = 204

-- The render script we'll be using
local render_script = library.embedFile('xl_render.lua')

-- Initializes the monitor
local monitor = IndustryMonitor(screens, page_size, render_script)
monitor.render_config.colors ={
  default = Color_Default,
  stopped = Color_Stopped,
  pending = Color_Pending,
  running = Color_Running,
  warning = Color_Warning,
  error = Color_Error,
},

system.print(('[ Wolfe Labs Industry Monitor XL v%s ]'):format(monitor.version))