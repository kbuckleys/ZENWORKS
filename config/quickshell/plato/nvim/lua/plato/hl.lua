-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/
--
-- Highlighting: where each colour comes from, and how it reaches plato.
--
-- THREE LAYERS PER CELL, painted in this order and merged the way nvim
-- combines them:
--   base   the syntax group: treesitter's capture, or the regex engine's
--   deco   an extmark's highlight: a diagnostic's underline, mostly
--   over   what sits on top: search matches and the visual selection
-- A cell's style is the merge of its three groups, and every distinct
-- combination is registered once and given a number. Frames carry numbers;
-- the colours behind them are sent the first time a number is used.
--
-- WHY NOT JUST ASK NVIM. A grid UI would be sent every cell's final colour,
-- but a Lua UI cannot have a grid, and treesitter's colours in particular only
-- exist in the middle of nvim's own redraw — which a headless nvim never
-- does. So the captures are run here, over the visible lines only, the same
-- way the highlighter would run them.

local api = vim.api
local M = {}

-- ── the style registry ─────────────────────────────────────────────────
local resolved = {}   -- group name → its attributes, links followed
local ids = {}        -- "base\0deco\0over" → id
local defs = {}       -- id → merged attributes
local fresh = {}      -- ids made since the client was last told
local nextId = 1

local function hex(n) return n and string.format("#%06x", n) or nil end

-- A group's attributes, links followed. "@keyword.function.lua" is not a
-- group anyone defines; the highlighter falls back through "@keyword.function"
-- to "@keyword", and so does this.
-- HOW STRONGLY A HIGHLIGHT'S BACKGROUND IS DRAWN, for the ones that sit
-- over text rather than replacing it (see theme.lua): the client draws the
-- background at this opacity. Anything not named here is solid.
M.wash = {
  Visual = 0.32, MultiCursorVisual = 0.32,
  Search = 0.30, CurSearch = 0.50, IncSearch = 0.45, Substitute = 0.45,
}

function M.attrs(group)
  if not group then return nil end
  local a = resolved[group]
  if a then return a end
  local name = group
  local h = api.nvim_get_hl(0, { name = name, link = false })
  while next(h) == nil and name:find("%.") do
    name = name:gsub("%.[^.]*$", "")
    h = api.nvim_get_hl(0, { name = name, link = false })
  end
  a = {
    fg = hex(h.fg), bg = hex(h.bg), sp = hex(h.sp),
    b = h.bold or nil, i = h.italic or nil, s = h.strikethrough or nil,
    u = h.underline or nil,
    c = (h.undercurl or h.underdouble or h.underdotted or h.underdashed) or nil,
    -- a link (MultiCursorVisual → Visual) washes as what it links to
    a = h.bg and (M.wash[group] or M.wash[name]) or nil,
    -- the selection: drawn by the window as one rounded shape over all its
    -- rows (WindowView), not a strip per span
    v = (group == "Visual" or name == "Visual") or nil,
  }
  if h.bg and not a.a then
    local link = api.nvim_get_hl(0, { name = name, link = true }).link
    if link then a.a = M.wash[link] end
  end
  resolved[group] = a
  return a
end

local function merge(into, a)
  if not a then return end
  for k, v in pairs(a) do into[k] = v end
end

local byLook = {}      -- the merged attributes, serialised → id

-- The id for a cell painted with these three groups (any may be nil), or 0
-- when they add up to nothing — plain text in Normal's colour, which the
-- client needs no span to draw.
--
-- NUMBERED BY LOOK, NOT BY NAME. Under a selection, a keyword and a string
-- can come out the same (two groups linked to one colour): two names, one
-- look. Keyed by name they were two styles, and a line came out as a span
-- per syntax group instead of one.
function M.style(base, deco, over)
  local key = (base or "") .. "\0" .. (deco or "") .. "\0" .. (over or "")
  local id = ids[key]
  if id then return id end
  local s = {}
  merge(s, M.attrs(base))
  merge(s, M.attrs(deco))
  merge(s, M.attrs(over))
  if next(s) == nil then
    ids[key] = 0
    return 0
  end
  local look = {}
  for _, k in ipairs({ "fg", "bg", "sp", "b", "i", "s", "u", "c", "a", "v" }) do
    look[#look + 1] = tostring(s[k])
  end
  look = table.concat(look, "\1")
  id = byLook[look]
  if not id then
    id = nextId
    nextId = nextId + 1
    byLook[look] = id
    s.id = id
    defs[id] = s
    fresh[#fresh + 1] = s
  end
  ids[key] = id
  return id
end

-- the styles made since last asked, as a list for the next frame
function M.takeFresh()
  if #fresh == 0 then return nil end
  local out = fresh
  fresh = {}
  return out
end

-- a new client knows none of them
function M.all()
  fresh = {}
  local out = {}
  for _, s in pairs(defs) do out[#out + 1] = s end
  return out
end

-- the colours changed: every id means something else now
function M.reset()
  resolved, ids, defs, fresh, byLook, nextId = {}, {}, {}, {}, {}, 1
end

-- The UI's own colours — gutter, current line, folds — for QML to paint
-- things nvim would have painted around the text.
function M.ui()
  local function a(g) return M.attrs(g) or {} end
  return {
    normal = a("Normal").fg,
    cursorline = a("CursorLine").bg,
    linenr = a("LineNr").fg,
    cursorlinenr = a("CursorLineNr").fg,
    folded = a("Folded").fg,
    nontext = a("NonText").fg,
    visual = a("Visual").bg,
    visualAlpha = M.wash.Visual,
  }
end

-- ── base: treesitter ───────────────────────────────────────────────────
-- Every capture over lines [top, bot] (0-based, inclusive), per line, in the
-- order the highlighter would apply them: by priority, then as found — so a
-- later, more specific capture wins, and an injected language (a child tree)
-- paints over its host.
--   return  paints   lnum → { {sc, ec, group}, ... }   ec = -1: to the end
--           conceal  lnum → { {sc, ec, char}, ... }    char "" = hide
--           hidden   lnum → true, for conceal_lines (a whole line hidden)
function M.treesitter(buf, top, bot)
  local hl = vim.treesitter.highlighter.active[buf]
  if not hl then return nil end
  local out, conceal, hidden = {}, {}, {}
  local seq = 0
  local ok = pcall(function()
    hl.tree:parse({ top, bot + 1 })
    hl.tree:for_each_tree(function(tstree, ltree)
      local lang = ltree:lang()
      local q = vim.treesitter.query.get(lang, "highlights")
      if not q then return end
      for id, node, meta in q:iter_captures(tstree:root(), buf, top, bot + 1) do
        local name = q.captures[id]
        local m = meta[id] or {}
        local cc = m.conceal or meta.conceal
        local clines = m.conceal_lines or meta.conceal_lines
        if cc ~= nil or clines ~= nil then
          local sr, sc, er, ec = node:range()
          if clines ~= nil then
            for l = math.max(sr, top), math.min(er, bot) do hidden[l] = true end
          elseif sr == er then
            conceal[sr] = conceal[sr] or {}
            table.insert(conceal[sr], { sc, ec, cc })
          end
        end
        if name ~= "spell" and name ~= "nospell" and name:sub(1, 1) ~= "_"
            and name ~= "conceal" then
          local sr, sc, er, ec = node:range()
          local prio = tonumber(meta.priority or (meta[id] and meta[id].priority)) or 100
          local group = "@" .. name .. "." .. lang
          seq = seq + 1
          for l = math.max(sr, top), math.min(er, bot) do
            local list = out[l]
            if not list then list = {}; out[l] = list end
            list[#list + 1] = {
              l == sr and sc or 0,
              l == er and ec or -1,
              group, prio, seq,
            }
          end
        end
      end
    end)
  end)
  if not ok then return nil end
  for _, list in pairs(out) do
    table.sort(list, function(x, y)
      if x[4] ~= y[4] then return x[4] < y[4] end
      return x[5] < y[5]
    end)
  end
  return out, conceal, hidden
end

-- ── base: the regex engine ─────────────────────────────────────────────
-- For every language treesitter has no parser for — which on this machine is
-- most of them. synID is the only question the regex engine answers, and it
-- answers per character, so it is asked once per character on screen and the
-- answer kept: a line's colours are reused until an edit at or above it
-- (syntax state flows downward, so an edit can change every line below).
local synCache = {}   -- buf → lnum(0-based) → { text, runs }
local synCount = {}   -- buf → how many lines synCache holds for it
local synName = {}    -- synID → its translated group's name
-- KEPT SMALL. Every line ever scrolled past was kept, and an edit walks the
-- whole cache to drop what is below it: a long file read top to bottom made
-- every keystroke a walk of thousands. Past this many, a buffer's cache is
-- started again — what is on screen is asked for again in one frame.
local SYN_MAX = 1500

function M.invalidateFrom(buf, first)
  local c = synCache[buf]
  if not c then return end
  local n = synCount[buf] or 0
  for l in pairs(c) do
    if l >= first then c[l] = nil; n = n - 1 end
  end
  synCount[buf] = n
end

function M.forget(buf) synCache[buf] = nil; synCount[buf] = nil end

-- `chars` is the layout's list of { b0, b1, ... } for the part of the line
-- that is on screen: only those characters are asked about.
function M.syntax(buf, lnum, text, chars)
  if vim.bo[buf].syntax == "" then return nil end
  local c = synCache[buf]
  if not c or (synCount[buf] or 0) > SYN_MAX then
    c = {}; synCache[buf] = c; synCount[buf] = 0
  end
  local hit = c[lnum]
  local first = chars[1] and chars[1][1] or 0
  local last = chars[#chars] and chars[#chars][1] or 0
  if hit and hit.text == text and hit.first <= first and hit.last >= last then
    return hit.runs
  end
  local runs = {}
  local cur, from = nil, 0
  for _, ch in ipairs(chars) do
    local id = vim.fn.synID(lnum + 1, ch[1] + 1, 1)
    local name = synName[id]
    if not name then
      name = id == 0 and false or vim.fn.synIDattr(vim.fn.synIDtrans(id), "name")
      if name == "" then name = false end
      synName[id] = name
    end
    if name ~= cur then
      if cur then runs[#runs + 1] = { from, ch[1], cur } end
      cur, from = name, ch[1]
    end
  end
  if cur then runs[#runs + 1] = { from, -1, cur } end
  if not hit then synCount[buf] = (synCount[buf] or 0) + 1 end
  c[lnum] = { text = text, runs = runs, first = first, last = last }
  return runs
end

-- ── one line, as a group per byte ──────────────────────────────────────
-- What the ANSI renderer, sticky scroll and the minimap all want: the
-- highlight group behind each byte of line `l` (0-based) — from `paints`
-- (a treesitter() result covering the line) when there is one, the regex
-- engine otherwise. maxSyntax: lines longer than this skip the regex engine
-- (it asks per character), and come out plain.
--   → { [byte0] = group, … }
function M.chars(s)
  local chars, i = {}, 1
  while i <= #s do
    local b = s:byte(i)
    local len = b < 0x80 and 1 or b < 0xE0 and 2 or b < 0xF0 and 3 or 4
    chars[#chars + 1] = { i - 1, i - 1 + len }
    i = i + len
  end
  return chars
end

function M.byteGroups(buf, l, s, paints, maxSyntax)
  local group = {}
  local function paint(b0, b1, g)
    local e = (b1 == -1) and #s or math.min(b1, #s)
    for b = b0, e - 1 do group[b] = g end
  end
  if paints then
    for _, p in ipairs(paints[l] or {}) do paint(p[1], p[2], p[3]) end
  elseif not maxSyntax or #s < maxSyntax then
    for _, r in ipairs(M.syntax(buf, l, s, M.chars(s)) or {}) do paint(r[1], r[2], r[3]) end
  end
  return group
end

return M
