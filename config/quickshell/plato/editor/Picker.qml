// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// The picker: one fuzzy list, four things to pick from.
//
//   files      ARTEMIS. Its index (one walk of $HOME, kept in the shell's
//              cache), its ranking (fzf over that file, a few ms a keystroke),
//              its frecency (what you open, first), its rows (icons.js' glyph,
//              the path fitted and highlighted by artemis.js). Everything
//              artemis searches, files only — not the project alone: the file
//              you want is as often in another tree as in this one. Plato has
//              no finder of its own to drift from it. Without artemis (a
//              shell that has none) the project gets an index of its own,
//              built by the same artemis.js function.
//   grep       ripgrep over the project; a result opens at its line
//   buffers    the open buffers, ranked here
//   commands   plato's actions (see actions.js) and every ex command — what
//              you run most (and lately) first, from the window's `history`
//              (PlatoManager's usage)
//   refs       the language server's references to the word at the cursor,
//              handed in (openRefs), each previewed where it is
//   yanks      the yank history (editing.lua): Enter puts one after the
//              cursor
//   diags      every open buffer's diagnostics, worst first, each previewed
//              where it is (the status line's counts open it)
//   undo       the undo history (undo.lua), newest first, every branch of
//              it: the preview is what going back would change, as a diff
//   pins       the project's pinned files (pins.lua), on Alt 1-9; ctrl x
//              unpins one
//   menu       a short list of things to do, handed in (openMenu): what the
//              status line's indent and language-server parts offer
//
// grep can also REPLACE: ctrl r takes every match in the project (not just
// the 300 shown) into the quickfix list and puts :cdo s/…//g on the command
// line, previewed live as it is typed (bridge.lua projectReplace).
//
// The project is the current file's: nvim finds its root (the nearest .git,
// or this shell's own .qmlls.ini / shell.qml) — see `root` in bridge.lua.
//
// FILES ARE PREVIEWED, and so are grep's matches — from a few lines above
// the match, with its line lit. The list takes the top of the sheet and the file
// under the cursor is shown below it — through terminus' own preview
// (terminus.js previewCommand: plato's highlighter, plato/nvim/render.lua,
// in plato's colours; bat when that is not there), and a picture as a
// picture. Read a moment after the cursor settles, and kept for the next
// time it lands there.
//
// Keys: type to filter, ↑/↓ or <C-n>/<C-p> or <C-j>/<C-k> to move, Enter to
// take, Esc to leave. Nothing typed here reaches nvim.
//
// A TERMINUS SHEET (PlatoSheet): it hangs from the tab strip with terminus'
// palette rows under it — 30 pixels, its sliding cursor bar, key chips on
// the right — and the field to type in across its top.

import QtQuick
import Quickshell
import Quickshell.Io
import "../../morpheus"
import "../../terminus"
import "../../terminus/terminus.js" as Terminus
import "../../artemis/artemis.js" as Artemis
import "../../morpheus/icons.js" as Icons
import "actions.js" as Actions

PlatoSheet {
  id: picker

  required property var ed
  required property var client
  required property font face
  // what an action is run with — see actions.js
  property var ctx: null
  // artemis (its ArtemisPopup), for the files mode; null leaves space f with
  // an index of its own
  property var finder: null
  // the editor's face, for the preview
  property string codeFamily: Zenon.faceFixed
  // what the palette has been used for: PlatoManager's used() / usageScore()
  property var history: null

  signal closed()

  property string mode: ""
  property string root: ""
  property var results: []
  property int sel: 0
  property var nvimCommands: []

  shown: picker.mode !== ""
  onDismissed: picker.close()

  readonly property var titles: ({
    files: "Find file", grep: "Search in project",
    buffers: "Switch buffer", commands: "Command palette",
    yanks: "Paste from yank history", refs: "References",
    diags: "Diagnostics", undo: "Undo history", pins: "Pinned files",
    symbols: "Go to symbol",
  })
  // the rows of a "menu": [{ label, detail?, cmd? | run? }]
  property var menuRows: []
  property string menuTitle: ""
  property string menuGlyph: ""
  function openMenu(title, glyph, rows) {
    picker.menuTitle = title;
    picker.menuGlyph = glyph;
    picker.menuRows = rows;
    picker.open("menu");
  }
  property var nvimList: []
  property var nvimYanks: []

  function open(mode) {
    picker.mode = mode;
    picker.results = [];
    picker.sel = 0;
    input.text = "";
    input.forceActiveFocus();
    if (mode === "files") {
      picker.client.request("root", {}, (r) => {
        picker.root = r || "";
        picker.useIndexFor(picker.root);
        picker.refresh();
      });
    } else if (mode === "grep") {
      picker.client.request("root", {}, (r) => {
        picker.root = r || "";
        picker.refresh();
      });
    } else if (mode === "yanks") {
      picker.nvimYanks = [];
      picker.client.request("yanks", {}, (list) => {
        picker.nvimYanks = picker.ed._list(list);
        picker.refresh();
      });
    } else if (mode === "symbols") {
      // the file's outline (symbols.lua), for the file being edited
      picker.nvimList = [];
      picker.symbolsFile = picker.ed.file.replace(/^~/, picker.home);
      picker.client.request("symbols", {}, (list) => {
        picker.nvimList = picker.ed._list(list);
        picker.refresh();
      });
    } else if (mode === "diags" || mode === "undo" || mode === "pins") {
      picker.nvimList = [];
      const method = { diags: "diagnostics", undo: "undoList", pins: "pins" }[mode];
      picker.client.request(method, { all: true }, (list) => {
        picker.nvimList = picker.ed._list(list);
        picker.refresh();
      });
    } else if (mode === "commands") {
      picker.client.request("commands", {}, (list) => {
        picker.nvimCommands = picker.ed._list(list);
        picker.refresh();
      });
      picker.refresh();
    } else {
      picker.refresh();
    }
  }

  property string symbolsFile: ""
  // a symbol's kind, as one glyph: what runs, what holds, a heading
  function kindGlyph(k) {
    if (/Function|Method|Constructor/.test(k)) return "\u{F0295}";
    if (/Class|Struct|Object|Interface|Module|Namespace|Enum|Package/.test(k)) return "\u{F01A7}";
    if (k === "Heading") return "#";
    return "\u2022";
  }

  // a path as artemis shows it: home written as ~
  readonly property string home: Quickshell.env("HOME")
  function tidy(p) {
    return p.indexOf(picker.home + "/") === 0 ? "~" + p.slice(picker.home.length) : p;
  }

  // the references, as grep's rows: the line, then where it is
  property var refItems: []
  function openRefs(items) {
    picker.refItems = picker.ed._list(items).map((it) => ({
      label: it.text, path: it.path, line: it.line, col: it.col,
      detail: picker.tidy(it.path) + ":" + it.line,
    }));
    picker.open("refs");
  }

  function close() {
    picker.mode = "";
    search.running = false;
    picker.closed();
  }

  // ── ranking what is already here ───────────────────────────────────
  function rank(rows, hay, q) {
    q = q.toLowerCase();
    if (q === "") return rows;
    const scored = [];
    for (let i = 0; i < rows.length; ++i) {
      const sc = Terminus.fuzzyScore(hay(rows[i]).toLowerCase(), q);
      if (sc >= 0) scored.push({ r: rows[i], sc: sc, i: i });
    }
    scored.sort((a, b) => (b.sc - a.sc) || (a.i - b.i));
    return scored.map((x) => x.r);
  }

  // THE PALETTE REMEMBERS. Nothing typed: what you have run, most (and most
  // lately) first, then everything else in its usual order. Something
  // typed: the fuzzy rank, with a nudge for what you use — enough to break
  // a near tie, never to lift a poor match over a good one.
  function useKey(r) { return r.action ? "a:" + r.action.title : r.ex ? "x:" + r.ex : ""; }
  function byUse(rows, q) {
    const h = picker.history;
    if (!h) return rows;
    const scored = rows.map((r, i) => ({ r: r, i: i, u: h.usageScore(picker.useKey(r)) }));
    if (q === "") scored.sort((a, b) => (b.u - a.u) || (a.i - b.i));
    else scored.sort((a, b) => (a.i - Math.log2(1 + a.u) * 2) - (b.i - Math.log2(1 + b.u) * 2));
    return scored.map((x) => x.r);
  }

  function refresh() {
    const q = input.text;
    picker.sel = 0;
    if (picker.mode === "buffers") {
      const rows = picker.ed.buffers.map((b) => ({
        label: b.name, detail: b.path, mark: b.modified ? "\uEA73" : "", buf: b.id }));
      picker.results = picker.rank(rows, (r) => r.detail || r.label, q);
    } else if (picker.mode === "commands") {
      const own = Actions.all().map((a) => ({
        label: a.title, detail: a.keys ? "space " + Actions.spell(a.keys) : (a.hint || ""),
        action: a }));
      const ex = picker.nvimCommands.map((c) => ({ label: ":" + c, detail: "", ex: c }));
      picker.results = picker.byUse(picker.rank(own.concat(ex), (r) => r.label, q), q).slice(0, 300);
    } else if (picker.mode === "refs") {
      picker.results = picker.rank(picker.refItems, (r) => r.detail + " " + r.label, q);
    } else if (picker.mode === "yanks") {
      const rows = picker.nvimYanks.map((y, i) => {
        const first = String(y.text).split("\n")[0];
        return { label: first.trim() === "" ? "(blank)" : first.trim(),
                 detail: y.lines > 1 ? "+" + (y.lines - 1) + " more lines"
                   : y.regtype === "V" ? "whole line" : "",
                 yank: i + 1, text: y.text };
      });
      picker.results = picker.rank(rows, (r) => r.text, q);
    } else if (picker.mode === "diags") {
      const glyphs = ["", "\u{F0159}", "\u{F0026}", "\u{F02FC}", "\u{F0335}"];
      const rows = picker.nvimList.map((d) => ({
        label: d.text, sev: d.sev, glyph: glyphs[d.sev] || "",
        detail: picker.tidy(d.path) + ":" + d.line + (d.source ? "  " + d.source : ""),
        path: d.path, line: d.line, col: d.col }));
      picker.results = picker.rank(rows, (r) => r.label + " " + r.detail, q);
    } else if (picker.mode === "undo") {
      picker.results = picker.rank(picker.nvimList.map((u) => ({
        label: u.label, detail: u.detail, seq: u.seq, current: u.current })), (r) => r.label, q);
    } else if (picker.mode === "symbols") {
      // nothing typed: the outline, nested; something typed: the best first
      const rows = picker.nvimList.map((y) => ({
        label: (q === "" ? "    ".repeat(y.depth) : "") + y.name,
        name: y.name, glyph: picker.kindGlyph(y.kind),
        detail: y.kind.toLowerCase() + "  " + y.line,
        path: picker.symbolsFile, line: y.line, col: y.col }));
      picker.results = picker.rank(rows, (r) => r.name, q);
    } else if (picker.mode === "pins") {
      picker.results = picker.rank(picker.nvimList.map((p) => ({
        label: p.path.slice(p.path.lastIndexOf("/") + 1),
        detail: picker.tidy(p.path),
        key: "alt " + p.n, path: p.path })), (r) => r.detail, q);
    } else if (picker.mode === "menu") {
      picker.results = picker.rank(picker.menuRows, (r) => r.label, q);
    } else if (picker.mode === "files" || picker.mode === "grep") {
      searchDelay.interval = picker.mode === "grep" ? 120 : 30;
      searchDelay.restart();
    }
  }

  // ── which index ────────────────────────────────────────────────────
  // artemis' own, when it covers the project — and then artemis is asked to
  // walk it again, exactly as opening artemis does; the view refreshes when
  // the fresh index lands. Otherwise one of the project's own, in the shell's
  // cache, built by artemis' indexCommand.
  property string index: ""
  function hashOf(str) {
    let h = 5381;
    for (let i = 0; i < str.length; ++i) h = ((h * 33) ^ str.charCodeAt(i)) >>> 0;
    return h.toString(16);
  }
  // the scope files are searched in: artemis' whole index, or this project
  property string scope: ""
  function useIndexFor(root) {
    const f = picker.finder;
    if (f) {
      picker.index = f.indexPath;
      picker.scope = "files";
      f.reindex();
      return;
    }
    picker.scope = root;
    picker.index = Quickshell.cachePath("plato-index-" + picker.hashOf(root));
    ownIndex.command = ["sh", "-c", Artemis.indexCommand(root, picker.index)];
    ownIndex.running = true;
  }
  Process {
    id: ownIndex
    onExited: if (picker.mode === "files") picker.refresh()
  }
  Connections {
    target: picker.finder
    function onIndexedAtChanged() { if (picker.mode === "files") picker.refresh(); }
  }

  // ── asking artemis' index, and rg ──────────────────────────────────
  // One search at a time: a newer query stops the older one, and a reply
  // that arrives for a query that is no longer the current one is dropped.
  property int gen: 0
  Timer {
    id: searchDelay
    onTriggered: picker.runSearch()
  }
  function runSearch() {
    if (picker.root === "") return;
    const q = input.text.trim();
    if (picker.mode === "grep" && q.length < 2) { picker.results = []; return; }
    if (picker.mode === "files" && picker.index === "") return;
    picker.gen++;
    search.gen = picker.gen;
    search.query = q;
    search.running = false;
    search.command = picker.mode === "files"
      ? ["sh", "-c", q === ""
          ? Artemis.browseCommand(picker.index, false, picker.scope)
          : Artemis.filterCommand(picker.index, q, false, picker.scope)]
      : ["sh", "-c", "cd \"$1\" && rg --vimgrep --smart-case --hidden -g '!.git'"
          + " --max-columns 240 --max-columns-preview -- \"$2\" 2>/dev/null | head -n 300",
         "sh", picker.root, q];
    search.running = true;
  }
  Process {
    id: search
    property int gen: 0
    property string query: ""
    stdout: StdioCollector {
      id: found
      onStreamFinished: {
        if (search.gen !== picker.gen || !picker.shown) return;
        const lines = found.text.split("\n").filter((l) => l !== "");
        if (picker.mode === "files") {
          // Before anything is typed, what you open most in this project
          // comes first — artemis' frecency, which plato's opens feed too
          // (see accept) — and the rest of the project after it.
          // Paths come back absolute from the whole index and relative from a
          // project's; either way they are shown as artemis shows them, home
          // written as ~.
          let rows = Artemis.parseResults(lines.join("\n"))
            .map((r) => ({ path: r.path, preview: picker.tidy(r.path), isDir: false }));
          // Before anything is typed, what you open most comes first —
          // artemis' frecency, which plato's opens feed too (see accept).
          if (search.query === "" && picker.finder && picker.scope === "files") {
            const often = Artemis.freqRanked(picker.finder.freq, 400)
              .filter((r) => !r.isDir)
              .map((r) => ({ path: r.path, preview: picker.tidy(r.path), isDir: false }));
            const seen = new Set(often.map((r) => r.path));
            rows = often.concat(rows.filter((r) => !seen.has(r.path)));
          }
          picker.results = rows;
        } else {
          picker.results = lines.map((l) => {
            const m = l.match(/^(.*?):(\d+):(\d+):(.*)$/);
            if (!m) return null;
            return { label: m[4].trim(), detail: m[1] + ":" + m[2], path: m[1],
                     line: Number(m[2]), col: Number(m[3]) };
          }).filter((r) => r !== null);
        }
        picker.sel = 0;
      }
    }
  }

  // ── taking one ─────────────────────────────────────────────────────
  function accept() {
    const r = picker.results[picker.sel];
    const mode = picker.mode;
    picker.close();
    if (!r) return;
    if (mode === "files") {
      const abs = r.path.charAt(0) === "/" ? r.path : picker.root + "/" + r.path;
      picker.client.openAt(abs);
      // opened here counts in artemis too, and the other way round
      if (picker.finder) picker.finder.noteOpened(abs);
    }
    else if (mode === "grep") picker.client.openAt(picker.root + "/" + r.path, r.line, r.col);
    else if (mode === "buffers") picker.client.bufShow(r.buf);
    else if (mode === "refs" || mode === "diags") picker.client.openAt(r.path, r.line, r.col);
    else if (mode === "pins") picker.client.openAt(r.path);
    // the same file: the cursor goes there, and '' comes back
    else if (mode === "symbols") picker.client.cmd("normal! m'\ncall cursor(" + r.line + ", " + r.col + ")\nnormal! zz");
    else if (mode === "undo") picker.client.request("undoTo", { seq: r.seq });
    else if (mode === "menu") { if (r.run) r.run(); else if (r.cmd) picker.client.cmd(r.cmd); }
    else if (mode === "yanks") picker.client.request("putYank", { index: r.yank });
    else if (r.action) {
      if (picker.history) picker.history.used(picker.useKey(r));
      r.action.run(picker.ctx);
    }
    // an ex command may want arguments: it is put on the command line, not run
    else if (r.ex) {
      if (picker.history) picker.history.used(picker.useKey(r));
      picker.client.input(":" + r.ex + " ");
    }
  }

  // every match in the project, replaced: see the header, and bridge.lua
  function replaceAll() {
    const q = input.text.trim();
    if (picker.mode !== "grep" || q.length < 2) return;
    const root = picker.root;
    picker.close();
    picker.client.request("projectReplace", { root: root, query: q }, (r) => {
      if (!r || !r.cmd) return;
      picker.client.input(":" + r.cmd.replace(/</g, "<lt>") + "<Left>".repeat(r.back));
    });
  }
  function unpin() {
    const r = picker.results[picker.sel];
    if (picker.mode !== "pins" || !r) return;
    picker.client.request("unpin", { path: r.path }, () => picker.open("pins"));
  }

  // ── the sheet ──────────────────────────────────────────────────────
  FontMetrics { id: fm; font: picker.face }
  readonly property int pageRows: 14
  readonly property int fieldH: 46
  // files: a fixed list over the preview, so nothing jumps as results come
  readonly property bool previewing: picker.mode === "files" || picker.mode === "grep"
    || picker.mode === "refs" || picker.mode === "diags" || picker.mode === "undo"
    || picker.mode === "pins" || picker.mode === "symbols"
  readonly property real roomH: Math.max(320, picker.height - picker.fromTop - picker.footH - 40)
  readonly property int listRows: picker.previewing
    ? Math.max(4, Math.min(10, Math.floor((picker.roomH - picker.fieldH - 13) * 0.42 / picker.rowH)))
    : Math.max(1, Math.min(picker.pageRows, picker.results.length))
  readonly property real previewH: picker.previewing
    ? Math.max(140, picker.roomH - picker.fieldH - 13 - picker.listRows * picker.rowH - 1) : 0
  cardW: picker.previewing ? Math.min(900, Math.max(620, picker.width - 120)) : 620
  cardH: picker.fieldH + 1 + 12 + picker.listRows * picker.rowH
    + (picker.previewing ? picker.previewH + 1 : 0)
  foot: false

  readonly property string glyph: ({
    files: "󰈞", grep: "󰱼", buffers: "󰓩", commands: "󰘳", yanks: "\u{F018F}", refs: "\u{F0CDB}",
    diags: "\u{F0028}", undo: "\u{F02DA}", pins: "\u{F0403}", menu: picker.menuGlyph,
    symbols: "\u{F0295}",
  })[picker.mode] || ""

  // the field: what kind of search, and what is typed
  Item {
    id: head
    width: parent.width
    height: picker.fieldH
    Text {
      id: prompt
      x: 18
      anchors.verticalCenter: parent.verticalCenter
      font.family: Zenon.faceMono
      font.pixelSize: 17
      color: Zenon.cyan
      text: picker.glyph
    }
    TextInput {
      id: input
      anchors.left: prompt.right
      anchors.leftMargin: 12
      anchors.right: parent.right
      anchors.rightMargin: 18
      anchors.verticalCenter: parent.verticalCenter
      font.family: Zenon.face
      font.pixelSize: 16
      color: Zenon.white
      selectionColor: Qt.rgba(Zenon.magenta.r, Zenon.magenta.g, Zenon.magenta.b, 0.5)
      cursorDelegate: Caret { field: input }
      clip: true
      onTextChanged: if (picker.shown) picker.refresh()
      Keys.onPressed: (event) => {
        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
        const n = picker.results.length;
        if (event.key === Qt.Key_Escape) { picker.close(); event.accepted = true; }
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          picker.accept(); event.accepted = true;
        } else if (ctrl && event.key === Qt.Key_R && picker.mode === "grep") {
          picker.replaceAll(); event.accepted = true;
        } else if (ctrl && event.key === Qt.Key_X && picker.mode === "pins") {
          picker.unpin(); event.accepted = true;
        } else if (event.key === Qt.Key_Down || (ctrl && (event.key === Qt.Key_N || event.key === Qt.Key_J))) {
          if (n) picker.sel = (picker.sel + 1) % n;
          event.accepted = true;
        } else if (event.key === Qt.Key_Up || (ctrl && (event.key === Qt.Key_P || event.key === Qt.Key_K))) {
          if (n) picker.sel = (picker.sel - 1 + n) % n;
          event.accepted = true;
        }
      }
    }
    Text {
      visible: input.text === ""
      anchors.left: input.left
      anchors.verticalCenter: parent.verticalCenter
      font.family: Zenon.face
      font.pixelSize: 16
      color: Zenon.muted
      text: picker.mode === "menu" ? picker.menuTitle : (picker.titles[picker.mode] || "")
    }
  }
  Rectangle {
    id: headRule
    anchors.top: head.bottom
    width: parent.width
    height: 1
    color: Zenon.border
  }

  ListView {
    id: list
    anchors.top: headRule.bottom
    anchors.topMargin: 6
    anchors.left: parent.left
    anchors.right: parent.right
    height: picker.listRows * picker.rowH
    clip: true
    model: picker.results
    currentIndex: picker.sel
    boundsBehavior: Flickable.DragAndOvershootBounds
    boundsMovement: Flickable.FollowBoundsBehavior
    onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
    ElasticScroll { view: list }

    // terminus' cursor: one bar sliding under the rows
    SelectBar { view: list; index: picker.sel; rowH: picker.rowH }

    delegate: Item {
      id: item
      required property var modelData
      required property int index
      width: list.width
      height: picker.rowH

      // ── a file, as artemis draws one ──────────────────────────────
      // Its glyph from icons.js in the mono face, a touch larger than the
      // text; the path fitted (losing the middle, never the name) and the
      // query's letters picked out, both by artemis.js. The same row in both
      // places, because it is the same search.
      Text {
        visible: picker.mode === "files"
        x: 14
        anchors.verticalCenter: parent.verticalCenter
        width: 22
        horizontalAlignment: Text.AlignHCenter
        font.family: Zenon.faceMono
        font.pixelSize: 18
        color: Zenon.white
        text: {
          if (picker.mode !== "files") return "";
          const p = String(item.modelData.path || "");
          return Icons.glyphFor({ name: p.slice(p.lastIndexOf("/") + 1), isDir: false });
        }
      }
      Text {
        visible: picker.mode === "files"
        anchors.left: parent.left
        anchors.leftMargin: 14 + 22 + 10
        anchors.right: parent.right
        anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.RichText
        font.family: Zenon.face
        font.weight: 600
        font.pixelSize: 16
        color: Zenon.white
        text: {
          if (picker.mode !== "files") return "";
          const avail = Math.max(8, Math.floor(width / (16 * 0.55)));
          return Artemis.highlightedPreview(Artemis.fitPath(item.modelData.preview, avail),
            search.query);
        }
      }

      Text {
        id: label
        visible: picker.mode !== "files"
        anchors.left: parent.left
        anchors.leftMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, parent.width * 0.62)
        elide: Text.ElideRight
        textFormat: Text.PlainText
        // grep's results are code, and read as code
        font.family: picker.mode === "grep" || picker.mode === "yanks" || picker.mode === "refs" ? picker.face.family : Zenon.face
        font.pixelSize: picker.mode === "grep" || picker.mode === "yanks" || picker.mode === "refs" ? picker.face.pixelSize - 1 : 16
        // a verb you can run in white (the user's call, 2026-10-05: terminus'
        // yellow read as a warning here); a diagnostic in its severity's;
        // where the undo history is now, in cyan
        color: item.modelData.action || picker.mode === "menu" ? Zenon.white
          : item.modelData.sev === 1 ? Zenon.red : item.modelData.sev === 2 ? Zenon.yellow
          : item.modelData.sev === 3 ? Zenon.blue : item.modelData.sev === 4 ? Zenon.cyan
          : item.modelData.current ? Zenon.cyan : Zenon.white
        text: (item.modelData.glyph ? item.modelData.glyph + "  " : "")
          + item.modelData.label + (item.modelData.mark ? "  " + item.modelData.mark : "")
      }
      // the key it already has, so the palette teaches as well as does
      KeyCap {
        id: cap
        visible: (picker.mode === "commands" && (item.modelData.detail || "") !== "")
          || (item.modelData.key || "") !== ""
        anchors.right: parent.right
        anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        label: item.modelData.key || item.modelData.detail || ""
        fontSize: 12
      }
      Text {
        visible: picker.mode === "buffers" || picker.mode === "grep" || picker.mode === "yanks"
          || picker.mode === "refs" || picker.mode === "diags" || picker.mode === "undo"
          || picker.mode === "pins" || picker.mode === "menu" || picker.mode === "symbols"
        anchors.left: label.right
        anchors.leftMargin: 14
        anchors.right: (item.modelData.key || "") !== "" ? cap.left : parent.right
        anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideMiddle
        textFormat: Text.PlainText
        font.family: Zenon.face
        font.pixelSize: 13
        color: Zenon.muted
        text: item.modelData.detail || ""
      }
      // no hover: the bar is the cursor and the keys move it; a click picks
      MouseArea {
        anchors.fill: parent
        onClicked: { picker.sel = item.index; picker.accept(); }
      }
    }
  }
  ScrollRail {
    target: list
    anchors.right: list.right
    anchors.rightMargin: 2
    anchors.top: list.top
    anchors.bottom: list.bottom
  }

  // ── the preview ────────────────────────────────────────────────────
  // FilePreview.qml (the completion menu and the pointer's path card show
  // files through it too): the file under the selection, from a few lines
  // above the match for grep and the rest. The undo history's is its own:
  // what going back would change, handed in with show().
  function absOf(r) {
    if (!r || !r.path) return "";
    if (picker.mode === "grep") return picker.root + "/" + r.path;
    if (picker.mode === "refs" || picker.mode === "diags" || picker.mode === "pins"
      || picker.mode === "symbols") return r.path;
    return r.path.charAt(0) === "/" ? r.path : picker.root + "/" + r.path;
  }
  readonly property var previewRow: picker.previewing ? picker.results[picker.sel] : undefined
  readonly property int previewLine: (picker.mode === "grep" || picker.mode === "refs"
    || picker.mode === "diags" || picker.mode === "symbols") && picker.previewRow
    ? picker.previewRow.line : 0
  onSelChanged: if (picker.mode === "undo") undoDelay.restart()
  onResultsChanged: if (picker.mode === "undo") undoDelay.restart()
  Timer { id: undoDelay; interval: 60; onTriggered: picker.loadUndoPreview(picker.results[picker.sel]) }
  // the undo history's preview: what going back to that state would change,
  // as a diff — removed lines red, added green, where in the file muted
  property string undoKey: ""
  function loadUndoPreview(r) {
    if (!r) { picker.undoKey = ""; preview.show("", "", ""); return; }
    const key = "undo#" + r.seq;
    if (key === picker.undoKey) return;
    picker.undoKey = key;
    if (r.current) { preview.show(key, "empty", ""); return; }
    picker.client.request("undoPreview", { seq: r.seq }, (diff) => {
      const now = picker.results[picker.sel];
      if (picker.mode !== "undo" || !now || now.seq !== r.seq) return;
      const esc = (t) => t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
        .replace(/ /g, "&nbsp;");
      const lines = String(diff || "").split("\n").filter((l) => l !== "").slice(0, 200);
      if (lines.length === 0) { preview.show(key, "empty", ""); return; }
      const ink = (l) => l.startsWith("@@") ? Zenon.muted : l.startsWith("+") ? Zenon.green
        : l.startsWith("-") ? Zenon.red : Zenon.white;
      preview.show(key, "text", lines.map((l) =>
        "<span style=\"color:" + ink(l) + "\">" + esc(l) + "</span>").join("<br>"));
    });
  }
  onShownChanged: if (!picker.shown) { picker.undoKey = ""; preview.forget(); }

  Rectangle {
    id: previewRule
    visible: picker.previewing
    anchors.top: list.bottom
    anchors.topMargin: 6
    width: parent.width
    height: 1
    color: Zenon.border
  }
  FilePreview {
    id: preview
    visible: picker.previewing
    anchors.top: previewRule.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    clip: true
    manual: picker.mode === "undo"
    file: picker.mode === "undo" ? "" : picker.absOf(picker.previewRow)
    from: picker.previewLine > 0 ? Math.max(1, picker.previewLine - 6) : 1
    hit: picker.previewLine > 0 ? picker.previewLine - preview.from : -1
    codeFamily: picker.codeFamily
    pixelSize: picker.face.pixelSize
    imageMargin: 14
    message: preview.kind === "binary" ? "binary file — nothing to show"
      : picker.mode === "undo" ? (preview.kind === "empty" ? "this is where you are" : "")
      : preview.kind === "empty" ? "empty file"
      : preview.kind === "" && picker.results.length === 0 ? "no file to preview" : ""
  }
}
