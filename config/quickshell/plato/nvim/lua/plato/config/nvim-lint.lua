-- nvim-lint: linters a language server does not cover, their findings shown
-- as diagnostics (the gutter, the scrollbar's marks, the status line's count).
-- Run by plato after the plugin loads; edit freely (plato's plugin panel,
-- "configure", opens this file).
--
-- Linted when a file is opened, saved, and as insert mode is left. A linter
-- that is not installed is skipped. To have them: shellcheck, luacheck.

local lint = require("lint")
lint.linters_by_ft = {
  sh = { "shellcheck" },
  bash = { "shellcheck" },
  lua = { "luacheck" },
}

vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost", "InsertLeave" }, {
  group = vim.api.nvim_create_augroup("plato.lint", { clear = true }),
  callback = function(ev)
    if vim.bo[ev.buf].buftype ~= "" then return end
    local names = {}
    for _, n in ipairs(lint.linters_by_ft[vim.bo[ev.buf].filetype] or {}) do
      local l = lint.linters[n]
      local cmd = type(l) == "table" and l.cmd or nil
      if type(cmd) == "function" then cmd = cmd() end
      if type(cmd) == "string" and vim.fn.executable(cmd) == 1 then names[#names + 1] = n end
    end
    if #names > 0 then lint.try_lint(names) end
  end,
})
