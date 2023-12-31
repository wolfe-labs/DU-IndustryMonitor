local is_text_mode = data.text_mode == true

local margin = 8
local text_size = 10
local text_padding = 2
local line_size = text_size + text_padding

local font_number = loadFont('RobotoMono', text_size)
local font_name = loadFont('Oxanium-Medium', text_size)
local font_title = loadFont('BankGothic', text_size)

local title_color = { 1, 1, 1 }

local width, height = getResolution()
local columns = (is_text_mode and 1) or 4
local column_size = (width - margin) / columns
local column_items = math.floor(height / line_size)

local layers = {}
for i = 0, columns do
  layers[i] = createLayer()
  setLayerClipRect(layers[i], i * column_size, 0, column_size, height)
  setDefaultTextAlign(layers[i], AlignH_Left, AlignV_Top)
end

local tier_colors = {
  { 0.75, 0.75, 0.75 },
  { 0, 0.8, 0 },
  { 0, 0.6, 1 },
  { 0.8, 0, 0.8 },
  { 0.8, 0.6, 0 },
}

local state_colors = {
  [0] = data.config.colors.default or  { 0.10, 0.10, 0.10 }, -- Loading
  [1] = data.config.colors.stopped or { 0.15, 0.15, 0.15 }, -- Stopped
  [2] = data.config.colors.running or { 0.08, 0.20, 0.05 }, -- Running
  [3] = data.config.colors.warning or { 1.00, 0.50, 0.00 }, -- Missing ingredient
  [4] = data.config.colors.warning or { 1.00, 0.50, 0.00 }, -- Output full
  [5] = data.config.colors.error or { 1.00, 0.00, 0.00 }, -- No output
  [6] = data.config.colors.pending or { 0.05, 0.15, 0.20 }, -- Pending
  [7] = data.config.colors.error or { 1.00, 0.00, 0.00 }, -- Missing schematics
}

local function color(c, i, a)
  i = i or 1
  a = a or 1
  return c[1] * i, c[2] * i, c[3] * i, a
end

function pad(number, digits)
  return string.rep('0', digits - string.len(number)) .. number
end

function render(item, layer, x, y)
  if 'string' == type(item) then
    render_title(item, layer, x, y)
  else
    render_item(item, layer, x, y)
  end
end

function render_title(title, layer, x, y)
  if not is_text_mode then
    setNextStrokeColor(layer, color(title_color))
    setNextStrokeWidth(layer, 1)
    addLine(layer, x - text_padding, y + text_size, x + column_size, y + text_size)
  end

  setNextFillColor(layer, color(title_color))
  addText(layer, font_title, title, x + text_padding, y + text_padding / 2)
end

local number_digits = data.digits or 0
function render_item(item, layer, x, y)
  local num = pad(item[1], number_digits)
  local tier = item[2]
  local tier_color = tier_colors[tier + 1]
  local is_running = item[3]
  local state = item[4]
  local state_color = state_colors[state] or state_colors[1]
  local state_label = item[5]
  local item_label = item[6]
  local quantity_completed = item[7]
  local schematic = item[8]
  local maintain = item[9]
  local is_stuck = item[10]

  local label = ('%s: %s'):format(state_label, item_label)
  if is_stuck then
    -- Stuck
    state_color = { 1, 0, 0.5 }
  elseif nil ~= quantity_completed and false ~= quantity_completed then
    -- Batches completed
    state_color = { 0, 1, 0.75 }
    label = ('Ready: %dx %s'):format(quantity_completed, item_label)
  elseif state == 7 then
    -- Missing schematic
    label = ('%s: %s'):format(state_label, schematic)
  elseif (state == 4 or state == 6) and 'number' == type(maintain) then
    -- Maintain full, fixed amount
    state_color = state_colors[6]
    label = ('Maintain: %dx %s'):format(math.floor(maintain), item_label)
  elseif state == 4 and true == maintain then
    -- Maintain full, forever
    state_color = state_colors[6]
    label = ('Maintain: %s'):format(item_label)
  end

  local num_width = getTextBounds(font_number, num)
  
  setNextFillColor(layer, color(tier_color, 0.3))
  addText(layer, font_number, num, x, y)

  setNextFillColor(layer, color(state_color))
  addText(layer, font_name, label, x + num_width + text_padding, y)
end

-- Special settings for text mode
if is_text_mode then
  text_size = 14
  text_padding = 4
  line_size = text_size + text_padding
  
  font_title = loadFont('FiraMono', text_size)
  title_color = { 0.75, 0.75, 0.75 }
end

-- Main loop
for _, item in pairs(data.rows or {}) do
  local column = math.floor((_ - 1) / column_items)
  local row = (_ - 1) % column_items
  render(item, layers[column], margin / 2 + column * column_size, row * line_size)
end