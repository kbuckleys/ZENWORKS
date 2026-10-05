-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/
--
-- Plato's engine. This nvim never draws anything: it runs headless, and the
-- window you type into is quickshell's. Everything here is either editing
-- behaviour (kept from the terminal nvim config where it was about editing) or engine
-- setup that makes nvim's view of the screen match the one plato draws.
--
-- ISOLATED BY NVIM_APPNAME=quickshell/plato/nvim, set by the process that
-- starts us (core/NvimClient.qml): data, state and cache live under
-- ~/.local/{share,state}/quickshell/plato/nvim and ~/.cache/quickshell/plato/nvim,
-- so undo history and shada never mix with any other nvim's. Not by
-- overriding XDG_*_HOME — that would leak into every child nvim starts
-- (an LSP server, a :! command) and send them looking in the wrong places.

local here = vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))
vim.opt.runtimepath:prepend(here)
-- nvim's matchparen marks the pair with window matches, which no frame
-- reads; plato outlines the pair itself (brackets.lua), so it only cost time
vim.g.loaded_matchparen = 1

-- ── the screen is plato's ──────────────────────────────────────────────
-- nvim's window IS plato's viewport: one window, filling the whole grid,
-- with nothing of nvim's own chrome taking rows or columns from it. The
-- gutter, statusline and command line are all drawn in QML, so every one of
-- these is off — a status line here would be a row plato's lines are
-- measured against and never shows.
vim.o.laststatus = 0
vim.o.showtabline = 0
vim.o.cmdheight = 0
vim.o.ruler = false
vim.o.showmode = false
-- showcmd is ON but shown nowhere: 'showcmdloc' puts it in a statusline
-- that is never drawn, and status.lua reads it back (%S) for plato's own
vim.o.showcmd = true
vim.o.showcmdloc = "statusline"
-- The gutter IS nvim's: every window reserves its own number and sign
-- columns, so its text starts where nvim says (getwininfo().textoff) and a
-- split's two gutters are each the right width. plato draws the numbers
-- and signs into those cells itself; statuscolumn stays empty because
-- nothing nvim would render there is ever shown.
vim.o.number = true
vim.o.relativenumber = true
-- room for four digits and the three cells plato keeps between a number and
-- the text it numbers (EditorRow); nvim's own one-cell gap read as cramped,
-- and so did two
vim.o.numberwidth = 7
vim.o.signcolumn = "yes"
vim.o.foldcolumn = "0"
vim.o.statuscolumn = ""
-- wrapped, as the terminal nvim is; nvim decides where the rows break and the
-- view model reports them (see view.lua)
vim.o.wrap = true
vim.o.sidescroll = 1
vim.o.sidescrolloff = 4
-- no prompt can be answered from a window that does not exist: a "-- More --"
-- would stall every key after it
vim.o.more = false
vim.o.mouse = "a"
vim.opt.fillchars = { eob = " ", fold = " " }

-- ── editing, as the terminal nvim had it (options.lua) ─────────────────
vim.g.mapleader = " "
vim.o.tabstop = 4
vim.o.softtabstop = 4
vim.o.shiftwidth = 4
vim.o.expandtab = true
vim.o.smartindent = true
vim.o.ignorecase = true
vim.o.smartcase = true
vim.o.swapfile = false
vim.o.backup = false
vim.o.undofile = true
vim.o.undodir = vim.fn.stdpath("data") .. "/undodir"
vim.opt.clipboard:append("unnamedplus")
vim.opt.isfname:append("@-@")
vim.o.scrolloff = 8
vim.opt.shortmess:append("cIF")

-- ── editing binds, as the terminal nvim had them (binds.lua) ───────────
-- Only the ones about text. Buffer cycling, finders and file managers are
-- application bindings and belong to plato's own keymap.
local map = vim.keymap.set
map("n", "<Esc>", "<cmd>nohlsearch<cr>", { silent = true })
-- moving lines (Alt j/k, and h/l) is mini.move's: config/mini.nvim.lua
map("v", "<", "<gv")
map("v", ">", ">gv")
map("n", "J", "mzJ`z")
map("n", "n", "nzzzv")
map("n", "N", "Nzzzv")
-- buffers, which are plato's tabs: <C-c> closes one, as the terminal nvim
-- had it. <C-Tab> and <C-S-Tab> are plato's own (EditorView): they follow
-- the tabs' order, which plato keeps and nvim does not know.
map("n", "<C-c>", "<cmd>bdelete<cr>", { silent = true })
-- Ctrl-V pastes, as everywhere else on the desktop: in insert mode the
-- clipboard goes in as typed text without auto-indent (<C-r><C-o>), and on
-- the : line it is inserted too. Normal mode keeps <C-v> for visual block;
-- a literal character is still <C-q> in insert mode.
map("i", "<C-v>", "<C-r><C-o>+", { silent = true })
map("c", "<C-v>", "<C-r>+")

-- Retain cursor position across sessions, as the terminal nvim does
vim.api.nvim_create_autocmd("BufReadPost", {
  callback = function()
    local mark = vim.api.nvim_buf_get_mark(0, '"')
    local lcount = vim.api.nvim_buf_line_count(0)
    if mark[1] > 0 and mark[1] <= lcount then
      pcall(vim.api.nvim_win_set_cursor, 0, mark)
    end
  end,
})

-- ── colours ────────────────────────────────────────────────────────────
require("plato.theme").apply()

-- ── treesitter ─────────────────────────────────────────────────────────
-- nvim bundles a handful of parsers (lua, c, vim, markdown, …); the queries
-- for everything else come with nvim-treesitter (see plugins.lua). A language
-- with no parser falls back to the regex engine, which plato also draws.
vim.api.nvim_create_autocmd("FileType", {
  callback = function(ev)
    local lang = vim.treesitter.language.get_lang(ev.match)
    -- not for a file too big for it (large.lua)
    if lang and not vim.b[ev.buf].plato_large then pcall(vim.treesitter.start, ev.buf, lang) end
  end,
})


-- ── diagnostics, as the terminal nvim had them (lsp.lua) ───────────────
vim.diagnostic.config({
  virtual_text = { prefix = "▪", spacing = 2 },
  underline = true,
  severity_sort = true,
})

-- ── what the settings sheet controls, and the flashes ─────────────────
-- see editing.lua: cmdline autocompletion, :w with no file name, trimming
-- and formatting on save, and the yank and delete flashes plato draws
require("plato.editing").setup(function(obj) require("plato.bridge").send(obj) end)
-- insert mode's GUI keys: shift selects, ctrl moves and deletes by words,
-- ctrl c / x / v / a / z (cua.lua)
require("plato.cua").setup()
-- the minimap's text, sent beside the frames (minimap.lua)
require("plato.minimap").setup(function(obj) require("plato.bridge").send(obj) end)
-- who last changed the cursor's line (git.lua)
require("plato.git").blame()
-- each project's open files, kept and brought back (sessions.lua)
require("plato.sessions").setup()
-- pinned files on Alt 1-9 (pins.lua)
require("plato.pins").setup()
-- files this user cannot write, saved as root (root.lua)
require("plato.root").setup()
-- files changed on disk under an open buffer (disk.lua)
require("plato.disk").setup()
-- the file's outline and the status line's breadcrumb (symbols.lua)
require("plato.symbols").setup()
-- files too big for the extras (large.lua)
require("plato.large").setup()
-- spelling, and z= as plato's menu (spell.lua)
require("plato.spell").setup(function(obj) require("plato.bridge").send(obj) end)

require("plato.bridge").start(vim.env.PLATO_SOCK)

-- ── plugins and language servers (see plugins.lua) ─────────────────────
-- AFTER the bridge is listening. On a fresh machine loading them means
-- cloning them first, and a window cannot wait that long for a socket that
-- is not there yet: it would give up and close. Listening first, it connects
-- at once and is told what is happening while the clones run.
-- completion is nvim's own and needs no plugin; see plugins.lua
require("plato.plugins").completion()

vim.schedule(function()
  local plugins = require("plato.plugins")
  plugins.load()
  plugins.lsp()
  -- git's changed lines, from mini.diff once it is loaded (see git.lua)
  require("plato.git").setup()
  -- buffers opened while plugins were loading missed their FileType
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].filetype ~= "" then
      vim.api.nvim_exec_autocmds("FileType", { buffer = b, modeline = false })
    end
  end
end)
