# sixel-graphics.nvim

A Neovim plugin for displaying images using the sixel graphics protocol.

## Requirements

- Neovim >= 0.10.0
- A terminal that supports sixel (e.g. [foot](https://codeberg.org/dnkl/foot), [WezTerm](https://wezfurlong.org/wezterm/))

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "mammothb/sixel-graphics.nvim",
  opts = {},
}
```

## Configuration

```lua
require("sixel-graphics").setup({
  -- Maximum display width in cells (nil = no limit)
  max_width = nil,
  -- Maximum display height in cells (nil = no limit)
  max_height = nil,
  -- Scale factor for rendered images
  scale = 1.0,
  -- Default row offset for rendering
  y_offset = 0,
})
```

## License

MIT
