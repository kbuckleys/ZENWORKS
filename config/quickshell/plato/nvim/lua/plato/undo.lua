-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/
--
-- THE UNDO HISTORY, AS A LIST. nvim keeps every state a buffer has been in
-- — a tree, not a line: an undo then a new edit starts a branch, and `u`
-- alone can never reach the old one again. undotree() has all of them; this
-- lays them out newest first for plato's picker (Space h), each with when
-- it was made and how much it differs from now, and previews what going
-- back would change as a diff. Enter goes there (:undo N), branches and all.
-- What undotree plugins drew in a split, without the split.

local api = vim.api
local M = {}

-- every state, flattened out of the tree: { seq, time, save? }
local function flatten(entries, out)
  for _, e in ipairs(entries or {}) do
    out[#out + 1] = { seq = e.seq, time = e.time, save = e.save }
    if e.alt then flatten(e.alt, out) end
  end
  return out
end

-- The buffer's text at each state in `seqs`, got by going to each in turn
-- and coming back once. Nothing else hears of the trip through autocommands:
-- they are off for it, and the view and cursor are put back as they were.
--
-- ONE WALK, NOT A TRIP PER STATE. eventignore does not silence buffer
-- updates (nvim_buf_attach), and the language server hears every :undo as an
-- edit; going there and back for each of sixty states told it a hundred and
-- twenty times. Now it is one step per state and one home.
--   → seq → lines
local function textsAt(seqs)
  local now = vim.fn.undotree().seq_cur
  local view = vim.fn.winsaveview()
  local ei = vim.o.eventignore
  vim.o.eventignore = "all"
  local out = {}
  for _, seq in ipairs(seqs) do
    local ok, lines = pcall(function()
      vim.cmd("silent undo " .. seq)
      return api.nvim_buf_get_lines(0, 0, -1, false)
    end)
    if ok then out[seq] = lines end
  end
  pcall(vim.cmd, "silent undo " .. now)
  vim.o.eventignore = ei
  vim.fn.winrestview(view)
  return out
end

local function counts(diff)
  local add, del = 0, 0
  for l in diff:gmatch("[^\n]+") do
    local c = l:sub(1, 1)
    if c == "+" and l:sub(1, 3) ~= "+++" then add = add + 1
    elseif c == "-" and l:sub(1, 3) ~= "---" then del = del + 1 end
  end
  return add, del
end

-- newest first: { seq, label, detail, current }
function M.list()
  local tree = vim.fn.undotree()
  local states = flatten(tree.entries, {})
  table.sort(states, function(a, b) return a.seq > b.seq end)
  local now = table.concat(api.nvim_buf_get_lines(0, 0, -1, false), "\n") .. "\n"
  local out = {}
  -- the state before any change, so the very first edit can be undone too
  states[#states + 1] = { seq = 0, time = nil }
  while #states > 60 do table.remove(states, 60) end
  local want = {}
  for _, s in ipairs(states) do
    if s.seq ~= tree.seq_cur then want[#want + 1] = s.seq end
  end
  local texts = textsAt(want)
  for _, s in ipairs(states) do
    local detail = ""
    if s.seq ~= tree.seq_cur then
      local lines = texts[s.seq]
      if lines then
        local a, d = counts(vim.diff(now, table.concat(lines, "\n") .. "\n") or "")
        detail = ("+%d −%d"):format(a, d)
      end
    end
    out[#out + 1] = {
      seq = s.seq,
      label = s.seq == 0 and "as it was opened"
        or ("change %d · %s%s"):format(s.seq, require("plato.util").ago(s.time, true),
          s.save and " · saved" or ""),
      detail = s.seq == tree.seq_cur and "you are here" or detail,
      current = s.seq == tree.seq_cur,
    }
  end
  return out
end

-- what going to `seq` would change, as a unified diff of now against it
function M.preview(seq)
  local lines = textsAt({ seq })[seq]
  if not lines then return "" end
  local now = table.concat(api.nvim_buf_get_lines(0, 0, -1, false), "\n") .. "\n"
  return vim.diff(now, table.concat(lines, "\n") .. "\n", { ctxlen = 2 }) or ""
end

function M.go(seq)
  vim.cmd("undo " .. seq)
  require("plato.view").schedule(true)
end

return M
