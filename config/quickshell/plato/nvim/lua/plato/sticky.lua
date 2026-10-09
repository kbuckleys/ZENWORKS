-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/
--
-- STICKY SCROLL: the lines that open what the top of the window is inside —
-- the function, the class, the QML object — pinned over the top of the
-- text while their bodies scroll under them.
--
-- FOUND BY INDENTATION, not by a parser. Walking up from the first line in
-- view, every line indented less than the last one found (and not just a
-- closing bracket) opens a block the view is inside. That answers the same
-- question treesitter would, in every language — including the ones plato
-- has no parser for, which on this machine is most of them (QML among them).
--
--   M.context(win, buf, top) → { { n, chunks = { {text, fg, bold}, ... } } }
--                              innermost last, at most M.max, coloured as the
--                              view colours (hl.lua), tabs expanded

local api = vim.api
local hl = require("plato.hl")
local M = { max = 3 }

local function indentOf(s)
  local ws = s:match("^%s*")
  local ts = vim.bo.tabstop
  local n = 0
  for c in ws:gmatch(".") do n = c == "\t" and (n - n % ts + ts) or n + 1 end
  return n
end

-- one line, as runs of one colour
local function chunks(buf, l, s)
  local group = hl.byteGroups(buf, l, s, hl.treesitter(buf, l, l))
  local out, cur, piece, col = {}, false, {}, 0
  local ts = vim.bo[buf].tabstop
  local function flush()
    if #piece == 0 then return end
    local a = cur and hl.attrs(cur) or nil
    out[#out + 1] = { table.concat(piece), a and a.fg or vim.NIL, a and a.b or false }
    piece = {}
  end
  local i = 1
  while i <= #s do
    local b = s:byte(i)
    local len = b < 0x80 and 1 or b < 0xE0 and 2 or b < 0xF0 and 3 or 4
    local g = group[i - 1] or false
    if g ~= cur then flush(); cur = g end
    if b == 9 then
      local w = ts - (col % ts)
      piece[#piece + 1] = string.rep(" ", w)
      col = col + w
    else
      piece[#piece + 1] = s:sub(i, i + len - 1)
      col = col + 1
    end
    i = i + len
  end
  flush()
  return out
end

-- What the answer depends on, and the answer: a frame goes out for every
-- key, and nearly every one leaves the top of the view and the text as
-- they were.
local lastKey, lastOut = nil, {}
-- new colours: the chunks carry them, so the answer is worked out again
function M.forget() lastKey = nil end

function M.context(win, buf, top)
  if vim.g.plato_sticky == false or vim.b[buf].plato_large then return {} end
  local key = table.concat({ buf, api.nvim_buf_get_changedtick(buf), top,
    vim.bo[buf].tabstop, M.max }, ":")
  if key == lastKey then return lastOut end
  local last = api.nvim_buf_line_count(buf)
  -- the first line in view that says anything decides how deep the view is
  local want = nil
  for _, s in ipairs(api.nvim_buf_get_lines(buf, top - 1, math.min(last, top + 5), false)) do
    if s:find("%S") then want = indentOf(s); break end
  end
  local out = {}
  if want and want > 0 then
    -- ONE READ, NOT ONE A LINE. Walking up line by line asked nvim for each
    -- one: deep in a long QML file, hundreds of calls on every key.
    local floor = math.max(1, top - 2000)
    local above = top > floor and api.nvim_buf_get_lines(buf, floor - 1, top - 1, false) or {}
    local found = {}
    for k = #above, 1, -1 do
      if want <= 0 then break end
      local s = above[k]
      if s:find("%S") then
        local ind = indentOf(s)
        local body = vim.trim(s)
        -- a closing bracket, or a comment, opens nothing
        if ind < want and not body:match("^[%)%]}]") and not body:match("^[/#%-%*]") then
          table.insert(found, 1, { n = floor + k - 1, s = s })
          want = ind
        end
      end
    end
    -- the innermost few, and never as many as would cover the view
    while #found > M.max do table.remove(found, 1) end
    for _, f in ipairs(found) do
      out[#out + 1] = { n = f.n, chunks = chunks(buf, f.n - 1, f.s) }
    end
  end
  lastKey, lastOut = key, out
  return out
end

return M
