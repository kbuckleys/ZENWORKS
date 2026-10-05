-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/
--
-- The small things more than one part of the engine needs.
--
--   markers, rootOf(file)     a file's project: the nearest .git, or this
--                             shell's .qmlls.ini / shell.qml — or its own
--                             directory, for a file in no project
--   readJson(path)            a JSON file as a table ({} when missing or bad)
--   writeJson(path, t)        written whole or not at all (see below)
--   ago(t, short)             "3 days ago" — or "3 min ago" with short, and
--                             a date once it is older than a day

local M = {}

M.markers = { ".git", ".qmlls.ini", "shell.qml" }

function M.rootOf(file)
  return vim.fs.root(file, M.markers) or vim.fs.dirname(file)
end

function M.readJson(path)
  local f = io.open(path, "r")
  if not f then return {} end
  local ok, j = pcall(vim.json.decode, f:read("*a"))
  f:close()
  return ok and type(j) == "table" and j or {}
end

-- WHOLE OR NOT AT ALL. Every plato window's engine writes these files, and
-- one cut off halfway (a crash, a full disk) read back as nothing — every
-- project's pins or tabs gone. Written beside the real file and renamed over
-- it, which is atomic on one filesystem: a reader sees the old file or the
-- new one, never part of either.
function M.writeJson(path, t)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local tmp = path .. ".tmp" .. vim.uv.os_getpid()
  local f = io.open(tmp, "w")
  if not f then return false end
  f:write(vim.json.encode(t))
  f:close()
  local ok = vim.uv.fs_rename(tmp, path)
  if not ok then os.remove(tmp) end
  return ok and true or false
end

function M.ago(t, short)
  local d = os.time() - t
  if short then
    if d < 60 then return d .. " s ago" end
    if d < 3600 then return math.floor(d / 60) .. " min ago" end
    if d < 86400 then return math.floor(d / 3600) .. " h ago" end
    return os.date("%d %b %H:%M", t)
  end
  if d < 60 then return "just now" end
  local function n(v, unit) v = math.floor(v); return v .. " " .. unit .. (v == 1 and "" or "s") .. " ago" end
  if d < 3600 then return n(d / 60, "minute") end
  if d < 86400 then return n(d / 3600, "hour") end
  if d < 86400 * 30 then return n(d / 86400, "day") end
  if d < 86400 * 365 then return n(d / (86400 * 30), "month") end
  return n(d / (86400 * 365), "year")
end

return M
