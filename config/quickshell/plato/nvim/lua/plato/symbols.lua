-- ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
-- ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
-- └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
-- https://github.com/kbuckleys/
--
-- WHAT IS IN THE FILE: its functions, classes, objects and headings — for
-- the outline picker (Space l o) and the breadcrumb in the status line
-- (Settings › load).
--
-- FROM THE LANGUAGE SERVER when one is attached (textDocument/documentSymbol,
-- asked a moment after the text stops changing and kept per buffer). With
-- none — no lua_ls on this machine, a markdown note — from the text itself:
-- headings, and lines that read as definitions (function, def, class, fn,
-- struct, …), nested by heading level or by indent.
--
--   M.list(buf)          [{ name, kind, line, col, depth }] in file order
--   M.crumbs(buf, line)  the names of what `line` is inside, outermost first
--   M.trail(buf, line)   the same as { name, kind, line, col }, for the
--                        status line's clickable breadcrumb

local api = vim.api
local M = {}

local METHOD = "textDocument/documentSymbol"
local cache = {}      -- buf → { tick, tree, lsp }
local timers = {}

local kindName = {}
for name, n in pairs(vim.lsp.protocol.SymbolKind) do
  if type(n) == "number" then kindName[n] = name end
end

-- nodes: { name, kind, first, last, line, col, children } — lines 1-based
local function fromLsp(result)
  local out = {}
  local function walk(list, into)
    for _, s in ipairs(list or {}) do
      local r = s.range or (s.location and s.location.range)
      if r then
        local sel = s.selectionRange or r
        local node = { name = s.name, kind = kindName[s.kind] or "Symbol",
          first = r.start.line + 1, last = r["end"].line + 1,
          line = sel.start.line + 1, col = sel.start.character + 1, children = {} }
        into[#into + 1] = node
        walk(s.children, node.children)
      end
    end
  end
  walk(result, out)
  -- SymbolInformation (flat): nested by range, since it says nothing else
  local flat = true
  for _, n in ipairs(out) do if #n.children > 0 then flat = false; break end end
  if flat and #out > 1 then
    table.sort(out, function(a, b) return a.first < b.first or (a.first == b.first and a.last > b.last) end)
    local roots, stack = {}, {}
    for _, n in ipairs(out) do
      while #stack > 0 and stack[#stack].last < n.first do stack[#stack] = nil end
      if #stack > 0 then table.insert(stack[#stack].children, n) else roots[#roots + 1] = n end
      stack[#stack + 1] = n
    end
    return roots
  end
  return out
end

-- ── from the text ──────────────────────────────────────────────────────
local defs = {
  { "^%s*local%s+function%s+([%w_%.:]+)", "Function" },
  { "^%s*function%s+([%w_%.:]+)", "Function" },
  { "^%s*export%s+default%s+function%s*([%w_]*)", "Function" },
  { "^%s*export%s+async%s+function%s+([%w_]+)", "Function" },
  { "^%s*export%s+function%s+([%w_]+)", "Function" },
  { "^%s*async%s+function%s+([%w_]+)", "Function" },
  { "^%s*async%s+def%s+([%w_]+)", "Function" },
  { "^%s*def%s+([%w_]+)", "Function" },
  { "^%s*class%s+([%w_]+)", "Class" },
  { "^%s*export%s+class%s+([%w_]+)", "Class" },
  { "^%s*pub%s+fn%s+([%w_]+)", "Function" },
  { "^%s*fn%s+([%w_]+)", "Function" },
  { "^%s*func%s+([%w_%(%)%*%s]-[%w_]+)%s*%(", "Function" },
  { "^%s*pub%s+struct%s+([%w_]+)", "Struct" },
  { "^%s*struct%s+([%w_]+)", "Struct" },
  { "^%s*pub%s+enum%s+([%w_]+)", "Enum" },
  { "^%s*enum%s+([%w_]+)", "Enum" },
  { "^%s*trait%s+([%w_]+)", "Interface" },
  { "^%s*impl%s+([%w_<>%s]+)", "Class" },
  { "^%s*mod%s+([%w_]+)", "Module" },
  { "^%s*([%w_%-]+)%s*%(%)%s*{", "Function" },          -- sh: name() {
  { "^%s*([%w_]+)%s*=%s*function", "Function" },        -- js/lua: x = function
  { "^%s*([A-Z][%w_%.]*)%s*{%s*$", "Object" },           -- QML: Item {
}

local function indentOf(s, ts)
  local n = 0
  for c in s:match("^%s*"):gmatch(".") do n = c == "\t" and (n - n % ts + ts) or n + 1 end
  return n
end

local function fromText(buf)
  local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
  local ts = vim.bo[buf].tabstop
  local md = vim.bo[buf].filetype == "markdown"
  local flat = {}
  local fence = false
  for i, s in ipairs(lines) do
    if md then
      if s:match("^%s*```") or s:match("^%s*~~~") then fence = not fence end
      local hashes, title = s:match("^(#+)%s+(.-)%s*#*%s*$")
      if hashes and not fence then
        flat[#flat + 1] = { name = title, kind = "Heading", line = i, col = 1, level = #hashes }
      end
    else
      for _, d in ipairs(defs) do
        local name = s:match(d[1])
        if name then
          name = vim.trim(name)
          flat[#flat + 1] = { name = name ~= "" and name or "(anonymous)", kind = d[2],
            line = i, col = #s:match("^%s*") + 1, level = indentOf(s, ts) }
          break
        end
      end
    end
  end
  -- each runs to the line before the next of its own level or shallower
  for k, n in ipairs(flat) do
    n.first = n.line
    n.last = #lines
    for j = k + 1, #flat do
      if flat[j].level <= n.level then n.last = flat[j].line - 1; break end
    end
    n.children = {}
  end
  local roots, stack = {}, {}
  for _, n in ipairs(flat) do
    while #stack > 0 and stack[#stack].level >= n.level do stack[#stack] = nil end
    if #stack > 0 then table.insert(stack[#stack].children, n) else roots[#roots + 1] = n end
    stack[#stack + 1] = n
  end
  return roots
end

local function lspClient(buf)
  return #vim.lsp.get_clients({ bufnr = buf, method = METHOD }) > 0
end

local function params(buf)
  return { textDocument = vim.lsp.util.make_text_document_params(buf) }
end

local function firstResult(results)
  for _, r in pairs(results or {}) do
    if r.result and #r.result > 0 then return r.result end
  end
  return nil
end

-- asked again, without waiting for the answer
function M.refresh(buf)
  if not api.nvim_buf_is_valid(buf) or vim.b[buf].plato_large then return end
  local tick = api.nvim_buf_get_changedtick(buf)
  if not lspClient(buf) then
    cache[buf] = { tick = tick, tree = fromText(buf), lsp = false }
    require("plato.view").schedule()
    return
  end
  vim.lsp.buf_request_all(buf, METHOD, params(buf), function(results)
    if not api.nvim_buf_is_valid(buf) then return end
    local res = firstResult(results)
    cache[buf] = { tick = tick, tree = res and fromLsp(res) or fromText(buf), lsp = res ~= nil }
    vim.schedule(function() require("plato.view").schedule() end)
  end)
end

local function later(buf)
  timers[buf] = timers[buf] or vim.uv.new_timer()
  timers[buf]:start(600, 0, vim.schedule_wrap(function() M.refresh(buf) end))
end

-- the tree now: what the cache has if it is current, asked for (and waited
-- on, briefly) if not
local function tree(buf, wait)
  local c = cache[buf]
  local tick = api.nvim_buf_get_changedtick(buf)
  if c and c.tick == tick then return c.tree end
  if wait and lspClient(buf) then
    local res = firstResult(vim.lsp.buf_request_sync(buf, METHOD, params(buf), 1500))
    cache[buf] = { tick = tick, tree = res and fromLsp(res) or fromText(buf), lsp = res ~= nil }
    return cache[buf].tree
  end
  if wait then
    cache[buf] = { tick = tick, tree = fromText(buf), lsp = false }
    return cache[buf].tree
  end
  return c and c.tree or nil
end

function M.list(buf)
  buf = buf or api.nvim_get_current_buf()
  local out = {}
  local function walk(nodes, depth)
    for _, n in ipairs(nodes or {}) do
      out[#out + 1] = { name = n.name, kind = n.kind, line = n.line, col = n.col, depth = depth }
      walk(n.children, depth + 1)
    end
  end
  walk(tree(buf, true), 0)
  return out
end

function M.crumbs(buf, line)
  local out = {}
  for _, n in ipairs(M.trail(buf, line)) do out[#out + 1] = n.name end
  return out
end

function M.trail(buf, line)
  local t = tree(buf, false)
  if not t then return {} end
  local out = {}
  local nodes = t
  while nodes do
    local inside = nil
    for _, n in ipairs(nodes) do
      if line >= n.first and line <= n.last then inside = n end
    end
    if not inside then break end
    local name = inside.name:gsub("%s+", " ")
    if #name > 32 then name = name:sub(1, 31) .. "…" end
    out[#out + 1] = { name = name, kind = inside.kind, line = inside.line, col = inside.col }
    nodes = inside.children
    if #out >= 4 then break end
  end
  return out
end

function M.setup()
  local group = api.nvim_create_augroup("plato.symbols", { clear = true })
  api.nvim_create_autocmd({ "TextChanged", "InsertLeave", "BufEnter", "BufWritePost" }, {
    group = group,
    callback = function(ev)
      if vim.bo[ev.buf].buftype ~= "" then return end
      local c = cache[ev.buf]
      if c and c.tick == api.nvim_buf_get_changedtick(ev.buf) then return end
      later(ev.buf)
    end,
  })
  api.nvim_create_autocmd("LspAttach", {
    group = group, callback = function(ev) later(ev.buf) end })
  api.nvim_create_autocmd("BufWipeout", {
    group = group,
    callback = function(ev)
      cache[ev.buf] = nil
      if timers[ev.buf] then timers[ev.buf]:close(); timers[ev.buf] = nil end
    end,
  })
end

return M
