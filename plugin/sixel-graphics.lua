---Auto-initialization entry point for sixel-graphics.nvim.
---
---Loaded automatically by Neovim from runtimepath (see :h load-plugins).
---This file is intentionally small: it reads config, calls _init(),
---and defines <Plug> mappings. Heavy submodules (magick_cli, mermaid,
---markdown) are only required inside the deferred callbacks, not here.
---
---Users who want to prevent auto-loading can set:
---  vim.g.loaded_sixel_graphics = true
---before plugins are sourced.

if vim.g.loaded_sixel_graphics then
  return
end
vim.g.loaded_sixel_graphics = true

-- Apply vim.g config if the user set it before plugin load.
-- Supports both a table and a function that returns a table.
local gcfg = vim.g.sixel_graphics
if type(gcfg) == "function" then
  gcfg = gcfg()
end
if gcfg then
  require("sixel-graphics.config").setup(gcfg)
end

-- Auto-initialize state, backend, and hover autocommands.
-- Idempotent: if setup() already called _init(), this no-ops.
require("sixel-graphics")._init()

-- <Plug> mappings — deferred require in callback bodies so the
-- main module is only loaded when the mapping is actually invoked.
vim.keymap.set("n", "<Plug>(SixelGraphicsClosePopup)", function()
  require("sixel-graphics").close_popup()
end)

vim.keymap.set("n", "<Plug>(SixelGraphicsToggle)", function()
  local sg = require("sixel-graphics")
  if sg.is_enabled() then
    sg.disable()
  else
    sg.enable()
  end
end)
