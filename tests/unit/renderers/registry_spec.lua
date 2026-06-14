describe("renderers registry", function()
  it("exports mermaid renderer", function()
    local reg = require("sixel-graphics.renderers")
    assert.is_not_nil(reg.mermaid)
  end)

  it("mermaid renderer has correct id", function()
    local mermaid = require("sixel-graphics.renderers.mermaid")
    assert.are.equal("mermaid", mermaid.id)
  end)

  it("mermaid renderer has render function", function()
    local mermaid = require("sixel-graphics.renderers.mermaid")
    assert.is_function(mermaid.render)
  end)

  it("mermaid.render notifies and returns nil for unknown renderer", function()
    local _notify = vim.notify
    local notifications = {}
    vim.notify = function(msg, level)
      table.insert(notifications, { msg = msg, level = level })
    end

    local mermaid = require("sixel-graphics.renderers.mermaid")
    local result = mermaid.render("source", { renderer = "plantuml" })
    assert.is_nil(result)
    assert.are.equal(1, #notifications)
    assert.is_not_nil(string.find(notifications[1].msg, "unknown renderer"))

    vim.notify = _notify
  end)
end)
