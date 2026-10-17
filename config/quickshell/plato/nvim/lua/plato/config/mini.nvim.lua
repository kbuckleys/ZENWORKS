-- mini.nvim: a library of small modules, each switched on by its setup().
-- Run by plato after the plugin loads; edit freely (plato's plugin panel,
-- "configure", opens this file). mini.nvim is one of plato's core plugins —
-- its mini.diff draws git's changed lines (plato/nvim/lua/plato/git.lua, set
-- up there, not here) — so it cannot be switched off, but each module below
-- can be, by taking its line out.

-- sa sd sr: add, delete and replace what surrounds a text object
-- (saiw" quotes a word, sd( takes the brackets off, sr"' swaps the quotes)
require("mini.surround").setup()

-- better a and i text objects: arguments (daa, cia), function calls (dif),
-- quotes and brackets of any kind (ciq, cib) — and the NEXT or LAST one, so
-- ci"  works before the cursor reaches the string (cin" cil")
require("mini.ai").setup({ n_lines = 200 })

-- Alt with h j k l moves the line, or the selection, as one piece: up and
-- down past its neighbors, left and right by an indent. Its indentation goes
-- with it as it was: mini.move's default re-indents a line it moves up or down
-- (`=`), which rewrote it to whatever the filetype's indent rules guessed
-- (user, 2026-10-11) — Alt h/l is the way to change it.
require("mini.move").setup({ options = { reindent_linewise = false } })

-- gS: an argument list (a table, an array…) split one item to a line, or
-- joined back onto one
require("mini.splitjoin").setup()

-- ga: line things up on a character — ga= on a block of assignments, or
-- ga, on a table — with a live preview as you choose
require("mini.align").setup()

-- brackets and quotes closed as they are opened, and stepped over as their
-- closing one is typed
require("mini.pairs").setup({ modes = { insert = true, command = false, terminal = false } })

-- TODO, FIXME, HACK and NOTE picked out wherever they are written. (Color
-- codes — #rrggbb, Qt.rgba — are plato's own: view.lua paints them already.)
local hp = require("mini.hipatterns")
local p = require("plato.palette")
local function word(w) return "%f[%w]()" .. w .. "()%f[%W]" end
hp.setup({
  highlighters = {
    fixme = { pattern = word("FIXME"), group = "MiniHipatternsFixme" },
    hack  = { pattern = word("HACK"),  group = "MiniHipatternsHack" },
    todo  = { pattern = word("TODO"),  group = "MiniHipatternsTodo" },
    note  = { pattern = word("NOTE"),  group = "MiniHipatternsNote" },
  },
})
local hl = vim.api.nvim_set_hl
hl(0, "MiniHipatternsFixme", { fg = p.black, bg = p.red, bold = true })
hl(0, "MiniHipatternsHack",  { fg = p.black, bg = p.magenta, bold = true })
hl(0, "MiniHipatternsTodo",  { fg = p.black, bg = p.yellow, bold = true })
hl(0, "MiniHipatternsNote",  { fg = p.black, bg = p.cyan, bold = true })
