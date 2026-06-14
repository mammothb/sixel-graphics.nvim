---Terminal cell size detection via TIOCGWINSZ ioctl (LuaJIT FFI) or
---pure-Lua 5.1 fallback using vim.o.columns/vim.o.lines + hardcoded
---cell pixel dimensions (10×20 px/cell).
---Result is cached; updates on VimResized.
---
---On non-LuaJIT Neovim builds, accurate cell pixel dimensions are
---not available. Users can set cell_width_override / cell_height_override
---in the plugin config to match their terminal's actual cell size.
---@class TermSize
local M = {}

local logger = require("sixel-graphics.utils.logger")

local cached_size = nil

-- Probe FFI availability once at module load.
-- LuaJIT builds have ffi; Lua 5.1 builds do not.
local has_ffi, ffi_mod = pcall(require, "ffi")

---Call TIOCGWINSZ ioctl to get terminal dimensions.
---Uses LuaJIT FFI when available; falls back to vim.o + hardcoded
---cell pixel dimensions on pure-Lua 5.1 builds.
---Updates the cached_size table.
local update_size

if has_ffi then
  -- ── FFI path (LuaJIT): ioctl(TIOCGWINSZ) ──────────────────────
  local ffi = ffi_mod

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
    TIOCGWINSZ = nil -- unsupported OS, fall through to defaults below
  end

  update_size = function()
    if not TIOCGWINSZ then
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
      logger.debug("update_size: ioctl TIOCGWINSZ failed (non-terminal?)")
      return -- non-terminal environment, keep previous
    end

    local xpixel = sz.xpixel
    local ypixel = sz.ypixel

    -- Fallback when pixel dimensions unavailable (SSH, some tty)
    -- Default: 8px wide × 16px tall per cell
    if xpixel == 0 or ypixel == 0 then
      logger.debug(function()
        return string.format(
          "update_size: pixel dimensions unavailable from ioctl (got %dx%d px), using fallback 8x16 per cell",
          xpixel,
          ypixel
        )
      end)
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

    logger.info(function()
      return string.format(
        "term size: %dx%d cells, %dx%d px, cell=%dx%d px",
        sz.col,
        sz.row,
        xpixel,
        ypixel,
        cached_size.cell_width,
        cached_size.cell_height
      )
    end)
  end
else
  -- ── Pure-Lua 5.1 path (no FFI): Neovim options + hardcoded cell px ──

  -- Default cell pixel dimensions: 10×20 px.
  -- Most terminals with a typical 12pt monospace font fall in the
  -- 8–10 px wide × 16–20 px tall range.  Users who need precise sizing
  -- can set cell_width_override / cell_height_override in the plugin config.
  local DEFAULT_CELL_W = 10
  local DEFAULT_CELL_H = 20

  update_size = function()
    cached_size = {
      screen_cols = vim.o.columns,
      screen_rows = vim.o.lines,
      cell_width = DEFAULT_CELL_W,
      cell_height = DEFAULT_CELL_H,
    }

    logger.info(function()
      return string.format(
        "term size (no FFI): %dx%d cells, cell=%dx%d px (default). Set cell_width_override / cell_height_override in config for accurate sizing.",
        cached_size.screen_cols,
        cached_size.screen_rows,
        cached_size.cell_width,
        cached_size.cell_height
      )
    end)
  end
end

-- Compute once at module load, refresh on VimResized
update_size()
vim.api.nvim_create_autocmd("VimResized", { callback = update_size })

---Return the effective cell size, respecting user overrides from config.
---Overrides only affect cell_width/cell_height; screen dimensions remain from TIOCGWINSZ.
---@return { cell_width: number, cell_height: number, screen_cols: number, screen_rows: number, screen_x?: number, screen_y?: number }|nil
function M.get_size()
  if not cached_size then
    return nil
  end

  local config = require("sixel-graphics.config")
  local cw = config.cell_width_override or cached_size.cell_width
  local ch = config.cell_height_override or cached_size.cell_height

  return {
    cell_width = cw,
    cell_height = ch,
    screen_cols = cached_size.screen_cols,
    screen_rows = cached_size.screen_rows,
    screen_x = cached_size.screen_x,
    screen_y = cached_size.screen_y,
  }
end

return M
