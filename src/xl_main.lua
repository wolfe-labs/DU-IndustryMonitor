local IndustryMonitor = require('industry_monitor')

-- Gets connected screens
local screens = library.getLinksByClass('Screen', true) ---@type table<number,Screen>

-- How many industry per page we have
local page_size = 204

-- The render script we'll be using
local render_script = library.embedFile('xl_render.lua')

-- Initializes the monitor
local monitor = IndustryMonitor(screens, page_size, render_script)
system.print(('[ Wolfe Labs Industry Monitor XL v%s ]'):format(monitor.version))