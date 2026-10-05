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

  -- treesitter if plato would use it for this file; the regex engine if not
  local lang = vim.treesitter.language.get_lang(vim.bo[buf].filetype)
  if lang then pcall(vim.treesitter.start, buf, lang) end
  local paints = hl.treesitter(buf, first, n - 1)

  local lines = api.nvim_buf_get_lines(buf, 0, n, false)
  for l = first, n - 1 do
    local s = lines[l + 1] or ""
    -- per byte, the group that colours it
    local group = hl.byteGroups(buf, l, s, paints)

    -- and out it goes, a colour change at a time, tabs to the next stop
    local cur, col, piece = nil, 0, {}
    local i = 1
    while i <= #s do
      local b = s:byte(i)
      local len = b < 0x80 and 1 or b < 0xE0 and 2 or b < 0xF0 and 3 or 4
      local g = group[i - 1]
      if g ~= cur then
        cur = g
        local a = g and hl.attrs(g) or nil
        local code = "\27[0m"
        if a and a.fg then
          local r, gg, bb = tonumber(a.fg:sub(2, 3), 16), tonumber(a.fg:sub(4, 5), 16),
            tonumber(a.fg:sub(6, 7), 16)
          code = code .. "\27[38;2;" .. r .. ";" .. gg .. ";" .. bb .. "m"
        end
        if a and a.b then code = code .. "\27[1m" end
        piece[#piece + 1] = code
      end
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
    emit(table.concat(piece) .. "\27[0m")
  end
end)

if ok then io.stdout:write(table.concat(out, "\n") .. "\n") end
vim.cmd("qall!")
