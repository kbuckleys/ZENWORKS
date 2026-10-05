-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/
--
-- WHAT THE STATUS LINE KNOWS, beyond the file and the cursor. nvim's own
-- statusline, ruler, showmode and showcmd are all off (init.lua), and with
-- them went things it is easy to be lost without — a macro recording, a
-- command half typed. They are gathered here into one small table that rides
-- on the view frame (view.lua `status`), sent only when it changed:
--
--   rec      the register a macro is being recorded into, or ""
--   pending  the keys of a command not finished yet ("2d", "\"a"): nvim's
--            showcmd text, read through %S ('showcmdloc' statusline). Only
--            what a frame can see: between the keys of one command nvim runs
--            nothing scheduled and no frame goes out, so plato fills that gap
--            with the keys it sent itself (EditorState.keysSent).
--   op       true while an operator waits for its motion (d, c, y, …)
--   sel      in visual mode: { lines, chars, words }
--   diag     the buffer's diagnostics by severity: { e, w, i, h }
--   lsp      { names = { … }, busy = "rust-analyzer: indexing 40%" | nil }
--   branch   the git branch (or a short commit, detached), "" outside git
--   diff     mini.diff's summary of the buffer: { a, c, d }
--   indent   { tabs, width }   and   eol "unix"|"dos"|"mac",  enc "utf-8"…

local api = vim.api
local M = {}

-- ── language servers at work ───────────────────────────────────────────
-- $/progress, as nvim hands it on (LspProgress): the latest message of each
-- client still working, dropped when it says "end"
local progress = {}
api.nvim_create_autocmd("LspProgress", {
  callback = function(ev)
    local d = ev.data or {}
    local v = d.params and d.params.value
    if type(v) ~= "table" then return end
    local id = d.client_id
    if v.kind == "end" then progress[id] = nil
    else
      local c = vim.lsp.get_client_by_id(id)
      local msg = v.title or ""
      if v.message and v.message ~= "" then msg = msg .. (msg ~= "" and " " or "") .. v.message end
      if v.percentage then msg = msg .. " " .. v.percentage .. "%" end
      progress[id] = (c and c.name or "lsp") .. ": " .. msg
    end
    require("plato.view").schedule()
  end,
})
api.nvim_create_autocmd({ "LspAttach", "LspDetach" }, {
  callback = function() require("plato.view").schedule() end,
})

-- ── the branch ─────────────────────────────────────────────────────────
-- read from .git/HEAD rather than asked of git: no process per frame. A
-- worktree's .git is a file naming the real directory. Kept per root, and
-- read again only when HEAD's mtime moves.
local heads = {}
-- a file's repository, found once: vim.fs.root walks up the directories,
-- and this is asked on every frame. Keyed by the path, so a renamed or
-- moved buffer asks again.
local roots = {}
function M.repoOf(name)
  if name == "" then return nil end
  local r = roots[name]
  if r == nil then
    r = vim.fs.root(name, ".git") or false
    roots[name] = r
  end
  return r or nil
end
-- looked for again when the buffer is entered: a `git init` since is seen
api.nvim_create_autocmd("BufEnter", {
  callback = function(ev) roots[api.nvim_buf_get_name(ev.buf)] = nil end,
})
local function branchOf(buf)
  local root = M.repoOf(vim.api.nvim_buf_get_name(buf))
  if not root then return "" end
  local dotgit = root .. "/.git"
  local st = vim.uv.fs_stat(dotgit)
  if not st then return "" end
  if st.type == "file" then
    local f = io.open(dotgit)
    local line = f and f:read("*l") or ""
    if f then f:close() end
    local gd = line:match("^gitdir:%s*(.+)$")
    if not gd then return "" end
    dotgit = gd:sub(1, 1) == "/" and gd or (root .. "/" .. gd)
  end
  local head = dotgit .. "/HEAD"
  local hs = vim.uv.fs_stat(head)
  if not hs then return "" end
  local c = heads[head]
  if c and c.mtime == hs.mtime.sec and c.nsec == hs.mtime.nsec then return c.name end
  local f = io.open(head)
  local ref = f and f:read("*l") or ""
  if f then f:close() end
  local name = ref:match("^ref: refs/heads/(.+)$") or ref:sub(1, 7)
  heads[head] = { mtime = hs.mtime.sec, nsec = hs.mtime.nsec, name = name }
  return name
end

-- ── the table ──────────────────────────────────────────────────────────
local sent = nil
function M.forget() sent = nil end

function M.compute(ed, buf, mode)
  local s = {}
  s.rec = vim.fn.reg_recording()
  local okp, sc = pcall(api.nvim_eval_statusline, "%S", { winid = ed })
  s.pending = okp and sc.str or ""
  s.op = mode:sub(1, 2) == "no"
  -- select mode too: insert mode's shift selection (cua.lua)
  if mode:match("^[vVsS\22\19]$") then
    s.sel = api.nvim_win_call(ed, function()
      local wc = vim.fn.wordcount()
      return {
        lines = math.abs(vim.fn.line("v") - vim.fn.line(".")) + 1,
        chars = wc.visual_chars or 0,
        words = wc.visual_words or 0,
      }
    end)
  end
  local n = vim.diagnostic.count(buf)
  local sev = vim.diagnostic.severity
  s.diag = { e = n[sev.ERROR] or 0, w = n[sev.WARN] or 0, i = n[sev.INFO] or 0, h = n[sev.HINT] or 0 }
  local names, busy = {}, nil
  for _, c in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
    names[#names + 1] = c.name
    if progress[c.id] then busy = progress[c.id] end
  end
  s.lsp = { names = names, busy = busy }
  s.branch = vim.bo[buf].buftype == "" and branchOf(buf) or ""
  local sum = vim.b[buf].minidiff_summary
  if type(sum) == "table" and sum.source_name then
    s.diff = { a = sum.add or 0, c = sum.change or 0, d = sum.delete or 0 }
  end
  s.indent = { tabs = not vim.bo[buf].expandtab, width = vim.fn.shiftwidth() }
  -- a file that is root's, which plato saves as root (root.lua)
  s.root = vim.b[buf].plato_root == true
  -- a file too big for the extras (large.lua)
  s.large = vim.b[buf].plato_large == true
  -- what the cursor is inside: class › function (symbols.lua)
  local okc, crumbs = pcall(require("plato.symbols").crumbs, buf, api.nvim_win_get_cursor(ed)[1])
  s.crumbs = okc and crumbs or {}
  s.eol = vim.bo[buf].fileformat
  s.enc = vim.bo[buf].fileencoding ~= "" and vim.bo[buf].fileencoding or vim.o.encoding
  local sig = vim.json.encode(s)
  if sig == sent then return nil end
  sent = sig
  return s
end

return M
