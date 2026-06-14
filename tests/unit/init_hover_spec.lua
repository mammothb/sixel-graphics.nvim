---Unit tests for init.lua hover/popup functions:
---check_cursor_on_image, close_popup.
---
---Mocks Neovim APIs and markdown integration to isolate logic
---from terminal/fileystem side effects.

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
      enabled = false, -- don't auto-register CursorMoved; we test functions directly
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
  local _get_current_buf
  local _notify
  local _bo

  before_each(function()
    _get_current_buf = vim.api.nvim_get_current_buf
    _notify = vim.notify
    _bo = vim.bo

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
      },
    }
  end)

  after_each(function()
    vim.api.nvim_get_current_buf = _get_current_buf
    vim.notify = _notify
    vim.bo = _bo
  end)

  -- ── check_cursor_on_image ───────────────────────────────────────────

  describe("check_cursor_on_image()", function()
    it("notifies 'not a markdown buffer' for non-markdown filetype", function()
      vim.api.nvim_get_current_buf = function()
        return 1
      end
      -- vim.bo is a table indexed by buffer number
      vim.bo = setmetatable({}, {
        __index = function(_, buf)
          if buf == 1 then
            return { filetype = "lua" }
          end
          return {}
        end,
      })

      local msg, level = nil, nil
      vim.notify = function(m, l)
        msg = m
        level = l
      end

      M.check_cursor_on_image()

      assert.is_not_nil(msg:match("not a markdown buffer"))
      assert.are.equal(vim.log.levels.INFO, level)
    end)

    it("notifies 'no image on this line' for markdown without match", function()
      vim.api.nvim_get_current_buf = function()
        return 1
      end
      vim.bo = setmetatable({}, {
        __index = function(_, buf)
          if buf == 1 then
            return { filetype = "markdown" }
          end
          return {}
        end,
      })

      -- find_image_at_row already returns nil (from pre-loaded mock)

      local msg, level = nil, nil
      vim.notify = function(m, l)
        msg = m
        level = l
      end

      M.check_cursor_on_image()

      assert.is_not_nil(msg:match("no image on this line"))
      assert.are.equal(vim.log.levels.INFO, level)
    end)

    it("notifies 'image found: url' for markdown with a match", function()
      vim.api.nvim_get_current_buf = function()
        return 1
      end
      vim.bo = setmetatable({}, {
        __index = function(_, buf)
          if buf == 1 then
            return { filetype = "markdown" }
          end
          return {}
        end,
      })

      -- Inject a match into the mock
      local markdown = require("sixel-graphics.integrations.markdown")
      markdown.find_image_at_row = function(_buf)
        return { url = "./cat.png", range = { start_row = 3, start_col = 0, end_row = 3, end_col = 15 } }
      end

      local msg, level = nil, nil
      vim.notify = function(m, l)
        msg = m
        level = l
      end

      M.check_cursor_on_image()

      assert.is_not_nil(msg:match("image found: ./cat%.png"))
      assert.are.equal(vim.log.levels.INFO, level)

      -- Restore
      markdown.find_image_at_row = function()
        return nil
      end
    end)
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
