---@class SixelGraphics
---@field has_setup boolean
local M = { has_setup = false }

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

  local group = vim.api.nvim_create_augroup("SixelGraphics", { clear = true })

  -- TODO: add autocommands, keymaps, etc.

  M.has_setup = true
end

---Check whether the current terminal supports sixel.
---Delegates to the sixel backend for detection logic.
---@return boolean
function M.is_sixel_supported()
  return require("sixel-graphics.backends.sixel").is_sixel_supported()
end

---Send a hardcoded 4-color sixel test pattern for visual verification.
---@param x? number  Terminal column (0-indexed)
---@param y? number  Terminal row (0-indexed)
function M.send_test_sixel(x, y)
  require("sixel-graphics.backends.sixel").send_test_sixel(x, y)
end

---Send the test pattern at the current Neovim cursor position.
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

---Encode an image file to sixel and render at cursor.
---Convenience function for manual testing.
---@param path string
---@param width? number
---@param height? number
function M.render_image_at_cursor(path, width, height)
  local proc = require("sixel-graphics.processors.magick_cli")
  local backend = require("sixel-graphics.backends.sixel")
  local data = proc.encode_to_sixel(path, width, height)
  if not data then
    return false
  end
  local cursor = vim.api.nvim_win_get_cursor(0)
  backend.send_sixel(data, cursor[2], cursor[1] - 1)
  return true
end

return M
