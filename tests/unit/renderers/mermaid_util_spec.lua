---Unit tests for mermaid renderer utility functions.
---Mocks vim.fn calls to isolate logic from the filesystem and subprocesses.

describe("mermaid renderer — utilities", function()
  local mermaid

  -- Saved originals for restoration
  local _sha256, _stdpath, _mkdir, _filereadable

  before_each(function()
    _sha256 = vim.fn.sha256
    _stdpath = vim.fn.stdpath
    _mkdir = vim.fn.mkdir
    _filereadable = vim.fn.filereadable

    -- Reload module to pick up any internal state
    package.loaded["sixel-graphics.renderers.mermaid"] = nil
    mermaid = require("sixel-graphics.renderers.mermaid")
  end)

  after_each(function()
    vim.fn.sha256 = _sha256
    vim.fn.stdpath = _stdpath
    vim.fn.mkdir = _mkdir
    vim.fn.filereadable = _filereadable
  end)

  -- ── _compute_hash ─────────────────────────────────────────────────

  describe("_compute_hash", function()
    it("returns a 64-character hex string", function()
      vim.fn.sha256 = function(_s)
        return "abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890"
      end
      local h = mermaid._compute_hash("flowchart LR; A-->B", "mmdr")
      assert.is_string(h)
      assert.are.equal(64, #h)
    end)

    it("includes renderer name in hash input", function()
      local captured = nil
      vim.fn.sha256 = function(s)
        captured = s
        return string.rep("0", 64)
      end
      mermaid._compute_hash("source", "mmdr")
      assert.is_not_nil(string.find(captured, "mmdr"))
      assert.is_not_nil(string.find(captured, "source"))
    end)

    it("uses 'mmdc' in hash input when renderer is mmdc", function()
      local captured = nil
      vim.fn.sha256 = function(s)
        captured = s
        return string.rep("0", 64)
      end
      mermaid._compute_hash("source", "mmdc")
      assert.is_not_nil(string.find(captured, "mmdc"))
    end)

    it("produces different hashes for different sources (same renderer)", function()
      local calls = {}
      vim.fn.sha256 = function(s)
        table.insert(calls, s)
        if #calls == 1 then
          return "a" .. string.rep("a", 63)
        end
        return "b" .. string.rep("b", 63)
      end
      local h1 = mermaid._compute_hash("source A", "mmdr")
      local h2 = mermaid._compute_hash("source B", "mmdr")
      assert.are_not.equal(h1, h2)
    end)

    it("produces different hashes for same source with different renderers", function()
      local calls = {}
      vim.fn.sha256 = function(s)
        table.insert(calls, s)
        if #calls == 1 then
          return "a" .. string.rep("a", 63)
        end
        return "b" .. string.rep("b", 63)
      end
      local h1 = mermaid._compute_hash("same source", "mmdr")
      local h2 = mermaid._compute_hash("same source", "mmdc")
      assert.are_not.equal(h1, h2)
    end)
  end)

  -- ── _get_cache_dir ────────────────────────────────────────────────

  describe("_get_cache_dir", function()
    it("returns path under stdpath('cache')/sixel-graphics/mermaid", function()
      vim.fn.stdpath = function(kind)
        assert.are.equal("cache", kind)
        return "/home/user/.cache/nvim"
      end
      vim.fn.mkdir = function() end

      local dir = mermaid._get_cache_dir()
      assert.are.equal("/home/user/.cache/nvim/sixel-graphics/mermaid", dir)
    end)

    it("creates directory with parents flag", function()
      vim.fn.stdpath = function()
        return "/cache"
      end
      local mkdir_calls = {}
      vim.fn.mkdir = function(path, flag)
        table.insert(mkdir_calls, { path = path, flag = flag })
      end

      local dir = mermaid._get_cache_dir()
      assert.are.equal(1, #mkdir_calls)
      assert.are.equal(dir, mkdir_calls[1].path)
      assert.are.equal("p", mkdir_calls[1].flag)
    end)
  end)

  -- ── _get_cache_path ───────────────────────────────────────────────

  describe("_get_cache_path", function()
    it("appends hash.png to cache directory", function()
      vim.fn.stdpath = function()
        return "/cache"
      end
      vim.fn.mkdir = function() end

      local path = mermaid._get_cache_path("abc123def456")
      assert.are.equal("/cache/sixel-graphics/mermaid/abc123def456.png", path)
    end)
  end)

  -- ── _check_cache ──────────────────────────────────────────────────

  describe("_check_cache", function()
    it("returns path when cached file is readable", function()
      vim.fn.stdpath = function()
        return "/cache"
      end
      vim.fn.mkdir = function() end
      vim.fn.filereadable = function(path)
        return 1
      end

      local result = mermaid._check_cache("abc123")
      assert.are.equal("/cache/sixel-graphics/mermaid/abc123.png", result)
    end)

    it("returns nil when cached file is not readable", function()
      vim.fn.stdpath = function()
        return "/cache"
      end
      vim.fn.mkdir = function() end
      vim.fn.filereadable = function(path)
        return 0
      end

      local result = mermaid._check_cache("abc123")
      assert.is_nil(result)
    end)
  end)
end)
