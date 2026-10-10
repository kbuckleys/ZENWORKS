-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/
--
-- A FILE TOO BIG FOR THE EXTRAS. A log of a hundred megabytes, a minified
-- bundle, a dump: every extra plato draws walks the file somewhere — syntax,
-- treesitter, a language server, git's diff, the minimap, sticky scroll,
-- the outline, colour codes, guides — and together they make moving through
-- one slow. Past the settings' threshold (largeFileMB, 5 by default) a
-- buffer is marked `b:plato_large` before it is read, and each of them
-- checks the mark and stays out. The status line says so.
--
-- What is left is nvim itself: the text, search, every motion and edit.

local api = vim.api
local M = {}

function M.is(buf) return vim.b[buf or 0].plato_large == true end

function M.setup()
  local group = api.nvim_create_augroup("plato.large", { clear = true })
  api.nvim_create_autocmd("BufReadPre", {
    group = group,
    callback = function(ev)
      local st = vim.uv.fs_stat(ev.match)
      local mb = tonumber(vim.g.plato_large_mb) or 5
      if not (st and st.type == "file" and st.size > mb * 1024 * 1024) then return end
      local b = ev.buf
      vim.b[b].plato_large = true
      -- mini.diff and mini.hipatterns stay out of a buffer that says so
      vim.b[b].minidiff_disable = true
      vim.b[b].minihipatterns_disable = true
      -- an undo file for a file this size is as big again, and slow to write
      vim.bo[b].undofile = false
      vim.bo[b].swapfile = false
    end,
  })
  -- after the filetype's own setting up: no syntax, no parser
  api.nvim_create_autocmd("FileType", {
    group = group,
    callback = function(ev)
      if not M.is(ev.buf) then return end
      pcall(vim.treesitter.stop, ev.buf)
      vim.schedule(function()
        if api.nvim_buf_is_valid(ev.buf) then vim.bo[ev.buf].syntax = "OFF" end
      end)
    end,
  })
  -- no language server for it either
  api.nvim_create_autocmd("LspAttach", {
    group = group,
    callback = function(ev)
      if not M.is(ev.buf) then return end
      vim.schedule(function()
        pcall(vim.lsp.buf_detach_client, ev.buf, ev.data.client_id)
      end)
    end,
  })
end

return M
