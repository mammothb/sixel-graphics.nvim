---Integration tests for tmux detection and passthrough helpers.
---Stubs vim.fn.system to verify CLI output parsing logic.
---@diagnostic disable: duplicate-set-field

local backend = require("sixel-graphics.backends.sixel")

describe("tmux detection", function()
  local system_stub

  before_each(function()
    -- Default: no tmux, system returns empty
    vim.env.TMUX = nil
    system_stub = nil
  end)

  after_each(function()
    vim.env.TMUX = nil
    -- Restore original system
    if system_stub then
      vim.fn.system = system_stub
    end
  end)

  describe("tmux_has_sixel_feature()", function()
    it("returns true when client_termfeatures contains 'sixel'", function()
      vim.env.TMUX = "/tmp/tmux-1000/default"
      vim.fn.system = function()
        return "clipboard,focus,sixel,title"
      end
      assert.is_true(backend.tmux_has_sixel_feature())
    end)

    it("returns true when 'sixel' is the only feature", function()
      vim.env.TMUX = "/tmp/tmux-1000/default"
      vim.fn.system = function()
        return "sixel"
      end
      assert.is_true(backend.tmux_has_sixel_feature())
    end)

    it("returns false when client_termfeatures does not contain 'sixel'", function()
      vim.env.TMUX = "/tmp/tmux-1000/default"
      vim.fn.system = function()
        return "clipboard,focus,title"
      end
      assert.is_false(backend.tmux_has_sixel_feature())
    end)

    it("returns false when client_termfeatures is empty", function()
      vim.env.TMUX = "/tmp/tmux-1000/default"
      vim.fn.system = function()
        return ""
      end
      assert.is_false(backend.tmux_has_sixel_feature())
    end)

    it("returns false when not in tmux (TMUX env unset)", function()
      vim.env.TMUX = nil
      vim.fn.system = function()
        return "sixel"
      end
      assert.is_false(backend.tmux_has_sixel_feature())
    end)

    it("returns false when system() call fails (pcall guard)", function()
      vim.env.TMUX = "/tmp/tmux-1000/default"
      vim.fn.system = function()
        error("command not found")
      end
      assert.is_false(backend.tmux_has_sixel_feature())
    end)
  end)

  describe("tmux_has_passthrough()", function()
    it("returns true when passthrough is 'on'", function()
      vim.env.TMUX = "/tmp/tmux-1000/default"
      vim.fn.system = function()
        return "on"
      end
      assert.is_true(backend.tmux_has_passthrough())
    end)

    it("returns true when passthrough is 'all'", function()
      vim.env.TMUX = "/tmp/tmux-1000/default"
      vim.fn.system = function()
        return "all"
      end
      assert.is_true(backend.tmux_has_passthrough())
    end)

    it("returns false when passthrough is 'off'", function()
      vim.env.TMUX = "/tmp/tmux-1000/default"
      vim.fn.system = function()
        return "off"
      end
      assert.is_false(backend.tmux_has_passthrough())
    end)

    it("returns false when passthrough value is unrecognized", function()
      vim.env.TMUX = "/tmp/tmux-1000/default"
      vim.fn.system = function()
        return "disabled"
      end
      assert.is_false(backend.tmux_has_passthrough())
    end)

    it("returns false when not in tmux", function()
      vim.env.TMUX = nil
      vim.fn.system = function()
        return "on"
      end
      assert.is_false(backend.tmux_has_passthrough())
    end)

    it("handles system() failure gracefully", function()
      vim.env.TMUX = "/tmp/tmux-1000/default"
      vim.fn.system = function()
        error("command failed")
      end
      assert.is_false(backend.tmux_has_passthrough())
    end)
  end)

  describe("get_tmux_pane_offset()", function()
    it("returns 0,0 when not in tmux", function()
      vim.env.TMUX = nil
      local x, y = backend.get_tmux_pane_offset()
      assert.are.equal(0, x)
      assert.are.equal(0, y)
    end)

    it("parses 'left top' from tmux output", function()
      vim.env.TMUX = "/tmp/tmux-1000/default"
      vim.fn.system = function()
        return "15 8"
      end
      local x, y = backend.get_tmux_pane_offset()
      assert.are.equal(15, x)
      assert.are.equal(8, y)
    end)

    it("returns 0,0 when output is unparseable", function()
      vim.env.TMUX = "/tmp/tmux-1000/default"
      vim.fn.system = function()
        return "garbage output"
      end
      local x, y = backend.get_tmux_pane_offset()
      assert.are.equal(0, x)
      assert.are.equal(0, y)
    end)

    it("returns 0,0 when system() fails", function()
      vim.env.TMUX = "/tmp/tmux-1000/default"
      vim.fn.system = function()
        error("no tmux")
      end
      local x, y = backend.get_tmux_pane_offset()
      assert.are.equal(0, x)
      assert.are.equal(0, y)
    end)

    it("handles large offset values", function()
      vim.env.TMUX = "/tmp/tmux-1000/default"
      vim.fn.system = function()
        return "120 60"
      end
      local x, y = backend.get_tmux_pane_offset()
      assert.are.equal(120, x)
      assert.are.equal(60, y)
    end)
  end)

  describe("is_tmux()", function()
    it("returns true when TMUX env is set", function()
      vim.env.TMUX = "/tmp/tmux-1000/default,1234,0"
      assert.is_true(backend.is_tmux())
    end)

    it("returns false when TMUX env is nil", function()
      vim.env.TMUX = nil
      assert.is_false(backend.is_tmux())
    end)
  end)
end)
