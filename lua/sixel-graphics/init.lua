---@class SixelGraphics
---@field has_setup boolean
---@field state table|nil
local M = { has_setup = false, state = nil }

---@private
local function guard_setup()
  if not M.has_setup then
    error("sixel-graphics.nvim is not set up. Call require('sixel-graphics').setup() first.")
  end
end

---Setup sixel-graphics.nvim with optional configuration.
---
---```lua
---require("sixel-graphics").setup({
---  max_width = 80,
---  scale = 1.0,
---})
---```
---
---@param opts Config?
function M.setup(opts)
  require("sixel-graphics.config").setup(opts)

  -- Initialize shared state
  M.state = {
    images = {},
    enabled = require("sixel-graphics.config").options.enabled,
    term_size = require("sixel-graphics.utils.term").get_size(),
    options = require("sixel-graphics.config").options,
  }

  -- Initialize backend
  require("sixel-graphics.backends.sixel").setup(M.state)

  local _group = vim.api.nvim_create_augroup("SixelGraphics", { clear = true })

  -- TODO: autocommands in Steps 5-6

  M.has_setup = true
end

---Check whether the current terminal supports sixel.
---Delegates to the sixel backend for detection logic.
---@return boolean
function M.is_sixel_supported()
  return require("sixel-graphics.backends.sixel").is_sixel_supported()
end

---Send a hardcoded 4-color sixel test pattern for visual verification.
---@deprecated Use render_image_at_cursor instead
---@param x? number  Terminal column (0-indexed)
---@param y? number  Terminal row (0-indexed)
function M.send_test_sixel(x, y)
  require("sixel-graphics.backends.sixel").send_test_sixel(x, y)
end

---Send the test pattern at the current Neovim cursor position.
---@deprecated Use render_image_at_cursor instead
function M.send_test_sixel_at_cursor()
  require("sixel-graphics.backends.sixel").send_test_sixel_at_cursor()
end

---Check if ImageMagick is available for image processing.
---@return boolean
function M.magick_is_available()
  return require("sixel-graphics.processors.magick_cli").is_available()
end

---Get the format of an image file.
---@param path string
---@return string|nil
function M.get_image_format(path)
  return require("sixel-graphics.processors.magick_cli").get_format(path)
end

---Get the pixel dimensions of an image file.
---@param path string
---@return { width: number, height: number }?
function M.get_image_dimensions(path)
  return require("sixel-graphics.processors.magick_cli").get_dimensions(path)
end

---Parse the current markdown buffer and return all image references.
---Each match includes the source range and the raw URL/path.
---
---Usage:
---```lua
---:lua vim.print(require("sixel-graphics").query_markdown_images())
---```
---
---@param buf? number  Buffer handle (default: current buffer)
---@return MarkdownImageMatch[]
function M.query_markdown_images(buf)
  return require("sixel-graphics.integrations.markdown").query_buffer_images(buf)
end

---Resolve an image path found in a markdown file to an absolute filesystem path.
---
---Usage:
---```lua
---:lua print(require("sixel-graphics").resolve_image_path(
---  vim.api.nvim_buf_get_name(0), "./images/cat.png"))
---```
---
---@param buffer_file_path string  Absolute path to the markdown file
---@param image_path string         Image URL as written in the markdown
---@return string  Absolute path to the resolved image
function M.resolve_image_path(buffer_file_path, image_path)
  return require("sixel-graphics.utils.path").resolve_image_path(buffer_file_path, image_path)
end

---Render an image at the current cursor position with a given width in cells.
---Height is derived from the image's aspect ratio.
---@param path string
---@param width_cells? number  Width in character cells (default 40)
---@return boolean  True if rendered successfully
function M.render_image_at_cursor(path, width_cells)
  width_cells = width_cells or 40

  guard_setup()

  if not M.state.enabled then
    vim.notify("sixel-graphics: rendering is disabled. Call enable() or setup().", vim.log.levels.WARN)
    return false
  end

  local proc = require("sixel-graphics.processors.magick_cli")
  local backend = require("sixel-graphics.backends.sixel")
  local term = require("sixel-graphics.utils.term").get_size()
  if not term then
    vim.notify("sixel-graphics: cannot determine terminal cell size", vim.log.levels.ERROR)
    return false
  end

  -- Get image natural dimensions
  local dims = proc.get_dimensions(path)
  if not dims then
    return false
  end

  -- Calculate height to preserve aspect ratio
  local aspect = dims.height / dims.width
  local pixel_h = math.floor(width_cells * term.cell_width * aspect + 0.5)
  local height_cells = pixel_h / term.cell_height

  local cursor = vim.api.nvim_win_get_cursor(0)
  local id = backend.render(path, cursor[2], cursor[1] - 1, width_cells, height_cells)
  if id then
    vim.notify("Rendered: " .. id, vim.log.levels.INFO)
    return true
  end
  return false
end

---Clear all rendered images from tracking state.
---Sixel images persist on screen until terminal redraw (Ctrl-L, scroll, etc.).
function M.clear_images()
  guard_setup()
  require("sixel-graphics.backends.sixel").clear()
  vim.notify("Images cleared", vim.log.levels.INFO)
end

---Accessor for the current config options.
---Returns a reference to the active options table (modifications may be
---lost on next setup() call).
---@return Config
function M.config()
  return require("sixel-graphics.config").options
end

---Check whether image rendering is currently enabled.
---@return boolean
function M.is_enabled()
  return not not (M.has_setup and M.state and M.state.enabled == true)
end

---Enable image rendering (show images).
---Re-renders all currently tracked images.
function M.enable()
  guard_setup()
  M.state.enabled = true
  -- Re-render all tracked images
  for _, img in pairs(M.state.images) do
    if img.is_rendered then
      require("sixel-graphics.backends.sixel").render(img.path, img.x, img.y, img.width, img.height)
    end
  end
  vim.notify("sixel-graphics: enabled", vim.log.levels.INFO)
end

---Disable image rendering (hide images).
---Images persist on screen until terminal redraw (Ctrl-L, scroll).
function M.disable()
  guard_setup()
  M.state.enabled = false
  vim.notify("sixel-graphics: disabled", vim.log.levels.INFO)
end

----------------------------------------------------------------------
-- Phase 6.1: Floating window terminal positioning
----------------------------------------------------------------------

---@private
---Compute the absolute terminal (col, row) for a floating window's content area.
---The content area is the region inside the border where we want sixels to appear.
---Accounts for border thickness and tabline visibility.
---@param win number  Window handle
---@return number col  0-indexed terminal column of content area top-left
---@return number row  0-indexed terminal row of content area top-left
local function floating_win_term_origin(win)
  -- nvim_win_get_position returns {row, col} as a single array
  local pos = vim.api.nvim_win_get_position(win)
  local screen_row = pos[1]
  local screen_col = pos[2]

  -- Account for border: position includes border.
  -- Content area is offset inward by border thickness.
  local config = vim.api.nvim_win_get_config(win)
  if config.border and config.border ~= "none" then
    screen_row = screen_row + 1 -- top border
    screen_col = screen_col + 1 -- left border
  end

  -- Account for tabline if visible above the editing area
  local showtab = vim.o.showtabline
  if showtab == 2 or (showtab == 1 and #vim.api.nvim_list_tabpages() > 1) then
    screen_row = screen_row + 1
  end

  return screen_col, screen_row
end

---Create a floating window at cursor and render a hardcoded sixel test pattern
---inside it. Phase 6.1 verification: proves sixel can render at the correct
---terminal position within a floating window.
---
---Usage:
---```vim
---:lua require("sixel-graphics").show_test_popup()
---```
---
---@return number|nil win  Floating window handle
---@return number|nil buf  Buffer handle
function M.show_test_popup()
  guard_setup()

  if not M.state.enabled then
    vim.notify("sixel-graphics: rendering is disabled", vim.log.levels.WARN)
    return nil, nil
  end

  -- 1. Create floating window below cursor
  local buf = vim.api.nvim_create_buf(false, true)
  local width = 20
  local height = 10

  local win = vim.api.nvim_open_win(buf, false, {
    relative = "cursor",
    row = 1, -- appear below cursor
    col = 0, -- same column as cursor
    width = width,
    height = height,
    style = "minimal",
    border = "single",
  })

  -- 2. Compute terminal coordinates for the content area
  local term_col, term_row = floating_win_term_origin(win)

  -- 3. Send hardcoded test sixel at computed position
  require("sixel-graphics.backends.sixel").send_test_sixel(term_col, term_row)

  local debug_pos = vim.api.nvim_win_get_position(win)
  vim.notify(
    string.format(
      "sixel-graphics: test popup at term (%d,%d), screen (%d,%d)",
      term_col,
      term_row,
      debug_pos[2], -- screen col
      debug_pos[1] -- screen row
    ),
    vim.log.levels.INFO
  )

  return win, buf
end

----------------------------------------------------------------------
-- Phase 6.2: Render real image inside floating window
----------------------------------------------------------------------

---Maximum fraction of the screen a popup may occupy (height and width).
local MAX_POPUP_SCREEN_FRACTION = 0.5

---Show an image in a floating popup window at the cursor position.
---The window is sized to fit the image while preserving aspect ratio,
---constrained to at most ~50% of screen dimensions and config limits.
---
---Uses the lower-level encode→sixel pipeline directly (not backend.render())
---because the popup pre-computes its own dimensions with scale/constraints —
---backend.render() would double-apply config transforms.
---
---Usage:
---```vim
---:lua require("sixel-graphics").show_image_popup("test-plasma.png")
---```
---
---@param image_path string  Absolute path to the image file
---@return number|nil win    Floating window handle, nil on failure
---@return string|nil image_id  Image id for tracking/cleanup
function M.show_image_popup(image_path)
  guard_setup()

  if not M.state.enabled then
    vim.notify("sixel-graphics: rendering is disabled", vim.log.levels.WARN)
    return nil, nil
  end

  local proc = require("sixel-graphics.processors.magick_cli")
  local backend = require("sixel-graphics.backends.sixel")
  local term = require("sixel-graphics.utils.term").get_size()
  if not term then
    return nil, nil
  end

  -- 1. Get image natural dimensions
  local dims = proc.get_dimensions(image_path)
  if not dims then
    vim.notify("sixel-graphics: cannot read image dimensions from " .. image_path, vim.log.levels.ERROR)
    return nil, nil
  end

  -- 2. Compute popup size in cells (apply scale, constrain to screen and config)
  local opts = M.state.options or {}
  local scale = opts.scale or 1.0

  local natural_w = math.max(1, math.floor(dims.width / term.cell_width * scale + 0.5))
  local natural_h = math.max(1, math.floor(dims.height / term.cell_height * scale + 0.5))

  -- Max dimensions: smaller of screen-fraction cap and user-configured max
  local max_w = math.floor(term.screen_cols * MAX_POPUP_SCREEN_FRACTION)
  local max_h = math.floor(term.screen_rows * MAX_POPUP_SCREEN_FRACTION)
  if opts.max_width then
    max_w = math.min(max_w, opts.max_width)
  end
  if opts.max_height then
    max_h = math.min(max_h, opts.max_height)
  end

  -- Fit within bounds, preserving aspect ratio
  local pw, ph = natural_w, natural_h
  if pw > max_w then
    ph = math.floor(ph * max_w / pw + 0.5)
    pw = max_w
  end
  if ph > max_h then
    pw = math.floor(pw * max_h / ph + 0.5)
    ph = max_h
  end

  -- Minimum size so the window + border is visible
  pw = math.max(pw, 5)
  ph = math.max(ph, 3)

  -- 3. Create floating window at cursor
  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, false, {
    relative = "cursor",
    row = 1,
    col = 0,
    width = pw,
    height = ph,
    style = "minimal",
    border = "single",
  })

  -- 4. Compute terminal coordinates for content area
  local term_col, term_row = floating_win_term_origin(win)

  -- 5. Convert cell dimensions → pixels, apply sixel density compensation
  local sps = opts.sixel_pixel_scale or 1.0
  local pixel_w = math.floor(pw * term.cell_width * sps + 0.5)
  local pixel_h = math.floor(ph * term.cell_height * sps + 0.5)

  -- 6. Track in state for cleanup (do this before the async send)
  local image_id = image_path .. "@popup-" .. tostring(win)
  M.state.images[image_id] = {
    id = image_id,
    path = image_path,
    x = term_col,
    y = term_row,
    width = pw,
    height = ph,
    is_rendered = true,
  }

  vim.notify(
    string.format(
      "sixel-graphics: popup %dx%d cells (%dx%d px), original %dx%d px",
      pw,
      ph,
      pixel_w,
      pixel_h,
      dims.width,
      dims.height
    ),
    vim.log.levels.INFO
  )

  -- 7. Encode + send after floating window is painted.
  --    vim.schedule: runs in next event-loop iteration after Neovim
  --    processes the window creation and flushes its redraw to stdout.
  --    vim.defer_fn(16): waits one frame (~16ms at 60Hz) for the
  --    terminal to actually render the window before we send sixel
  --    to stderr (which would otherwise race ahead and render first).
  vim.schedule(function()
    if not vim.api.nvim_win_is_valid(win) then
      return
    end

    local sixel_data = proc.encode_to_sixel(image_path, pixel_w, pixel_h)
    if not sixel_data then
      vim.notify("sixel-graphics: encode_to_sixel failed for " .. image_path, vim.log.levels.ERROR)
      return
    end

    vim.defer_fn(function()
      if not vim.api.nvim_win_is_valid(win) then
        return
      end
      backend.send_sixel(sixel_data, term_col, term_row)
    end, opts.popup_render_delay_ms or 16)
  end)

  return win, image_id
end

----------------------------------------------------------------------
-- Phase 6.3: Cursor tracking + hover detection
----------------------------------------------------------------------

---Check if the cursor is currently on a line with a markdown image.
---Prints the image URL to :messages. For manual verification.
function M.check_cursor_on_image()
  guard_setup()

  local buf = vim.api.nvim_get_current_buf()
  local ft = vim.bo[buf].filetype
  if ft ~= "markdown" then
    vim.notify("sixel-graphics: not a markdown buffer", vim.log.levels.INFO)
    return
  end

  local match = require("sixel-graphics.integrations.markdown").find_image_at_row(buf)
  if match then
    vim.notify("sixel-graphics: image found: " .. match.url, vim.log.levels.INFO)
  else
    vim.notify("sixel-graphics: no image on this line", vim.log.levels.INFO)
  end
end

---Enable debug CursorMoved logging for hover detection verification.
---Logs to :messages whenever the cursor lands on a markdown image line.
---Call stop_hover_debug() to disable.
function M.start_hover_debug()
  guard_setup()

  local group = vim.api.nvim_create_augroup("SixelGraphicsHoverDebug", { clear = true })

  vim.api.nvim_create_autocmd({ "CursorMoved" }, {
    group = group,
    callback = function(args)
      local ft = vim.bo[args.buf].filetype
      if ft ~= "markdown" then
        return
      end

      local match = require("sixel-graphics.integrations.markdown").find_image_at_row(args.buf)
      if match then
        vim.notify("[hover] " .. match.url, vim.log.levels.INFO)
      end
    end,
  })

  vim.notify("sixel-graphics: hover debug enabled (CursorMoved logging)", vim.log.levels.INFO)
end

---Disable the debug CursorMoved logging.
function M.stop_hover_debug()
  pcall(vim.api.nvim_del_augroup_by_name, "SixelGraphicsHoverDebug")
  vim.notify("sixel-graphics: hover debug disabled", vim.log.levels.INFO)
end

return M
