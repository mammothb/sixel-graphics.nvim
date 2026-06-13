---Integration tests for magick_cli output parsing: get_format and get_dimensions.
---Stubs vim.fn.system to verify parsing of ImageMagick CLI output
---without requiring actual ImageMagick installation.

-- Helper: creates a stub that returns queued responses for successive calls.
-- Note: vim.v.shell_error is read-only so we can't simulate shell errors here.
-- Error paths are tested via empty-path / non-existent-file guards instead.
local function queued_system(responses)
  local call = 0
  return function(_cmd)
    call = call + 1
    local r = responses[call]
    if not r then
      return ""
    end
    return r.output or ""
  end
end

local proc = require("sixel-graphics.processors.magick_cli")

describe("magick_cli output parsing", function()
  local orig_system

  before_each(function()
    orig_system = vim.fn.system
  end)

  after_each(function()
    vim.fn.system = orig_system
  end)

  -- ====================================================================
  -- get_format
  -- ====================================================================
  describe("get_format", function()
    it("returns lowercase format string from identify output", function()
      vim.fn.system = queued_system({
        { output = "PNG\n" },
      })
      -- Use real test file for filereadable check
      local result = proc.get_format("test.png")
      assert.are.equal("png", result)
    end)

    it("trims trailing whitespace from output", function()
      vim.fn.system = queued_system({
        { output = "JPEG  \n  " },
      })
      local result = proc.get_format("test.png")
      -- %s+$ strips all trailing whitespace (spaces, newlines)
      assert.are.equal("jpeg", result)
    end)

    it("returns nil for non-existent file (filereadable fails)", function()
      vim.fn.system = queued_system({
        { output = "png\n" },
      })
      local result = proc.get_format("/nonexistent/file.png")
      assert.is_nil(result)
    end)

    it("returns nil for empty path", function()
      local result = proc.get_format("")
      assert.is_nil(result)
    end)
  end)

  -- ====================================================================
  -- get_dimensions
  -- ====================================================================
  describe("get_dimensions", function()
    it("parses WxH output into {width, height} table", function()
      vim.fn.system = queued_system({
        { output = "png\n" },
        { output = "640x480\n" },
      })
      local dims = proc.get_dimensions("test.png")
      assert.is_not_nil(dims)
      assert.are.equal(640, dims.width)
      assert.are.equal(480, dims.height)
    end)

    it("handles large resolution", function()
      vim.fn.system = queued_system({
        { output = "png\n" },
        { output = "3840x2160\n" },
      })
      local dims = proc.get_dimensions("test.png")
      assert.are.equal(3840, dims.width)
      assert.are.equal(2160, dims.height)
    end)

    it("handles 1x1 pixel images", function()
      vim.fn.system = queued_system({
        { output = "png\n" },
        { output = "1x1\n" },
      })
      local dims = proc.get_dimensions("test.png")
      assert.are.equal(1, dims.width)
      assert.are.equal(1, dims.height)
    end)

    it("appends [0] to path for GIF files", function()
      -- Use a stateful stub: first call returns format "gif", second returns dimensions.
      -- The dimension command path must include [0] suffix.
      local seen_paths = {}
      vim.fn.system = function(cmd)
        -- cmd is a list: {"magick", "identify", "-format", ..., path}
        -- or v6: {"identify", "-format", ..., path}
        local path_arg = cmd[#cmd] -- last arg is always the path
        table.insert(seen_paths, path_arg)
        if #seen_paths == 1 then
          return "gif\n"
        else
          return "100x100\n"
        end
      end

      local dims = proc.get_dimensions("test.png")
      assert.is_not_nil(dims)
      assert.are.equal(100, dims.width)
      assert.are.equal(100, dims.height)
      -- The second system call should use path with [0] suffix
      assert.is_not_nil(seen_paths[2]:match("%[0%]$"))
    end)

    it("returns nil for non-existent file", function()
      vim.fn.system = queued_system({
        { output = "png\n" },
      })
      local dims = proc.get_dimensions("/nonexistent/file.png")
      assert.is_nil(dims)
    end)

    it("returns nil for empty path", function()
      local dims = proc.get_dimensions("")
      assert.is_nil(dims)
    end)

    it("returns nil when dimension output has leading whitespace", function()
      -- Current implementation uses ^ anchor — leading whitespace breaks parsing.
      -- This documents actual behavior; a future fix could handle trimming.
      vim.fn.system = queued_system({
        { output = "png\n" },
        { output = "  800x600  \n" },
      })
      local dims = proc.get_dimensions("test.png")
      assert.is_nil(dims)
    end)
  end)
end)
