---Markdown integration: treesitter-based image reference detection.
---
---Parses markdown buffers via treesitter and extracts image references
---(![alt](url) and shortcut link references) with their source positions.
---
---@class MarkdownImageMatch
---@field range { start_row: number, start_col: number, end_row: number, end_col: number }
---@field url string  Raw URL/path from the markdown source

---@class DiagramMatch
---@field renderer_id string  e.g., "mermaid"
---@field source string       Diagram source code (without ``` fences or language tag)
---@field range { start_row: number, start_col: number, end_row: number, end_col: number }

---@class MarkdownIntegration
local M = {}

local logger = require("sixel-graphics.utils.logger")

-- Cached treesitter query for fenced code blocks (reused across calls)
local diagram_query = nil

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

---Parse a markdown buffer via treesitter and return all mermaid diagram
---fenced code blocks.
---
---Only detects fenced code blocks with info string exactly "mermaid".
---Whitelist-gated to leave room for plantuml/d2/gnuplot in the future.
---
---@param buf? number  Buffer handle (default: current buffer)
---@return DiagramMatch[]
function M.query_buffer_diagrams(buf)
  buf = buf or vim.api.nvim_get_current_buf()

  -- Get the markdown treesitter parser
  local ok, parser = pcall(vim.treesitter.get_parser, buf, "markdown")
  if not ok or not parser then
    logger.warn(function()
      return string.format(
        "query_buffer_diagrams: no markdown parser for buffer %d (ft=%s)",
        buf,
        vim.bo[buf].filetype or "nil"
      )
    end)
    vim.notify("sixel-graphics: no markdown treesitter parser found for buffer " .. buf, vim.log.levels.WARN)
    return {}
  end

  -- Force re-parse to ensure tree is current
  local trees = parser:parse(true)
  local root = trees[1]:root()

  -- Cache the query on first call
  if not diagram_query then
    diagram_query =
      vim.treesitter.query.parse("markdown", "(fenced_code_block (info_string) @info (code_fence_content) @code)")
  end

  local diagrams = {}
  local current_language = nil
  local current_range = nil

  for id, node in diagram_query:iter_captures(root, buf) do
    local capture_name = diagram_query.captures[id]

    if capture_name == "info" then
      local value = vim.treesitter.get_node_text(node, buf)

      -- Get the fenced_code_block parent node range (covers ``` fences)
      local fenced_block = node:parent()
      if fenced_block then
        local start_row, start_col, end_row, end_col = fenced_block:range()
        current_range = {
          start_row = start_row,
          start_col = start_col,
          end_row = end_row,
          end_col = end_col,
        }
      end

      -- Whitelist: only "mermaid" for now (leaves room for plantuml/d2/gnuplot)
      if value == "mermaid" then
        current_language = value
      else
        current_language = nil
      end
    elseif capture_name == "code" then
      if current_language then
        local source = vim.treesitter.get_node_text(node, buf)

        -- Strip block quote prefixes from source text inside block quotes
        if node:parent():parent() and node:parent():parent():type() == "block_quote" then
          source = source:gsub("\n>", "\n"):gsub("^>", "")
        end

        table.insert(diagrams, {
          renderer_id = current_language,
          source = source,
          range = current_range,
        })
      end
      current_language = nil
      current_range = nil
    end
  end

  logger.debug(function()
    return string.format("query_buffer_diagrams: buffer %d, found %d diagram(s)", buf, #diagrams)
  end)
  return diagrams
end

---Find a mermaid diagram whose range contains the given cursor row.
---Returns the first matching diagram, or nil if cursor is not inside a
---diagram code block.
---@param buf? number      Buffer handle (default: current buffer)
---@param cursor_row? number  0-indexed row to check (default: current cursor row)
---@return DiagramMatch|nil
function M.find_diagram_at_row(buf, cursor_row)
  buf = buf or vim.api.nvim_get_current_buf()
  local diagrams = M.query_buffer_diagrams(buf)

  if cursor_row == nil then
    local cursor = vim.api.nvim_win_get_cursor(0)
    cursor_row = cursor[1] - 1 -- 1-indexed → 0-indexed
  end

  for _, diagram in ipairs(diagrams) do
    -- fenced_code_block is a multi-row block node; treesitter end_row is
    -- exclusive (points to the row after closing ```). Use < to avoid
    -- triggering on the blank line after the fence.
    if diagram.range.start_row <= cursor_row and cursor_row < diagram.range.end_row then
      logger.debug(function()
        return string.format("find_diagram_at_row: row=%d hit renderer=%s", cursor_row, diagram.renderer_id)
      end)
      return diagram
    end
  end

  return nil
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
    -- Inline image nodes are single-row: treesitter sets end_row == start_row.
    -- With <=, cursor_row == start_row matches, cursor_row == start_row+1
    -- does not (since start_row+1 <= start_row is false). Safe.
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
