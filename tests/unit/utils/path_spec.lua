local path = require("sixel-graphics.utils.path")

describe("path.resolve_image_path", function()
  it("resolves absolute paths unchanged", function()
    local r = path.resolve_image_path("/home/user/notes.md", "/absolute/cat.png")
    assert.are.equal("/absolute/cat.png", r)
  end)

  it("expands ~ to home directory", function()
    local r = path.resolve_image_path("/home/user/notes.md", "~/Pictures/cat.png")
    assert.are.equal(vim.fn.expand("~") .. "/Pictures/cat.png", r)
  end)

  it("resolves relative paths from markdown file dir", function()
    local r = path.resolve_image_path("/home/user/notes/blog/post.md", "./images/cat.png")
    assert.are.equal("/home/user/notes/blog/images/cat.png", r)
  end)

  it("resolves .. parent paths", function()
    local r = path.resolve_image_path("/home/user/notes/blog/post.md", "../shared/banner.png")
    assert.are.equal("/home/user/notes/shared/banner.png", r)
  end)
end)
