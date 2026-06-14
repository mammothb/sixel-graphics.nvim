---:checkhealth provider for sixel-graphics.nvim.
---
---Usage:
---  :checkhealth sixel-graphics

local M = {}

function M.check()
  vim.health.start("sixel-graphics")

  -- ── ImageMagick ──────────────────────────────────────────────

  local has_magick = vim.fn.executable("magick") == 1
  local has_convert = vim.fn.executable("convert") == 1
  local has_identify = vim.fn.executable("identify") == 1

  if has_magick then
    vim.health.ok("ImageMagick v7: magick found")
  elseif has_convert and has_identify then
    vim.health.ok("ImageMagick v6: convert + identify found")
  else
    local missing = {}
    if not has_magick then
      table.insert(missing, "magick")
    end
    if not has_convert then
      table.insert(missing, "convert")
    end
    if not has_identify then
      table.insert(missing, "identify")
    end
    vim.health.error(
      "ImageMagick not found (missing: " .. table.concat(missing, ", ") .. "). Install ImageMagick with sixel support."
    )
  end

  -- ── Mermaid renderers ────────────────────────────────────────

  if vim.fn.executable("mmdr") == 1 then
    vim.health.ok("mmdr found (recommended renderer)")
  else
    vim.health.warn("mmdr not found. Install: cargo install mermaid-rs-renderer")
  end

  if vim.fn.executable("mmdc") == 1 then
    vim.health.ok("mmdc found (alternative renderer)")
  else
    vim.health.info("mmdc not found. Optional: npm install -g @mermaid-js/mermaid-cli")
  end

  -- ── tmux ─────────────────────────────────────────────────────

  if vim.env.TMUX then
    vim.health.info("Running inside tmux")

    local pok, presult = pcall(vim.fn.system, { "tmux", "show", "-Apv", "allow-passthrough" })
    if pok and presult then
      local stripped = presult:gsub("%s+$", "")
      if stripped == "on" or stripped == "all" then
        vim.health.ok("tmux allow-passthrough is on")
      else
        vim.health.error(
          "tmux allow-passthrough is off (got: '" .. stripped .. "'). Run: tmux set allow-passthrough on"
        )
      end
    else
      vim.health.warn("Could not query tmux allow-passthrough setting")
    end

    local fok, fresult = pcall(vim.fn.system, { "tmux", "display", "-p", "#{client_termfeatures}" })
    if fok and fresult and fresult:find("sixel", 1, true) then
      vim.health.ok("tmux reports sixel terminal feature")
    elseif fok then
      vim.health.warn("tmux: outer terminal does not report sixel feature")
    end
  else
    vim.health.info("Not running inside tmux")
  end

  -- ── Config ───────────────────────────────────────────────────

  local gcfg = vim.g.sixel_graphics
  if type(gcfg) == "function" then
    gcfg = gcfg()
  end
  if type(gcfg) == "table" then
    local config = require("sixel-graphics.config")
    local unknown = config._find_unknown_keys(gcfg)
    if #unknown > 0 then
      vim.health.warn("Unknown config keys in vim.g.sixel_graphics: " .. table.concat(unknown, ", "))
    else
      vim.health.ok("vim.g.sixel_graphics config: no unknown keys")
    end
  end

  vim.health.ok("Plugin loaded")
end

return M
