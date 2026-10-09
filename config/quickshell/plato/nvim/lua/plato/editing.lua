-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/
--
-- The editing behaviour plato's settings sheet controls, and the few things
-- the engine tells plato about edits as they happen.
--
--   options(p)      the sheet's editing settings, applied to this nvim
--   :w with no name plato's save dialog, rather than E32
--   on save         trailing spaces trimmed, the file formatted (each a setting)
--   flashes         a yank or a delete, sent as screen cells for plato to light
--   the : line      completions offered as you type (wildtrigger)

local api = vim.api
local M = {}
local send = function() end

-- ── the settings ───────────────────────────────────────────────────────
-- core/Settings.qml's editing settings, sent by every window on connect and
-- whenever one changes. The window-local ones go to every ordinary window as
-- well as the global value, so a :vsplit made later gets them too; indent
-- goes to every ordinary buffer already open.
function M.options(p)
  local function each_win(fn)
    for _, w in ipairs(api.nvim_list_wins()) do
      if api.nvim_win_get_config(w).relative == "" then fn(w) end
    end
  end
  if p.wrap ~= nil then
    vim.o.wrap = p.wrap
    each_win(function(w) vim.wo[w].wrap = p.wrap end)
  end
  if p.relativeNumbers ~= nil then
    vim.o.relativenumber = p.relativeNumbers
    each_win(function(w) vim.wo[w].relativenumber = p.relativeNumbers end)
  end
  if p.scrollOff ~= nil then
    vim.o.scrolloff = p.scrollOff
    each_win(function(w) vim.wo[w].scrolloff = vim.g.plato_typewriter and 999 or -1 end)
  end
  if p.tabWidth ~= nil or p.expandTab ~= nil then
    local tw, et = p.tabWidth or vim.o.tabstop, p.expandTab
    if et == nil then et = vim.o.expandtab end
    vim.o.tabstop, vim.o.shiftwidth, vim.o.softtabstop, vim.o.expandtab = tw, tw, tw, et
    for _, b in ipairs(api.nvim_list_bufs()) do
      if api.nvim_buf_is_loaded(b) and vim.bo[b].buftype == "" then
        vim.bo[b].tabstop, vim.bo[b].shiftwidth, vim.bo[b].softtabstop = tw, tw, tw
        vim.bo[b].expandtab = et
      end
    end
  end
  if p.smartCase ~= nil then
    vim.o.ignorecase = p.smartCase
    vim.o.smartcase = p.smartCase
  end
  if p.completeAsYouType ~= nil then vim.o.autocomplete = p.completeAsYouType end
  if p.cmdlineAsYouType ~= nil then vim.g.plato_cmdline_complete = p.cmdlineAsYouType end
  if p.trimOnSave ~= nil then vim.g.plato_trim = p.trimOnSave end
  if p.formatOnSave ~= nil then vim.g.plato_format = p.formatOnSave end
  if p.editFlash ~= nil then vim.g.plato_flash = p.editFlash end
  if p.gitBlame ~= nil then vim.g.plato_blame = p.gitBlame end
  if p.stickyScroll ~= nil then vim.g.plato_sticky = p.stickyScroll end
  if p.reopenTabs ~= nil then vim.g.plato_reopen = p.reopenTabs end
  if p.zen ~= nil then vim.g.plato_zen = p.zen end
  if p.minimap ~= nil then vim.g.plato_minimap = p.minimap end
  if p.minimapRows ~= nil then require("plato.minimap").setRows(p.minimapRows) end
  if p.indentGuides ~= nil then vim.g.plato_guides = p.indentGuides end
  if p.rainbowBrackets ~= nil then vim.g.plato_rainbow = p.rainbowBrackets end
  if p.suggestParsers ~= nil then vim.g.plato_suggest_parsers = p.suggestParsers end
  if type(p.markdown) == "table" then vim.g.plato_md = p.markdown end
  if p.largeFileMB ~= nil then vim.g.plato_large_mb = p.largeFileMB end
  -- TYPEWRITER (zen only, PlatoWindow decides): the cursor's line held in
  -- the middle — a scrolloff no window is tall enough to satisfy. Off, every
  -- window goes back to the global value the settings sheet keeps.
  if p.typewriter ~= nil and p.typewriter ~= (vim.g.plato_typewriter == true) then
    vim.g.plato_typewriter = p.typewriter
    each_win(function(w) vim.wo[w].scrolloff = p.typewriter and 999 or -1 end)
  end
  require("plato.view").schedule(true)
  return true
end

-- ── the : line, completed as you type ──────────────────────────────────
-- nvim 0.12's cmdline autocompletion: wildtrigger() on every change opens the
-- wildmenu without selecting anything, so Enter still runs what was typed;
-- Tab and the arrows move through it. The menu arrives as popupmenu events
-- on the command line's grid, which StatusBar draws above the bar.
-- <Up>/<Down> close it first, so they still walk the history.
local function cmdlineComplete()
  vim.o.wildmode = "noselect:lastused,full"
  vim.o.wildoptions = "pum,fuzzy"
  api.nvim_create_autocmd("CmdlineChanged", {
    pattern = ":",
    callback = function()
      if vim.g.plato_cmdline_complete == false then return end
      vim.fn.wildtrigger()
    end,
  })
  vim.keymap.set("c", "<Up>", function()
    return vim.fn.wildmenumode() == 1 and "<C-e><Up>" or "<Up>"
  end, { expr = true })
  vim.keymap.set("c", "<Down>", function()
    return vim.fn.wildmenumode() == 1 and "<C-e><Down>" or "<Down>"
  end, { expr = true })
end

-- ── :w WITH NO NAME TO WRITE TO ────────────────────────────────────────
-- A new buffer has no file, and :w answered it with E32 in the status line.
-- Enter on such a command line is taken instead: the command is dropped and
-- plato is asked to open its save dialog (terminus'), which writes with
-- :saveas — and quits after, for :wq and :x.
local writes = {
  w = 1, wr = 1, wri = 1, writ = 1, write = 1,
  up = 1, upd = 1, upda = 1, updat = 1, update = 1,
  wq = 2, x = 2, xi = 2, xit = 2, exi = 2, exit = 2,
}
function M.unnamedWrite(line)
  local c = line:match("^%s*(%a+)!?%s*$")
  local kind = c and writes[c]
  if not kind then return nil end
  if api.nvim_buf_get_name(0) ~= "" or vim.bo.buftype ~= "" then return nil end
  return kind
end
-- :w :wq :x and the like, bare, for a buffer that is root's (root.lua)
function M.rootWrite(line)
  local c = line:match("^%s*(%a+)!?%s*$")
  local kind = c and writes[c]
  if not kind or not vim.b.plato_root then return nil end
  return kind
end
local function saveAsOnWrite()
  vim.keymap.set("c", "<CR>", function()
    if vim.fn.getcmdtype() == ":" then
      local kind = M.unnamedWrite(vim.fn.getcmdline())
      if kind then
        vim.schedule(function() send({ event = "saveAs", quit = kind == 2 }) end)
        return "<C-c>"
      end
      -- a file this user cannot write: plato asks, and writes it as root
      -- (root.lua) — nvim's own :w would only say E505
      kind = M.rootWrite(vim.fn.getcmdline())
      if kind then
        local buf = api.nvim_get_current_buf()
        vim.schedule(function() require("plato.root").ask(buf, kind == 2) end)
        return "<C-c>"
      end
    end
    return "<CR>"
  end, { expr = true })
end

-- ── on save ────────────────────────────────────────────────────────────
-- Both off by default, both settings. Trimming leaves markdown's two-space
-- line break alone; formatting asks a language server that says it can.
local function trim(buf)
  local md = vim.bo[buf].filetype == "markdown"
  local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
  for i, l in ipairs(lines) do
    local tail = l:match("%s+$")
    if tail and not (md and tail == "  " and l:find("%S")) then
      api.nvim_buf_set_lines(buf, i - 1, i, false, { l:sub(1, #l - #tail) })
    end
  end
end
-- FORMATTING: conform.nvim's formatters for the filetype when it is loaded
-- and has some that are installed (stylua, shfmt, prettier, ruff — see
-- config/conform.nvim.lua), the language server's otherwise. Space l f
-- and format-on-save both come here.
function M.format(buf)
  buf = buf or api.nvim_get_current_buf()
  local before = api.nvim_buf_get_lines(buf, 0, -1, false)
  local okc, conform = pcall(require, "conform")
  if okc then
    pcall(conform.format, { bufnr = buf, timeout_ms = 1500, lsp_format = "fallback" })
  elseif #vim.lsp.get_clients({ bufnr = buf, method = "textDocument/formatting" }) > 0 then
    pcall(vim.lsp.buf.format, { bufnr = buf, timeout_ms = 1500 })
  end
  M.flashChanged(buf, before)
end
local function onSave()
  -- a file in a directory that is not there yet (a new note, a capture
  -- file): the directory is made, rather than :w failing with E212
  api.nvim_create_autocmd("BufWritePre", {
    callback = function(ev)
      if vim.bo[ev.buf].buftype ~= "" or ev.match:match("^%a+://") then return end
      local dir = vim.fs.dirname(vim.fn.fnamemodify(ev.match, ":p"))
      if dir and not vim.uv.fs_stat(dir) then pcall(vim.fn.mkdir, dir, "p") end
    end,
  })
  api.nvim_create_autocmd("BufWritePre", {
    callback = function(ev)
      if vim.bo[ev.buf].buftype ~= "" or vim.bo[ev.buf].binary then return end
      if vim.g.plato_format then M.format(ev.buf) end
      if vim.g.plato_trim then
        local view = vim.fn.winsaveview()
        trim(ev.buf)
        vim.fn.winrestview(view)
      end
    end,
  })
  -- written: counted per buffer, for the status line's "saved" flash
  -- (status.lua `saved`) — root.lua's own writes fire this too
  api.nvim_create_autocmd("BufWritePost", {
    callback = function(ev)
      vim.b[ev.buf].plato_saved = (vim.b[ev.buf].plato_saved or 0) + 1
      require("plato.view").schedule()
    end,
  })
end

-- ── the flash ──────────────────────────────────────────────────────────
-- What a yank took lights up, and what a delete took fades out where it was.
-- Both are plato's to draw (EditorView's flashes) and nvim's to measure: the
-- region, as runs of screen cells on nvim's grid, { row, col, len }, all
-- 0-based. Only what is on screen, and only in an ordinary window.
--
-- TextYankPost comes BEFORE a delete takes the text away — measured: dd's
-- yank sees the buffer still four lines long — so the cells measured here
-- are where the text was, and the window still has its old rows when plato
-- gets this, a frame ahead of the one without them. That is what lets the
-- delete's ghost be drawn from the text that is about to go.
local function cells(win, regtype, s, t)
  local e = vim.v.event
  s = s or api.nvim_buf_get_mark(0, "[")
  t = t or api.nvim_buf_get_mark(0, "]")
  if s[1] == 0 or t[1] == 0 then return {} end
  local info = vim.fn.getwininfo(win)[1]
  local textL = info.wincol - 1 + info.textoff
  local textR = info.wincol - 1 + info.width
  local top, bot = info.topline, info.botline
  local rt = regtype or e.regtype or "v"
  local block = rt:sub(1, 1) == "\22"
  local out = {}
  local function add(row, c0, c1)
    if row > 0 and c1 > c0 then out[#out + 1] = { row = row - 1, col = c0, len = c1 - c0 } end
  end
  local leftcol = vim.fn.winsaveview().leftcol
  for l = math.max(s[1], top), math.min(t[1], bot) do
    if vim.fn.foldclosed(l) == -1 then
      local line = vim.fn.getline(l)
      if rt == "V" then
        -- a whole line is its text, from the first character to the last:
        -- not the indent before it, nor the empty width past it
        local b0 = line:find("%S")
        if not b0 then
          add(vim.fn.screenpos(win, l, 1).row, textL, textL + 1)
        else
          local b1 = #line - #line:match("%s*$")
          local p0 = vim.fn.screenpos(win, l, b0)
          local p1 = vim.fn.screenpos(win, l, b1)
          if p0.row > 0 and p1.row > 0 then
            if p0.row == p1.row then add(p0.row, p0.col - 1, p1.endcol)
            else
              add(p0.row, p0.col - 1, textR)
              for r = p0.row + 1, p1.row - 1 do add(r, textL, textR) end
              add(p1.row, textL, p1.endcol)
            end
          else
            -- scrolled sideways past it: the rows, whole
            local r0 = vim.fn.screenpos(win, l, 1).row
            local r1 = vim.fn.screenpos(win, l, math.max(1, #line)).row
            for r = r0, math.max(r0, r1) do add(r, textL, textR) end
          end
        end
      elseif block then
        -- display columns, from the two corners
        local v0 = vim.fn.virtcol({ s[1], s[2] + 1 }) - 1
        local v1 = vim.fn.virtcol({ t[1], t[2] + 1 })
        if v0 > v1 then v0, v1 = v1 - 1, v0 + 1 end
        local r = vim.fn.screenpos(win, l, 1).row
        add(r, math.max(textL, textL + v0 - leftcol), math.min(textR, textL + v1 - leftcol))
      else
        local b0 = l == s[1] and s[2] or 0
        local b1 = l == t[1] and math.min(#line, t[2] + 1) or #line
        if #line == 0 then
          -- a line break taken with nothing on the line: one cell
          add(vim.fn.screenpos(win, l, 1).row, textL, textL + 1)
        else
          local p0 = vim.fn.screenpos(win, l, b0 + 1)
          local p1 = vim.fn.screenpos(win, l, math.max(b0 + 1, b1))
          if p0.row > 0 and p1.row > 0 then
            if p0.row == p1.row then add(p0.row, p0.col - 1, p1.endcol)
            else
              add(p0.row, p0.col - 1, textR)
              for r = p0.row + 1, p1.row - 1 do add(r, textL, textR) end
              add(p1.row, textL, p1.endcol)
            end
          end
        end
      end
    end
  end
  return out
end
-- ── THE YANK HISTORY ───────────────────────────────────────────────────
-- Every yank and delete that went to a register, newest first, the last
-- thirty — what plato's "Paste from history" picker lists (yanks()) and puts
-- back (putYank()). The same text twice is kept once, at the top.
M.ring = {}
function M.yanks()
  local out = {}
  for i, y in ipairs(M.ring) do
    out[i] = { text = table.concat(y.lines, "\n"), lines = #y.lines, regtype = y.regtype }
  end
  return out
end
function M.putYank(i)
  local y = M.ring[i]
  if not y then return false end
  local linewise = y.regtype == "V"
  M.notePut()
  api.nvim_put(y.lines, linewise and "l" or (y.regtype:sub(1, 1) == "\22" and "b" or "c"), true, true)
  -- the chosen one goes back to the top, and into the unnamed register
  table.remove(M.ring, i)
  table.insert(M.ring, 1, y)
  vim.fn.setreg('"', y.lines, y.regtype)
  return true
end
local function remember()
  -- mini.move carries a line in register z; that is no yank
  if vim.b.minibracketed_disable then return end
  local e = vim.v.event
  local lines = e.regcontents
  if not lines or #lines == 0 or (#lines == 1 and lines[1]:match("^%s*$")) then return end
  local key = table.concat(lines, "\n")
  for i = #M.ring, 1, -1 do
    if table.concat(M.ring[i].lines, "\n") == key then table.remove(M.ring, i) end
  end
  table.insert(M.ring, 1, { lines = vim.deepcopy(lines), regtype = e.regtype })
  while #M.ring > 30 do table.remove(M.ring) end
end

-- ── A MOVED LINE SLIDES ────────────────────────────────────────────────
-- mini.move (Alt j/k) moves a line, or a selection of them, by yanking it
-- into register z, deleting it and putting it back a line on: a yank and a
-- put, which flashed as both. It is neither. Where its lines were on screen
-- is noted at the yank (mini.move's commands run with
-- b:minibracketed_disable set, which is how it is told from a real "zy);
-- where they are now, at the TextChanged that follows the whole move — sent
-- as a "move", which plato draws as the rows sliding to their new places.
local moving = nil
-- the screen rows of lines l1..l2 in `win`: the first (0-based) and how many
local function screenRows(win, l1, l2)
  local r0 = vim.fn.screenpos(win, l1, 1).row
  local r1 = vim.fn.screenpos(win, l2, math.max(1, #vim.fn.getline(l2))).row
  if r0 == 0 or r1 < r0 then return nil end
  return r0 - 1, r1 - r0 + 1
end
local function noteMove(win)
  moving = nil
  if vim.v.event.regtype ~= "V" then return end
  local s, t = api.nvim_buf_get_mark(0, "["), api.nvim_buf_get_mark(0, "]")
  if s[1] == 0 or t[1] == 0 then return end
  local row, n = screenRows(win, s[1], t[1])
  if row then moving = { win = win, buf = api.nvim_get_current_buf(), row = row, n = n } end
end
local function sendMove()
  local m = moving
  moving = nil
  if vim.g.plato_flash == false then return end
  local win = api.nvim_get_current_win()
  if win ~= m.win or api.nvim_get_current_buf() ~= m.buf then return end
  local s, t = api.nvim_buf_get_mark(0, "["), api.nvim_buf_get_mark(0, "]")
  if s[1] == 0 or t[1] == 0 then return end
  local row, n = screenRows(win, s[1], t[1])
  -- a line that wraps differently where it landed: no slide, only the move
  if row and n == m.n and row ~= m.row then
    send({ event = "flash", kind = "move", from = m.row, to = row, rows = n })
  end
end

local function flashes()
  api.nvim_create_autocmd("TextYankPost", { callback = remember })
  api.nvim_create_autocmd("TextChanged", {
    callback = function() if moving then sendMove() end end,
  })
  api.nvim_create_autocmd("TextYankPost", {
    callback = function()
      local win0 = api.nvim_get_current_win()
      if vim.b.minibracketed_disable then
        if vim.v.event.operator == "y" and api.nvim_win_get_config(win0).relative == "" then
          pcall(noteMove, win0)
        end
        return
      end
      if vim.g.plato_flash == false then return end
      local op = vim.v.event.operator
      local kind = op == "y" and "yank" or op == "d" and "delete" or nil
      if not kind then return end
      local win = api.nvim_get_current_win()
      if api.nvim_win_get_config(win).relative ~= "" then return end
      local ok, list = pcall(cells, win)
      if ok and #list > 0 then
        send({ event = "flash", kind = kind, linewise = vim.v.event.regtype == "V", cells = list })
      end
    end,
  })
end

-- ── EDITS ARRIVING, SEEN ───────────────────────────────────────────────
-- A paste (p, P, gp, ]p, the yank history) and a format light up what they
-- brought in, a green wash that ebbs as a yank's yellow does: text you did
-- not type appearing should be seen to appear. A put is told apart from
-- other changes by the key that started it (on_key: p or P in normal or
-- visual mode, not after f t r m, where p is a character); a format by
-- comparing the buffer before and after it.
local putPending = false
local lastKey = ""
function M.notePut() putPending = true end
local function puts()
  vim.on_key(function(key, typed)
    -- mini.move's own put (see A MOVED LINE SLIDES) is not a paste
    if vim.b.minibracketed_disable then return end
    local k = (typed and typed ~= "") and typed or key
    local m = api.nvim_get_mode().mode
    if (k == "p" or k == "P") and (m == "n" or m == "v" or m == "V" or m == "\22")
        and not lastKey:match("^[fFtTrm]$") then
      putPending = true
    elseif k ~= "g" and k ~= "]" and k ~= "[" and not k:match("^%d$") and k ~= '"' then
      -- only the keys of the same command keep it pending
      if not lastKey:match('^"$') then putPending = false end
    end
    lastKey = k
  end, api.nvim_create_namespace("plato.puts"))
end
-- `put`: a paste, which the window SLIDES in (room opened, the new text
-- uncovered — the delete's gap played forwards); without it (a format) the
-- green wash. `linewise` says which room: lines, or cells in one.
local function sendArrive(win, list, put, linewise)
  if #list > 0 then
    send({ event = "flash", kind = "arrive", cells = list, put = put or nil, linewise = linewise or nil })
  end
end
-- after a put: '[ and '] hold what it brought
function M.flashPut()
  putPending = false
  if vim.g.plato_flash == false then return end
  local win = api.nvim_get_current_win()
  if api.nvim_win_get_config(win).relative ~= "" then return end
  local rt = vim.fn.getregtype(vim.v.register)
  local lw = rt:sub(1, 1) == "V"
  local ok, list = pcall(cells, win, lw and "V" or "v")
  if ok then sendArrive(win, list, true, lw) end
end
-- the lines a change rewrote, from the buffer as it was: each hunk vim.diff
-- finds, flashed as whole lines
function M.flashChanged(buf, before)
  if vim.g.plato_flash == false then return end
  local win = api.nvim_get_current_win()
  if api.nvim_win_get_buf(win) ~= buf or api.nvim_win_get_config(win).relative ~= "" then return end
  local after = api.nvim_buf_get_lines(buf, 0, -1, false)
  local diff = vim.text and vim.text.diff or vim.diff
  local ok, hunks = pcall(diff, table.concat(before, "\n") .. "\n", table.concat(after, "\n") .. "\n",
    { result_type = "indices" })
  if not ok then return end
  local list = {}
  for _, h in ipairs(hunks) do
    local s, n = h[3], h[4]
    if n > 0 then
      local okc, part = pcall(cells, win, "V", { s, 0 }, { s + n - 1, 0 })
      if okc then for _, c in ipairs(part) do list[#list + 1] = c end end
    end
  end
  sendArrive(win, list)
end

-- ── UNDO AND REDO, SEEN ────────────────────────────────────────────────
-- An undo sweeps back across the text it changed, a redo forward: nvim
-- leaves the changed stretch in the '[ and '] marks, and which way the
-- change went is in the change number. Per buffer: the number last seen and
-- the highest there has been. Lower than last time is an undo; higher, but
-- not past the highest, is a redo; past it is a new edit, which is not
-- flashed (it is what you just typed). changenr() is one number — the whole
-- undotree() is asked for only once per buffer, for where the redo history
-- reaches when it was read back from an undo file.
--
-- What lights up is the text the step wrote, character by character, as
-- nvim_buf_attach's on_bytes reports it — not the '[ '] lines, which cover
-- whole lines (and one past the change): a redo that brings back the tail
-- of a line lights that tail only. A step that only took text away has no
-- text to show; one cell marks where it went.
local seq = {}
local wrote = {}
local function noteBytes(_, buf, _, sr, sc, _, oer, oec, _, ner, nec)
  local list = wrote[buf]
  if not list then return end
  -- lines added or removed above shift what an earlier step of the same
  -- undo block recorded below them
  local d = ner - oer
  if d ~= 0 then
    for _, r in ipairs(list) do
      if r[1] > sr + oer then r[1], r[3] = r[1] + d, r[3] + d end
    end
  end
  if #list < 400 then
    -- 5–8: the change's own extents, for slideOf
    list[#list + 1] = { sr, sc, sr + ner, ner == 0 and sc + nec or nec, oer, oec, ner, nec }
  end
end
-- cells on one screen row that touch or overlap become one (a redo of
-- typing replays it a character or a few at a time)
local function mergeCells(list)
  table.sort(list, function(a, b) return a.row < b.row or (a.row == b.row and a.col < b.col) end)
  local out = {}
  for _, c in ipairs(list) do
    local p = out[#out]
    if p and p.row == c.row and c.col <= p.col + p.len then
      p.len = math.max(p.len, c.col + c.len - p.col)
    else
      out[#out + 1] = { row = c.row, col = c.col, len = c.len }
    end
  end
  return out
end
local function wroteCells(win, buf)
  local out, gone = {}, {}
  for _, r in ipairs(wrote[buf] or {}) do
    local r0, c0, r1, c1 = r[1], r[2], r[3], r[4]
    local n = api.nvim_buf_line_count(buf)
    if r0 < n then
      local s, t
      local into = out
      if r1 == r0 and c1 <= c0 then
        -- only taken away: one cell where it was
        s, t, into = { r0 + 1, c0 }, { r0 + 1, c0 }, gone
      else
        if c1 == 0 and r1 > r0 then
          -- ends with a line break: the last line written whole
          r1 = r1 - 1
          c1 = #(api.nvim_buf_get_lines(buf, r1, r1 + 1, false)[1] or "")
        end
        local first = api.nvim_buf_get_lines(buf, r0, r0 + 1, false)[1] or ""
        if c0 >= #first and r1 > r0 then r0, c0 = r0 + 1, 0 end
        s, t = { r0 + 1, c0 }, { math.min(r1, n - 1) + 1, math.max(c1 - 1, 0) }
      end
      local ok, part = pcall(cells, win, "v", s, t)
      if ok then for _, c in ipairs(part) do into[#into + 1] = c end end
    end
  end
  if #out == 0 then
    -- nothing written: the first place something went, one cell
    return gone[1] and { gone[1] } or {}
  end
  return mergeCells(out)
end
-- ── AN UNDO SLIDES, AS AN EDIT DOES ─────────────────────────────────────
-- A step that is ONE plain change — text only added, or only taken away,
-- whole lines or within one line — is told to the window as the slide a
-- paste or a delete plays (the user asked: "omni-directional like
-- delete"): `in` with the cells it wrote, or `out` with cells over what it
-- took (the rows on screen still hold it: the flash goes out a frame ahead
-- of them, so the window draws the ghost from them). Anything else (a
-- replacement, several changes) keeps the sweep. nil for those.
local function slideOf(win, buf, r)
  if not r or not r[5] then return nil end
  local sr, sc, oer, oec, ner, nec = r[1], r[2], r[5], r[6], r[7], r[8]
  local info = vim.fn.getwininfo(win)[1]
  local textL = info.wincol - 1 + info.textoff
  local n = api.nvim_buf_line_count(buf)
  local function rowOf(line)
    if line > n then
      local p = vim.fn.screenpos(win, n, 1)
      return p.row > 0 and p.row or 0
    end
    local p = vim.fn.screenpos(win, line, 1)
    return p.row > 0 and p.row - 1 or -1
  end
  if sc == 0 and oec == 0 and nec == 0 and oer ~= ner then
    if ner > oer then
      -- counted, not read off the cells: a blank line written has none
      local row = rowOf(sr + 1)
      if row < 0 then return nil end
      return { dir = "in", linewise = true, row = row, n = ner - oer }
    end
    -- whole lines taken: where they were, the text width of each row
    local row = rowOf(sr + 1)
    if row < 0 then return nil end
    local out = {}
    for k = 0, oer - ner - 1 do
      out[#out + 1] = { row = row + k, col = textL, len = info.width - info.textoff }
    end
    return { dir = "out", linewise = true, cells = out }
  end
  if oer == 0 and ner == 0 then
    if nec > 0 and oec == 0 then return { dir = "in", linewise = false, n = nec } end
    if oec > 0 and nec == 0 then
      local p = vim.fn.screenpos(win, sr + 1, sc + 1)
      if p.row == 0 then
        -- the line's end: one past its last character
        local line = api.nvim_buf_get_lines(buf, sr, sr + 1, false)[1] or ""
        p = vim.fn.screenpos(win, sr + 1, math.max(1, #line))
        if p.row == 0 then return nil end
        p = { row = p.row, col = p.endcol + 1 }
        if #line == 0 then p.col = textL + 1 end
      end
      return { dir = "out", linewise = false, cells = { { row = p.row - 1, col = p.col - 1, len = oec } } }
    end
  end
  return nil
end
-- Several records on one line are one change by their NET: an undo of
-- typing comes back as a run of small replacements (completion swapping the
-- word as it was typed), which together took " tail" away. The leftmost
-- start, and what was added less what was taken. nil when they span lines
-- or net to nothing.
local function oneChange(list)
  -- records that changed nothing (a plugin's no-op set_text) do not count
  local real = {}
  for _, r in ipairs(list) do
    if not (r[5] == 0 and r[6] == 0 and r[7] == 0 and r[8] == 0) then real[#real + 1] = r end
  end
  list = real
  if #list == 1 then return list[1] end
  local row, sc, net = nil, math.huge, 0
  for _, r in ipairs(list) do
    if not r[5] or r[5] ~= 0 or r[7] ~= 0 then return nil end
    if row and r[1] ~= row then return nil end
    row = r[1]
    sc = math.min(sc, r[2])
    net = net + r[8] - r[6]
  end
  if net == 0 then return nil end
  return { row, sc, row, sc + math.max(0, net), 0, math.max(0, -net), 0, math.max(0, net) }
end
local function undos()
  local function know(buf)
    local okt, ut = pcall(vim.fn.undotree, buf)
    local cur = api.nvim_buf_call(buf, vim.fn.changenr)
    seq[buf] = { cur = cur, max = okt and math.max(ut.seq_last, cur) or cur }
    if not wrote[buf] and api.nvim_buf_is_loaded(buf) then
      wrote[buf] = {}
      api.nvim_buf_attach(buf, false, {
        on_bytes = noteBytes,
        on_detach = function(_, b) wrote[b] = nil end,
      })
    end
  end
  api.nvim_create_autocmd({ "BufReadPost", "BufNewFile", "BufEnter" }, {
    callback = function(ev) if not seq[ev.buf] then know(ev.buf) end end,
  })
  api.nvim_create_autocmd("BufWipeout", { callback = function(ev) seq[ev.buf] = nil end })
  -- each step's bytes start afresh: typing in insert mode collects nothing
  -- past its own TextChangedI
  api.nvim_create_autocmd({ "TextChangedI", "TextChangedP" }, {
    callback = function(ev) if wrote[ev.buf] then wrote[ev.buf] = {} end end,
  })
  -- typing changes the number too, and fires only TextChangedI: kept up to
  -- date here, so the undo of what was just typed reads as an undo
  api.nvim_create_autocmd({ "TextChangedI", "TextChangedP", "InsertLeave" }, {
    callback = function(ev)
      local s = seq[ev.buf]
      if not s then return end
      local cur = vim.fn.changenr()
      s.cur, s.max = cur, math.max(s.max, cur)
    end,
  })
  api.nvim_create_autocmd("TextChanged", {
    callback = function(ev)
      local s = seq[ev.buf]
      if not s then know(ev.buf); return end
      local cur = vim.fn.changenr()
      local kind
      if cur < s.cur then kind = "undo"
      elseif cur > s.cur and cur <= s.max then kind = "redo" end
      s.cur, s.max = cur, math.max(s.max, cur)
      local bytes = wrote[ev.buf]
      if bytes then wrote[ev.buf] = {} end
      if not kind and putPending then M.flashPut(); return end
      if not kind or vim.g.plato_flash == false then return end
      local win = api.nvim_get_current_win()
      if api.nvim_win_get_config(win).relative ~= "" or api.nvim_win_get_buf(win) ~= ev.buf then return end
      local list
      local slide = bytes and #bytes > 0 and slideOf(win, ev.buf, oneChange(bytes)) or nil
      if bytes then
        wrote[ev.buf] = bytes
        list = wroteCells(win, ev.buf)
        wrote[ev.buf] = {}
      else
        -- not attached (yet): the '[ '] lines whole, as before
        local ok, l = pcall(cells, win, "V")
        list = ok and l or {}
      end
      if slide and slide.dir == "out" then
        send({ event = "flash", kind = kind, cells = slide.cells, slide = "out", linewise = slide.linewise })
      elseif #list > 0 or (slide and slide.dir == "in") then
        send({ event = "flash", kind = kind, cells = list,
               slide = slide and "in" or nil, linewise = slide and slide.linewise or nil,
               slideRow = slide and slide.row or nil, slideN = slide and slide.n or nil })
      end
    end,
  })
end

-- ── gf ON A PICTURE ─────────────────────────────────────────────────────
-- A path to an image under the cursor opens in Picasso, the shell's
-- viewer, rather than as a buffer of binary. Anything else is nvim's gf.
local images = { png = 1, jpg = 1, jpeg = 1, gif = 1, webp = 1, bmp = 1, svg = 1,
  tif = 1, tiff = 1, avif = 1, ico = 1, jxl = 1, heic = 1 }
function M.imagePath(f)
  if not f or f == "" then return nil end
  local ext = (f:match("%.([%w]+)$") or ""):lower()
  if not images[ext] then return nil end
  local p = vim.fn.expand(f)
  if p:sub(1, 1) ~= "/" then
    local here = vim.fn.expand("%:p:h")
    p = (here ~= "" and here or vim.fn.getcwd()) .. "/" .. p
  end
  p = vim.fs.normalize(p)
  return vim.uv.fs_stat(p) and p or nil
end
local function pictures()
  vim.keymap.set("n", "gf", function()
    local p = M.imagePath(vim.fn.expand("<cfile>"))
    if not p then return "gf" end
    vim.system({ "qs", "ipc", "call", "Picasso", "view", p })
    return ""
  end, { expr = true, desc = "Go to file (pictures open in Picasso)" })
end

function M.setup(sendFn)
  send = sendFn
  pictures()
  cmdlineComplete()
  saveAsOnWrite()
  onSave()
  flashes()
  puts()
  undos()
end

return M
