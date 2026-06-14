---Sixel backend: terminal capability detection and sixel output.
---@class SixelBackend
local M = {}

-- Backend state (set during setup)
M.state = nil

---Check whether tmux reports the outer terminal as sixel-capable.
---Uses tmux's built-in feature detection (client_termfeatures).
---This is the most reliable check inside tmux — no hardcoded terminal lists.
---@return boolean
function M.tmux_has_sixel_feature()
  if vim.env.TMUX == nil then
    return false
  end
  local ok, result = pcall(vim.fn.system, { "tmux", "display", "-p", "#{client_termfeatures}" })
  if not ok or not result then
    return false
  end
  -- client_termfeatures is a comma-separated list, e.g. "clipboard,focus,sixel,title"
  return result:find("sixel", 1, true) ~= nil
end

---Check whether tmux passthrough is enabled.
---Required for sixel escape sequences to reach the outer terminal.
---@return boolean
function M.tmux_has_passthrough()
  if vim.env.TMUX == nil then
    return false
  end
  local ok, result = pcall(vim.fn.system, { "tmux", "show", "-Apv", "allow-passthrough" })
  if not ok or not result then
    return false
  end
  return result:find("^on") ~= nil or result:find("^all") ~= nil
end

---Check whether the current terminal supports sixel.
---Inside tmux: delegates to tmux's own terminal feature detection (client_termfeatures).
---Outside tmux: optimistic — the user chose the sixel backend, assume their terminal
---supports it. If it doesn't, sixel output fails silently (garbage or placeholder text).
---@return boolean
function M.is_sixel_supported()
  if vim.env.TMUX ~= nil then
    return M.tmux_has_sixel_feature() or M.tmux_has_passthrough()
  end
  -- Outside tmux: no reliable dynamic detection without terminal lists.
  -- The user explicitly chose sixel — trust their setup.
  return true
end

---Check whether running inside tmux.
---@return boolean
function M.is_tmux()
  return vim.env.TMUX ~= nil
end

---Get the tmux pane's offset (in character cells) within the outer terminal.
---Returns { 0, 0 } when not in tmux.
---@return number x  Left offset
---@return number y  Top offset
function M.get_tmux_pane_offset()
  if not M.is_tmux() then
    return 0, 0
  end
  local ok, result = pcall(vim.fn.system, { "tmux", "display-message", "-p", "#{pane_left} #{pane_top}" })
  if not ok or not result then
    return 0, 0
  end
  local left, top = result:match("(%d+)%s+(%d+)")
  return tonumber(left) or 0, tonumber(top) or 0
end

---Wrap a DCS sequence for tmux passthrough so the outer terminal receives it.
---Doubles all ESC bytes to prevent tmux from interpreting them.
---@param data string  Complete DCS sequence (including \eP intro and \e\\ terminator)
---@return string  Wrapped DCS ready to send through tmux
local function tmux_wrap(data)
  return "\27Ptmux;" .. data:gsub("\27", "\27\27") .. "\27\\"
end

---Ensure raw sixel data is wrapped in a DCS escape sequence.
---@param data string  Raw sixel bytes (may or may not have DCS/ST wrappers)
---@return string  Complete DCS sequence
local function ensure_dcs(data)
  if not data:match("^\27P") and not data:match("^\155") then
    data = "\27P0;1;0q" .. data
  end
  if not data:match("\27\\$") and not data:match("\156$") then
    data = data .. "\27\\"
  end
  return data
end

---Send sixel image data to the terminal via stderr.
---Handles DCS wrapping, tmux passthrough, cursor save/restore, and positioning.
---Inside tmux, the entire escape sequence (cursor ops + sixel) is wrapped
---in tmux passthrough so all of it targets the outer terminal.
---@param sixel_data string  Raw sixel bytes (with or without DCS/ST wrappers)
---@param x? number  Terminal column (0-indexed). If nil, renders at current cursor.
---@param y? number  Terminal row (0-indexed). If nil, renders at current cursor.
function M.send_sixel(sixel_data, x, y)
  if not sixel_data or #sixel_data == 0 then
    return
  end

  -- Wrap in DCS if needed
  local dcs = ensure_dcs(sixel_data)

  -- Build the inner escape sequence (SCP + position + sixel + RCP)
  local inner = "\27[s" -- save cursor position

  if x and y then
    -- Inside tmux: pane coordinates are relative; add pane offset
    -- so the outer terminal cursor lands at the correct position.
    if M.is_tmux() then
      local px, py = M.get_tmux_pane_offset()
      x = x + px
      y = y + py
    end
    -- CSI y;xH (cursor position, 1-indexed)
    inner = inner .. string.format("\27[%d;%dH", y + 1, x + 1)
  end

  inner = inner .. dcs
  inner = inner .. "\27[u" -- restore cursor position

  -- Inside tmux: wrap the entire inner sequence in passthrough
  -- so cursor positioning and sixel both target the outer terminal.
  if M.is_tmux() then
    inner = tmux_wrap(inner)
  end

  -- Send via stderr (does not modify buffer contents)
  vim.fn.chansend(vim.v.stderr, inner)
end

---Send a hardcoded 4-color sixel test pattern.
---10x10 sixels (~60x60 pixels): red, green, blue, yellow quadrants.
---Useful for visually verifying sixel output during development.
---@param x? number  Terminal column (0-indexed)
---@param y? number  Terminal row (0-indexed)
function M.send_test_sixel(x, y)
  -- 10x10 sixels = 10px wide × 60px tall (~3.5 char cells at 16px/cell)
  local row = "~~~~~~~~~~" -- 10 solid sixels = 10 pixels wide
  local test_image = '"1;1;10;10' -- sixel params: 10x10 aspect dots
    .. "#0;2;100;0;0" -- color 0: red   (RGB 100,0,0)
    .. "#1;2;0;100;0" -- color 1: green (RGB 0,100,0)
    .. "#2;2;0;0;100" -- color 2: blue  (RGB 0,0,100)
    .. "#3;2;100;100;0" -- color 3: yellow (RGB 100,100,0)
    -- Top half: red + green
    .. "#0"
    .. row
    .. "#1"
    .. row
    .. "$#0"
    .. row
    .. "#1"
    .. row
    .. "$#0"
    .. row
    .. "#1"
    .. row
    .. "$#0"
    .. row
    .. "#1"
    .. row
    .. "$#0"
    .. row
    .. "#1"
    .. row
    -- Bottom half: blue + yellow
    .. "$#2"
    .. row
    .. "#3"
    .. row
    .. "$#2"
    .. row
    .. "#3"
    .. row
    .. "$#2"
    .. row
    .. "#3"
    .. row
    .. "$#2"
    .. row
    .. "#3"
    .. row
    .. "$#2"
    .. row
    .. "#3"
    .. row

  M.send_sixel(test_image, x, y)
end

---Send the test pattern at the current Neovim cursor position.
---Converts Neovim's (1-indexed row, 0-indexed col) to terminal coordinates.
function M.send_test_sixel_at_cursor()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1 -- 1-indexed → 0-indexed
  local col = cursor[2]
  M.send_test_sixel(col, row)
end

---Initialize the sixel backend with a shared state table.
---Called once by the plugin setup process.
---@param state table  Shared state: { images: table }
function M.setup(state)
  M.state = state

  -- Validate ImageMagick
  if vim.fn.executable("magick") == 0 and vim.fn.executable("convert") == 0 then
    vim.notify("sixel-graphics: ImageMagick not found. Install ImageMagick with sixel support.", vim.log.levels.ERROR)
    return
  end

  -- Check tmux passthrough
  if M.is_tmux() and not M.tmux_has_passthrough() then
    vim.notify(
      "sixel-graphics: running inside tmux but allow-passthrough is off. "
        .. "Enable it with: tmux set allow-passthrough on",
      vim.log.levels.ERROR
    )
  end
end

---Render an image file at the given cell position and dimensions.
---Converts cell dimensions to pixels using terminal metrics,
---encodes to sixel via ImageMagick, and sends to the terminal.
---@param image_path string  Absolute path to image file
---@param x number           Terminal column (0-indexed) — top-left corner
---@param y number           Terminal row (0-indexed) — top-left corner
---@param width_cells number Width in character cells
---@param height_cells number Height in character cells
---@return string|nil image_id  Unique id if rendered successfully, nil on failure
function M.render(image_path, x, y, width_cells, height_cells)
  if not M.state then
    vim.notify(
      "sixel-graphics: backend not set up. Call require('sixel-graphics').setup() first.",
      vim.log.levels.ERROR
    )
    return nil
  end

  local term_size = require("sixel-graphics.utils.term").get_size()
  if not term_size or not term_size.cell_width then
    vim.notify("sixel-graphics: cannot determine terminal cell size", vim.log.levels.ERROR)
    return nil
  end

  -- Convert cell dimensions → pixel dimensions (apply sixel density compensation)
  local opts = M.state.options or {}
  local sps = opts.sixel_pixel_scale or 1.0
  local pixel_w = math.floor(width_cells * term_size.cell_width * sps + 0.5)
  local pixel_h = math.floor(height_cells * term_size.cell_height * sps + 0.5)

  -- Apply config: scale, max size (aspect-ratio-preserving), y_offset

  -- Scale (user preference, e.g. 0.5 = half size)
  local scale = opts.scale or 1.0
  if scale ~= 1.0 then
    pixel_w = math.floor(pixel_w * scale + 0.5)
    pixel_h = math.floor(pixel_h * scale + 0.5)
  end

  -- Max width constraint (cells → pixels, preserves aspect ratio)
  if opts.max_width then
    local max_w_px = math.floor(opts.max_width * term_size.cell_width + 0.5)
    if pixel_w > max_w_px then
      local ratio = max_w_px / pixel_w
      pixel_w = max_w_px
      pixel_h = math.floor(pixel_h * ratio + 0.5)
    end
  end

  -- Max height constraint (cells → pixels, preserves aspect ratio)
  if opts.max_height then
    local max_h_px = math.floor(opts.max_height * term_size.cell_height + 0.5)
    if pixel_h > max_h_px then
      local ratio = max_h_px / pixel_h
      pixel_h = max_h_px
      pixel_w = math.floor(pixel_w * ratio + 0.5)
    end
  end

  -- Vertical offset (rows below the logical position)
  y = y + (opts.y_offset or 0)

  -- Encode via ImageMagick
  local proc = require("sixel-graphics.processors.magick_cli")
  local sixel_data = proc.encode_to_sixel(image_path, pixel_w, pixel_h)
  if not sixel_data then
    return nil
  end

  -- Send to terminal
  M.send_sixel(sixel_data, x, y)

  -- Track image in state
  local image_id = image_path .. "@" .. tostring(x) .. "," .. tostring(y)
  M.state.images[image_id] = {
    id = image_id,
    path = image_path,
    x = x,
    y = y,
    width = width_cells,
    height = height_cells,
    is_rendered = true,
  }

  return image_id
end

---Clear rendered images from the terminal.
---Sixel images persist on screen until overwritten by terminal redraw
---(scroll, mode change, Ctrl-L). Clearing removes them from tracking state.
---@param image_id? string  Specific image to clear, or nil to clear all
function M.clear(image_id)
  if not M.state then
    return
  end

  if image_id then
    local img = M.state.images[image_id]
    if img then
      img.is_rendered = false
      M.state.images[image_id] = nil
    end
  else
    -- Clear all
    for _, img in pairs(M.state.images) do
      img.is_rendered = false
    end
    M.state.images = {}
  end
end

-- Exported for unit testing
M._ensure_dcs = ensure_dcs
M._tmux_wrap = tmux_wrap

return M
