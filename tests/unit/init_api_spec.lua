---Unit tests for public API diagram functions: query_markdown_diagrams, render_mermaid.
---
---Mocks Neovim APIs and sub-modules to isolate delegation logic.

-- Pre-load mocks to prevent side effects during init.lua loading
package.loaded["sixel-graphics.backends.sixel"] = {
  setup = function() end,
  clear = function() end,
  is_sixel_supported = function()
    return true
  end,
}
package.loaded["sixel-graphics.utils.term"] = {
  get_size = function()
    return { cell_width = 10, cell_height = 20, screen_cols = 80, screen_rows = 24 }
  end,
}
package.loaded["sixel-graphics.processors.magick_cli"] = {
  get_dimensions = function()
    return { width = 640, height = 480 }
  end,
  encode_to_sixel = function()
    return "dummy"
  end,
  is_available = function()
    return true
  end,
}
package.loaded["sixel-graphics.utils.logger"] = {
  debug = function() end,
  info = function() end,
  warn = function() end,
  error = function() end,
}
package.loaded["sixel-graphics.integrations.markdown"] = {
  query_buffer_images = function()
    return {}
  end,
  find_image_at_row = function()
    return nil
  end,
  query_buffer_diagrams = function()
    return {}
  end,
  find_diagram_at_row = function()
    return nil
  end,
}
-- Pre-load mermaid mock (used by render_mermaid, lazy-loaded in init.lua)
package.loaded["sixel-graphics.renderers.mermaid"] = {
  id = "mermaid",
  render = function()
    return { file_path = "/cache/test.png" }
  end,
}

local M = require("sixel-graphics")

describe("public API — diagram functions", function()
  before_each(function()
    M.has_setup = false -- thin wrappers, no state needed
  end)

  -- ── query_markdown_diagrams ────────────────────────────────────

  describe("query_markdown_diagrams()", function()
    it("is a function", function()
      assert.is_function(M.query_markdown_diagrams)
    end)

    it("returns a table", function()
      local result = M.query_markdown_diagrams()
      assert.is_table(result)
    end)

    it("delegates to markdown.query_buffer_diagrams with buf arg", function()
      local markdown = require("sixel-graphics.integrations.markdown")
      local spy = require("luassert.spy").on(markdown, "query_buffer_diagrams")

      M.query_markdown_diagrams(42)

      assert.spy(spy).was_called(1)
      assert.spy(spy).was_called_with(42)
      spy:revert()
    end)

    it("delegates with nil buf (defaults to current buffer in markdown module)", function()
      local markdown = require("sixel-graphics.integrations.markdown")
      local spy = require("luassert.spy").on(markdown, "query_buffer_diagrams")

      M.query_markdown_diagrams()

      assert.spy(spy).was_called(1)
      spy:revert()
    end)
  end)

  -- ── render_mermaid ─────────────────────────────────────────────

  describe("render_mermaid()", function()
    it("is a function", function()
      assert.is_function(M.render_mermaid)
    end)

    it("returns { file_path } on success (sync path)", function()
      local result = M.render_mermaid("flowchart LR; A-->B", { renderer = "mmdr" })
      assert.is_table(result)
      assert.are.equal("/cache/test.png", result.file_path)
    end)

    it("delegates to mermaid.render with source, opts, and nil on_complete", function()
      local mermaid = require("sixel-graphics.renderers.mermaid")
      local render_spy = require("luassert.spy").new(function()
        return { file_path = "/cache/test.png" }
      end)
      mermaid.render = render_spy

      local source = "flowchart LR; A-->B"
      local opts = { renderer = "mmdr", mmdr = { width = 800 } }

      M.render_mermaid(source, opts)

      assert.spy(render_spy).was_called(1)
      assert.spy(render_spy).was_called_with(source, opts, nil)
    end)

    it("passes on_complete callback through for mmdc path", function()
      local mermaid = require("sixel-graphics.renderers.mermaid")
      local captured_cb = nil
      mermaid.render = function(_, _, cb)
        captured_cb = cb
        return { job_id = 99 }
      end

      local opts = { renderer = "mmdc" }
      M.render_mermaid("source", opts, function() end)

      assert.is_not_nil(captured_cb)
      assert.is_function(captured_cb)
    end)

    it("returns nil when mermaid.render returns nil (error)", function()
      local mermaid = require("sixel-graphics.renderers.mermaid")
      mermaid.render = function()
        return nil
      end

      local result = M.render_mermaid("bad syntax", { renderer = "mmdr" })
      assert.is_nil(result)
    end)
  end)
end)
