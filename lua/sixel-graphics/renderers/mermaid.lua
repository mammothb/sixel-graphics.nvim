---Mermaid diagram renderer.
---
---Renders Mermaid diagram source code to PNG via an external CLI tool.
---Two renderer backends are supported:
---  - mmdr (mermaid-rs-renderer): native Rust, 2-6ms, synchronous `vim.fn.system()`
---  - mmdc (mermaid-cli): Node.js/Chromium, 1-5s, async `vim.fn.jobstart()` (Step D3)
---
---Currently only the mmdr path is implemented. The mmdc path will be added in Step D3.
---@class MermaidRenderer
local M = {
  id = "mermaid",
}

local logger = require("sixel-graphics.utils.logger")

---@private
---Compute a deterministic cache key from diagram source and renderer name.
---Same source renders differently under mmdr vs mmdc, so include the
---renderer name in the hash input to keep their caches separate.
---@param source string        Diagram source code
---@param renderer_name string  "mmdr" or "mmdc"
---@return string  sha256 hex digest (64 characters)
local function _compute_hash(source, renderer_name)
  return vim.fn.sha256(renderer_name .. ":" .. source)
end
M._compute_hash = _compute_hash

---@private
---Get or create the mermaid cache directory.
---@return string  Absolute path to cache directory
local function _get_cache_dir()
  local dir = vim.fn.stdpath("cache") .. "/sixel-graphics/mermaid"
  local ok = vim.fn.mkdir(dir, "p")
  if ok == 0 then
    vim.notify("sixel-graphics: failed to create cache directory: " .. dir, vim.log.levels.ERROR)
  end
  return dir
end
M._get_cache_dir = _get_cache_dir

---@private
---Get the full cache file path for a given hash.
---@param hash string  sha256 hex digest
---@return string  Absolute path to cached PNG file
local function _get_cache_path(hash)
  return _get_cache_dir() .. "/" .. hash .. ".png"
end
M._get_cache_path = _get_cache_path

---@private
---Check if a cached PNG exists for the given hash.
---@param hash string  sha256 hex digest
---@return string|nil  Path to cached PNG, or nil if not cached
local function _check_cache(hash)
  local path = _get_cache_path(hash)
  if vim.fn.filereadable(path) == 1 then
    return path
  end
  return nil
end
M._check_cache = _check_cache

---@private
---Build the mmdr command array for vim.fn.system().
---Returns an array of strings (not a single shell string) so
---vim.fn.system() passes each arg directly without shell interpolation.
---@param temp_path string    Path to temporary .mmd input file
---@param cache_path string   Path to output .png file
---@param mmdr_opts table     options.renderer_options.mermaid.mmdr
---@return string[]  Command array: {"mmdr", "-i", ..., "-e", "png"}
local function _build_mmdr_command(temp_path, cache_path, mmdr_opts)
  mmdr_opts = mmdr_opts or {}
  local args = {
    "mmdr",
    "-i",
    temp_path,
    "-o",
    cache_path,
    "-e",
    "png",
  }

  if mmdr_opts.width then
    table.insert(args, "-w")
    table.insert(args, tostring(mmdr_opts.width))
  end
  if mmdr_opts.height then
    table.insert(args, "-H")
    table.insert(args, tostring(mmdr_opts.height))
  end
  if mmdr_opts.config_file then
    table.insert(args, "-c")
    table.insert(args, mmdr_opts.config_file)
  end
  if mmdr_opts.fast_text then
    table.insert(args, "--fastText")
  end

  return args
end
M._build_mmdr_command = _build_mmdr_command

---@private
---Build the mmdc command array from temp input path, cache output path, and options.
---Mirrors _build_mmdr_command but for mmdc's different CLI flags.
---
---mmdc CLI reference (from mmdc --help, 2026-06-14):
---  -i, --input <input>              Input mermaid file
---  -o, --output [output]            Output file
---  -e, --outputFormat [format]      Output format: svg, png, pdf
---  -b, --backgroundColor [bg]       Background color (default: "white")
---  -t, --theme [theme]              Theme: default, forest, dark, neutral
---  -s, --scale [scale]              Puppeteer scale factor (default: 1)
---  -w, --width [width]              Width of the page (default: 800)
---  -H, --height [height]            Height of the page (default: 600)
---
---@param temp_path string    Path to temporary .mmd input file
---@param cache_path string   Path to output .png file
---@param mmdc_opts table     options.renderer_options.mermaid.mmdc
---@return string[]  Command array suitable for vim.fn.jobstart()
local function _build_mmdc_command(temp_path, cache_path, mmdc_opts)
  mmdc_opts = mmdc_opts or {}
  local args = { "mmdc" }

  -- cli_args first (e.g., {"--no-sandbox"} — must come before -i/-o)
  if mmdc_opts.cli_args then
    for _, arg in ipairs(mmdc_opts.cli_args) do
      table.insert(args, arg)
    end
  end

  -- Required flags
  table.insert(args, "-i")
  table.insert(args, temp_path)
  table.insert(args, "-o")
  table.insert(args, cache_path)
  table.insert(args, "-e")
  table.insert(args, "png")

  -- Optional flags
  if mmdc_opts.background then
    table.insert(args, "-b")
    table.insert(args, mmdc_opts.background)
  end
  if mmdc_opts.theme then
    table.insert(args, "-t")
    table.insert(args, mmdc_opts.theme)
  end
  if mmdc_opts.scale then
    table.insert(args, "-s")
    table.insert(args, tostring(mmdc_opts.scale))
  end
  if mmdc_opts.width then
    table.insert(args, "-w")
    table.insert(args, tostring(mmdc_opts.width))
  end
  if mmdc_opts.height then
    table.insert(args, "-H")
    table.insert(args, tostring(mmdc_opts.height))
  end

  return args
end
M._build_mmdc_command = _build_mmdc_command

---@private
---Run a shell command via vim.fn.system() and return both output and exit code.
---Extracted for testability — tests mock this instead of vim.fn.system()
---to control exit codes without touching read-only vim.v.shell_error.
---@param cmd_args string[]  Command array
---@return string output
---@return number exit_code
local function _run_system(cmd_args)
  local output = vim.fn.system(cmd_args)
  return output, vim.v.shell_error
end
M._run_system = _run_system

---@private
---Resolve the bundled mmdr-config.json path (shipped with the plugin).
---Used as default config_file when user doesn't specify one, so fonts
---render correctly on Linux systems where mmdr's default fonts are absent.
---@return string|nil  Absolute path to bundled config, or nil if plugin dir can't be resolved
local function _bundled_config_path()
  -- Derive plugin root from this file's path
  local source = debug.getinfo(1, "S").source
  local prefix = source:match("@(.*)/lua/sixel%-graphics/renderers/mermaid%.lua$")
  if prefix then
    return prefix .. "/lua/sixel-graphics/renderers/mmdr-config.json"
  end
  return nil
end

---@private
---Spawn an async job via vim.fn.jobstart(). Extracted for testability.
---Tests mock this to return a fake job_id without spawning real processes.
---@param cmd_args string[]  Command array
---@param callbacks table    on_stdout, on_stderr, on_exit callbacks
---@return number  Job ID (> 0) or 0 on failure, -1 on invalid args
local function _jobstart(cmd_args, callbacks)
  return vim.fn.jobstart(cmd_args, callbacks)
end
M._jobstart = _jobstart

---Render a mermaid diagram source to a PNG file.
---
---mmdr path (sync): hash → cache check → write temp → vim.fn.system() → return file_path.
---mmdc path (async): hash → cache check → write temp → jobstart → return { job_id }.
---  Result delivered asynchronously via on_complete callback (on_exit handler).
---
---@param source string     Diagram source code
---@param options table      renderer_options.mermaid from config
---@param on_complete? fun(path: string|nil, err: string|nil)  Async completion callback (mmdc only)
---@return { file_path: string }?  Sync success
---@return { job_id: number }?     Async started (mmdc cache miss); on_complete will fire
---@return nil                     Error (not installed, spawn failed)
function M.render(source, options, on_complete)
  options = options or {}
  local renderer_name = options.renderer or "mmdr"

  -- ── mmdc path ──────────────────────────────────────────────────
  if renderer_name == "mmdc" then
    -- 1. Hash source with "mmdc:" prefix (separate cache from mmdr)
    local hash = _compute_hash(source, "mmdc")

    -- 2. Check cache — sync return, no callback
    local cached = _check_cache(hash)
    if cached then
      logger.debug(function()
        return "mermaid.render: mmdc cache hit " .. hash
      end)
      return { file_path = cached }
    end

    -- 3. on_complete is required for async path
    if not on_complete then
      vim.notify("sixel-graphics: mmdc render requires a callback for async completion", vim.log.levels.ERROR)
      return nil
    end

    -- 4. Check mmdc executable
    if vim.fn.executable("mmdc") == 0 then
      vim.notify(
        "sixel-graphics: mmdc not found in PATH. Install via: npm install -g @mermaid-js/mermaid-cli",
        vim.log.levels.ERROR
      )
      return nil
    end

    -- 5. Write source to temp file
    local temp_path = vim.fn.tempname() .. ".mmd"
    local lines = vim.split(source, "\n")
    vim.fn.writefile(lines, temp_path)

    -- 6. Build command
    local cache_path = _get_cache_path(hash)
    local mmdc_opts = vim.deepcopy(options.mmdc or {})
    local cmd_args = _build_mmdc_command(temp_path, cache_path, mmdc_opts)

    logger.debug(function()
      return "mermaid.render: mmdc spawning: " .. table.concat(cmd_args, " ")
    end)

    -- 7. Collect stderr for error reporting
    local stderr_lines = {}

    -- 8. Set up timeout guard (30s)
    local timeout_guard = nil

    -- 9. Spawn async job with on_exit completion handler
    local job_id = M._jobstart(cmd_args, {
      on_stderr = function(_, data, _)
        if data then
          for _, line in ipairs(data) do
            table.insert(stderr_lines, line)
          end
        end
      end,
      on_exit = function(_, exit_code, _)
        -- Cancel timeout guard if job completed before timeout
        if timeout_guard then
          vim.fn.timer_stop(timeout_guard)
          timeout_guard = nil
        end

        -- on_exit fires in libuv context — schedule to safely call Neovim APIs
        vim.schedule(function()
          -- Clean up temp file
          vim.fn.delete(temp_path)

          if exit_code == 0 and vim.fn.filereadable(cache_path) == 1 then
            on_complete(cache_path)
          else
            local err = string.format("mmdc exited with code %d", exit_code)
            if #stderr_lines > 0 then
              err = err .. "\n" .. table.concat(stderr_lines, "\n"):gsub("^%s+", ""):gsub("%s+$", "")
            end
            on_complete(nil, err)
          end
        end)
      end,
    })

    if job_id <= 0 then
      vim.fn.delete(temp_path)
      vim.notify(
        "sixel-graphics: failed to start mmdc. Check that Node.js and mermaid-cli are installed.",
        vim.log.levels.ERROR
      )
      return nil
    end

    -- 10. Start timeout guard (fires if on_exit never does)
    timeout_guard = vim.fn.timer_start(30000, function()
      pcall(vim.fn.jobstop, job_id)
      vim.schedule(function()
        vim.fn.delete(temp_path)
        on_complete(nil, "mmdc render timed out after 30s")
      end)
    end)

    -- Return job_id for tracking (result comes via on_complete callback)
    return { job_id = job_id }
  end

  -- ── mmdr path (unchanged from D2) ──────────────────────────────
  if renderer_name ~= "mmdr" then
    vim.notify("sixel-graphics: unknown renderer '" .. tostring(renderer_name) .. "'", vim.log.levels.ERROR)
    return nil
  end

  -- 1. Hash source (includes renderer name for separate caches)
  local hash = _compute_hash(source, "mmdr")

  -- 2. Check cache
  local cached = _check_cache(hash)
  if cached then
    logger.debug(function()
      return "mermaid.render: cache hit " .. hash
    end)
    return { file_path = cached }
  end

  -- 3. Check mmdr executable
  if vim.fn.executable("mmdr") == 0 then
    vim.notify(
      "sixel-graphics: mmdr not found in PATH. Install via: cargo install mermaid-rs-renderer",
      vim.log.levels.ERROR
    )
    return nil
  end

  -- 4. Write source to temp file
  local temp_path = vim.fn.tempname() .. ".mmd"
  local lines = vim.split(source, "\n")
  vim.fn.writefile(lines, temp_path)

  -- 5. Build command and run synchronously
  local cache_path = _get_cache_path(hash)
  local mmdr_opts = vim.deepcopy(options.mmdr or {})

  -- Default config_file to bundled font config if user didn't set one
  if not mmdr_opts.config_file then
    mmdr_opts.config_file = _bundled_config_path()
  end

  local cmd_args = _build_mmdr_command(temp_path, cache_path, mmdr_opts)

  logger.debug(function()
    return "mermaid.render: running: " .. table.concat(cmd_args, " ")
  end)

  local output, exit_code = M._run_system(cmd_args)

  -- 6. Clean up temp file
  vim.fn.delete(temp_path)

  -- 7. Check result
  if exit_code ~= 0 then
    local stderr = tostring(output):gsub("^%s+", ""):gsub("%s+$", "")
    vim.notify(
      "sixel-graphics: mmdr failed (exit " .. exit_code .. "):" .. (#stderr > 0 and "\n" .. stderr or ""),
      vim.log.levels.ERROR
    )
    return nil
  end

  if vim.fn.filereadable(cache_path) == 0 then
    vim.notify("sixel-graphics: mmdr did not produce output file", vim.log.levels.ERROR)
    return nil
  end

  logger.debug(function()
    return "mermaid.render: success → " .. cache_path
  end)

  return { file_path = cache_path }
end

return M
