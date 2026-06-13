local backend = require("sixel-graphics.backends.sixel")

local ESC = "\27"

describe("backends.sixel escape helpers", function()
  describe("_ensure_dcs", function()
    it("wraps plain sixel data with DCS intro and ST terminator", function()
      local result = backend._ensure_dcs("sixeldata")
      assert.is_not_nil(result:match("^" .. ESC .. "P"))
      assert.is_not_nil(result:match(ESC .. "\\$"))
    end)

    it("does not double-wrap data already starting with DCS intro", function()
      local already = ESC .. "P0;1;0qsixeldata" .. ESC .. "\\"
      local result = backend._ensure_dcs(already)
      -- Should still start with exactly one DCS intro (not two)
      assert.are.equal(already, result)
    end)

    it("adds ST terminator if data has DCS intro but no ST", function()
      local partial = ESC .. "P0;1;0qsixeldata"
      local result = backend._ensure_dcs(partial)
      assert.is_not_nil(result:match(ESC .. "\\$"))
      -- Should NOT have prepended another DCS intro
      assert.is_nil(result:match("^" .. ESC .. "P.*" .. ESC .. "P"))
    end)

    it("preserves data content between DCS and ST", function()
      local data = "custom-sixel-payload"
      local result = backend._ensure_dcs(data)
      assert.is_not_nil(result:match("custom%-sixel%-payload"))
    end)
  end)

  describe("_tmux_wrap", function()
    it("wraps data in tmux passthrough DCS", function()
      local inner = ESC .. "Psixel" .. ESC .. "\\"
      local result = backend._tmux_wrap(inner)
      assert.is_not_nil(result:match("^" .. ESC .. "Ptmux;"))
      assert.is_not_nil(result:match(ESC .. "\\$"))
    end)

    it("doubles all ESC bytes within the payload", function()
      local inner = ESC .. "[10;20H" .. ESC .. "Psixel" .. ESC .. "\\"
      local result = backend._tmux_wrap(inner)
      -- After the \ePtmux; prefix and before the final \e\\,
      -- every original ESC should be doubled.
      -- Count ESCs in the wrapped result (excluding the \ePtmux; intro and final \e\\).
      local body = result:gsub("^" .. ESC .. "Ptmux;", ""):gsub(ESC .. "\\$", "")
      -- Each original ESC → \e\e, so 3 original ESCs → 6 ESCs in body
      local _, count = body:gsub(ESC, "")
      assert.are.equal(6, count)
    end)

    it("handles data with no ESC bytes", function()
      local result = backend._tmux_wrap("plaintext")
      assert.is_true(result:find("plaintext", 1, true) ~= nil)
    end)
  end)
end)
