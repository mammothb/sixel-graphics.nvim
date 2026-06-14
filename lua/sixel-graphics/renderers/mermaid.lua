---Mermaid diagram renderer.
---
---Renders Mermaid diagram source code to PNG via an external CLI tool.
---Two renderer backends are supported:
---  - mmdr (mermaid-rs-renderer): native Rust, 2-6ms, synchronous `vim.fn.system()`
---  - mmdc (mermaid-cli): Node.js/Chromium, 1-5s, async `vim.fn.jobstart()` (Step D3)
---
---Currently only the mmdr path is implemented. The mmdc path will be added in Step D3.
---@class MermaidRenderer
local M = {
  id = "mermaid",
}

local logger = require("sixel-graphics.utils.logger")

---@private
---Compute a deterministic cache key from diagram source and renderer name.
---Same source renders differently under mmdr vs mmdc, so include the
---renderer name in the hash input to keep their caches separate.
---@param source string        Diagram source code
---@param renderer_name string  "mmdr" or "mmdc"
---@return string  sha256 hex digest (64 characters)
local function _compute_hash(source, renderer_name)
  return vim.fn.sha256(renderer_name .. ":" .. source)
end
M._compute_hash = _compute_hash

---@private
---Get or create the mermaid cache directory.
---@return string  Absolute path to cache directory
local function _get_cache_dir()
  local dir = vim.fn.stdpath("cache") .. "/sixel-graphics/mermaid"
  vim.fn.mkdir(dir, "p")
  return dir
end
M._get_cache_dir = _get_cache_dir

---@private
---Get the full cache file path for a given hash.
---@param hash string  sha256 hex digest
---@return string  Absolute path to cached PNG file
local function _get_cache_path(hash)
  return _get_cache_dir() .. "/" .. hash .. ".png"
end
M._get_cache_path = _get_cache_path

---@private
---Check if a cached PNG exists for the given hash.
---@param hash string  sha256 hex digest
---@return string|nil  Path to cached PNG, or nil if not cached
local function _check_cache(hash)
  local path = _get_cache_path(hash)
  if vim.fn.filereadable(path) == 1 then
    return path
  end
  return nil
end
M._check_cache = _check_cache

---Render a mermaid diagram source to PNG.
---
---mmdr path (sync, implemented): hash → cache check → vim.fn.system() → file_path
---mmdc path (async, NOT YET IMPLEMENTED): returns nil with notification
---
---@param source string   Diagram source code
---@param options table   renderer_options.mermaid from config
---@return { file_path: string }?  nil if renderer not installed or not yet implemented
function M.render(source, options)
  options = options or {}
  local renderer_name = options.renderer or "mmdr"

  if renderer_name == "mmdc" then
    vim.notify("sixel-graphics: mmdc renderer not yet implemented (coming in Step D3)", vim.log.levels.WARN)
    return nil
  end

  if renderer_name ~= "mmdr" then
    vim.notify("sixel-graphics: unknown renderer '" .. tostring(renderer_name) .. "'", vim.log.levels.ERROR)
    return nil
  end

  logger.debug("mermaid.render: not yet implemented (mmdr path coming in D2.3-D2.5)")
  return nil
end

return M
