// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// Plato's own actions: what the leader menu and the command palette offer.
//
// ONE LIST, TWO WAYS IN. Every action has a title and, if it is on the leader
// menu, a key sequence after <Space>. The menu walks the sequences; the
// palette searches the titles. Adding an action here adds it to both, the
// way terminus' `commands` feeds its own palette from its keymap.
//
// An action runs against a context the window hands in:
//   ctx.client   the NvimClient: cmd(), input(), openAt()
//   ctx.picker   open("files" | "buffers" | "grep" | "commands")
//   ctx.here()   the directory of the current file
//   ctx.exec(argv)          start a program, detached
//   ctx.choose(dir, save, reply)   terminus' open/save dialog
//   ctx.toggleTree()        the file tree: show and go to it, or put it away
//   ctx.toggleWrap()        the settings' "Wrap long lines", for every window
//   ctx.plugins()           the plugin manager (PluginPanel.qml)
//   ctx.settings()          plato's settings sheet (SettingsSheet.qml)
//   ctx.save(all)           :write — or, for a buffer with no file, the save
//                           dialog (and :wall)
//   ctx.peek()              the definition, in an editable card (peek.lua)
//   ctx.restoreTabs()       the project's other files, back (sessions.lua)
//   ctx.toggleZen()         zen mode, in this window
//   ctx.formatMenu()        the file's indentation and line endings, to change
//   ctx.lspMenu()           restart, stop, format, check the language servers
//   ctx.plugins(page)       the plugin manager, on a page: "parsers"
//   ctx.toggleSetting(key)  flip one of plato's on/off settings
//
// An action with no `keys` is in the palette only; `hint` is the key that
// does it elsewhere (| for the tree), shown beside it there.
//
// Kept to what is about EDITING or about getting to the file to edit. Git
// beyond fugitive's own commands, a terminal, a file manager: those are other
// programs' work, and the actions only hand over to them. The file tree is
// morpheus' FileTree, terminus' tree standing on its own.

.pragma library

// groups on the leader menu, by their key
const groups = {
  "l": "LSP",
  "g": "Git",
  "d": "Diagnostics & marks",
  "m": "Multiple cursors",
};

const list = [
  // ── getting to files ──────────────────────────────────────────────────
  { keys: "f", title: "Find file", run: (c) => c.picker.open("files") },
  { keys: "/", title: "Search in project", run: (c) => c.picker.open("grep") },
  { keys: "b", title: "Switch buffer", run: (c) => c.picker.open("buffers") },
  { keys: "p", title: "Command palette", run: (c) => c.picker.open("commands") },
  // Space Space: terminus' open dialog, at the current file's directory
  { keys: " ", title: "Open via file dialog…", run: (c) => c.choose(c.here(), false,
      (paths) => { if (paths.length) c.client.openAt(paths[0]); }) },
  { title: "File tree", hint: "|", run: (c) => c.toggleTree() },
  { keys: "E", title: "Show in file manager",
    run: (c) => c.exec(["qs", "ipc", "call", "Terminus", "open", c.here()]) },
  { keys: "t", title: "Terminal here",
    run: (c) => c.exec(["sh", "-c", "cd \"$1\" && exec xdg-terminal-exec", "sh", c.here()]) },

  // ── the buffer ────────────────────────────────────────────────────────
  { keys: "n", title: "New blank tab", run: (c) => c.client.cmd("enew") },
  { keys: "w", title: "Save", run: (c) => c.save(false) },
  { keys: "W", title: "Save all", run: (c) => c.save(true) },
  { keys: "S", title: "Save as…", run: (c) => c.choose(c.here(), true,
      (paths) => { if (paths.length) c.client.cmd(saveAsCmd(paths[0])); }) },
  { keys: "q", title: "Close buffer", run: (c) => c.client.cmd("bdelete") },
  // from the terminal nvim's leader binds
  { keys: "s", title: "Replace word under cursor",
    run: (c) => c.client.input(":%s/\\<<C-r><C-w>\\>/<C-r><C-w>/gI<Left><Left><Left>") },
  { keys: "X", title: "Make file executable", run: (c) => c.client.cmd("silent !chmod +x %") },
  { keys: "r", title: "Toggle wrap", run: (c) => c.toggleWrap() },
  { keys: "R", title: "Reopen this project's tabs", run: (c) => c.restoreTabs() },
  { keys: "y", title: "Paste from yank history", run: (c) => c.picker.open("yanks") },
  { keys: "h", title: "Undo history", run: (c) => c.picker.open("undo") },
  { keys: "a", title: "Pin / unpin this file", hint: "alt 1-9 to go", run: (c) => c.client.cmd("lua require('plato.pins').toggle()") },
  { keys: "A", title: "Pinned files", run: (c) => c.picker.open("pins") },
  { title: "Replace in project…", hint: "ctrl r in search", run: (c) => c.picker.open("grep") },
  { title: "Indentation and line endings…", run: (c) => c.formatMenu() },
  { title: "Language servers…", run: (c) => c.lspMenu() },
  { keys: "z", title: "Zen mode", run: (c) => c.toggleZen() },
  { title: "Typewriter scrolling in zen", run: (c) => c.toggleSetting("typewriter") },
  { title: "Indent guides", run: (c) => c.toggleSetting("indentGuides") },
  { keys: "k", title: "Spell check on / off", hint: "z= suggests",
    run: (c) => c.client.cmd("lua require('plato.spell').toggle()") },
  { keys: "U", title: "Plugins", run: (c) => c.plugins() },
  { title: "Language parsers (treesitter)", run: (c) => c.plugins("parsers") },
  { keys: ",", title: "Settings", hint: "ctrl ,", run: (c) => c.settings() },

  // ── LSP ───────────────────────────────────────────────────────────────
  { keys: "ld", title: "Go to definition", run: (c) => c.client.cmd("lua vim.lsp.buf.definition()") },
  { keys: "lp", title: "Peek definition", run: (c) => c.peek() },
  { keys: "lo", title: "Go to symbol", run: (c) => c.picker.open("symbols") },
  { keys: "lr", title: "Rename symbol", run: (c) => c.client.cmd("lua vim.lsp.buf.rename()") },
  { keys: "la", title: "Code action", run: (c) => c.client.cmd("lua vim.lsp.buf.code_action()") },
  { keys: "lf", title: "Format file", run: (c) => c.client.cmd("lua require('plato.editing').format()") },
  { keys: "lR", title: "References", run: (c) => c.client.cmd("lua require('plato.peek').references()") },
  { keys: "lh", title: "Hover", run: (c) => c.client.cmd("lua vim.lsp.buf.hover()") },
  { keys: "ls", title: "Signature help", run: (c) => c.client.cmd("lua vim.lsp.buf.signature_help()") },
  { keys: "li", title: "Language servers", run: (c) => c.client.cmd("checkhealth vim.lsp") },

  // ── git, through fugitive ─────────────────────────────────────────────
  { keys: "gs", title: "Git status", run: (c) => c.client.cmd("Git") },
  { keys: "gb", title: "Git blame", run: (c) => c.client.cmd("Git blame") },
  { keys: "gl", title: "Git log", run: (c) => c.client.cmd("Git log --oneline") },

  // ── several cursors (multicursor.nvim; see its config file) ──────────
  { keys: "mn", title: "Add cursor at next match", run: (c) => c.client.cmd("lua require('multicursor-nvim').matchAddCursor(1)") },
  { keys: "mN", title: "Add cursor at previous match", run: (c) => c.client.cmd("lua require('multicursor-nvim').matchAddCursor(-1)") },
  { keys: "ms", title: "Skip this match", run: (c) => c.client.cmd("lua require('multicursor-nvim').matchSkipCursor(1)") },
  { keys: "ma", title: "Add cursors at every match", run: (c) => c.client.cmd("lua require('multicursor-nvim').matchAllAddCursors()") },
  { keys: "mj", title: "Add cursor below", run: (c) => c.client.cmd("lua require('multicursor-nvim').lineAddCursor(1)") },
  { keys: "mk", title: "Add cursor above", run: (c) => c.client.cmd("lua require('multicursor-nvim').lineAddCursor(-1)") },
  { keys: "mA", title: "Align cursors", run: (c) => c.client.cmd("lua require('multicursor-nvim').alignCursors()") },
  { keys: "mx", title: "Back to one cursor", run: (c) => c.client.cmd("lua require('multicursor-nvim').clearCursors()") },

  // ── diagnostics and marks ─────────────────────────────────────────────
  { keys: "dn", title: "Next diagnostic", run: (c) => c.client.cmd("lua vim.diagnostic.jump({ count = 1, float = true })") },
  { keys: "dp", title: "Previous diagnostic", run: (c) => c.client.cmd("lua vim.diagnostic.jump({ count = -1, float = true })") },
  { keys: "dl", title: "Diagnostic under cursor", run: (c) => c.client.cmd("lua vim.diagnostic.open_float()") },
  { keys: "dd", title: "All diagnostics", run: (c) => c.picker.open("diags") },
  // from the terminal nvim's leader binds
  { keys: "dm", title: "Delete a mark", run: (c) => c.client.input(":delmark ") },
  { keys: "da", title: "Delete all marks in file", run: (c) => c.client.cmd("delmarks!") },
];

// how a key sequence reads on a keycap: Space is a word, not a blank
function spell(keys) {
  return String(keys).split("").map((k) => k === " " ? "space" : k).join(" ");
}

function escape(path) { return String(path).replace(/([ \\%#|"])/g, "\\$1"); }

// Writing the buffer to a path picked in the save dialog. :saveas on a
// buffer with NO name leaves a listed [No Name] behind as the alternate
// file — a second tab out of nowhere — so an unnamed buffer is named
// (:file) and written instead; a named one is :saveas'd as before.
function saveAsCmd(path) {
  const p = escape(path);
  return "if bufname() ==# '' | file " + p + " | write | else | saveas " + p + " | endif";
}

function all() { return list; }

// What the leader menu shows after `prefix` has been typed: one entry per
// next key, either an action or a group to go into.
//   [{ key, title, group: bool, action }]
function next(prefix) {
  const seen = {};
  const out = [];
  for (let i = 0; i < list.length; ++i) {
    const a = list[i];
    if (!a.keys || a.keys.indexOf(prefix) !== 0 || a.keys.length === prefix.length) continue;
    const k = a.keys.charAt(prefix.length);
    if (seen[k]) continue;
    seen[k] = true;
    if (a.keys.length === prefix.length + 1) out.push({ key: k, title: a.title, group: false, action: a });
    else out.push({ key: k, title: groups[prefix + k] || (prefix + k), group: true, action: null });
  }
  // groups last, as which-key lays them out; each part in key order
  out.sort((x, y) => (x.group - y.group) || (x.key.toLowerCase() < y.key.toLowerCase() ? -1
    : x.key.toLowerCase() > y.key.toLowerCase() ? 1 : (x.key < y.key ? -1 : 1)));
  return out;
}
