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
