---Markdown integration: treesitter-based image reference detection.
---
---Parses markdown buffers via treesitter and extracts image references
---(![alt](url) and shortcut link references) with their source positions.
---
---@class MarkdownImageMatch
---@field range { start_row: number, start_col: number, end_row: number, end_col: number }
---@field url string  Raw URL/path from the markdown source

---@class MarkdownIntegration
local M = {}

local logger = require("sixel-graphics.utils.logger")

---Parse a markdown buffer via treesitter and return all image references.
---
---Handles two markdown image syntaxes:
---  1. Standard:  ![alt text](path/to/image.png)
---  2. Shortcut:  ![alt text]  (where [alt text] is a reference link)
---
---Uses the markdown_inline language tree for finer granularity
---(image nodes appear inside inline nodes, not at block level).
---
---@param buf? number  Buffer handle (default: current buffer)
---@return MarkdownImageMatch[]
function M.query_buffer_images(buf)
  buf = buf or vim.api.nvim_get_current_buf()

  -- Get the markdown treesitter parser
  local ok, parser = pcall(vim.treesitter.get_parser, buf, "markdown")
  if not ok or not parser then
    logger.warn(function()
      return string.format(
        "query_buffer_images: no markdown parser for buffer %d (ft=%s)",
        buf,
        vim.bo[buf].filetype or "nil"
      )
    end)
    vim.notify("sixel-graphics: no markdown treesitter parser found for buffer " .. buf, vim.log.levels.WARN)
    return {}
  end

  -- Force re-parse to ensure tree is current
  parser:parse(true)

  -- Get the markdown_inline child language tree
  local inline_lang = "markdown_inline"
  local inlines = parser:children()[inline_lang]

  if not inlines then
    logger.debug("query_buffer_images: no markdown_inline tree found")
    return {}
  end

  -- Query all image nodes; distinguish standard vs shortcut by child presence.
  -- Standard: ![alt](url) has a link_destination child.
  -- Shortcut: ![alt] has no link_destination; use image_description text.
  local image_query = vim.treesitter.query.parse(inline_lang, "(image) @image")

  local images = {}

  ---Iterate a treesitter tree and extract image matches.
  ---@param tree TSTree
  local function get_inline_images(tree)
    local root = tree:root()

    for id, node in image_query:iter_captures(root, buf) do
      if image_query.captures[id] == "image" then
        local start_row, start_col, end_row, end_col = node:range()
        local url = nil

        -- Check children for link_destination (standard) or image_description (shortcut)
        for child in node:iter_children() do
          if child:named() and child:type() == "link_destination" then
            url = vim.treesitter.get_node_text(child, buf)
            break
          end
        end

        -- Fallback: shortcut link — use image_description text as the reference
        if not url then
          for child in node:iter_children() do
            if child:named() and child:type() == "image_description" then
              url = vim.treesitter.get_node_text(child, buf)
              break
            end
          end
        end

        if url then
          table.insert(images, {
            range = {
              start_row = start_row,
              start_col = start_col,
              end_row = end_row,
              end_col = end_col,
            },
            url = url,
          })
        end
      end
    end
  end

  -- markdown_inline has its own per-tree iteration (not for_each_child)
  inlines:for_each_tree(get_inline_images)

  logger.debug(function()
    return string.format("query_buffer_images: buffer %d, found %d image(s)", buf, #images)
  end)
  return images
end

---Find a markdown image whose range contains the given cursor row.
---Returns the first matching image, or nil if cursor is not on an image line.
---@param buf? number      Buffer handle (default: current buffer)
---@param cursor_row? number  0-indexed row to check (default: current cursor row)
---@return MarkdownImageMatch|nil
function M.find_image_at_row(buf, cursor_row)
  buf = buf or vim.api.nvim_get_current_buf()
  local images = M.query_buffer_images(buf)

  if cursor_row == nil then
    local cursor = vim.api.nvim_win_get_cursor(0)
    cursor_row = cursor[1] - 1 -- 1-indexed → 0-indexed
  end

  for _, img in ipairs(images) do
    if img.range.start_row <= cursor_row and cursor_row <= img.range.end_row then
      logger.debug(function()
        return string.format("find_image_at_row: row=%d hit url=%s", cursor_row, img.url)
      end)
      return img
    end
  end

  return nil
end

return M
