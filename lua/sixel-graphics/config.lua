---@class ConfigManager
---@field defaults Config
---@field options Config
local M = {}

---@class Config
---@field enabled boolean
---@field max_width? integer|nil Maximum display width in cells (nil for no limit)
---@field max_height? integer|nil Maximum display height in cells (nil for no limit)
---@field scale? number Scale factor (default 1.0)
---@field y_offset? integer Default row offset for rendering
---@field cell_width_override? integer|nil
---@field cell_height_override? integer|nil
M.defaults = {
  enabled = true,
  max_width = nil,
  max_height = nil,
  scale = 1.0,
  y_offset = 0,
  cell_width_override = nil, -- force cell width in pixels (overrides TIOCGWINSZ)
  cell_height_override = nil, -- force cell height in pixels (overrides TIOCGWINSZ)
  sixel_pixel_scale = 1.0, -- compensate for terminal sixel density vs text cell density
  -- set to 0.625 for Windows Terminal HiDPI, 1.0 for most others
  popup_render_delay_ms = 16, -- delay after window creation before sending sixel
  -- one frame at 60Hz; increase if image renders behind window
  debug = {
    enabled = false,
    level = "info", -- "debug"|"info"|"warn"|"error"
    file_path = nil, -- e.g. "/tmp/sixel-debug.log"
  },
  hover = {
    images = { enabled = true }, -- show images on hover in markdown
    diagrams = { enabled = true }, -- show mermaid diagrams on hover
    debounce_ms = 150, -- delay before showing popup after cursor settles
    max_screen_fraction = 0.5, -- max fraction of screen the popup may occupy
    filetypes = { "markdown" }, -- filetypes to enable hover in
  },
  renderer_options = {
    mermaid = {
      renderer = "mmdr", -- "mmdr" (native Rust, 2-6ms) | "mmdc" (Node.js/Chromium, 1-5s)
      min_popup_width = 40, -- minimum popup width in cells (diagrams auto-size to content, enforce floor)
      mmdr = {
        width = nil, -- nil | number (px, mmdr -w flag, default 1200)
        height = nil, -- nil | number (px, mmdr -H flag, default 800)
        fast_text = false, -- use calibrated fallback widths (mmdr --fastText)
        config_file = nil, -- nil | path to mmdr config.json (-c flag; bundled default has font settings)
      },
      mmdc = {
        theme = nil, -- nil | "default" | "dark" | "forest" | "neutral"
        background = nil, -- nil | "transparent" | "white" | "#hex"
        scale = nil, -- nil | number (1-3)
        width = nil, -- nil | number (px)
        height = nil, -- nil | number (px)
        cli_args = nil, -- nil | string[] (extra mmdc CLI args, e.g. {"--no-sandbox"})
      },
    },
  },
}

---@param opts Config?
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})

  -- ── Validation ───────────────────────────────────────────────
  local o = M.options
  local prefix = "sixel-graphics"

  local function check_positive(path, value)
    if type(value) ~= "number" then
      return
    end
    if value <= 0 then
      vim.notify(prefix .. "." .. path .. ": expected > 0, got " .. tostring(value), vim.log.levels.ERROR)
    end
  end
  local function check_positive_integer(path, value)
    if value == nil then
      return
    end
    if type(value) ~= "number" then
      return
    end
    if math.floor(value) ~= value then
      vim.notify(prefix .. "." .. path .. ": expected integer, got " .. tostring(value), vim.log.levels.ERROR)
    elseif value <= 0 then
      vim.notify(prefix .. "." .. path .. ": expected > 0, got " .. tostring(value), vim.log.levels.ERROR)
    end
  end

  -- Type checks (via vim.validate, wrapped in pcall)
  local ok, verr = pcall(vim.validate, {
    enabled = { o.enabled, "boolean" },
    max_width = { o.max_width, "number", true },
    max_height = { o.max_height, "number", true },
    scale = { o.scale, "number" },
    y_offset = { o.y_offset, "number" },
    cell_width_override = { o.cell_width_override, "number", true },
    cell_height_override = { o.cell_height_override, "number", true },
    sixel_pixel_scale = { o.sixel_pixel_scale, "number" },
    popup_render_delay_ms = { o.popup_render_delay_ms, "number" },
    debug = { o.debug, "table" },
    hover = { o.hover, "table" },
    renderer_options = { o.renderer_options, "table" },
  })
  if not ok then
    vim.notify(prefix .. "." .. verr, vim.log.levels.ERROR)
  end

  -- Range / integer checks (vim.validate can't express these)
  check_positive("scale", o.scale)
  check_positive("sixel_pixel_scale", o.sixel_pixel_scale)
  check_positive_integer("max_width", o.max_width)
  check_positive_integer("max_height", o.max_height)
  check_positive_integer("cell_width_override", o.cell_width_override)
  check_positive_integer("cell_height_override", o.cell_height_override)
  check_positive_integer("popup_render_delay_ms", o.popup_render_delay_ms)

  -- ── Nested validation ────────────────────────────────────────

  -- debug
  local dbg = o.debug
  if type(dbg) == "table" then
    local dok, derr = pcall(vim.validate, {
      enabled = { dbg.enabled, "boolean" },
      level = { dbg.level, "string" },
      file_path = { dbg.file_path, "string", true },
    })
    if not dok then
      vim.notify(prefix .. ".debug." .. derr, vim.log.levels.ERROR)
    end
    if dbg.level and not vim.tbl_contains({ "debug", "info", "warn", "error" }, dbg.level) then
      vim.notify(
        prefix .. ".debug.level: expected one of debug|info|warn|error, got " .. tostring(dbg.level),
        vim.log.levels.ERROR
      )
    end
  end

  -- hover
  local hov = o.hover
  if type(hov) == "table" then
    local hok, herr = pcall(vim.validate, {
      debounce_ms = { hov.debounce_ms, "number" },
      max_screen_fraction = { hov.max_screen_fraction, "number" },
      filetypes = { hov.filetypes, "table" },
      images = { hov.images, "table" },
      diagrams = { hov.diagrams, "table" },
    })
    if not hok then
      vim.notify(prefix .. ".hover." .. herr, vim.log.levels.ERROR)
    end
    check_positive_integer("hover.debounce_ms", hov.debounce_ms)
    check_positive("hover.max_screen_fraction", hov.max_screen_fraction)
    if hov.max_screen_fraction ~= nil and type(hov.max_screen_fraction) == "number" and hov.max_screen_fraction > 1 then
      vim.notify(
        prefix .. ".hover.max_screen_fraction: expected <= 1, got " .. tostring(hov.max_screen_fraction),
        vim.log.levels.WARN
      )
    end
    for _, sub in ipairs({ "images", "diagrams" }) do
      local s = hov[sub]
      if type(s) == "table" then
        local sok, serr = pcall(vim.validate, {
          enabled = { s.enabled, "boolean" },
        })
        if not sok then
          vim.notify(prefix .. ".hover." .. sub .. "." .. serr, vim.log.levels.ERROR)
        end
      end
    end
  end

  -- renderer_options.mermaid
  local ro = o.renderer_options
  if type(ro) == "table" and type(ro.mermaid) == "table" then
    local m = ro.mermaid
    local mok, merr = pcall(vim.validate, {
      renderer = { m.renderer, "string" },
      min_popup_width = { m.min_popup_width, "number" },
      mmdr = { m.mmdr, "table" },
      mmdc = { m.mmdc, "table" },
    })
    if not mok then
      vim.notify(prefix .. ".renderer_options.mermaid." .. merr, vim.log.levels.ERROR)
    end
    if m.renderer and not vim.tbl_contains({ "mmdr", "mmdc" }, m.renderer) then
      vim.notify(
        prefix .. ".renderer_options.mermaid.renderer: expected mmdr|mmdc, got " .. tostring(m.renderer),
        vim.log.levels.ERROR
      )
    end
    check_positive_integer("renderer_options.mermaid.min_popup_width", m.min_popup_width)

    -- mmdr subtable
    if type(m.mmdr) == "table" then
      local drok, drerr = pcall(vim.validate, {
        width = { m.mmdr.width, "number", true },
        height = { m.mmdr.height, "number", true },
        fast_text = { m.mmdr.fast_text, "boolean" },
        config_file = { m.mmdr.config_file, "string", true },
      })
      if not drok then
        vim.notify(prefix .. ".renderer_options.mermaid.mmdr." .. drerr, vim.log.levels.ERROR)
      end
      check_positive_integer("renderer_options.mermaid.mmdr.width", m.mmdr.width)
      check_positive_integer("renderer_options.mermaid.mmdr.height", m.mmdr.height)
    end

    -- mmdc subtable
    if type(m.mmdc) == "table" then
      local dcok, dcerr = pcall(vim.validate, {
        theme = { m.mmdc.theme, "string", true },
        background = { m.mmdc.background, "string", true },
        scale = { m.mmdc.scale, "number", true },
        width = { m.mmdc.width, "number", true },
        height = { m.mmdc.height, "number", true },
        cli_args = { m.mmdc.cli_args, "table", true },
      })
      if not dcok then
        vim.notify(prefix .. ".renderer_options.mermaid.mmdc." .. dcerr, vim.log.levels.ERROR)
      end
      if m.mmdc.scale ~= nil and type(m.mmdc.scale) == "number" then
        if m.mmdc.scale < 1 or m.mmdc.scale > 3 then
          vim.notify(
            prefix .. ".renderer_options.mermaid.mmdc.scale: expected 1-3, got " .. tostring(m.mmdc.scale),
            vim.log.levels.ERROR
          )
        end
      end
      check_positive_integer("renderer_options.mermaid.mmdc.width", m.mmdc.width)
      check_positive_integer("renderer_options.mermaid.mmdc.height", m.mmdc.height)
    end
  end
end

---Return keys present in user config but absent from defaults.
---Walks nested tables; e.g. { max_widht = 80 } returns {"max_widht"}.
---Useful for health-check typo detection.
---@param user_opts table|nil  Raw opts table passed to setup()
---@return string[]  Dot-separated unknown key paths (empty if none or nil)
function M._find_unknown_keys(user_opts)
  if not user_opts then
    return {}
  end

  local unknown = {}
  local function walk(u, d, path)
    for k, v in pairs(u) do
      local full = path == "" and k or path .. "." .. k
      if d[k] == nil then
        table.insert(unknown, full)
      elseif type(v) == "table" and type(d[k]) == "table" and not vim.tbl_islist(v) then
        walk(v, d[k], full)
      end
    end
  end
  walk(user_opts, M.defaults, "")
  return unknown
end

return setmetatable(M, {
  __index = function(_, key)
    if rawget(M, "options") == nil then
      M.setup()
    end
    if key == "options" then
      return rawget(M, "options")
    end
    return rawget(M, "options")[key]
  end,
})
