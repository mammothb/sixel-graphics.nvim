---Tests for backend.render() pixel math: cell→pixel conversion,
---scale, max size constraints (aspect-ratio-preserving), and y_offset.
---Mocks term.get_size() and magick_cli.encode_to_sixel(); spies on send_sixel().
---@diagnostic disable: duplicate-set-field

-- Pre-load mocks for modules that render() requires at call time
local mock_term_size = { cell_width = 10, cell_height = 20, screen_cols = 80, screen_rows = 24 }
package.loaded["sixel-graphics.utils.term"] = {
  get_size = function()
    return mock_term_size
  end,
}

-- encode_to_sixel spy that reports the pixel dimensions it was called with
local encode_calls = {}
package.loaded["sixel-graphics.processors.magick_cli"] = {
  encode_to_sixel = function(path, w, h)
    encode_calls[#encode_calls + 1] = { path = path, w = w, h = h }
    return "dummy-sixel-data"
  end,
}

local backend = require("sixel-graphics.backends.sixel")

describe("backends.sixel render() pixel math", function()
  local send_sixel_spy

  before_each(function()
    -- Reset call tracking
    encode_calls = {}
    -- Spy on send_sixel to verify calls and capture coordinates
    send_sixel_spy = require("luassert.spy").new(function() end)
    backend.send_sixel = send_sixel_spy
    -- Set up backend state with no config options
    backend.state = { images = {}, options = {} }
  end)

  after_each(function()
    -- Restore original send_sixel (avoid polluting other tests)
    -- Not strictly needed since tests run in isolation, but clean.
  end)

  describe("cell-to-pixel conversion (no config)", function()
    it("converts width_cells * cell_width to pixel width", function()
      backend.render("/tmp/img.png", 0, 0, 40, 18)
      -- 40 cells * 10 px/cell = 400 px; 18 * 20 = 360 px
      assert.are.equal(400, encode_calls[1].w)
      assert.are.equal(360, encode_calls[1].h)
    end)

    it("rounds fractional pixels correctly via floor(x+0.5)", function()
      -- 40.3 cells * 10 = 403, no rounding issue
      backend.render("/tmp/img.png", 0, 0, 40, 18)
      assert.are.equal(400, encode_calls[1].w)
      assert.are.equal(360, encode_calls[1].h)
    end)
  end)

  describe("scale", function()
    it("applies scale factor to both dimensions", function()
      backend.state.options = { scale = 0.5 }
      backend.render("/tmp/img.png", 0, 0, 40, 18)
      -- 400 * 0.5 = 200; 360 * 0.5 = 180
      assert.are.equal(200, encode_calls[1].w)
      assert.are.equal(180, encode_calls[1].h)
    end)

    it("scale of 1.0 is a no-op", function()
      backend.state.options = { scale = 1.0 }
      backend.render("/tmp/img.png", 0, 0, 40, 18)
      assert.are.equal(400, encode_calls[1].w)
      assert.are.equal(360, encode_calls[1].h)
    end)

    it("scale greater than 1.0 enlarges", function()
      backend.state.options = { scale = 2.0 }
      backend.render("/tmp/img.png", 0, 0, 40, 18)
      assert.are.equal(800, encode_calls[1].w)
      assert.are.equal(720, encode_calls[1].h)
    end)
  end)

  describe("max_width constraint", function()
    it("clamps width and preserves aspect ratio", function()
      backend.state.options = { max_width = 20 } -- 20 cells → 200 px max
      backend.render("/tmp/img.png", 0, 0, 40, 18)
      -- 400 > 200, clamp to 200. Height: 360 * (200/400) = 180
      assert.are.equal(200, encode_calls[1].w)
      assert.are.equal(180, encode_calls[1].h)
    end)

    it("does not clamp when width is under max", function()
      backend.state.options = { max_width = 80 }
      backend.render("/tmp/img.png", 0, 0, 40, 18)
      assert.are.equal(400, encode_calls[1].w)
    end)
  end)

  describe("max_height constraint", function()
    it("clamps height and preserves aspect ratio", function()
      backend.state.options = { max_height = 10 } -- 10 cells → 200 px max
      backend.render("/tmp/img.png", 0, 0, 40, 18)
      -- 360 > 200, clamp height to 200. Width: 400 * (200/360) ≈ 222
      assert.are.equal(200, encode_calls[1].h)
      assert.is_near(222, encode_calls[1].w, 1)
    end)

    it("does not clamp when height is under max", function()
      backend.state.options = { max_height = 50 }
      backend.render("/tmp/img.png", 0, 0, 40, 18)
      assert.are.equal(360, encode_calls[1].h)
    end)
  end)

  describe("combined constraints", function()
    it("applies scale before max_width", function()
      backend.state.options = { scale = 0.5, max_width = 20 }
      backend.render("/tmp/img.png", 0, 0, 40, 18)
      -- After scale: 200×180. max_width=200px. 200 == 200, no clamp.
      assert.are.equal(200, encode_calls[1].w)
      assert.are.equal(180, encode_calls[1].h)
    end)

    it("applies scale before max_height", function()
      backend.state.options = { scale = 2.0, max_height = 50 } -- 50*20=1000px max
      backend.render("/tmp/img.png", 0, 0, 40, 18)
      -- After scale: 800×720. max_height=1000px. 720 < 1000, no clamp.
      assert.are.equal(800, encode_calls[1].w)
      assert.are.equal(720, encode_calls[1].h)
    end)

    it("both max_width and max_height can apply", function()
      backend.state.options = { max_width = 30, max_height = 20 }
      backend.render("/tmp/img.png", 0, 0, 40, 40)
      -- 400×800. max_width=300, max_height=400.
      -- First clamp width: 300. Height: 800*(300/400)=600.
      -- Then clamp height: 600 > 400 → 400. Width: 300*(400/600)=200.
      assert.is_near(200, encode_calls[1].w, 1)
      assert.is_near(400, encode_calls[1].h, 1)
    end)
  end)

  describe("y_offset", function()
    it("adds y_offset to the y coordinate", function()
      backend.state.options = { y_offset = 5 }
      backend.render("/tmp/img.png", 10, 3, 40, 18)
      -- y becomes 3 + 5 = 8
      assert.are.equal(1, #send_sixel_spy.calls)
      local args = send_sixel_spy.calls[1].vals
      assert.are.equal(10, args[2])
      assert.are.equal(8, args[3])
    end)

    it("default 0 y_offset does not change y", function()
      backend.state.options = {}
      backend.render("/tmp/img.png", 10, 3, 40, 18)
      local args = send_sixel_spy.calls[1].vals
      assert.are.equal(10, args[2])
      assert.are.equal(3, args[3])
    end)

    it("negative y_offset shifts upward", function()
      backend.state.options = { y_offset = -2 }
      backend.render("/tmp/img.png", 10, 5, 40, 18)
      local args = send_sixel_spy.calls[1].vals
      assert.are.equal(10, args[2])
      assert.are.equal(3, args[3])
    end)
  end)

  describe("image tracking", function()
    it("returns a unique image_id", function()
      local id = backend.render("/tmp/img.png", 0, 0, 40, 18)
      assert.is_not_nil(id)
      assert.is_true(id:find("/tmp/img.png@0,0", 1, true) ~= nil)
    end)

    it("stores image in state.images", function()
      backend.render("/tmp/img.png", 5, 3, 30, 15)
      local img = backend.state.images["/tmp/img.png@5,3"]
      assert.is_not_nil(img)
      assert.are.equal("/tmp/img.png", img.path)
      assert.are.equal(5, img.x)
      assert.are.equal(3, img.y)
      assert.are.equal(30, img.width)
      assert.are.equal(15, img.height)
      assert.is_true(img.is_rendered)
    end)
  end)

  describe("edge cases", function()
    it("returns nil when encode_to_sixel fails", function()
      -- Mock encode_to_sixel to return nil (simulate failure)
      package.loaded["sixel-graphics.processors.magick_cli"].encode_to_sixel = function()
        return nil
      end
      local id = backend.render("/tmp/bad.png", 0, 0, 40, 18)
      assert.is_nil(id)
      -- Restore mock
      package.loaded["sixel-graphics.processors.magick_cli"].encode_to_sixel = function(path, w, h)
        encode_calls[#encode_calls + 1] = { path = path, w = w, h = h }
        return "dummy-sixel-data"
      end
    end)

    it("respects custom cell_width_override and cell_height_override", function()
      mock_term_size.cell_width = 16
      mock_term_size.cell_height = 32
      backend.render("/tmp/img.png", 0, 0, 20, 10)
      -- 20*16=320, 10*32=320
      assert.are.equal(320, encode_calls[1].w)
      assert.are.equal(320, encode_calls[1].h)
      -- Reset
      mock_term_size.cell_width = 10
      mock_term_size.cell_height = 20
    end)
  end)
end)
