---Unit tests for markdown.query_buffer_images.
---Mocks treesitter to test error paths and happy paths
---without requiring the markdown parser to be installed.
---@diagnostic disable: duplicate-set-field

local M = require("sixel-graphics.integrations.markdown")

describe("markdown.query_buffer_images", function()
  -- Saved originals for restoration
  local _get_parser
  local _query_parse
  local _get_node_text
  local _notify
  local _get_current_buf

  before_each(function()
    _get_parser = vim.treesitter.get_parser
    _query_parse = vim.treesitter.query.parse
    _get_node_text = vim.treesitter.get_node_text
    _notify = vim.notify
    _get_current_buf = vim.api.nvim_get_current_buf
  end)

  after_each(function()
    vim.treesitter.get_parser = _get_parser
    vim.treesitter.query.parse = _query_parse
    vim.treesitter.get_node_text = _get_node_text
    vim.notify = _notify
    vim.api.nvim_get_current_buf = _get_current_buf
  end)

  -- ── helpers ───────────────────────────────────────────────────────────

  ---Create a mock TSTreeNode that returns given range and children.
  ---@param opts { start_row?: number, start_col?: number, end_row?: number, end_col?: number, children?: table[] }
  local function mock_node(opts)
    opts = opts or {}
    local children = opts.children or {}
    return {
      range = function()
        return opts.start_row or 0, opts.start_col or 0, opts.end_row or 0, opts.end_col or 0
      end,
      iter_children = function()
        local i = 0
        return function()
          i = i + 1
          return children[i]
        end
      end,
    }
  end

  ---Create a named child node with a type and optional text.
  ---get_node_text is mocked separately; text is just metadata for the mock.
  ---@param opts { type: string, named?: boolean }
  local function mock_child(opts)
    local child = mock_node(opts)
    child.named = function()
      return opts.named ~= false
    end
    child.type = function()
      return opts.type
    end
    return child
  end

  ---Set up a mocked treesitter environment that returns the given image nodes.
  ---Includes parser, children, inline trees, and query with captures.
  ---@param image_nodes table[]  TSTreeNode mocks that will be yielded by iter_captures
  ---@param expected_buf number?  Buffer number expected to be passed to get_parser (default 42)
  local function mock_treesitter_chain(image_nodes, expected_buf)
    expected_buf = expected_buf or 42
    local nodes = image_nodes or {}

    vim.treesitter.get_parser = function(buf, lang)
      assert.are.equal("markdown", lang)
      assert.are.equal(expected_buf, buf)
      return {
        parse = function() end,
        children = function()
          return {
            markdown_inline = {
              -- :for_each_tree passes self as first arg
              for_each_tree = function(_, callback)
                -- Create a tree; root node is irrelevant since iter_captures
                -- yields our pre-built nodes directly
                local tree = {
                  root = function()
                    return mock_node()
                  end,
                }
                callback(tree)
              end,
            },
          }
        end,
      }
    end

    -- Build capture list: pairs of {capture_id, node}
    local caps = {}
    for i, node in ipairs(nodes) do
      caps[i] = { 1, node } -- id=1 for "image" capture
    end

    vim.treesitter.query.parse = function(lang, _query_str)
      assert.are.equal("markdown_inline", lang)
      return {
        captures = { "image" },
        iter_captures = function()
          local i = 0
          return function()
            i = i + 1
            if caps[i] then
              return caps[i][1], caps[i][2]
            end
            return nil
          end
        end,
      }
    end
  end

  -- ── error paths ───────────────────────────────────────────────────────

  describe("error paths", function()
    it("returns {} and warns when get_parser throws", function()
      vim.treesitter.get_parser = function()
        error("parser error")
      end
      local warn_msg = nil
      vim.notify = function(msg, level)
        warn_msg = msg
        assert.are.equal(vim.log.levels.WARN, level)
      end

      local result = M.query_buffer_images(1)
      assert.are.same({}, result)
      assert.is_not_nil(warn_msg:match("no markdown treesitter parser"))
    end)

    it("returns {} and warns when get_parser returns nil", function()
      vim.treesitter.get_parser = function()
        return nil
      end

      local warned = false
      vim.notify = function(_, level)
        warned = true
        assert.are.equal(vim.log.levels.WARN, level)
      end

      local result = M.query_buffer_images(2)
      assert.are.same({}, result)
      assert.is_true(warned)
    end)

    it("returns {} when markdown_inline children absent", function()
      vim.treesitter.get_parser = function()
        return {
          parse = function() end,
          children = function()
            return {} -- no markdown_inline key
          end,
        }
      end

      local result = M.query_buffer_images(3)
      assert.are.same({}, result)
    end)
  end)

  -- ── standard image parsing ────────────────────────────────────────────

  describe("standard image ![alt](url)", function()
    it("extracts range and url from link_destination child", function()
      local child = mock_child({ type = "link_destination" })
      local node = mock_node({
        start_row = 2,
        start_col = 18,
        end_row = 2,
        end_col = 35,
        children = { child },
      })

      mock_treesitter_chain({ node })
      vim.treesitter.get_node_text = function(_n, buf)
        assert.are.equal(42, buf)
        return "./images/cat.png"
      end

      local result = M.query_buffer_images(42)
      assert.are.equal(1, #result)
      assert.are.equal("./images/cat.png", result[1].url)
      assert.are.same({ start_row = 2, start_col = 18, end_row = 2, end_col = 35 }, result[1].range)
    end)

    it("prefers link_destination over image_description children", function()
      -- When both children exist, link_destination wins (standard syntax)
      local link_dest = mock_child({ type = "link_destination" })
      local img_desc = mock_child({ type = "image_description" })
      local node = mock_node({
        start_row = 0,
        start_col = 0,
        end_row = 0,
        end_col = 10,
        children = { img_desc, link_dest }, -- both present
      })

      mock_treesitter_chain({ node })
      vim.treesitter.get_node_text = function(n)
        if n.type() == "link_destination" then
          return "./url-from-link.png"
        end
        return "should-not-be-used"
      end

      local result = M.query_buffer_images(42)
      assert.are.equal(1, #result)
      assert.are.equal("./url-from-link.png", result[1].url)
    end)
  end)

  -- ── shortcut image parsing ────────────────────────────────────────────

  describe("shortcut image ![alt]", function()
    it("falls back to image_description text when no link_destination", function()
      local child = mock_child({ type = "image_description" })
      local node = mock_node({
        start_row = 5,
        start_col = 10,
        end_row = 5,
        end_col = 20,
        children = { child },
      })

      mock_treesitter_chain({ node })
      vim.treesitter.get_node_text = function(_n, _buf)
        return "bird"
      end

      local result = M.query_buffer_images(42)
      assert.are.equal(1, #result)
      assert.are.equal("bird", result[1].url)
      assert.are.same({ start_row = 5, start_col = 10, end_row = 5, end_col = 20 }, result[1].range)
    end)

    it("skips image node when children are neither link_destination nor image_description", function()
      local child = mock_child({ type = "emphasis" })
      local node = mock_node({ children = { child } })

      mock_treesitter_chain({ node })
      vim.treesitter.get_node_text = function()
        error("get_node_text should not be called for unmatched child types")
      end

      local result = M.query_buffer_images(42)
      assert.are.same({}, result)
    end)
  end)

  -- ── multiple / empty results ──────────────────────────────────────────

  describe("multiple images", function()
    it("returns all image matches in document order", function()
      local child1 = mock_child({ type = "link_destination" })
      local child2 = mock_child({ type = "image_description" })
      local node1 = mock_node({
        start_row = 0,
        start_col = 0,
        end_row = 0,
        end_col = 10,
        children = { child1 },
      })
      local node2 = mock_node({
        start_row = 1,
        start_col = 5,
        end_row = 1,
        end_col = 15,
        children = { child2 },
      })

      mock_treesitter_chain({ node1, node2 })

      -- get_node_text: use counter to return different values per call
      local call_count = 0
      vim.treesitter.get_node_text = function(_n, _buf)
        call_count = call_count + 1
        if call_count == 1 then
          return "./cat.png"
        end
        return "bird-ref"
      end

      local result = M.query_buffer_images(42)
      assert.are.equal(2, #result)
      assert.are.equal("./cat.png", result[1].url)
      assert.are.equal(0, result[1].range.start_row)
      assert.are.equal("bird-ref", result[2].url)
      assert.are.equal(1, result[2].range.start_row)
    end)
  end)

  describe("no images in buffer", function()
    it("returns empty when iter_captures yields nothing", function()
      mock_treesitter_chain({}) -- no nodes
      local result = M.query_buffer_images(42)
      assert.are.same({}, result)
    end)
  end)

  -- ── buf parameter ─────────────────────────────────────────────────────

  describe("buf parameter", function()
    it("defaults to current buffer when buf is nil", function()
      vim.api.nvim_get_current_buf = function()
        return 100
      end

      local buf_arg = nil
      vim.treesitter.get_parser = function(buf, _lang)
        buf_arg = buf
        return {
          parse = function() end,
          children = function()
            return {}
          end,
        }
      end

      M.query_buffer_images() -- no argument
      assert.are.equal(100, buf_arg)
    end)
  end)
end)
