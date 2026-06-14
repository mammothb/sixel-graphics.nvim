---Minimal Image class stub.
---Holds the fields the backend needs; not the full image.nvim Image.
---@class Image
---@field id string           Unique identifier
---@field path string          Absolute path to image file
---@field geometry ImageGeometry  Position and dimensions in cells
---@field is_rendered boolean  Whether currently rendered to terminal
local Image = {}
Image.__index = Image

local next_id = 1

---Create an Image from a file path.
---@param path string       Path to image (made absolute)
---@param opts? { x?: number, y?: number, width?: number, height?: number }
---@return Image
function Image.from_file(path, opts)
  opts = opts or {}
  local id = "img-" .. tostring(next_id)
  next_id = next_id + 1

  return setmetatable({
    id = id,
    path = vim.fn.fnamemodify(path, ":p"), -- absolute path
    geometry = {
      x = opts.x or 0,
      y = opts.y or 0,
      width = opts.width, -- nil = use original aspect
      height = opts.height, -- nil = use original aspect
    },
    is_rendered = false,
  }, Image)
end

---@class ImageGeometry
---@field x number     Column (0-indexed)
---@field y number     Row (0-indexed)
---@field width? number  Width in cells (nil = aspect-ratio from height)
---@field height? number Height in cells (nil = aspect-ratio from width)

return Image
