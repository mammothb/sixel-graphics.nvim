---Integration tests for mermaid renderer using real mmdr binary.
---Requires mmdr to be on PATH.

describe("mermaid renderer — integration (real mmdr)", function()
  local mermaid = require("sixel-graphics.renderers.mermaid")

  -- Ensure cache directory exists before any test (belt-and-suspenders:
  -- _get_cache_dir() creates it too, but if stdpath("cache") parent
  -- chain is missing on some systems, this guarantees it upfront).
  before_each(function()
    local cache_dir = vim.fn.stdpath("cache") .. "/sixel-graphics/mermaid"
    vim.fn.mkdir(cache_dir, "p")
  end)

  it("renders a simple flowchart to a PNG file", function()
    local source = "flowchart LR\n    A[Start] --> B[End]"

    local result = mermaid.render(source, { renderer = "mmdr" })
    assert.is_not_nil(result, "render should return a result")
    assert.is_not_nil(result.file_path, "result should have file_path")
    assert.is_not_nil(
      string.find(result.file_path, "%.png$"),
      "file_path should be a .png: " .. tostring(result.file_path)
    )

    -- Verify the file exists and is non-empty
    local path = result.file_path
    assert.are.equal(1, vim.fn.filereadable(path), "output file should exist: " .. path)
    local size = vim.fn.getfsize(path)
    assert.is_true(size > 0, "output file should not be empty; got " .. tostring(size) .. " bytes")
  end)

  it("caches repeated renders of the same source", function()
    local source = "flowchart TD\n    X --> Y --> Z"

    local r1 = mermaid.render(source, { renderer = "mmdr" })
    assert.is_not_nil(r1)

    -- Second render should return the same path from cache
    local r2 = mermaid.render(source, { renderer = "mmdr" })
    assert.is_not_nil(r2)
    assert.are.equal(r1.file_path, r2.file_path)
  end)

  it("renders with width and fast_text options", function()
    local source = "flowchart LR\n    A --> B"

    local result = mermaid.render(source, {
      renderer = "mmdr",
      mmdr = {
        width = 400,
        height = 300,
        fast_text = true,
      },
    })
    assert.is_not_nil(result)
    assert.are.equal(1, vim.fn.filereadable(result.file_path))
    local size = vim.fn.getfsize(result.file_path)
    assert.is_true(size > 0)
  end)

  it("handles invalid diagram syntax without crashing", function()
    local source = "this is not valid mermaid @@@"

    local result = mermaid.render(source, { renderer = "mmdr" })
    -- mmdr may exit non-zero or produce a blank PNG — either way,
    -- the render function should not crash.
    -- If it returns a path, the file must exist.
    if result then
      assert.are.equal(1, vim.fn.filereadable(result.file_path))
    end
  end)
end)

-- ── mmdc integration tests ─────────────────────────────────────────

describe("mermaid renderer — integration (real mmdc)", function()
  local mermaid = require("sixel-graphics.renderers.mermaid")

  -- Skip if mmdc not installed
  if vim.fn.executable("mmdc") == 0 then
    vim.notify("SKIP: mmdc not installed — skipping mmdc integration tests", vim.log.levels.WARN)
    return
  end

  before_each(function()
    local cache_dir = vim.fn.stdpath("cache") .. "/sixel-graphics/mermaid"
    vim.fn.mkdir(cache_dir, "p")
  end)

  it("renders a simple flowchart asynchronously via mmdc", function()
    local source = "flowchart LR\n    A[mmdc] --> B[Done]"

    local done = false
    local final_path = nil
    local final_err = nil

    local result = mermaid.render(source, { renderer = "mmdc" }, function(path, err)
      done = true
      final_path = path
      final_err = err
    end)

    -- Cache miss: should return { job_id }
    if result and result.job_id then
      -- Wait for on_exit to fire (mmdc takes 1-5s)
      vim.wait(30000, function()
        return done
      end, 50)

      assert.is_true(done, "on_complete should have been called within 30s")
      assert.is_nil(final_err, "mmdc should not error: " .. tostring(final_err))
      assert.is_not_nil(final_path)
      assert.are.equal(1, vim.fn.filereadable(final_path), "output file should exist: " .. tostring(final_path))
      local size = vim.fn.getfsize(final_path)
      assert.is_true(size > 0, "output file should not be empty; got " .. tostring(size) .. " bytes")
    elseif result and result.file_path then
      -- Cache hit from a previous run: verify file exists
      assert.are.equal(1, vim.fn.filereadable(result.file_path))
      local size = vim.fn.getfsize(result.file_path)
      assert.is_true(size > 0)
    else
      -- result is nil — unexpected failure
      error("render returned nil unexpectedly")
    end
  end)

  it("caches repeated async renders (second call is cache hit)", function()
    local source = "flowchart TD\n    X --> Y"

    -- First render: cache miss, async
    local done = false
    local r1 = mermaid.render(source, { renderer = "mmdc" }, function()
      done = true
    end)

    if r1 and r1.job_id then
      vim.wait(30000, function()
        return done
      end, 50)
      assert.is_true(done, "first render should complete")
    end

    -- Second render: should be cache hit (file_path, no job_id)
    local r2 = mermaid.render(source, { renderer = "mmdc" })
    assert.is_not_nil(r2, "cache hit should return a result")
    assert.is_not_nil(r2.file_path, "cache hit should return file_path")
    assert.is_nil(r2.job_id, "cache hit should not spawn a job")
    assert.are.equal(1, vim.fn.filereadable(r2.file_path))
  end)

  it("renders with mmdc options (theme, background, scale)", function()
    local source = "flowchart LR\n    OptA --> OptB"

    local done = false
    local final_err = nil
    local result = mermaid.render(source, {
      renderer = "mmdc",
      mmdc = {
        theme = "dark",
        background = "white",
        scale = 2,
      },
    }, function(_, err)
      done = true
      final_err = err
    end)

    -- Cache hit: no callback, verify file directly
    if result and result.file_path then
      assert.are.equal(1, vim.fn.filereadable(result.file_path))
      local size = vim.fn.getfsize(result.file_path)
      assert.is_true(size > 0)
      return
    end

    -- Cache miss: wait for async callback
    assert.is_not_nil(result, "render should return { job_id } for cache miss")
    vim.wait(30000, function()
      return done
    end, 50)
    assert.is_true(done, "mmdc with options should complete")
    assert.is_nil(final_err, "mmdc with options should not error: " .. tostring(final_err))
  end)

  it("handles invalid diagram syntax gracefully", function()
    local source = "this is not valid mermaid @@@ #mmdc"

    local done = false
    local result = mermaid.render(source, { renderer = "mmdc" }, function(_, _)
      done = true
    end)

    -- Cache hit from previous test run: no crash, just verify
    if result and result.file_path then
      assert.are.equal(1, vim.fn.filereadable(result.file_path))
      return
    end

    -- Cache miss: wait for async callback
    vim.wait(30000, function()
      return done
    end, 50)
    assert.is_true(done, "callback should fire even for bad syntax")
    -- mmdc may produce an error PNG or exit non-zero — either is handled
  end)

  it("produces different cache keys for same source with mmdr vs mmdc", function()
    local source = "flowchart LR\n    A --> B"

    -- Render with mmdr
    local r_mmdr = mermaid.render(source, { renderer = "mmdr" })
    assert.is_not_nil(r_mmdr)
    assert.is_not_nil(r_mmdr.file_path)

    -- Render with mmdc (may be cache hit if already rendered above)
    local r_mmdc = mermaid.render(source, { renderer = "mmdc" })

    if r_mmdc and r_mmdc.file_path then
      -- Cache hit: paths must differ
      assert.are_not.equal(r_mmdr.file_path, r_mmdc.file_path, "mmdr and mmdc caches must be isolated")
    elseif r_mmdc and r_mmdc.job_id then
      -- Async: wait for render, then re-render to get cache hit
      local done = false
      mermaid.render(source, { renderer = "mmdc" }, function()
        done = true
      end)
      vim.wait(30000, function()
        return done
      end, 50)
      local r_mmdc2 = mermaid.render(source, { renderer = "mmdc" })
      if r_mmdc2 and r_mmdc2.file_path then
        assert.are_not.equal(r_mmdr.file_path, r_mmdc2.file_path, "mmdr and mmdc caches must be isolated")
      end
    end
    -- If r_mmdc is nil: mmdc not installed — already guarded at top
  end)
end)
