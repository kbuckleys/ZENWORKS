-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/
--
-- The zenon colours, for an nvim that draws nothing.
--
-- The palette is plato/nvim/lua/plato/palette.lua, the same colours
-- morpheus/Zenon.qml holds on the QML side; the groups below say which
-- colour each kind of text is, as zenon.lua did for the terminal nvim.

local M = {}

-- ── THE SHELL'S THEME ───────────────────────────────────────────────────
-- palette.lua is Zenon. When the shell wears another theme, PlatoWindow
-- sends its resolved colours (Zenon's slot names, as hex) and `use` lays
-- them over a copy of the palette: nothing here is a second theme format,
-- and a slot the theme leaves out is still Zenon's because the shell has
-- already filled it in. `mode` is the theme's dark/light.
local over, mode = nil, "dark"

-- Zenon's slot → the palette's names. The bright_ variants a theme does not
-- carry fall back to the base hue: on a light ground a "brighter" accent is
-- the one thing that cannot be read.
local function mapped(c)
  return {
    black = c.ground, layer = c.ground, lblack = c.surface,
    white = c.ink, bright_white = c.ink, bright_black = c.muted,
    red = c.red, green = c.green, yellow = c.yellow, blue = c.blue,
    magenta = c.magenta, cyan = c.cyan,
    bright_red = c.pink, bright_yellow = c.sand,
    bright_green = c.green, bright_blue = c.blue,
    bright_magenta = c.magenta, bright_cyan = c.cyan,
    soft = c.soft, table = c.border,
  }
end

local function palette()
  local base = require("plato.palette")
  if not over then return base end
  local p = {}
  for k, v in pairs(base) do p[k] = v end
  for k, v in pairs(over) do if type(v) == "string" and v ~= "" then p[k] = v end end
  return p
end

-- the shell's theme, or nil for Zenon; repaints only when it changed
function M.use(t)
  local want = t and t.colors and mapped(t.colors) or nil
  local nextMode = t and t.mode == "light" and "light" or "dark"
  if vim.deep_equal(want, over) and nextMode == mode then return false end
  over, mode = want, nextMode
  M.apply()
  -- view.lua's ColorScheme handler resets the style table and tells QML
  vim.api.nvim_exec_autocmds("ColorScheme", { modeline = false })
  return true
end

function M.apply()
  local p = palette()
  local set = function(g, v) vim.api.nvim_set_hl(0, g, v) end
  vim.o.termguicolors = true
  vim.o.background = mode

  -- ── text and its surroundings, as zenon.lua has them ────────────────
  set("Normal", { fg = p.white })
  -- SELECTIONS AND MATCHES ARE A WASH, NOT A BLOCK: their background is
  -- drawn translucent over the text (hl.lua's `wash`, EditorRow), and the
  -- text keeps its own colours through it rather than turning black
  set("Visual", { bg = p.magenta })
  set("CursorLine", { bg = p.lblack, nocombine = true })
  set("CurSearch", { bg = p.red, bold = true })
  set("Search", { bg = p.bright_red })
  set("IncSearch", { bg = p.red })
  set("Substitute", { bg = p.red })
  set("YankHighlight", { fg = p.black, bg = p.bright_red, nocombine = true })
  set("DiagnosticVirtualTextError", { fg = p.red })
  set("DiagnosticVirtualTextWarn", { fg = p.yellow })
  set("DiagnosticVirtualTextInfo", { fg = p.bright_red })
  set("DiagnosticVirtualTextHint", { fg = p.cyan })
  -- the gutter and folds: what the terminal shows by default under zenon
  set("LineNr", { fg = p.bright_black })
  set("CursorLineNr", { fg = p.yellow })
  set("Folded", { fg = p.bright_black, italic = true })
  set("NonText", { fg = p.bright_black })
  -- a closed fold's count of lines, in the pill after its first line
  set("PlatoFoldChip", { fg = p.bright_black })
  -- rainbow brackets (brackets.lua), a colour a level, round and round
  for i, c in ipairs({ p.blue, p.magenta, p.yellow, p.cyan, p.green, p.bright_red }) do
    set("PlatoRainbow" .. i, { fg = c })
  end
  -- rendered markdown (markdown.lua); EditorRow's heading bands take the
  -- same colours, a level each
  for i, c in ipairs({ p.magenta, p.blue, p.cyan, p.green, p.yellow, p.bright_red }) do
    set("PlatoMdH" .. i, { fg = c, bold = true })
  end
  -- a bullet's colour by how deep its list is
  for i, c in ipairs({ p.blue, p.magenta, p.cyan, p.green }) do
    set("PlatoMdBullet" .. i, { fg = c })
  end
  set("PlatoMdQuoteText", { fg = p.soft or "#a2a8b5", italic = true })
  set("PlatoMdCalloutText", { fg = p.white })
  set("PlatoMdComment", { fg = p.bright_black, italic = true })
  set("PlatoMdTodo", { fg = p.bright_black })
  set("PlatoMdCheck", { fg = p.green })
  set("PlatoMdDone", { fg = p.bright_black, strikethrough = true })
  set("PlatoMdBold", { bold = true })
  set("PlatoMdItalic", { italic = true })
  set("PlatoMdStrike", { fg = p.bright_black, strikethrough = true })
  set("PlatoMdCode", { fg = p.bright_red, bg = p.lblack })
  set("PlatoMdLink", { fg = p.blue, underline = true, sp = p.blue })
  set("PlatoMdFence", { fg = p.bright_black, italic = true })
  set("PlatoMdTable", { fg = p.table or "#454b57" })
  set("PlatoMdTableHead", { fg = p.white, bold = true })
  set("PlatoMdQuote", { fg = p.bright_black })
  set("PlatoMdNote", { fg = p.blue, bold = true })
  set("PlatoMdTip", { fg = p.green, bold = true })
  set("PlatoMdImportant", { fg = p.magenta, bold = true })
  set("PlatoMdWarning", { fg = p.yellow, bold = true })
  set("PlatoMdCaution", { fg = p.red, bold = true })
  -- spelling (spell.lua): a curl under the word, as a diagnostic's
  set("SpellBad", { undercurl = true, sp = p.red })
  set("SpellCap", { undercurl = true, sp = p.yellow })
  set("SpellRare", { undercurl = true, sp = p.cyan })
  set("SpellLocal", { undercurl = true, sp = p.cyan })

  -- ── syntax (regex engine) ───────────────────────────────────────────
  local syntax = {
    Comment = p.bright_black, String = p.yellow, Constant = p.bright_red,
    Number = p.yellow, Boolean = p.bright_red, Character = p.yellow,
    Statement = p.magenta, Keyword = p.magenta, Conditional = p.magenta,
    Repeat = p.magenta, Label = p.magenta, Operator = p.magenta,
    Function = p.green, Identifier = p.green,
    Type = p.cyan, StorageClass = p.cyan, Structure = p.cyan, Typedef = p.cyan,
    PreProc = p.magenta, Include = p.magenta, Define = p.magenta, Macro = p.magenta,
    Special = p.bright_red, SpecialChar = p.bright_red,
    Error = p.red, Todo = p.bright_red,
  }
  for g, c in pairs(syntax) do set(g, { fg = c }) end

  -- ── syntax (treesitter) ─────────────────────────────────────────────
  local ts = {
    ["@comment"] = p.bright_black,
    ["@string"] = p.cyan, ["@string.escape"] = p.cyan, ["@character"] = p.cyan,
    ["@constant"] = p.bright_red, ["@constant.builtin"] = p.bright_red,
    ["@number"] = p.yellow, ["@boolean"] = p.bright_red,
    ["@keyword"] = p.magenta, ["@keyword.function"] = p.magenta,
    ["@keyword.return"] = p.magenta, ["@conditional"] = p.magenta,
    ["@repeat"] = p.magenta, ["@operator"] = p.magenta, ["@preproc"] = p.magenta,
    ["@function"] = p.green, ["@function.call"] = p.green,
    ["@function.method"] = p.green, ["@function.method.call"] = p.green,
    ["@constructor"] = p.green,
    ["@variable"] = p.white, ["@parameter"] = p.white, ["@field"] = p.white,
    ["@property"] = p.white, ["@punctuation"] = p.white,
    ["@type"] = p.yellow, ["@type.builtin"] = p.yellow,
    ["@module"] = p.yellow, ["@namespace"] = p.yellow,
    ["@special"] = p.bright_red, ["@error"] = p.red,
  }
  for g, c in pairs(ts) do set(g, { fg = c }) end
end

return M
