-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/
--
-- Git, in the editor: which lines changed since the last commit, and who
-- last touched the line the cursor is on.
--
--   marks(buf)    line → "a" added, "c" changed, "d" lines deleted above it.
--                 mini.diff's hunks (mini.nvim is one of plato's plugins),
--                 kept up to date by mini.diff as you type; plato draws them
--                 as a bar down the gutter's edge and on the scrollbar.
--   blame         the cursor's line, at the end of the line, a moment after
--                 the cursor stops: "author, 3 days ago · summary". Read with
--                 `git blame --porcelain` for that one line, off the main
--                 loop, and dropped as soon as the line changes or the cursor
--                 moves on. A setting (vim.g.plato_blame).
--   hunk(action)  the change the cursor is in, staged ("apply": into git's
--                 index, as `git add -p` would) or undone ("reset": the
--                 lines back as last committed, an ordinary undo away).
--                 mini.diff's own do_hunks; plato's right-click menu asks.
--                 With a selection: only the selected lines of it.
--
-- mini.diff draws nothing itself here: its view is "number", which colours
-- nvim's number column — a column plato draws on its own — so its signs
-- never compete with diagnostics' for the one sign cell.

local api = vim.api
local M = {}

local diff = nil
function M.setup()
  local ok, md = pcall(require, "mini.diff")
  if not ok then return end
  pcall(md.setup, { view = { style = "number" } })
  diff = md
  -- a new state of the hunks is a new frame
  api.nvim_create_autocmd("User", {
    pattern = "MiniDiffUpdated",
    callback = function() require("plato.view").schedule() end,
  })
end

function M.marks(buf)
  if not diff then return nil end
  local ok, data = pcall(diff.get_buf_data, buf)
  if not ok or not data or not data.hunks then return nil end
  local out = {}
  for _, h in ipairs(data.hunks) do
    if h.type == "delete" then
      out[math.max(1, h.buf_start)] = out[math.max(1, h.buf_start)] or "d"
    else
      local mark = h.type == "add" and "a" or "c"
      for l = h.buf_start, h.buf_start + h.buf_count - 1 do out[l] = mark end
    end
  end
  return out
end

-- the scrollbar's share: every changed line, as { line, kind }
function M.list(buf)
  local m = M.marks(buf)
  if not m then return {} end
  local out = {}
  for l, k in pairs(m) do out[#out + 1] = { l, k } end
  return out
end

-- ── one change: staged or undone ───────────────────────────────────────
-- The whole change the cursor is in, not just its line: do_hunks takes the
-- part of a hunk inside the region it is given, and mini.diff splits one
-- edited block into a hunk per line it can pair up — so the hunks that
-- touch are joined first, the block you see as one bar in the gutter.
local function hunkAt(buf, line)
  local ok, data = pcall(diff.get_buf_data, buf)
  if not ok or not data or not data.hunks then return nil end
  local spans = {}
  for _, h in ipairs(data.hunks) do
    local a = math.max(1, h.buf_start)
    spans[#spans + 1] = { a, h.type == "delete" and a or h.buf_start + h.buf_count - 1 }
  end
  table.sort(spans, function(x, y) return x[1] < y[1] end)
  local cur = nil
  for _, sp in ipairs(spans) do
    if cur and sp[1] <= cur[2] + 1 then
      cur[2] = math.max(cur[2], sp[2])
    else
      if cur and line >= cur[1] and line <= cur[2] then return cur[1], cur[2] end
      cur = { sp[1], sp[2] }
    end
  end
  if cur and line >= cur[1] and line <= cur[2] then return cur[1], cur[2] end
  return nil
end

function M.hunk(action, from, to)
  local buf = api.nvim_get_current_buf()
  if not diff then return end
  local a, b = from, to
  if not a then
    a, b = hunkAt(buf, api.nvim_win_get_cursor(0)[1])
    if not a then
      vim.notify("No change on this line", vim.log.levels.WARN)
      return
    end
  end
  local ok, err = pcall(diff.do_hunks, buf, action, { line_start = a, line_end = b })
  if not ok then vim.notify(tostring(err), vim.log.levels.ERROR) end
end

-- the selection's lines, read before the menu's Esc ends it
function M.hunkSelected(action)
  local a, b = vim.fn.line("v"), vim.fn.line(".")
  if a > b then a, b = b, a end
  api.nvim_feedkeys(api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
  M.hunk(action, a, b)
end

-- ── blame ──────────────────────────────────────────────────────────────
local ns = api.nvim_create_namespace("plato.blame")
local timer = vim.uv.new_timer()
local asked = 0
-- the line whose blame is showing (or being asked for): moving along it
-- changes nothing, and is not a new `git blame`
local at = nil   -- { buf, line, tick }

local function clear(buf)
  at = nil
  if api.nvim_buf_is_valid(buf) then api.nvim_buf_clear_namespace(buf, ns, 0, -1) end
end

local function blameNow()
  local buf = api.nvim_get_current_buf()
  local name = api.nvim_buf_get_name(buf)
  if vim.g.plato_blame == false or name == "" or vim.bo[buf].buftype ~= "" or vim.b[buf].plato_large
      or vim.bo[buf].modified or api.nvim_get_mode().mode ~= "n" then return end
  -- a file in no repository: nothing to ask git, and no process to start
  if not require("plato.status").repoOf(name) then return end
  local line = api.nvim_win_get_cursor(0)[1]
  at = { buf = buf, line = line, tick = api.nvim_buf_get_changedtick(buf) }
  asked = asked + 1
  local mine = asked
  vim.system({ "git", "-C", vim.fs.dirname(name), "blame", "--porcelain",
    "-L", line .. "," .. line, "--", name }, { text = true }, vim.schedule_wrap(function(r)
    if mine ~= asked or r.code ~= 0 or not api.nvim_buf_is_valid(buf) then return end
    if api.nvim_get_current_buf() ~= buf or api.nvim_win_get_cursor(0)[1] ~= line then return end
    local out = r.stdout or ""
    local hash = out:match("^(%x+)")
    local text
    if not hash or hash:match("^0+$") then
      text = "not committed yet"
    else
      local who = out:match("\nauthor ([^\n]*)") or "?"
      local when = tonumber(out:match("\nauthor%-time (%d+)") or "") or os.time()
      local what = out:match("\nsummary ([^\n]*)") or ""
      text = who .. ", " .. require("plato.util").ago(when) .. (what ~= "" and " · " .. what or "")
    end
    local keep = at
    clear(buf)
    at = keep
    pcall(api.nvim_buf_set_extmark, buf, ns, line - 1, 0, {
      virt_text = { { "    " .. text, "PlatoBlame" } }, virt_text_pos = "eol", priority = 1,
    })
    require("plato.view").schedule()
  end))
end

function M.blame()
  api.nvim_set_hl(0, "PlatoBlame", { link = "Comment", default = true })
  api.nvim_create_autocmd({ "CursorMoved", "TextChanged", "InsertEnter", "BufLeave" }, {
    callback = function(ev)
      -- still on the line already blamed (or being blamed), unchanged
      if ev.event == "CursorMoved" and at and at.buf == ev.buf
          and at.tick == api.nvim_buf_get_changedtick(ev.buf)
          and api.nvim_win_get_cursor(0)[1] == at.line then return end
      asked = asked + 1
      clear(ev.buf)
      timer:stop()
      timer:start(700, 0, vim.schedule_wrap(blameNow))
    end,
  })
end

return M
