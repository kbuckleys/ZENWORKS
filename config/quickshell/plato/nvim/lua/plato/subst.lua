-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/
--
-- :s, LIVE. While a substitute is being typed, the lines it would change
-- show what they would become, with the replacements lit — before Enter.
--
-- nvim has this ('inccommand'), but applies it while it redraws the screen,
-- and a headless engine never redraws: the matches lit up and the text never
-- changed. So the command line is read here (nvim_parse_cmd: the range, and
-- the pattern, replacement and flags behind the delimiter) and the view model
-- asks `apply` for each line on screen it covers — the buffer itself is never
-- touched.

local api = vim.api
local M = {}

-- split "/pat/rep/flags" at its own delimiter, honouring backslashes
local function split(arg)
  local d = arg:sub(1, 1)
  if d == "" or d:match("[%w%s\\\"|]") then return nil end
  local parts, cur, i = {}, {}, 2
  while i <= #arg do
    local c = arg:sub(i, i)
    if c == "\\" and i < #arg then
      local n = arg:sub(i + 1, i + 1)
      -- an escaped delimiter is the character itself; anything else stays escaped
      cur[#cur + 1] = n == d and d or c .. n
      i = i + 2
    elseif c == d then
      parts[#parts + 1] = table.concat(cur)
      cur = {}
      i = i + 1
    else
      cur[#cur + 1] = c
      i = i + 1
    end
  end
  parts[#parts + 1] = table.concat(cur)
  return parts
end

-- nil, or { first, last, only?, apply(line) → newLine, { {b0, b1}, ... } }
-- (only: the set of lines it applies to, when not every line in range)
function M.compute()
  if vim.fn.getcmdtype() ~= ":" then return nil end
  local ok, cmd = pcall(api.nvim_parse_cmd, vim.fn.getcmdline(), {})
  -- :cdo s/…/…/ (plato's replace in the project): the :s it runs, shown on
  -- the quickfix list's lines in this buffer and nowhere else
  local only
  if ok and cmd and cmd.cmd == "cdo" then
    local inner = table.concat(cmd.args or {}, " "):gsub("%s+|.*$", "")
    ok, cmd = pcall(api.nvim_parse_cmd, inner, {})
    if not ok or not cmd or cmd.cmd ~= "substitute" then return nil end
    only = {}
    local buf = api.nvim_get_current_buf()
    for _, it in ipairs(vim.fn.getqflist()) do
      if it.bufnr == buf then only[it.lnum] = true end
    end
    cmd.range = { 1, api.nvim_buf_line_count(buf) }
  end
  if not ok or not cmd or cmd.cmd ~= "substitute" then return nil end
  local parts = split(cmd.args and cmd.args[1] or "")
  -- nothing to show until the replacement has begun
  if not parts or #parts < 2 or parts[1] == "" then return nil end
  local pat, rep, flags = parts[1], parts[2], parts[3] or ""
  local all = flags:find("g") ~= nil
  if flags:find("i") then pat = "\\c" .. pat elseif flags:find("I") then pat = "\\C" .. pat end
  local okr = pcall(vim.regex, pat)
  if not okr then return nil end
  local cur = api.nvim_win_get_cursor(0)[1]
  local first = cmd.range and cmd.range[1] or cur
  local last = cmd.range and (cmd.range[2] or cmd.range[1]) or cur
  return {
    first = first, last = last, only = only,
    apply = function(line)
      local out, lit, from = {}, {}, 0
      local len = 0
      while true do
        local m = vim.fn.matchstrpos(line, pat, from)
        local s, e = m[2], m[3]
        if s < 0 then break end
        out[#out + 1] = line:sub(from + 1, s)
        len = len + (s - from)
        local okS, new = pcall(vim.fn.substitute, m[1], pat, rep, "")
        new = okS and new or m[1]
        out[#out + 1] = new
        lit[#lit + 1] = { len, len + #new }
        len = len + #new
        -- an empty match moves on a character, or it would match forever
        if e > s then from = e
        else
          out[#out + 1] = line:sub(e + 1, e + 1)
          len = len + #line:sub(e + 1, e + 1)
          from = e + 1
        end
        if not all or from > #line then break end
      end
      if #lit == 0 then return nil end
      out[#out + 1] = line:sub(from + 1)
      return table.concat(out), lit
    end,
  }
end

return M
