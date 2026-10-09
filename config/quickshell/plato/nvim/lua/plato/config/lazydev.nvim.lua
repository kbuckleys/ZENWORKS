-- lazydev.nvim: teaches the Lua language server nvim's API — vim.api,
-- vim.lsp, vim.uv and the rest — in Lua files that are nvim configuration,
-- plato's own included (plato/nvim/lua). Completion and hover then know
-- them, instead of calling `vim` an undefined global.
-- Does nothing until lua-language-server is installed.
-- Run by plato after the plugin loads; edit freely (plato's plugin panel,
-- "configure", opens this file).
require("lazydev").setup({
  library = {
    { path = "${3rd}/luv/library", words = { "vim%.uv" } },
  },
})
