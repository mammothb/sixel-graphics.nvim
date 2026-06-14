---@class ConfigManager
---@field defaults Config
---@field options Config
local M = {}

---@class Config
---@field enabled boolean
---@field max_width? integer|nil Maximum display width in cells (nil for no limit)
---@field max_height? integer|nil Maximum display height in cells (nil for no limit)
---@field scale? number Scale factor (default 1.0)
---@field y_offset? integer Default row offset for rendering
---@field cell_width_override? integer|nil
---@field cell_height_override? integer|nil
M.defaults = {
  enabled = true,
  max_width = nil,
  max_height = nil,
  scale = 1.0,
  y_offset = 0,
  cell_width_override = nil, -- force cell width in pixels (overrides TIOCGWINSZ)
  cell_height_override = nil, -- force cell height in pixels (overrides TIOCGWINSZ)
  sixel_pixel_scale = 1.0, -- compensate for terminal sixel density vs text cell density
  -- set to 0.625 for Windows Terminal HiDPI, 1.0 for most others
  popup_render_delay_ms = 16, -- delay after window creation before sending sixel
  -- one frame at 60Hz; increase if image renders behind window
  debug = {
    enabled = false,
    level = "info", -- "debug"|"info"|"warn"|"error"
    file_path = nil, -- e.g. "/tmp/sixel-debug.log"
  },
  hover = {
    enabled = true, -- automatically show images on hover in markdown
    debounce_ms = 150, -- delay before showing popup after cursor settles
    max_screen_fraction = 0.5, -- max fraction of screen the popup may occupy
    filetypes = { "markdown" }, -- filetypes to enable hover in
  },
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
