---Unit tests for markdown.find_image_at_row.
---Mocks query_buffer_images to isolate cursor-row matching logic
---from treesitter parsing.

-- Pre-load mock so require returns a known module
package.loaded["sixel-graphics.integrations.markdown"] = nil

local M = require("sixel-graphics.integrations.markdown")

describe("markdown.find_image_at_row", function()
  -- Save originals for restoration
  local _get_current_win
  local _win_get_cursor

  before_each(function()
    _get_current_win = vim.api.nvim_get_current_win
    _win_get_cursor = vim.api.nvim_win_get_cursor
  end)

  after_each(function()
    vim.api.nvim_get_current_win = _get_current_win
    vim.api.nvim_win_get_cursor = _win_get_cursor
  end)

  ---Create an image match table with the given row range.
  ---@param start_row number
  ---@param end_row number
  ---@param url? string
  ---@return table
  local function match_for_rows(start_row, end_row, url)
    return {
      range = { start_row = start_row, start_col = 0, end_row = end_row, end_col = 10 },
      url = url or "test.png",
    }
  end

  -- ── single-line images ──────────────────────────────────────────────

  describe("single-line image", function()
    it("returns match when cursor is on the image line", function()
      -- Mock query_buffer_images via package.loaded
      local original_query = M.query_buffer_images
      M.query_buffer_images = function(_buf)
        return { match_for_rows(3, 3, "./cat.png") }
      end

      local result = M.find_image_at_row(1, 3)
      assert.is_not_nil(result)
      assert.are.equal("./cat.png", result.url)

      M.query_buffer_images = original_query
    end)

    it("returns nil when cursor is before the image line", function()
      local original_query = M.query_buffer_images
      M.query_buffer_images = function(_buf)
        return { match_for_rows(5, 5) }
      end

      local result = M.find_image_at_row(1, 2)
      assert.is_nil(result)

      M.query_buffer_images = original_query
    end)

    it("returns nil when cursor is after the image line", function()
      local original_query = M.query_buffer_images
      M.query_buffer_images = function(_buf)
        return { match_for_rows(1, 1) }
      end

      local result = M.find_image_at_row(1, 5)
      assert.is_nil(result)

      M.query_buffer_images = original_query
    end)

    it("returns nil when no images exist in buffer", function()
      local original_query = M.query_buffer_images
      M.query_buffer_images = function(_buf)
        return {}
      end

      local result = M.find_image_at_row(1, 0)
      assert.is_nil(result)

      M.query_buffer_images = original_query
    end)
  end)

  -- ── multi-line image ranges ─────────────────────────────────────────

  describe("multi-line image range", function()
    -- Each test case manages its own query_buffer_images mock.
    it("returns match when cursor on start_row", function()
      local original_query = M.query_buffer_images
      M.query_buffer_images = function()
        return { match_for_rows(3, 5, "./wide.png") }
      end
      local result = M.find_image_at_row(1, 3)
      assert.is_not_nil(result)
      assert.are.equal("./wide.png", result.url)
      M.query_buffer_images = original_query
    end)

    it("returns match when cursor on end_row", function()
      local original_query = M.query_buffer_images
      M.query_buffer_images = function()
        return { match_for_rows(3, 5, "./wide.png") }
      end
      local result = M.find_image_at_row(1, 5)
      assert.is_not_nil(result)
      M.query_buffer_images = original_query
    end)

    it("returns match when cursor between start_row and end_row", function()
      local original_query = M.query_buffer_images
      M.query_buffer_images = function()
        return { match_for_rows(3, 5, "./wide.png") }
      end
      local result = M.find_image_at_row(1, 4)
      assert.is_not_nil(result)
      M.query_buffer_images = original_query
    end)

    it("returns nil when cursor below the multi-line range", function()
      local original_query = M.query_buffer_images
      M.query_buffer_images = function()
        return { match_for_rows(3, 5, "./wide.png") }
      end
      local result = M.find_image_at_row(1, 6)
      assert.is_nil(result)
      M.query_buffer_images = original_query
    end)
  end)

  -- ── cursor_row default ──────────────────────────────────────────────

  describe("cursor_row default", function()
    it("derives cursor_row from current window cursor when nil", function()
      vim.api.nvim_get_current_win = function()
        return 1
      end
      vim.api.nvim_win_get_cursor = function(_win)
        return { 8, 1 } -- 1-indexed row 8 → 0-indexed row 7
      end

      local original_query = M.query_buffer_images
      M.query_buffer_images = function(_buf)
        return { match_for_rows(7, 7, "./at-row-7.png") }
      end

      local result = M.find_image_at_row(1) -- no cursor_row
      assert.is_not_nil(result)
      assert.are.equal("./at-row-7.png", result.url)

      M.query_buffer_images = original_query
    end)

    it("returns nil when default cursor row has no image", function()
      vim.api.nvim_get_current_win = function()
        return 1
      end
      vim.api.nvim_win_get_cursor = function(_win)
        return { 3, 1 } -- 1-indexed row 3 → 0-indexed row 2
      end

      local original_query = M.query_buffer_images
      M.query_buffer_images = function(_buf)
        return { match_for_rows(10, 10) }
      end

      local result = M.find_image_at_row(1) -- no cursor_row
      assert.is_nil(result)

      M.query_buffer_images = original_query
    end)
  end)

  -- ── buf parameter ───────────────────────────────────────────────────

  describe("buf parameter", function()
    it("passes buf through to query_buffer_images", function()
      local captured_buf = nil
      local original_query = M.query_buffer_images
      M.query_buffer_images = function(buf)
        captured_buf = buf
        return { match_for_rows(1, 1) }
      end

      M.find_image_at_row(42, 1)
      assert.are.equal(42, captured_buf)

      M.query_buffer_images = original_query
    end)

    it("defaults buf to current buffer when nil", function()
      local captured_buf = nil
      vim.api.nvim_get_current_win = function()
        return 1
      end
      vim.api.nvim_win_get_cursor = function(_win)
        return { 1, 1 }
      end

      local original_query = M.query_buffer_images
      M.query_buffer_images = function(buf)
        captured_buf = buf
        return {}
      end

      M.find_image_at_row(nil, 1)
      assert.is_not_nil(captured_buf) -- defaults to current buf

      M.query_buffer_images = original_query
    end)
  end)

  -- ── first match ─────────────────────────────────────────────────────

  describe("multiple images on same line", function()
    it("returns the first matching image", function()
      local original_query = M.query_buffer_images
      M.query_buffer_images = function(_buf)
        return {
          match_for_rows(2, 2, "first.png"),
          match_for_rows(2, 2, "second.png"),
        }
      end

      local result = M.find_image_at_row(1, 2)
      assert.is_not_nil(result)
      assert.are.equal("first.png", result.url)

      M.query_buffer_images = original_query
    end)
  end)
end)
