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

  -- ── hover defaults ──────────────────────────────────────────────

  describe("hover defaults", function()
    it("has all hover keys with correct defaults", function()
      config.setup()
      local hover = config.options.hover
      assert.is_not_nil(hover)
      assert.is_not_nil(hover.images)
      assert.is_true(hover.images.enabled)
      assert.is_not_nil(hover.diagrams)
      assert.is_true(hover.diagrams.enabled)
      assert.are.equal(150, hover.debounce_ms)
      assert.are.equal(0.5, hover.max_screen_fraction)
      assert.are.same({ "markdown" }, hover.filetypes)
    end)

    it("has hover.diagrams.enabled = true by default", function()
      config.setup()
      local diagrams = config.options.hover.diagrams
      assert.is_not_nil(diagrams)
      assert.is_true(diagrams.enabled)
    end)

    it("accepts hover.diagrams.enabled override", function()
      config.setup({
        hover = {
          diagrams = { enabled = false },
        },
      })
      assert.is_false(config.options.hover.diagrams.enabled)
      -- Other hover keys unaffected
      assert.is_true(config.options.hover.images.enabled)
      assert.are.equal(150, config.options.hover.debounce_ms)
    end)

    it("deep-extends hover overrides while keeping non-overridden keys", function()
      config.setup({
        hover = {
          debounce_ms = 300,
        },
      })
      local hover = config.options.hover
      assert.is_true(hover.images.enabled) -- from default
      assert.is_true(hover.diagrams.enabled) -- from default
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

  -- ── hover.images defaults ───────────────────────────────────────

  describe("hover.images defaults", function()
    it("has hover.images.enabled = true by default", function()
      config.setup()
      local images = config.options.hover.images
      assert.is_not_nil(images)
      assert.is_true(images.enabled)
    end)

    it("accepts hover.images.enabled override", function()
      config.setup({
        hover = {
          images = { enabled = false },
        },
      })
      assert.is_false(config.options.hover.images.enabled)
      assert.is_true(config.options.hover.diagrams.enabled) -- unaffected
    end)

    it("deep-extends hover.images without losing other hover keys", function()
      config.setup({
        hover = {
          images = { enabled = false },
          debounce_ms = 300,
        },
      })
      assert.is_false(config.options.hover.images.enabled)
      assert.is_true(config.options.hover.diagrams.enabled) -- from default
      assert.are.equal(300, config.options.hover.debounce_ms)
    end)
  end)

  -- ── debug defaults ──────────────────────────────────────────────

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

  -- ── sixel + popup config ─────────────────────────────────────────

  -- ── renderer_options.mermaid defaults ────────────────────────────

  describe("renderer_options.mermaid defaults", function()
    it("has renderer_options with mermaid key", function()
      config.setup()
      local ro = config.options.renderer_options
      assert.is_not_nil(ro)
      assert.is_not_nil(ro.mermaid)
    end)

    it("default renderer is mmdr", function()
      config.setup()
      assert.are.equal("mmdr", config.options.renderer_options.mermaid.renderer)
    end)

    it("mmdr defaults are correct", function()
      config.setup()
      local mmdr = config.options.renderer_options.mermaid.mmdr
      assert.is_not_nil(mmdr)
      assert.is_nil(mmdr.width)
      assert.is_nil(mmdr.height)
      assert.is_false(mmdr.fast_text)
      assert.is_nil(mmdr.config_file)
    end)

    it("min_popup_width defaults to 40", function()
      config.setup()
      assert.are.equal(40, config.options.renderer_options.mermaid.min_popup_width)
    end)

    it("mmdc defaults are correct", function()
      config.setup()
      local mmdc = config.options.renderer_options.mermaid.mmdc
      assert.is_not_nil(mmdc)
      assert.is_nil(mmdc.theme)
      assert.is_nil(mmdc.background)
      assert.is_nil(mmdc.scale)
      assert.is_nil(mmdc.width)
      assert.is_nil(mmdc.height)
      assert.is_nil(mmdc.cli_args)
    end)

    it("deep-extends renderer_options correctly", function()
      config.setup({
        renderer_options = {
          mermaid = {
            renderer = "mmdc",
            mmdr = { width = 800 },
            mmdc = { theme = "dark" },
          },
        },
      })
      local m = config.options.renderer_options.mermaid
      assert.are.equal("mmdc", m.renderer)
      assert.are.equal(800, m.mmdr.width)
      assert.is_nil(m.mmdr.height) -- from default
      assert.is_false(m.mmdr.fast_text) -- from default
      assert.is_nil(m.mmdr.config_file) -- from default
      assert.are.equal(40, m.min_popup_width) -- from default
      assert.are.equal("dark", m.mmdc.theme)
      assert.is_nil(m.mmdc.background) -- from default
      assert.is_nil(m.mmdc.scale) -- from default
      assert.is_nil(m.mmdc.width) -- from default
      assert.is_nil(m.mmdc.height) -- from default
      assert.is_nil(m.mmdc.cli_args) -- from default
    end)
  end)

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

  -- ── validation ──────────────────────────────────────────────────

  describe("validation", function()
    local _notify
    local notifications

    before_each(function()
      _notify = vim.notify
      notifications = {}
      vim.notify = function(msg, level)
        table.insert(notifications, { msg = msg, level = level })
      end
    end)

    after_each(function()
      vim.notify = _notify
    end)

    it("accepts valid config without errors", function()
      config.setup({ scale = 2.0, max_width = 80 })
      assert.are.equal(0, #notifications)
    end)

    it("accepts nil optional fields without errors", function()
      config.setup({ max_width = nil, max_height = nil })
      assert.are.equal(0, #notifications)
    end)

    it("rejects wrong type for enabled", function()
      config.setup({ enabled = "yes" })
      assert.are.equal(1, #notifications)
      assert.match("sixel%-graphics%.enabled:", notifications[1].msg)
      assert.are.equal(vim.log.levels.ERROR, notifications[1].level)
    end)

    it("rejects wrong type for scale", function()
      config.setup({ scale = "big" })
      assert.are.equal(1, #notifications)
      assert.match("sixel%-graphics%.scale:", notifications[1].msg)
    end)

    it("rejects negative scale", function()
      config.setup({ scale = -0.5 })
      assert.are.equal(1, #notifications)
      assert.match("expected > 0", notifications[1].msg)
    end)

    it("rejects zero scale", function()
      config.setup({ scale = 0 })
      assert.are.equal(1, #notifications)
      assert.match("expected > 0", notifications[1].msg)
    end)

    it("rejects negative max_width", function()
      config.setup({ max_width = -5 })
      assert.are.equal(1, #notifications)
      assert.match("expected > 0", notifications[1].msg)
    end)

    it("rejects non-integer max_width", function()
      config.setup({ max_width = 3.5 })
      assert.are.equal(1, #notifications)
      assert.match("expected integer", notifications[1].msg)
    end)

    it("rejects negative sixel_pixel_scale", function()
      config.setup({ sixel_pixel_scale = -1 })
      assert.are.equal(1, #notifications)
      assert.match("expected > 0", notifications[1].msg)
    end)

    it("rejects non-integer popup_render_delay_ms", function()
      config.setup({ popup_render_delay_ms = 16.7 })
      assert.are.equal(1, #notifications)
      assert.match("expected integer", notifications[1].msg)
    end)

    it("rejects negative cell_width_override", function()
      config.setup({ cell_width_override = -8 })
      assert.are.equal(1, #notifications)
      assert.match("expected > 0", notifications[1].msg)
    end)

    it("accepts integer cell_width_override", function()
      config.setup({ cell_width_override = 16 })
      assert.are.equal(0, #notifications)
    end)

    it("rejects debug as non-table", function()
      config.setup({ debug = "on" })
      assert.are.equal(1, #notifications)
      assert.match("sixel%-graphics%.debug:", notifications[1].msg)
    end)

    it("rejects hover as non-table", function()
      config.setup({ hover = true })
      assert.are.equal(1, #notifications)
      assert.match("sixel%-graphics%.hover:", notifications[1].msg)
    end)

    it("still sets options even when validation fails", function()
      config.setup({ scale = -1 })
      assert.are.equal(-1, config.options.scale) -- value is set, just warned
    end)
  end)
end)
