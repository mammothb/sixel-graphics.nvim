---Unit tests for the LRU cache module.
---No mocking needed — the cache is pure Lua, no vim.fn dependencies.

describe("cache — LRU", function()
  local Cache

  before_each(function()
    package.loaded["sixel-graphics.utils.cache"] = nil
    Cache = require("sixel-graphics.utils.cache")
  end)

  describe("new", function()
    it("creates an empty cache", function()
      local c = Cache.new(5)
      local s = c:stats()
      assert.are.equal(0, s.size)
      assert.are.equal(0, s.hits)
      assert.are.equal(0, s.misses)
    end)

    it("rejects max_entries = 0", function()
      assert.has_error(function()
        Cache.new(0)
      end)
    end)

    it("rejects negative max_entries", function()
      assert.has_error(function()
        Cache.new(-1)
      end)
    end)

    it("rejects non-integer max_entries", function()
      assert.has_error(function()
        Cache.new(2.5)
      end)
    end)

    it("rejects non-number max_entries", function()
      assert.has_error(function()
        Cache.new("fifty")
      end)
    end)

    it("accepts max_entries = 1", function()
      local c = Cache.new(1)
      assert.is_not_nil(c)
    end)
  end)

  describe("set and get", function()
    local c

    before_each(function()
      c = Cache.new(5)
    end)

    it("stores and retrieves a value", function()
      c:set("a", "value-a")
      assert.are.equal("value-a", c:get("a"))
    end)

    it("returns nil for missing key and records miss", function()
      local s_before = c:stats()
      assert.is_nil(c:get("nonexistent"))
      local s_after = c:stats()
      assert.are.equal(s_before.misses + 1, s_after.misses)
      assert.are.equal(s_before.hits, s_after.hits)
    end)

    it("overwrites existing key without changing size", function()
      c:set("a", "first")
      c:set("a", "second")
      assert.are.equal(1, c:stats().size)
      assert.are.equal("second", c:get("a"))
    end)

    it("records hit on successful get", function()
      c:set("a", "value")
      local s_before = c:stats()
      c:get("a")
      local s_after = c:stats()
      assert.are.equal(s_before.hits + 1, s_after.hits)
      assert.are.equal(s_before.misses, s_after.misses)
    end)

    it("does not change stats on set()", function()
      local s_before = c:stats()
      c:set("a", "value")
      local s_after = c:stats()
      assert.are.equal(s_before.hits, s_after.hits)
      assert.are.equal(s_before.misses, s_after.misses)
    end)
  end)

  describe("eviction", function()
    it("evicts least-recently-used when capacity exceeded", function()
      local c = Cache.new(3)
      c:set("a", 1) -- LRU order: a
      c:set("b", 2) -- LRU order: a, b
      c:set("c", 3) -- LRU order: a, b, c

      -- Cache is full (3/3). Insert "d", should evict "a" (LRU).
      c:set("d", 4)

      assert.is_nil(c:get("a")) -- evicted
      assert.are.equal(2, c:get("b"))
      assert.are.equal(3, c:get("c"))
      assert.are.equal(4, c:get("d"))
      assert.are.equal(3, c:stats().size)
    end)

    it("get() promotes to most-recently-used, preventing eviction", function()
      local c = Cache.new(3)
      c:set("a", 1)
      c:set("b", 2)
      c:set("c", 3)

      -- Access "a" to make it MRU. LRU is now "b".
      c:get("a")

      -- Insert "d", should evict "b" (now LRU).
      c:set("d", 4)

      assert.are.equal(1, c:get("a")) -- still here (promoted)
      assert.is_nil(c:get("b")) -- evicted
      assert.are.equal(3, c:get("c")) -- still here
      assert.are.equal(4, c:get("d"))
    end)

    it("set() on existing key promotes to MRU without eviction", function()
      local c = Cache.new(3)
      c:set("a", 1)
      c:set("b", 2)
      c:set("c", 3)

      -- "a" is LRU. Update "a" — promotes to MRU. LRU is now "b".
      c:set("a", "updated")

      c:set("d", 4) -- evicts "b"

      assert.are.equal("updated", c:get("a"))
      assert.is_nil(c:get("b"))
      assert.are.equal(3, c:get("c"))
      assert.are.equal(3, c:stats().size)
    end)

    it("evicts in correct LRU order after mixed operations", function()
      local c = Cache.new(3)
      c:set("a", 1) -- LRU: a
      c:set("b", 2) -- LRU: a, b
      c:set("c", 3) -- LRU: a, b, c
      c:get("b") -- LRU: a, c, b (b promoted)
      c:get("a") -- LRU: c, b, a (a promoted)
      -- LRU is now "c"

      c:set("d", 4) -- evicts "c"

      assert.are.equal(1, c:get("a"))
      assert.are.equal(2, c:get("b"))
      assert.is_nil(c:get("c"))
      assert.are.equal(4, c:get("d"))
    end)

    it("single-entry cache evicts itself when overwritten with different key", function()
      local c = Cache.new(1)
      c:set("a", 1)
      c:set("b", 2)

      assert.is_nil(c:get("a"))
      assert.are.equal(2, c:get("b"))
      assert.are.equal(1, c:stats().size)
    end)

    it("does not evict when capacity is not exceeded", function()
      local c = Cache.new(5)
      for i = 1, 5 do
        c:set("k" .. i, i)
      end
      assert.are.equal(5, c:stats().size)
      for i = 1, 5 do
        assert.are.equal(i, c:get("k" .. i))
      end
    end)
  end)

  describe("clear", function()
    it("empties all entries", function()
      local c = Cache.new(5)
      c:set("a", 1)
      c:set("b", 2)
      c:clear()
      assert.are.equal(0, c:stats().size)
      assert.is_nil(c:get("a"))
      assert.is_nil(c:get("b"))
    end)

    it("resets stats to zero", function()
      local c = Cache.new(5)
      c:set("a", 1)
      c:get("a") -- hit
      c:get("missing") -- miss
      c:clear()
      local s = c:stats()
      assert.are.equal(0, s.size)
      assert.are.equal(0, s.hits)
      assert.are.equal(0, s.misses)
    end)

    it("is idempotent", function()
      local c = Cache.new(5)
      c:clear()
      c:clear()
      local s = c:stats()
      assert.are.equal(0, s.size)
    end)
  end)

  describe("stats", function()
    it("returns size, hits, and misses", function()
      local c = Cache.new(10)
      local s = c:stats()
      assert.is_table(s)
      assert.is_number(s.size)
      assert.is_number(s.hits)
      assert.is_number(s.misses)
    end)

    it("size reflects current entry count", function()
      local c = Cache.new(10)
      assert.are.equal(0, c:stats().size)
      c:set("a", 1)
      assert.are.equal(1, c:stats().size)
      c:set("b", 2)
      assert.are.equal(2, c:stats().size)
      c:set("a", "updated") -- overwrite, no size change
      assert.are.equal(2, c:stats().size)
    end)

    it("hits increments only on get() success", function()
      local c = Cache.new(10)
      c:set("a", 1)
      c:get("a")
      c:get("a")
      assert.are.equal(2, c:stats().hits)
    end)

    it("misses increments only on get() failure", function()
      local c = Cache.new(10)
      c:get("nope")
      c:get("nope")
      c:get("also-nope")
      assert.are.equal(0, c:stats().hits)
      assert.are.equal(3, c:stats().misses)
    end)
  end)

  describe("multiple instances", function()
    it("are independent", function()
      local c1 = Cache.new(2)
      local c2 = Cache.new(2)

      c1:set("a", 1)
      c2:set("x", 99)

      assert.are.equal(1, c1:get("a"))
      assert.is_nil(c2:get("a"))
      assert.are.equal(99, c2:get("x"))
      assert.is_nil(c1:get("x"))
    end)

    it("have independent stats", function()
      local c1 = Cache.new(2)
      local c2 = Cache.new(2)

      c1:set("a", 1)
      c1:get("a")
      c2:get("missing")

      local s1 = c1:stats()
      local s2 = c2:stats()
      assert.are.equal(1, s1.hits)
      assert.are.equal(0, s1.misses)
      assert.are.equal(0, s2.hits)
      assert.are.equal(1, s2.misses)
    end)
  end)
end)
