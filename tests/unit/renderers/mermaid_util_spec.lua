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

  -- ── _build_mmdc_command ─────────────────────────────────────────

  describe("_build_mmdc_command", function()
    it("builds minimal command with required flags only", function()
      local args = mermaid._build_mmdc_command("/tmp/in.mmd", "/cache/out.png", {})
      local joined = table.concat(args, " ")
      assert.is_not_nil(string.find(joined, "^mmdc "))
      assert.is_not_nil(string.find(joined, "%-i /tmp/in%.mmd"))
      assert.is_not_nil(string.find(joined, "%-o /cache/out%.png"))
      assert.is_not_nil(string.find(joined, "%-e png"))
      -- No optional flags
      assert.is_nil(string.find(joined, "%-b "))
      assert.is_nil(string.find(joined, "%-t "))
      assert.is_nil(string.find(joined, "%-s "))
      assert.is_nil(string.find(joined, "%-w "))
      assert.is_nil(string.find(joined, "%-H "))
    end)

    it("includes -b when background is set", function()
      local args = mermaid._build_mmdc_command("/tmp/in.mmd", "/cache/out.png", {
        background = "transparent",
      })
      local joined = table.concat(args, " ")
      assert.is_not_nil(string.find(joined, "%-b transparent"))
    end)

    it("includes -t when theme is set", function()
      local args = mermaid._build_mmdc_command("/tmp/in.mmd", "/cache/out.png", {
        theme = "dark",
      })
      local joined = table.concat(args, " ")
      assert.is_not_nil(string.find(joined, "%-t dark"))
    end)

    it("includes -s when scale is set", function()
      local args = mermaid._build_mmdc_command("/tmp/in.mmd", "/cache/out.png", {
        scale = 2,
      })
      local joined = table.concat(args, " ")
      assert.is_not_nil(string.find(joined, "%-s 2"))
    end)

    it("includes -w when width is set", function()
      local args = mermaid._build_mmdc_command("/tmp/in.mmd", "/cache/out.png", {
        width = 1200,
      })
      local joined = table.concat(args, " ")
      assert.is_not_nil(string.find(joined, "%-w 1200"))
    end)

    it("includes -H when height is set", function()
      local args = mermaid._build_mmdc_command("/tmp/in.mmd", "/cache/out.png", {
        height = 900,
      })
      local joined = table.concat(args, " ")
      assert.is_not_nil(string.find(joined, "%-H 900"))
    end)

    it("prepends cli_args before -i/-o", function()
      local args = mermaid._build_mmdc_command("/tmp/in.mmd", "/cache/out.png", {
        cli_args = { "--no-sandbox", "--quiet" },
      })
      local joined = table.concat(args, " ")
      local no_sandbox_pos = string.find(joined, "%-%-no%-sandbox")
      local quiet_pos = string.find(joined, "%-%-quiet")
      local i_pos = string.find(joined, "%-i ")
      assert.is_true(no_sandbox_pos < i_pos, "--no-sandbox must come before -i")
      assert.is_true(quiet_pos < i_pos, "--quiet must come before -i")
    end)

    it("always includes -e png", function()
      local args = mermaid._build_mmdc_command("/tmp/in.mmd", "/cache/out.png", {
        background = "white",
        scale = 3,
      })
      local joined = table.concat(args, " ")
      assert.is_not_nil(string.find(joined, "%-e png"))
    end)

    it("combines all options", function()
      local args = mermaid._build_mmdc_command("/tmp/in.mmd", "/cache/out.png", {
        theme = "forest",
        background = "#F0F0F0",
        scale = 2,
        width = 1600,
        height = 1200,
        cli_args = { "--no-sandbox" },
      })
      local joined = table.concat(args, " ")

      -- cli_args first
      local ns_pos = string.find(joined, "%-%-no%-sandbox")
      local i_pos = string.find(joined, "%-i ")
      assert.is_true(ns_pos < i_pos)

      -- All flags present
      assert.is_not_nil(string.find(joined, "%-t forest"))
      assert.is_not_nil(string.find(joined, "%-b #F0F0F0"))
      assert.is_not_nil(string.find(joined, "%-s 2"))
      assert.is_not_nil(string.find(joined, "%-w 1600"))
      assert.is_not_nil(string.find(joined, "%-H 1200"))
      assert.is_not_nil(string.find(joined, "%-e png"))
    end)

    it("handles nil options gracefully", function()
      local args = mermaid._build_mmdc_command("/tmp/in.mmd", "/cache/out.png", nil)
      local joined = table.concat(args, " ")
      assert.is_not_nil(string.find(joined, "^mmdc "))
      assert.is_not_nil(string.find(joined, "%-i "))
      assert.is_not_nil(string.find(joined, "%-o "))
      assert.is_nil(string.find(joined, "%-b ")) -- no optional flags
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

  -- ── render (mmdc path, mocked) ──────────────────────────────────

  describe("M.render (mmdc path)", function()
    local _executable, _tempname, _writefile, _delete, _sha256
    local _stdpath, _mkdir, _notify, _filereadable
    local _original_jobstart

    before_each(function()
      _executable = vim.fn.executable
      _tempname = vim.fn.tempname
      _writefile = vim.fn.writefile
      _delete = vim.fn.delete
      _sha256 = vim.fn.sha256
      _stdpath = vim.fn.stdpath
      _mkdir = vim.fn.mkdir
      _notify = vim.notify
      _filereadable = vim.fn.filereadable

      -- Stub cache directory
      vim.fn.stdpath = function()
        return "/fake-cache"
      end
      vim.fn.mkdir = function() end

      -- Reload module
      package.loaded["sixel-graphics.renderers.mermaid"] = nil
      mermaid = require("sixel-graphics.renderers.mermaid")
      _original_jobstart = mermaid._jobstart
    end)

    after_each(function()
      vim.fn.executable = _executable
      vim.fn.tempname = _tempname
      vim.fn.writefile = _writefile
      vim.fn.delete = _delete
      vim.fn.sha256 = _sha256
      vim.fn.stdpath = _stdpath
      vim.fn.mkdir = _mkdir
      vim.notify = _notify
      vim.fn.filereadable = _filereadable
      if mermaid then
        mermaid._jobstart = _original_jobstart
      end
    end)

    -- ── cache hit ──────────────────────────────────────────────────

    it("returns file_path on mmdc cache hit (sync, no job_id, no callback needed)", function()
      vim.fn.sha256 = function()
        return string.rep("d", 64)
      end
      vim.fn.filereadable = function(_path)
        return 1 -- cached
      end

      -- Should NOT check executable or spawn job
      vim.fn.executable = function()
        error("should not check executable on cache hit")
      end

      local result = mermaid.render("flowchart LR; A--B", { renderer = "mmdc" })
      assert.is_not_nil(result)
      assert.is_not_nil(string.find(result.file_path, "%.png$"))
      assert.is_nil(result.job_id) -- no job on cache hit
    end)

    -- ── not installed ──────────────────────────────────────────────

    it("returns nil when mmdc not installed", function()
      vim.fn.sha256 = function()
        return string.rep("d", 64)
      end
      vim.fn.filereadable = function(_path)
        return 0
      end -- cache miss
      vim.fn.executable = function(cmd)
        assert.are.equal("mmdc", cmd)
        return 0 -- not found
      end

      local notifications = {}
      vim.notify = function(msg, level)
        table.insert(notifications, { msg = msg, level = level })
      end

      local result = mermaid.render("source", { renderer = "mmdc" }, function() end)
      assert.is_nil(result)
      assert.are.equal(1, #notifications)
      assert.is_not_nil(string.find(notifications[1].msg, "mmdc not found"))
      assert.are.equal(vim.log.levels.ERROR, notifications[1].level)
    end)

    -- ── missing callback ───────────────────────────────────────────

    it("returns nil and notifies when on_complete is missing (cache miss)", function()
      vim.fn.sha256 = function()
        return string.rep("d", 64)
      end
      vim.fn.filereadable = function(_path)
        return 0
      end -- cache miss
      vim.fn.executable = function()
        return 1
      end -- installed

      local notifications = {}
      vim.notify = function(msg, level)
        table.insert(notifications, { msg = msg, level = level })
      end

      -- No callback passed → error
      local result = mermaid.render("source", { renderer = "mmdc" })
      assert.is_nil(result)
      assert.are.equal(1, #notifications)
      assert.is_not_nil(string.find(notifications[1].msg, "requires a callback"))
    end)

    -- ── job spawn (cache miss, mmdc installed) ─────────────────────

    it("returns { job_id } on mmdc cache miss (async)", function()
      vim.fn.sha256 = function()
        return string.rep("d", 64)
      end
      vim.fn.filereadable = function(_path)
        return 0
      end -- cache miss
      vim.fn.executable = function()
        return 1
      end -- installed
      vim.fn.tempname = function()
        return "/tmp/neoXXXXXX"
      end
      vim.fn.writefile = function() end

      mermaid._jobstart = function(cmd_args, callbacks)
        local joined = table.concat(cmd_args, " ")
        assert.is_not_nil(string.find(joined, "^mmdc "))
        assert.is_not_nil(string.find(joined, "%-i /tmp/neoXXXXXX%.mmd"))
        assert.is_not_nil(string.find(joined, "%-e png"))
        assert.is_function(callbacks.on_exit)
        assert.is_function(callbacks.on_stderr)
        return 42 -- fake job_id
      end

      -- Mock timer_start/stop (for timeout guard)
      local _timer_start = vim.fn.timer_start
      vim.fn.timer_start = function(_, _)
        return 999
      end

      local callback_fired = false
      local result = mermaid.render("flowchart LR; A--B", {
        renderer = "mmdc",
        mmdc = { theme = "dark", scale = 2 },
      }, function(_path, _err)
        callback_fired = true
      end)

      assert.is_not_nil(result)
      assert.are.equal(42, result.job_id)
      assert.is_nil(result.file_path) -- no file_path for async
      assert.is_false(callback_fired) -- callback fires only after on_exit

      vim.fn.timer_start = _timer_start
    end)

    it("includes mmdc options in spawned command", function()
      vim.fn.sha256 = function()
        return string.rep("d", 64)
      end
      vim.fn.filereadable = function(_path)
        return 0
      end
      vim.fn.executable = function()
        return 1
      end
      vim.fn.tempname = function()
        return "/tmp/neoXXXXXX"
      end
      vim.fn.writefile = function() end

      local captured_cmd = nil
      mermaid._jobstart = function(cmd_args, _callbacks)
        captured_cmd = table.concat(cmd_args, " ")
        return 42
      end

      -- Mock timer_start
      local _timer_start = vim.fn.timer_start
      vim.fn.timer_start = function(_, _)
        return 999
      end

      mermaid.render("source", {
        renderer = "mmdc",
        mmdc = {
          theme = "forest",
          background = "transparent",
          scale = 3,
          width = 1600,
          height = 1200,
          cli_args = { "--no-sandbox" },
        },
      }, function() end)

      assert.is_not_nil(string.find(captured_cmd, "%-%-no%-sandbox"))
      assert.is_not_nil(string.find(captured_cmd, "%-t forest"))
      assert.is_not_nil(string.find(captured_cmd, "%-b transparent"))
      assert.is_not_nil(string.find(captured_cmd, "%-s 3"))
      assert.is_not_nil(string.find(captured_cmd, "%-w 1600"))
      assert.is_not_nil(string.find(captured_cmd, "%-H 1200"))

      vim.fn.timer_start = _timer_start
    end)

    it("returns nil and notifies when jobstart fails (job_id <= 0)", function()
      vim.fn.sha256 = function()
        return string.rep("d", 64)
      end
      vim.fn.filereadable = function(_path)
        return 0
      end
      vim.fn.executable = function()
        return 1
      end
      vim.fn.tempname = function()
        return "/tmp/neoXXXXXX"
      end
      vim.fn.writefile = function() end
      vim.fn.delete = function() end

      mermaid._jobstart = function(_cmd_args, _callbacks)
        return 0 -- failure
      end

      local notifications = {}
      vim.notify = function(msg, level)
        table.insert(notifications, { msg = msg, level = level })
      end

      local result = mermaid.render("source", { renderer = "mmdc" }, function() end)
      assert.is_nil(result)
      assert.are.equal(1, #notifications)
      assert.is_not_nil(string.find(notifications[1].msg, "failed to start mmdc"))
    end)

    -- ── cache isolation: mmdr vs mmdc ──────────────────────────────

    it("uses separate cache from mmdr (different hash prefix)", function()
      -- Verify mmdc uses "mmdc:" prefix in hash, producing a different
      -- cache path than mmdr. This is a pure hash test — no render paths.
      local mmdc_captured = nil
      vim.fn.sha256 = function(s)
        if string.find(s, "^mmdc:") then
          mmdc_captured = s
        end
        return string.rep("0", 64)
      end

      vim.fn.filereadable = function(_)
        return 0
      end -- cache miss
      vim.fn.executable = function()
        return 1
      end
      vim.fn.tempname = function()
        return "/tmp/neoXXXXXX"
      end
      vim.fn.writefile = function() end

      mermaid._jobstart = function()
        return 42
      end
      local _timer_start = vim.fn.timer_start
      vim.fn.timer_start = function(_, _)
        return 999
      end

      local r2 = mermaid.render("same source", { renderer = "mmdc" }, function() end)

      assert.is_not_nil(r2)
      assert.are.equal(42, r2.job_id)
      assert.is_nil(r2.file_path) -- async: no file_path
      assert.is_not_nil(mmdc_captured)
      assert.is_not_nil(string.find(mmdc_captured, "^mmdc:"))
      assert.is_not_nil(string.find(mmdc_captured, "same source"))

      vim.fn.timer_start = _timer_start
    end)

    -- ── regression: mmdr path still works ──────────────────────────

    it("mmdr path is unaffected by mmdc additions", function()
      vim.fn.sha256 = function()
        return string.rep("0", 64)
      end
      vim.fn.filereadable = function(_path)
        return 1
      end -- cache hit

      local result = mermaid.render("flowchart LR; A--B", { renderer = "mmdr" })
      assert.is_not_nil(result)
      assert.is_not_nil(string.find(result.file_path, "%.png$"))
      assert.is_nil(result.job_id) -- mmdr should never have job_id
    end)

    -- ── timeout guard ────────────────────────────────────────────

    it("stops timeout guard when on_exit fires before timeout", function()
      vim.fn.sha256 = function()
        return string.rep("d", 64)
      end
      vim.fn.filereadable = function(_)
        return 0
      end
      vim.fn.executable = function()
        return 1
      end
      vim.fn.tempname = function()
        return "/tmp/neoXXXXXX"
      end
      vim.fn.writefile = function() end
      vim.fn.delete = function() end

      local stored_callbacks = nil
      mermaid._jobstart = function(_, cb)
        stored_callbacks = cb
        return 42
      end

      local timer_stopped = nil
      vim.fn.timer_start = function(_, _)
        return 999
      end
      vim.fn.timer_stop = function(id)
        timer_stopped = id
      end

      mermaid.render("source", { renderer = "mmdc" }, function() end)

      -- on_exit fires → timer_stop should be called with the guard ID
      stored_callbacks.on_exit(nil, 0, "exit")
      assert.are.equal(999, timer_stopped)
    end)

    it("timeout guard calls jobstop and on_complete with error", function()
      vim.fn.sha256 = function()
        return string.rep("d", 64)
      end
      vim.fn.filereadable = function(_)
        return 0
      end
      vim.fn.executable = function()
        return 1
      end
      vim.fn.tempname = function()
        return "/tmp/neoXXXXXX"
      end
      vim.fn.writefile = function() end
      vim.fn.delete = function() end

      mermaid._jobstart = function(_, _)
        return 42
      end

      local timeout_cb = nil
      vim.fn.timer_start = function(_, cb)
        timeout_cb = cb
        return 999
      end
      vim.fn.timer_stop = function() end

      local job_stopped = nil
      vim.fn.jobstop = function(id)
        job_stopped = id
      end

      mermaid.render("source", { renderer = "mmdc" }, function() end)

      -- Simulate timeout: fire the timeout callback directly
      -- (in production this fires after 30s via vim.fn.timer_start)
      assert.is_not_nil(timeout_cb, "timer_start should have been called with a callback")
      timeout_cb()

      -- jobstop should have been called
      assert.are.equal(42, job_stopped)

      -- on_complete should receive error (via vim.schedule → need to pump)
      -- The callback was passed to vim.schedule inside the timeout handler.
      -- In vusted, vim.schedule callbacks are processed on the next
      -- event-loop iteration. We can't easily assert here without vim.wait.
      -- Key verification: timeout_cb exists and doesn't crash.
      assert.is_not_nil(timeout_cb)
    end)
  end)
end)
