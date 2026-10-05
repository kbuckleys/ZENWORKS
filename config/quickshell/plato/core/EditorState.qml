// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// What the editor window is showing, as plain properties. The view binds to
// this and nothing else: it never sees a message from nvim, only the state
// the messages left behind.
//
// ROWS ARE PATCHED, NOT REPLACED. A frame names only the rows that changed,
// and a row nvim did not resend stays the very same object — which is how a
// window tells what to redraw: a keystroke re-draws one line and leaves the
// rest of the screen alone (see WindowView).
//
// NOT A ListModel. A row carries lists (its colour spans, its sign) and a
// ListModel turns every nested list into a ListModel of its own, which is
// both slow and awkward to read back. Rows are kept as the plain objects
// nvim sent, and each row item pulls its own when told it changed.

import QtQuick

QtObject {
  id: state

  // ── the screen ─────────────────────────────────────────────────────
  // nvim's grid, in cells, and the windows laid out on it — splits and all,
  // each where nvim put it: { id, row, col, width, height, textoff, current }
  property int gridRows: 0
  property int gridCols: 0
  property var wins: []
  // THE WINDOWS' IDS ALONE, for what draws one item per window (EditorView's
  // windows). `wins` is replaced whenever any window's size or place
  // changes, and a Repeater over it destroyed and rebuilt every window —
  // its rows, its glide, and its current-line bar, which came back at the
  // top and slid down to the cursor: the bar jumping when the tree went in
  // or out. This changes only when a window opens or closes; where each one
  // is comes from winOf, which follows `wins`.
  property var winIds: []
  function winOf(id) {
    for (let i = 0; i < state.wins.length; ++i) if (state.wins[i].id === id) return state.wins[i];
    return null;
  }
  // per window: its rows (as view.lua describes them: n, k, t, s, g, f), which
  // visible LINE each row belongs to (what relative numbers count in), and
  // where its cursor is. Kept out of `wins` so a keystroke does not rebuild
  // every window's items.
  property var _rows: ({})
  property var _ords: ({})
  property var _cursors: ({})
  property var _scroll: ({})
  property var _edges: ({})
  function scrollOf(win) { return state._scroll[win] || { top: 1, lines: 1, rnu: true }; }
  // bumped after every frame: what per-window bindings (cursor, ordinals)
  // hang off, since the maps above do not notify
  property int frame: 0

  function rowsOf(win) { return state._rows[win] || []; }
  // a window's rows past its top and bottom edges, for the frost under the
  // bars: { above, below } (see view.lua's margin)
  function edgesOf(win) { return state._edges[win] || { above: [], below: [] }; }
  function ordsOf(win) { return state._ords[win] || []; }
  function cursorOf(win) { return state._cursors[win] || { row: 0, col: 0 }; }

  // the window the editor's cursor is in, and that cursor in grid cells
  readonly property var curWin: {
    for (let i = 0; i < state.wins.length; ++i) if (state.wins[i].current) return state.wins[i];
    return null;
  }

  // style id → { fg, bg, sp, b, i, s, u, c }, from the frames that define them
  property var styles: ({})
  // every style changed meaning (a new colourscheme): every row redraws
  signal stylesReset()

  // the UI's own colours, from nvim's highlight groups
  property color normalFg: "#dfdfdd"
  property color cursorLineBg: "#20242a"
  property color lineNrFg: "#6a707f"
  property color cursorLineNrFg: "#fab387"
  // the colour the cursor's line number is drawn in: the settings' choice
  // (PlatoWindow), nvim's CursorLineNr when nothing sets it
  property color numberHere: state.cursorLineNrFg
  // the selection's colour, and how strongly it washes over the text
  property color visualInk: "#c8a4e0"
  property real visualAlpha: 0.32

  // ── floats and the completion menu ─────────────────────────────────
  // nvim's floating windows — hover, signature help, completion's docs —
  // each as { id, row, col, width, height, z, rows, cursor? }: see view.lua
  property var floats: []
  // the cursor is in one of them (K K), not in the editor's rows
  property bool inFloat: false

  // the open buffers, which are the tabs: { id, name, path, modified, current }
  property var buffers: []
  // whether nvim has said which they are yet: an empty list before it has is
  // not "nothing open" (PlatoManager.holding)
  property bool buffersKnown: false
  // THE TABS' ORDER IS PLATO'S. nvim keeps buffers in the order they were
  // made and cannot be told otherwise, and a tab strip you can drag to
  // rearrange must keep the order you left it in. So: buffer ids, new ones
  // at the end, closed ones dropped, and `tabs` is the buffers in this order.
  property var tabOrder: []
  readonly property var tabs: {
    const byId = {};
    for (const b of state.buffers) byId[b.id] = b;
    return state.tabOrder.map((id) => byId[id]).filter((b) => b !== undefined);
  }
  function moveTab(from, to) {
    if (from === to || from < 0 || to < 0) return;
    const o = state.tabOrder.slice();
    const [id] = o.splice(from, 1);
    o.splice(to, 0, id);
    state.tabOrder = o;
  }
  // tabs to be put at a place in the strip once nvim has them (files dropped
  // on it): { ids, at }
  property var _placing: null
  function placeTabs(ids, at) {
    state._placing = { ids: ids, at: at };
    state._place();
  }
  function _place() {
    const p = state._placing;
    if (!p) return;
    const o = state.tabOrder.slice();
    if (!p.ids.every((id) => o.indexOf(id) >= 0)) return;
    state._placing = null;
    const rest = o.filter((id) => p.ids.indexOf(id) < 0);
    const at = Math.max(0, Math.min(rest.length, p.at));
    rest.splice(at, 0, ...p.ids);
    state.tabOrder = rest;
  }
  // the tab `step` along from the current one, wrapping — for <C-Tab>
  function tabAfter(step) {
    const t = state.tabs;
    if (t.length < 2) return null;
    let i = t.findIndex((b) => b.current);
    if (i < 0) i = 0;
    return t[(i + step + t.length) % t.length];
  }

  property bool pumShown: false
  property var pumItems: []
  property int pumSelected: -1
  property int pumRow: 0
  property int pumCol: 0
  // the menu belongs to the command line (wildmenu), not to the text:
  // pumCol is then a byte in the command, and the status bar draws it
  property bool pumCmdline: false

  // ── the cursor and the buffer ──────────────────────────────────────
  property int cursorRow: 0
  property int cursorCol: 0
  // the cursor's character in its row's text: cursorCol counts cells, and a
  // wide character before it makes the two differ
  property int cursorChar: 0
  property int line: 1
  property int column: 1
  property int lines: 1
  property string mode: "n"
  property bool blocking: false
  property bool wrap: true
  property string file: ""
  property string filetype: ""
  property bool modified: false
  property bool readonly: false
  // { current, total, incomplete } while a search is lit or typed, else null
  property var search: null
  // the scrollbar's marks for the editor window: [[line, kind], ...] — kind
  // "e" "w" "i" "h" a diagnostic, "s" a search match, "a" "c" "d" git
  property var marks: []
  // sticky scroll for the editor window: [{ n, chunks: [[text, fg, bold]] }]
  property var context: []
  // the minimap's text: { first, total, lines: [[[col, len, fg], ...], ...] }
  property var minimap: null
  function applyMinimap(ev) {
    state.minimap = { first: ev.first, total: ev.total,
      lines: state._list(ev.lines).map((l) => state._list(l)) };
  }
  // zen mode: the cursor's paragraph, [first, last] buffer lines, or null
  property var para: null
  // the indent guide of the block the cursor is in: { col, first, last },
  // or null (view.lua's scope)
  property var scope: null
  // a search jump landed on a match: { row, col, len, win } in that
  // window's cells, for one frame — WindowView pulses an outline round it
  signal pulsed(var hit)
  // how many cursors (multicursor.nvim): more than one shows in the status bar
  property int cursors: 1

  // ── the status line's facts (status.lua) ───────────────────────────
  // { rec, pending, op, sel?, diag: {e,w,i,h}, lsp: {names, busy?},
  //   branch, diff?: {a,c,d}, indent: {tabs, width}, eol, enc } — sent when
  // they change, and kept until they do
  property var status: ({ rec: "", pending: "", op: false, diag: { e: 0, w: 0, i: 0, h: 0 },
    lsp: { names: [] }, branch: "", indent: { tabs: false, width: 4 }, eol: "unix", enc: "utf-8" })

  // THE KEYS OF A COMMAND NOT FINISHED YET — "2d", "\"a", "g", "<C-w>".
  // A frame carries nvim's own word for them (showcmd), but between the keys
  // of one command nvim sends no frame at all: it is reading the next key
  // and runs nothing else. So the keys this window sent since the last frame
  // are kept too, and shown if no frame has come for them by the time a
  // frame would have (80 ms) — the frame that does come puts it right.
  property string pending: ""
  property string _framePending: ""
  property string _tail: ""
  property Timer _tailTimer: Timer {
    interval: 80
    onTriggered: state.pending = state._framePending + state._tail
  }
  function keysSent(keys) {
    const m = state.mode;
    // typing text is not a command half done
    if (!(m === "n" || m.startsWith("no") || m === "v" || m === "V" || m === "\u0016")) return;
    state._tail += String(keys).replace(/<lt>/g, "<");
    state._tailTimer.restart();
  }

  // the command line, while one is open — ":" and "/" and "?"
  property bool cmdlineShown: false
  property string cmdlineText: ""
  property string cmdlineFirstc: ""
  property string cmdlinePrompt: ""
  property int cmdlinePos: 0

  // "normal", "insert", "visual", "replace", "command": what the mode reads as
  readonly property string modeName: {
    const m = state.mode;
    if (m.startsWith("i")) return "insert";
    if (m.startsWith("R")) return "replace";
    if (m === "v" || m === "V" || m === "\u0016" || m.startsWith("s") || m === "S")
      return "visual";
    if (m.startsWith("c")) return "command";
    if (m.startsWith("t")) return "terminal";
    return "normal";
  }

  // A LIST, WHATEVER SHAPE IT ARRIVES IN. A frame passes through a `var`
  // signal on its way here, and since Qt 6.12 a list comes out of one as a
  // sequence that is not an Array: Array.isArray said no, and the tabs, the
  // floats and the completion menu were all thrown away as "not a list". A
  // Lua table that was empty arrives as {} (no length) and means none.
  function _list(x) {
    if (!x || typeof x !== "object" || typeof x.length !== "number") return [];
    return Array.from(x);
  }

  function _defineStyles(list) {
    if (!list) return;
    for (let k = 0; k < list.length; ++k) state.styles[list[k].id] = list[k];
  }

  function applyTheme(ev) {
    if (ev.reset) state.styles = ({});
    state._defineStyles(ev.styles);
    const ui = ev.ui || {};
    if (ui.normal) state.normalFg = ui.normal;
    if (ui.cursorline) state.cursorLineBg = ui.cursorline;
    if (ui.linenr) state.lineNrFg = ui.linenr;
    if (ui.cursorlinenr) state.cursorLineNrFg = ui.cursorlinenr;
    if (ui.visual) state.visualInk = ui.visual;
    if (ui.visualAlpha) state.visualAlpha = ui.visualAlpha;
    state.stylesReset();
  }

  function applyView(ev) {
    // styles first: the rows below may use the ones this frame defines
    state._defineStyles(ev.styles);
    state.gridRows = ev.grid.rows;
    state.gridCols = ev.grid.cols;

    const layout = [];
    const live = {};
    for (let k = 0; k < ev.wins.length; ++k) {
      const w = ev.wins[k];
      live[w.id] = true;
      let rows = state._rows[w.id];
      if (w.full || !rows || rows.length !== w.height) {
        const fresh = new Array(w.height);
        for (let i = 0; i < w.height; ++i)
          fresh[i] = (rows && rows[i]) || { n: 0, k: 0, t: "", s: [], f: false };
        rows = fresh;
      }
      for (let j = 0; j < w.rows.length; ++j) rows[w.rows[j].i] = w.rows[j];
      state._rows[w.id] = rows;
      // ordinals change with any row's n or k, so they are simply recounted
      const ord = new Array(rows.length);
      let o = -1;
      for (let i = 0; i < rows.length; ++i) { if (rows[i].k === 0) o++; ord[i] = o; }
      state._ords[w.id] = ord;
      state._cursors[w.id] = w.cursor;
      layout.push({ id: w.id, row: w.row, col: w.col, width: w.width, height: w.height,
                    textoff: w.textoff, current: w.current });
      // where it is scrolled to, apart from the layout: scrolling is not a
      // new layout, and must not rebuild the window's items
      state._scroll[w.id] = { top: w.top, lines: w.lines, rnu: w.rnu !== false, buf: w.buf };
      // the rows just past its edges (view.lua's margin), when they changed
      // NOT Array.isArray: the frame reaches here through NvimClient's
      // `view` signal, which turns its arrays into QML sequences — they
      // index and have a length, and Array.isArray says no to every one of
      // them, which threw the edge rows away (the frost stayed empty after
      // every tab switch)
      if (w.above !== undefined || w.below !== undefined)
        state._edges[w.id] = { above: w.above ? Array.from(w.above) : [],
                               below: w.below ? Array.from(w.below) : [] };
    }
    for (const id in state._rows) if (!live[id]) {
      delete state._rows[id]; delete state._ords[id]; delete state._cursors[id];
      delete state._scroll[id];
      delete state._edges[id];
    }
    // the layout is replaced only when it changed: replacing it rebuilds
    // every window's items, which a keystroke must not do
    if (JSON.stringify(layout) !== JSON.stringify(state.wins)) state.wins = layout;
    const ids = layout.map((w) => w.id);
    if (ids.join(",") !== state.winIds.join(",")) state.winIds = ids;

    // absent: as they were. An empty table from Lua can arrive as {} rather
    // than [], so anything not a list means none.
    if (ev.floats !== undefined && ev.floats !== null)
      state.floats = state._list(ev.floats);
    if (ev.buffers !== undefined && ev.buffers !== null) {
      state.buffers = state._list(ev.buffers);
      state.buffersKnown = true;
      const live = state.buffers.map((b) => b.id);
      const kept = state.tabOrder.filter((id) => live.indexOf(id) >= 0);
      for (const id of live) if (kept.indexOf(id) < 0) kept.push(id);
      if (JSON.stringify(kept) !== JSON.stringify(state.tabOrder)) state.tabOrder = kept;
      state._place();
    }
    state.inFloat = ev.inFloat === true;

    const c = state.curWin ? state.cursorOf(state.curWin.id) : { row: 0, col: 0 };
    state.cursorRow = c.row;
    state.cursorCol = c.col;
    state.cursorChar = c.ch !== undefined ? c.ch : c.col;
    state.line = ev.line;
    state.column = ev.column;
    state.lines = ev.lines;
    state.mode = ev.mode;
    state.blocking = ev.blocking;
    state.wrap = ev.wrap;
    state.file = ev.file;
    state.filetype = ev.filetype;
    state.modified = ev.modified;
    state.readonly = ev.readonly;
    state.search = ev.search || null;
    if (ev.marks !== undefined && ev.marks !== null) state.marks = state._list(ev.marks);
    if (ev.context !== undefined && ev.context !== null) state.context = state._list(ev.context);
    state.para = ev.para ? state._list(ev.para) : null;
    state.scope = ev.scope || null;
    state.cursors = ev.cursors || 1;
    if (ev.status) state.status = ev.status;
    state._framePending = state.status.pending || "";
    state._tail = "";
    state._tailTimer.stop();
    state.pending = state._framePending;
    // the command line rides on the frame (see view.lua): open while one is
    // there, closed once the frame says none and nvim has left it
    if (ev.cmdline) state.applyCmdline(Object.assign({ shown: true }, ev.cmdline));
    else if (state.cmdlineShown && !String(ev.mode).startsWith("c")) state.cmdlineShown = false;
    state.frame++;
    if (ev.pulse) state.pulsed(ev.pulse);
  }

  function applyPum(ev) {
    state.pumShown = ev.shown;
    if (!ev.shown) return;
    state.pumItems = state._list(ev.items);
    state.pumSelected = ev.selected;
    state.pumRow = ev.row;
    state.pumCol = ev.col;
    state.pumCmdline = ev.cmdline === true;
  }

  function applyCmdline(ev) {
    state.cmdlineShown = ev.shown;
    if (!ev.shown) return;
    state.cmdlineText = ev.text || "";
    state.cmdlineFirstc = ev.firstc || "";
    state.cmdlinePrompt = ev.prompt || "";
    state.cmdlinePos = ev.pos || 0;
  }
}
