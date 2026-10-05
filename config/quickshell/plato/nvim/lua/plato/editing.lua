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
  local okc, conform = pcall(require, "conform")
  if okc then
    pcall(conform.format, { bufnr = buf, timeout_ms = 1500, lsp_format = "fallback" })
  elseif #vim.lsp.get_clients({ bufnr = buf, method = "textDocument/formatting" }) > 0 then
    pcall(vim.lsp.buf.format, { bufnr = buf, timeout_ms = 1500 })
  end
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
local function cells(win, regtype)
  local e = vim.v.event
  local s = api.nvim_buf_get_mark(0, "[")
  local t = api.nvim_buf_get_mark(0, "]")
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
        local r0 = vim.fn.screenpos(win, l, 1).row
        local r1 = vim.fn.screenpos(win, l, math.max(1, #line)).row
        for r = r0, math.max(r0, r1) do add(r, textL, textR) end
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
  api.nvim_put(y.lines, linewise and "l" or (y.regtype:sub(1, 1) == "\22" and "b" or "c"), true, true)
  -- the chosen one goes back to the top, and into the unnamed register
  table.remove(M.ring, i)
  table.insert(M.ring, 1, y)
  vim.fn.setreg('"', y.lines, y.regtype)
  return true
end
local function remember()
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

local function flashes()
  api.nvim_create_autocmd("TextYankPost", { callback = remember })
  api.nvim_create_autocmd("TextYankPost", {
    callback = function()
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

-- ── UNDO AND REDO, SEEN ────────────────────────────────────────────────
-- An undo sweeps back across the text it changed, a redo forward: nvim
-- leaves the changed stretch in the '[ and '] marks, and which way the
-- change went is in the change number. Per buffer: the number last seen and
-- the highest there has been. Lower than last time is an undo; higher, but
-- not past the highest, is a redo; past it is a new edit, which is not
-- flashed (it is what you just typed). changenr() is one number — the whole
-- undotree() is asked for only once per buffer, for where the redo history
-- reaches when it was read back from an undo file.
local seq = {}
local function undos()
  local function know(buf)
    local okt, ut = pcall(vim.fn.undotree, buf)
    local cur = api.nvim_buf_call(buf, vim.fn.changenr)
    seq[buf] = { cur = cur, max = okt and math.max(ut.seq_last, cur) or cur }
  end
  api.nvim_create_autocmd({ "BufReadPost", "BufNewFile", "BufEnter" }, {
    callback = function(ev) if not seq[ev.buf] then know(ev.buf) end end,
  })
  api.nvim_create_autocmd("BufWipeout", { callback = function(ev) seq[ev.buf] = nil end })
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
      if not kind or vim.g.plato_flash == false then return end
      local win = api.nvim_get_current_win()
      if api.nvim_win_get_config(win).relative ~= "" then return end
      -- an undo's marks are lines (nvim sets them to the first and last
      -- line it touched, column 0): the sweep covers those lines whole
      local ok, list = pcall(cells, win, "V")
      if ok and #list > 0 then send({ event = "flash", kind = kind, cells = list }) end
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
  undos()
end

return M
