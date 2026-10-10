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
  if pcall(vim.treesitter.language.add, lang) then return nil end
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
  bridge.ask(("No syntax parser for %s yet — colours come from the regex engine. Build one? (a few seconds)")
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

function M.setup()
  api.nvim_create_autocmd("FileType", {
    group = api.nvim_create_augroup("plato.suggest", { clear = true }),
    callback = function(ev)
      -- after the FileType handlers that start treesitter, and after
      -- large.lua has had its say
      vim.schedule(function() M.check(ev.buf) end)
    end,
  })
end

return M
