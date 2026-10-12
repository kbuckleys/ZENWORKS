-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/
--
-- Side windows belong to their tab.
--
-- A plato tab is a FILE (a listed buffer with nothing special about it). A
-- window showing anything else — fugitive's status, a blame, a log, help —
-- is a SIDE WINDOW, and it belongs to the tab that was showing when it
-- opened. They used to be loose: fugitive's buffers came up as tabs of
-- their own (a nameless one for :Git), no tab was lit while the cursor was
-- in a blame, and a click on a tab swapped the file into whichever split
-- the cursor was in (user capture, 2026-10-11).
--
--   isTab(buf)    what the tab strip lists
--   fileWin()     the window the tabs are about: the current one when it
--                 shows a file, else the last one that did
--   toFile()      go there first (a tab click, an open, a drop)
--   toggle(kind, cmd)
--                 the leader's git verbs: close that kind of side window
--                 when one is up, open it (from the file's window) when not
--
-- LEAVING A TAB puts its side windows away: what each one was is kept
-- (the command that makes it again, or the buffer, while it lives), they
-- close, and coming back to the tab brings them back.

local api = vim.api
local M = {}

local function isFloat(w) return api.nvim_win_get_config(w).relative ~= "" end

function M.isTab(b)
  if not api.nvim_buf_is_valid(b) or not vim.bo[b].buflisted or vim.bo[b].buftype ~= "" then
    return false
  end
  -- fugitive://, oil://, …: a view of something, not a file
  return not api.nvim_buf_get_name(b):match("^%a[%w+.-]*://")
end

local lastFile = nil
function M.fileWin()
  local cur = api.nvim_get_current_win()
  if not isFloat(cur) and M.isTab(api.nvim_win_get_buf(cur)) then
    lastFile = cur
    return cur
  end
  if lastFile and api.nvim_win_is_valid(lastFile)
      and vim.tbl_contains(api.nvim_tabpage_list_wins(0), lastFile) then
    return lastFile
  end
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    if not isFloat(w) and M.isTab(api.nvim_win_get_buf(w)) then lastFile = w; return w end
  end
  return nil
end

function M.toFile()
  local w = M.fileWin()
  if w and w ~= api.nvim_get_current_win() then api.nvim_set_current_win(w) end
end

-- what kind of side window this is, and the command that makes it again
local function kindOf(b)
  local k = vim.b[b].plato_kind
  if k then return k, vim.b[b].plato_reopen end
  local ft = vim.bo[b].filetype
  if ft == "fugitive" then return "status", "Git" end
  if ft == "fugitiveblame" then return "blame", "Git blame" end
  return nil, nil
end

local function sides()
  local fw = M.fileWin()
  local out = {}
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    if w ~= fw and not isFloat(w) and not M.isTab(api.nvim_win_get_buf(w)) then
      out[#out + 1] = w
    end
  end
  return out
end

-- tab buffer → its side windows, put away: { cmd? , buf?, vertical, size }
local stash = {}

local function putAway(owner)
  local fw = M.fileWin()
  local kept = {}
  for _, w in ipairs(sides()) do
    local b = api.nvim_win_get_buf(w)
    local _, cmd = kindOf(b)
    local wide = api.nvim_win_get_width(w) < vim.o.columns
    local entry = {
      cmd = cmd,
      -- a buffer that outlives its window can simply be shown again
      buf = (not cmd and not vim.bo[b].bufhidden:match("^[wdu]")) and b or nil,
      vertical = wide,
      size = wide and api.nvim_win_get_width(w) or api.nvim_win_get_height(w),
    }
    if entry.cmd or entry.buf then kept[#kept + 1] = entry end
    pcall(api.nvim_win_close, w, true)
  end
  if owner then stash[owner] = #kept > 0 and kept or nil end
  if fw and api.nvim_win_is_valid(fw) then api.nvim_set_current_win(fw) end
end

local function bringBack(owner)
  local kept = stash[owner]
  stash[owner] = nil
  if not kept then return end
  local fw = M.fileWin()
  for _, e in ipairs(kept) do
    if fw and api.nvim_win_is_valid(fw) then api.nvim_set_current_win(fw) end
    if e.cmd then
      pcall(M.open, e.cmd)
    elseif e.buf and api.nvim_buf_is_valid(e.buf) then
      pcall(vim.cmd, (e.vertical and "vertical " or "") .. "sbuffer " .. e.buf)
      pcall(e.vertical and api.nvim_win_set_width or api.nvim_win_set_height, 0, e.size)
    end
  end
  if fw and api.nvim_win_is_valid(fw) then api.nvim_set_current_win(fw) end
end

-- run cmd from the file's window, and mark what it opened as `kind` (when
-- given), so it can be found again to toggle, and made again on coming back
function M.open(cmd, kind)
  M.toFile()
  local before = {}
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do before[w] = true end
  vim.cmd(cmd)
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    if not before[w] and not isFloat(w) then
      local b = api.nvim_win_get_buf(w)
      if kind and not M.isTab(b) then
        vim.b[b].plato_kind = kind
        vim.b[b].plato_reopen = cmd
      end
    end
  end
end

function M.toggle(kind, cmd)
  for _, w in ipairs(sides()) do
    if kindOf(api.nvim_win_get_buf(w)) == kind then
      local fw = M.fileWin()
      pcall(api.nvim_win_close, w, true)
      if fw and api.nvim_win_is_valid(fw) then api.nvim_set_current_win(fw) end
      require("plato.view").schedule(true)
      return
    end
  end
  local ok, err = pcall(M.open, cmd, kind)
  if not ok then vim.notify((tostring(err):gsub("^.-:%d+: ", "")), vim.log.levels.ERROR) end
  require("plato.view").schedule(true)
end

-- a tab is closing: its side windows go with it, for good
function M.drop(buf)
  stash[buf] = nil
  local fw = M.fileWin()
  if fw and api.nvim_win_get_buf(fw) == buf then putAway(nil) end
end

function M.setup()
  -- which file each file window was showing: a different one there is the
  -- tab changing
  local shown = {}
  local g = api.nvim_create_augroup("plato_confine", { clear = true })
  api.nvim_create_autocmd("BufWinEnter", {
    group = g,
    callback = function(ev)
      local w = api.nvim_get_current_win()
      if isFloat(w) or not M.isTab(ev.buf) then return end
      local was = shown[w]
      shown[w] = ev.buf
      if not was or was == ev.buf then return end
      -- the layout cannot change inside the autocommand's own turn
      vim.schedule(function()
        if not api.nvim_win_is_valid(w) or api.nvim_win_get_buf(w) ~= ev.buf then return end
        if api.nvim_get_current_win() ~= w then api.nvim_set_current_win(w) end
        putAway(api.nvim_buf_is_valid(was) and was or nil)
        bringBack(ev.buf)
        require("plato.view").schedule(true)
      end)
    end,
  })
  api.nvim_create_autocmd("WinClosed", {
    group = g,
    callback = function(ev) shown[tonumber(ev.match)] = nil end,
  })
  api.nvim_create_autocmd("BufWipeout", {
    group = g,
    callback = function(ev) stash[ev.buf] = nil end,
  })
end

return M
