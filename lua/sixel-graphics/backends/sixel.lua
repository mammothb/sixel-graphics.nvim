---Sixel backend: terminal capability detection and sixel output.
---@class SixelBackend
local M = {}

---Check whether tmux reports the outer terminal as sixel-capable.
---Uses tmux's built-in feature detection (client_termfeatures).
---This is the most reliable check inside tmux — no hardcoded terminal lists.
---@return boolean
function M.tmux_has_sixel_feature()
  if vim.env.TMUX == nil then
    return false
  end
  local ok, result = pcall(vim.fn.system, { "tmux", "display", "-p", "#{client_termfeatures}" })
  if not ok or not result then
    return false
  end
  -- client_termfeatures is a comma-separated list, e.g. "clipboard,focus,sixel,title"
  return result:find("sixel", 1, true) ~= nil
end

---Check whether tmux passthrough is enabled.
---Required for sixel escape sequences to reach the outer terminal.
---@return boolean
function M.tmux_has_passthrough()
  if vim.env.TMUX == nil then
    return false
  end
  local ok, result = pcall(vim.fn.system, { "tmux", "show", "-Apv", "allow-passthrough" })
  if not ok or not result then
    return false
  end
  return result:find("^on") ~= nil or result:find("^all") ~= nil
end

---Check whether the current terminal supports sixel.
---Inside tmux: delegates to tmux's own terminal feature detection (client_termfeatures).
---Outside tmux: optimistic — the user chose the sixel backend, assume their terminal
---supports it. If it doesn't, sixel output fails silently (garbage or placeholder text).
---@return boolean
function M.is_sixel_supported()
  if vim.env.TMUX ~= nil then
    return M.tmux_has_sixel_feature() or M.tmux_has_passthrough()
  end
  -- Outside tmux: no reliable dynamic detection without terminal lists.
  -- The user explicitly chose sixel — trust their setup.
  return true
end

---Check whether running inside tmux.
---@return boolean
function M.is_tmux()
  return vim.env.TMUX ~= nil
end

return M
