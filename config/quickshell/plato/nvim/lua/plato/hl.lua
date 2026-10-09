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
-- the line-local highlighters' answers (lineLocal, below), per text
local lineCache = {}   -- buf → { [0] = the highlighter, [text] = runs }
local lineCount = {}
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

function M.forget(buf) synCache[buf] = nil; synCount[buf] = nil; lineCache[buf] = nil end

-- ── base: line-local Lua highlighters ──────────────────────────────────
-- Formats bat colours and nvim has no grammar for (or one too slow for a
-- big file): csv/tsv columns and logs. Each looks at one line alone — no
-- regex engine, no syncing — so it also colours a file too big for syntax
-- (large.lua turns that off; terminus hands bat anything past 4 MB, and the
-- two must agree). The colours are bat's under --theme=ansi, so the editor,
-- plato's previews and bat's say the same thing.

-- csv and tsv: a column at a time, bat's cycle of five (PlatoCol1-5,
-- theme.lua), a quoted field as a string (its "" escapes cyan), the
-- delimiters plain
local function columns(text, d)
  local runs, i, col, n = {}, 1, 0, #text
  while i <= n + 1 do
    local b0 = i - 1
    local j, quoted = i, text:sub(i, i) == '"'
    local esc = {}
    if quoted then
      j = i + 1
      while j <= n do
        local c = text:sub(j, j)
        if c == '"' then
          if text:sub(j + 1, j + 1) == '"' then esc[#esc + 1] = j; j = j + 2 else j = j + 1; break end
        else j = j + 1 end
      end
      -- what follows the closing quote, up to the delimiter, is the field's
      j = text:find(d, j, true) or n + 1
    else
      j = text:find(d, i, true) or n + 1
    end
    if j - 1 > b0 then
      local g = quoted and "PlatoColQuoted" or ("PlatoCol" .. (col % 5 + 1))
      -- a quoted field's "" (an escaped quote) in the escape's cyan, as bat's
      local from = b0
      for _, x in ipairs(esc) do
        if x - 1 > from then runs[#runs + 1] = { from, x - 1, g } end
        runs[#runs + 1] = { x - 1, x + 1, "PlatoColEscape" }
        from = x + 1
      end
      runs[#runs + 1] = { from, j - 1, g }
    end
    col = col + 1
    i = j + 1
  end
  return runs
end

-- a log, as bat's `log` syntax: dates and times, numbers (a word's own
-- digits are not one — v1, 10ms, 1e10), hex, an address's groups, a quoted
-- string (bat lets an unclosed one run on to the end of the file; this
-- stops at the line's end), key= with its key. Levels stay plain, as bat
-- leaves them.
local function isWord(c) return c ~= "" and c:match("[%w_]") ~= nil end
local function logRuns(s)
  local runs, n, i = {}, #s, 1
  local function put(a, b, g) runs[#runs + 1] = { a - 1, b, g } end
  while i <= n do
    local c = s:sub(i, i)
    local prev = i > 1 and s:sub(i - 1, i - 1) or ""
    local done = false
    -- a URL: plain, all of it (bat's too), so its ?x=1 is no key
    if isWord(c) and not isWord(prev) then
      local _, ue = s:find("^%a[%w+.-]*://[^%s\"'<>]*", i)
      if ue then i = ue + 1; done = true end
    end
    -- a quoted string
    -- (a double-quoted one's backslash escapes, \n \" \\, in the key's colour,
    -- as bat's; a single-quoted one has none)
    if (c == '"' or c == "'") and not isWord(prev) then
      local e, esc = i + 1, {}
      while e <= n do
        local ch = s:sub(e, e)
        if ch == "\\" and c == '"' and e < n then esc[#esc + 1] = e; e = e + 2
        elseif ch == c then break
        else e = e + 1 end
      end
      -- unclosed: to the line's end, as bat has it (bat runs on into the
      -- lines after; one line is as far as this goes)
      do
        local from = i
        for _, x in ipairs(esc) do
          if x > from then put(from, x - 1, "PlatoLogString") end
          put(x, x + 1, "PlatoLogKey")
          from = x + 2
        end
        put(from, math.min(e, n), "PlatoLogString")
        i = e + 1; done = true
      end
    end
    -- key=, the key's colour whatever it is made of (2358734848=true)
    if not done and isWord(c) and not isWord(prev) then
      local _, e = s:find("^[%w_]+", i)
      if s:sub(e + 1, e + 1) == "=" then
        put(i, e, "PlatoLogKey"); put(e + 1, e + 1, "PlatoLogSep"); i = e + 2; done = true
      end
    end
    if not done and not isWord(prev) then
      -- 2026-10-09, then T and a time
      local d1, d2 = s:find("^%d%d%d%d%-%d%d%-%d%d", i)
      if not d1 then d1, d2 = s:find("^%d%d%d%d/%d%d/%d%d", i) end
      local after = d1 and s:sub(d2 + 1, d2 + 1) or ""
      if d1 and (after == "T" or not isWord(after)) then
        put(d1, d2, "PlatoLogNumber")
        i = d2 + 1
        if s:sub(i, i) == "T" and s:find("^%d%d:%d%d:%d%d", i + 1) then put(i, i, "PlatoLogSep"); i = i + 1 end
        done = true
      end
    end
    if not done and (not isWord(prev) or s:sub(i - 1, i - 1) == "T") then
      -- 03:57:51: a time, whole
      local t1, t2 = s:find("^%d%d:%d%d:%d%d", i)
      -- with its milliseconds, unless a zone letter follows (.123Z stays
      -- plain); microseconds are a number of their own, as bat has them
      local f2 = t1 and select(2, s:find("^%.%d%d?%d?", t2 + 1))
      if f2 and not isWord(s:sub(f2 + 1, f2 + 1)) then t2 = f2 end
      if t1 and not s:sub(t2 + 1, t2 + 1):match("[%w_:]") then
        put(t1, t2, "PlatoLogNumber"); i = t2 + 1; done = true
      end
    end
    if not done and not isWord(prev) then
      -- 0xDEADBEEF: the 0x and its digits
      local h1, h2 = s:find("^0[xX]%x+", i)
      if h1 and not isWord(s:sub(h2 + 1, h2 + 1)) then
        put(h1, h1 + 1, "PlatoLogNumber"); put(h1 + 2, h2, "PlatoLogNumber"); i = h2 + 1; done = true
      end
    end
    if not done and not isWord(prev) then
      -- an address of hex groups and colons (a MAC, IPv6): each group
      local a1, a2 = s:find("^[%x:]+", i)
      if a1 and not isWord(s:sub(a2 + 1, a2 + 1)) then
        local tok = s:sub(a1, a2)
        local _, colons = tok:gsub(":", "")
        local short = true
        for g in tok:gmatch("%x+") do if #g > 4 then short = false end end
        if colons >= 2 and short and tok:find("%x") and not tok:find(":::") then
          local at = a1
          while at <= a2 do
            local _, ge = s:find("^%x+", at)
            if ge and ge <= a2 then put(at, ge, "PlatoLogNumber"); at = ge + 1 else at = at + 1 end
          end
          i = a2 + 1; done = true
        end
      end
    end
    if not done and c:match("%d") and not isWord(prev) then
      -- an IPv4 address: four numbers, the dots plain
      local p1, p2 = s:find("^%d+%.%d+%.%d+%.%d+", i)
      local octets = p1 ~= nil
      if p1 then
        for o in s:sub(p1, p2):gmatch("%d+") do if #o > 3 or tonumber(o) > 255 then octets = false end end
      end
      if octets and not isWord(s:sub(p2 + 1, p2 + 1)) then
        local at = p1
        while at <= p2 do
          local _, ge = s:find("^%d+", at)
          if ge then put(at, ge, "PlatoLogNumber"); at = ge + 2 else at = at + 1 end
        end
        i = p2 + 1; done = true
      end
    end
    if not done and c:match("%d") and not isWord(prev) then
      -- a number, with its decimal part (2.1.280 is 2.1, then 280)
      local _, j = s:find("^%d+", i)
      local f1, f2 = s:find("^%.%d+", j + 1)
      if f1 and not isWord(s:sub(f2 + 1, f2 + 1)) then
        put(i, f2, "PlatoLogNumber"); i = f2 + 1; done = true
      elseif not isWord(s:sub(j + 1, j + 1)) then
        put(i, j, "PlatoLogNumber"); i = j + 1; done = true
      end
    end
    if not done and isWord(c) then
      -- a word: key= takes the key's colour; otherwise skipped whole, so
      -- its digits are never a number
      local _, e = s:find("^[%w_]+", i)
      if s:sub(e + 1, e + 1) == "=" then
        put(i, e, "PlatoLogKey"); put(e + 1, e + 1, "PlatoLogSep"); i = e + 2
      else
        i = e + 1
      end
      done = true
    end
    if not done then i = i + 1 end
  end
  return runs
end

-- /etc/hosts, as bat's "Hosts File": the address, then its names, then a
-- comment (nvim calls the file `conf` and colours the comment only)
local function hostsRuns(s)
  local runs = {}
  local hash = s:find("#", 1, true)
  local body = hash and s:sub(1, hash - 1) or s
  local k = 0
  for a, w, e in body:gmatch("()(%S+)()") do
    runs[#runs + 1] = { a - 1, e - 1, k == 0 and "PlatoHostAddr" or "PlatoHostName" }
    k = k + 1
  end
  if hash then runs[#runs + 1] = { hash - 1, -1, "Comment" } end
  return runs
end

local function isLog(buf)
  local ft = vim.bo[buf].filetype
  if ft == "log" then return true end
  if ft ~= "" and ft ~= "text" then return false end
  local name = vim.api.nvim_buf_get_name(buf)
  return name:match("%.log$") ~= nil or name:match("%.log%.%d+$") ~= nil
    or name:match("^/var/log/") ~= nil
end

local function csv(t) return columns(t, ",") end
local function tsv(t) return columns(t, "\t") end

-- bat's line-local formats, and plato's for them; nil for any other
function M.lineLocal(buf, text)
  local ft = vim.bo[buf].filetype
  local f
  if ft == "csv" then f = csv
  elseif ft == "tsv" then f = tsv
  elseif isLog(buf) then f = logRuns
  elseif vim.api.nvim_buf_get_name(buf) == "/etc/hosts" then f = hostsRuns
  else return nil end
  local c = lineCache[buf]
  if not c or c[0] ~= f or (lineCount[buf] or 0) > 2000 then
    c = { [0] = f }; lineCache[buf] = c; lineCount[buf] = 0
  end
  local hit = c[text]
  if hit then return hit end
  hit = f(text)
  c[text] = hit
  lineCount[buf] = lineCount[buf] + 1
  return hit
end

-- the filetype for what nvim has none for (init.lua, before any file loads)
function M.filetypes()
  vim.filetype.add({
    extension = { log = "log" },
    pattern = { [".*%.log%.%d+"] = "log", ["/var/log/.*"] = "log" },
  })
end

-- `chars` is the layout's list of { b0, b1, ... } for the part of the line
-- that is on screen: only those characters are asked about.
function M.syntax(buf, lnum, text, chars)
  local own = M.lineLocal(buf, text)
  if own then return own end
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
