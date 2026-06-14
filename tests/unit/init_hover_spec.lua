---Unit tests for init.lua hover/popup functions: close_popup.
---
---Mocks Neovim APIs and markdown integration to isolate logic
---from terminal/filesystem side effects.

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
package.loaded["sixel-graphics.config"] = {
  setup = function() end,
  options = {
    enabled = true,
    scale = 1.0,
    sixel_pixel_scale = 1.0,
    popup_render_delay_ms = 16,
    hover = {
      images = { enabled = true },
      diagrams = { enabled = true },
      debounce_ms = 150,
      max_screen_fraction = 0.5,
      filetypes = { "markdown" },
    },
    debug = {
      enabled = false,
      level = "info",
      file_path = nil,
    },
  },
}

-- Mock the markdown integration
package.loaded["sixel-graphics.integrations.markdown"] = {
  query_buffer_images = function()
    return {}
  end,
  find_image_at_row = function()
    return nil
  end,
}

local M = require("sixel-graphics")

describe("init hover", function()
  -- Save originals for restoration
  local _notify

  before_each(function()
    _notify = vim.notify

    -- Set up state for tests that need it
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
      },
    }
  end)

  after_each(function()
    vim.notify = _notify
  end)

  -- ── close_popup ─────────────────────────────────────────────────────

  describe("close_popup()", function()
    it("does not error when called with no active popup", function()
      -- The active_popup local starts nil after module load.
      -- close_popup() → close_active_popup() should be a safe no-op.
      assert.has_no.errors(function()
        M.close_popup()
      end)
    end)

    it("does not error when called multiple times in succession", function()
      assert.has_no.errors(function()
        M.close_popup()
        M.close_popup()
      end)
    end)
  end)
end)
