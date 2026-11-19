local M = {}
local api = vim.api
local uv = vim.uv
local name = "system-palette"
local options = {
  path = (vim.env.XDG_STATE_HOME or vim.fn.expand("~/.local/state")) .. "/quickshell/user/generated/colors.json",
  watch = true,
}
local watcher
local active_palette

local function read_palette()
  local file, err = io.open(vim.fn.expand(options.path), "r")
  if not file then
    return nil, err
  end
  local raw = file:read("*a")
  file:close()

  local ok, colors = pcall(vim.json.decode, raw)
  if not ok or type(colors) ~= "table" then
    return nil, "expected a JSON object with Material 3 colors"
  end

  local function hex(key)
    local value = colors[key]
    if type(value) == "string" and value:match("^#%x%x%x%x%x%x$") then
      return value:lower()
    end
  end

  local bg = hex("surface") or hex("background")
  local fg = hex("on_surface") or hex("on_background")
  local primary = hex("primary")
  if not (bg and fg and primary) then
    return nil, "expected surface, on_surface and primary colors in #RRGGBB format"
  end

  local panel = hex("surface_container") or bg
  return {
    bg = bg,
    fg = fg,
    primary = primary,
    secondary = hex("secondary") or fg,
    tertiary = hex("tertiary") or primary,
    muted = hex("outline") or fg,
    panel = panel,
    selection = hex("secondary_container") or panel,
    selected_text = hex("on_secondary_container") or fg,
    error = hex("error") or primary,
  }
end

function M.available()
  return read_palette() ~= nil
end

local function apply(p)
  vim.cmd.highlight("clear")
  vim.g.colors_name = name
  local groups = {
    Normal = { fg = p.fg, bg = p.bg },
    NormalFloat = { fg = p.fg, bg = p.panel },
    FloatBorder = { fg = p.muted, bg = p.panel },
    Pmenu = { fg = p.fg, bg = p.panel },
    PmenuSel = { fg = p.selected_text, bg = p.selection },
    Visual = { fg = p.selected_text, bg = p.selection },
    CursorLine = { bg = p.panel },
    CursorLineNr = { fg = p.primary, bold = true },
    LineNr = { fg = p.muted },
    SignColumn = { bg = p.bg },
    WinSeparator = { fg = p.muted },
    StatusLine = { fg = p.fg, bg = p.panel },
    StatusLineNC = { fg = p.muted, bg = p.panel },
    Search = { fg = p.selected_text, bg = p.selection },
    IncSearch = { fg = p.bg, bg = p.primary },
    MatchParen = { fg = p.bg, bg = p.tertiary, bold = true },
    Comment = { fg = p.muted, italic = true },
    Constant = { fg = p.tertiary },
    String = { fg = p.secondary },
    Identifier = { fg = p.fg },
    Function = { fg = p.primary },
    Statement = { fg = p.primary },
    PreProc = { fg = p.tertiary },
    Type = { fg = p.tertiary },
    Special = { fg = p.secondary },
    Error = { fg = p.error },
    Todo = { fg = p.primary, bold = true },
    DiagnosticError = { fg = p.error },
    DiagnosticWarn = { fg = p.tertiary },
    DiagnosticInfo = { fg = p.primary },
    DiagnosticHint = { fg = p.secondary },
    DiagnosticOk = { fg = p.secondary },
    Added = { fg = p.secondary },
    Changed = { fg = p.tertiary },
    Removed = { fg = p.error },
    Directory = { fg = p.primary },
    Title = { fg = p.primary, bold = true },
  }

  for group, spec in pairs(groups) do
    api.nvim_set_hl(0, group, spec)
  end
end

function M.load()
  local palette, err = read_palette()
  if not palette then
    error(name .. ": " .. err, 0)
  end
  apply(palette)
  active_palette = palette
end

local function stop_watching()
  if watcher then
    watcher:close()
    watcher = nil
  end
end

function M.setup(opts)
  options = vim.tbl_extend("force", options, opts or {})
  stop_watching()

  api.nvim_create_user_command("SystemPaletteReload", function()
    vim.cmd.colorscheme(name)
  end, {})

  local group = api.nvim_create_augroup("SystemPalette", { clear = true })
  if not options.watch then
    return
  end

  local poll = assert(uv.new_fs_poll())
  local started, err = poll:start(vim.fn.expand(options.path), 500, vim.schedule_wrap(function()
    if watcher ~= poll or vim.g.colors_name ~= name then
      return
    end
    local palette = read_palette()
    if palette and not vim.deep_equal(palette, active_palette) then
      pcall(vim.cmd.colorscheme, name)
    end
  end))

  if not started then
    poll:close()
    vim.notify(name .. ": " .. err, vim.log.levels.WARN)
    return
  end

  watcher = poll
  api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = stop_watching,
  })
end

return M
