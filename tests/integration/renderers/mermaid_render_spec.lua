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
