-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/
--
-- The bridge: how plato talks to this nvim.
--
-- WHY NOT NVIM'S OWN RPC. It is msgpack, which is binary, and every channel
-- quickshell offers QML — Process stdio, Socket — is typed QString. Bytes
-- pass through a UTF-8 decode on the way in and come out mangled. So the
-- bridge lives in here instead, where Lua can speak something text-shaped:
-- one JSON object per line over a unix socket, which a SplitParser on the
-- QML side cuts up for free.
--
--   plato → nvim   {"id":3,"method":"input","params":{"keys":"dd"}}
--   nvim → plato   {"id":3,"result":true}           the reply, when there is one
--                  {"event":"view", ...}             whenever the screen changes
--
-- ONE CLIENT AT A TIME. A second connection replaces the first: that is what
-- a shell reload looks like from here, the old window's socket dying and the
-- rebuilt one arriving.
--
-- NVIM OUTLIVES ITS WINDOW BRIEFLY, AND NO LONGER. A shell reload tears the
-- window down and builds it again, and nvim must still be here when it comes
-- back — that is why it is started detached rather than as a child. The price
-- of detaching is that nothing will kill it, so it has to notice for itself:
-- when its client goes and none comes back within GRACE_MS, it quits. A window
-- that is closed on purpose says `quit` and nvim goes at once.

local uv = vim.uv
local api = vim.api
local view = require("plato.view")

local M = {}
local GRACE_MS = 5000

local server, client
local grace = uv.new_timer()
local deadline = uv.new_timer()

-- ── THE GRACE CANNOT BE LEFT TO THE MAIN LOOP ALONE ────────────────────
-- The polite exit — keep what was not saved, then :qall — has to run on
-- nvim's main loop, and the main loop can be stuck: a prompt raised while
-- nobody is connected (plugins installing, say) waits for an answer that
-- will never come, and everything scheduled waits behind it. Found for real:
-- three engines from windows that died in a shell reload before they ever
-- connected, alive eleven hours later, idle, holding their sockets.
--
-- So every grace carries a deadline that does NOT need the main loop. A
-- libuv timer's own callback runs whatever nvim is stuck in; if the polite
-- exit has not happened ten seconds after it was due, nvim is signalled to
-- stop (SIGTERM, which it handles by exiting), and killed outright if that
-- is not enough either. A client arriving cancels both.
-- nvim gone in `ms` whatever its main loop is doing: SIGTERM then, and
-- SIGKILL five seconds after that if it is still here. `unless` is asked
-- first, from the timer's own callback, and can call it off.
local function killAfter(ms, unless)
  deadline:start(ms, 0, function()
    if unless and unless() then return end
    local pid = uv.os_getpid()
    uv.kill(pid, "sigterm")
    deadline:start(5000, 0, function() uv.kill(pid, "sigkill") end)
  end)
end

local function armGrace(ms)
  grace:start(ms, 0, vim.schedule_wrap(function()
    if not client then M.quit() end
  end))
  killAfter(ms + 10000, function() return client ~= nil end)
end
local function disarmGrace()
  grace:stop()
  deadline:stop()
end
local buffered = ""

local function send(obj)
  if not client or client:is_closing() then return end
  local ok, line = pcall(vim.json.encode, obj)
  if not ok then
    -- a buffer holding bytes that are not UTF-8 cannot be JSON; say so
    -- rather than dropping the frame silently
    line = vim.json.encode({ event = "error", message = "encode: " .. tostring(line) })
  end
  client:write(line .. "\n")
end
M.send = send

-- ── keeping what was not saved ─────────────────────────────────────────
-- swapfile is off (as in the terminal nvim), so a quit with modified buffers
-- would lose them. Anything modified is written beside the rest of plato's
-- state and named in a notification before nvim goes.
local function rescue()
  local saved = {}
  for _, b in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_loaded(b) and vim.bo[b].modified and vim.bo[b].buftype == "" then
      local name = api.nvim_buf_get_name(b)
      local base = name ~= "" and vim.fs.basename(name) or "untitled"
      local dir = vim.fn.stdpath("state") .. "/rescue"
      vim.fn.mkdir(dir, "p")
      -- the buffer's number too: two new buffers rescued in the same second
      -- were both "…-untitled", and the second overwrote the first
      local out = ("%s/%s-%d-%s"):format(dir, os.date("%Y%m%d-%H%M%S"), b, base)
      vim.fn.writefile(api.nvim_buf_get_lines(b, 0, -1, false), out)
      saved[#saved + 1] = vim.fn.fnamemodify(out, ":~")
    end
  end
  -- PLATO_QUIET: the bridge test drives this path and must not put toasts
  -- on the desktop of whoever runs it
  if #saved > 0 and vim.env.PLATO_QUIET ~= "1" then
    vim.system({ "notify-send", "-a", "Plato", "Unsaved changes kept",
      table.concat(saved, "\n") }):wait(2000)
  end
end

function M.quit()
  rescue()
  if server then pcall(uv.fs_unlink, M.path) end
  vim.cmd("qall!")
end

-- ── the methods ─────────────────────────────────────────────────────────
local methods = {}

-- keys in nvim's notation, into the input queue
function methods.input(p)
  return api.nvim_input(p.keys)
end

function methods.open(p)
  vim.cmd.edit(vim.fn.fnameescape(p.path))
  view.schedule(true)
  return true
end

-- plato's rows and columns become nvim's: the one window fills the grid, so
-- this is the viewport's size too
function methods.resize(p)
  local rows = math.max(1, math.floor(p.rows))
  local cols = math.max(1, math.floor(p.cols))
  if vim.o.lines ~= rows then vim.o.lines = rows end
  if vim.o.columns ~= cols then vim.o.columns = cols end
  view.schedule(true)
  return true
end

-- The wheel: moves the view of the window under the pointer (row and col are
-- grid cells), and its cursor only as far as scrolloff insists. Answers
-- whether the view moved — false at the top or the end, which is plato's cue
-- for the rubber band.
function methods.scroll(p)
  local n = math.floor(p.lines)
  if n == 0 then return true end
  local target = api.nvim_get_current_win()
  if p.row and p.col then
    for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
      if api.nvim_win_get_config(w).relative == "" then
        local pos = api.nvim_win_get_position(w)
        if p.row >= pos[1] and p.row < pos[1] + api.nvim_win_get_height(w)
            and p.col >= pos[2] and p.col < pos[2] + api.nvim_win_get_width(w) then
          target = w
          break
        end
      end
    end
  end
  local key = n > 0 and "\5" or "\25"
  return api.nvim_win_call(target, function()
    local before = vim.fn.winsaveview()
    if n > 0 then
      -- NOT PAST THE END. <C-e> goes on until the last line is at the top,
      -- leaving a screen of nothing under it; the wheel stops once the last
      -- line is in view, as every other scrolling surface does. (nvim's own
      -- <C-e> and <C-d> on the keyboard still go as far as they always have.)
      local last = api.nvim_buf_line_count(0)
      for _ = 1, n do
        if vim.fn.line("w$") >= last then break end
        vim.cmd("normal! " .. key)
      end
    else
      vim.cmd("normal! " .. math.abs(n) .. key)
    end
    local after = vim.fn.winsaveview()
    return before.topline ~= after.topline or before.skipcol ~= after.skipcol
  end)
end

-- A scrollbar dragged: window `win` shows `line` at its top. The cursor is
-- carried along, just inside 'scrolloff' of the new view, as the wheel
-- carries it — left where it was, nvim would scroll straight back to it.
function methods.scrollTo(p)
  local win = p.win
  if not (win and api.nvim_win_is_valid(win)) then return false end
  api.nvim_win_call(win, function()
    local last = api.nvim_buf_line_count(0)
    local h = api.nvim_win_get_height(0)
    -- the bar ends with the last line at the bottom, not at the top
    local top = math.max(1, math.min(math.max(1, last - h + 1), math.floor(p.line)))
    local so = math.min(vim.wo.scrolloff, math.floor((h - 1) / 2))
    local cur = api.nvim_win_get_cursor(0)[1]
    local lo = math.min(last, top + so)
    local hi = math.max(lo, math.min(last, top + h - 1 - so))
    vim.fn.winrestview({ topline = top, lnum = math.max(lo, math.min(hi, cur)) })
  end)
  view.schedule()
  return true
end

-- a click, in window cells. nvim_input_mouse does the rest natively: a
-- click places the cursor, a drag makes a visual selection.
function methods.mouse(p)
  -- rendered markdown (markdown.lua): its rows hide and widen text, so a
  -- plain left click there is placed here, by what the row shows
  if p.button == "left" and p.action == "press" and (p.mods or "") == "" then
    local w, l, b = view.clickAt(p.row, p.col)
    if w then
      vim.schedule(function()
        if not api.nvim_win_is_valid(w) then return end
        api.nvim_set_current_win(w)
        pcall(api.nvim_win_set_cursor, w, { l + 1, b })
        view.schedule()
      end)
      return true
    end
  end
  api.nvim_input_mouse(p.button, p.action, p.mods or "", 0, p.row, p.col)
  return true
end

-- the tabs: show a buffer, or close one. Closing a modified buffer is
-- refused by nvim (E89) and the refusal reaches the status line, so a tab's
-- close button cannot lose unsaved work.
-- ── BACK WHERE YOU LEFT IT ───────────────────────────────────────────────
-- nvim brings back a buffer's cursor, not its view: the top line is worked
-- out again from the cursor and 'scrolloff', so going back to a tab could
-- land a row off from how you left it. The whole view (top line, cursor,
-- leftcol, skipcol) is kept per buffer on the way out and put back on the
-- way in. A jump INTO a buffer (a definition, a grep hit) still lands where
-- it aims: those place the cursor after entering, and nvim scrolls to it.
do
  local g = api.nvim_create_augroup("plato_views", { clear = true })
  api.nvim_create_autocmd("BufLeave", {
    group = g,
    callback = function(a)
      if vim.bo[a.buf].buftype == "" then vim.b[a.buf].plato_view = vim.fn.winsaveview() end
    end,
  })
  api.nvim_create_autocmd("BufEnter", {
    group = g,
    callback = function(a)
      local v = vim.b[a.buf].plato_view
      if v and vim.bo[a.buf].buftype == "" then pcall(vim.fn.winrestview, v) end
    end,
  })
end

function methods.bufShow(p)
  if api.nvim_buf_is_valid(p.id) then api.nvim_set_current_buf(p.id) end
  return true
end
function methods.bufClose(p)
  if not api.nvim_buf_is_valid(p.id) then return true end
  local ok, err = pcall(vim.cmd.bdelete, { args = { tostring(p.id) }, bang = p.force == true })
  if not ok then vim.notify(tostring(err):gsub("^.-(E%d+)", "%1"), vim.log.levels.ERROR) end
  return ok
end

-- ── for the picker and the leader menu ─────────────────────────────────
-- The project the current file belongs to: the nearest directory holding a
-- .git, or this shell's own markers — or, for a file in no project, the
-- directory it is in (nvim's working directory is wherever plato was
-- started, which for a file in /tmp is nothing to do with it). A buffer with
-- no file gets home. Files, grep and the tree all work under it.
function methods.root()
  local buf = api.nvim_win_get_buf(0)
  local name = api.nvim_buf_get_name(buf)
  -- a new buffer, in a new window: home — not the project nvim's working
  -- directory happens to be in (vim.fs.root asks that, for a buffer with
  -- no name), which is wherever the shell was started
  if name == "" then return vim.env.HOME end
  return require("plato.util").rootOf(name)
end

-- FORK: what is selected, copied into a new buffer with no file — a new
-- tab, unsaved, in the same language. With nothing selected, the line the
-- cursor is on. The selection is left behind (back to normal mode) in the
-- buffer it came from.
function methods.fork()
  local mode = api.nvim_get_mode().mode
  local visual = mode == "v" or mode == "V" or mode == "\22"
  local lines = visual
    and vim.fn.getregion(vim.fn.getpos("v"), vim.fn.getpos("."), { type = mode })
    or { api.nvim_get_current_line() }
  local ft = vim.bo.filetype
  if visual then api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false) end
  vim.cmd.enew()
  api.nvim_buf_set_lines(0, 0, -1, false, lines)
  vim.bo.filetype = ft
  view.schedule(true)
  return #lines
end

-- FILES DROPPED ON THE WINDOW (from terminus, or any file manager): each
-- opened as a tab, the last one shown. A directory is not a file to edit;
-- it is passed over, and said so. Answers the buffers, in the order given,
-- so plato can put their tabs where they were dropped.
function methods.dropped(p)
  local ids, skipped = {}, 0
  for _, path in ipairs(p.paths or {}) do
    if vim.fn.isdirectory(path) == 1 then skipped = skipped + 1
    else
      local ok = pcall(vim.cmd.edit, vim.fn.fnameescape(path))
      if ok then ids[#ids + 1] = api.nvim_get_current_buf() end
    end
  end
  if skipped > 0 then
    vim.notify(skipped == 1 and "A directory is not opened as a tab"
      or (skipped .. " directories are not opened as tabs"), vim.log.levels.WARN)
  end
  view.schedule(true)
  return ids
end

-- THE START CARD (an empty window): the files opened lately, the files
-- pinned anywhere, and the projects with tabs kept. Paths are whole.
function methods.startCard()
  local recent, seen = {}, {}
  for _, f in ipairs(vim.v.oldfiles or {}) do
    if #recent >= 9 then break end
    local p = vim.fn.fnamemodify(f, ":p")
    if not seen[p] and not p:match("^%a+://") and not p:find("/rescue/", 1, true)
        and vim.fn.filereadable(p) == 1 then
      seen[p] = true
      recent[#recent + 1] = p
    end
  end
  local projects = {}
  for i, s in ipairs(require("plato.sessions").projects()) do
    if i > 6 then break end
    projects[#projects + 1] = { root = s.root, files = s.files, ago = require("plato.util").ago(s.at) }
  end
  local pins = {}
  for i, p in ipairs(require("plato.pins").all()) do
    if i > 6 then break end
    pins[#pins + 1] = p
  end
  return { recent = recent, pins = pins, projects = projects }
end
-- a project from the start card: its tabs back, the first of them shown
function methods.openProject(p)
  local was = api.nvim_get_current_buf()
  local n = require("plato.sessions").restore(p.root)
  if n > 0 then
    for _, b in ipairs(api.nvim_list_bufs()) do
      local name = api.nvim_buf_get_name(b)
      if vim.bo[b].buflisted and name:sub(1, #p.root + 1) == p.root .. "/" then
        api.nvim_set_current_buf(b)
        break
      end
    end
    -- the empty buffer the window started with is not a tab worth keeping
    if was ~= api.nvim_get_current_buf() and api.nvim_buf_get_name(was) == ""
        and not vim.bo[was].modified and api.nvim_buf_line_count(was) == 1
        and api.nvim_buf_get_lines(was, 0, 1, false)[1] == "" then
      pcall(api.nvim_buf_delete, was, {})
    end
  end
  view.schedule(true)
  return n
end

-- each project's open files, back as tabs (sessions.lua)
function methods.restore(p) return require("plato.sessions").restore(p.root) end
-- the yank history, and putting one of it back (editing.lua)
function methods.yanks() return require("plato.editing").yanks() end
function methods.putYank(p) return require("plato.editing").putYank(p.index) end

-- the settings sheet's editing settings (see editing.lua)
function methods.options(p)
  return require("plato.editing").options(p)
end

-- every ex command nvim knows, for the command palette
function methods.commands()
  return vim.fn.getcompletion("", "command")
end

-- open a file, optionally at a line and column (1-based), as grep's results do
function methods.openAt(p)
  vim.cmd.edit(vim.fn.fnameescape(p.path))
  if p.line then
    local last = api.nvim_buf_line_count(0)
    pcall(api.nvim_win_set_cursor, 0, { math.min(p.line, last), math.max(0, (p.col or 1) - 1) })
    vim.cmd("normal! zz")
  end
  view.schedule(true)
  return true
end

-- A file was renamed or moved outside nvim — by plato's tree — and a buffer
-- may be showing it. The buffer follows it to its new name; one with no
-- unsaved changes is read again from there, so nvim does not think it is a
-- new file that would overwrite something on the next :w.
--
-- A DIRECTORY TOO. The tree renames those as well, and every buffer inside
-- one was left holding a path that no longer existed: its next :w failed.
function methods.renamed(p)
  if not p.from or p.from == "" or not p.to or p.to == "" then
    view.schedule(true)
    return true
  end
  local from = p.from:gsub("/+$", "")
  local to = p.to:gsub("/+$", "")
  for _, b in ipairs(api.nvim_list_bufs()) do
    local name = api.nvim_buf_get_name(b)
    local new
    if name == from then new = to
    elseif name:sub(1, #from + 1) == from .. "/" then new = to .. name:sub(#from + 1) end
    if new then
      api.nvim_buf_set_name(b, new)
      if not vim.bo[b].modified then
        api.nvim_buf_call(b, function() vim.cmd("silent! edit") end)
      end
    end
  end
  view.schedule(true)
  return true
end

-- run an ex command, as a menu item does. A failure is said in the status
-- line like any error, rather than lost.
function methods.cmd(p)
  local ok, err = pcall(vim.cmd, p.cmd)
  if not ok then
    vim.notify((tostring(err):gsub("^.-:%d+: ", "")), vim.log.levels.ERROR)
  end
  view.schedule()
  return ok
end

-- a click on a completion item: select it, put it in, close the menu
function methods.pumPick(p)
  api.nvim_select_popupmenu_item(p.index, true, true, {})
  return true
end

-- window closed on purpose
-- the undo history (undo.lua): the list, one state's diff, and going there
function methods.undoList() return require("plato.undo").list() end
function methods.undoPreview(p) return require("plato.undo").preview(p.seq) end
function methods.undoTo(p) require("plato.undo").go(p.seq); return true end

-- the file's outline (symbols.lua): [{ name, kind, line, col, depth }]
function methods.symbols() return require("plato.symbols").list() end

-- pinned files (pins.lua)
function methods.pins() return require("plato.pins").list() end
function methods.unpin(p) require("plato.pins").unpin(p.path); return true end

-- THE DIAGNOSTICS, AS A LIST: the current buffer's, or (all) every open
-- buffer's, worst first and then in file order, for the picker
--   [{ path, line, col, text, sev, source }]
function methods.diagnostics(p)
  local list = vim.diagnostic.get(p.all and nil or 0)
  table.sort(list, function(a, b)
    if a.severity ~= b.severity then return a.severity < b.severity end
    if a.bufnr ~= b.bufnr then return a.bufnr < b.bufnr end
    return a.lnum < b.lnum
  end)
  local out = {}
  for _, d in ipairs(list) do
    local name = api.nvim_buf_get_name(d.bufnr)
    if name ~= "" then
      out[#out + 1] = { path = name, line = d.lnum + 1, col = d.col + 1,
        text = (d.message or ""):gsub("\n.*", ""), sev = d.severity, source = d.source or "" }
    end
  end
  return out
end

-- REPLACE IN THE PROJECT. ripgrep finds every line (not just the picker's
-- first 300), they become the quickfix list, the first is opened, and the
-- command that does the replacing is handed back for plato to put on the
-- command line, the cursor where the replacement goes:
--   :cdo s/\v<query>//ge | update
-- Shown live, as any :s is (subst.lua knows :cdo), and nothing is changed
-- until Enter. The query is ripgrep's regex; \v reads near enough the same,
-- and smart case is kept (\c with no capitals in it).
function methods.projectReplace(p)
  local r = vim.system({ "rg", "--vimgrep", "--smart-case", "--hidden", "-g", "!.git",
    "--", p.query }, { cwd = p.root, text = true }):wait(10000)
  -- ONE ENTRY A LINE. --vimgrep gives a line once per match on it, and :cdo
  -- runs the :s once per entry: the first did the whole line (g), and every
  -- one after it found nothing left and said E486.
  local items, files, seen, count = {}, {}, {}, 0
  for line in (r.stdout or ""):gmatch("[^\n]+") do
    local f, l, c, t = line:match("^(.-):(%d+):(%d+):(.*)$")
    if f then
      local abs = f:sub(1, 1) == "/" and f or (p.root .. "/" .. f)
      count = count + 1
      if not seen[abs .. ":" .. l] then
        seen[abs .. ":" .. l] = true
        items[#items + 1] = { filename = abs, lnum = tonumber(l), col = tonumber(c), text = t }
        files[abs] = true
      end
    end
  end
  if #items == 0 then
    vim.notify("Nothing matches " .. p.query, vim.log.levels.WARN)
    return vim.NIL
  end
  vim.fn.setqflist({}, " ", { title = "Replace " .. p.query, items = items })
  vim.cmd("silent cfirst")
  local nfiles = vim.tbl_count(files)
  vim.notify(("%d matches in %d file%s — type the replacement, Enter to replace all")
    :format(count, nfiles, nfiles == 1 and "" or "s"))
  local q = p.query:gsub("/", "\\/")
  local case = q:find("%u") and "" or "\\c"
  view.schedule(true)
  -- e: a line ripgrep's regex matched and \v reads differently is passed
  -- over, rather than stopping the rest with an error
  return { cmd = "cdo s/\\v" .. case .. q .. "//ge | update", back = #"/ge | update" }
end

-- ── QUESTIONS, AS CARDS ────────────────────────────────────────────────
-- nvim's own prompts (confirm(), "Press ENTER", W11) wait for a key in a
-- command line nobody sees, and a headless nvim waiting on one stops
-- answering everything else. A question plato needs answered instead goes
-- out as a card in the corner (Toasts.qml) with its choices on it — a click,
-- or Alt and the choice's key — and the answer comes back here. Nothing
-- waits for it: `done(choice)` runs whenever it comes, with "" for a card
-- put away unanswered.
--   choices: { { key = "s", label = "Save as root" }, ... }
-- Kept until answered, and sent again to a window that reconnects (a shell
-- reload drops every card).
local asks, askSeq = {}, 0
function M.ask(text, tone, choices, done)
  askSeq = askSeq + 1
  asks[askSeq] = { done = done, msg = { event = "ask", ask = askSeq, text = text,
    tone = tone or "warn", choices = choices } }
  send(asks[askSeq].msg)
  return askSeq
end
-- a question that no longer stands (the buffer went), taken back
function M.unask(n)
  if not asks[n] then return end
  asks[n] = nil
  send({ event = "unask", ask = n })
end
function methods.answer(p)
  local a = asks[p.ask]
  asks[p.ask] = nil
  if a and a.done then a.done(p.choice or "") end
  view.schedule()
  return true
end
local function reask()
  local ns = vim.tbl_keys(asks)
  table.sort(ns)
  for _, n in ipairs(ns) do send(asks[n].msg) end
end

function methods.quit()
  vim.schedule(M.quit)
  return true
end

function methods.ping() return "pong" end

-- ── KEYS DO NOT WAIT FOR THE MAIN LOOP ─────────────────────────────────
-- A key typed mid-command — the second g of gg, the j of 10j, the second d
-- of dd — arrives while nvim is sitting in its key reader waiting for exactly
-- that key. Fed to nvim_input from a scheduled callback, as every request
-- used to be, the key went into the queue but the waiting reader was never
-- woken to look: it noticed only when something else woke it — 'timeoutlen'
-- for a key with mappings after it (dd took a second, behind marks.nvim's
-- dm), and nothing at all for a count. 10j did nothing; gg froze the window
-- until the hard deadline killed the engine. Fed from the socket callback
-- itself, in the fast context nvim_input is made for (a real UI's keys come
-- in exactly so, over RPC), the reader wakes at once.
--
-- ORDER STILL HOLDS. `open` has to run on the main loop (it runs :edit), and
-- keys sent straight after it must land in the file, not in the buffer
-- before it. Requests are taken in order: a fast one goes in at once only
-- when nothing slow is still ahead of it; otherwise it waits its turn, and
-- the slow one, once done, lets everything behind it through.
--
-- EXCEPT HALFWAY THROUGH A COMMAND. After " (a register), d, g, a count,
-- nvim sits in its key reader waiting for the rest — and runs NO scheduled
-- callbacks while it does. A slow request arriving then (the window's focus
-- coming back sends :checktime; the wheel, a resize) could never run, and
-- every key behind it, the very keys that would finish the command, waited
-- for it: the engine was wedged until the window closed and the hard
-- deadline killed it (found 2026-10-04, from " then a focus change). So
-- while nvim is mid-command (nvim_get_mode().blocking, which is safe to ask
-- here), keys go in ahead of a slow request that is waiting; it runs as
-- soon as the command is done.
--
-- ONCE A SLOW ONE IS RUNNING, KEYS GO IN. They can no longer overtake it,
-- and it may be waiting for them: a rename's "New name:" prompt is asked
-- from inside the request that opened it, and holding the answer back
-- until the request finished would wait forever.
local fast = { input = true, mouse = true }
local queue, slowAhead, slowRunning = {}, false, false

local function midCommand()
  local ok, m = pcall(api.nvim_get_mode)
  return ok and m.blocking == true
end

local function mayGo()
  if #queue == 0 then return false end
  if not slowAhead then return true end
  if fast[queue[1].method] ~= true then return false end
  return slowRunning or midCommand()
end

local function reply(msg, ok, res)
  if not msg.id then return end
  if ok then send({ id = msg.id, result = res == nil and vim.NIL or res })
  else send({ id = msg.id, error = tostring(res) }) end
end

local function pump()
  while mayGo() do
    local msg = table.remove(queue, 1)
    local fn = methods[msg.method]
    if not fn then
      reply(msg, false, "no such method: " .. tostring(msg.method))
    elseif fast[msg.method] then
      reply(msg, pcall(fn, msg.params or {}))
    else
      slowAhead = true
      vim.schedule(function()
        slowRunning = true
        pump()
        reply(msg, pcall(fn, msg.params or {}))
        slowAhead, slowRunning = false, false
        pump()
      end)
    end
  end
end

local function dispatch(msg)
  queue[#queue + 1] = msg
  pump()
end

local function onRead(err, chunk)
  if err or not chunk then
    -- the window went away: close our end and start counting
    if client then client:close() end
    client = nil
    armGrace(GRACE_MS)
    return
  end
  buffered = buffered .. chunk
  while true do
    local nl = buffered:find("\n", 1, true)
    if not nl then break end
    local line = buffered:sub(1, nl - 1)
    buffered = buffered:sub(nl + 1)
    if line ~= "" then
      local ok, msg = pcall(vim.json.decode, line)
      -- A quit is also held to the deadline, armed HERE, in the socket's own
      -- callback: the polite exit is scheduled like every request, and a
      -- main loop that is stuck would never get to it. Asked to go, nvim goes
      -- — nicely within eight seconds, or by signal after them.
      if ok and type(msg) == "table" and msg.method == "quit" then killAfter(8000) end
      if ok and type(msg) == "table" then dispatch(msg)
      else send({ event = "error", message = "bad request: " .. line }) end
    end
  end
end

-- ── the command line and messages ──────────────────────────────────────
-- A Lua UI can have these even though it cannot have the grid, and they
-- are exactly the parts plato wants to draw itself: ":" and "/" as its own
-- bar, and messages as its own notices. Forwarded as plain text; nvim's
-- highlight attributes on the chunks are dropped for now.
local function chunksText(content)
  local parts = {}
  for _, c in ipairs(content or {}) do parts[#parts + 1] = c[2] end
  return table.concat(parts)
end

local function attachUi()
  local ns = api.nvim_create_namespace("plato.ui")
  vim.ui_attach(ns, { ext_cmdline = true, ext_messages = true, ext_popupmenu = true },
  function(event, ...)
    local a = { ... }
    -- the completion menu: nvim still chooses what is in it and which item
    -- is selected (<C-n>, <C-p>, fuzzy filtering as you type); plato only
    -- draws it. row and col are where the completed word starts, in the
    -- same cells the view model uses.
    if event == "popupmenu_show" then
      local items = {}
      -- a path offered (paths.lua) carries the file, for plato to preview
      local offered = package.loaded["plato.paths"] and package.loaded["plato.paths"].offered or {}
      for i, it in ipairs(a[1]) do
        items[i] = { word = it[1], kind = it[2], menu = it[3],
                     path = (it[2] == "dir" or it[2] == "file") and offered[it[1]] or nil }
      end
      -- grid -1: anchored to the command line (ext_cmdline), where col is
      -- the byte in the command's text the completed word starts at
      send({ event = "pum", shown = true, items = items, selected = a[2],
             row = a[3], col = a[4], cmdline = a[5] == -1 })
      return
    elseif event == "popupmenu_select" then
      send({ event = "pum_select", selected = a[1] })
      return
    elseif event == "popupmenu_hide" then
      send({ event = "pum", shown = false })
      return
    end
    if event == "cmdline_show" then
      send({ event = "cmdline", shown = true, text = chunksText(a[1]), pos = a[2],
             firstc = a[3], prompt = a[4], level = a[6] })
    elseif event == "cmdline_pos" then
      send({ event = "cmdline_pos", pos = a[1] })
    elseif event == "cmdline_hide" then
      send({ event = "cmdline", shown = false })
    elseif event == "msg_show" then
      -- replace_last: this message takes the place of the one before it;
      -- append: it carries on the one before it (nvim 0.11's msg_show)
      -- msgId: a message that updates one already shown (a write's progress
      -- line, then its "written") carries the same one. NOT `id`: a line
      -- with an id is a reply to a request, and NvimClient took every
      -- message for one and dropped it — no notification ever arrived.
      local id = a[6]
      send({ event = "msg", kind = a[1], text = chunksText(a[2]),
             replace = a[3] == true, append = a[5] == true,
             msgId = (type(id) == "number" or type(id) == "string") and id or vim.NIL })
    elseif event == "msg_clear" then
      send({ event = "msg_clear" })
    end
    -- nothing else is handled, and nothing here may touch the API
  end)
end

function M.start(path)
  assert(path and path ~= "", "PLATO_SOCK is not set")
  M.path = path
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  pcall(uv.fs_unlink, path)
  server = uv.new_pipe(false)
  assert(server:bind(path))
  server:listen(8, function()
    local c = uv.new_pipe(false)
    server:accept(c)
    -- the newcomer wins: a reload's rebuilt window replacing its old self
    if client and not client:is_closing() then client:close() end
    client = c
    buffered = ""
    disarmGrace()
    c:read_start(onRead)
    vim.schedule(function()
      send({ event = "hello", pid = vim.fn.getpid() })
      -- the colours before the first frame that uses them
      view.reset()
      view.schedule(true)
      reask()
    end)
  end)
  view.setup(send)
  attachUi()
  -- nobody ever connected: the same grace applies from birth
  armGrace(GRACE_MS * 2)
end

return M
