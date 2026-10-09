-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/
--
-- Insert mode, as every other text box: the keys a GUI editor has.
--
--   ctrl ← →            a word back, a word on (nvim's own)
--   shift ← → ↑ ↓       select, a character or a line at a time
--   shift home / end    select to the start, the end of the line
--   shift page up/down  select a screen at a time
--   ctrl shift ← →      select a word at a time
--   ctrl shift home/end select to the top, the end of the file
--   ctrl a              select everything
--   ctrl backspace/del  delete a word back, a word on
--   ctrl c / x / v      copy, cut, paste
--   ctrl z, ctrl shift z undo, redo
--
-- With a selection up, typing replaces it, backspace and delete take it
-- away, the plain arrows put it down (← at its start, → at its end, as
-- everywhere else) and Esc puts it down where the cursor is. Insert mode
-- carries on throughout: none of this leaves it.
--
-- IT IS NVIM'S SELECT MODE, STARTED FROM INSERT (<C-o>gh): typing over it
-- and landing back in insert mode are nvim's own. Two things are not:
--
-- EXCLUSIVE, WHILE IT IS UP (and 'virtualedit' onemore, for the same reason). A GUI selection lies BETWEEN characters — the
-- cursor is a bar, and shift → from it takes one character. nvim's
-- 'selection' says so only when "exclusive", and that would also change
-- what v does in normal mode, so it is exclusive from the first shift key
-- until insert mode is left.
--
-- TYPING OVER IT KEEPS THE CLIPBOARD. Select mode deletes what it replaces
-- into the unnamed register, which here is the clipboard (unnamedplus): the
-- text just copied to paste over a word was gone by the time it was pasted.
-- Every printable key in select mode is therefore its own map, through the
-- black hole register. (A key outside ASCII still goes nvim's way.)

local api = vim.api
local M = {}

-- ── exclusive, while a selection is up ─────────────────────────────────
local saved = nil
local function exclusive()
  if saved == nil then saved = { vim.o.selection, vim.o.virtualedit } end
  vim.o.selection = "exclusive"
  -- the <C-o> that starts one from the end of a line would otherwise step
  -- the cursor back onto the last character, and the selection would begin
  -- one character early
  if not vim.o.virtualedit:find("onemore") and not vim.o.virtualedit:find("all") then
    vim.opt.virtualedit:append("onemore")
  end
end
local function restore()
  if saved ~= nil then vim.o.selection, vim.o.virtualedit = saved[1], saved[2]; saved = nil end
end

-- the selection's two ends, in order: { row, col } 1-based rows, 0-based
-- byte columns; the end is exclusive
local function ends()
  local v, c = vim.fn.getpos("v"), vim.fn.getpos(".")
  local a, b = { v[2], v[3] - 1 }, { c[2], c[3] - 1 }
  if a[1] > b[1] or (a[1] == b[1] and a[2] > b[2]) then a, b = b, a end
  return a, b
end

-- the text under the selection, as lines
local function text()
  local ok, lines = pcall(vim.fn.getregion, vim.fn.getpos("v"), vim.fn.getpos("."),
    { type = "v", exclusive = true })
  return ok and lines or {}
end

-- ── putting it down ────────────────────────────────────────────────────
-- Esc ends select mode back in insert mode at the cursor; this moves the
-- cursor first to whichever end of the selection the key says.
local landing = nil
function M.mark(where)
  local a, b = ends()
  landing = where == "start" and a or b
end
function M.land()
  if landing then pcall(api.nvim_win_set_cursor, 0, landing) end
  landing = nil
end

-- BACK ON THE ANCHOR IS NOTHING SELECTED. An exclusive selection whose two
-- ends meet still covers one character in nvim; in a GUI it is no selection
-- at all. So a step that lands back where it began puts it down.
function M.check()
  local v, c = vim.fn.getpos("v"), vim.fn.getpos(".")
  if v[2] == c[2] and v[3] == c[3] then
    api.nvim_feedkeys(api.nvim_replace_termcodes("<Esc>", true, false, true), "in", false)
  end
end

-- ── the clipboard ──────────────────────────────────────────────────────
function M.copy()
  local lines = text()
  if #lines == 0 then return end
  vim.fn.setreg("+", lines, "v")
  vim.fn.setreg('"', lines, "v")
end

-- ── a word forward, deleted ────────────────────────────────────────────
-- At the end of a line it joins the next, as a GUI's does; otherwise up to
-- the next word, into the black hole.
function M.deleteWord()
  local col = api.nvim_win_get_cursor(0)[2]
  local line = api.nvim_get_current_line()
  if col >= #line then return "<Del>" end
  return '<C-o>"_dw'
end

-- ── a step of the selection ────────────────────────────────────────────
-- The keys that move its end, each behind <C-o>: in select mode that is
-- visual mode for one command, then back. A motion that FAILS (h on the
-- first column) aborts the rest of the map, and would leave select mode
-- holding its phantom character; so each one is asked whether it can go
-- first, and at an edge does what a GUI does instead: ← wraps to the end
-- of the line above, → to the start of the next, ↑ on the first line goes
-- to its start, ↓ on the last to its end.
local function o(...)
  local out = {}
  for _, k in ipairs({ ... }) do out[#out + 1] = "<C-o>" .. k end
  return table.concat(out)
end
function M.step(name)
  local row, col = unpack(api.nvim_win_get_cursor(0))
  local last = api.nvim_buf_line_count(0)
  local len = #api.nvim_get_current_line()
  local first, final = row == 1 and col == 0, row == last and col >= len
  if name == "left" then
    if col > 0 then return o("h") end
    return row > 1 and o("k", "$") or ""
  elseif name == "right" then
    if col < len then return o("l") end
    return row < last and o("j", "0") or ""
  elseif name == "up" then return row > 1 and o("k") or o("0")
  elseif name == "down" then return row < last and o("j") or o("$")
  elseif name == "home" then return o("0")
  elseif name == "end" then return o("$")
  elseif name == "pageUp" then return row > 1 and o("<PageUp>") or o("0")
  elseif name == "pageDown" then return row < last and o("<PageDown>") or o("$")
  elseif name == "wordBack" then return first and "" or o("b")
  elseif name == "word" then return final and "" or o("w")
  elseif name == "top" then return o("gg", "0")
  elseif name == "bottom" then return o("G", "$")
  end
  return ""
end

-- ── the maps ───────────────────────────────────────────────────────────
function M.setup()
  local function i(lhs, rhs, opts) vim.keymap.set("i", lhs, rhs, opts or {}) end
  local function s(lhs, rhs, opts) vim.keymap.set("s", lhs, rhs, opts or {}) end

  -- start a selection from insert, then take the first step of it.
  -- gh selects nothing yet: an exclusive selection begins empty.
  local start = "<Cmd>lua require('plato.cua').begin()<CR><C-o>gh"
  local check = "<Cmd>lua require('plato.cua').check()<CR>"
  for lhs, name in pairs({
    ["<S-Left>"] = "left",        ["<S-Right>"] = "right",
    ["<S-Up>"] = "up",            ["<S-Down>"] = "down",
    ["<S-Home>"] = "home",        ["<S-End>"] = "end",
    ["<S-PageUp>"] = "pageUp",    ["<S-PageDown>"] = "pageDown",
    ["<C-S-Left>"] = "wordBack",  ["<C-S-Right>"] = "word",
    ["<C-S-Home>"] = "top",       ["<C-S-End>"] = "bottom",
  }) do
    i(lhs, function() return start .. M.step(name) .. check end, { expr = true })
    s(lhs, function() return M.step(name) .. check end, { expr = true })
  end
  i("<C-a>", "<Cmd>lua require('plato.cua').begin()<CR><C-o>gg<C-o>0<C-o>gh<C-o>G<C-o>$")
  s("<C-a>", "<Esc><C-a>", { remap = true })

  -- the plain keys put it down
  s("<Left>", "<Cmd>lua require('plato.cua').mark('start')<CR><Esc><Cmd>lua require('plato.cua').land()<CR>")
  s("<Right>", "<Cmd>lua require('plato.cua').mark('end')<CR><Esc><Cmd>lua require('plato.cua').land()<CR>")
  for _, k in ipairs({ "<Up>", "<Down>", "<Home>", "<End>", "<PageUp>", "<PageDown>",
                       "<C-Left>", "<C-Right>", "<C-Home>", "<C-End>" }) do
    s(k, "<Esc>" .. k)
  end

  -- taken away, and typed over, without touching the clipboard
  for _, k in ipairs({ "<BS>", "<Del>", "<C-BS>", "<C-Del>", "<C-h>" }) do
    s(k, '<C-g>"_d')
  end
  for c = 0x21, 0x7e do
    local ch = string.char(c)
    local lhs = ch == "<" and "<lt>" or ch
    s(lhs, '<C-g>"_c' .. lhs)
  end
  s("<Space>", '<C-g>"_c<Space>')
  s("<CR>", '<C-g>"_c<CR>')
  s("<Tab>", '<C-g>"_c<Tab>')

  -- the clipboard
  s("<C-c>", "<Cmd>lua require('plato.cua').copy()<CR>")
  s("<C-x>", "<C-g>d")
  -- over a selection; in plain insert mode <C-v> is init.lua's own paste
  s("<C-v>", '<C-g>"_c<C-r><C-o>+')

  -- words. nvim's <C-w> stops at where this insert began — a word typed
  -- after a selection was put down came off one piece at a time — unless
  -- 'backspace' has nostop (which is <C-u> as well, the same way)
  vim.opt.backspace:append("nostop")
  i("<C-BS>", "<C-w>")
  i("<C-Del>", M.deleteWord, { expr = true })

  -- undo
  i("<C-z>", "<C-o>u")
  i("<C-S-z>", "<C-o><C-r>")

  -- exclusive only while a selection is up: back as it was once insert
  -- mode is left (<C-o> passes through visual on the way)
  api.nvim_create_autocmd("ModeChanged", {
    callback = function()
      if saved == nil then return end
      local m = api.nvim_get_mode().mode
      -- insert mode too: the selection begins and ends there (and passes
      -- through niI, the <C-o> on the way in), and autocomplete's menu
      -- closing on the first key is a change of mode (ic → i) of its own.
      -- 'selection' means nothing to insert mode itself.
      if not m:match("^[vVsS\22\19i]") and m ~= "niI" then restore() end
    end,
  })
end

function M.begin() exclusive() end

return M
