-- conform.nvim: formatting with the formatter each language is written with,
-- not only what a language server offers. Space l f, and every save when the
-- setting "Format on save" is on (plato/nvim/lua/plato/editing.lua).
-- Run by plato after the plugin loads; edit freely (plato's plugin panel,
-- "configure", opens this file).
--
-- A FORMATTER THAT IS NOT INSTALLED IS SKIPPED, and the language server
-- formats instead (lsp_format = "fallback"), so this list can name more than
-- this machine has. To have them: stylua, shfmt, ruff, prettier.
--
-- QML IS LEFT OUT ON PURPOSE: qmlformat rewrites the layout of a file
-- wholesale, and this shell's files are laid out by hand.

local web = { "prettierd", "prettier", stop_after_first = true }
require("conform").setup({
  formatters_by_ft = {
    lua = { "stylua" },
    sh = { "shfmt" },
    bash = { "shfmt" },
    python = { "ruff_format" },
    javascript = web, typescript = web, json = web, jsonc = web,
    css = web, scss = web, html = web, yaml = web, markdown = web,
    rust = { "rustfmt", lsp_format = "fallback" },
  },
  default_format_opts = { lsp_format = "fallback" },
})
