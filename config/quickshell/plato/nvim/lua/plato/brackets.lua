-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/
--
-- Brackets: the pair the cursor is on, and how deep each one sits.
--
--   pair(...)      the bracket at the cursor and its partner, for plato to
--                  outline both (nvim's matchparen marks them with window
--                  matches, which a frame never reads — and it is off)
--   rainbow(...)   every bracket on a line with its depth, for view.lua to
--                  colour by level (the settings' "Rainbow brackets")
--
-- A LINE SCANNER, NOT A PARSER. Most of plato's languages have no compiled
-- treesitter parser here, so brackets are found by reading the line: quoted
-- strings are stepped over, and so is the rest of a line after its
-- 'commentstring' lead (//, --, #). A block comment or a string that spans
-- lines can throw a depth off; the depth never goes below zero, so a stray
-- closer heals at the next one.
--
-- DEPTHS ARE KEPT per buffer: the depth at the start of each line, worked
-- out as far down as anything has asked and forgotten from the first line
-- an edit touched (view.lua's on_lines calls invalidate).

local api = vim.api
local M = {}

local open = { ["("] = ")", ["["] = "]", ["{"] = "}" }
local close = { [")"] = "(", ["]"] = "[", ["}"] = "{" }

-- the line comment's lead for a buffer: 'commentstring' up to its %s
local function lead(buf)
  local cs = vim.bo[buf].commentstring or ""
  local l = cs:match("^%s*(.-)%s*%%s") or ""
  -- a block comment's opener (/* %s */) is not a line comment
  if l == "" or cs:find("%%s%s*%S") then return nil end
  return l
end

-- every bracket on `line` outside strings and the line comment:
-- { {byte (0-based), char}, ... }
function M.scan(line, cl, rust)
  local out = {}
  if not line:find("[%(%)%[%]{}]") then return out end
  local i, n = 1, #line
  while i <= n do
    local c = line:sub(i, i)
    if cl and c == cl:sub(1, 1) and line:sub(i, i + #cl - 1) == cl then break end
    if open[c] or close[c] then
      out[#out + 1] = { i - 1, c }
      i = i + 1
    elseif c == '"' or c == "`" or c == "'" then
      local skip = true
      if c == "'" then
        -- an apostrophe in a word (don't) is not a quote; nor, in rust, a
        -- lifetime ('a): only a character literal like 'x' or '\n' is
        local prev = i > 1 and line:sub(i - 1, i - 1) or ""
        if prev:match("[%w]") then skip = false
        elseif rust then skip = line:sub(i, i + 3):match("^'\\?.'") ~= nil end
      end
      if skip then
        local j = i + 1
        while j <= n do
          local d = line:sub(j, j)
          if d == "\\" then j = j + 2
          elseif d == c then break
          else j = j + 1 end
        end
        i = j + 1
      else
        i = i + 1
      end
    else
      i = i + 1
    end
  end
  return out
end

local function scanOf(buf)
  return lead(buf), vim.bo[buf].filetype == "rust"
end

-- ── depths ──────────────────────────────────────────────────────────────
local cache = {}   -- buf → { d = { [l0] = depth at the line's start }, upto }

function M.invalidate(buf, first)
  local c = cache[buf]
  if c and c.upto > first then c.upto = first end
end
function M.forget(buf) cache[buf] = nil end

local function depthAt(buf, l0)
  local c = cache[buf]
  if not c then c = { d = { [0] = 0 }, upto = 0 }; cache[buf] = c end
  if l0 <= c.upto then return c.d[l0] end
  local cl, rust = scanOf(buf)
  local lines = api.nvim_buf_get_lines(buf, c.upto, l0, false)
  local d = c.d[c.upto]
  for k, line in ipairs(lines) do
    for _, b in ipairs(M.scan(line, cl, rust)) do
      if open[b[2]] then d = d + 1 elseif d > 0 then d = d - 1 end
    end
    c.d[c.upto + k] = d
  end
  c.upto = l0
  return d
end

-- the brackets on line l0 (0-based) with their depth from 0: { {byte, level} }
function M.rainbow(buf, l0, line)
  local cl, rust = scanOf(buf)
  local d = depthAt(buf, l0)
  local out = {}
  for _, b in ipairs(M.scan(line, cl, rust)) do
    if open[b[2]] then
      out[#out + 1] = { b[1], d }
      d = d + 1
    else
      if d > 0 then d = d - 1 end
      out[#out + 1] = { b[1], d }
    end
  end
  return out
end

-- ── the pair at the cursor ──────────────────────────────────────────────
-- The bracket under the cursor — in insert mode the one just before it
-- first, as nvim's matchparen — and its partner, looked for only between
-- lines `top` and `bot` (0-based, the window's): { {l0, byte}, {l0, byte} }
-- or nil.
function M.pair(buf, l0, col, insert, top, bot)
  local cl, rust = scanOf(buf)
  local line = api.nvim_buf_get_lines(buf, l0, l0 + 1, false)[1] or ""
  local here = M.scan(line, cl, rust)
  local at
  local tries = insert and { col - 1, col } or { col }
  for _, want in ipairs(tries) do
    for k, b in ipairs(here) do
      if b[1] == want then at = k; break end
    end
    if at then break end
  end
  if not at then return nil end
  local ch = here[at][2]
  local fwd = open[ch] ~= nil
  local mine, other = ch, fwd and open[ch] or close[ch]
  local depth = 0
  local function walk(list, l, from, to, step)
    for k = from, to, step do
      local c = list[k][2]
      if c == mine then depth = depth + 1
      elseif c == other then
        if depth == 0 then return { l, list[k][1] } end
        depth = depth - 1
      end
    end
  end
  local found = fwd and walk(here, l0, at + 1, #here, 1) or (not fwd and walk(here, l0, at - 1, 1, -1))
  local l = l0
  while not found do
    l = l + (fwd and 1 or -1)
    if l < top or l > bot then return nil end
    local list = M.scan(api.nvim_buf_get_lines(buf, l, l + 1, false)[1] or "", cl, rust)
    found = fwd and walk(list, l, 1, #list, 1) or (not fwd and walk(list, l, #list, 1, -1))
  end
  return { { l0, here[at][1] }, found }
end

return M
