---Unit tests for utils/logger: is_enabled + level filtering.
---Uses real temp files for write verification instead of mocking io.open
---(selene forbids reassigning standard library globals).

-- Pre-load mock config so logger's require returns our controlled values.
-- The logger calls pcall(require, "sixel-graphics.config") at runtime,
-- so we install a mock that returns a config table we control.
local mock_config = {
  debug = {
    enabled = false,
    level = "info",
    file_path = nil,
  },
}

package.loaded["sixel-graphics.config"] = setmetatable({}, {
  __index = function(_, key)
    return mock_config[key]
  end,
})

local logger = require("sixel-graphics.utils.logger")

describe("logger", function()
  local _hrtime
  local tmp_path

  before_each(function()
    _hrtime = vim.loop.hrtime
    tmp_path = os.tmpname()
    -- Reset mock state
    mock_config.debug = {
      enabled = false,
      level = "info",
      file_path = nil,
    }
  end)

  after_each(function()
    vim.loop.hrtime = _hrtime
    os.remove(tmp_path)
  end)

  -- ── is_enabled ──────────────────────────────────────────────────────

  describe("is_enabled()", function()
    it("returns false when debug.enabled is false", function()
      mock_config.debug.enabled = false
      mock_config.debug.file_path = "/tmp/log.txt"
      assert.is_false(logger.is_enabled())
    end)

    it("returns false when debug.file_path is nil", function()
      mock_config.debug.enabled = true
      mock_config.debug.file_path = nil
      assert.is_false(logger.is_enabled())
    end)

    it("returns false when both enabled and file_path are missing", function()
      mock_config.debug.enabled = false
      mock_config.debug.file_path = nil
      assert.is_false(logger.is_enabled())
    end)

    it("returns true when both enabled==true and file_path is set", function()
      mock_config.debug.enabled = true
      mock_config.debug.file_path = "/tmp/log.txt"
      assert.is_true(logger.is_enabled())
    end)
  end)

  -- ── helpers ─────────────────────────────────────────────────────────

  ---Read all lines from the temp file after logging.
  ---@return string[]
  local function read_log()
    local f = io.open(tmp_path, "r")
    if not f then
      return {}
    end
    local lines = {}
    for line in f:lines() do
      table.insert(lines, line)
    end
    f:close()
    return lines
  end

  ---Set up deterministic hrtime returning sequential values 1s apart.
  local function mock_hrtime_sequential()
    local calls = 0
    vim.loop.hrtime = function()
      calls = calls + 1
      return calls * 1e9 -- 1s, 2s, 3s, ...
    end
  end

  ---Enable logging to the temp file with deterministic time.
  ---@return string path  The temp file path
  local function setup_full_mock()
    mock_config.debug.enabled = true
    mock_config.debug.file_path = tmp_path
    mock_config.debug.level = "debug"
    mock_hrtime_sequential()
    return tmp_path
  end

  -- ── level filtering ─────────────────────────────────────────────────

  describe("level filtering", function()
    it("debug() writes when config level is 'debug'", function()
      setup_full_mock()
      mock_config.debug.level = "debug"
      logger.debug("trace message")
      local lines = read_log()
      assert.are.equal(1, #lines)
      assert.is_not_nil(lines[1]:match("trace message"))
      assert.is_not_nil(lines[1]:match("%[debug%]"))
    end)

    it("debug() is skipped when config level is 'info'", function()
      setup_full_mock()
      mock_config.debug.level = "info"
      logger.debug("should be suppressed")
      local lines = read_log()
      assert.are.equal(0, #lines)
    end)

    it("info() writes when config level is 'info'", function()
      setup_full_mock()
      mock_config.debug.level = "info"
      logger.info("something happened")
      local lines = read_log()
      assert.are.equal(1, #lines)
      assert.is_not_nil(lines[1]:match("something happened"))
      assert.is_not_nil(lines[1]:match("%[info%]"))
    end)

    it("info() is skipped when config level is 'warn'", function()
      setup_full_mock()
      mock_config.debug.level = "warn"
      logger.info("should be suppressed")
      local lines = read_log()
      assert.are.equal(0, #lines)
    end)

    it("warn() writes when config level is 'warn'", function()
      setup_full_mock()
      mock_config.debug.level = "warn"
      logger.warn("caution")
      local lines = read_log()
      assert.are.equal(1, #lines)
      assert.is_not_nil(lines[1]:match("caution"))
      assert.is_not_nil(lines[1]:match("%[warn%]"))
    end)

    it("warn() is skipped when config level is 'error'", function()
      setup_full_mock()
      mock_config.debug.level = "error"
      logger.warn("should be suppressed")
      local lines = read_log()
      assert.are.equal(0, #lines)
    end)

    it("error() writes when config level is 'error'", function()
      setup_full_mock()
      mock_config.debug.level = "error"
      logger.error("disaster")
      local lines = read_log()
      assert.are.equal(1, #lines)
      assert.is_not_nil(lines[1]:match("disaster"))
      assert.is_not_nil(lines[1]:match("%[error%]"))
    end)

    it("error() writes when config level is 'info' (error >= info)", function()
      setup_full_mock()
      mock_config.debug.level = "info"
      logger.error("critical")
      local lines = read_log()
      assert.are.equal(1, #lines)
    end)

    it("all levels write when config level is 'debug'", function()
      setup_full_mock()
      mock_config.debug.level = "debug"

      logger.debug("d")
      logger.info("i")
      logger.warn("w")
      logger.error("e")

      local lines = read_log()
      assert.are.equal(4, #lines)
      assert.is_not_nil(lines[1]:match("%[debug%]"))
      assert.is_not_nil(lines[2]:match("%[info%]"))
      assert.is_not_nil(lines[3]:match("%[warn%]"))
      assert.is_not_nil(lines[4]:match("%[error%]"))
    end)
  end)

  -- ── lazy message functions ──────────────────────────────────────────

  describe("lazy message functions", function()
    it("does not evaluate the function when logging is disabled", function()
      local called = false
      logger.debug(function()
        called = true
        return "expensive message"
      end)
      assert.is_false(called) -- logger was disabled (mock_config default)
    end)

    it("does not evaluate the function when level threshold suppresses it", function()
      setup_full_mock()
      mock_config.debug.level = "info" -- suppress debug

      local called = false
      logger.debug(function()
        called = true
        return "should not run"
      end)

      assert.is_false(called)
      assert.are.equal(0, #read_log())
    end)

    it("evaluates the function and writes when threshold allows", function()
      setup_full_mock()
      mock_config.debug.level = "debug"

      local called = false
      logger.debug(function()
        called = true
        return "computed message"
      end)

      assert.is_true(called)
      local lines = read_log()
      assert.are.equal(1, #lines)
      assert.is_not_nil(lines[1]:match("computed message"))
    end)

    it("catches errors in the message function and does not crash", function()
      setup_full_mock()
      mock_config.debug.level = "debug"

      assert.has_no.errors(function()
        logger.debug(function()
          error("boom inside lazy message")
        end)
      end)

      -- The error in the function prevents the write
      assert.are.equal(0, #read_log())
    end)
  end)

  -- ── timestamp format ────────────────────────────────────────────────

  describe("timestamp format", function()
    it("includes elapsed ms and level tag", function()
      setup_full_mock()
      mock_config.debug.level = "debug"

      logger.debug("hello")

      local lines = read_log()
      -- Format: "+1000.000ms [debug] hello"
      assert.is_not_nil(lines[1]:match("^%+%d+%.%d+ms %[debug%] hello"))
    end)
  end)
end)
