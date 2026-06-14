---Integration tests for markdown.query_buffer_images.
---Creates a real Neovim buffer and queries it via treesitter.
---Requires the markdown treesitter parser to be installed.
---@diagnostic disable: duplicate-set-field

local M = require("sixel-graphics.integrations.markdown")

-- Check parser availability once before registering tests.
-- If missing, register a single skipped test and return.
local function check_markdown_parser()
  local b = vim.api.nvim_create_buf(true, true)
  local ok, p = pcall(vim.treesitter.get_parser, b, "markdown")
  vim.api.nvim_buf_delete(b, { force = true })
  return ok and p ~= nil
end
local has_parser = check_markdown_parser()

describe("markdown.query_buffer_images (integration)", function()
  if not has_parser then
    it("SKIP: markdown treesitter parser not installed", function() end)
    return
  end

  local buf

  before_each(function()
    -- Create a scratch unlisted buffer
    buf = vim.api.nvim_create_buf(true, true)
  end)

  after_each(function()
    if buf and vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end)

  -- Helper: set buffer content and filetype, then query
  local function set_content_and_query(lines)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].filetype = "markdown"
    -- Force treesitter to re-parse (query_buffer_images also calls parse(true))
    return M.query_buffer_images(buf)
  end

  it("finds standard ![alt](url) images", function()
    local imgs = set_content_and_query({
      "# Test",
      "",
      "Here is an image: ![cat](./images/cat.png)",
      "",
      "Another: ![dog](/absolute/path/dog.jpg)",
    })

    assert.are.equal(2, #imgs)

    -- cat image on line 3 (0-indexed: row 2)
    local cat = imgs[1]
    assert.are.equal(2, cat.range.start_row)
    assert.are.equal("./images/cat.png", cat.url)
    -- starts with ![ and ends with )
    local cat_line = vim.api.nvim_buf_get_lines(buf, cat.range.start_row, cat.range.start_row + 1, false)[1]
    assert.is_not_nil(cat_line:find("!%[cat%]"))

    -- dog image on line 5 (0-indexed: row 4)
    local dog = imgs[2]
    assert.are.equal(4, dog.range.start_row)
    assert.are.equal("/absolute/path/dog.jpg", dog.url)
  end)

  it("finds shortcut link images ![alt]", function()
    local imgs = set_content_and_query({
      "# Shortcut Test",
      "",
      "Reference: ![bird]",
      "",
      "[bird]: ./images/bird.gif",
    })

    -- Should find the shortcut image reference
    assert.are.equal(1, #imgs)
    assert.are.equal(2, imgs[1].range.start_row)
    assert.are.equal("bird", imgs[1].url) -- link_text, not resolved destination
  end)

  it("returns empty for buffers with no images", function()
    local imgs = set_content_and_query({
      "# Plain Markdown",
      "",
      "No images here, just [a link](https://example.com).",
      "",
      "And some **bold** text.",
    })

    assert.are.same({}, imgs)
  end)

  it("handles multiple images on same line", function()
    local imgs = set_content_and_query({
      "# Inline images",
      "",
      "![a](a.png) and ![b](b.png)",
    })

    assert.are.equal(2, #imgs)
    assert.are.equal(2, imgs[1].range.start_row)
    assert.are.equal(2, imgs[2].range.start_row)
    assert.are.equal("a.png", imgs[1].url)
    assert.are.equal("b.png", imgs[2].url)
  end)

  it("handles empty buffer", function()
    local imgs = set_content_and_query({})
    assert.are.same({}, imgs)
  end)

  it("reports correct column positions", function()
    local imgs = set_content_and_query({
      "",
      "",
      "  ![spaced](./img.png)",
    })

    assert.are.equal(1, #imgs)
    -- start_col should be 2 (where ! is)
    assert.are.equal(2, imgs[1].range.start_col)
  end)
end)
