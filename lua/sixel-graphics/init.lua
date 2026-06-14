---@class SixelGraphics
---@field state table|nil
local M = { state = nil }

---@private
local function guard_setup()
  if not M.state then
    error("sixel-graphics.nvim is not initialized. Call require('sixel-graphics')._init() or setup() first.")
  end
end

-- Forward declarations: used in setup() before their definitions below
local on_cursor_moved
local close_active_popup
local active_popup

---Override default configuration.
---Pure config merge — no side effects beyond updating the options table.
---Safe to call before or after initialization. If called before _init(),
---the merged config will be used when initialization runs.
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

  -- If already initialized, update state.options in-place so live
  -- references (autocommand callbacks, etc.) pick up new config.
  if M.state then
    M.state.options = require("sixel-graphics.config").options
  end

  -- Auto-initialize on first setup() call (plugin/ entry point also
  -- calls _init() directly; idempotent guard prevents double-init).
  M._init()
end

---@private
---Initialize plugin state, backend, and autocommands.
---Idempotent: safe to call multiple times (second call is a no-op).
---Called automatically by setup() and by plugin/sixel-graphics.lua.
function M._init()
  if M._initialized then
    return
  end

  local logger = require("sixel-graphics.utils.logger")

  -- Log config (redact file_path for privacy)
  logger.info(function()
    local config = require("sixel-graphics.config").options
    local safe = vim.deepcopy(config)
    if safe.debug and safe.debug.file_path then
      safe.debug.file_path = "<set>"
    end
    return string.format("_init() with config: %s", vim.inspect(safe))
  end)

  -- Initialize shared state
  M.state = {
    images = {},
    enabled = require("sixel-graphics.config").options.enabled,
    term_size = require("sixel-graphics.utils.term").get_size(),
    options = require("sixel-graphics.config").options,
  }

  logger.info(function()
    return string.format(
      "state: enabled=%s, term_size=%dx%d cells",
      tostring(M.state.enabled),
      M.state.term_size and M.state.term_size.screen_cols or -1,
      M.state.term_size and M.state.term_size.screen_rows or -1
    )
  end)

  -- Initialize backend
  require("sixel-graphics.backends.sixel").setup(M.state)

  -- Hover autocommands: show images on cursor hover in markdown buffers
  local hover_opts = M.state.options.hover
  if hover_opts then
    local group = vim.api.nvim_create_augroup("SixelGraphicsHover", { clear = true })

    vim.api.nvim_create_autocmd({ "CursorMoved" }, {
      group = group,
      callback = function(args)
        if not M.state.enabled then
          return
        end
        on_cursor_moved(args.buf)
      end,
    })

    -- Close popup when leaving a markdown buffer
    vim.api.nvim_create_autocmd({ "BufLeave" }, {
      group = group,
      callback = function(args)
        local ft = vim.bo[args.buf].filetype
        local supported = hover_opts.filetypes or { "markdown" }
        if vim.tbl_contains(supported, ft) then
          close_active_popup()
        end
      end,
    })

    -- Clean up if floating window is closed externally (e.g. :q)
    vim.api.nvim_create_autocmd({ "WinClosed" }, {
      group = group,
      callback = function(args)
        if active_popup and active_popup.win == tonumber(args.file) then
          if active_popup.image_id then
            require("sixel-graphics.backends.sixel").clear(active_popup.image_id)
          end
          active_popup = nil
        end
      end,
    })

    -- Close popup when entering insert/visual mode (popup covers text being edited)
    vim.api.nvim_create_autocmd({ "ModeChanged" }, {
      group = group,
      pattern = "*:i,*:v,*:V,*:\22",
      callback = function()
        close_active_popup()
      end,
    })
  end

  M._initialized = true
end

---Check whether the current terminal supports sixel.
---Delegates to the sixel backend for detection logic.
---@return boolean
function M.is_sixel_supported()
  return require("sixel-graphics.backends.sixel").is_sixel_supported()
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

---Parse the current markdown buffer and return all mermaid diagram
---fenced code blocks. Each match includes the renderer_id, source
---code, and source range.
---
---Usage:
---```lua
---:lua vim.print(require("sixel-graphics").query_markdown_diagrams())
---```
---
---@param buf? number  Buffer handle (default: current buffer)
---@return DiagramMatch[]
function M.query_markdown_diagrams(buf)
  return require("sixel-graphics.integrations.markdown").query_buffer_diagrams(buf)
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
    require("sixel-graphics.utils.logger").debug("Rendered: " .. id)
    return true
  end
  return false
end

---Clear all rendered images from tracking state.
---Sixel images persist on screen until terminal redraw (Ctrl-L, scroll, etc.).
function M.clear_images()
  guard_setup()
  require("sixel-graphics.backends.sixel").clear()
  require("sixel-graphics.utils.logger").debug("Images cleared")
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
  return not not (M.state and M.state.enabled == true)
end

---Enable image rendering (show images).
function M.enable()
  guard_setup()
  M.state.enabled = true
  require("sixel-graphics.utils.logger").debug("sixel-graphics: enabled")
end

---Disable image rendering (hide images).
---Closes active popup and suppresses future hover rendering.
function M.disable()
  guard_setup()
  M.state.enabled = false
  close_active_popup()
  require("sixel-graphics.utils.logger").debug("sixel-graphics: disabled")
end

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
function M.show_image_popup(image_path, popup_opts)
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

  -- Get image natural dimensions
  local dims = proc.get_dimensions(image_path)
  if not dims then
    vim.notify("sixel-graphics: cannot read image dimensions from " .. image_path, vim.log.levels.ERROR)
    return nil, nil
  end

  -- Compute popup size in cells (apply scale, constrain to screen and config)
  local opts = M.state.options or {}
  local scale = opts.scale or 1.0

  local natural_w = math.max(1, math.floor(dims.width / term.cell_width * scale + 0.5))
  local natural_h = math.max(1, math.floor(dims.height / term.cell_height * scale + 0.5))

  -- Max dimensions: smaller of screen-fraction cap and user-configured max
  local max_screen_frac = (opts.hover or {}).max_screen_fraction or 0.5
  local max_w = math.floor(term.screen_cols * max_screen_frac)
  local max_h = math.floor(term.screen_rows * max_screen_frac)
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

  -- Enforce minimum popup width (diagrams auto-size to content, can be tiny).
  -- Clamped to max_w so the minimum cannot exceed screen/configured bounds.
  if popup_opts and popup_opts.min_width_cells then
    local min_w = math.min(popup_opts.min_width_cells, max_w)
    if pw < min_w then
      ph = math.floor(ph * min_w / pw + 0.5)
      pw = min_w
    end
  end

  -- Minimum size so the window + border is visible
  pw = math.max(pw, 5)
  ph = math.max(ph, 3)

  -- Create floating window at cursor
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

  -- Compute terminal coordinates for content area
  local term_col, term_row = floating_win_term_origin(win)

  -- Convert cell dimensions → pixels, apply sixel density compensation
  local sps = opts.sixel_pixel_scale or 1.0
  local pixel_w = math.floor(pw * term.cell_width * sps + 0.5)
  local pixel_h = math.floor(ph * term.cell_height * sps + 0.5)

  -- Track in state for cleanup
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

  require("sixel-graphics.utils.logger").debug(function()
    return string.format(
      "sixel-graphics: popup %dx%d cells (%dx%d px), original %dx%d px",
      pw,
      ph,
      pixel_w,
      pixel_h,
      dims.width,
      dims.height
    )
  end)

  -- Encode + send after floating window is painted.
  -- vim.schedule: runs in next event-loop iteration after Neovim
  -- processes the window creation and flushes its redraw to stdout.
  -- vim.defer_fn(16): waits one frame (~16ms at 60Hz) for the
  -- terminal to actually render the window before we send sixel
  -- to stderr (which would otherwise race ahead and render first).
  vim.schedule(function()
    if not vim.api.nvim_win_is_valid(win) then
      return
    end

    require("sixel-graphics.utils.logger").debug(function()
      return string.format("show_image_popup: encoding %s → %dx%d px", image_path, pixel_w, pixel_h)
    end)

    local sixel_data = proc.encode_to_sixel(image_path, pixel_w, pixel_h)
    if not sixel_data then
      return
    end

    require("sixel-graphics.utils.logger").debug(function()
      return string.format("show_image_popup: encode done, %d bytes", #sixel_data)
    end)

    vim.defer_fn(function()
      if not vim.api.nvim_win_is_valid(win) then
        return
      end
      require("sixel-graphics.utils.logger").debug("show_image_popup: sending sixel to stderr")
      backend.send_sixel(sixel_data, term_col, term_row)
    end, opts.popup_render_delay_ms or 16)
  end)

  return win, image_id
end

-- Active popup state (single-popup: only one hover popup at a time)
active_popup = nil -- { win: number, buf: number, image_id: string, path: string, source?: string }

-- mmdc job currently rendering (nil if idle). Tracked separately from
-- active_popup because during async rendering there is no popup yet —
-- the popup only appears when mmdc completes. This field lets us
-- detect "cursor moved away during loading" and silently discard
-- the stale result (it's cached on disk; next hover is instant).
local active_diagram_job_id = nil

local popup_timer = nil -- vim.fn.timer_start handle for debounce
local popup_in_progress = false -- guard against re-entrant create/destroy

-- Tracks the cursor row from the previous on_cursor_moved invocation.
-- When the cursor lands on the same row as an already-active popup,
-- we skip the entire dispatch (image/diagram check + debounce) to
-- avoid unnecessary work on every CursorMoved event within the same line.
local prev_cursor_row = -1

---@private
---Close the active hover popup (if any) and clear its sixel image.
close_active_popup = function()
  -- Cancel any pending mmdc job (result will be cached, silently ignored).
  -- Must happen before the active_popup nil guard so stale jobs are
  -- cleaned up even when cursor moves during mmdc loading (no popup yet).
  active_diagram_job_id = nil

  if not active_popup then
    return
  end

  require("sixel-graphics.utils.logger").debug("close_active_popup")

  popup_in_progress = true

  -- Clear the image from backend tracking
  if active_popup.image_id then
    require("sixel-graphics.backends.sixel").clear(active_popup.image_id)
  end

  -- Close the floating window (triggers Neovim redraw → clears sixel from screen)
  if active_popup.win and vim.api.nvim_win_is_valid(active_popup.win) then
    vim.api.nvim_win_close(active_popup.win, true)
  end

  active_popup = nil

  -- Close triggers Neovim autocmds (BufEnter on the newly-focused
  -- window, WinClosed for the popup). If on_cursor_moved fires from
  -- those autocmds before popup_in_progress is cleared, it could
  -- re-create the popup immediately. Defer the reset past the current
  -- event-loop tick so those cascading autocmds see the guard.
  vim.defer_fn(function()
    popup_in_progress = false
  end, 50)
end

---@private
---Create and show a hover popup for the resolved image path.
---@param image_path string  Absolute path to the image file
---@return boolean  True if popup was created
local function create_popup_for_image(image_path)
  local logger = require("sixel-graphics.utils.logger")
  logger.debug(function()
    return "create_popup_for_image: " .. image_path
  end)

  if popup_in_progress then
    logger.debug("create_popup_for_image: blocked")
    return false
  end

  -- Close any existing popup first (enforce single-popup)
  close_active_popup()

  -- Show the image in a floating window
  local win, image_id = M.show_image_popup(image_path)
  if not win then
    logger.debug("create_popup_for_image: show_image_popup returned nil")
    return false
  end

  active_popup = {
    win = win,
    buf = vim.api.nvim_win_get_buf(win),
    image_id = image_id,
    path = image_path,
  }

  logger.debug("create_popup_for_image: done")
  return true
end

---Render a mermaid diagram and show it in a floating popup.
---Uses the configured renderer (mmdr or mmdc) to produce a PNG,
---then delegates to show_image_popup() for display.
---
---mmdr path: synchronous vim.fn.system() (~2-6ms). Returns
---  immediately with the popup visible.
---
---mmdc path: asynchronous vim.fn.jobstart() (~1-5s). Returns
---  immediately after spawning the job; the popup appears later
---  via an on_complete callback when mmdc finishes.
---
---@param source string        Diagram source code
---@param renderer_opts table  renderer_options.mermaid from config
---@return boolean  True if popup was created (or async job started)
function M.create_popup_for_diagram(source, renderer_opts)
  guard_setup()

  local logger = require("sixel-graphics.utils.logger")
  logger.debug(function()
    return "create_popup_for_diagram: " .. source:gsub("\n", "\\n"):sub(1, 80)
  end)

  if popup_in_progress then
    logger.debug("create_popup_for_diagram: blocked")
    return false
  end

  -- Close any existing popup first (enforce single-popup)
  -- Do this before rendering so stale popup doesn't linger during mmdc delay
  close_active_popup()

  local renderer_name = renderer_opts and renderer_opts.renderer or "mmdr"
  local mermaid = require("sixel-graphics.renderers.mermaid")
  local popup_opts = renderer_opts
      and renderer_opts.min_popup_width
      and { min_width_cells = renderer_opts.min_popup_width }
    or nil

  -- ── mmdc path ────────────────────────────────────────────────

  if renderer_name == "mmdc" then
    active_diagram_job_id = nil -- clear any stale job

    -- mmdc has two return shapes:
    --   cache hit:  { file_path }          ← sync, no callback consumed
    --   cache miss: { job_id }              ← async, callback was consumed
    local result = mermaid.render(source, renderer_opts, function(path, err)
      vim.schedule(function()
        if active_diagram_job_id == nil then
          -- Popup was closed while loading (cursor moved away).
          -- Job result is cached on disk; next hover will be instant.
          logger.debug("create_popup_for_diagram: mmdc complete but stale (popup closed)")
          return
        end
        active_diagram_job_id = nil

        if err then
          vim.notify("sixel-graphics: diagram render failed: " .. err, vim.log.levels.ERROR)
          return
        end

        -- Close any popup that appeared in the meantime
        close_active_popup()

        local win, image_id = M.show_image_popup(path, popup_opts)
        if win then
          active_popup = {
            win = win,
            buf = vim.api.nvim_win_get_buf(win),
            image_id = image_id,
            path = path,
            source = source,
          }
          logger.debug("create_popup_for_diagram: mmdc async complete")
        end
      end)
    end)

    if not result then
      -- Renderer not installed or spawn failed (already notified by mermaid module)
      logger.debug("create_popup_for_diagram: mmdc render failed to start")
      return false
    end

    -- Cache hit: synchronous return with file_path
    if result.file_path then
      logger.debug("create_popup_for_diagram: mmdc cache hit")

      local win, image_id = M.show_image_popup(result.file_path, popup_opts)
      if not win then
        logger.debug("create_popup_for_diagram: show_image_popup returned nil")
        return false
      end

      active_popup = {
        win = win,
        buf = vim.api.nvim_win_get_buf(win),
        image_id = image_id,
        path = result.file_path,
        source = source,
      }

      logger.debug("create_popup_for_diagram: mmdc cache hit done")
      return true
    end

    -- Cache miss: async job started
    if result.job_id then
      vim.notify("sixel-graphics: rendering diagram...", vim.log.levels.INFO)
      active_diagram_job_id = result.job_id
      logger.debug("create_popup_for_diagram: mmdc async started (job_id=" .. result.job_id .. ")")
      return true
    end

    -- Malformed result (shouldn't happen)
    logger.debug("create_popup_for_diagram: mmdc result has neither file_path nor job_id")
    return false
  end

  -- ── mmdr sync path ────────────────────────────────────────────

  local result = mermaid.render(source, renderer_opts)

  if not result then
    -- mermaid.render already notified the user (renderer not installed / error)
    logger.debug("create_popup_for_diagram: mermaid.render returned nil")
    return false
  end

  if not result.file_path then
    logger.debug("create_popup_for_diagram: result has no file_path")
    return false
  end

  -- Show the rendered PNG in a floating window
  local win, image_id = M.show_image_popup(result.file_path, popup_opts)
  if not win then
    logger.debug("create_popup_for_diagram: show_image_popup returned nil")
    return false
  end

  active_popup = {
    win = win,
    buf = vim.api.nvim_win_get_buf(win),
    image_id = image_id,
    path = result.file_path,
    source = source,
  }

  logger.debug("create_popup_for_diagram: done")
  return true
end

---Render a mermaid diagram to PNG using the configured renderer.
---Convenience wrapper around the renderer module. Useful for
---keymaps and manual rendering.
---
---mmdr path: synchronous (~2-6ms), returns { file_path } immediately.
---mmdc path: requires on_complete callback for async result.
---
---Usage:
---```lua
---:lua local r = require("sixel-graphics").render_mermaid("flowchart LR; A-->B")
---:lua vim.print(r.file_path)
---```
---
---@param source string     Diagram source code
---@param opts? table        renderer_options.mermaid (default: from config)
---@param on_complete? fun(path: string|nil, err: string|nil)  mmdc async callback
---@return { file_path: string }?  Sync success (mmdr or mmdc cache hit)
---@return { job_id: number }?     Async started (mmdc cache miss)
---@return nil                     Error
function M.render_mermaid(source, opts, on_complete)
  opts = opts or require("sixel-graphics.config").options.renderer_options.mermaid
  return require("sixel-graphics.renderers.mermaid").render(source, opts, on_complete)
end

---@private
---Start a debounced popup timer. Cancels any pending timer first
---(caller already did this — defensive). On fire, clears popup_timer
---and runs callback inside vim.schedule for safe Neovim API access.
---@param delay_ms number
---@param label string      Log label ("image" or "diagram")
---@param callback function  Called inside vim.schedule when timer fires
local function schedule_popup(delay_ms, label, callback)
  require("sixel-graphics.utils.logger").debug(function()
    return "on_cursor_moved: " .. label .. " debounce " .. delay_ms .. "ms"
  end)
  popup_timer = vim.fn.timer_start(delay_ms, function()
    popup_timer = nil
    require("sixel-graphics.utils.logger").debug("on_cursor_moved: timer fired (" .. label .. ")")
    vim.schedule(callback)
  end)
end

---@private
---CursorMoved handler: detect if cursor is on an image reference or
---inside a mermaid diagram block, and create/close popup accordingly.
---Debounced to prevent flicker on rapid cursor movement.
---@param buf number  Buffer handle
on_cursor_moved = function(buf)
  -- Skip if a popup operation is already in progress (prevent re-entrancy
  -- from autocmds firing during window create/destroy).
  if popup_in_progress then
    return
  end

  -- Only show popups in normal mode. The ModeChanged autocmd closes
  -- any active popup when entering insert/visual; this guard prevents
  -- re-creation until returning to normal mode.
  if vim.fn.mode(true) ~= "n" then
    return
  end

  local ft = vim.bo[buf].filetype
  local hover = M.state.options.hover
  if not vim.tbl_contains(hover.filetypes, ft) then
    -- Cursor left a supported buffer: close any active popup
    close_active_popup()
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local cursor_row = cursor[1] - 1

  -- Same line as before with an active popup: nothing to do
  if cursor_row == prev_cursor_row and active_popup then
    return
  end
  prev_cursor_row = cursor_row

  -- Cancel any pending debounced popup
  if popup_timer then
    vim.fn.timer_stop(popup_timer)
    popup_timer = nil
  end

  -- ── IMAGE CHECK ────────────────────────────────────────────────

  if hover.images.enabled ~= false then
    local match = require("sixel-graphics.integrations.markdown").find_image_at_row(buf, cursor_row)

    if match then
      -- Resolve image path
      local buf_path = vim.api.nvim_buf_get_name(buf)
      if buf_path == "" then
        return -- untitled buffer, can't resolve relative paths
      end

      local abs_path = require("sixel-graphics.utils.path").resolve_image_path(buf_path, match.url)

      -- Check file exists
      if vim.fn.filereadable(abs_path) == 0 then
        return
      end

      -- If the same image is already showing, don't recreate
      if active_popup and active_popup.path == abs_path then
        return
      end

      -- Debounce: wait for cursor to settle before showing popup.
      -- Rapid cursor movement keeps cancelling the timer → no flicker.
      schedule_popup(hover.debounce_ms, "image", function()
        create_popup_for_image(abs_path)
      end)
      return
    end
  end

  -- ── DIAGRAM CHECK ─────────────────────────────────────────────

  if hover.diagrams.enabled ~= false then
    local diagram = require("sixel-graphics.integrations.markdown").find_diagram_at_row(buf, cursor_row)

    if diagram then
      -- If the same diagram is already showing, don't recreate
      if active_popup and active_popup.source == diagram.source then
        require("sixel-graphics.utils.logger").debug("on_cursor_moved: same diagram, skipping")
        return
      end

      local renderer_opts = M.state.options.renderer_options.mermaid
      schedule_popup(hover.debounce_ms, "diagram", function()
        M.create_popup_for_diagram(diagram.source, renderer_opts)
      end)
      return
    end
  end

  -- ── NEITHER ───────────────────────────────────────────────────

  -- Cursor on neither image nor diagram: close popup immediately
  close_active_popup()
end

---Close the active hover popup (if any).
---Public API — can be called manually or mapped to a key.
function M.close_popup()
  close_active_popup()
end

return M
