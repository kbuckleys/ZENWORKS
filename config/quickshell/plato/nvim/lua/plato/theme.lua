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

local function palette() return require("plato.palette") end

function M.apply()
  local p = palette()
  local set = function(g, v) vim.api.nvim_set_hl(0, g, v) end
  vim.o.termguicolors = true
  vim.o.background = "dark"

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
