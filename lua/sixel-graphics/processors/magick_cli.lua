---ImageMagick CLI processor: auto-detection and basic image operations.
---All operations use synchronous vim.fn.system() for simplicity during development.
---Async vim.loop.spawn() pipeline comes in later steps.
---@class MagickCliProcessor
local M = {}

----------------------------------------------------------------------
-- Phase 2.1: ImageMagick auto-detection
----------------------------------------------------------------------

-- Version 7: single "magick" binary for all operations
-- Version 6: separate "convert" and "identify" binaries
local has_magick = vim.fn.executable("magick") == 1
local has_convert = vim.fn.executable("convert") == 1
local has_identify = vim.fn.executable("identify") == 1

-- Determine which commands to use (v7 preferred over v6)
-- For encoding (sixel, resize, etc.): magick or convert
-- For inspection (format, dimensions): magick identify or identify

---Check whether any usable ImageMagick installation is available.
---Returns true if either v7 (magick) or v6 (convert + identify) is found.
---@return boolean
function M.is_available()
  return has_magick or (has_convert and has_identify)
end

---Check which ImageMagick version was detected.
---@return string|nil  "v7" if magick found, "v6" if convert+identify found, nil if none
function M.version()
  if has_magick then
    return "v7"
  elseif has_convert and has_identify then
    return "v6"
  end
  return nil
end

---Check if magick (v7) is available.
---@return boolean
function M.has_v7()
  return has_magick
end

---Check if convert + identify (v6) are available.
---@return boolean
function M.has_v6()
  return has_convert and has_identify
end

----------------------------------------------------------------------
-- Phase 2.2: get_format
----------------------------------------------------------------------

---Returns the image format as a lowercase string: "png", "jpeg", "gif", etc.
---Uses identify -format %m (v6) or magick identify -format %m (v7).
---@param path string  Absolute or relative path to image file
---@return string|nil  Format string (lowercase), or nil on failure
function M.get_format(path)
  if not has_magick and not has_identify then
    vim.notify("sixel-graphics: ImageMagick 'identify' command not found", vim.log.levels.WARN)
    return nil
  end
  if not path or path == "" then
    vim.notify("sixel-graphics: get_format called with empty path", vim.log.levels.WARN)
    return nil
  end
  if vim.fn.filereadable(path) == 0 then
    vim.notify("sixel-graphics: file not readable: " .. path, vim.log.levels.WARN)
    return nil
  end

  -- Build command (list form avoids shell injection)
  local cmd
  if has_magick then
    cmd = { "magick", "identify", "-format", "%m", path }
  else
    cmd = { "identify", "-format", "%m", path }
  end

  local output = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    local err = output:gsub("%s+$", "")
    vim.notify("sixel-graphics: identify failed for " .. path .. ": " .. err, vim.log.levels.WARN)
    return nil
  end

  -- Trim and lowercase
  local format = output:gsub("%s+$", ""):lower()
  if format == "" then
    return nil
  end
  return format
end

return M
