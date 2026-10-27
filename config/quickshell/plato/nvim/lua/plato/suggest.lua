-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/
--
-- A file opened in a language there is no treesitter parser for, but one
-- that could be built, is offered one: a question card (bridge.ask) with
-- Build · Not now · Never for <lang>. Build hands the language to the
-- window (`buildParsers` event), which builds it the way the plugin panel's
-- Parsers page does (core/Plugins.qml, nvim/parsers.lua) and every open
-- buffer in it lights up when it lands (plugins.parsersAdded).
--
-- The language is nvim's own guess: vim.filetype has already matched the
-- file by its name, its extension, its shebang or its first lines before
-- FileType fires, and vim.treesitter.language.get_lang maps that filetype
-- to a parser (nvim-treesitter registers the ones nvim does not know).
--
-- Asked once per language per engine. "Never" is kept, for every window,
-- in the engine's state dir (parsers-declined.json). Not asked for:
--   a file too big for the extras (large.lua), a buffer that is not a file,
--   a grammar that must be generated with the tree-sitter CLI when there is
--   none, or no C compiler — the build could only fail.
-- vim.g.plato_suggest_parsers = false (the settings sheet) turns it off.

local M = {}
local api = vim.api
local util = require("plato.util")

local declinedPath = vim.fn.stdpath("state") .. "/parsers-declined.json"
local asked = {}

-- the build nvim-treesitter knows for a language, or nil
local function buildable(lang)
  local ok, registry = pcall(require, "nvim-treesitter.parsers")
  if not ok or type(registry) ~= "table" then return nil end
  local spec = registry[lang]
  local info = spec and spec.install_info
  if not info then return nil end
  if info.generate and vim.fn.executable("tree-sitter") ~= 1 then return nil end
  if vim.fn.executable("cc") ~= 1 or vim.fn.executable("git") ~= 1 then return nil end
  return info
end

-- the parser a buffer would want and cannot load, or nil
function M.missing(buf)
  if not api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "" then return nil end
  if vim.b[buf].plato_large then return nil end
  local ft = vim.bo[buf].filetype
  if ft == "" then return nil end
  local lang = vim.treesitter.language.get_lang(ft) or ft
  -- language.add RETURNS its failure (nil, "No parser for …") rather than
  -- throwing it, so pcall alone said every language loaded and nothing was
  -- ever offered (user, 2026-10-11: a .yaml)
  local ok, loaded = pcall(vim.treesitter.language.add, lang)
  if ok and loaded then return nil end
  if not buildable(lang) then return nil end
  return lang
end

function M.check(buf)
  if vim.g.plato_suggest_parsers == false then return end
  local lang = M.missing(buf)
  if not lang or asked[lang] then return end
  if util.readJson(declinedPath)[lang] then return end
  asked[lang] = true
  local bridge = require("plato.bridge")
  bridge.ask(("No syntax parser for %s yet — colors come from the regex engine. Build one? (a few seconds)")
    :format(lang), "info", {
      { key = "b", label = "Build " .. lang },
      { key = "l", label = "Not now" },
      { key = "n", label = "Never for " .. lang },
    }, function(choice)
      if choice == "b" then
        bridge.send({ event = "buildParsers", langs = { lang } })
      elseif choice == "n" then
        local d = util.readJson(declinedPath)
        d[lang] = true
        util.writeJson(declinedPath, d)
      end
    end)
end

-- ── AND THE TOOLS, ON FIRST USE (user, 2026-10-27) ─────────────────────
-- The language servers (plugins.lua), formatters (conform) and linters
-- (nvim-lint) plato is set up for are skipped quietly when they are not
-- installed. A file whose language wants one that is missing asks, once
-- per language: Install · Not now · Never, and Install hands the packages
-- to the window (`install` event → Ceres, as Calypso installs its tools).
-- Only what PKG knows the Arch package of is offered. "Never" is kept per
-- package (tools-declined.json); vim.g.plato_suggest_tools = false (the
-- settings sheet) turns it off.
local toolsDeclined = vim.fn.stdpath("state") .. "/tools-declined.json"
local toolsAsked = {}
local PKG = {
  ["lua-language-server"] = "lua-language-server", stylua = "stylua", luacheck = "luacheck",
  ["bash-language-server"] = "bash-language-server", shfmt = "shfmt", shellcheck = "shellcheck",
  marksman = "marksman", ["rust-analyzer"] = "rust-analyzer", clangd = "clang", gopls = "gopls",
  ruff = "ruff", basedpyright = "basedpyright", ["typescript-language-server"] = "typescript-language-server",
  ["yaml-language-server"] = "yaml-language-server", taplo = "taplo-cli", prettier = "prettier",
}
-- a formatter's program, where its conform name is not it
local FORMATTER_EXE = { ruff_format = "ruff" }

-- what a filetype is set up to use and is not here: { { exe, pkg, role } }
function M.missingTools(buf)
  if not api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "" or vim.b[buf].plato_large then return {} end
  local ft = vim.bo[buf].filetype
  if ft == "" then return {} end
  local out, seen = {}, {}
  local function want(exe, role)
    if type(exe) ~= "string" or exe == "" or seen[exe] then return end
    seen[exe] = true
    if vim.fn.executable(exe) == 1 or not PKG[exe] then return end
    out[#out + 1] = { exe = exe, pkg = PKG[exe], role = role }
  end
  for _, name in ipairs(require("plato.plugins").lspCandidates or {}) do
    local ok, cfg = pcall(function() return vim.lsp.config[name] end)
    if ok and cfg and type(cfg.cmd) == "table" and vim.tbl_contains(cfg.filetypes or {}, ft) then
      want(cfg.cmd[1], "language server")
    end
  end
  local okc, conform = pcall(require, "conform")
  if okc then
    for _, f in ipairs(conform.formatters_by_ft and conform.formatters_by_ft[ft] or {}) do
      if type(f) == "string" then want(FORMATTER_EXE[f] or f, "formatter") end
    end
  end
  local okl, lint = pcall(require, "lint")
  if okl then
    for _, n in ipairs(lint.linters_by_ft[ft] or {}) do
      local l = lint.linters[n]
      local cmd = type(l) == "table" and l.cmd or nil
      if type(cmd) == "function" then cmd = cmd() end
      want(cmd, "checker")
    end
  end
  return out
end

function M.checkTools(buf)
  if vim.g.plato_suggest_tools == false then return end
  local ft = vim.bo[buf].filetype
  if ft == "" or toolsAsked[ft] then return end
  local declined = util.readJson(toolsDeclined)
  local tools = vim.tbl_filter(function(t) return not declined[t.pkg] end, M.missingTools(buf))
  if #tools == 0 then return end
  toolsAsked[ft] = true
  local names, pkgs = {}, {}
  for _, t in ipairs(tools) do
    names[#names + 1] = t.exe .. " (" .. t.role .. ")"
    if not vim.tbl_contains(pkgs, t.pkg) then pkgs[#pkgs + 1] = t.pkg end
  end
  local bridge = require("plato.bridge")
  bridge.ask(("Not installed for %s files: %s. Install?"):format(ft, table.concat(names, ", ")), "info", {
      { key = "i", label = "Install" },
      { key = "l", label = "Not now" },
      { key = "n", label = "Never" },
    }, function(choice)
      if choice == "i" then
        bridge.send({ event = "install", pkgs = pkgs, why = "for " .. ft .. " files in Plato" })
      elseif choice == "n" then
        local d = util.readJson(toolsDeclined)
        for _, p in ipairs(pkgs) do d[p] = true end
        util.writeJson(toolsDeclined, d)
      end
    end)
end

function M.setup()
  api.nvim_create_autocmd("FileType", {
    group = api.nvim_create_augroup("plato.suggest", { clear = true }),
    callback = function(ev)
      -- after the FileType handlers that start treesitter, and after
      -- large.lua has had its say
      vim.schedule(function() M.check(ev.buf); M.checkTools(ev.buf) end)
    end,
  })
end

return M
