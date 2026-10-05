-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/
--
-- A file, coloured as plato colours it, printed as ANSI for anything that
-- reads ANSI: terminus' quick look, in place of bat.
--
--   NVIM_APPNAME=quickshell/plato/nvim nvim --headless -i NONE -n --clean \
--     -c "luafile render.lua" -- FILE
--   PLATO_RENDER_LINES   how many lines (90, as terminus asked bat for)
--   PLATO_RENDER_FROM    the first of them (1): plato's grep previews the
--                        middle of a file, around the match
--
-- ONE HIGHLIGHTER, NOT TWO. bat has its own grammars and its own idea of
-- what a keyword is, so a file previewed in terminus and opened in plato came
-- out in two different sets of colours. This is plato's own engine — its
-- theme (theme.lua, from the zenon palette), treesitter where plato has a
-- parser and its queries, the regex engine where it has not (hl.lua) — so
-- the two agree because they are the same code.
--
-- 24-bit colour (38;2;r;g;b), which terminus' ansiToRich already reads.

local here = vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))
vim.opt.runtimepath:prepend(here)
-- nvim-treesitter's queries, where plato's plugins are (see plugins.lua)
local nts = vim.fn.stdpath("data") .. "/site/pack/core/opt/nvim-treesitter/runtime"
if vim.uv.fs_stat(nts) then vim.opt.runtimepath:append(nts) end

local api = vim.api
local out = {}
local function emit(s) out[#out + 1] = s end

local ok = pcall(function()
  require("plato.theme").apply()
  local hl = require("plato.hl")
  local buf = api.nvim_get_current_buf()
  local first = math.max(0, (tonumber(vim.env.PLATO_RENDER_FROM) or 1) - 1)
  local n = math.min(api.nvim_buf_line_count(buf),
    first + (tonumber(vim.env.PLATO_RENDER_LINES) or 90))
  local ts = vim.bo[buf].tabstop

  -- A LONG MARKDOWN FILE IS CUT TO WHAT IS SHOWN. nvim parses every one of
  -- its paragraphs' inline trees to colour any of them (300 ms for 8000
  -- lines); the lines past the preview change nothing in it, and a few
  -- hundred before it are context enough for a fence or a list
  if vim.bo[buf].filetype == "markdown" and api.nvim_buf_line_count(buf) > n + 50 then
    api.nvim_buf_set_lines(buf, n + 50, -1, false, {})
    local cut = math.max(0, first - 300)
    if cut > 0 then
      api.nvim_buf_set_lines(buf, 0, cut, false, {})
      first, n = first - cut, n - cut
    end
  end

  -- treesitter if plato would use it for this file; the regex engine if not
  local lang = vim.treesitter.language.get_lang(vim.bo[buf].filetype)
  if lang then pcall(vim.treesitter.start, buf, lang) end
  local paints = hl.treesitter(buf, first, n - 1)

  -- MARKDOWN AS PLATO DRAWS IT (markdown.lua): the same headings, tables,
  -- bullets and boxes as the editor shows, by plato's own settings — read
  -- from its settings file, since nobody here was sent them
  local md = require("plato.markdown")
  if vim.bo[buf].filetype == "markdown" then
    local files = vim.fn.glob(vim.fn.expand("~/.local/state/quickshell/by-shell/*/plato.json"), false, true)
    table.sort(files, function(x, y)
      return (vim.uv.fs_stat(x) or {}).mtime.sec > (vim.uv.fs_stat(y) or {}).mtime.sec
    end)
    local okj, j = pcall(function() return vim.json.decode(table.concat(vim.fn.readfile(files[1]), "\n")) end)
    if okj and type(j) == "table" then
      vim.g.plato_md = {
        render = j.mdRender, headings = j.mdHeadings, inline = j.mdInline, lists = j.mdLists,
        code = j.mdCode, tables = j.mdTables, quotes = j.mdQuotes, rules = j.mdRules,
      }
    end
  end
  local mdLines = md.active(buf) and md.compute(buf, first, n - 1, true) or {}
  local merge = require("plato.view").mergeConceal

  local function attrs(g) return g and hl.attrs(g) or nil end
  local function rgb(h, lead)
    return lead .. ";2;" .. tonumber(h:sub(2, 3), 16) .. ";" .. tonumber(h:sub(4, 5), 16)
      .. ";" .. tonumber(h:sub(6, 7), 16)
  end
  local function sgr(g, panel)
    local a = attrs(g) or {}
    local code = "\27[0"
    if a.fg then code = code .. ";" .. rgb(a.fg, "38") end
    if a.bg and not a.a then code = code .. ";" .. rgb(a.bg, "48")
    elseif panel then code = code .. ";" .. rgb(panel, "48") end
    if a.b then code = code .. ";1" end
    if a.i then code = code .. ";3" end
    if a.u then code = code .. ";4" end
    if a.s then code = code .. ";9" end
    return code .. "m"
  end

  -- every line as runs of { text, group } and how many cells it takes
  local lines = api.nvim_buf_get_lines(buf, 0, n, false)
  local laid = {}
  for l = first, n - 1 do
    local s = lines[l + 1] or ""
    -- per byte, the group that colours it
    local group = hl.byteGroups(buf, l, s, paints)
    local ml = mdLines[l]
    if ml then
      for _, p in ipairs(ml.paint) do
        for b = p[1], (p[2] == -1 and #s or math.min(p[2], #s)) - 1 do group[b] = p[3] end
      end
    end
    local cc = ml and #ml.cc > 0 and merge(vim.deepcopy(ml.cc)) or {}
    local runs, col, ci = {}, 0, 1
    local function put(t, g, w)
      local last = runs[#runs]
      if last and last[2] == g then last[1] = last[1] .. t else runs[#runs + 1] = { t, g } end
      col = col + w
    end
    local i = 1
    while i <= #s do
      while cc[ci] and cc[ci][2] <= i - 1 do ci = ci + 1 end
      local c = cc[ci]
      if c and c[1] <= i - 1 then
        if c[3] and c[3] ~= "" then put(c[3], group[i - 1], vim.fn.strdisplaywidth(c[3])) end
        i = math.min(c[2], #s) + 1
        ci = ci + 1
      else
        local b = s:byte(i)
        local len = b < 0x80 and 1 or b < 0xE0 and 2 or b < 0xF0 and 3 or 4
        if b == 9 then
          local w = ts - (col % ts)
          put(string.rep(" ", w), group[i - 1], w)
        else
          local ch = s:sub(i, i + len - 1)
          put(ch, group[i - 1], len == 1 and 1 or vim.fn.strdisplaywidth(ch))
        end
        i = i + len
      end
    end
    laid[#laid + 1] = { runs = runs, w = col, blk = ml and ml.blk, tb = ml and ml.tb }
  end

  -- a code block is one panel: every line of it as wide as its widest
  local panel = require("plato.palette").lblack
  local k = 1
  while k <= #laid do
    if laid[k].blk and laid[k].blk.k == "c" then
      local j, w = k, 0
      while j <= #laid and laid[j].blk and laid[j].blk.k == "c" do
        w = math.max(w, laid[j].w); j = j + 1
      end
      for q = k, j - 1 do laid[q].pad = w + 2 - laid[q].w end
      k = j
    else
      k = k + 1
    end
  end

  -- A TABLE'S BOX, which the editor draws and a preview has to write: a
  -- line of ┌─┬─┐ above its first row and └─┴─┘ below its last
  local function border(tb, l, mid, r)
    local rules = {}
    for _, c in ipairs(tb.c or {}) do rules[c] = true end
    local s = { string.rep(" ", tb.x), l }
    for c = tb.x + 1, tb.x + tb.w - 2 do s[#s + 1] = rules[c] and mid or "\u{2500}" end
    s[#s + 1] = r
    return sgr("PlatoMdTable") .. table.concat(s) .. "\27[0m"
  end

  -- and out it goes, a colour change at a time
  for _, L in ipairs(laid) do
    local isCode = L.blk and L.blk.k == "c"
    local bg = isCode and panel or nil
    local piece = {}
    local tb = L.tb
    if tb and tb.e and tb.e:find("t") then emit(border(tb, "\u{250C}", "\u{252C}", "\u{2510}")) end
    if L.blk and L.blk.k == "hr" then
      piece[#piece + 1] = sgr("PlatoMdTable") .. string.rep("\u{2500}", 40)
    else
      if isCode then piece[#piece + 1] = sgr(nil, bg) .. " " end
      for _, r in ipairs(L.runs) do piece[#piece + 1] = sgr(r[2], bg) .. r[1] end
      if isCode then piece[#piece + 1] = sgr(nil, bg) .. string.rep(" ", L.pad - 1) end
    end
    emit(table.concat(piece) .. "\27[0m")
    if tb and tb.e and tb.e:find("b") then emit(border(tb, "\u{2514}", "\u{2534}", "\u{2518}")) end
    -- a top-level heading is underlined in its colour, as the editor's is
    -- banded and set larger
    if L.blk and L.blk.k == "h" and L.blk.n <= 2 and L.w > 0 then
      emit(sgr("PlatoMdH" .. L.blk.n) .. string.rep(L.blk.n == 1 and "\u{2501}" or "\u{2500}", L.w) .. "\27[0m")
    end
  end
end)

if ok then io.stdout:write(table.concat(out, "\n") .. "\n") end
vim.cmd("qall!")
