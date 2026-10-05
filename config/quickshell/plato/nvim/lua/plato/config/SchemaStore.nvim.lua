-- SchemaStore.nvim: the schemas of common JSON and YAML files — package.json,
-- tsconfig, GitHub workflows, docker-compose and hundreds more — handed to
-- the JSON and YAML language servers, which then complete and check them.
-- Does nothing until vscode-json-languageserver / yaml-language-server are
-- installed (plato enables a server only when its program is on the PATH).
-- Run by plato after the plugin loads; edit freely (plato's plugin panel,
-- "configure", opens this file).
local ss = require("schemastore")
vim.lsp.config("jsonls", {
  settings = { json = { schemas = ss.json.schemas(), validate = { enable = true } } },
})
vim.lsp.config("yamlls", {
  settings = { yaml = { schemaStore = { enable = false, url = "" }, schemas = ss.yaml.schemas() } },
})
