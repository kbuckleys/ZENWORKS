-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/
--
-- PATHS, COMPLETED AS THEY ARE TYPED. A source for 'autocomplete' (the "F"
-- in 'complete', see plugins.lua): "~/to" offers ~/todo and ~/tools/, "./"
-- the files beside this one, "/etc/" what is in /etc. Directories end in a
-- slash, so taking one and typing on lists what is inside it.
--
-- WHAT IT OFFERS IS A FILE, AND PLATO SHOWS IT. Each offer's absolute path
-- is kept (M.offered, by the name shown in the menu); the bridge hands it to
-- plato with the menu's items, and the completion menu previews the one
-- that is selected — the text highlighted, a picture drawn, a directory
-- listed (editor/PathCard.qml).
--
-- A path is a run of path characters before the cursor holding a slash.
-- Not a URL's (https://…) or a comment's (//), and a relative one is the
-- current file's directory's, as gf reads it.

local M = {}
local uv = vim.uv

-- name in the menu → absolute path, for the last offers made
M.offered = {}

local MAX = 200

local function typed()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2]
  local before = line:sub(1, col)
  local s = before:match("[%w%._%-~/%+@,=]*$") or ""
  -- "a=b/c", "x,y/z": only what follows the last = or , is the path
  s = s:match("[^=,]*$")
  if not s:find("/", 1, true) then return nil end
  if s:sub(1, 2) == "//" then return nil end
  local start = #before - #s
  if start > 0 and before:sub(start, start) == ":" then return nil end
  -- "~" only at the start, and only as ~/
  if s:find("~", 2, true) or (s:sub(1, 1) == "~" and s:sub(2, 2) ~= "/") then return nil end
  return start, s
end

-- the directory a typed path's last part is looked for in
local function dirOf(s)
  local cut = s:match("^.*()/")
  local dir = s:sub(1, cut)
  local abs
  if dir:sub(1, 1) == "~" then
    abs = vim.env.HOME .. dir:sub(2)
  elseif dir:sub(1, 1) == "/" then
    abs = dir
  else
    local name = vim.api.nvim_buf_get_name(0)
    local base = name ~= "" and vim.fs.dirname(name) or uv.cwd()
    abs = base .. "/" .. dir
  end
  return dir, vim.fs.normalize(abs), s:sub(cut + 1)
end

function M.complete(findstart, base)
  if findstart == 1 then
    local start = typed()
    return start or -3
  end
  M.offered = {}
  local start, s = typed()
  if not start then return { words = {} } end
  s = base ~= "" and base or s
  local dir, abs, part = dirOf(s)
  local lower = part:lower()
  local hidden = part:sub(1, 1) == "."
  local found = {}
  local h = uv.fs_scandir(abs)
  if not h then return { words = {}, refresh = "always" } end
  while #found < MAX do
    local name, kind = uv.fs_scandir_next(h)
    if not name then break end
    if (hidden or name:sub(1, 1) ~= ".") and name:lower():sub(1, #lower) == lower then
      local full = (abs == "/" and "" or abs) .. "/" .. name
      if kind == "link" then
        local st = uv.fs_stat(full)
        kind = st and st.type or "file"
      end
      found[#found + 1] = { name = name, dir = kind == "directory", full = full }
    end
  end
  table.sort(found, function(a, b)
    if a.dir ~= b.dir then return a.dir end
    return a.name:lower() < b.name:lower()
  end)
  local words = {}
  for i, f in ipairs(found) do
    -- the menu shows the name alone (the abbr), and that is what the
    -- bridge is handed back
    local abbr = f.name .. (f.dir and "/" or "")
    M.offered[abbr] = f.full
    words[i] = { word = dir .. abbr, abbr = abbr,
                 kind = f.dir and "dir" or "file", icase = 1, dup = 0 }
  end
  return { words = words, refresh = "always" }
end

-- for 'complete': "F" takes a function's name, and this is what it is called
_G.PlatoPathComplete = M.complete

return M
