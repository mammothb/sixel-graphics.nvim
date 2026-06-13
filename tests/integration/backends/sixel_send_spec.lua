---Integration tests for send_sixel() escape sequence generation.
---Spies on vim.fn.chansend to verify exact escape sequences produced
---without actually writing to the terminal.

local backend = require("sixel-graphics.backends.sixel")
local ESC = "\27"

describe("send_sixel escape sequences", function()
  local captured_calls = {}

  before_each(function()
    captured_calls = {}
    -- Spy on chansend: capture arguments without actually writing to stderr
    vim.fn.chansend = function(fd, data)
      table.insert(captured_calls, { fd = fd, data = data })
    end
    -- Clear tmux environment
    vim.env.TMUX = nil
  end)

  -- Helper to get the last captured data string
  local function last_data()
    return captured_calls[#captured_calls] and captured_calls[#captured_calls].data
  end

  describe("basic sixel output (no tmux)", function()
    it("sends via chansend to stderr", function()
      backend.send_sixel("rawdata", nil, nil)
      assert.are.equal(1, #captured_calls)
      assert.are.equal(vim.v.stderr, captured_calls[1].fd)
    end)

    it("wraps raw data in DCS intro and ST", function()
      backend.send_sixel("rawdata", nil, nil)
      local data = last_data()
      -- Should contain the DCS intro
      assert.is_not_nil(data:match(ESC .. "P"))
      -- Should contain the ST terminator
      assert.is_not_nil(data:match(ESC .. "\\"))
      -- Should contain the inner data
      assert.is_not_nil(data:find("rawdata", 1, true))
    end)

    it("does not double-wrap already DCS-wrapped data", function()
      local already = ESC .. "P0;1;0qsixel" .. ESC .. "\\"
      backend.send_sixel(already, nil, nil)
      local data = last_data()
      -- Should have exactly one DCS intro
      local first_idx = data:find(ESC .. "P", 1, true)
      local second_idx = data:find(ESC .. "P", (first_idx or 0) + 3, true)
      assert.is_nil(second_idx) -- no second DCS intro
    end)

    it("includes cursor save (SCP) and restore (RCP)", function()
      backend.send_sixel("rawdata", nil, nil)
      local data = last_data()
      assert.is_not_nil(data:match(ESC .. "%[s")) -- SCP
      assert.is_not_nil(data:match(ESC .. "%[u")) -- RCP
    end)

    it("cursor save comes before sixel, restore comes after", function()
      backend.send_sixel("TESTDATA", nil, nil)
      local data = last_data()
      local scp_pos = data:find(ESC .. "[s", 1, true)
      local sixel_pos = data:find("TESTDATA", 1, true)
      local rcp_pos = data:find(ESC .. "[u", 1, true)
      assert.is_true(scp_pos < sixel_pos)
      assert.is_true(sixel_pos < rcp_pos)
    end)
  end)

  describe("cursor positioning", function()
    it("includes CSI y;xH when x and y are provided", function()
      backend.send_sixel("rawdata", 10, 5)
      local data = last_data()
      -- CSI row;colH — note 1-indexed: y+1=6, x+1=11
      assert.is_not_nil(data:match(ESC .. "%[6;11H"))
    end)

    it("omits CSI positioning when x is nil", function()
      backend.send_sixel("rawdata", nil, 5)
      local data = last_data()
      -- Should not contain CSI y;xH pattern
      assert.is_nil(data:match(ESC .. "%[%d+;%d+H"))
    end)

    it("omits CSI positioning when y is nil", function()
      backend.send_sixel("rawdata", 10, nil)
      local data = last_data()
      assert.is_nil(data:match(ESC .. "%[%d+;%d+H"))
    end)

    it("converts 0-indexed coordinates to 1-indexed in CSI", function()
      backend.send_sixel("rawdata", 0, 0)
      local data = last_data()
      -- (0,0) 0-indexed → (1,1) 1-indexed
      assert.is_not_nil(data:match(ESC .. "%[1;1H"))
    end)
  end)

  describe("inside tmux", function()
    before_each(function()
      vim.env.TMUX = "/tmp/tmux-1000/default"
      -- Stub system() for tmux passthrough detection
      vim.fn.system = function(cmd)
        if type(cmd) == "table" then
          local cmd_str = table.concat(cmd, " ")
          if cmd_str:match("display.*client_termfeatures") then
            return "clipboard,focus,sixel,title"
          elseif cmd_str:match("display%-message.*pane_left") then
            return "5 3" -- pane at column 5, row 3
          elseif cmd_str:match("show.*allow%-passthrough") then
            return "on"
          end
        end
        return ""
      end
    end)

    after_each(function()
      vim.env.TMUX = nil
    end)

    it("wraps entire sequence in tmux passthrough DCS", function()
      backend.send_sixel("rawdata", 10, 5)
      local data = last_data()
      -- Outer wrapper: \ePtmux;...\e\\
      assert.is_not_nil(data:match("^" .. ESC .. "Ptmux;"))
      assert.is_not_nil(data:match(ESC .. "\\$"))
    end)

    it("doubles all inner ESC bytes within passthrough", function()
      backend.send_sixel("rawdata", nil, nil)
      local data = last_data()
      -- Strip the outer \ePtmux; prefix and final \e\\ suffix
      local body = data:gsub("^" .. ESC .. "Ptmux;", ""):gsub(ESC .. "\\$", "")
      -- Every inner ESC should appear as \e\e (doubled)
      -- Count doubled ESCs: original inner had SCP(\e[s) + DCS intro(\eP) + ST(\e\\) + RCP(\e[u) = 4 ESCs
      -- After doubling: 8 ESCs in body
      local _, count = body:gsub(ESC .. ESC, "")
      assert.are.equal(4, count)
    end)

    it("adds pane offset to cursor coordinates", function()
      backend.send_sixel("rawdata", 10, 5)
      local data = last_data()
      -- Original: (10,5) + pane offset (5,3) = (15,8) → 1-indexed: row=9, col=16
      assert.is_not_nil(data:match(ESC .. ESC .. "%[9;16H"))
    end)

    it("cursor positioning is wrapped inside passthrough", function()
      backend.send_sixel("rawdata", 10, 5)
      local data = last_data()
      -- The CSI H should be preceded by doubled ESC (\e\e) — meaning it's inside the passthrough
      assert.is_not_nil(data:match(ESC .. ESC .. "%[%d+;%d+H"))
    end)
  end)

  describe("nil/empty guard", function()
    it("returns early when data is nil", function()
      backend.send_sixel(nil, 0, 0)
      assert.are.equal(0, #captured_calls)
    end)

    it("returns early when data is empty string", function()
      backend.send_sixel("", 0, 0)
      assert.are.equal(0, #captured_calls)
    end)
  end)
end)
