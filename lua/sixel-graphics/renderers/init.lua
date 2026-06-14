---Renderer registry.
---Maps renderer IDs to renderer modules. Add new renderers here
---as they are implemented (e.g., plantuml, d2, gnuplot).
local mermaid = require("sixel-graphics.renderers.mermaid")

return {
  mermaid = mermaid,
}
