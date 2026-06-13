---Path resolution for markdown image references.
---Handles absolute, home-relative, and relative paths.
---@class PathUtils
local M = {}

---Resolve an image path found in a markdown file to an absolute filesystem path.
---Handles:
---  - Absolute paths: /foo/bar.png → /foo/bar.png (returned as-is)
---  - Home-relative paths: ~/foo.png → /home/user/foo.png
---  - Relative paths: ./images/cat.png → /path/to/markdown-dir/images/cat.png
---@param buffer_file_path string  Absolute path to the markdown file
---@param image_path string         Image URL as written in the markdown (may be relative)
---@return string  Absolute path to the resolved image file
function M.resolve_image_path(buffer_file_path, image_path)
  -- Absolute path: return as-is
  if string.sub(image_path, 1, 1) == "/" then
    return image_path
  end

  -- Home-relative: expand ~
  if string.sub(image_path, 1, 1) == "~" then
    return vim.fn.fnamemodify(image_path, ":p")
  end

  -- Relative path: join with markdown file's directory, then normalize
  local document_dir = vim.fn.fnamemodify(buffer_file_path, ":h")
  local absolute = document_dir .. "/" .. image_path
  absolute = vim.fn.fnamemodify(absolute, ":p")
  return vim.fs.normalize(absolute)
end

return M
