---LRU (Least-Recently-Used) in-memory cache.
---
---Doubly-linked list + hash map for O(1) get/set/evict.
---Two sentinel nodes (head/tail) simplify insert/remove edge cases.
---
---Usage:
---```lua
---local M = require("sixel-graphics.utils.cache")
---local c = M.new(50)
---c:set("key", "value")
---local v = c:get("key")  -- "value", promotes to most-recently-used
---```
---
---@class LruCache
---@field _capacity number
---@field _map table<string, LruNode>
---@field _head LruNode  Sentinel: most-recently-used end
---@field _tail LruNode  Sentinel: least-recently-used end
---@field _hits number
---@field _misses number
local M = {}
M.__index = M

---@class LruNode
---@field key string
---@field value any
---@field prev LruNode|nil
---@field next LruNode|nil

---Create a new LRU cache.
---@param max_entries number  Maximum number of entries before eviction (must be >= 1)
---@return LruCache
function M.new(max_entries)
  if type(max_entries) ~= "number" or max_entries < 1 or math.floor(max_entries) ~= max_entries then
    error("max_entries must be a positive integer, got " .. tostring(max_entries))
  end

  local head = {} -- sentinel: most-recently-used
  local tail = {} -- sentinel: least-recently-used
  head.next = tail
  tail.prev = head

  return setmetatable({
    _capacity = max_entries,
    _map = {},
    _head = head,
    _tail = tail,
    _hits = 0,
    _misses = 0,
  }, M)
end

---@private
---Remove a node from the linked list (does not touch _map).
---@param node LruNode|nil
local function _remove_node(node)
  if not node then
    return
  end
  node.prev.next = node.next
  node.next.prev = node.prev
end

---@private
---Insert a node at the head (most-recently-used end).
---@param self LruCache
---@param node LruNode
local function _insert_head(self, node)
  node.next = self._head.next
  node.prev = self._head
  self._head.next.prev = node
  self._head.next = node
end

---@private
---Move an existing node to the head (promote to most-recently-used).
---@param self LruCache
---@param node LruNode
local function _move_to_head(self, node)
  _remove_node(node)
  _insert_head(self, node)
end

---@private
---Evict the least-recently-used entry (tail.prev).
---@param self LruCache
local function _evict_lru(self)
  local node = self._tail.prev
  if node == nil or node == self._head then
    return -- cache is empty
  end
  _remove_node(node)
  self._map[node.key] = nil
end

---Retrieve a value by key. Promotes the entry to most-recently-used.
---Records a hit on success, miss on failure.
---@param key string
---@return any|nil  Value if found, nil otherwise
function M:get(key)
  local node = self._map[key]
  if node then
    self._hits = self._hits + 1
    _move_to_head(self, node)
    return node.value
  end
  self._misses = self._misses + 1
  return nil
end

---Store a value by key. Evicts least-recently-used if at capacity.
---If the key already exists, updates the value and promotes to
---most-recently-used (no eviction).
---@param key string
---@param value any
function M:set(key, value)
  local node = self._map[key]
  if node then
    -- Update existing: new value, promote to MRU
    node.value = value
    _move_to_head(self, node)
    return
  end

  -- Evict if at capacity before inserting the new node
  if vim.tbl_count(self._map) >= self._capacity then
    _evict_lru(self)
  end

  -- Insert new node at head
  node = { key = key, value = value }
  _insert_head(self, node)
  self._map[key] = node
end

---Remove all entries and reset statistics.
function M:clear()
  self._map = {}
  self._head.next = self._tail
  self._tail.prev = self._head
  self._hits = 0
  self._misses = 0
end

---Return cache statistics.
---@return { size: number, hits: number, misses: number }
function M:stats()
  return {
    size = vim.tbl_count(self._map),
    hits = self._hits,
    misses = self._misses,
  }
end

return M
