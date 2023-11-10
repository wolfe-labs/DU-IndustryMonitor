local IndustryMonitor = require('industry_monitor')

-- Gets connected screens
local screens = library.getLinksByClass('Screen', true) ---@type table<number,Screen>

-- How many industry per page we have
local page_size = 204

-- The render script we'll be using
local render_script = library.embedFile('xl_render.lua')

-- Initializes the monitor
system.print('[ Wolfe Labs Industry Monitor XL v1.0 ]')
IndustryMonitor(screens, page_size, render_script)