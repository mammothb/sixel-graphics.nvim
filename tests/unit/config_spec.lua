local config = require("sixel-graphics.config")

describe("config", function()
  before_each(function()
    -- Reset to a known state before each test
    config.setup()
  end)

  describe("defaults", function()
    it("has expected default values", function()
      assert.is_true(config.defaults.enabled)
      assert.is_nil(config.defaults.max_width)
      assert.is_nil(config.defaults.max_height)
      assert.are.equal(1.0, config.defaults.scale)
      assert.are.equal(0, config.defaults.y_offset)
      assert.is_nil(config.defaults.cell_width_override)
      assert.is_nil(config.defaults.cell_height_override)
    end)
  end)

  describe("setup()", function()
    it("applies only defaults when no opts given", function()
      config.setup()
      assert.is_true(config.options.enabled)
      assert.is_nil(config.options.max_width)
      assert.is_nil(config.options.max_height)
      assert.are.equal(1.0, config.options.scale)
      assert.are.equal(0, config.options.y_offset)
    end)

    it("merges user opts over defaults", function()
      config.setup({ max_width = 80, scale = 0.5 })
      assert.is_true(config.options.enabled) -- from default
      assert.are.equal(80, config.options.max_width)
      assert.is_nil(config.options.max_height) -- from default
      assert.are.equal(0.5, config.options.scale)
      assert.are.equal(0, config.options.y_offset) -- from default
    end)

    it("handles nil opts gracefully", function()
      config.setup(nil)
      assert.is_true(config.options.enabled)
      assert.are.equal(1.0, config.options.scale)
    end)

    it("handles empty table opts gracefully", function()
      config.setup({})
      assert.is_true(config.options.enabled)
    end)

    it("accepts cell_width_override and cell_height_override", function()
      config.setup({ cell_width_override = 16, cell_height_override = 32 })
      assert.are.equal(16, config.options.cell_width_override)
      assert.are.equal(32, config.options.cell_height_override)
    end)
  end)

  describe("metatable proxy", function()
    it("auto-initializes options on first access", function()
      config.options = nil
      -- Accessing config.enabled triggers __index which calls setup()
      assert.is_true(config.enabled)
    end)

    it("reads options fields through proxy", function()
      config.setup({ max_width = 60, scale = 2.0 })
      assert.are.equal(60, config.max_width)
      assert.are.equal(2.0, config.scale)
    end)
  end)

  -- ── hover defaults (Step 6) ──────────────────────────────────────

  describe("hover defaults", function()
    it("has all hover keys with correct defaults", function()
      config.setup()
      local hover = config.options.hover
      assert.is_not_nil(hover)
      assert.is_true(hover.enabled)
      assert.are.equal(150, hover.debounce_ms)
      assert.are.equal(0.5, hover.max_screen_fraction)
      assert.are.same({ "markdown" }, hover.filetypes)
    end)

    it("deep-extends hover overrides while keeping non-overridden keys", function()
      config.setup({
        hover = {
          debounce_ms = 300,
        },
      })
      local hover = config.options.hover
      assert.is_true(hover.enabled) -- from default
      assert.are.equal(300, hover.debounce_ms) -- user override
      assert.are.equal(0.5, hover.max_screen_fraction) -- from default
      assert.are.same({ "markdown" }, hover.filetypes) -- from default
    end)

    it("deep-extends filetypes override", function()
      config.setup({
        hover = {
          filetypes = { "markdown", "asciidoc" },
        },
      })
      assert.are.same({ "markdown", "asciidoc" }, config.options.hover.filetypes)
    end)
  end)

  -- ── debug defaults (Step 6) ──────────────────────────────────────

  describe("debug defaults", function()
    it("has all debug keys with correct defaults", function()
      config.setup()
      local debug = config.options.debug
      assert.is_not_nil(debug)
      assert.is_false(debug.enabled)
      assert.are.equal("info", debug.level)
      assert.is_nil(debug.file_path)
    end)

    it("merges debug overrides", function()
      config.setup({
        debug = {
          enabled = true,
          file_path = "/tmp/mylog.log",
        },
      })
      local debug = config.options.debug
      assert.is_true(debug.enabled)
      assert.are.equal("/tmp/mylog.log", debug.file_path)
      assert.are.equal("info", debug.level) -- from default
    end)
  end)

  -- ── sixel + popup config (Step 6) ─────────────────────────────────

  describe("sixel config", function()
    it("sixel_pixel_scale defaults to 1.0", function()
      config.setup()
      assert.are.equal(1.0, config.options.sixel_pixel_scale)
    end)

    it("popup_render_delay_ms defaults to 16", function()
      config.setup()
      assert.are.equal(16, config.options.popup_render_delay_ms)
    end)

    it("accepts sixel_pixel_scale override", function()
      config.setup({ sixel_pixel_scale = 0.625 })
      assert.are.equal(0.625, config.options.sixel_pixel_scale)
    end)

    it("accepts popup_render_delay_ms override", function()
      config.setup({ popup_render_delay_ms = 32 })
      assert.are.equal(32, config.options.popup_render_delay_ms)
    end)
  end)
end)
