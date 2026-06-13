---@diagnostic disable: missing-fields
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
end)
