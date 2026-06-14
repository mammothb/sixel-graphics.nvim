---Sixel backend: terminal capability detection and sixel output.
---@class SixelBackend
local M = {}

local logger = require("sixel-graphics.utils.logger")

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
    logger.warn("send_sixel: empty data, skipped")
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
      logger.debug(function()
        return string.format(
          "send_sixel: tmux pane_offset=(%d,%d), local=(%d,%d), outer=(%d,%d)",
          px,
          py,
          x,
          y,
          x + px,
          y + py
        )
      end)
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
  local using_tmux_wrap = M.is_tmux()
  if using_tmux_wrap then
    inner = tmux_wrap(inner)
  end

  -- Send via stderr (does not modify buffer contents)
  logger.debug(function()
    return string.format(
      "send_sixel: %d raw bytes → %d wrapped bytes, pos=(%d,%d), tmux_wrap=%s",
      #sixel_data,
      #inner,
      x or -1,
      y or -1,
      tostring(using_tmux_wrap)
    )
  end)
  vim.fn.chansend(vim.v.stderr, inner)
end

---Initialize the sixel backend with a shared state table.
---Called once by the plugin setup process.
---@param state table  Shared state: { images: table }
function M.setup(state)
  M.state = state

  logger.debug("sixel backend setup() called")

  -- Log terminal environment
  logger.debug(function()
    return string.format(
      "env: TERM=%s, TMUX=%s, TERM_PROGRAM=%s",
      vim.env.TERM or "nil",
      vim.env.TMUX and "set" or "nil",
      vim.env.TERM_PROGRAM or "nil"
    )
  end)

  -- Check tmux passthrough
  if M.is_tmux() then
    logger.info("detected tmux")
    local has_passthrough = M.tmux_has_passthrough()
    local has_sixel = M.tmux_has_sixel_feature()
    logger.debug(function()
      return string.format("tmux: passthrough=%s, sixel_feature=%s", tostring(has_passthrough), tostring(has_sixel))
    end)
    if not has_passthrough then
      logger.warn("tmux allow-passthrough is off — sixel output will not reach terminal")
      vim.notify(
        "sixel-graphics: running inside tmux but allow-passthrough is off. "
          .. "Enable it with: tmux set allow-passthrough on",
        vim.log.levels.ERROR
      )
    end
  end

  -- Validate ImageMagick
  if vim.fn.executable("magick") == 0 and vim.fn.executable("convert") == 0 then
    logger.error("ImageMagick not found (magick/convert missing)")
    vim.notify("sixel-graphics: ImageMagick not found. Install ImageMagick with sixel support.", vim.log.levels.ERROR)
  else
    logger.info(function()
      local ver = require("sixel-graphics.processors.magick_cli").version()
      return string.format("ImageMagick available: %s", ver or "unknown version")
    end)
  end

  logger.info("sixel backend initialized")
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
  logger.debug(function()
    return string.format(
      "render: path=%s cells=(%d,%d)@(%d,%d)",
      vim.fn.fnamemodify(image_path, ":t"),
      width_cells,
      height_cells,
      x,
      y
    )
  end)

  if not M.state then
    logger.error("render: backend state not initialized")
    vim.notify(
      "sixel-graphics: backend not set up. Call require('sixel-graphics').setup() first.",
      vim.log.levels.ERROR
    )
    return nil
  end

  local term_size = require("sixel-graphics.utils.term").get_size()
  if not term_size or not term_size.cell_width then
    logger.error("render: cannot determine terminal cell size")
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

  logger.debug(function()
    return string.format(
      "render: target px=(%d,%d), cell=(%.1f,%.1f), scale=%.2f, sps=%.2f",
      pixel_w,
      pixel_h,
      term_size.cell_width,
      term_size.cell_height,
      scale,
      sps
    )
  end)

  -- Encode via ImageMagick
  local proc = require("sixel-graphics.processors.magick_cli")
  local sixel_data = proc.encode_to_sixel(image_path, pixel_w, pixel_h)
  if not sixel_data then
    logger.error(function()
      return "render: encode_to_sixel failed for " .. vim.fn.fnamemodify(image_path, ":t")
    end)
    return nil
  end

  logger.debug(function()
    return string.format("render: encoded %d bytes of sixel data", #sixel_data)
  end)

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

  logger.info(function()
    return string.format("render: done id=%s", image_id)
  end)

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
    logger.debug(function()
      return string.format("clear: single image id=%s, existed=%s", image_id, tostring(M.state.images[image_id] ~= nil))
    end)
    local img = M.state.images[image_id]
    if img then
      img.is_rendered = false
      M.state.images[image_id] = nil
    end
  else
    local count = 0
    for _ in pairs(M.state.images) do
      count = count + 1
    end
    logger.debug(function()
      return string.format("clear: all images, count=%d", count)
    end)
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
