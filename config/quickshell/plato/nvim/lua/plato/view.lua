-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/
--
-- The view model: what plato should draw, worked out on nvim's side.
--
-- NOT A GRID. A Lua UI cannot have one (vim.ui_attach refuses ext_linegrid),
-- and plato does not want one: it draws lines, not cells. So nvim is asked
-- the questions a renderer needs answered — which buffer lines are on screen
-- and in what order (folds and wrapping make that a question), what each one
-- looks like once tabs are expanded, what colour every part of it is, where
-- the cursor is in screen terms — and the answers are sent as plain data.
--
-- nvim stays the authority on the viewport. Its window is sized to plato's
-- rows and columns, so scrolloff, <C-d>, zz, folding and wrapping all move
-- the view the way they always have, and this file only reports where it went.
--
-- A SCREEN ROW is { i, n, k, t, s, g, f }:
--   i  the row on screen          n  the buffer line (0 past the end)
--   k  which wrapped piece of the line this is (0 = its first row)
--   t  the text as drawn          s  its colours: { {col, len, style}, ... }
--   g  the sign in the gutter     f  a closed fold
--   ig the indent guides: the cells, from the text's left, a guide runs down
--   m  the bracket at the cursor and its partner: the cells to outline
--   sl the selection on this row: { from, to } cells (plato draws one
--      rounded shape over every row of it)
--   vt a diagnostic at the line's end: { from, to, kind, cut } cells, kind
--      "e" "w" "i" "h", cut when the window's edge took the rest of it
--   fc a closed fold's pill: { from, len } cells of its "⋯ N lines"
--   md rendered markdown's block (markdown.lua): { k = "h", n } a heading,
--      { k = "c", x, e } a code block from cell x ("t" top, "b" bottom),
--      { k = "hr" } a rule
-- Style numbers are defined in the frame's `styles` the first time they are
-- used — see hl.lua.
--
-- ROWS ARE DIFFED. The frame carries every row only when asked to (a new
-- client, a resize, a new buffer); otherwise just the rows that differ from
-- the last frame sent. Typing a character re-sends one line, not a screen.

local api = vim.api
local hl = require("plato.hl")
local M = {}

local pending = false
local emit = nil
-- window → { rows = screen row → { l, chars, c0, len }, r0, c0, h, w }:
-- rendered markdown's rows and where the window's text is on nvim's grid
M.clicks = {}

-- A cell of nvim's grid (0-based row and column) as the window, line and
-- byte it shows, where rendered markdown drew that row otherwise than it is
-- written — or nil, where nvim's own mapping is right. Plain Lua only: it is
-- asked from a fast callback.
function M.clickAt(row, col)
  for win, c in pairs(M.clicks) do
    if row >= c.r0 and row < c.r0 + c.h and col >= c.c0 and col < c.c0 + c.w then
      local l, b = M.clickIn(c.rows[row - c.r0], col - c.c0)
      if l then return win, l, b end
      return nil
    end
  end
  return nil
end

-- one row's cell → its line and byte (past the text: the last byte)
function M.clickIn(m, col)
  if not m then return nil end
  local cell = m.c0 + col
  local byte = m.len
  for _, ch in ipairs(m.chars) do
    if cell < ch[3] + math.max(1, ch[4]) then byte = ch[1]; break end
  end
  return m.l, math.max(0, math.min(byte, math.max(0, m.len - 1)))
end
local hlns = api.nvim_create_namespace("plato.view")

-- ── layout: bytes to cells ─────────────────────────────────────────────
-- One buffer line laid out in screen cells: tabs to the next stop, control
-- characters as ^X, wide characters two cells. Only cells [from, from+limit)
-- are produced. Returns the text of those cells and, per character that has
-- any cell in them, { b0, b1, cell, width } with bytes 0-based, end exclusive
-- and cell relative to `from` (negative for a character cut by the left edge).
-- ── ONE CHARACTER AS NVIM DRAWS IT ─────────────────────────────────────
-- A flag (two regional indicators), an emoji with a skin tone, a letter with
-- a combining accent: several code points, ONE character to nvim, in the
-- cells of the whole. Measured a code point at a time they came out wider
-- than the line nvim had laid out — a lone accent counts a cell, half a flag
-- two — and the text past them was cut off the row: "flags 🇪🇪" lost its
-- flag, "a\u030a" its å (2026-10-09). strcharpart's skipcc takes the
-- character with everything that composes with it, as nvim does.
local function clusterAt(s, i)
  local b = s:byte(i)
  local nb = s:byte(i + 1)
  if b < 0x80 and (not nb or nb < 0x80) then return s:sub(i, i) end
  local piece = vim.fn.strcharpart(s:sub(i, i + 63), 0, 1, 1)
  if piece == "" then
    local len = b < 0x80 and 1 or b < 0xE0 and 2 or b < 0xF0 and 3 or 4
    piece = s:sub(i, i + len - 1)
  end
  return piece
end
local function clusters(t)
  local out, i, n = {}, 1, #t
  while i <= n do
    local ch = clusterAt(t, i)
    out[#out + 1] = ch
    i = i + #ch
  end
  return out
end

local function layout(s, ts, from, limit, conceal)
  local out, chars = {}, {}
  local col, stop = 0, from + limit
  local i, n = 1, #s
  local ci = 1
  while i <= n and col < stop do
    -- concealed bytes: shown as something else, or not at all. The
    -- something else is a cell, as nvim's conceal has it, or several:
    -- rendered markdown pads a table's columns on its pipes
    if conceal then
      while conceal[ci] and conceal[ci][2] <= i - 1 do ci = ci + 1 end
      local c = conceal[ci]
      if c and c[1] <= i - 1 then
        if c[3] then
          local w = c[3]:find("[\128-\255]") and vim.fn.strdisplaywidth(c[3]) or #c[3]
          if col >= from then
            out[#out + 1] = c[3]
            chars[#chars + 1] = { i - 1, math.min(c[2], n), col - from, w }
          elseif col + w > from then
            out[#out + 1] = string.rep(" ", col + w - from)
            chars[#chars + 1] = { i - 1, math.min(c[2], n), col - from, w }
          end
          col = col + w
        end
        i = math.min(c[2], n) + 1
        ci = ci + 1
        goto continue
      end
    end
    do
      local b = s:byte(i)
      local len = b < 0x80 and 1 or b < 0xE0 and 2 or b < 0xF0 and 3 or 4
      local w, shown
      if b == 9 then
        w = ts - (col % ts)
        shown = string.rep(" ", w)
      elseif b < 0x20 or b == 0x7f then
        w = 2
        shown = "^" .. string.char(b == 0x7f and 63 or b + 64)
      elseif b < 0x80 and (s:byte(i + 1) or 0) < 0x80 then
        w = 1
        shown = string.char(b)
      else
        shown = clusterAt(s, i)
        len = #shown
        w = vim.fn.strdisplaywidth(shown)
      end
      if col + w > from then
        if col >= from then
          out[#out + 1] = shown
        else
          -- straddling the left edge: the part in view, as blanks
          out[#out + 1] = string.rep(" ", col + w - from)
        end
        chars[#chars + 1] = { i - 1, i - 1 + len, col - from, w }
      end
      col = col + w
      i = i + len
    end
    ::continue::
  end
  return table.concat(out), chars, col
end

-- ── cells, not characters ──────────────────────────────────────────────
-- Everything positional here counts screen CELLS, and a wide character is one
-- character in two of them. strchars/strcharpart count characters, so they are
-- only right for text without any: "日本 abc" is 6 characters and 8 cells,
-- and a search match on "abc" measured in characters lit one cell of three.
-- ASCII — nearly every line — takes the byte-length shortcut.
local function ascii(t) return not t:find("[\128-\255]") end

local function cellWidth(t)
  if ascii(t) then return #t end
  return vim.fn.strdisplaywidth(t)
end

-- cells [c0, c1) of already-laid-out text (no tabs left in it)
local function cellSlice(t, c0, c1)
  if ascii(t) then return t:sub(c0 + 1, c1) end
  local out, cell = {}, 0
  for _, ch in ipairs(clusters(t)) do
    local w = #ch == 1 and 1 or vim.fn.strdisplaywidth(ch)
    if cell >= c1 then break end
    if cell >= c0 then out[#out + 1] = ch end
    cell = cell + w
  end
  return table.concat(out)
end

-- first character at or after byte b0 (chars are in byte order)
local function seek(chars, b0)
  local lo, hi = 1, #chars + 1
  while lo < hi do
    local mid = math.floor((lo + hi) / 2)
    if chars[mid][1] < b0 then lo = mid + 1 else hi = mid end
  end
  return lo
end

-- paint `group` into `layer` over bytes [b0, b1) — b1 of -1 is the line's end
local function paint(layer, chars, ncells, b0, b1, group)
  if b1 ~= -1 and b1 <= b0 then return end
  for k = seek(chars, b0), #chars do
    local ch = chars[k]
    if b1 ~= -1 and ch[1] >= b1 then break end
    for c = math.max(0, ch[3]), math.min(ncells, ch[3] + ch[4]) - 1 do
      layer[c] = group
    end
  end
end

-- ── what sits on top: search and the selection ─────────────────────────
-- committed: only @/, never a search still being typed (the scrollbar's
-- marks, which are recounted when @/ changes, not on every typed key)
local function searchPattern(committed)
  local pat, cur
  local ct = vim.fn.getcmdtype()
  if not committed and (ct == "/" or ct == "?") and vim.o.incsearch then
    pat, cur = vim.fn.getcmdline(), "IncSearch"
  elseif vim.v.hlsearch == 1 then
    pat, cur = vim.fn.getreg("/"), "CurSearch"
  end
  if not pat or pat == "" then return nil end
  -- matchbufline honours 'ignorecase' but not 'smartcase'; searching does
  if vim.o.ignorecase and vim.o.smartcase and not pat:find("\\[cC]")
      and pat:gsub("\\.", ""):find("%u") then
    pat = "\\C" .. pat
  end
  return pat, cur
end

-- lnum(0-based) → { {b0, b1, group}, ... }
local function searchMatches(buf, top, bot, curLine, curCol)
  if vim.o.hlsearch == false and vim.fn.getcmdtype() == "" then return {} end
  local pat, curGroup = searchPattern()
  if not pat then return {} end
  local ok, found = pcall(vim.fn.matchbufline, buf, pat, top + 1, bot + 1)
  if not ok then return {} end
  local out = {}
  for _, m in ipairs(found) do
    local l = m.lnum - 1
    local b0, b1 = m.byteidx, m.byteidx + #m.text
    local isCur = l == curLine and curCol >= b0 and curCol < math.max(b1, b0 + 1)
    out[l] = out[l] or {}
    table.insert(out[l], { b0, b1, isCur and curGroup or "Search" })
  end
  return out
end

-- lnum(0-based) → { b0, b1 } with b1 = -1 past the end, and whether an empty
-- or line-wise row shows one selected cell past its text, as nvim draws it
local function selection(mode)
  -- select mode (insert mode's shift selection, cua.lua) is drawn as visual
  mode = ({ s = "v", S = "V", ["\19"] = "\22" })[mode] or mode
  if not (mode == "v" or mode == "V" or mode == "\22") then return {} end
  local ok, regions = pcall(vim.fn.getregionpos, vim.fn.getpos("v"), vim.fn.getpos("."),
    { type = mode, eol = true })
  if not ok then return {} end
  local out = {}
  for _, r in ipairs(regions) do
    local s, e = r[1], r[2]
    local line = api.nvim_buf_get_lines(0, s[2] - 1, s[2], false)[1] or ""
    local b1 = e[3] + (e[4] or 0)
    local pastEnd = e[3] > #line
    out[s[2] - 1] = { s[3] - 1, pastEnd and -1 or b1, pastEnd or #line == 0 }
  end
  return out
end

-- ── colour codes, in their own colour ──────────────────────────────────
-- "#9fcbfc", "#fff", "rgb(255, 0, 0)", Qt.rgba(1, 1, 1, 0.5): each is painted
-- with itself as its background and black or white text on it, whichever
-- reads — as a colour picker would show it. A colour with alpha is shown as
-- it would look over the editor's own near-black.
--
-- EIGHT DIGITS MEAN TWO THINGS. CSS writes #rrggbbaa; Qt writes #aarrggbb.
-- In a QML file it is Qt's, everywhere else the web's.
local madeColor = {}
function M.forgetColors() madeColor = {} end

local function colorGroup(r, g, b, a)
  a = a or 1
  r, g, b = math.floor(r * a + 0.5), math.floor(g * a + 0.5), math.floor(b * a + 0.5)
  local hexv = string.format("%02x%02x%02x", r, g, b)
  local name = "PlatoColor_" .. hexv
  if not madeColor[name] then
    -- relative luminance, roughly: light colours get black text
    local lum = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255
    api.nvim_set_hl(0, name, { bg = "#" .. hexv, fg = lum > 0.55 and "#000000" or "#ffffff" })
    madeColor[name] = true
  end
  return name
end

local function hexDigits(h) return tonumber(h, 16) end

-- every colour on a line: { {b0, b1, group}, ... } in bytes, end exclusive
local function colorCodes(line, qml)
  local out = {}
  if line:find("#", 1, true) then
    local init = 1
    while true do
      local s = line:find("#%x%x%x", init)
      if not s then break end
      -- the longest run of hex digits after the #, and it must end there
      local run = line:match("^%x+", s + 1)
      local after = line:sub(s + 1 + #run, s + 1 + #run)
      local okEnd = after == "" or not after:match("[%w_]")
      local r, g, b, a
      if okEnd and (#run == 6 or #run == 8) then
        local hx = run
        if #run == 8 then
          if qml then a, hx = hexDigits(run:sub(1, 2)) / 255, run:sub(3)
          else a, hx = hexDigits(run:sub(7, 8)) / 255, run:sub(1, 6) end
        end
        r, g, b = hexDigits(hx:sub(1, 2)), hexDigits(hx:sub(3, 4)), hexDigits(hx:sub(5, 6))
      elseif okEnd and (#run == 3 or #run == 4) then
        local function d(i) return hexDigits(run:sub(i, i)) * 17 end
        r, g, b = d(1), d(2), d(3)
        if #run == 4 then a = d(4) / 255 end
      end
      if r then out[#out + 1] = { s - 1, s + #run, colorGroup(r, g, b, a) } end
      init = s + 1 + #run
    end
  end
  if line:find("rgb", 1, true) then
    local init = 1
    while true do
      local s, e, fn, args = line:find("([%w%.]*rgba?)(%b())", init)
      if not s then break end
      local nums = {}
      for n in args:gmatch("[%d%.]+") do nums[#nums + 1] = tonumber(n) end
      -- only literal numbers count: Qt.rgba(Zenon.cyan.r, ...) is no colour
      local literal = not args:sub(2, -2):find("[^%d%.,%s%%]")
      if literal and (#nums == 3 or #nums == 4) and nums[1] and nums[2] and nums[3] then
        local unit = fn:find("Qt%.") ~= nil
          or (nums[1] <= 1 and nums[2] <= 1 and nums[3] <= 1 and args:find("%.") ~= nil)
        local k = unit and 255 or 1
        local function c(v) return math.max(0, math.min(255, v * k)) end
        local a = nums[4]
        if a and a > 1 then a = a / 100 end
        out[#out + 1] = { s - 1, e, colorGroup(c(nums[1]), c(nums[2]), c(nums[3]), a) }
      end
      init = e + 1
    end
  end
  return out
end

-- ── decorations: extmarks ───────────────────────────────────────────────
-- Highlights, signs and end-of-line virtual text, from any namespace — which
-- is how diagnostics arrive, and how any plugin that marks text will.
local function extmarks(buf, top, bot)
  local deco, signs, virt, conceal = {}, {}, {}, {}
  local marks = api.nvim_buf_get_extmarks(buf, -1, { top, 0 }, { bot, -1 },
    { details = true, overlap = true })
  for _, m in ipairs(marks) do
    local row, col, d = m[2], m[3], m[4]
    if d.hl_group and d.ns_id ~= hlns then
      local er = d.end_row or row
      local ec = d.end_col
      for l = math.max(row, top), math.min(er, bot) do
        deco[l] = deco[l] or {}
        table.insert(deco[l], {
          l == row and col or 0,
          (l == er and ec) and ec or -1,
          d.hl_group, d.priority or 4096,
        })
      end
    end
    if d.conceal and row >= top and row <= bot then
      local ec = (d.end_row or row) == row and d.end_col or -1
      conceal[row] = conceal[row] or {}
      table.insert(conceal[row], { col, ec, d.conceal })
    end
    if d.sign_text and row >= top and row <= bot then
      local cur = signs[row]
      local prio = d.priority or 10
      if not cur or prio > cur[3] then
        signs[row] = { vim.trim(d.sign_text), d.sign_hl_group, prio }
      end
    end
    if d.virt_text and (d.virt_text_pos == "eol" or d.virt_text_pos == nil)
        and row >= top and row <= bot then
      virt[row] = virt[row] or {}
      for _, chunk in ipairs(d.virt_text) do table.insert(virt[row], chunk) end
    end
  end
  for _, list in pairs(deco) do
    table.sort(list, function(a, b) return a[4] < b[4] end)
  end
  return deco, signs, virt, conceal
end

-- ── spans ───────────────────────────────────────────────────────────────
-- cells [c0, c1) of the three layers as { {col, len, style}, ... }, runs of
-- plain Normal left out (the client draws those in Normal's colour anyway)
local function spans(base, deco, over, c0, c1)
  local out = {}
  local runKey, runStart
  local rb, rd, ro
  local function close(at)
    local id = runKey and runKey ~= "\0\0" and hl.style(rb, rd, ro) or 0
    if id ~= 0 then
      -- different groups, same colour ("(", "a", ")"): one span, not three
      local prev = out[#out]
      if prev and prev[3] == id and prev[1] + prev[2] == runStart - c0 then
        prev[2] = prev[2] + at - runStart
      else
        out[#out + 1] = { runStart - c0, at - runStart, id }
      end
    end
  end
  for c = c0, c1 - 1 do
    local b, d, o = base[c], deco[c], over[c]
    local key = (b or "") .. "\0" .. (d or "") .. "\0" .. (o or "")
    if key ~= runKey then
      close(c)
      runKey, runStart, rb, rd, ro = key, c, b, d, o
    end
  end
  close(c1)
  return out
end

-- CELLS ARE NOT CHARACTERS. Spans are counted in screen cells, which is what
-- places a background or an underline; but the client builds its text by
-- character, and a wide character is one character in two cells. On a row
-- that has any, each span also carries where it starts and how long it is in
-- characters: { col, len, style, char, chars }. Everywhere else the two
-- counts agree and the extra pair is left off.
local function charSpans(piece, list)
  if not piece:find("[\194-\244]") then return list end
  local cellToChar, cell, idx = {}, 0, 0
  for _, ch in ipairs(clusters(piece)) do
    local w = #ch == 1 and 1 or vim.fn.strdisplaywidth(ch)
    for k = 0, w - 1 do cellToChar[cell + k] = idx end
    cell = cell + w
    -- the client counts code points: a cluster of several advances by all
    idx = idx + (#ch == 1 and 1 or vim.fn.strchars(ch))
  end
  cellToChar[cell] = idx
  for _, s in ipairs(list) do
    local a = cellToChar[s[1]] or idx
    local b = cellToChar[s[1] + s[2]] or idx
    s[4], s[5] = a, b - a
  end
  return list
end

-- Conceal ranges in byte order, overlaps resolved: of two that start
-- together the longer wins, and a later one is trimmed behind an earlier.
function M.mergeConceal(list)
  table.sort(list, function(x, y)
    if x[1] ~= y[1] then return x[1] < y[1] end
    return x[2] > y[2]
  end)
  local merged = { list[1] }
  for k = 2, #list do
    local p, c = merged[#merged], list[k]
    if c[1] >= p[2] then merged[#merged + 1] = c
    elseif c[2] > p[2] then merged[#merged + 1] = { p[2], c[2], c[3] } end
  end
  return merged
end

-- Rendered markdown's drawing for one row (markdown.lua's blk, q, tb), in
-- the row's cells: positions moved by the view's sideways scroll, and a
-- block's edges only on the row that has them — the first piece of a
-- wrapped line its top, the last its bottom.
local function mdRow(mdl, k, pieces, shift, raw)
  if not (mdl.blk or mdl.q or mdl.tb) then return nil end
  local function edges(e)
    if not e then return nil end
    local out = (k == 0 and e:find("t") and "t" or "") .. (k == pieces - 1 and e:find("b") and "b" or "")
    return out ~= "" and out or nil
  end
  -- the cursor's line, shown as written: drawn on the grid like any other
  local r = { raw = raw or nil }
  local b = mdl.blk
  if b then
    r.k, r.n = b.k, b.n
    if b.k == "c" then
      r.x, r.e = math.max(0, b.x - shift), edges(b.e)
      if k == 0 then r.lang = b.lang end
    end
  end
  if mdl.q then
    local bars = {}
    for _, c in ipairs(mdl.q.b) do if c - shift >= 0 then bars[#bars + 1] = c - shift end end
    r.q = { b = bars, k = mdl.q.k, e = edges(mdl.q.e) }
  end
  if mdl.tb then
    local t = mdl.tb
    local rules = {}
    for _, c in ipairs(t.c or {}) do rules[#rules + 1] = c - shift end
    r.tb = { x = t.x - shift, w = t.w, c = rules, h = t.h, d = t.d, z = t.z, e = edges(t.e),
      u = t.u }
  end
  return r
end

-- ── one window, as rows ─────────────────────────────────────────────────
-- Any window: the editor's, or a float — a hover, a signature, completion's
-- documentation. Run inside nvim_win_call, so every "current window" question
-- (w0, winsaveview, virtcol, foldclosed) is asked of this one.
--
-- CONCEAL is honoured where the window asks for it: markdown in a hover hides
-- its fences and backticks with treesitter's conceal and conceal_lines, and
-- without it the card shows raw ```lua lines. On the cursor's own line,
-- concealing stops unless 'concealcursor' names the mode, as nvim does.
local function build(win, isCurrent, mode, margin)
  margin = margin or 0
  local buf = api.nvim_win_get_buf(win)
  local height = api.nvim_win_get_height(win)
  -- the window's own gutter (number and sign columns) is nvim's to size and
  -- plato's to draw; the rows here are the text to the right of it
  local textoff = vim.fn.getwininfo(win)[1].textoff
  local width = api.nvim_win_get_width(win) - textoff
  local view = vim.fn.winsaveview()
  local wrap = vim.wo[win].wrap
  local cl = vim.wo[win].conceallevel
  local ts = vim.bo[buf].tabstop
  local last = api.nvim_buf_line_count(buf)
  local qml = vim.bo[buf].filetype == "qml"
  -- a file too big for the extras (large.lua): no colour codes, no guides,
  -- no spelling
  local large = vim.b[buf].plato_large == true
  local guides = not large and vim.g.plato_guides ~= false and vim.bo[buf].buftype == ""
    and api.nvim_win_get_config(win).relative == ""
  local sw = vim.fn.shiftwidth()
  if sw <= 0 then sw = ts end
  local spell = not large and vim.wo[win].spell
  local prose = spell and require("plato.spell").prose(buf)
  local plain = vim.bo[buf].buftype == "" and api.nvim_win_get_config(win).relative == ""
  -- rainbow brackets (brackets.lua): a colour a level
  local rainbow = not large and plain and vim.g.plato_rainbow ~= false
  local brackets = require("plato.brackets")
  -- markdown drawn as what it means (markdown.lua), in an editor's window
  local mdm = require("plato.markdown")
  local md = plain and mdm.active(buf)

  local top = vim.fn.line("w0") - 1
  local bot
  do
    -- a generous bottom: with folds, concealed lines or wrapping, fewer lines
    -- than rows fit, so this over-counts rather than under
    local l, rows, skipped = top + 1, 0, 0
    while l <= last and rows < height do
      local fe = vim.fn.foldclosedend(l)
      if fe ~= -1 then skipped = skipped + (fe - l); l = fe + 1
      else l = l + 1 end
      rows = rows + 1
    end
    bot = math.min(last - 1, top + height + skipped + ((cl > 0 or md) and height or 0))
  end

  -- the highlight ranges reach the rows past the edges too (see `margin`)
  local hlTop = math.max(0, top - margin)
  local hlBot = math.min(last - 1, bot + margin * 2)
  local tsPaints, tsConceal, tsHidden = hl.treesitter(buf, hlTop, hlBot)
  local deco, signs, virt, xConceal = extmarks(buf, hlTop, hlBot)
  local mdLines = md and mdm.compute(buf, hlTop, hlBot) or {}
  local mdRaw = md and mdm.rawLine()
  local found = searchMatches(buf, top, bot, isCurrent and view.lnum - 1 or -1, view.col)
  local sel = isCurrent and selection(mode) or {}
  -- the bracket at the cursor and its partner, both on screen: l0 → { bytes }
  local pairAt = {}
  if isCurrent and not large and not mode:find("^c") then
    local m1 = mode:sub(1, 1)
    local ok, pr = pcall(brackets.pair, buf, view.lnum - 1, view.col,
      m1 == "i" or m1 == "R", top, bot)
    if ok and pr then
      for _, b in ipairs(pr) do
        pairAt[b[1]] = pairAt[b[1]] or {}
        table.insert(pairAt[b[1]], b[2])
      end
    end
  end
  -- the search match the cursor sits on, in this window's cells
  local hit = nil

  local function concealFor(l)
    if md then
      -- the cursor's line as written, so it never sits on a hidden star
      if mdRaw and isCurrent and l == view.lnum - 1 then return nil end
      local list = {}
      for _, src in ipairs({ mdLines[l] and mdLines[l].cc or {}, xConceal[l] or {} }) do
        for _, c in ipairs(src) do
          list[#list + 1] = { c[1], c[2] == -1 and math.huge or c[2], c[3] ~= "" and c[3] or nil }
        end
      end
      if #list == 0 then return nil end
      return M.mergeConceal(list)
    end
    if cl == 0 then return nil end
    if isCurrent and l == view.lnum - 1 then
      local cc = vim.wo[win].concealcursor
      local m = mode:sub(1, 1)
      if not cc:find(m == "V" and "v" or m, 1, true) then return nil end
    end
    local list = {}
    for _, src in ipairs({ tsConceal and tsConceal[l] or {}, xConceal[l] or {} }) do
      for _, c in ipairs(src) do
        local ch = c[3] ~= "" and c[3] or nil
        if cl == 1 then ch = ch or " " elseif cl == 3 then ch = nil end
        list[#list + 1] = { c[1], c[2] == -1 and math.huge or c[2], ch }
      end
    end
    if #list == 0 then return nil end
    return M.mergeConceal(list)
  end

  -- ── INDENT GUIDES ────────────────────────────────────────────────────
  -- A guide every 'shiftwidth' cells inside a line's indent. A blank line
  -- takes the deeper of the lines around it, so a guide runs on through
  -- the gaps in a block rather than breaking at each one.
  local indents = {}
  local function indentAt(l1)
    local v = indents[l1]
    if v then return v end
    if l1 < 1 or l1 > last then return 0 end
    if vim.fn.getline(l1):find("%S") then v = vim.fn.indent(l1)
    else
      local p, n = vim.fn.prevnonblank(l1), vim.fn.nextnonblank(l1)
      v = math.max(p > 0 and vim.fn.indent(p) or 0, n > 0 and vim.fn.indent(n) or 0)
    end
    indents[l1] = v
    return v
  end
  local function guideCols(l1, from)
    local ind = indentAt(l1)
    if ind <= 0 then return nil end
    local out = {}
    for c = 0, ind - 1, sw do
      if c >= from then out[#out + 1] = c - from end
    end
    return #out > 0 and out or nil
  end

  local rows = {}
  -- rendered markdown: which bytes each window row's cells are, for a
  -- click (bridge.mouse) — nvim maps a screen cell by the text as written
  local clicks = md and {} or nil
  -- git's marks for this buffer (git.lua): a bar down the gutter's edge
  local vcs = require("plato.git").marks(buf)
  -- the cursor's cell, and which character of its row's text that is: the
  -- same number unless a wide character comes before it on the row
  local cursorRow, cursorCol, cursorChar = 0, 0, 0
  local ccolAbs
  do
    local vc = vim.fn.virtcol(".", 1)
    local onTab = api.nvim_get_current_line():sub(view.col + 1, view.col + 1) == "\t"
    ccolAbs = ((mode == "n" and onTab) and vc[2] or vc[1]) - 1
  end

  -- ── THE LINES, AS ROWS ─────────────────────────────────────────────────
  -- From line `l0` on, until `into` holds `target` rows (or line `stop` is
  -- reached): the window's own rows (`live`: the cursor, a :s preview, the
  -- top line's skipcol), and the few just past each edge that plato draws
  -- outside the window for the frost under its bars (see `margin`).
  local function run(l0, target, into, live, stop)
  local rows = into
  local height = target
  local l = l0
  while #rows < height and (not stop or l < stop) do
    if l >= last then
      if not live then break end
      rows[#rows + 1] = { n = 0, k = 0, t = "", s = {}, f = false }
    elseif ((cl > 0 and tsHidden and tsHidden[l]) or (md and mdLines[l] and mdLines[l].hide))
        and not (isCurrent and l == view.lnum - 1) then
      -- a whole line concealed (conceal_lines): not a row at all
      l = l + 1
      goto nextline
    else
      local fold = vim.fn.foldclosed(l + 1)
      if fold ~= -1 then
        -- A CLOSED FOLD IS ITS FIRST LINE, in its own colours, and a pill
        -- after it saying how many lines are folded under it — not
        -- foldtext's dashes across the row.
        local fe = vim.fn.foldclosedend(l + 1)
        local chip = "\u{22EF} " .. (fe - l) .. " lines"
        local chipW = cellWidth(chip)
        local first = (api.nvim_buf_get_lines(buf, l, l + 1, false)[1] or ""):gsub("%s+$", "")
        local t, fchars = layout(first, ts, wrap and 0 or view.leftcol, math.max(0, width - chipW - 3))
        local fbase = {}
        local nc = cellWidth(t)
        if tsPaints then
          for _, p in ipairs(tsPaints[l] or {}) do paint(fbase, fchars, nc, p[1], p[2], p[3]) end
        else
          for _, r in ipairs(hl.syntax(buf, l, first, fchars) or {}) do paint(fbase, fchars, nc, r[1], r[2], r[3]) end
        end
        local fc = nil
        if width - nc >= chipW + 3 then
          local at = nc + 2
          t = t .. string.rep(" ", at - nc) .. chip
          for c = at, at + chipW - 1 do fbase[c] = "PlatoFoldChip" end
          fc = { at, chipW }
          nc = at + chipW
        end
        if live and view.lnum - 1 >= l and view.lnum <= fe then
          cursorRow, cursorCol, cursorChar = #rows, 0, 0
        end
        rows[#rows + 1] = { n = l + 1, k = 0, t = t, f = true,
          s = charSpans(t, spans(fbase, {}, {}, 0, nc)), g = nil, fc = fc, fo = 2 }
        -- foldclosedend is 1-based: as a 0-based index it is the fold's
        -- last line, and the loop's own step moves past it
        l = vim.fn.foldclosedend(l + 1) - 1
      else
        local line = api.nvim_buf_get_lines(buf, l, l + 1, false)[1] or ""
        -- a :s being typed: the line as it would become (subst.lua)
        local subLit
        local sp = M._subst
        -- isCurrent, not nvim_get_current_win(): this runs inside
        -- nvim_win_call, where every window is the current one, and the
        -- preview spilled into every split and float
        if sp and live and isCurrent and l + 1 >= sp.first and l + 1 <= sp.last
          and (not sp.only or sp.only[l + 1]) then
          local new, lit = sp.apply(line)
          if new then line, subLit = new, lit end
        end
        -- nowrap: the one row starting at leftcol. wrap: every row of the line,
        -- from skipcol on the top line, but never more than the screen holds
        local from = wrap and ((live and l == top) and view.skipcol or 0) or view.leftcol
        local limit = wrap and width * (height - #rows) or width
        local hid = concealFor(l)
        local concealed = hid ~= nil
        local text, chars, lineCells = layout(line, ts, from, limit, hid)
        -- A FOLD STARTS HERE (open): the gutter's ring, the file tree's
        -- expander, which a click closes (EditorView). Its level above the
        -- line before is what starting one means; a closed fold is the row
        -- above, with fo = 2.
        local opensFold = vim.wo.foldenable
          and vim.fn.foldlevel(l + 1) > (l > 0 and vim.fn.foldlevel(l) or 0)
        local ncells = cellWidth(text)

        local base, dl, ol = {}, {}, {}
        if subLit then
          -- the preview's own colours: the text plain, what is new lit
          for _, r in ipairs(subLit) do paint(ol, chars, ncells, r[1], r[2], "Substitute") end
        elseif tsPaints then
          for _, p in ipairs(tsPaints[l] or {}) do paint(base, chars, ncells, p[1], p[2], p[3]) end
        else
          local runs = hl.syntax(buf, l, line, chars)
          for _, r in ipairs(runs or {}) do paint(base, chars, ncells, r[1], r[2], r[3]) end
        end
        local mdl = mdLines[l]
        if mdl and not subLit then
          for _, p in ipairs(mdl.paint) do paint(base, chars, ncells, p[1], p[2], p[3]) end
        end
        -- rainbow brackets, over the syntax's own colour — but not a bracket
        -- the syntax says is in a string or a comment
        if rainbow and not md and not subLit and line:find("[%(%)%[%]{}]") then
          for _, rb in ipairs(brackets.rainbow(buf, l, line)) do
            local k = seek(chars, rb[1])
            local ch = chars[k]
            if ch and ch[1] == rb[1] then
              local g = (base[math.max(0, ch[3])] or ""):lower()
              if not (g:find("comment") or g:find("string")) then
                paint(base, chars, ncells, rb[1], rb[1] + 1, "PlatoRainbow" .. (rb[2] % 6 + 1))
              end
            end
          end
        end
        for _, p in ipairs(deco[l] or {}) do paint(dl, chars, ncells, p[1], p[2], p[3]) end
        if not large then
          for _, p in ipairs(colorCodes(line, qml)) do paint(dl, chars, ncells, p[1], p[2], p[3]) end
        end
        -- words spelled wrong (spell.lua): in prose all of them, in code
        -- only those in comments and strings
        if spell and line:find("%a") then
          for _, w in ipairs(vim.spell.check(line)) do
            local b0 = w[3] - 1
            local ok = prose
            if not ok then
              local k = seek(chars, b0)
              local ch = chars[k]
              local g = ch and base[math.max(0, ch[3])]
              g = g and g:lower() or ""
              ok = g:find("comment") ~= nil or g:find("string") ~= nil
            end
            if ok then
              local grp = w[2] == "caps" and "SpellCap" or w[2] == "rare" and "SpellRare"
                or w[2] == "local" and "SpellLocal" or "SpellBad"
              paint(dl, chars, ncells, b0, b0 + #w[1], grp)
            end
          end
        end
        local hitCells = nil
        if not subLit then
          for _, p in ipairs(found[l] or {}) do
            paint(ol, chars, ncells, p[1], p[2], p[3])
            if live and p[3] == "CurSearch" then
              local k0 = seek(chars, p[1])
              local k1 = seek(chars, math.max(p[1] + 1, p[2])) - 1
              if chars[k0] and chars[k1] then
                hitCells = { chars[k0][3], chars[k1][3] + chars[k1][4] }
              end
            end
          end
        end
        local sl = sel[l]
        if sl then
          paint(ol, chars, ncells, sl[1], sl[2], "Visual")
          -- one cell past the text, where nvim shows the selection reaching
          -- the end of an empty or line-wise-selected line
          if sl[3] and (lineCells - from) >= 0 and (lineCells - from) < limit then
            local at = lineCells - from
            if at >= ncells then
              text = text .. string.rep(" ", at - ncells + 1)
              ncells = at + 1
            end
            ol[at] = "Visual"
          end
        end

        -- End-of-line virtual text: one blank cell after the text, as nvim
        -- places it, on the line's last row — and CUT at the window's edge,
        -- not wrapped onto a row of its own. nvim wraps inline virtual text
        -- but never eol text; a diagnostic that reached the next row made the
        -- file look a line longer than it is.
        local v = virt[l]
        local pill = nil
        if v and (lineCells - from) < limit then
          local rowEnd = wrap
            and math.max(1, math.ceil(math.max(ncells, 1) / width)) * width
            or width
          local at = math.max(ncells, lineCells - from + 1)
          if at < rowEnd then
            text = text .. string.rep(" ", at - ncells)
            ncells = at
            for _, chunk in ipairs(v) do
              local s, g = chunk[1], chunk[2]
              if type(g) == "table" then g = g[#g] end
              local full = cellWidth(s)
              local w = math.min(full, rowEnd - ncells)
              if w <= 0 then pill = pill and { pill[1], pill[2], pill[3], true }; break end
              -- a diagnostic sits in a pill of its severity's colour
              local sev = type(g) == "string" and g:match("^DiagnosticVirtualText(%a+)")
              if sev then
                local lead = #(s:match("^%s*"))
                if lead < w then
                  local kind = ({ Error = "e", Warn = "w", Info = "i", Hint = "h" })[sev] or "h"
                  if pill then pill[2] = ncells + w
                  else pill = { ncells + lead, ncells + w, kind, false } end
                end
              end
              text = text .. cellSlice(s, 0, w)
              for c = ncells, ncells + w - 1 do base[c] = g end
              ncells = ncells + w
              if w < full then
                -- cut by the edge: its last cell says so
                if pill then pill[4] = true end
                text = cellSlice(text, 0, ncells - 1) .. "\u{2026}"
                break
              end
            end
          end
        end

        -- the cursor, if it is on this line
        local onLine = live and (l == view.lnum - 1)
        local pieces = wrap and math.max(1, math.ceil(math.max(ncells, 1) / width)) or 1
        for k = 0, pieces - 1 do
          if #rows >= height then break end
          local c0 = wrap and k * width or 0
          local c1 = wrap and math.min(ncells, c0 + width) or math.min(ncells, width)
          local piece = cellSlice(text, c0, c1)
          if onLine then
            local rel = ccolAbs - from
            local at
            if wrap then
              if (rel >= c0 and rel < c0 + width) or (k == pieces - 1 and rel >= c0) then
                at = rel - c0
              end
            else
              at = rel
            end
            if at then
              cursorRow, cursorCol = #rows, at
              -- (past the text's end, a cell is a character again)
              cursorChar = (at > 0 and not ascii(piece))
                and vim.fn.strchars(cellSlice(piece, 0, at)) + math.max(0, at - cellWidth(piece))
                or at
            end
          end
          local sign = (k == 0) and signs[l] or nil
          -- the outlined pair, the selection, a diagnostic's pill and the
          -- search hit: each in this piece's own cells
          local m = nil
          for _, pb in ipairs(pairAt[l] or {}) do
            local pk = seek(chars, pb)
            local pc = chars[pk]
            if pc and pc[1] == pb and pc[3] >= c0 and pc[3] < c1 then
              m = m or {}
              m[#m + 1] = pc[3] - c0
            end
          end
          local slc = nil
          if sl then
            local a, z
            for c = c0, math.max(c0, c1) - 1 do
              if ol[c] == "Visual" then a = a or c; z = c end
            end
            if a then slc = { a - c0, z + 1 - c0 } end
          end
          local vt = nil
          if pill and pill[1] < c1 and pill[2] > c0 then
            vt = { math.max(pill[1], c0) - c0, math.min(pill[2], c1) - c0, pill[3], pill[4] }
          end
          if hitCells and hitCells[1] >= c0 and hitCells[1] < math.max(c1, c0 + 1) then
            hit = { row = #rows, col = hitCells[1] - c0, len = hitCells[2] - hitCells[1] }
          end
          -- every row, once markdown has hidden a line: below it, nvim's
          -- own rows and the drawn ones no longer match
          if clicks and live then
            clicks[#rows] = { l = l, chars = chars, c0 = c0, len = #line }
          end
          rows[#rows + 1] = {
            n = l + 1, k = k, t = piece, f = false,
            s = charSpans(piece, spans(base, dl, ol, c0, c1)),
            g = sign and { sign[1], sign[2] and hl.style(sign[2]) or 0 } or nil,
            v = vcs and vcs[l + 1] or nil,
            ig = (guides and k == 0 and not (wrap and from > 0)) and guideCols(l + 1, wrap and 0 or from) or nil,
            m = m, sl = slc, vt = vt,
            fo = (opensFold and k == 0 and not (wrap and from > 0)) and 1 or nil,
            md = mdl and mdRow(mdl, k, pieces, wrap and 0 or from, mdRaw and live and isCurrent and l == view.lnum - 1) or nil,
          }
        end
      end
      l = l + 1
    end
    ::nextline::
  end
  return l
  end

  run(top, height, rows, true)
  -- kept as plain data: the click arrives in a fast callback (bridge.lua),
  -- where nvim cannot be asked where a window is
  if clicks then
    local pos = api.nvim_win_get_position(win)
    M.clicks[win] = { rows = clicks, r0 = pos[1], c0 = pos[2] + textoff, h = height, w = width }
  else
    M.clicks[win] = nil
  end

  -- ── PAST THE EDGES ─────────────────────────────────────────────────────
  -- `margin` rows above the window and below it, drawn by plato just
  -- outside the window, so the frost under the tab strip and the status
  -- line is the file as it is now — the rows the glide happened to keep
  -- were the past (a tab switch left nothing, an edit pushed rows down
  -- that never reached it). Above: from `margin` lines up, keeping the last
  -- `margin` rows (a wrapped line is several).
  -- A WRAPPED LINE CUT BY AN EDGE COUNTS TOO. Scrolled partway down a long
  -- line (skipcol), the rows of it above the window are what is under the
  -- tab strip, and a line cut off at the bottom goes on under the status
  -- line: a file of a few very long lines (front matter, prose) had no
  -- whole line past either edge and nothing to frost.
  local above, below = {}, {}
  if margin > 0 then
    local skipRows = (wrap and view.skipcol > 0 and width > 0) and math.floor(view.skipcol / width) or 0
    if top > 0 or skipRows > 0 then
      local got = {}
      run(math.max(0, top - margin), 100000, got, false, skipRows > 0 and top + 1 or top)
      -- of the top line itself, only the rows skipped
      if skipRows > 0 then
        local kept, seen = {}, 0
        for _, r in ipairs(got) do
          if r.n == top + 1 then
            seen = seen + 1
            if seen <= skipRows then kept[#kept + 1] = r end
          else kept[#kept + 1] = r end
        end
        got = kept
      end
      for i = math.max(1, #got - margin + 1), #got do above[#above + 1] = got[i] end
    end
    -- below: on from where the window stopped — the rest of a line it cut
    -- off, then the lines it did not reach
    local nextL, shownOfLast = top, 0
    for i = #rows, 1, -1 do
      if rows[i].n > 0 then
        local r = rows[i]
        nextL = r.f and vim.fn.foldclosedend(r.n) or r.n
        if not r.f then
          for j = i, 1, -1 do
            if rows[j].n ~= r.n then break end
            shownOfLast = shownOfLast + 1
          end
          -- the top line shows from skipcol: those rows came first
          if r.n == top + 1 then shownOfLast = shownOfLast + skipRows end
        end
        break
      end
    end
    if wrap and shownOfLast > 0 and nextL > 0 and nextL <= last then
      local got = {}
      run(nextL - 1, shownOfLast + margin, got, false)
      for i = shownOfLast + 1, #got do below[#below + 1] = got[i] end
    elseif nextL < last and nextL > 0 then run(nextL, margin, below, false) end
  end

  -- ── THE CURSOR'S BLOCK ───────────────────────────────────────────────
  -- Which guide is the block the cursor is in, and the lines it runs down,
  -- so plato can draw that one brighter. On a line that opens a block (the
  -- next line is deeper), the block it opens; otherwise the one its own
  -- indent sits in.
  local scope = nil
  if guides and isCurrent then
    local tick = api.nvim_buf_get_changedtick(buf)
    local key = table.concat({ buf, tick, view.lnum, sw, view.leftcol }, ":")
    if M._scopeKey == key then scope = M._scope
    else
      local cl = view.lnum
      local ci = indentAt(cl)
      local nn = vim.fn.nextnonblank(cl + 1)
      local col
      if vim.fn.getline(cl):find("%S") and nn > 0 and vim.fn.indent(nn) > ci then col = ci
      elseif ci > 0 then col = math.floor((ci - 1) / sw) * sw end
      if col then
        local first, lastL = cl, cl
        local lo = math.max(1, cl - 3000)
        local hi = math.min(last, cl + 3000)
        while first - 1 >= lo and indentAt(first - 1) > col do first = first - 1 end
        while lastL + 1 <= hi and indentAt(lastL + 1) > col do lastL = lastL + 1 end
        -- the opener itself is not inside its block
        if indentAt(first) <= col then first = first + 1 end
        if first <= lastL then
          scope = { col = col - (wrap and 0 or view.leftcol), first = first, last = lastL }
        end
      end
      M._scopeKey, M._scope = key, scope
    end
  end

  return {
    rows = rows, above = above, below = below,
    height = height, width = width, buf = buf, view = view,
    wrap = wrap, last = last, textoff = textoff, scope = scope, hit = hit,
    cursor = { row = cursorRow, col = math.max(0, cursorCol), ch = math.max(0, cursorChar) },
  }
end

local function signature(row)
  return row.n .. "\1" .. row.k .. "\1" .. row.t .. "\1" .. tostring(row.f)
    .. "\1" .. vim.json.encode(row.s) .. "\1" .. vim.json.encode(row.g or false)
    .. "\1" .. (row.v or "") .. "\1" .. (row.ig and table.concat(row.ig, ",") or "")
    .. "\1" .. vim.json.encode({ row.m or false, row.sl or false, row.vt or false, row.fc or false,
      row.md or false, row.fo or false })
end

-- ── the editor window ───────────────────────────────────────────────────
-- The window plato's editor surface shows: the current one, unless the
-- current one is a float (you have jumped into a hover with K K), in which
-- case the last ordinary window you were in.
local lastNormal = nil
local function isFloat(w) return api.nvim_win_get_config(w).relative ~= "" end
local function editorWindow()
  local cur = api.nvim_get_current_win()
  if not isFloat(cur) then lastNormal = cur; return cur end
  if lastNormal and api.nvim_win_is_valid(lastNormal) then return lastNormal end
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    if not isFloat(w) then lastNormal = w; return w end
  end
  return cur
end

-- ── floats ──────────────────────────────────────────────────────────────
-- Every visible float, drawn by plato as a card of its own at nvim's position
-- for it — so hover, signature help, completion's documentation and the
-- diagnostic float all come for free, whoever opened them.
--   { id, row, col, width, height, z, rows, cursor? }
-- Positions are in the editor window's cells, the same grid as its rows.
local sentFloats = ""
local function floats(mode)
  local out = {}
  local cur = api.nvim_get_current_win()
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    local cfg = api.nvim_win_get_config(w)
    if cfg.relative ~= "" and not cfg.hide then
      local pos = api.nvim_win_get_position(w)
      local isCur = (w == cur)
      local b = api.nvim_win_call(w, function() return build(w, isCur, mode) end)
      -- trailing empty rows: a float sized to its text has none, one that
      -- is not still should not draw a tail of blank card
      local rows = b.rows
      while #rows > 1 and rows[#rows].n == 0 do rows[#rows] = nil end
      for i, r in ipairs(rows) do r.i = i - 1 end
      out[#out + 1] = {
        id = w, row = pos[1], col = pos[2], width = b.width, height = #rows,
        textoff = b.textoff,
        z = cfg.zindex or 50, rows = rows, focusable = cfg.focusable ~= false,
        cursor = isCur and b.cursor or nil,
        -- a name for the card (peek.lua sets one)
        title = vim.w[w].plato_title or nil,
      }
    end
  end
  table.sort(out, function(a, b) return a.z < b.z end)
  local sig = vim.json.encode(out)
  if sig == sentFloats then return nil end
  sentFloats = sig
  return out
end

-- ── the open buffers: plato's tabs ─────────────────────────────────────
-- Every listed buffer, in nvim's order, sent only when something about the
-- list changed — a buffer opened or closed, renamed, modified or saved, or
-- another one made current.
--   { id, name, path, modified, current, pin? }
local sentBuffers = ""
local function buffers()
  local cur = api.nvim_win_get_buf(editorWindow())
  local pins = require("plato.pins").numbers()
  local out = {}
  for _, b in ipairs(api.nvim_list_bufs()) do
    if vim.bo[b].buflisted then
      local full = api.nvim_buf_get_name(b)
      out[#out + 1] = {
        id = b,
        name = full ~= "" and vim.fs.basename(full) or "[no name]",
        path = full ~= "" and vim.fn.fnamemodify(full, ":~") or "",
        modified = vim.bo[b].modified,
        current = b == cur,
        -- its number on Alt, when it is pinned (pins.lua)
        pin = pins[full],
      }
    end
  end
  local sig = vim.json.encode(out)
  if sig == sentBuffers then return nil end
  sentBuffers = sig
  return out
end

-- ── every match in the file ─────────────────────────────────────────────
-- Asked for twice a frame — the search count ("3 of 12") and the scrollbar's
-- marks — and the same answer until the text or the pattern changes. Kept
-- per (buffer, changedtick, pattern, case options), as a flat list of match
-- starts { lnum, byte, lnum, byte, … } in file order, read in slices of a
-- thousand lines and stopped once there are MAXCOUNT of them.
--
-- WHY NOT searchcount(). With recompute it walks the whole file on every
-- frame — every key — up to its 30 ms timeout while a search was lit. A
-- moved cursor needs no new walk: the count before it is a binary search
-- here. searchcount() is still asked when this cannot answer: a pattern
-- that can match across lines (matchbufline cannot), a file past
-- MATCHLINES, or a cursor past where an incomplete list stopped.
local MAXCOUNT, MATCHLINES = 9999, 20000
local matchKey, matchList = nil, nil
local function allMatches(buf, pat)
  if pat:find("\\n") or pat:find("\\_") then return nil end
  local last = api.nvim_buf_line_count(buf)
  if last > MATCHLINES then return nil end
  local key = table.concat({ buf, api.nvim_buf_get_changedtick(buf), pat,
    tostring(vim.o.ignorecase), tostring(vim.o.smartcase), tostring(vim.o.magic) }, "\1")
  if key == matchKey then return matchList end
  local list = { n = 0, incomplete = false, upto = last }
  local from = 1
  while from <= last do
    local to = math.min(last, from + 999)
    local ok, hits = pcall(vim.fn.matchbufline, buf, pat, from, to)
    if not ok then list = nil; break end
    for _, h in ipairs(hits) do
      if list.n >= MAXCOUNT then list.incomplete = true; list.upto = h.lnum - 1; break end
      list[#list + 1] = h.lnum
      list[#list + 1] = h.byteidx
      list.n = list.n + 1
    end
    if list.incomplete then break end
    from = to + 1
  end
  matchKey, matchList = key, list
  return list
end

-- how many matches start at or before (lnum, byte): searchcount's `current`
local function countUpTo(list, lnum, byte)
  local lo, hi = 1, list.n + 1
  while lo < hi do
    local mid = math.floor((lo + hi) / 2)
    local ml, mb = list[mid * 2 - 1], list[mid * 2]
    if ml < lnum or (ml == lnum and mb <= byte) then lo = mid + 1 else hi = mid end
  end
  return lo - 1
end

-- ── the scrollbar's marks ───────────────────────────────────────────────
-- Where in the whole file there is something to find: diagnostics ("e" "w"
-- "i" "h", by severity), search matches ("s") and git's changes ("a" "c"
-- "d"), as { line, kind }. Sent only when they change. Matches are looked
-- for in files of up to 20000 lines, and no more than 2000 are kept.
local sentMarks = ""
local sevKind = { "e", "w", "i", "h" }
-- recounted only when something they come from moved: the text, the
-- search, diagnostics or git (marksGen, bumped by their events in setup)
M.marksGen = 0
local marksKey = ""
local function scrollMarks(buf)
  local key = table.concat({ buf, api.nvim_buf_get_changedtick(buf), vim.v.hlsearch,
    vim.fn.getreg("/"), M.marksGen }, "\1")
  if key == marksKey then return nil end
  marksKey = key
  local out = {}
  for _, d in ipairs(vim.diagnostic.get(buf)) do
    out[#out + 1] = { d.lnum + 1, sevKind[d.severity] or "h" }
  end
  if vim.v.hlsearch == 1 then
    local pat = searchPattern(true)
    local list = pat and allMatches(buf, pat)
    if list then
      local seen, kept = {}, 0
      for k = 1, list.n do
        if kept >= 2000 then break end
        local l = list[k * 2 - 1]
        if not seen[l] then seen[l] = true; kept = kept + 1; out[#out + 1] = { l, "s" } end
      end
    end
  end
  for _, g in ipairs(require("plato.git").list(buf)) do out[#out + 1] = g end
  local sig = vim.json.encode(out)
  if sig == sentMarks then return nil end
  sentMarks = sig
  return out
end

-- ── the frame ───────────────────────────────────────────────────────────
-- EVERY WINDOW, AS NVIM LAID THEM OUT. A split is nvim's: :vsplit, <C-w>,
-- fugitive opening its status beside the file — each window is sent with
-- its place on nvim's grid, and plato draws it there. Rows are diffed per
-- window; a window that moved or changed size is sent whole.
--   wins: [{ id, row, col, width, height, textoff, full, rows, cursor,
--            current, lines }]
local sentWins = {}   -- window id → { geo, sigs }

function M.frame(full)
  local modeInfo = api.nvim_get_mode()
  local mode = modeInfo.mode
  M._subst = require("plato.subst").compute()
  local ed = editorWindow()
  local cur = api.nvim_get_current_win()
  local wins, seen = {}, {}
  local edBuild
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    if not isFloat(w) then
      local pos = api.nvim_win_get_position(w)
      -- four rows past each edge: the frost under plato's bars (see build)
      local b = api.nvim_win_call(w, function() return build(w, w == cur, mode, 4) end)
      if w == ed then edBuild = b end
      local geo = table.concat({ pos[1], pos[2], b.width, b.height, b.textoff }, ",")
      local prev = sentWins[w]
      local whole = full or not prev or prev.geo ~= geo
      local sigs = whole and {} or prev.sigs
      local changed = {}
      for r = 1, b.height do
        local row = b.rows[r]
        local sig = signature(row)
        if whole or sigs[r] ~= sig then
          row.i = r - 1
          changed[#changed + 1] = row
          sigs[r] = sig
        end
      end
      for r = b.height + 1, #sigs do sigs[r] = nil end
      -- the rows past the edges, sent whole and only when they changed
      local extraSig = vim.json.encode({ b.above, b.below })
      local extraNew = whole or not prev or prev.extra ~= extraSig
      sentWins[w] = { geo = geo, sigs = sigs, extra = extraSig }
      seen[w] = true
      wins[#wins + 1] = {
        id = w, row = pos[1], col = pos[2], width = b.width + b.textoff,
        height = b.height, textoff = b.textoff, full = whole, rows = changed,
        cursor = b.cursor, current = w == ed, lines = b.last,
        -- the first line in view, for the window's scrollbar
        top = b.view.topline,
        rnu = vim.wo[w].relativenumber,
        -- which buffer: rows are keyed by line number alone, so without it a
        -- switch of file looked like a scroll to the drawing (see WindowView)
        buf = api.nvim_win_get_buf(w),
        -- rows just above and below the window, or nil for unchanged
        above = extraNew and b.above or nil,
        below = extraNew and b.below or nil,
      }
    end
  end
  for w in pairs(sentWins) do
    if not seen[w] then sentWins[w] = nil end
  end
  for w in pairs(M.clicks) do
    if not seen[w] then M.clicks[w] = nil end
  end

  if full then
    sentFloats = ""; sentBuffers = ""; sentMarks = ""; marksKey = ""; M._sentContext = nil
    require("plato.status").forget()
    require("plato.minimap").reset()
  end
  local fl = floats(mode)
  local bufs = buffers()

  local b = edBuild
  local buf, view = b.buf, b.view
  local name = api.nvim_buf_get_name(buf)

  -- "3 of 12" while a search is lit or being typed, as nvim's own [3/12]
  -- would have said in the command line it does not draw. Capped, so a huge
  -- file costs a moment rather than a stall.
  local search = vim.NIL
  do
    local ct = vim.fn.getcmdtype()
    local typing = (ct == "/" or ct == "?")
    if typing or (vim.v.hlsearch == 1 and vim.fn.getreg("/") ~= "") then
      local pat = searchPattern()
      local list = pat and allMatches(buf, pat)
      local cur = api.nvim_win_get_cursor(ed)
      if list and cur[1] <= list.upto then
        search = { current = countUpTo(list, cur[1], cur[2]), total = list.n,
                   incomplete = list.incomplete and 1 or 0 }
      elseif pat then
        local ok, sc = pcall(vim.fn.searchcount, {
          recompute = 1, maxcount = MAXCOUNT, timeout = 30,
          pattern = typing and vim.fn.getcmdline() or nil,
        })
        if ok and sc.total then
          search = { current = sc.current, total = sc.total, incomplete = sc.incomplete }
        end
      end
    end
  end

  -- THE COMMAND LINE, READ RATHER THAN TOLD. ext_cmdline's cmdline_show
  -- is sent from nvim's screen flush, and a headless nvim with only a Lua UI
  -- never flushes: plato got the hide and never the show, so ":" opened
  -- nothing. The same facts are asked for here, on every frame the command
  -- line is open (CmdlineChanged and every key make one).
  local cmdline = vim.NIL
  do
    local ct = vim.fn.getcmdtype()
    if ct ~= "" then
      local okp, prompt = pcall(vim.fn.getcmdprompt)
      cmdline = {
        text = vim.fn.getcmdline(),
        pos = math.max(0, vim.fn.getcmdpos() - 1),
        -- input() is "@"; its line has no first character, only a prompt
        firstc = (ct == "@" or ct == "-") and "" or ct,
        prompt = okp and prompt or "",
      }
    end
  end

  -- A SEARCH JUMP (n, N, *, #, or / and ? confirmed) lands on a match:
  -- plato pulses an outline round it, so the eye finds where it went
  local pulse = vim.NIL
  if M._searchJump and M._searchJump > 0 then
    if b.hit then
      pulse = { row = b.hit.row, col = b.hit.col, len = b.hit.len, win = ed }
      M._searchJump = 0
    else
      M._searchJump = M._searchJump - 1
    end
  end
  local marks = scrollMarks(buf)
  -- the minimap's lines go on their own, a moment later (minimap.lua)
  pcall(require("plato.minimap").poke, ed, buf)
  -- zen mode: the paragraph the cursor is in, which plato keeps lit while
  -- the rest of the text is dimmed
  local para = vim.NIL
  if vim.g.plato_zen then
    para = api.nvim_win_call(ed, function()
      local up = vim.fn.search("^\\s*$", "bnW")
      local down = vim.fn.search("^\\s*$", "nW")
      return { up + 1, down == 0 and b.last or down - 1 }
    end)
  end
  -- sticky scroll (sticky.lua): sent when it changes
  local ctx = vim.NIL
  do
    local okc, c = pcall(function()
      return api.nvim_win_call(ed, function()
        return require("plato.sticky").context(ed, buf, view.topline)
      end)
    end)
    local list = okc and c or {}
    local sig = vim.json.encode(list)
    if sig ~= M._sentContext then M._sentContext = sig; ctx = list end
  end
  -- the status line's facts (status.lua): sent when they change
  local okst, st = pcall(require("plato.status").compute, ed, buf, mode)
  return {
    status = okst and st or vim.NIL,
    context = ctx,
    -- the indent guide of the block the cursor is in: { col, first, last }
    scope = b.scope or vim.NIL,
    -- multicursor.nvim's cursors, when there are several (1 otherwise)
    cursors = (function()
      local mcm = package.loaded["multicursor-nvim"]
      local okn, n = pcall(function() return mcm and mcm.numCursors() or 1 end)
      return okn and n or 1
    end)(),
    para = para,
    pulse = pulse,
    marks = marks or vim.NIL,
    cmdline = cmdline,
    search = search,
    event = "view",
    grid = { rows = vim.o.lines, cols = vim.o.columns },
    wins = wins,
    floats = fl,
    buffers = bufs,
    -- the cursor is in a float, not in any window's rows
    inFloat = ed ~= cur,
    styles = hl.takeFresh(),
    line = view.lnum,
    column = api.nvim_win_call(ed, function() return vim.fn.virtcol(".") end),
    lines = b.last,
    mode = mode,
    blocking = modeInfo.blocking,
    wrap = b.wrap,
    file = name ~= "" and vim.fn.fnamemodify(name, ":~") or "",
    filetype = vim.bo[buf].filetype,
    modified = vim.bo[buf].modified,
    readonly = vim.bo[buf].readonly or not vim.bo[buf].modifiable,
  }
end

-- Coalesced: however many things change in one trip round the event loop —
-- a `dd` fires on_lines, TextChanged, CursorMoved and WinScrolled — the
-- client gets one frame, built after all of them have landed.
function M.schedule(full)
  if full then M._full = true end
  if pending then return end
  pending = true
  vim.schedule(function()
    pending = false
    local f = M._full
    M._full = false
    if emit then emit(M.frame(f)) end
  end)
end

local attached = {}
local function attach(buf)
  if attached[buf] or not api.nvim_buf_is_loaded(buf) then return end
  attached[buf] = true
  api.nvim_buf_attach(buf, false, {
    on_lines = function(_, b, _, first)
      hl.invalidateFrom(b, first)
      require("plato.brackets").invalidate(b, first)
      M.schedule()
    end,
    on_detach = function(_, b) attached[b] = nil; hl.forget(b); require("plato.brackets").forget(b) end,
    on_reload = function(_, b) hl.forget(b); require("plato.brackets").forget(b); M.schedule(true) end,
  })
end

function M.setup(send)
  emit = send
  local group = api.nvim_create_augroup("plato.view", { clear = true })
  api.nvim_create_autocmd({
    "CursorMoved", "CursorMovedI", "ModeChanged", "WinScrolled",
    "WinResized", "VimResized", "BufWritePost", "BufModifiedSet",
    "CmdlineLeave", "CmdlineChanged", "TextChanged", "TextChangedI",
    "DiagnosticChanged", "TextYankPost", "BufAdd", "BufDelete", "BufWipeout",
    "BufFilePost",
  }, { group = group, callback = function() M.schedule() end })
  -- what the scrollbar's marks come from, other than the text and search
  api.nvim_create_autocmd("DiagnosticChanged", {
    group = group, callback = function() M.marksGen = M.marksGen + 1 end })
  api.nvim_create_autocmd("User", { group = group, pattern = "MiniDiffUpdated",
    callback = function() M.marksGen = M.marksGen + 1 end })
  -- a different buffer, or the same one read afresh, is a different screen
  api.nvim_create_autocmd({ "BufEnter", "BufWinEnter", "FileType", "Syntax", "OptionSet" }, {
    group = group,
    callback = function(ev)
      attach(ev.buf)
      if ev.event ~= "OptionSet" then hl.forget(ev.buf) end
      M.schedule(true)
    end,
  })
  -- new colours: every style number means something else now
  api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function()
      hl.reset()
      M.forgetColors()
      require("plato.sticky").forget()
      if emit then emit({ event = "theme", ui = hl.ui(), reset = true }) end
      M.schedule(true)
    end,
  })
  -- EVERY KEY, AS WELL. Most of what a key does fires an event above, but not
  -- all of it: `:nohlsearch` — which is what <Esc> is mapped to — clears the
  -- search highlight and tells nobody, and the matches stayed lit on screen
  -- until something else moved. on_key sees the key before it runs; the
  -- scheduled frame is built after, and is coalesced and diffed like any
  -- other, so a key that changed nothing costs one comparison.
  vim.on_key(function(key, typed)
    local k = (typed and typed ~= "") and typed or key
    if (k == "n" or k == "N" or k == "*" or k == "#") and api.nvim_get_mode().mode == "n" then
      M._searchJump = 3
    end
    M.schedule()
  end, api.nvim_create_namespace("plato.keys"))
  api.nvim_create_autocmd("CmdlineLeave", {
    group = group,
    callback = function()
      local t = vim.fn.getcmdtype()
      if (t == "/" or t == "?") and not vim.v.event.abort then M._searchJump = 3 end
    end,
  })
  attach(api.nvim_get_current_buf())
end

-- a new client knows nothing: forget what the last one was told, and tell it
-- every style and the UI colours before the first frame
function M.reset()
  sentWins = {}
  if emit then emit({ event = "theme", ui = hl.ui(), styles = hl.all(), reset = true }) end
end

return M
