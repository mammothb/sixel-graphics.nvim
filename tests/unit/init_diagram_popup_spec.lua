---Unit tests for init.lua create_popup_for_diagram (mmdr sync + mmdc async).
---
---Mocks mermaid renderer, backends, term, magick to isolate the
---diagram → render → popup pipeline from filesystem/subprocess side effects.

-- Pre-load mocks to prevent side effects during init.lua loading
package.loaded["sixel-graphics.backends.sixel"] = {
  setup = function() end,
  clear = function() end,
  render = function()
    return "test-id"
  end,
  is_sixel_supported = function()
    return true
  end,
  send_sixel = function() end,
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
    return "dummy-sixel-data"
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

-- Mock markdown integration (query_buffer_images used by init loading)
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

local M = require("sixel-graphics")

describe("create_popup_for_diagram (mmdr sync)", function()
  local mermaid_mock
  local _notify
  local _win_is_valid
  local _win_close
  local _win_get_buf
  local _win_get_position

  before_each(function()
    _notify = vim.notify
    _win_is_valid = vim.api.nvim_win_is_valid
    _win_close = vim.api.nvim_win_close
    _win_get_buf = vim.api.nvim_win_get_buf
    _win_get_position = vim.api.nvim_win_get_position

    -- Mock window APIs so close_popup() in after_each is safe:
    -- our spy returns fake window IDs (1000) that aren't real windows.
    vim.api.nvim_win_is_valid = function(_win)
      return false -- never try to close fake windows
    end
    vim.api.nvim_win_close = function(_, _) end
    vim.api.nvim_win_get_buf = function(_win)
      return 1
    end
    vim.api.nvim_win_get_position = function(_win)
      return { 5, 10 }
    end

    -- Default mermaid mock: successful mmdr render
    mermaid_mock = {
      id = "mermaid",
      render = function()
        return { file_path = "/cache/sixel-graphics/mermaid/hash123.png" }
      end,
    }
    package.loaded["sixel-graphics.renderers.mermaid"] = mermaid_mock

    -- Set up state so guard_setup passes
    M.has_setup = true
    M.state = {
      enabled = true,
      images = {},
      options = {
        scale = 1.0,
        sixel_pixel_scale = 1.0,
        popup_render_delay_ms = 16,
        hover = {
          debounce_ms = 150,
          max_screen_fraction = 0.5,
          filetypes = { "markdown" },
        },
        renderer_options = {
          mermaid = {
            renderer = "mmdr",
            mmdr = {},
            mmdc = {},
          },
        },
      },
    }

    vim.notify = function() end
  end)

  after_each(function()
    vim.notify = _notify
    vim.api.nvim_win_is_valid = _win_is_valid
    vim.api.nvim_win_close = _win_close
    vim.api.nvim_win_get_buf = _win_get_buf
    vim.api.nvim_win_get_position = _win_get_position
    -- Close any popup left from the test (win_is_valid returns false, so safe)
    M.close_popup()
    -- Wait for deferred popup_in_progress reset (50ms timer in close_active_popup)
    vim.wait(100, function() end)
  end)

  -- ── success path ────────────────────────────────────────────────

  describe("success path", function()
    it("calls mermaid.render with source and options", function()
      local render_spy = require("luassert.spy").new(mermaid_mock.render)
      mermaid_mock.render = render_spy

      local source = "flowchart LR\n    A --> B"
      local opts = { renderer = "mmdr", mmdr = { width = 800 } }

      M.create_popup_for_diagram(source, opts)

      assert.spy(render_spy).was_called(1)
      -- Verify source was the first argument
      assert.are.equal(source, render_spy.calls[1].vals[1])
    end)

    it("calls show_image_popup with the returned file_path", function()
      -- Spy on the real show_image_popup (remains functional with mocked deps)
      local popup_spy = require("luassert.spy").on(M, "show_image_popup")

      local source = "flowchart LR\n    A --> B"
      local opts = { renderer = "mmdr" }

      M.create_popup_for_diagram(source, opts)

      assert.spy(popup_spy).was_called(1)
      assert.spy(popup_spy).was_called_with("/cache/sixel-graphics/mermaid/hash123.png", nil)
      popup_spy:revert()
    end)

    it("passes min_popup_width through to show_image_popup when configured", function()
      local popup_spy = require("luassert.spy").on(M, "show_image_popup")

      local source = "flowchart LR\n    A --> B"
      local opts = { renderer = "mmdr", min_popup_width = 60 }

      M.create_popup_for_diagram(source, opts)

      assert.spy(popup_spy).was_called(1)
      assert.spy(popup_spy).was_called_with("/cache/sixel-graphics/mermaid/hash123.png", { min_width_cells = 60 })
      popup_spy:revert()
    end)

    it("returns true on success", function()
      local result = M.create_popup_for_diagram("flowchart LR; A-->B", { renderer = "mmdr" })
      assert.is_true(result)
    end)
  end)

  -- ── nil return from mermaid.render ──────────────────────────────

  describe("when mermaid.render returns nil", function()
    it("returns false when renderer not installed", function()
      mermaid_mock.render = function()
        return nil
      end

      local result = M.create_popup_for_diagram("source", { renderer = "mmdr" })
      assert.is_false(result)
    end)

    it("does not call show_image_popup when render fails", function()
      mermaid_mock.render = function()
        return nil
      end

      local popup_spy = require("luassert.spy").on(M, "show_image_popup")
      M.create_popup_for_diagram("source", { renderer = "mmdr" })
      assert.spy(popup_spy).was_called(0)
      popup_spy:revert()
    end)
  end)

  -- ── single-popup enforcement ────────────────────────────────────

  describe("single-popup enforcement", function()
    it("does not error when called with a diagram popup active", function()
      -- First call: create a diagram popup
      local popup_spy1 = require("luassert.spy").on(M, "show_image_popup")
      local result1 = M.create_popup_for_diagram("flowchart LR; A-->B", { renderer = "mmdr" })
      assert.is_true(result1)
      assert.spy(popup_spy1).was_called(1)
      popup_spy1:revert()

      -- Second call: create another diagram popup (should close first)
      local popup_spy2 = require("luassert.spy").on(M, "show_image_popup")
      local result2 = M.create_popup_for_diagram("flowchart TD; X-->Y", { renderer = "mmdr" })
      assert.is_true(result2)
      assert.spy(popup_spy2).was_called(1)
      popup_spy2:revert()

      -- show_image_popup was called 2 times total (once per diagram)
      -- and close_active_popup was called between them (no crash)
    end)

    it("show_image_popup receives the diagram PNG path", function()
      local popup_spy = require("luassert.spy").on(M, "show_image_popup")

      local source = "sequenceDiagram\n    A->>B: Hello"
      local opts = { renderer = "mmdr" }

      M.create_popup_for_diagram(source, opts)

      assert.spy(popup_spy).was_called_with("/cache/sixel-graphics/mermaid/hash123.png", nil)
      popup_spy:revert()
    end)
  end)

  -- ── active_popup.source field ───────────────────────────────────

  describe("active_popup.source tracking", function()
    it("succeeds with the same source multiple times (source field set correctly)", function()
      local source = "flowchart TD\n    X --> Y"
      local opts = { renderer = "mmdr" }

      local result1 = M.create_popup_for_diagram(source, opts)
      assert.is_true(result1)

      M.close_popup()
      -- Wait for deferred popup_in_progress reset (50ms in close_active_popup)
      vim.wait(100, function() end)

      -- Create again with same source — should succeed
      local result2 = M.create_popup_for_diagram(source, opts)
      assert.is_true(result2)
    end)

    it("close_popup clears state without error after diagram popup", function()
      M.create_popup_for_diagram("diagram source", { renderer = "mmdr" })

      -- close_popup should work without error
      assert.has_no.errors(function()
        M.close_popup()
      end)

      -- Calling close_popup again should not error (active_popup is nil)
      assert.has_no.errors(function()
        M.close_popup()
      end)
    end)
  end)

  -- ── guard_setup ─────────────────────────────────────────────────

  describe("guard_setup", function()
    it("throws error when has_setup is false", function()
      M.has_setup = false
      assert.has.errors(function()
        M.create_popup_for_diagram("source", { renderer = "mmdr" })
      end)
      M.has_setup = true -- restore for other tests
    end)

    it("does not throw when has_setup is true", function()
      assert.has_no.errors(function()
        M.create_popup_for_diagram("flowchart LR; A-->B", { renderer = "mmdr" })
      end)
    end)
  end)

  -- ── mmdc async path ────────────────────────────────────────────

  describe("mmdc async path", function()
    local _timer_start

    before_each(function()
      _timer_start = vim.fn.timer_start
      vim.fn.timer_start = function(_, _)
        return 999
      end -- no-op timer for timeout guard
    end)

    after_each(function()
      vim.fn.timer_start = _timer_start
      -- Clear any pending async state between tests
      M.close_popup()
      vim.wait(100, function() end)
    end)

    it("passes on_complete callback to mermaid.render (3rd arg)", function()
      local render_spy = require("luassert.spy").new(function(_source, _opts, cb)
        -- Store callback for manual firing
        mermaid_mock._last_callback = cb
        return { job_id = 42 }
      end)
      mermaid_mock.render = render_spy

      local opts = { renderer = "mmdc", mmdc = { theme = "dark" } }
      M.create_popup_for_diagram("source", opts)

      assert.spy(render_spy).was_called(1)
      -- 3rd argument should be a function (the callback)
      local third_arg = render_spy.calls[1].vals[3]
      assert.is_function(third_arg)
    end)

    it("shows loading notification when mmdc job starts", function()
      local notify_calls = {}
      vim.notify = function(msg, level)
        table.insert(notify_calls, { msg = msg, level = level })
      end

      mermaid_mock.render = function(_, _, cb)
        mermaid_mock._last_callback = cb
        return { job_id = 42 }
      end

      M.create_popup_for_diagram("source", { renderer = "mmdc" })

      assert.are.equal(1, #notify_calls)
      assert.is_not_nil(string.find(notify_calls[1].msg, "rendering"))
      assert.are.equal(vim.log.levels.INFO, notify_calls[1].level)
    end)

    it("returns true when async job starts", function()
      mermaid_mock.render = function(_, _, cb)
        mermaid_mock._last_callback = cb
        return { job_id = 42 }
      end

      local result = M.create_popup_for_diagram("source", { renderer = "mmdc" })
      assert.is_true(result)
    end)

    it("does not call show_image_popup immediately (async)", function()
      mermaid_mock.render = function(_, _, cb)
        mermaid_mock._last_callback = cb
        return { job_id = 42 }
      end

      local popup_spy = require("luassert.spy").on(M, "show_image_popup")
      M.create_popup_for_diagram("source", { renderer = "mmdc" })
      -- show_image_popup should NOT be called synchronously
      assert.spy(popup_spy).was_called(0)
      popup_spy:revert()
    end)

    it("calls show_image_popup when on_complete fires with path", function()
      mermaid_mock.render = function(_, _, cb)
        mermaid_mock._last_callback = cb
        return { job_id = 42 }
      end

      M.create_popup_for_diagram("source", { renderer = "mmdc" })

      -- Simulate mmdc completion
      local popup_spy = require("luassert.spy").on(M, "show_image_popup")
      mermaid_mock._last_callback("/cache/mermaid/abc123.png") -- no error

      -- on_complete uses vim.schedule, so pump the event loop
      vim.wait(50, function() end)

      assert.spy(popup_spy).was_called(1)
      assert.spy(popup_spy).was_called_with("/cache/mermaid/abc123.png", nil)
      popup_spy:revert()
    end)

    it("shows error notification when on_complete fires with error", function()
      mermaid_mock.render = function(_, _, cb)
        mermaid_mock._last_callback = cb
        return { job_id = 42 }
      end

      M.create_popup_for_diagram("source", { renderer = "mmdc" })

      local notify_calls = {}
      vim.notify = function(msg, level)
        table.insert(notify_calls, { msg = msg, level = level })
      end

      mermaid_mock._last_callback(nil, "syntax error in diagram")
      vim.wait(50, function() end)

      assert.are.equal(1, #notify_calls)
      assert.is_not_nil(string.find(notify_calls[1].msg, "render failed"))
      assert.is_not_nil(string.find(notify_calls[1].msg, "syntax error"))
      assert.are.equal(vim.log.levels.ERROR, notify_calls[1].level)
    end)

    it("silently ignores completion when popup was closed (stale)", function()
      mermaid_mock.render = function(_, _, cb)
        mermaid_mock._last_callback = cb
        return { job_id = 42 }
      end

      M.create_popup_for_diagram("source", { renderer = "mmdc" })

      -- Close popup (simulates cursor moving away during load)
      M.close_popup()
      vim.wait(100, function() end) -- let popup_in_progress reset

      -- Now fire completion — should be silently ignored
      local popup_spy = require("luassert.spy").on(M, "show_image_popup")
      local notify_calls = {}
      vim.notify = function(msg, level)
        table.insert(notify_calls, { msg = msg, level = level })
      end

      mermaid_mock._last_callback("/cache/mermaid/stale.png")
      vim.wait(50, function() end)

      assert.spy(popup_spy).was_called(0) -- no popup for stale completion
      assert.are.equal(0, #notify_calls) -- no error either, just silence
      popup_spy:revert()
    end)

    it("returns false when mermaid.render returns nil (not installed)", function()
      mermaid_mock.render = function(_, _, _)
        return nil
      end

      local result = M.create_popup_for_diagram("source", { renderer = "mmdc" })
      assert.is_false(result)
    end)

    it("renders multiple mmdc diagrams sequentially", function()
      -- First render
      mermaid_mock.render = function(_, _, cb)
        mermaid_mock._last_callback = cb
        return { job_id = 42 }
      end

      local r1 = M.create_popup_for_diagram("first", { renderer = "mmdc" })
      assert.is_true(r1)

      -- Complete first job
      local popup_spy = require("luassert.spy").on(M, "show_image_popup")
      mermaid_mock._last_callback("/cache/first.png")
      vim.wait(50, function() end)
      assert.spy(popup_spy).was_called(1)

      -- Second render (simulates moving to different diagram)
      M.close_popup()
      vim.wait(100, function() end)

      mermaid_mock.render = function(_, _, cb)
        mermaid_mock._last_callback = cb
        return { job_id = 43 }
      end

      popup_spy:clear()
      local r2 = M.create_popup_for_diagram("second", { renderer = "mmdc" })
      assert.is_true(r2)

      mermaid_mock._last_callback("/cache/second.png")
      vim.wait(50, function() end)
      assert.spy(popup_spy).was_called(1)
      assert.spy(popup_spy).was_called_with("/cache/second.png", nil)
      popup_spy:revert()
    end)
  end)

  -- ── result without file_path or job_id ──────────────────────────

  describe("malformed render result", function()
    it("returns false when result has neither file_path nor job_id", function()
      mermaid_mock.render = function()
        return {} -- empty table
      end

      local result = M.create_popup_for_diagram("source", { renderer = "mmdr" })
      assert.is_false(result)
    end)

    it("returns false when result.file_path is nil", function()
      mermaid_mock.render = function()
        return { file_path = nil, job_id = nil }
      end

      local result = M.create_popup_for_diagram("source", { renderer = "mmdr" })
      assert.is_false(result)
    end)
  end)

  -- ── options passthrough ─────────────────────────────────────────

  describe("renderer_options passthrough", function()
    it("passes mmdr options through to mermaid.render", function()
      local render_spy = require("luassert.spy").new(mermaid_mock.render)
      mermaid_mock.render = render_spy

      local source = "flowchart TD\n    A --> B"
      local opts = {
        renderer = "mmdr",
        mmdr = { width = 1200, height = 900, fast_text = true },
      }

      M.create_popup_for_diagram(source, opts)

      assert.spy(render_spy).was_called(1)
      local passed_source = render_spy.calls[1].vals[1]
      local passed_opts = render_spy.calls[1].vals[2]
      assert.are.equal(source, passed_source)
      assert.are.equal("mmdr", passed_opts.renderer)
      assert.are.equal(1200, passed_opts.mmdr.width)
    end)

    it("passes through nil mmdr options gracefully", function()
      local render_spy = require("luassert.spy").new(mermaid_mock.render)
      mermaid_mock.render = render_spy

      local opts = { renderer = "mmdr" } -- no mmdr sub-table

      M.create_popup_for_diagram("flowchart LR; A-->B", opts)

      assert.spy(render_spy).was_called(1)
      local passed_opts = render_spy.calls[1].vals[2]
      assert.are.equal("mmdr", passed_opts.renderer)
    end)
  end)
end)
