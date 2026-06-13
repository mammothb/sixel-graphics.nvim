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

---Wrap a DCS sequence for tmux passthrough so the outer terminal receives it.
---Doubles all ESC bytes to prevent tmux from interpreting them.
---@param data string  Complete DCS sequence (including \eP intro and \e\\ terminator)
---@return string  Wrapped DCS ready to send through tmux
local function tmux_wrap(data)
  return "\27Ptmux;" .. data:gsub("\27", "\27\27") .. "\27\\"
end

---Ensure raw sixel data is wrapped in a DCS escape sequence.
---@param data string  Raw sixel bytes (may or may not have DCS/ST wrappers)
---@return string  Complete DCS sequence
local function ensure_dcs(data)
  if not data:match("^\27P") and not data:match("^\155") then
    data = "\27P0;1;0q" .. data
  end
  if not data:match("\27\\$") and not data:match("\156$") then
    data = data .. "\27\\"
  end
  return data
end

---Send sixel image data to the terminal via stderr.
---Handles DCS wrapping, tmux passthrough, cursor save/restore, and positioning.
---@param sixel_data string  Raw sixel bytes (with or without DCS/ST wrappers)
---@param x? number  Terminal column (0-indexed). If nil, renders at current cursor.
---@param y? number  Terminal row (0-indexed). If nil, renders at current cursor.
function M.send_sixel(sixel_data, x, y)
  if not sixel_data or #sixel_data == 0 then
    return
  end

  -- Wrap in DCS if needed
  local dcs = ensure_dcs(sixel_data)

  -- Wrap in tmux passthrough if needed
  if M.is_tmux() then
    dcs = tmux_wrap(dcs)
  end

  -- Build the full escape sequence
  local seq = "\27[s" -- save cursor position

  if x and y then
    -- CSI y;xH (cursor position, 1-indexed)
    seq = seq .. string.format("\27[%d;%dH", y + 1, x + 1)
  end

  seq = seq .. dcs
  seq = seq .. "\27[u" -- restore cursor position

  -- Send via stderr (does not modify buffer contents)
  vim.fn.chansend(vim.v.stderr, seq)
end

return M
