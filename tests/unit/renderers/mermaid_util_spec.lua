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
      vim.fn.filereadable = function(_path)
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
      vim.fn.filereadable = function(_path)
        return 0
      end

      local result = mermaid._check_cache("abc123")
      assert.is_nil(result)
    end)
  end)

  -- ── _build_mmdr_command ─────────────────────────────────────────

  describe("_build_mmdr_command", function()
    it("builds minimal command with required flags only", function()
      local args = mermaid._build_mmdr_command("/tmp/in.mmd", "/cache/out.png", {})
      local joined = table.concat(args, " ")
      -- Required flags present
      assert.is_not_nil(string.find(joined, "^mmdr "))
      assert.is_not_nil(string.find(joined, "%-i /tmp/in%.mmd"))
      assert.is_not_nil(string.find(joined, "%-o /cache/out%.png"))
      assert.is_not_nil(string.find(joined, "%-e png"))
      -- No optional flags
      assert.is_nil(string.find(joined, "%-w "))
      assert.is_nil(string.find(joined, "%-H "))
      assert.is_nil(string.find(joined, "%-c "))
      assert.is_nil(string.find(joined, "%-%-fastText"))
    end)

    it("includes -w when width is set", function()
      local args = mermaid._build_mmdr_command("/tmp/in.mmd", "/cache/out.png", { width = 800 })
      local joined = table.concat(args, " ")
      assert.is_not_nil(string.find(joined, "%-w 800"))
    end)

    it("includes -H when height is set", function()
      local args = mermaid._build_mmdr_command("/tmp/in.mmd", "/cache/out.png", { height = 600 })
      local joined = table.concat(args, " ")
      assert.is_not_nil(string.find(joined, "%-H 600"))
    end)

    it("includes -c when config_file is set", function()
      local args = mermaid._build_mmdr_command("/tmp/in.mmd", "/cache/out.png", {
        config_file = "/home/user/mmdr-config.json",
      })
      local joined = table.concat(args, " ")
      assert.is_not_nil(string.find(joined, "%-c /home/user/mmdr%-config%.json"))
    end)

    it("includes --fastText when fast_text is true", function()
      local args = mermaid._build_mmdr_command("/tmp/in.mmd", "/cache/out.png", { fast_text = true })
      local joined = table.concat(args, " ")
      assert.is_not_nil(string.find(joined, "%-%-fastText"))
    end)

    it("omits --fastText when fast_text is false", function()
      local args = mermaid._build_mmdr_command("/tmp/in.mmd", "/cache/out.png", { fast_text = false })
      local joined = table.concat(args, " ")
      assert.is_nil(string.find(joined, "%-%-fastText"))
    end)

    it("combines all optional flags", function()
      local args = mermaid._build_mmdr_command("/tmp/in.mmd", "/cache/out.png", {
        width = 1200,
        height = 900,
        config_file = "/tmp/theme.json",
        fast_text = true,
      })
      local joined = table.concat(args, " ")
      assert.is_not_nil(string.find(joined, "%-w 1200"))
      assert.is_not_nil(string.find(joined, "%-H 900"))
      assert.is_not_nil(string.find(joined, "%-c /tmp/theme%.json"))
      assert.is_not_nil(string.find(joined, "%-%-fastText"))
    end)

    it("handles nil options gracefully", function()
      local args = mermaid._build_mmdr_command("/tmp/in.mmd", "/cache/out.png", nil)
      local joined = table.concat(args, " ")
      assert.is_not_nil(string.find(joined, "^mmdr "))
      assert.is_nil(string.find(joined, "%-w "))
      assert.is_nil(string.find(joined, "%-H "))
    end)
  end)

  -- ── render (mmdr path, mocked) ──────────────────────────────────

  describe("M.render (mmdr sync path)", function()
    local _executable, _system, _tempname, _writefile, _delete, _notify
    local _original_run_system

    before_each(function()
      _executable = vim.fn.executable
      _system = vim.fn.system
      _tempname = vim.fn.tempname
      _writefile = vim.fn.writefile
      _delete = vim.fn.delete
      _notify = vim.notify

      -- Stub cache directory (inherits mocked stdpath from outer before_each)
      vim.fn.stdpath = function()
        return "/fake-cache"
      end
      vim.fn.mkdir = function() end
      vim.fn.sha256 = function()
        return string.rep("0", 64)
      end
      vim.fn.filereadable = function(_path)
        return 0
      end -- cache miss by default

      -- Reload module
      package.loaded["sixel-graphics.renderers.mermaid"] = nil
      mermaid = require("sixel-graphics.renderers.mermaid")
      _original_run_system = mermaid._run_system
    end)

    after_each(function()
      vim.fn.executable = _executable
      vim.fn.system = _system
      vim.fn.tempname = _tempname
      vim.fn.writefile = _writefile
      vim.fn.delete = _delete
      vim.notify = _notify
      if mermaid then
        mermaid._run_system = _original_run_system
      end
    end)

    it("returns cache hit when file exists", function()
      vim.fn.filereadable = function(_path)
        return 1 -- cached
      end
      vim.fn.executable = function()
        error("should not check executable on cache hit")
      end

      local result = mermaid.render("flowchart LR; A-->B", { renderer = "mmdr" })
      assert.is_not_nil(result)
      assert.is_not_nil(string.find(result.file_path, "%.png$"))
    end)

    it("returns nil when mmdr not installed", function()
      vim.fn.filereadable = function(_path)
        return 0
      end
      vim.fn.executable = function(cmd)
        assert.are.equal("mmdr", cmd)
        return 0 -- not found
      end

      local notifications = {}
      vim.notify = function(msg, level)
        table.insert(notifications, { msg = msg, level = level })
      end

      local result = mermaid.render("source", { renderer = "mmdr" })
      assert.is_nil(result)
      assert.are.equal(1, #notifications)
      assert.is_not_nil(string.find(notifications[1].msg, "mmdr not found"))
      assert.are.equal(vim.log.levels.ERROR, notifications[1].level)
    end)

    it("returns nil when mmdr fails (non-zero exit)", function()
      vim.fn.executable = function()
        return 1
      end
      vim.fn.tempname = function()
        return "/tmp/neoXXXXXX"
      end
      vim.fn.writefile = function() end
      vim.fn.delete = function() end

      mermaid._run_system = function(_cmd)
        return "syntax error in diagram", 1
      end

      local notifications = {}
      vim.notify = function(msg, level)
        table.insert(notifications, { msg = msg, level = level })
      end

      local result = mermaid.render("bad syntax", { renderer = "mmdr" })
      assert.is_nil(result)
      assert.are.equal(1, #notifications)
      assert.is_not_nil(string.find(notifications[1].msg, "mmdr failed"))
      assert.is_not_nil(string.find(notifications[1].msg, "syntax error"))
    end)

    it("returns file_path on successful render", function()
      vim.fn.executable = function()
        return 1
      end
      vim.fn.tempname = function()
        return "/tmp/neoXXXXXX"
      end
      vim.fn.writefile = function() end
      vim.fn.delete = function() end

      -- filereadable: first call (cache check) returns 0, second call (post-render) returns 1
      local call_count = 0
      vim.fn.filereadable = function(_path)
        call_count = call_count + 1
        return call_count >= 2 and 1 or 0
      end

      mermaid._run_system = function(_cmd)
        return "", 0
      end

      local result = mermaid.render("flowchart LR; A-->B", {
        renderer = "mmdr",
        mmdr = { width = 800, fast_text = true },
      })

      assert.is_not_nil(result)
      assert.is_not_nil(string.find(result.file_path, "%.png$"))
      assert.is_not_nil(string.find(result.file_path, "/fake%-cache/sixel%-graphics/mermaid/"))
    end)

    it("notifies and returns nil for mmdc path (not implemented)", function()
      local notifications = {}
      vim.notify = function(msg, level)
        table.insert(notifications, { msg = msg, level = level })
      end

      local result = mermaid.render("source", { renderer = "mmdc" })
      assert.is_nil(result)
      assert.are.equal(1, #notifications)
      assert.is_not_nil(string.find(notifications[1].msg, "not yet implemented"))
    end)

    it("notifies and returns nil for unknown renderer", function()
      local notifications = {}
      vim.notify = function(msg, level)
        table.insert(notifications, { msg = msg, level = level })
      end

      local result = mermaid.render("source", { renderer = "plantuml" })
      assert.is_nil(result)
      assert.are.equal(1, #notifications)
      assert.is_not_nil(string.find(notifications[1].msg, "unknown renderer"))
    end)
  end)
end)
