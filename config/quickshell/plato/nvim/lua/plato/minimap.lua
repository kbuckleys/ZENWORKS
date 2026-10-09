-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/
--
-- THE MINIMAP's text: the editor window's file as runs of colour, one row of
-- runs per line, for plato to draw a pixel or two tall down the right edge
-- (editor/Minimap.qml).
--
-- NOT THE WHOLE FILE. The map holds as many lines as it has room for
-- (`rows`, which plato sends as the setting's height changes) and, when the
-- file is longer, slides through it in proportion to the view, as VS Code's
-- does — so the work is the same few hundred lines in a file of any length.
--
-- NOT EVERY FRAME. A frame only notices that what the map would show has
-- changed (another buffer, an edit, the map sliding) and asks for it a
-- moment later; the lines are coloured and sent as their own event, so
-- typing never waits on the map.
--
--   { event = "minimap", first, total, lines = { { {col, len, fg}, ... }, ... } }
--   first is 1-based; col counts cells, tabs expanded; fg is "#rrggbb" or nil

local api = vim.api
local hl = require("plato.hl")
local M = { rows = 300 }

local send = function() end
local timer = vim.uv.new_timer()
local key, wanted = "", nil

-- one line as runs of one colour, blanks left out, at most `cap` cells wide
local function runs(s, groupAt, ts, cap)
  local out, col, i = {}, 0, 1
  local cur, start, curFg = nil, 0, nil
  local function close(at)
    if cur then out[#out + 1] = { start, at - start, curFg } end
    cur = nil
  end
  while i <= #s and col < cap do
    local b = s:byte(i)
    local len = b < 0x80 and 1 or b < 0xE0 and 2 or b < 0xF0 and 3 or 4
    if b == 9 or b == 32 then
      close(col)
      col = b == 9 and (col - col % ts + ts) or col + 1
    else
      local g = groupAt[i - 1]
      local a = g and hl.attrs(g)
      local fg = a and a.fg or nil
      if not cur or fg ~= curFg then close(col); cur, start, curFg = true, col, fg end
      col = col + 1
    end
    i = i + len
  end
  close(math.min(col, cap))
  return out
end

local function build(win, buf, first, last)
  local lines = api.nvim_buf_get_lines(buf, first - 1, last, false)
  local paints = hl.treesitter(buf, first - 1, last - 1)
  local ts = vim.bo[buf].tabstop
  local out = {}
  for idx, s in ipairs(lines) do
    local l = first - 2 + idx
    out[idx] = runs(s, hl.byteGroups(buf, l, s, paints, 400), ts, 120)
  end
  return out
end

-- Where the map starts: the view's place in the file, scaled to the map's.
local function placement(win, buf)
  local total = api.nvim_buf_line_count(buf)
  local rows = M.rows
  if total <= rows then return 1, total, total end
  local info = vim.fn.getwininfo(win)[1]
  local h = info.botline - info.topline + 1
  local f = (info.topline - 1) / math.max(1, total - h)
  local first = math.floor(math.max(0, math.min(1, f)) * (total - rows)) + 1
  return first, math.min(total, first + rows - 1), total
end

-- called by every frame, with the editor window: send when it would change
function M.poke(win, buf)
  if vim.g.plato_minimap == false or vim.b[buf].plato_large then return end
  local first, last, total = placement(win, buf)
  local k = table.concat({ buf, api.nvim_buf_get_changedtick(buf), first, last, M.rows }, ":")
  if k == key then return end
  key = k
  wanted = { win = win, buf = buf }
  timer:stop()
  timer:start(90, 0, vim.schedule_wrap(function()
    local w = wanted
    if not w or not api.nvim_win_is_valid(w.win) or not api.nvim_buf_is_valid(w.buf) then return end
    local f, l, t = placement(w.win, w.buf)
    local ok, lines = pcall(build, w.win, w.buf, f, l)
    if ok then send({ event = "minimap", first = f, total = t, lines = lines }) end
  end))
end

-- a new client, or the map resized: what it has must be sent again
function M.reset() key = "" end
function M.setRows(n)
  n = math.max(20, math.min(2000, math.floor(n or 300)))
  if n ~= M.rows then M.rows = n; key = "" end
end

function M.setup(sendFn) send = sendFn end

return M
