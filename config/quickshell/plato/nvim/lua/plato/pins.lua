-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/
--
-- PINNED FILES, PER PROJECT: the few you keep going back to, each on a key.
-- What harpoon was, with nothing to draw — the tabs wear the number.
--
--   Space a      pin the current file, or unpin it
--   Alt 1 … 9    the pinned file with that number, opened if it is not
--   Space A      the pinned files, in the picker (reordered by unpinning)
--
-- Kept in stdpath("state")/pins.json as { root: [path, …] }, shared by
-- every plato window, written as they change. The project is the file's own
-- (the nearest .git, or this shell's .qmlls.ini / shell.qml), as sessions.lua
-- and the picker have it.

local api = vim.api
local M = {}

local util = require("plato.util")
local path = vim.fn.stdpath("state") .. "/pins.json"
local MAX = 9

local function read() return util.readJson(path) end
local function write(all) util.writeJson(path, all) end

-- the project of the last file this engine had pins looked up for, so that
-- Alt N from a buffer with no file goes to the project you were just in
local lastRoot = nil

-- the current file's project, and its pins
local function here()
  local name = api.nvim_buf_get_name(0)
  if name == "" or vim.bo.buftype ~= "" then return nil, nil, {} end
  local root = util.rootOf(name)
  lastRoot = root
  return name, root, read()[root] or {}
end

-- every pinned path → its number, for the tabs (view.lua's buffers()).
-- Asked on every frame, so read again only when the file has changed (by
-- this engine or another window's).
local cache, cachedAt = {}, nil
function M.numbers()
  local st = vim.uv.fs_stat(path)
  local at = st and (st.mtime.sec .. "." .. st.mtime.nsec .. "." .. st.size) or ""
  if at == cachedAt then return cache end
  cachedAt = at
  cache = {}
  for _, list in pairs(read()) do
    for i, p in ipairs(list) do cache[p] = i end
  end
  return cache
end

function M.toggle()
  local name, root, list = here()
  if not name then
    vim.notify("Only a file can be pinned", vim.log.levels.WARN)
    return
  end
  local all = read()
  local at
  for i, p in ipairs(list) do if p == name then at = i end end
  if at then
    table.remove(list, at)
    vim.notify("Unpinned " .. vim.fs.basename(name))
  elseif #list >= MAX then
    vim.notify("Already " .. MAX .. " pinned in this project: unpin one first", vim.log.levels.WARN)
    return
  else
    list[#list + 1] = name
    vim.notify(("Pinned %s on Alt %d"):format(vim.fs.basename(name), #list))
  end
  all[root] = #list > 0 and list or nil
  write(all)
  require("plato.view").schedule(true)
end

function M.go(n)
  local _, _, list = here()
  -- a buffer with no file: the pins of the project you were last in —
  -- or, with none yet, the first project (by name) with that many
  if #list == 0 then
    local all = read()
    list = lastRoot and all[lastRoot] or {}
    if not list[n] then
      local roots = vim.tbl_keys(all)
      table.sort(roots)
      for _, r in ipairs(roots) do
        if all[r][n] then list = all[r]; break end
      end
    end
  end
  local p = list[n]
  if not p then
    vim.notify("Nothing pinned on Alt " .. n, vim.log.levels.WARN)
    return
  end
  vim.cmd.edit(vim.fn.fnameescape(p))
end

-- the project's pins, for the picker: { n, path }
-- every pinned file, in every project: for the start card
function M.all()
  local out = {}
  for _, list in pairs(read()) do
    for _, p in ipairs(list) do
      if vim.uv.fs_stat(p) then out[#out + 1] = p end
    end
  end
  table.sort(out)
  return out
end

function M.list()
  local _, _, list = here()
  local out = {}
  for i, p in ipairs(list) do out[#out + 1] = { n = i, path = p } end
  return out
end

function M.unpin(p)
  local all = read()
  for r, list in pairs(all) do
    for i, q in ipairs(list) do
      if q == p then
        table.remove(list, i)
        all[r] = #list > 0 and list or nil
        break
      end
    end
  end
  write(all)
  require("plato.view").schedule(true)
end

function M.setup()
  for i = 1, MAX do
    vim.keymap.set({ "n", "i", "x" }, "<A-" .. i .. ">", function() M.go(i) end,
      { desc = "Pinned file " .. i })
  end
end

return M
