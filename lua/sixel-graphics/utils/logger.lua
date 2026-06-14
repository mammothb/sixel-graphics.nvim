---File-based debug logger, configurable via setup().
---Reads config.debug on each write — no init step required.
---Log level thresholds (higher = more severe):
---  debug = 10, info = 20, warn = 30, error = 40
---Messages at or above the configured level are written.
---
---Config (in setup() call):
---```lua
---require("sixel-graphics").setup({
---  debug = {
---    enabled = true,
---    level = "debug",           -- "debug"|"info"|"warn"|"error"
---    file_path = "/tmp/sixel-debug.log",
---  },
---})
---```
---@class Logger
local M = {}

local levels = {
  debug = 10,
  info = 20,
  warn = 30,
  error = 40,
}

local start_time = nil

---Check whether the logger is active (enabled + file_path set in config).
---@return boolean
function M.is_enabled()
  local ok, config = pcall(require, "sixel-graphics.config")
  if not ok then
    return false
  end

  local debug_opts = config.debug or {}
  return debug_opts.enabled == true and debug_opts.file_path ~= nil
end

---Return elapsed time since first log call, in ms.
---@return string
local function elapsed()
  if not start_time then
    start_time = vim.loop.hrtime()
  end
  local ms = (vim.loop.hrtime() - start_time) / 1e6
  return string.format("+%d.%03dms", math.floor(ms), math.floor((ms % 1) * 1000))
end

---Write a message to the log file if the logger is active and
---the message level meets the configured threshold.
---@param level string  "debug"|"info"|"warn"|"error"
---@param message string|fun():string  Message or function that returns a message (lazy)
local function write(level, message)
  if not M.is_enabled() then
    return
  end

  local ok, config = pcall(require, "sixel-graphics.config")
  if not ok then
    return
  end

  local debug_opts = config.debug or {}
  local threshold = levels[debug_opts.level] or levels.info
  local msg_level = levels[level] or levels.debug

  if msg_level < threshold then
    return
  end

  -- Lazy message evaluation: accept functions to avoid work when disabled
  if type(message) == "function" then
    local ok2, result = pcall(message)
    if not ok2 then
      return
    end
    message = result
  end

  -- Ensure header is written (lazy init of start_time)
  local ts = elapsed()

  local file = io.open(debug_opts.file_path, "a")
  if not file then
    return
  end

  file:write(string.format("%s [%s] %s\n", ts, level, tostring(message)))
  file:close()
end

---Log a debug-level message (trace/diagnostic).
---@param message string|fun():string
function M.debug(message)
  write("debug", message)
end

---Log an info-level message (notable event).
---@param message string|fun():string
function M.info(message)
  write("info", message)
end

---Log a warning-level message (recoverable issue).
---@param message string|fun():string
function M.warn(message)
  write("warn", message)
end

---Log an error-level message (failure).
---@param message string|fun():string
function M.error(message)
  write("error", message)
end

return M
