-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/
--
-- Markdown, rendered in place: the file stays the file, but what marks it up
-- is drawn as what it means. "## Title" is a heading in its own colour on a
-- band, **bold** is bold with no stars, a table is ruled and its columns line
-- up, a code block sits on a panel, "- [ ]" is a box to tick.
--
-- NOTHING IS ADDED TO THE BUFFER. What this works out is the same kind of
-- answer view.lua already draws for a hover's markdown: bytes to conceal (or
-- to show as something else), colours to paint, and per line a block it
-- belongs to, for EditorRow to draw under the text.
--   lines[l] = { cc = { {b0, b1, shown}, ... },   shown "" hides them
--                paint = { {b0, b1, group}, ... }, in order, later wins
--                blk = { k = "h", n = level } | { k = "c", e = "t"|"b"|nil, x,
--                        lang } | { k = "hr" },
--                q = { b = { cells of its bars }, k = callout kind, e },
--                tb = { x, w, c = { cells of its column rules }, h = header row,
--                       d = the --- row, u = ruled under, z = an even body row, e },
--                hide = true: not a row at all (a table's --- row, ruled instead
--                       under its header) }
-- e is the block's edges on this line: "t" its first, "b" its last.
--
-- DRAWN, OR WRITTEN. The editor draws a quote's bars, a table's frame and a
-- code block's language itself (EditorRow), so here they are only hidden.
-- A preview has nothing but text and colour (render.lua): compute(…, true)
-- writes them as characters instead — ▎ for a bar, │ for a table's sides,
-- the language after a code glyph.
-- `shown` may be several cells wide: a table's padding rides on its pipes.
--
-- THE CURSOR'S LINE IS THE FILE AS WRITTEN (view.lua), the way a live
-- preview works in a notes app: what you are editing shows every star and
-- pipe, so the cursor is never on a character you cannot see.
--
-- Per buffer, on or off (Space v; b:plato_md_raw), and per kind of thing in
-- the settings sheet (g:plato_md, from core/Settings.qml).

local api = vim.api
local M = {}
-- this compute() writes what the editor would draw (see above)
local G = false

-- what the settings sheet sends; every kind on until told otherwise
local function want(kind)
  local o = vim.g.plato_md
  if type(o) ~= "table" then return true end
  return o[kind] ~= false
end

-- this buffer is drawn rendered
function M.active(buf)
  if vim.bo[buf].filetype ~= "markdown" then return false end
  if not want("render") then return false end
  if vim.b[buf].plato_md_raw then return false end
  return vim.b[buf].plato_large ~= true
end

-- the cursor's line shown as written (the settings' "Cursor's line as written")
function M.rawLine() return want("rawLine") end

function M.toggle()
  local buf = api.nvim_get_current_buf()
  if vim.bo[buf].filetype ~= "markdown" then
    vim.notify("Not a markdown file", vim.log.levels.INFO)
    return
  end
  vim.b[buf].plato_md_raw = not vim.b[buf].plato_md_raw
  M.forget(buf)
  require("plato.view").schedule(true)
end

-- "- [ ]" ⇄ "- [x]" on the cursor's line (or makes a plain item a task)
function M.toggleTask()
  local l = api.nvim_win_get_cursor(0)[1]
  local s = api.nvim_get_current_line()
  local new
  if s:find("^%s*[-*+] %[ %]") or s:find("^%s*%d+[.)] %[ %]") then
    new = s:gsub("%[ %]", "[x]", 1)
  elseif s:find("^%s*[-*+] %[[xX]%]") or s:find("^%s*%d+[.)] %[[xX]%]") then
    new = s:gsub("%[[xX]%]", "[ ]", 1)
  elseif s:find("^%s*[-*+] ") then
    new = s:gsub("^(%s*[-*+] )", "%1[ ] ", 1)
  else
    new = s:gsub("^(%s*)", "%1- [ ] ", 1)
  end
  api.nvim_buf_set_lines(0, l - 1, l, false, { new })
end

-- ── what things look like ──────────────────────────────────────────────
-- nf-md-format_header_1 … 6
local headIcon = { "\u{F026B}", "\u{F026C}", "\u{F026D}", "\u{F026E}", "\u{F026F}", "\u{F0270}" }
local bullets = { "\u{2022}", "\u{25E6}", "\u{25AA}", "\u{25AB}" }
local boxOpen, boxDone = "\u{F0131}", "\u{F0C52}"
local imageIcon = "\u{F02E9}"
local codeIcon = "\u{F0169}"
-- GitHub's callouts: > [!NOTE] and the rest
local callouts = {
  note = { "\u{F02FD}", "Note", "PlatoMdNote" },
  tip = { "\u{F0335}", "Tip", "PlatoMdTip" },
  important = { "\u{F017E}", "Important", "PlatoMdImportant" },
  warning = { "\u{F0026}", "Warning", "PlatoMdWarning" },
  caution = { "\u{F0CE6}", "Caution", "PlatoMdCaution" },
}

local function width(s)
  if not s:find("[\128-\255]") then return #s end
  return vim.fn.strdisplaywidth(s)
end

-- ── the work ───────────────────────────────────────────────────────────
local cache = {}   -- buf → { key, lines }
function M.forget(buf) cache[buf] = nil end

local function line(out, l)
  local e = out[l]
  if not e then e = { cc = {}, paint = {} }; out[l] = e end
  return e
end
local function hide(out, l, b0, b1, shown) table.insert(line(out, l).cc, { b0, b1, shown or "" }) end
local function paint(out, l, b0, b1, g) table.insert(line(out, l).paint, { b0, b1, g }) end

-- how wide bytes [b0, b1) of `s` come out once this line's conceals are applied
local function shownWidth(s, b0, b1, cc)
  local w = width(s:sub(b0 + 1, b1))
  for _, c in ipairs(cc or {}) do
    local a, z = math.max(c[1], b0), math.min(c[2], b1)
    if a < z then w = w - width(s:sub(a + 1, z)) + (c[1] >= b0 and width(c[3]) or 0) end
  end
  return w
end

local function listDepth(node)
  local d, p = 0, node:parent()
  while p do
    if p:type() == "list" then d = d + 1 end
    p = p:parent()
  end
  return d
end

-- every line of a block quote, [sr, er] the whole of it (a callout is known
-- by its first line): its ">"s as bars, and a callout's head. Only lines in
-- [top, bot] are marked.
local function quote(out, buf, sr, er, top, bot)
  local style, kind = "PlatoMdQuote", nil
  local lines = api.nvim_buf_get_lines(buf, sr, er + 1, false)
  do
    local head = (lines[1] or ""):match("^%s*>%s?%[!(%a+)%]")
    if head and callouts[head:lower()] then kind = head:lower(); style = callouts[kind][3] end
  end
  for l = math.max(sr, top), math.min(er, bot) do
    local s = lines[l - sr + 1] or ""
    local i = 1
    local bars = {}
    while true do
      local a, z = s:find("^%s*>", i)
      if not a then break end
      -- a quote inside a callout is a plain one
      local g = #bars == 0 and style or "PlatoMdQuote"
      hide(out, l, z - 1, z, G and "\u{258E}" or " ")
      paint(out, l, z - 1, z, g)
      bars[#bars + 1] = z - 1
      i = z + 1
      if s:sub(i, i) == " " then i = i + 1 end
    end
    if #bars > 0 then
      paint(out, l, i - 1, -1, kind and "PlatoMdCalloutText" or "PlatoMdQuoteText")
    end
    if l == sr and kind and #bars > 0 then
      local c = callouts[kind]
      local n = #s:sub(i):match("^%[!%a+%]")
      hide(out, l, i - 1, i - 1 + n, c[1] .. " " .. c[2])
      paint(out, l, i - 1, -1, style)
    end
    if #bars > 0 then
      line(out, l).q = { b = bars, k = kind,
        e = (l == sr and "t" or "") .. (l == er and "b" or "") }
    end
  end
end

local function table_(out, buf, node)
  -- every row: the byte columns of its pipes, its line's text
  local rows = {}
  for row in node:iter_children() do
    local t = row:type()
    if t == "pipe_table_header" or t == "pipe_table_row" or t == "pipe_table_delimiter_row" then
      local l = row:range()
      local s = api.nvim_buf_get_lines(buf, l, l + 1, false)[1] or ""
      local pipes = {}
      for c in row:iter_children() do
        if c:type() == "|" then
          local _, sc = c:range()
          pipes[#pipes + 1] = sc
        end
      end
      local align = {}
      if t == "pipe_table_delimiter_row" then
        for c in row:iter_children() do
          if c:type() == "pipe_table_delimiter_cell" then
            local l1, r1 = false, false
            for a in c:iter_children() do
              if a:type() == "pipe_table_align_left" then l1 = true end
              if a:type() == "pipe_table_align_right" then r1 = true end
            end
            align[#align + 1] = (l1 and r1) and "c" or r1 and "r" or "l"
          end
        end
      end
      rows[#rows + 1] = { l = l, s = s, pipes = pipes, kind = t, align = align }
    end
  end
  -- only a table every row of which opens and closes with a pipe is lined
  -- up: GitHub's optional outer pipes would leave nothing to pad on
  local delim
  for _, r in ipairs(rows) do
    local lead = r.s:match("^%s*()")
    if #r.pipes < 2 or r.pipes[1] ~= lead - 1 or not r.s:match("|%s*$") then return end
    if r.kind == "pipe_table_delimiter_row" then delim = r end
  end
  if not delim then return end
  local cols = #delim.pipes - 1
  local x0 = rows[1].pipes[1]
  local W = {}
  for j = 1, cols do W[j] = 1 end
  for _, r in ipairs(rows) do
    if r.kind ~= "pipe_table_delimiter_row" then
      local cc = out[r.l] and out[r.l].cc
      r.w = {}
      for j = 1, math.min(cols, #r.pipes - 1) do
        r.w[j] = shownWidth(r.s, r.pipes[j] + 1, r.pipes[j + 1], cc)
        W[j] = math.max(W[j], r.w[j])
      end
    end
  end
  -- the frame: the table's cells, from its first pipe to past its last
  local wide = 1
  local rules = {}
  for j = 1, cols do
    wide = wide + W[j] + 1
    if j < cols then rules[#rules + 1] = x0 + wide - 1 end
  end
  local body = 0
  for ri, r in ipairs(rows) do
    local tb = { x = x0, w = wide, c = rules,
      e = (ri == 1 and "t" or "") .. (ri == #rows and "b" or "") }
    if r.kind == "pipe_table_header" then tb.h = true; tb.u = not G end
    if r.kind == "pipe_table_delimiter_row" then
      tb.d = true
      if not G then line(out, r.l).hide = true end
    end
    if r.kind == "pipe_table_row" then
      body = body + 1
      tb.z = body % 2 == 0
    end
    line(out, r.l).tb = tb
  end
  for _, r in ipairs(rows) do
    if r.kind == "pipe_table_delimiter_row" then
      local parts = { "\u{251C}" }
      for j = 1, cols do
        parts[#parts + 1] = string.rep("\u{2500}", W[j])
        parts[#parts + 1] = j == cols and "\u{2524}" or "\u{253C}"
      end
      local a = r.pipes[1]
      -- the editor rules it itself: a line across, through the columns'
      hide(out, r.l, a, #r.s, G and table.concat(parts) or "")
      paint(out, r.l, a, #r.s, "PlatoMdTable")
    else
      if r.kind == "pipe_table_header" then paint(out, r.l, r.pipes[1], #r.s, "PlatoMdTableHead") end
      local n = math.min(cols, #r.pipes - 1)
      for k = 1, #r.pipes do
        -- this pipe closes column k-1 and opens column k: the one's padding
        -- after, the other's before, as each is aligned
        local before, after = "", ""
        local j = k - 1
        if j >= 1 and j <= n then
          local pad = W[j] - r.w[j]
          local al = delim.align[j]
          local right = al == "r" and 0 or al == "c" and math.floor(pad / 2) or pad
          before = string.rep(" ", right)
        end
        if k <= n then
          local pad = W[k] - r.w[k]
          local al = delim.align[k]
          after = string.rep(" ", al == "r" and pad or al == "c" and pad - math.floor(pad / 2) or 0)
        end
        local p = r.pipes[k]
        -- the frame and the column rules are the editor's to draw
        hide(out, r.l, p, p + 1, before .. (G and "\u{2502}" or " ") .. after)
        paint(out, r.l, p, p + 1, "PlatoMdTable")
      end
    end
  end
end

-- the block structure: headings, lists, quotes, code, tables, rules
local function blocks(out, buf, root, top, bot)
  local function visit(node)
    local sr, sc, er, ec = node:range()
    if er < top or sr > bot then return end
    local t = node:type()
    if t == "atx_heading" and want("headings") then
      local mk = node:child(0)
      local lv = tonumber(mk and mk:type():match("^atx_h(%d)_marker")) or 1
      local _, m0, _, m1 = mk:range()
      local s = api.nvim_buf_get_lines(buf, sr, sr + 1, false)[1] or ""
      hide(out, sr, m0, m1, headIcon[lv])
      paint(out, sr, 0, #s, "PlatoMdH" .. lv)
      line(out, sr).blk = { k = "h", n = lv }
      return
    elseif t == "setext_heading" and want("headings") then
      local under = node:child(node:child_count() - 1)
      local lv = under and under:type():find("h2") and 2 or 1
      local ul = under and (under:range()) or er
      for l = sr, ul - 1 do
        paint(out, l, 0, -1, "PlatoMdH" .. lv)
        line(out, l).blk = { k = "h", n = lv }
      end
      if under then
        local s = api.nvim_buf_get_lines(buf, ul, ul + 1, false)[1] or ""
        hide(out, ul, 0, #s, "")
        line(out, ul).blk = { k = "hr" }
      end
      return
    elseif t == "thematic_break" and want("rules") then
      local s = api.nvim_buf_get_lines(buf, sr, sr + 1, false)[1] or ""
      hide(out, sr, 0, #s, "")
      line(out, sr).blk = { k = "hr" }
      return
    elseif (t == "list_marker_minus" or t == "list_marker_star" or t == "list_marker_plus")
        and want("lists") then
      local nxt = node:next_named_sibling()
      local task = nxt and nxt:type():find("^task_list_marker") ~= nil
      if task then
        -- the box stands in for the bullet
        hide(out, sr, sc, ec, "")
      else
        local d = (listDepth(node) - 1) % #bullets + 1
        hide(out, sr, sc, sc + 1, bullets[d])
        paint(out, sr, sc, sc + 1, "PlatoMdBullet" .. d)
      end
      return
    elseif (t == "list_marker_dot" or t == "list_marker_parenthesis") and want("lists") then
      paint(out, sr, sc, ec, "PlatoMdBullet" .. ((listDepth(node) - 1) % #bullets + 1))
      return
    elseif t == "task_list_marker_unchecked" and want("lists") then
      hide(out, sr, sc, ec, boxOpen)
      paint(out, sr, sc, ec, "PlatoMdTodo")
      return
    elseif t == "task_list_marker_checked" and want("lists") then
      hide(out, sr, sc, ec, boxDone)
      paint(out, sr, sc, ec, "PlatoMdCheck")
      -- what is done steps back
      local para = node:next_named_sibling()
      if para then
        local pr, pc, per = para:range()
        for l = pr, math.min(per, pr) do paint(out, l, pc, -1, "PlatoMdDone") end
      end
      return
    elseif t == "block_quote" and want("quotes") then
      -- the quote's own lines; its children (lists, code) still get theirs
      local last = ec == 0 and er - 1 or er
      quote(out, buf, sr, last, top, bot)
    elseif t == "fenced_code_block" and want("code") then
      local last = ec == 0 and er - 1 or er
      local x = sc
      for l = math.max(sr, top), math.min(last, bot) do
        line(out, l).blk = { k = "c", x = x, e = (l == sr and "t") or (l == last and "b") or nil }
      end
      if sr == last then line(out, sr).blk.e = "tb" end
      for c in node:iter_children() do
        local ct = c:type()
        local cr, cs, _, ce = c:range()
        if ct == "fenced_code_block_delimiter" then
          hide(out, cr, cs, ce, (G and cr == sr) and codeIcon .. " " or "")
          paint(out, cr, cs, ce, "PlatoMdFence")
        elseif ct == "info_string" then
          paint(out, cr, cs, ce, "PlatoMdFence")
          -- the editor labels the panel with it, in its corner
          if not G then
            local lang = vim.treesitter.get_node_text(c, buf):match("^%S+")
            if out[cr] and out[cr].blk then out[cr].blk.lang = lang end
            hide(out, cr, cs, ce, "")
          end
        end
      end
      return
    elseif t == "indented_code_block" and want("code") then
      local last = ec == 0 and er - 1 or er
      for l = math.max(sr, top), math.min(last, bot) do
        line(out, l).blk = { k = "c", x = 0,
          e = (sr == last and "tb") or (l == sr and "t") or (l == last and "b") or nil }
      end
      return
    elseif t == "pipe_table" and want("tables") then
      -- after the inline pass has run over its cells (widths need it)
      out._tables = out._tables or {}
      table.insert(out._tables, node)
      return
    elseif (t == "minus_metadata" or t == "plus_metadata") and want("code") then
      -- front matter: a panel of its own, its --- fences hidden
      local last = ec == 0 and er - 1 or er
      for l = math.max(sr, top), math.min(last, bot) do
        paint(out, l, 0, -1, "PlatoMdFence")
        line(out, l).blk = { k = "c", x = 0,
          e = (l == sr and "t" or "") .. (l == last and "b" or ""),
          lang = l == sr and "front matter" or nil }
        if l == sr or l == last then
          local s = api.nvim_buf_get_lines(buf, l, l + 1, false)[1] or ""
          hide(out, l, 0, #s, (G and l == sr) and codeIcon .. " front matter" or "")
        end
      end
      return
    elseif t == "html_block" then
      -- a comment steps back, as one does in code
      local s = api.nvim_buf_get_lines(buf, sr, sr + 1, false)[1] or ""
      if s:find("^%s*<!%-%-") then
        local last = ec == 0 and er - 1 or er
        for l = math.max(sr, top), math.min(last, bot) do paint(out, l, 0, -1, "PlatoMdComment") end
      end
      return
    end
    for c in node:iter_children() do
      if c:named() then visit(c) end
    end
  end
  visit(root)
end

-- inside a paragraph: emphasis, code, links, escapes
local function inline(out, buf, root, top, bot)
  local function visit(node)
    local sr, sc, er, ec = node:range()
    if er < top or sr > bot then return end
    local t = node:type()
    if t == "emphasis_delimiter" or t == "code_span_delimiter" then
      hide(out, sr, sc, ec, "")
    elseif t == "code_span" then
      paint(out, sr, sc, sr == er and ec or -1, "PlatoMdCode")
    elseif (t == "strong_emphasis" or t == "emphasis")
        and not (out[sr] and out[sr].blk and out[sr].blk.k == "h") then
      -- (a heading is bold in its own colour already: a cell has one group,
      -- and plain bold would take the heading's colour away)
      paint(out, sr, sc, sr == er and ec or -1, t == "emphasis" and "PlatoMdItalic" or "PlatoMdBold")
    elseif t == "strikethrough" then
      paint(out, sr, sc, sr == er and ec or -1, "PlatoMdStrike")
    elseif t == "inline_link" or t == "full_reference_link" or t == "collapsed_reference_link"
        or t == "shortcut_link" or t == "image" then
      local text
      for c in node:iter_children() do
        if c:type() == "link_text" or c:type() == "image_description" then text = c end
      end
      -- "[!NOTE]" opening a quote is a callout's, not a link (quote above)
      local callout = t == "shortcut_link" and text
        and vim.treesitter.get_node_text(text, buf):sub(1, 1) == "!"
      if text and sr == er and not callout then
        local _, ts0, _, ts1 = text:range()
        if t == "image" then
          hide(out, sr, sc, ts0, imageIcon .. " ")
        else
          hide(out, sr, sc, ts0, "")
        end
        hide(out, sr, ts1, ec, "")
        paint(out, sr, sc, ec, "PlatoMdLink")
      end
      -- what is inside the text (code, emphasis) still counts
    elseif t == "uri_autolink" and sr == er then
      hide(out, sr, sc, sc + 1, "")
      hide(out, sr, ec - 1, ec, "")
      paint(out, sr, sc, ec, "PlatoMdLink")
      return
    elseif t == "backslash_escape" then
      hide(out, sr, sc, sc + 1, "")
      return
    end
    for c in node:iter_children() do visit(c) end
  end
  visit(root)
end

-- lines [top, bot], 0-based inclusive → lines (see the top of the file)
function M.compute(buf, top, bot, glyphs)
  G = glyphs == true
  local key = table.concat({ api.nvim_buf_get_changedtick(buf), top, bot, tostring(G),
    vim.inspect(vim.g.plato_md) }, ":")
  local c = cache[buf]
  if c and c.key == key then return c.lines end
  local out = {}
  local ok = pcall(function()
    local parser = vim.treesitter.get_parser(buf, "markdown", { error = false })
    if not parser then return end
    parser:parse({ top, bot + 1 })
    local inl = {}
    parser:for_each_tree(function(tstree, ltree)
      local lang = ltree:lang()
      if lang == "markdown" then
        blocks(out, buf, tstree:root(), top, bot)
      elseif lang == "markdown_inline" and want("inline") then
        inl[#inl + 1] = tstree:root()
      end
    end)
    -- a table's columns are as wide as its widest cell, on screen or not:
    -- the inline pass reaches every row of every table in view, or the
    -- columns would shift as it scrolled in
    local lo, hi = top, bot
    for _, t in ipairs(out._tables or {}) do
      local sr, _, er = t:range()
      lo, hi = math.min(lo, sr), math.max(hi, er)
    end
    if lo < top or hi > bot then
      parser:parse({ lo, hi + 1 })
      inl = {}
      parser:for_each_tree(function(tstree, ltree)
        if ltree:lang() == "markdown_inline" and want("inline") then inl[#inl + 1] = tstree:root() end
      end)
    end
    for _, r in ipairs(inl) do inline(out, buf, r, lo, hi) end
    for _, t in ipairs(out._tables or {}) do table_(out, buf, t) end
  end)
  out._tables = nil
  if not ok then out = {} end
  for _, e in pairs(out) do
    -- by start, and the longer of two that start together first: it wins
    table.sort(e.cc, function(a, b)
      if a[1] ~= b[1] then return a[1] < b[1] end
      return a[2] > b[2]
    end)
  end
  cache[buf] = { key = key, lines = out }
  return out
end

return M
