---Unit tests for markdown.find_diagram_at_row.
---Mocks query_buffer_diagrams to isolate cursor-row matching logic
---from treesitter parsing.

-- Pre-load mock so require returns a known module
package.loaded["sixel-graphics.integrations.markdown"] = nil

local M = require("sixel-graphics.integrations.markdown")

describe("markdown.find_diagram_at_row", function()
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

  ---Create a diagram match table with the given row range.
  ---Treesitter fenced_code_block ranges use [start, end) semantics —
  ---end_row is exclusive (points to row after closing ```).
  ---@param start_row number
  ---@param end_row number  Exclusive (first row NOT in the block)
  ---@param renderer_id? string
  ---@param source? string
  ---@return table
  local function match_for_rows(start_row, end_row, renderer_id, source)
    return {
      range = { start_row = start_row, start_col = 0, end_row = end_row, end_col = 0 },
      renderer_id = renderer_id or "mermaid",
      source = source or "flowchart LR\\n    A-->B",
    }
  end

  -- ── multi-line diagram block (the normal case) ──────────────────────

  describe("multi-line diagram block", function()
    -- Diagram at rows 3-8 (0-indexed), treesitter end_row=9 (exclusive).
    -- Cursor on rows 3-8 should hit; rows 2 and 9 should not.

    it("returns match when cursor on start_row (opening fence)", function()
      local original_query = M.query_buffer_diagrams
      M.query_buffer_diagrams = function(_buf)
        return { match_for_rows(3, 9) }
      end

      local result = M.find_diagram_at_row(1, 3)
      assert.is_not_nil(result)
      assert.are.equal("mermaid", result.renderer_id)

      M.query_buffer_diagrams = original_query
    end)

    it("returns match when cursor on last row inside block (closing fence)", function()
      local original_query = M.query_buffer_diagrams
      M.query_buffer_diagrams = function(_buf)
        return { match_for_rows(3, 9) }
      end

      -- Row 8 is the closing ``` — inside the block because 8 < 9
      local result = M.find_diagram_at_row(1, 8)
      assert.is_not_nil(result)

      M.query_buffer_diagrams = original_query
    end)

    it("returns match when cursor between start and end", function()
      local original_query = M.query_buffer_diagrams
      M.query_buffer_diagrams = function(_buf)
        return { match_for_rows(3, 9) }
      end

      local result = M.find_diagram_at_row(1, 5)
      assert.is_not_nil(result)

      M.query_buffer_diagrams = original_query
    end)

    it("returns nil when cursor is on row after closing fence", function()
      local original_query = M.query_buffer_diagrams
      M.query_buffer_diagrams = function(_buf)
        return { match_for_rows(3, 9) }
      end

      -- Row 9 is the blank line after ``` — exclusive end, should NOT hit
      local result = M.find_diagram_at_row(1, 9)
      assert.is_nil(result)

      M.query_buffer_diagrams = original_query
    end)

    it("returns nil when cursor is before the opening fence", function()
      local original_query = M.query_buffer_diagrams
      M.query_buffer_diagrams = function(_buf)
        return { match_for_rows(3, 9) }
      end

      local result = M.find_diagram_at_row(1, 2)
      assert.is_nil(result)

      M.query_buffer_diagrams = original_query
    end)
  end)

  -- ── single-line diagram content ─────────────────────────────────────

  describe("single-line diagram content", function()
    -- e.g., ```mermaid on row 0, graph TD; A-->B on row 1, ``` on row 2
    -- treesitter range: {start_row=0, end_row=3}

    it("returns match when cursor is on the source line", function()
      local original_query = M.query_buffer_diagrams
      M.query_buffer_diagrams = function(_buf)
        return { match_for_rows(0, 3, "mermaid", "graph TD; A-->B") }
      end

      local result = M.find_diagram_at_row(1, 1)
      assert.is_not_nil(result)
      assert.are.equal("graph TD; A-->B", result.source)

      M.query_buffer_diagrams = original_query
    end)

    it("returns nil when cursor is after the closing fence", function()
      local original_query = M.query_buffer_diagrams
      M.query_buffer_diagrams = function(_buf)
        return { match_for_rows(0, 3) }
      end

      local result = M.find_diagram_at_row(1, 3)
      assert.is_nil(result)

      M.query_buffer_diagrams = original_query
    end)
  end)

  -- ── no diagrams ─────────────────────────────────────────────────────

  describe("no diagrams in buffer", function()
    it("returns nil when query_buffer_diagrams returns empty", function()
      local original_query = M.query_buffer_diagrams
      M.query_buffer_diagrams = function(_buf)
        return {}
      end

      local result = M.find_diagram_at_row(1, 0)
      assert.is_nil(result)

      M.query_buffer_diagrams = original_query
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

      local original_query = M.query_buffer_diagrams
      M.query_buffer_diagrams = function(_buf)
        return { match_for_rows(7, 10, "mermaid", "diagram at row 7") }
      end

      local result = M.find_diagram_at_row(1) -- no cursor_row
      assert.is_not_nil(result)
      assert.are.equal("diagram at row 7", result.source)

      M.query_buffer_diagrams = original_query
    end)

    it("returns nil when default cursor row has no diagram", function()
      vim.api.nvim_get_current_win = function()
        return 1
      end
      vim.api.nvim_win_get_cursor = function(_win)
        return { 3, 1 } -- 1-indexed row 3 → 0-indexed row 2
      end

      local original_query = M.query_buffer_diagrams
      M.query_buffer_diagrams = function(_buf)
        return { match_for_rows(10, 15) }
      end

      local result = M.find_diagram_at_row(1) -- no cursor_row
      assert.is_nil(result)

      M.query_buffer_diagrams = original_query
    end)
  end)

  -- ── buf parameter ───────────────────────────────────────────────────

  describe("buf parameter", function()
    it("passes buf through to query_buffer_diagrams", function()
      local captured_buf = nil
      local original_query = M.query_buffer_diagrams
      M.query_buffer_diagrams = function(buf)
        captured_buf = buf
        return { match_for_rows(1, 5) }
      end

      M.find_diagram_at_row(42, 1)
      assert.are.equal(42, captured_buf)

      M.query_buffer_diagrams = original_query
    end)

    it("defaults buf to current buffer when nil", function()
      local captured_buf = nil
      vim.api.nvim_get_current_win = function()
        return 1
      end
      vim.api.nvim_win_get_cursor = function(_win)
        return { 1, 1 }
      end

      local original_query = M.query_buffer_diagrams
      M.query_buffer_diagrams = function(buf)
        captured_buf = buf
        return {}
      end

      M.find_diagram_at_row(nil, 1)
      assert.is_not_nil(captured_buf) -- defaults to current buf

      M.query_buffer_diagrams = original_query
    end)
  end)

  -- ── first match wins ────────────────────────────────────────────────

  describe("multiple diagrams in buffer", function()
    it("returns the first diagram whose range contains the cursor", function()
      local original_query = M.query_buffer_diagrams
      M.query_buffer_diagrams = function(_buf)
        return {
          match_for_rows(2, 5, "plantuml", "plantuml source"),
          match_for_rows(2, 5, "mermaid", "mermaid source"),
        }
      end

      local result = M.find_diagram_at_row(1, 3)
      assert.is_not_nil(result)
      -- Should return the first matching diagram (plantuml), not the second
      assert.are.equal("plantuml", result.renderer_id)
      assert.are.equal("plantuml source", result.source)

      M.query_buffer_diagrams = original_query
    end)

    it("skips diagrams whose range does not contain the cursor", function()
      local original_query = M.query_buffer_diagrams
      M.query_buffer_diagrams = function(_buf)
        return {
          match_for_rows(1, 3, "mermaid", "first"),
          match_for_rows(5, 8, "mermaid", "second"),
        }
      end

      -- Cursor on row 6 — only second diagram matches
      local result = M.find_diagram_at_row(1, 6)
      assert.is_not_nil(result)
      assert.are.equal("second", result.source)

      M.query_buffer_diagrams = original_query
    end)
  end)

  -- ── exact boundary ──────────────────────────────────────────────────

  describe("boundary conditions", function()
    it("returns match when cursor exactly on start_row", function()
      local original_query = M.query_buffer_diagrams
      M.query_buffer_diagrams = function(_buf)
        return { match_for_rows(0, 5) }
      end

      local result = M.find_diagram_at_row(1, 0)
      assert.is_not_nil(result)

      M.query_buffer_diagrams = original_query
    end)

    it("returns nil when cursor is one row below the block end", function()
      local original_query = M.query_buffer_diagrams
      M.query_buffer_diagrams = function(_buf)
        return { match_for_rows(0, 5) }
      end

      -- end_row=5 is exclusive; row 5 is the first row outside the block
      local result = M.find_diagram_at_row(1, 5)
      assert.is_nil(result)

      M.query_buffer_diagrams = original_query
    end)

    it("returns match when cursor is one row before the block end", function()
      local original_query = M.query_buffer_diagrams
      M.query_buffer_diagrams = function(_buf)
        return { match_for_rows(0, 5) }
      end

      -- Row 4 is inside (4 < 5)
      local result = M.find_diagram_at_row(1, 4)
      assert.is_not_nil(result)

      M.query_buffer_diagrams = original_query
    end)
  end)
end)
