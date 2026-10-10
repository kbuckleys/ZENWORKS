-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/
--
-- PEEK: a definition opened in a card under the cursor, rather than in place
-- of the file you are reading. The card is a real nvim window — a float
-- plato draws (FloatCard) — over the definition's own buffer, so it can be
-- read, moved about in and edited like any other.
--
--   q or <Esc> (normal mode)  closes it
--   <CR> (normal mode)        opens the definition for real, at that line
--
-- A buffer the peek loaded is kept out of the tabs while it is only being
-- looked at; one that was edited in the card stays a tab when it closes,
-- with its unsaved ●, so nothing typed there is lost.

local api = vim.api
local M = {}

local function close(win, buf, wasListed)
  if api.nvim_win_is_valid(win) then api.nvim_win_close(win, true) end
  if api.nvim_buf_is_valid(buf) then
    for _, k in ipairs({ "q", "<Esc>", "<CR>" }) do pcall(vim.keymap.del, "n", k, { buffer = buf }) end
    vim.bo[buf].buflisted = wasListed or vim.bo[buf].modified
  end
  require("plato.view").schedule(true)
end

function M.open(item)
  local file = item.filename
  local buf = vim.fn.bufadd(file)
  local wasListed = vim.bo[buf].buflisted and api.nvim_buf_is_loaded(buf)
  vim.fn.bufload(buf)
  vim.bo[buf].buflisted = wasListed
  local width = math.min(110, vim.o.columns - 6)
  local height = math.min(16, math.max(6, math.floor(vim.o.lines * 0.45)))
  local win = api.nvim_open_win(buf, true, {
    relative = "cursor", row = 1, col = 0, width = width, height = height,
    style = "minimal", zindex = 60,
  })
  vim.w[win].plato_title = vim.fn.fnamemodify(file, ":~:.") .. ":" .. item.lnum
  vim.wo[win].wrap = false
  pcall(api.nvim_win_set_cursor, win, { item.lnum, math.max(0, (item.col or 1) - 1) })
  vim.fn.winrestview({ topline = math.max(1, item.lnum - 2) })
  local function shut() close(win, buf, wasListed) end
  vim.keymap.set("n", "q", shut, { buffer = buf, nowait = true })
  vim.keymap.set("n", "<Esc>", shut, { buffer = buf, nowait = true })
  vim.keymap.set("n", "<CR>", function()
    local pos = api.nvim_win_get_cursor(win)
    shut()
    vim.cmd.edit(vim.fn.fnameescape(file))
    pcall(api.nvim_win_set_cursor, 0, pos)
    vim.cmd("normal! zz")
  end, { buffer = buf, nowait = true })
  -- leaving the card any other way closes it too
  api.nvim_create_autocmd("WinLeave", { once = true, callback = function()
    if api.nvim_get_current_win() == win then vim.schedule(shut) end
  end })
  require("plato.view").schedule(true)
end

-- REFERENCES, to browse rather than to land in nvim's quickfix list: sent
-- to plato as a list, which its picker shows with each one previewed in
-- place (Picker's "refs" mode).
function M.references()
  if #vim.lsp.get_clients({ bufnr = 0, method = "textDocument/references" }) == 0 then
    vim.notify("No language server here knows about references", vim.log.levels.WARN)
    return
  end
  vim.lsp.buf.references({ includeDeclaration = false }, {
    on_list = function(t)
      local items = {}
      for _, it in ipairs(t.items or {}) do
        items[#items + 1] = { path = it.filename, line = it.lnum, col = it.col,
                              text = vim.trim(it.text or "") }
      end
      if #items == 0 then
        vim.notify("No references found", vim.log.levels.WARN)
        return
      end
      require("plato.bridge").send({ event = "refs", items = items })
    end,
  })
end

function M.definition()
  vim.lsp.buf.definition({
    on_list = function(t)
      local item = t.items and t.items[1]
      if not item then
        vim.notify("No definition found", vim.log.levels.WARN)
        return
      end
      M.open(item)
    end,
  })
end

return M
