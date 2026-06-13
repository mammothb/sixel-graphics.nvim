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

return M
