-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/
--
-- The plugins plato's nvim runs, and the language servers.
--
-- TWO KINDS. The CORE is not features but data plato reads: nvim-lspconfig's
-- server definitions and nvim-treesitter's highlight queries. Everything
-- else is YOURS, listed in plato/nvim/plugins.json and managed from plato's
-- plugin panel (Space U): installed, switched off and on, configured and
-- removed there. A plugin's configuration is a Lua file of its own,
-- plato/nvim/lua/plato/config/<name>.lua, run after the plugin loads; the
-- panel's "configure" opens it in plato.
--
--   plugins.json   { "plugins": [ { "src": "https://github.com/…", "enabled": true } ] }
--
-- WHAT IS NOT HERE ANY MORE, and why. Completion is nvim's own now (0.12's
-- 'autocomplete' and vim.lsp.completion, below), so mini.completion,
-- mini.snippets and friendly-snippets went; marks.nvim only drew marks in a
-- sign column. nvim-autopairs went for mini.pairs, already in mini.nvim, and
-- the Alt j/k line moves for mini.move (config/mini.nvim.lua). Statuslines, finders, file managers and the like never had a
-- place: plato draws its own.
--
-- FETCHED ON FIRST START, NEVER BUNDLED. nvim's built-in vim.pack clones them
-- into plato's data directory (~/.local/share/quickshell/plato/nvim/site) at
-- the versions pinned in nvim-pack-lock.json beside init.lua — which travels
-- with this repository, as plugins.json does. Nothing here reads the
-- terminal nvim's config or packages.

local M = {}

local here = vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))   -- lua/plato
M.root = vim.fs.dirname(vim.fs.dirname(here))                       -- plato/nvim
M.manifestPath = M.root .. "/plugins.json"
M.configDir = here .. "/config"

local GH = "https://github.com/"
M.core = {
  { src = GH .. "neovim/nvim-lspconfig" },
  -- for its queries only: nvim bundles a few parsers, and these are how every
  -- other language gets coloured once a parser for it is installed
  { src = GH .. "nvim-treesitter/nvim-treesitter" },
  -- plato's git hunks are mini.diff's (git.lua), so mini.nvim is not yours to
  -- switch off; which of its other modules run is (config/mini.nvim.lua)
  { src = GH .. "nvim-mini/mini.nvim" },
}

function M.nameOf(src)
  return ((tostring(src):gsub("/+$", ""):match("[^/]+$") or src):gsub("%.git$", ""))
end

-- plugins.json, as a list of { src, name, enabled, version? }
function M.manifest()
  local ok, data = pcall(function()
    return vim.json.decode(table.concat(vim.fn.readfile(M.manifestPath), "\n"))
  end)
  local out = {}
  if not ok or type(data) ~= "table" or type(data.plugins) ~= "table" then return out end
  for _, p in ipairs(data.plugins) do
    if type(p) == "table" and type(p.src) == "string" and p.src ~= "" then
      out[#out + 1] = { src = p.src, name = M.nameOf(p.src), enabled = p.enabled ~= false,
                        version = p.version }
    end
  end
  return out
end

-- what vim.pack is given: the core, and the manifest's — only the switched-on
-- ones to load, every one to keep up to date (nvim/pack.lua)
function M.specs(all)
  local out = vim.deepcopy(M.core)
  for _, p in ipairs(M.manifest()) do
    if all or p.enabled then out[#out + 1] = { src = p.src, version = p.version } end
  end
  return out
end

-- a configuration that fails leaves the rest standing: one plugin renamed
-- upstream must not take the others down with it
local function warn(what, err)
  vim.schedule(function()
    vim.notify("plato: " .. what .. ": " .. tostring(err), vim.log.levels.WARN)
  end)
end

function M.configure(name)
  local f = M.configDir .. "/" .. name .. ".lua"
  if vim.uv.fs_stat(f) then
    local ok, err = pcall(dofile, f)
    if not ok then warn(name, err) end
  end
end

local function afterLoad()
  -- nvim-treesitter keeps its queries under runtime/, not at its root
  for _, p in ipairs(vim.pack.get()) do
    if p.spec.name == "nvim-treesitter" then
      local rt = p.path .. "/runtime"
      if not vim.tbl_contains(vim.opt.runtimepath:get(), rt) then
        vim.opt.runtimepath:append(rt)
      end
    end
  end
end

function M.load()
  -- the bridge test runs a bare engine: no plugins, and no network
  if vim.env.PLATO_NO_PLUGINS == "1" then return end
  local specs = M.specs(false)
  -- AN INSTALL THAT WAS CUT SHORT is not an install. Closing plato during
  -- the very first clones leaves directories that vim.pack will take for
  -- installed plugins next time: an empty checkout, a plugin at no revision.
  -- A marker is written once everything has arrived at its pinned version;
  -- without it, any directory not checked out at the lockfile's revision is
  -- removed, so vim.pack clones it again. (vim.pack.update rewrites the
  -- lockfile, so the check runs once after an update too, and passes.)
  local dir = vim.fn.stdpath("data") .. "/site/pack/core/opt/"
  local marker = vim.fn.stdpath("data") .. "/plato-plugins-ok"
  local lock = vim.fn.stdpath("config") .. "/nvim-pack-lock.json"
  local want = vim.fn.filereadable(lock) == 1 and vim.fn.sha256(table.concat(vim.fn.readfile(lock), "\n")) or ""
  local have = vim.fn.filereadable(marker) == 1 and vim.fn.readfile(marker)[1] or nil
  if have ~= want then
    local pins = {}
    pcall(function() pins = vim.json.decode(table.concat(vim.fn.readfile(lock), "\n")).plugins end)
    for _, sp in ipairs(specs) do
      local name = M.nameOf(sp.src)
      local d = dir .. name
      if vim.uv.fs_stat(d) then
        local r = vim.system({ "git", "-C", d, "rev-parse", "--verify", "-q", "HEAD" }):wait()
        local head = vim.trim(r.stdout or "")
        local pin = pins[name] and pins[name].rev
        if r.code ~= 0 or (pin and head ~= pin) then vim.fn.delete(d, "rf") end
      end
    end
  end

  -- confirm = false: there is no one to answer a prompt in a headless nvim.
  -- vim.pack reports its own progress, which reaches plato's status line.
  local ok, err = pcall(vim.pack.add, specs, { confirm = false })
  if not ok then warn("plugins", err); return end
  if have ~= want then vim.fn.writefile({ want }, marker) end
  afterLoad()
  -- a core plugin is configured too, when it has a file in config/
  for _, sp in ipairs(M.core) do M.configure(M.nameOf(sp.src)) end
  for _, p in ipairs(M.manifest()) do
    if p.enabled then M.configure(p.name) end
  end
end

-- One plugin, into the running engine: what the panel asks for after it has
-- installed a plugin or switched one on. Already on disk (the panel cloned
-- it, in an nvim of its own), so this costs no network. Buffers already open
-- are told their filetype again, so a plugin that works per buffer sees them.
function M.loadOne(name)
  for _, p in ipairs(M.manifest()) do
    if p.name == name then
      local ok, err = pcall(vim.pack.add, { { src = p.src, version = p.version } }, { confirm = false })
      if not ok then warn(name, err); return false end
      afterLoad()
      M.configure(name)
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].filetype ~= "" then
          vim.api.nvim_exec_autocmds("FileType", { buffer = b, modeline = false })
        end
      end
      return true
    end
  end
  return false
end

-- Parsers just built (parsers.lua, from the plugin panel's Parsers page):
-- every open buffer in one of those languages starts treesitter now, rather
-- than in the next window. A parser that was already loaded and has been
-- rebuilt stays the old one in this engine: nvim cannot unload a library.
function M.parsersAdded(langs)
  local want = {}
  for _, l in ipairs(langs or {}) do want[l] = true end
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    local ft = vim.api.nvim_buf_is_loaded(b) and vim.bo[b].filetype or ""
    local lang = ft ~= "" and vim.treesitter.language.get_lang(ft) or nil
    if lang and want[lang] and not vim.b[b].plato_large then
      if pcall(vim.treesitter.language.add, lang) then
        pcall(vim.treesitter.start, b, lang)
        require("plato.hl").forget(b)
      end
    end
  end
  require("plato.view").schedule(true)
end

-- ── completion, nvim's own ─────────────────────────────────────────────
-- 'autocomplete' opens the menu as you type, from the language server first
-- ("o": the omnifunc, which vim.lsp.completion provides) and then the words
-- of this buffer and the others on screen. vim.lsp.completion also expands
-- a server's snippets when one is accepted, and applies its extra edits
-- (an import added at the top). Plato draws the menu and its documentation
-- popup itself (CompletionMenu, FloatCard).
function M.completion()
  vim.o.autocomplete = true
  -- NO DELAY. While 'autocompletedelay' runs nvim sits waiting for the next
  -- key without running scheduled callbacks, so no frame goes out: every
  -- <BS> and most letters reached the screen 40 ms late, and a held
  -- backspace fell behind its own key repeat. At 0 a frame takes ~4 ms.
  vim.o.autocompletedelay = 0
  -- paths first (paths.lua): "~/to" is a path being typed before it is a
  -- word, and the language server has nothing to say about it
  require("plato.paths")
  vim.o.complete = "Fv:lua.PlatoPathComplete,o,.,w,b"
  vim.o.completeopt = "menuone,noselect,fuzzy,popup"
  -- NOT ON THE WAY IN. 'autocomplete' also opens a menu the moment insert
  -- mode starts after a word (A at a line's end, a on its last letter),
  -- and opening one swaps the word before the cursor for itself — the same
  -- text, but a change all the same: the tab's unsaved dot came on, and an
  -- empty undo step went into the history, before a key was typed. So it
  -- is held for this buffer from InsertEnter until the first character is
  -- typed (or insert is left), and the menu comes as you type, as before.
  local function release(buf)
    if not vim.b[buf].plato_ac_held then return end
    vim.b[buf].plato_ac_held = nil
    vim.api.nvim_buf_call(buf, function() vim.cmd("setlocal autocomplete<") end)
  end
  vim.api.nvim_create_autocmd("InsertEnter", {
    callback = function(ev)
      if not vim.go.autocomplete or vim.b[ev.buf].plato_ac_held then return end
      vim.b[ev.buf].plato_ac_held = true
      vim.bo[ev.buf].autocomplete = false
    end,
  })
  vim.api.nvim_create_autocmd({ "InsertCharPre", "InsertLeave" }, {
    callback = function(ev) release(ev.buf) end,
  })
  vim.api.nvim_create_autocmd("LspAttach", {
    callback = function(ev)
      local client = vim.lsp.get_client_by_id(ev.data.client_id)
      if client and client:supports_method("textDocument/completion") then
        pcall(vim.lsp.completion.enable, true, client.id, ev.buf, { autotrigger = false })
      end
    end,
  })
  -- AFTER A SERVER'S TRIGGER CHARACTER — "picker." "std::" "p->" — the
  -- server's members straight away, before any letter is typed. Not
  -- vim.lsp.completion's autotrigger: while a menu is up it re-asks the
  -- server and puts up the server's items alone, over 'autocomplete's
  -- merged menu. This only asks on the character itself; letters after it
  -- are 'autocomplete's again. Not on characters that are something else's:
  -- ( and , bring up the signature, / a path, and quotes and spaces would
  -- open a menu on every string and word.
  local notTriggers = { ["("] = true, [")"] = true, [","] = true, ["/"] = true,
                        ["'"] = true, ['"'] = true, [" "] = true, ["\t"] = true }
  vim.api.nvim_create_autocmd("InsertCharPre", {
    callback = function()
      local char = vim.v.char
      if notTriggers[char] or vim.fn.pumvisible() == 1 then return end
      for _, c in ipairs(vim.lsp.get_clients({ bufnr = 0, method = "textDocument/completion" })) do
        local tc = vim.tbl_get(c.server_capabilities, "completionProvider", "triggerCharacters") or {}
        if vim.tbl_contains(tc, char) then
          vim.schedule(function()
            if vim.api.nvim_get_mode().mode:sub(1, 1) == "i" then pcall(vim.lsp.completion.get) end
          end)
          return
        end
      end
    end,
  })
  -- <C-Space>: the menu on demand — on a blank, after a space, mid-word —
  -- from the same sources the menu as-you-type uses ('complete'), nothing
  -- picked yet ('completeopt' noselect). Again closes it.
  vim.keymap.set("i", "<C-Space>", function()
    return vim.fn.pumvisible() == 1 and "<C-e>" or "<C-n>"
  end, { expr = true, desc = "Completion menu" })
  -- signature help as a call is typed: after "(" and ",", as mini.completion
  -- used to show it
  vim.api.nvim_create_autocmd("InsertCharPre", {
    callback = function()
      if vim.v.char ~= "(" and vim.v.char ~= "," then return end
      if #vim.lsp.get_clients({ bufnr = 0, method = "textDocument/signatureHelp" }) == 0 then return end
      vim.schedule(function()
        pcall(vim.lsp.buf.signature_help, { focusable = false, silent = true })
      end)
    end,
  })
end

-- ── language servers ───────────────────────────────────────────────────
-- Each enabled only if its program is on the PATH, so the list can name more
-- than this machine has. Configurations come from nvim-lspconfig.
function M.lsp()
  -- qmlls goes by more than one name: `qmlls` in Qt's own bin, `qmlls6` as
  -- Arch puts it on the PATH. And its project root is where .qmlls.ini is —
  -- which quickshell fills with its own import paths — or failing that the
  -- directory holding shell.qml, not the nearest .git.
  local qmlls
  for _, c in ipairs({ "qmlls", "qmlls6", "/usr/lib/qt6/bin/qmlls" }) do
    if vim.fn.executable(c) == 1 then qmlls = c; break end
  end
  if qmlls then
    pcall(vim.lsp.config, "qmlls", {
      cmd = { qmlls },
      root_markers = { ".qmlls.ini", "shell.qml", ".git" },
    })
  end

  local candidates = {
    "qmlls", "rust_analyzer", "lua_ls", "clangd", "gopls", "basedpyright",
    "ruff", "ts_ls", "bashls", "jsonls", "yamlls", "taplo", "marksman",
    "html", "cssls",
  }
  for _, name in ipairs(candidates) do
    local ok, cfg = pcall(function() return vim.lsp.config[name] end)
    local cmd = ok and cfg and cfg.cmd
    local exe = type(cmd) == "table" and cmd[1] or nil
    if exe and vim.fn.executable(exe) == 1 then vim.lsp.enable(name) end
  end
end

return M
