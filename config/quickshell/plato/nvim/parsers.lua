-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/
--
-- Plato's treesitter parsers, built in an nvim of their own (as pack.lua is).
--
--   NVIM_APPNAME=quickshell/plato/nvim nvim --headless -i NONE --clean \
--     -c "luafile parsers.lua"
--     PLATO_PARSERS=list [PLATO_PARSERS_FT=qml]   every language there is a
--                                    parser for, as one line of JSON
--     PLATO_PARSERS=install PLATO_PARSERS_NAMES=qmljs,bash
--     PLATO_PARSERS=remove  PLATO_PARSERS_NAMES=qmljs
--
-- NO tree-sitter CLI NEEDED. nvim-treesitter (a core plugin, here for its
-- queries) pins every grammar it knows: a repository and a revision. Nearly
-- all of them ship their generated parser.c, so a parser is that revision
-- fetched with git and compiled with the C compiler — the CLI is only
-- wanted for the handful that must be generated from their grammar, and
-- those say so rather than fail halfway.
--
-- Built into ~/.local/share/quickshell/plato/nvim/site/parser/<lang>.so,
-- which nvim finds on its own; the revision built goes beside it in
-- parser-info/, so the list can say which are behind their pin. Replaced by
-- a rename, never written in place: an engine that has the old one loaded
-- keeps reading the file it opened.
--
-- Output: list → "JSON {…}"; install/remove → "OK <lang>" or
-- "FAIL <lang> <why>" per language, then "DONE".

local function out(s) io.stdout:write(s .. "\n") end

local data = vim.fn.stdpath("data")
local parserDir = data .. "/site/parser"
local infoDir = data .. "/site/parser-info"
local tsDir = data .. "/site/pack/core/opt/nvim-treesitter"

local okp, registry = pcall(dofile, tsDir .. "/lua/nvim-treesitter/parsers.lua")
if not okp or type(registry) ~= "table" then
  out("ERROR nvim-treesitter is not installed yet: open plato once so its plugins arrive")
  vim.cmd("qall!")
  return
end
-- the filetypes each language is for (nvim-treesitter registers them)
pcall(dofile, tsDir .. "/plugin/filetypes.lua")

local function exists(p) return vim.uv.fs_stat(p) ~= nil end
local function readFirst(p)
  local f = io.open(p, "r")
  if not f then return "" end
  local s = f:read("*l") or ""
  f:close()
  return vim.trim(s)
end

local function bundled()
  local set = {}
  for _, f in ipairs(vim.fn.globpath(vim.env.VIMRUNTIME, "parser/*.so", false, true)) do
    set[vim.fn.fnamemodify(f, ":t:r")] = true
  end
  return set
end

local function run(cmd, opts)
  local r = vim.system(cmd, vim.tbl_extend("force", { text = true }, opts or {})):wait(300000)
  if r.code ~= 0 then
    local why = vim.trim((r.stderr ~= "" and r.stderr) or r.stdout or "")
    return false, (why:gsub("\n.*", ""))
  end
  return true
end

-- ── list ───────────────────────────────────────────────────────────────
local function list()
  local b = bundled()
  local langs = {}
  for lang, spec in pairs(registry) do
    local info = spec.install_info
    if info then
      local have = exists(parserDir .. "/" .. lang .. ".so")
      langs[#langs + 1] = {
        lang = lang,
        installed = have,
        bundled = b[lang] == true,
        revision = info.revision or "",
        built = have and readFirst(infoDir .. "/" .. lang .. ".revision") or "",
        generate = info.generate == true,
        tier = spec.tier or 0,
        requires = spec.requires or {},
      }
    end
  end
  table.sort(langs, function(x, y) return x.lang < y.lang end)
  local want = ""
  local ft = vim.env.PLATO_PARSERS_FT or ""
  if ft ~= "" then want = vim.treesitter.language.get_lang(ft) or ft end
  out("JSON " .. vim.json.encode({ langs = langs, want = want,
    cli = vim.fn.executable("tree-sitter") == 1,
    cc = vim.fn.executable("cc") == 1 }))
end

-- ── install ────────────────────────────────────────────────────────────
local function build(lang)
  local spec = registry[lang]
  local info = spec and spec.install_info
  if not info then return false, "no parser is known for " .. lang end
  if vim.fn.executable("cc") ~= 1 then return false, "no C compiler (cc) on the PATH" end
  local tmp = vim.fn.tempname() .. "-" .. lang
  vim.fn.mkdir(tmp, "p")
  local function done(ok, why)
    vim.fn.delete(tmp, "rf")
    return ok, why
  end
  -- the pinned revision, and only that: a shallow fetch of one commit
  local ok, why = run({ "git", "init", "-q", tmp })
  if ok then ok, why = run({ "git", "-C", tmp, "fetch", "-q", "--depth", "1", info.url, info.revision or info.branch or "HEAD" }) end
  if ok then ok, why = run({ "git", "-C", tmp, "checkout", "-q", "FETCH_HEAD" }) end
  if not ok then return done(false, "fetch: " .. (why or "")) end
  local root = info.location and (tmp .. "/" .. info.location) or tmp
  if info.generate then
    if vim.fn.executable("tree-sitter") ~= 1 then
      return done(false, "has to be generated from its grammar, which needs the tree-sitter CLI")
    end
    ok, why = run({ "tree-sitter", "generate" }, { cwd = root })
    if not ok then return done(false, "generate: " .. (why or "")) end
  end
  local src = root .. "/src"
  if not exists(src .. "/parser.c") then return done(false, "no src/parser.c in the grammar") end
  local objs, cxx = {}, false
  local function compile(file, compiler)
    local o = file:gsub("%.[^.]+$", ".o")
    local args = { compiler, "-c", "-fPIC", "-O2", "-I", src, file, "-o", o }
    local okc, w = run(args)
    if not okc then return false, w end
    objs[#objs + 1] = o
    return true
  end
  ok, why = compile(src .. "/parser.c", "cc")
  if ok and exists(src .. "/scanner.c") then ok, why = compile(src .. "/scanner.c", "cc") end
  if ok and exists(src .. "/scanner.cc") then
    if vim.fn.executable("c++") ~= 1 then return done(false, "its scanner is C++, and there is no c++") end
    cxx = true
    ok, why = compile(src .. "/scanner.cc", "c++")
  end
  if not ok then return done(false, "compile: " .. (why or "")) end
  vim.fn.mkdir(parserDir, "p")
  vim.fn.mkdir(infoDir, "p")
  local so = parserDir .. "/" .. lang .. ".so"
  local link = vim.list_extend({ cxx and "c++" or "cc", "-shared", "-o", so .. ".new" }, objs)
  ok, why = run(link)
  if not ok then return done(false, "link: " .. (why or "")) end
  local okr, err = os.rename(so .. ".new", so)
  if not okr then return done(false, tostring(err)) end
  local f = io.open(infoDir .. "/" .. lang .. ".revision", "w")
  if f then f:write((info.revision or "") .. "\n"); f:close() end
  return done(true)
end

local function names()
  local list = {}
  for n in (vim.env.PLATO_PARSERS_NAMES or ""):gmatch("[^,%s]+") do list[#list + 1] = n end
  return list
end

local mode = vim.env.PLATO_PARSERS or "list"
if mode == "list" then
  list()
elseif mode == "install" then
  -- what each asks for first (a language built on another), and only once
  local order, seen = {}, {}
  local function add(lang)
    if seen[lang] then return end
    seen[lang] = true
    local spec = registry[lang]
    for _, r in ipairs(spec and spec.requires or {}) do
      if registry[r] and registry[r].install_info and not exists(parserDir .. "/" .. r .. ".so") then add(r) end
    end
    order[#order + 1] = lang
  end
  for _, n in ipairs(names()) do add(n) end
  for _, lang in ipairs(order) do
    out("BUILDING " .. lang)
    local ok, why = build(lang)
    if ok then out("OK " .. lang) else out("FAIL " .. lang .. " " .. tostring(why)) end
  end
elseif mode == "remove" then
  for _, lang in ipairs(names()) do
    vim.fn.delete(parserDir .. "/" .. lang .. ".so")
    vim.fn.delete(infoDir .. "/" .. lang .. ".revision")
    out("OK " .. lang)
  end
end
out("DONE")
vim.cmd("qall!")
