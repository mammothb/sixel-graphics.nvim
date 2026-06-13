---Tests for init.lua state machine: guard_setup error,
---enable/disable/is_enabled transitions, clear_images delegation.

-- Pre-load mocks to prevent side effects during init.lua loading
package.loaded["sixel-graphics.backends.sixel"] = {
  setup = function() end,
  clear = function() end,
  render = function() return "test-id" end,
  is_sixel_supported = function() return true end,
}
package.loaded["sixel-graphics.utils.term"] = {
  get_size = function() return { cell_width = 10, cell_height = 20, screen_cols = 80, screen_rows = 24 } end,
}
package.loaded["sixel-graphics.processors.magick_cli"] = {
  get_dimensions = function() return { width = 640, height = 480 } end,
  encode_to_sixel = function() return "dummy" end,
  is_available = function() return true end,
}
package.loaded["sixel-graphics.config"] = {
  setup = function() end,
  options = { enabled = true },
}

local M = require("sixel-graphics")

describe("init", function()
  describe("guard_setup", function()
    it("does not throw when has_setup is true", function()
      M.has_setup = true
      -- clear_images uses guard_setup
      assert.has_no.errors(function()
        M.clear_images()
      end)
    end)

    it("throws error when has_setup is false", function()
      M.has_setup = false
      assert.has.errors(function()
        M.clear_images()
      end)
    end)
  end)

  describe("enable / disable / is_enabled", function()
    before_each(function()
      M.has_setup = true
      M.state = {
        enabled = true,
        images = {},
        options = {},
      }
    end)

    it("is_enabled returns true when enabled", function()
      assert.is_true(M.is_enabled())
    end)

    it("is_enabled returns false when has_setup is false", function()
      M.has_setup = false
      assert.is_false(M.is_enabled())
    end)

    it("is_enabled returns false when state.enabled is false", function()
      M.state.enabled = false
      assert.is_false(M.is_enabled())
    end)

    it("is_enabled returns false when state is nil", function()
      M.state = nil
      assert.is_false(M.is_enabled())
    end)

    it("enable() sets state.enabled to true", function()
      M.state.enabled = false
      M.enable()
      assert.is_true(M.state.enabled)
    end)

    it("disable() sets state.enabled to false", function()
      M.state.enabled = true
      M.disable()
      assert.is_false(M.state.enabled)
    end)

    it("enable() re-renders tracked images", function()
      -- Spy on backend.render
      local backend = require("sixel-graphics.backends.sixel")
      local spy = require("luassert.spy").new(function() return "re-rendered-id" end)
      backend.render = spy

      -- Add a rendered image to state
      M.state.images["/tmp/img.png@0,0"] = {
        id = "/tmp/img.png@0,0",
        path = "/tmp/img.png",
        x = 10,
        y = 3,
        width = 40,
        height = 20,
        is_rendered = true,
      }
      -- Add an unrendered image (should NOT be re-rendered)
      M.state.images["/tmp/other.png@5,5"] = {
        id = "/tmp/other.png@5,5",
        path = "/tmp/other.png",
        x = 5,
        y = 5,
        width = 20,
        height = 10,
        is_rendered = false,
      }

      M.state.enabled = false
      M.enable()

      -- Only the rendered image should be re-rendered
      assert.spy(spy).was_called(1)
      assert.spy(spy).was_called_with("/tmp/img.png", 10, 3, 40, 20)
    end)

    it("enable() does not throw when state has no images", function()
      M.state.enabled = false
      M.state.images = {}
      assert.has_no.errors(function()
        M.enable()
      end)
    end)
  end)

  describe("clear_images", function()
    before_each(function()
      M.has_setup = true
      M.state = { enabled = true, images = {} }
    end)

    it("delegates to backend.clear() without arguments", function()
      local backend = require("sixel-graphics.backends.sixel")
      local clear_called = false
      backend.clear = function(image_id)
        clear_called = true
        assert.is_nil(image_id) -- clear all
      end

      M.clear_images()
      assert.is_true(clear_called)
    end)
  end)
end)
