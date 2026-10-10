-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/
--
-- Plato's plugin updates, run in an nvim of their own.
--
--   NVIM_APPNAME=quickshell/plato/nvim nvim --headless -i NONE --clean \
--     -c "luafile pack.lua"
--     PLATO_PACK=check                  print what vim.pack would update
--     PLATO_PACK=apply PLATO_PACK_NAMES=a,b   update those (all, if empty)
--     PLATO_PACK=install PLATO_PACK_NAMES=a   clone what plugins.json lists
--                                       and is not on disk yet
--     PLATO_PACK=remove PLATO_PACK_NAMES=a    delete those from disk and
--                                       from the lockfile
--
-- NOT IN THE EDITOR'S NVIM. vim.pack.update() waits on the network while it
-- fetches, and nvim waits with it; asked in the engine behind a window, the
-- editor would stop answering keys for as long as GitHub took. A throwaway
-- nvim with the same NVIM_APPNAME sees the same plugins and the same lockfile
-- (plato/nvim/nvim-pack-lock.json, which an update rewrites) and costs the
-- editor nothing.
--
-- CHECKING IS vim.pack's OWN. It fetches, works out each plugin's revisions
-- and pending commits, and writes them into its confirmation buffer; this
-- prints that buffer and quits without confirming, and plato's panel reads
-- it (editor/pack.js). Applying uses the fetch that checking just did.

local function out(s) io.stdout:write(s .. "\n") end
-- an error, without the Lua file and line it was raised at
local function why(err) return (tostring(err):gsub("^.-:%d+: ", "")) end

-- REGISTERED, NOT LOADED. vim.pack only knows where a plugin should go —
-- its source's newest commit rather than the one the lockfile pins — for a
-- plugin added in this session; without this every plugin reads as
-- "(not active)" and up to date, whatever is waiting upstream. load = false:
-- nothing is sourced, this nvim only asks.
local here = vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))
vim.opt.runtimepath:prepend(here)
local plugins = require("plato.plugins")
local added, addErr = pcall(vim.pack.add, plugins.specs(true), { load = false, confirm = false })
local names = vim.split(vim.env.PLATO_PACK_NAMES or "", ",", { trimempty = true })

-- INSTALLING IS REGISTERING. The panel writes the new plugin into
-- plugins.json first, so the vim.pack.add above has already cloned it (and
-- pinned it in the lockfile); all that is left is to say whether it worked.
if vim.env.PLATO_PACK == "install" then
  local have = {}
  for _, p in ipairs(vim.pack.get()) do have[p.spec.name] = p.path end
  local missing = {}
  for _, n in ipairs(names) do
    if not (have[n] and vim.uv.fs_stat(have[n])) then missing[#missing + 1] = n end
  end
  if #missing == 0 and added then out("OK")
  else out("ERROR " .. (added and ("could not install " .. table.concat(missing, ", "))
                               or why(addErr))) end
  vim.cmd("qall!")
  return
end

-- REMOVING: the panel has already taken the plugin out of plugins.json, so it
-- was not registered above — vim.pack deletes only what is not in use.
if vim.env.PLATO_PACK == "remove" then
  local ok, err = pcall(vim.pack.del, names)
  out(ok and "OK" or ("ERROR " .. why(err)))
  vim.cmd("qall!")
  return
end

-- AFTER STARTUP, which is why this is run with -c and not as -u: asked from
-- a VimEnter during startup, vim.pack.update() read every plugin as up to
-- date whatever was waiting upstream. The same call from -c found them.
if vim.env.PLATO_PACK == "apply" then
  local list = #names > 0 and names or nil
  local ok, err = pcall(vim.pack.update, list, { force = true, offline = true })
  out(ok and "OK" or ("ERROR " .. tostring(err)))
  vim.cmd("qall!")
  return
end

local ok, err = pcall(vim.pack.update, nil, {})
if not ok then
  out("ERROR " .. tostring(err))
  vim.cmd("qall!")
  return
end
-- nothing to update opens no buffer at all: the empty answer is the answer
for _, b in ipairs(vim.api.nvim_list_bufs()) do
  if vim.api.nvim_buf_get_name(b):find("^nvim%-pack://confirm") then
    out(table.concat(vim.api.nvim_buf_get_lines(b, 0, -1, false), "\n"))
  end
end
vim.cmd("qall!")
