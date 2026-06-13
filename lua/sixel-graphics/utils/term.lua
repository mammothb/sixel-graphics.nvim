---Terminal cell size detection via TIOCGWINSZ ioctl (LuaJIT FFI).
---Provides pixel dimensions per character cell for cell↔pixel conversion.
---Result is cached; updates on VimResized.
---@class TermSize
local M = {}

local cached_size = nil

---Call TIOCGWINSZ ioctl to get terminal dimensions.
---Updates the cached_size table.
---@return table|nil
local update_size = function()
  local ffi = require("ffi")
  ffi.cdef([[
    typedef struct {
      unsigned short row;
      unsigned short col;
      unsigned short xpixel;
      unsigned short ypixel;
    } winsize;
    int ioctl(int, int, ...);
  ]])

  local TIOCGWINSZ
  if vim.fn.has("linux") == 1 then
    TIOCGWINSZ = 0x5413
  elseif vim.fn.has("mac") == 1 or vim.fn.has("bsd") == 1 then
    TIOCGWINSZ = 0x40087468
  else
    -- Unsupported OS: sensible defaults
    cached_size = {
      screen_cols = vim.o.columns,
      screen_rows = vim.o.lines,
      cell_width = 10,
      cell_height = 20,
    }
    return
  end

  local sz = ffi.new("winsize")
  if ffi.C.ioctl(1, TIOCGWINSZ, sz) ~= 0 then
    return -- non-terminal environment, keep previous
  end

  local xpixel = sz.xpixel
  local ypixel = sz.ypixel

  -- Fallback when pixel dimensions unavailable (SSH, some tty)
  -- Default: 8px wide × 16px tall per cell
  if xpixel == 0 or ypixel == 0 then
    xpixel = sz.col * 8
    ypixel = sz.row * 16
  end

  cached_size = {
    screen_x = xpixel,
    screen_y = ypixel,
    screen_cols = sz.col,
    screen_rows = sz.row,
    cell_width = xpixel / sz.col,
    cell_height = ypixel / sz.row,
  }
end

-- Compute once at module load, refresh on VimResized
update_size()
vim.api.nvim_create_autocmd("VimResized", { callback = update_size })

---Return the current terminal cell size.
---@return { cell_width: number, cell_height: number, screen_cols: number, screen_rows: number, screen_x?: number, screen_y?: number }|nil
function M.get_size()
  return cached_size
end

return M
