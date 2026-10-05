-- multicursor.nvim: several cursors at once, each doing what you type.
-- Run by plato after the plugin loads; edit freely (plato's plugin panel,
-- "configure", opens this file).
--
-- NOT ON <leader>. Space never reaches nvim in plato — it opens plato's own
-- leader menu — so the plugin's usual <leader> bindings could never fire.
-- These are keys the editor passes through, and the rest is on the leader
-- menu's "m" group (editor/actions.js), which calls the same functions.
--
--   <C-n>              a cursor at the next match of the word / selection
--                      (VS Code's Ctrl-D)
--   <C-Up> <C-Down>    a cursor on the line above / below
--   Ctrl + click       a cursor where you click (again: take it away)
--   with several:  <Left> <Right> make another one the main cursor,
--                  <Esc> goes back to one
--
-- Plato draws the extra cursors itself, from the plugin's highlights: a
-- cyan block like plato's own cursor, and Visual for their selections.

local mc = require("multicursor-nvim")
mc.setup()

local set = vim.keymap.set
set({ "n", "x" }, "<C-n>", function() mc.matchAddCursor(1) end)
set({ "n", "x" }, "<C-Up>", function() mc.lineAddCursor(-1) end)
set({ "n", "x" }, "<C-Down>", function() mc.lineAddCursor(1) end)
set("n", "<C-LeftMouse>", mc.handleMouse)
set("n", "<C-LeftDrag>", mc.handleMouseDrag)
set("n", "<C-LeftRelease>", mc.handleMouseRelease)

mc.addKeymapLayer(function(layerSet)
  layerSet({ "n", "x" }, "<Left>", mc.prevCursor)
  layerSet({ "n", "x" }, "<Right>", mc.nextCursor)
  layerSet("n", "<Esc>", function()
    if not mc.cursorsEnabled() then mc.enableCursors() else mc.clearCursors() end
  end)
end)

-- plato's cursor ink (Zenon's cyan, from plato's palette)
local p = require("plato.palette")
local hl = vim.api.nvim_set_hl
hl(0, "MultiCursorCursor", { bg = p.cyan, fg = p.black })
hl(0, "MultiCursorVisual", { link = "Visual" })
hl(0, "MultiCursorSign", { link = "SignColumn" })
hl(0, "MultiCursorMatchPreview", { link = "Search" })
hl(0, "MultiCursorDisabledCursor", { bg = p.bright_black or "#555555", fg = p.black })
hl(0, "MultiCursorDisabledVisual", { link = "Visual" })
hl(0, "MultiCursorDisabledSign", { link = "SignColumn" })
