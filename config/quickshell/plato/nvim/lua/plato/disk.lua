-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/
--
-- A FILE CHANGED UNDER YOU — by git, a formatter, another editor.
--
-- nvim notices (:checktime) and would ask in a prompt nobody can see: W11,
-- "Load File / OK", waiting for a key in a headless nvim, which then stops
-- answering every other key. FileChangedShell takes the question here:
--
--   changed, buffer untouched    read again, quietly — nothing of yours is lost
--   changed, buffer has edits    a card: Reload (yours are lost) / Keep mine /
--                                Diff — the difference, in a split, and the
--                                card asked again
--   deleted                      a card: Keep the text (as an unsaved buffer)
--                                / Close the tab
--
-- WHEN IT LOOKS: on entering a buffer, when the cursor rests, and when the
-- window comes back into focus (plato asks, PlatoWindow.focused).

local api = vim.api
local M = {}

local asked = {}

local function tidy(buf) return vim.fn.fnamemodify(api.nvim_buf_get_name(buf), ":~") end

-- the buffer against the file, as a unified diff in a split of its own
local function showDiff(buf)
  local name = api.nvim_buf_get_name(buf)
  local okr, disk = pcall(vim.fn.readfile, name)
  if not okr then return end
  local mine = api.nvim_buf_get_lines(buf, 0, -1, false)
  local d = vim.text.diff(table.concat(disk, "\n") .. "\n", table.concat(mine, "\n") .. "\n",
    { result_type = "unified", ctxlen = 3 })
  local lines = { "--- on disk: " .. tidy(buf), "+++ in plato (yours)" }
  for l in tostring(d or ""):gmatch("[^\n]*\n?") do
    if l ~= "" then lines[#lines + 1] = (l:gsub("\n$", "")) end
  end
  vim.cmd("botright vnew")
  local b = api.nvim_get_current_buf()
  vim.bo[b].buftype = "nofile"
  vim.bo[b].bufhidden = "wipe"
  vim.bo[b].buflisted = false
  vim.bo[b].swapfile = false
  api.nvim_buf_set_lines(b, 0, -1, false, lines)
  vim.bo[b].modifiable = false
  vim.bo[b].filetype = "diff"
  pcall(api.nvim_buf_set_name, b, "plato://changes/" .. vim.fs.basename(name))
end

local function ask(buf, deleted)
  if asked[buf] or not api.nvim_buf_is_valid(buf) then return end
  local bridge = require("plato.bridge")
  local n
  if deleted then
    n = bridge.ask(tidy(buf) .. " was deleted on disk.", "warn", {
      { key = "k", label = "Keep the text" },
      { key = "c", label = "Close the tab" },
    }, function(choice)
      asked[buf] = nil
      if not api.nvim_buf_is_valid(buf) then return end
      if choice == "c" then pcall(vim.cmd.bdelete, { args = { tostring(buf) }, bang = true })
      elseif choice == "k" then vim.bo[buf].modified = true end
    end)
  else
    n = bridge.ask(tidy(buf) .. " changed on disk, and you have unsaved edits.", "warn", {
      { key = "r", label = "Reload" },
      { key = "m", label = "Keep mine" },
      { key = "d", label = "Diff" },
    }, function(choice)
      asked[buf] = nil
      if not api.nvim_buf_is_valid(buf) then return end
      if choice == "r" then
        api.nvim_buf_call(buf, function() vim.cmd("silent! edit!") end)
      elseif choice == "d" then
        showDiff(buf)
        -- seen the difference: the question still stands
        ask(buf, false)
      end
    end)
  end
  asked[buf] = n
end

function M.setup()
  local group = api.nvim_create_augroup("plato.disk", { clear = true })
  api.nvim_create_autocmd("FileChangedShell", {
    group = group,
    callback = function(ev)
      local reason = vim.v.fcs_reason
      local buf = ev.buf
      -- nothing but the time or the mode: not worth a word
      if reason == "mode" or reason == "time" then vim.v.fcs_choice = ""; return end
      if reason == "deleted" then
        vim.v.fcs_choice = ""
        vim.schedule(function() ask(buf, true) end)
      elseif vim.bo[buf].modified or reason == "conflict" then
        vim.v.fcs_choice = ""
        vim.schedule(function() ask(buf, false) end)
      else
        -- nothing of yours in it: read it again
        vim.v.fcs_choice = "reload"
      end
    end,
  })
  api.nvim_create_autocmd({ "BufEnter", "CursorHold", "CursorHoldI" }, {
    group = group,
    callback = function()
      if vim.fn.getcmdwintype() == "" then vim.cmd("silent! checktime") end
    end,
  })
  api.nvim_create_autocmd("BufWipeout", {
    group = group,
    callback = function(ev)
      if asked[ev.buf] then require("plato.bridge").unask(asked[ev.buf]); asked[ev.buf] = nil end
    end,
  })
end

return M
