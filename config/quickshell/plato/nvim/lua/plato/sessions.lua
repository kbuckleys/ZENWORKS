-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/
--
-- WHAT WAS OPEN, PER PROJECT. Every engine keeps, for each project it has
-- files open in, the list of them — in stdpath("state")/sessions.json,
-- shared by every plato window, written a moment after the list changes and
-- when the engine goes.
--
--   restore(root)   the project's files opened again as tabs (not shown:
--                   the one you are in stays in front). With no root, the
--                   current file's project. Space r, or the palette.
--   automatically   with the setting "Reopen a project's tabs"
--                   (vim.g.plato_reopen): the first file an engine opens
--                   brings the rest of its project back with it.
--
-- Where in each file you were is nvim's own business already (shada's '"
-- mark, restored on read by init.lua), so only the files are kept here.

local api = vim.api
local M = {}

local util = require("plato.util")
local path = vim.fn.stdpath("state") .. "/sessions.json"

local function read() return util.readJson(path) end
local function write(all) util.writeJson(path, all) end

-- every listed file, by project, in nvim's order
local function current()
  local by = {}
  for _, b in ipairs(api.nvim_list_bufs()) do
    if vim.bo[b].buflisted and vim.bo[b].buftype == "" then
      local name = api.nvim_buf_get_name(b)
      if name ~= "" and vim.uv.fs_stat(name) then
        local r = util.rootOf(name)
        by[r] = by[r] or {}
        table.insert(by[r], name)
      end
    end
  end
  return by
end

-- the projects this engine has had files open in: one whose last file was
-- closed here is dropped, rather than kept as it was before the closing —
-- tabs you closed one by one must not all come back the next time
local mine = {}
function M.save()
  local all = read()
  local now = current()
  for r in pairs(mine) do
    if not now[r] then all[r] = nil end
  end
  mine = {}
  for r, files in pairs(now) do
    all[r] = { files = files, at = os.time() }
    mine[r] = true
  end
  write(all)
end

function M.restore(root)
  local here = api.nvim_buf_get_name(0)
  root = root or (here ~= "" and util.rootOf(here)) or nil
  if not root then return 0 end
  local s = read()[root]
  if not s or not s.files then return 0 end
  local n = 0
  for _, f in ipairs(s.files) do
    if f ~= here and vim.uv.fs_stat(f) and vim.fn.buflisted(f) == 0 then
      vim.cmd.badd(vim.fn.fnameescape(f))
      n = n + 1
    end
  end
  if n > 0 then
    vim.notify(("Reopened %d file%s from %s"):format(n, n == 1 and "" or "s",
      vim.fn.fnamemodify(root, ":~")))
  end
  require("plato.view").schedule(true)
  return n
end

-- the projects there are tabs kept for, the latest first: for the start card
function M.projects()
  local out = {}
  for root, s in pairs(read()) do
    if type(s) == "table" and s.files and #s.files > 0 and vim.uv.fs_stat(root) then
      out[#out + 1] = { root = root, files = #s.files, at = s.at or 0 }
    end
  end
  table.sort(out, function(a, b) return a.at > b.at end)
  return out
end

local timer = vim.uv.new_timer()
function M.setup()
  local first = true
  api.nvim_create_autocmd({ "BufAdd", "BufDelete", "BufFilePost" }, {
    callback = function()
      timer:stop()
      timer:start(1500, 0, vim.schedule_wrap(M.save))
    end,
  })
  api.nvim_create_autocmd("VimLeavePre", { callback = M.save })
  api.nvim_create_autocmd("BufReadPost", {
    callback = function(ev)
      if not first or vim.bo[ev.buf].buftype ~= "" then return end
      first = false
      if vim.g.plato_reopen then vim.schedule(function() M.restore() end) end
    end,
  })
end

return M
