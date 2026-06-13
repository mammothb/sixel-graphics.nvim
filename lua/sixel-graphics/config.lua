---@class ConfigManager
---@field defaults Config
---@field options Config
local M = {}

---@class Config
---@field enabled boolean
---@field max_width integer|nil Maximum display width in cells (nil for no limit)
---@field max_height integer|nil Maximum display height in cells (nil for no limit)
---@field scale number Scale factor (default 1.0)
---@field y_offset integer Default row offset for rendering
M.defaults = {
  enabled = true,
  max_width = nil,
  max_height = nil,
  scale = 1.0,
  y_offset = 0,
  cell_width_override = nil,   -- force cell width in pixels (overrides TIOCGWINSZ)
  cell_height_override = nil,  -- force cell height in pixels (overrides TIOCGWINSZ)
}

---@param opts Config?
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})
end

return setmetatable(M, {
  __index = function(_, key)
    if rawget(M, "options") == nil then
      M.setup()
    end
    local options = rawget(M, "options")
    return options[key]
  end,
})
