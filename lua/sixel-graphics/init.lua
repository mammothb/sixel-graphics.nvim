---@class SixelGraphics
---@field has_setup boolean
---@field state table
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

  local group = vim.api.nvim_create_augroup("SixelGraphics", { clear = true })

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
---@return { width: number, height: number }|nil
function M.get_image_dimensions(path)
  return require("sixel-graphics.processors.magick_cli").get_dimensions(path)
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
  return M.has_setup and M.state and M.state.enabled == true
end

---Enable image rendering (show images).
---Re-renders all currently tracked images.
function M.enable()
  guard_setup()
  M.state.enabled = true
  -- Re-render all tracked images
  for _, img in pairs(M.state.images) do
    if img.is_rendered then
      require("sixel-graphics.backends.sixel").render(
        img.path, img.x, img.y, img.width, img.height
      )
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

return M
