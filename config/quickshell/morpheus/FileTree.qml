// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// FILETREE — a directory as a tree you can open and close, for any window.
//
//   FileTree { rootPath: "/some/dir"; onFileActivated: (p) => open(p) }
//
// Terminus' tree, lifted out of terminus. Its tree is an inline `Pane` wired
// to forty-odd members of its window, so it cannot be embedded anywhere else;
// this is the same design standing on its own, built from the same parts:
//
//   listing      terminus.js listCommand / parseListing, one `find` per branch
//   order        terminus.js sortEntries — directories first, natural names
//   the tree     terminus' flattening: a depth-first walk of the open
//                branches into one list, each row carrying a bitmask of which
//                ancestor columns still have siblings below it (its guides)
//   git          terminus.js gitCommand / parseGit / gitWorse / gitMark /
//                gitInk, rolled up so a directory wears its worst descendant
//   the rows     terminus/EntryRow.qml itself, with its metadata off
//   glyphs       terminus.js enrich — icons.js glyphs, terminus' inks
//   edits        terminus.js createCommand / mkdirCommand / renameCommand /
//                trashCommand / copyPathCommand, behind a CardPopup menu
//   liveness     inotifywait over the open branches, as terminus watches
//
// Plato's sidebar is the first user. Terminus could become the second.
//
// Keys, when it has focus: j/k or ↑/↓ move, l/→/Enter open (a directory: into
// it), h/← close or go to the parent, a new file (end in / for a directory),
// A a new directory, r reveal the file being shown, R or F2 rename, d trash, y copy the path, . hidden files,
// c collapse everything, Esc hands focus back.
//
// With `toolbar` on, a band along the top (or the bottom) names the root and carries the
// same verbs as buttons: new file, new directory, collapse, reveal the current
// file, hidden files, refresh.
// The mouse is terminus': a click picks a row, a double click opens it, the
// chevron opens a directory, and a right click is the menu.

import QtQuick
import Quickshell
import Quickshell.Io
import "."
import "icons.js" as Icons
import "../terminus"
import "../terminus/terminus.js" as Terminus

FocusScope {
  id: tree

  // ── what the caller sets ───────────────────────────────────────────
  property string rootPath: ""
  // the file the caller is showing, highlighted and revealed
  property string currentPath: ""
  // dotfiles shown: a config tree is mostly dotfiles, and a tree that hides
  // them by default hides most of what gets edited ('.' toggles it)
  property bool showHidden: true
  property int fontSize: 15
  // the window this sits in, for the context menu's popup
  property var window: null
  // the band of buttons along the top, and how tall it is — a caller lines
  // it up with its own (plato: its tab strip)
  property bool toolbar: false
  // the caller may put the whole tree away: q, while the tree has the keys
  property bool hideable: false
  signal hideRequested()
  property real toolbarHeight: 34
  // the toolbar's glyphs: a step larger than the text, as the shell's bars
  // draw theirs — at the text's own size they read as specks
  property int toolbarGlyphSize: tree.fontSize + 4
  // the band along the bottom instead of the top (plato: in line with its
  // status line), and its colour — the tab strip's band by default, or the
  // tree's own background where it should read as part of the tree
  property bool toolbarBottom: false
  property color toolbarColor: Zenon.headBg
  // the key that puts the tree away besides q (plato: |, the key that
  // brought it out)
  property string hideKey: ""
  // which directories were open, remembered per root by the caller:
  // { recall(root) → [paths], keep(root, [paths]) } (plato: PlatoManager's,
  // so a project's tree comes back as you left it, in any window)
  property var memory: null

  signal fileActivated(string path)
  // Esc: the caller decides where focus goes back to
  signal dismissed()
  // a path the tree changed on disk (renamed, trashed) — an editor may have
  // it open
  signal pathChanged(string from, string to)

  // ── the model ──────────────────────────────────────────────────────
  // Which directories are open, and what each one holds, keyed "k:" + path so a
  // path never collides with an Object property.
  property var openDirs: ({})
  property var kids: ({})
  // git state per path, directories rolled up to their worst descendant
  property var git: ({})

  function isOpen(p) { return tree.openDirs["k:" + p] === true; }
  // set while reset() clears and restores, so neither is remembered as a
  // change of yours (the clear would have wiped what it is about to recall)
  property bool _restoring: false
  onOpenDirsChanged: {
    if (tree._restoring) return;
    // only the ones you opened: a reveal's are gone again by the next one
    if (tree.memory && tree.rootPath !== "")
      tree.memory.keep(tree.rootPath, Object.keys(tree.openDirs)
        .filter((k) => !tree.revealed[k]).map((k) => k.slice(2)));
  }
  function setOpen(p, want) {
    // opened or closed by hand, a revealed directory is yours to keep
    if (tree.revealed["k:" + p]) {
      const a = Object.assign({}, tree.revealed);
      delete a["k:" + p];
      tree.revealed = a;
    }
    const o = Object.assign({}, tree.openDirs);
    if (want) o["k:" + p] = true; else delete o["k:" + p];
    tree.openDirs = o;
    if (want && tree.kids["k:" + p] === undefined) tree.readKids(p);
    watcher.restartSoon();
  }
  function toggle(p) { tree.setOpen(p, !tree.isOpen(p)); }

  // ── reading directories: one `find` at a time, in the order asked ──────
  property var queue: []
  function readKids(p) {
    if (tree.queue.indexOf(p) < 0) tree.queue = tree.queue.concat([p]);
    tree.pump();
  }
  function pump() {
    if (lister.running || tree.queue.length === 0) return;
    const p = tree.queue[0];
    tree.queue = tree.queue.slice(1);
    lister.dir = p;
    lister.command = ["sh", "-c", Terminus.listCommand(p)];
    lister.running = true;
  }
  Process {
    id: lister
    property string dir: ""
    stdout: StdioCollector {
      id: listed
      onStreamFinished: {
        const rows = Terminus.enrich(Terminus.sortEntries(
          Terminus.parseListing(listed.text, lister.dir), "name", false, true, true, ({})), Icons);
        const k = Object.assign({}, tree.kids);
        k["k:" + lister.dir] = rows;
        tree.kids = k;
      }
    }
    onExited: Qt.callLater(() => {
      tree.pump();
      // the last directory read: a row still missing is not coming
      if (tree.following !== "") tree._land();
    })
  }

  // ── the flat tree, with its guides ─────────────────────────────────
  // terminus' walk (see `flat` in TerminusWindow's Pane): every row, depth
  // first, and per row a mask of the ancestor columns whose branch carries
  // on below it — which is all a guide line needs to know.
  readonly property var flat: {
    const out = [];
    const walk = (dir, d, anc) => {
      let rows = tree.kids["k:" + dir];
      if (!rows) return;
      if (!tree.showHidden) rows = rows.filter((r) => !r.isHidden);
      for (let i = 0; i < rows.length; ++i) {
        const r = rows[i];
        const mine = (i === rows.length - 1) ? anc : (anc | (1 << d));
        // as terminus: the top level hangs from nothing, so has no guide
        out.push({ e: r, depth: d, guide: d > 0 ? mine : -1 });
        if (d < 12 && r.isDir && tree.isOpen(r.path)) walk(r.path, d + 1, mine);
      }
    };
    if (tree.rootPath !== "") walk(tree.rootPath, 0, 0);
    return out;
  }

  // ── git ────────────────────────────────────────────────────────────
  function readGit() {
    if (tree.rootPath === "" || gitProc.running) return;
    gitProc.command = ["sh", "-c", Terminus.gitCommand(tree.rootPath)];
    gitProc.running = true;
  }
  Process {
    id: gitProc
    stdout: StdioCollector {
      id: gitOut
      onStreamFinished: {
        const g = Terminus.parseGit(gitOut.text);
        const out = {};
        // every entry, and every directory above it up to the root, wears the
        // worst state beneath it
        for (const e of g.entries) {
          let p = e.path.replace(/\/$/, "");
          out[p] = Terminus.gitWorse(out[p], e.state);
          while (p.length > tree.rootPath.length) {
            p = p.slice(0, p.lastIndexOf("/"));
            if (p.length < tree.rootPath.length) break;
            out[p] = Terminus.gitWorse(out[p], e.state);
          }
        }
        tree.git = out;
      }
    }
  }

  // ── liveness ───────────────────────────────────────────────────────
  // The open branches that have been read, watched for anything appearing,
  // vanishing or moving; a hit re-reads that directory and git, once things
  // settle. Restarted whenever the set of open branches changes.
  Process {
    id: watcher
    property var hits: ({})
    function restartSoon() { rewatch.restart(); }
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: (line) => {
        const h = Object.assign({}, watcher.hits);
        h[line.replace(/\/$/, "")] = true;
        watcher.hits = h;
        settle.restart();
      }
    }
  }
  Timer {
    id: rewatch
    interval: 120
    onTriggered: {
      const dirs = [tree.rootPath];
      for (const k in tree.openDirs) if (tree.kids[k] !== undefined) dirs.push(k.slice(2));
      watcher.running = false;
      if (tree.rootPath === "") return;
      // on the next tick: stopped and started in one, a Process may not
      // notice it was ever stopped, and keeps watching the old set
      Qt.callLater(() => {
        watcher.command = ["inotifywait", "-m", "-q", "-e", "create,delete,moved_to,moved_from",
          "--format", "%w"].concat(dirs);
        watcher.running = true;
      });
    }
  }
  Timer {
    id: settle
    interval: 150
    onTriggered: {
      for (const d in watcher.hits) tree.readKids(d);
      watcher.hits = ({});
      tree.readGit();
    }
  }

  // ── starting over at a new root ────────────────────────────────────
  onRootPathChanged: tree.reset()
  // A ROOT GIVEN FROM THE START is not a change: no rootPathChanged comes for
  // the value a tree is created with, and plato's — home, fixed — left a new
  // window's tree empty. So the first reading happens here too.
  Component.onCompleted: if (tree.rootPath !== "" && Object.keys(tree.kids).length === 0) tree.reset()
  function reset() {
    tree._restoring = true;
    tree._reset();
    tree._restoring = false;
  }
  function _reset() {
    tree.kids = ({});
    tree.revealed = ({});
    tree.openDirs = ({});
    tree.git = ({});
    tree.sel = 0;
    if (tree.rootPath === "") return;
    tree.readKids(tree.rootPath);
    // the directories this root had open last time, opened again
    const kept = tree.memory ? (tree.memory.recall(tree.rootPath) || []) : [];
    if (kept.length > 0) {
      const o = ({});
      for (const d of kept) if (d.indexOf(tree.rootPath + "/") === 0) { o["k:" + d] = true; tree.readKids(d); }
      tree.openDirs = o;
    }
    tree.readGit();
    tree.reveal(tree.currentPath);
    rewatch.restart();
  }
  // Refresh everything read so far — after a save, say, when git has news.
  function refresh() {
    tree.readKids(tree.rootPath);
    for (const k in tree.openDirs) tree.readKids(k.slice(2));
    tree.readGit();
  }

  // Open every directory between the root and `p`, so the file is on show.
  // ONLY UNTIL THE NEXT ONE. The directories a reveal had to open itself are
  // `revealed`, and the next reveal closes those it does not need, so a
  // tree that follows file after file does not end up with all their
  // directories open (nor remember them: see onOpenDirsChanged). One that
  // was already open, or that you open or close by hand, stays yours.
  property var revealed: ({})
  function reveal(p) {
    const o = Object.assign({}, tree.openDirs);
    const mine = ({});
    if (p && tree.rootPath !== "" && p.indexOf(tree.rootPath + "/") === 0) {
      let d = p.slice(0, p.lastIndexOf("/"));
      while (d.length > tree.rootPath.length) {
        const k = "k:" + d;
        if (!o[k] || tree.revealed[k]) mine[k] = true;
        o[k] = true;
        if (tree.kids[k] === undefined) tree.readKids(d);
        d = d.slice(0, d.lastIndexOf("/"));
      }
    }
    for (const k in tree.revealed) if (!mine[k]) delete o[k];
    // before openDirs, whose handler leaves these out of the memory
    tree.revealed = mine;
    tree.openDirs = o;
    watcher.restartSoon();
  }
  onCurrentPathChanged: tree.reveal(tree.currentPath)

  // ── the keyboard's place in it ─────────────────────────────────────
  property int sel: 0
  onFlatChanged: {
    // keep the cursor on the file being shown when there is nothing better
    if (tree.sel >= tree.flat.length) tree.sel = Math.max(0, tree.flat.length - 1);
    if (tree.following !== "") tree._land();
  }
  // Put the cursor on `p` and scroll it into view, its directories opened
  // on the way. Those are read one `find` at a time, so the row may not be
  // there yet: `following` waits for it, and gives up once nothing more is
  // being read (or another follow takes over). `focus`: go into the tree.
  property string following: ""
  property bool _followFocus: false
  function follow(p, focus) {
    if (!p || tree.rootPath === "" || p.indexOf(tree.rootPath + "/") !== 0) return;
    tree.reveal(p);
    tree.following = p;
    tree._followFocus = focus === true;
    tree._land();
  }
  function _land() {
    const i = tree.flat.findIndex((r) => r.e.path === tree.following);
    if (i < 0) {
      if (!lister.running && tree.queue.length === 0) tree.following = "";
      return;
    }
    tree.following = "";
    tree.sel = i;
    // currentIndex only scrolls when it moves; this row may already be it
    Qt.callLater(() => list.positionViewAtIndex(i, ListView.Contain));
    if (tree._followFocus) list.forceActiveFocus();
  }
  function selPath() { const r = tree.flat[tree.sel]; return r ? r.e.path : ""; }
  function activate(i) {
    const r = tree.flat[i];
    if (!r) return;
    tree.sel = i;
    if (r.e.isDir) tree.toggle(r.e.path);
    else tree.fileActivated(r.e.path);
  }

  // ── editing the tree ───────────────────────────────────────────────
  // One command at a time, with a message on failure; the watcher sees the
  // result and the listing follows on its own.
  property string error: ""
  function run(cmd, after) {
    runner.after = after || null;
    runner.command = ["sh", "-c", cmd];
    runner.running = true;
  }
  Process {
    id: runner
    property var after: null
    stderr: StdioCollector { id: runErr }
    onExited: (code) => {
      tree.error = code === 0 ? "" : (String(runErr.text).trim() || "failed");
      if (code === 0 && runner.after) runner.after();
      errorClear.restart();
    }
  }
  Timer { id: errorClear; interval: 4000; onTriggered: tree.error = "" }

  // The inline field: a new name, or a new name for something. `editing` is
  // "" | "new" | "rename"; the field sits over the row it concerns.
  property string editing: ""
  property string editDir: ""
  // `directory`: what is typed names a directory, with or without its slash
  property bool editDirectory: false
  function beginNew(directory) {
    const r = tree.flat[tree.sel];
    tree.editDir = !r ? tree.rootPath : (r.e.isDir && tree.isOpen(r.e.path)) ? r.e.path
      : r.e.path.slice(0, r.e.path.lastIndexOf("/"));
    tree.editDirectory = directory === true;
    tree.editing = "new";
    nameField.text = "";
    nameField.forceActiveFocus();
  }
  // every branch closed again, down to the root's own entries
  function collapseAll() {
    tree.revealed = ({});
    tree.openDirs = ({});
    tree.sel = 0;
    watcher.restartSoon();
  }
  // the file being shown, opened up to and put under the cursor
  function revealCurrent() {
    tree.follow(tree.currentPath, true);
    list.forceActiveFocus();
  }
  // Renaming is the row's own — terminus' EntryRow edits its name in place
  // and asks its host to commit or give up (see `host` below).
  function beginRename() {
    const r = tree.flat[tree.sel];
    if (!r) return;
    treeHost.renamePath = r.e.path;
    treeHost.renaming = true;
  }
  function commitEdit() {
    let name = nameField.text.trim();
    if (tree.editDirectory && name !== "" && !/\/$/.test(name)) name += "/";
    const mode = tree.editing;
    tree.editing = "";
    list.forceActiveFocus();
    if (name === "") return;
    if (mode === "new") {
      const dir = tree.editDir;
      tree.setOpen(dir === tree.rootPath ? dir : dir, true);
      tree.run(Terminus.createCommand(dir, name), () => {
        tree.readKids(dir);
        if (!/\/$/.test(name)) tree.fileActivated(Terminus.joinPath(dir, name));
      });
    }
  }
  function trashSel() {
    const p = tree.selPath();
    if (p === "") return;
    tree.run(Terminus.trashCommand([p]), () => tree.pathChanged(p, ""));
  }

  // ── THE ROW IS TERMINUS' ───────────────────────────────────────────
  // terminus/EntryRow.qml, the row terminus lists with — glyph, name, the
  // tree's guides and chevron, git's mark, rename in place — drawn with its
  // metadata columns off (showMeta), which leaves the tree alone.
  //
  // The row reads what it needs to know about its window off `host`. This
  // is that host for a tree in a sidebar: terminus' measurements at this
  // size, git on when the root is in a repository, and the columns, tags,
  // disk usage and drag and drop terminus has and a sidebar does not, at
  // their "nothing here" values.
  QtObject {
    id: treeHost
    // terminus draws at zoom 1 for 16px text
    readonly property real zoom: tree.fontSize / 16
    readonly property int rowH: Math.round(26 * treeHost.zoom)
    // Tighter than terminus' 28: a level's step is where a sidebar's width
    // goes, and at 28 two levels down left a name a hundred pixels to live
    // in. The guides are drawn against this, so nothing else moves.
    readonly property int treeStep: Math.round(20 * treeHost.zoom)
    readonly property int treeArrowW: Math.round(14 * treeHost.zoom)
    readonly property int doubleMs: 400
    property bool hoverRow: false
    // the row's two acknowledgements, a light across a row that was opened
    // or just made: terminus bumps these, and so could a host that wants them
    property int openPulse: 0
    property int madePulse: 0
    readonly property string cwd: tree.rootPath
    readonly property string searchMode: ""
    readonly property bool modal: false
    readonly property int markedCount: 0
    readonly property bool railHover: false
    readonly property bool railDragging: false

    readonly property bool git: Object.keys(tree.git).length > 0
    readonly property var gitMarks: tree.git
    function gitInk(state) { return Terminus.gitInk(state); }

    // a directory read and found empty shows no chevron, as in terminus
    readonly property var dirEmpty: {
      const out = {};
      for (const k in tree.kids) if (tree.kids[k].length === 0) out[k.slice(2)] = true;
      return out;
    }

    // the name takes the whole row: no kind, size or date columns
    readonly property var colPlain: ({ name: 1, where: 0, kind: 0, size: 0, time: 0 })
    readonly property var colFound: treeHost.colPlain
    readonly property var colFoundNarrow: treeHost.colPlain
    function colWidths(inner, f) { return { name: inner, where: 0, kind: 0, size: 0, time: 0 }; }
    readonly property var dirSizes: ({})
    readonly property bool usage: false
    readonly property real usageMax: 0
    readonly property real otherUsageMax: 0
    function usageOf(e) { return 0; }
    function sizeTextOf(e) { return Terminus.formatSize(e.size); }
    function whenOf(e) { return Terminus.formatTime(e.mtime); }
    function kindOf(e) { return e.isDir ? "directory" : Terminus.kindOf(e.name); }
    readonly property var tagMarks: ({})
    function tagInk(name) { return Zenon.muted; }
    function isBookmarked(p) { return false; }

    // no dragging out of the sidebar, and nothing dropped into it
    readonly property string dropDir: ""
    function dropDirAt() {}
    function beginDrag() {}
    readonly property var dragProxy: null
    readonly property string freshPath: ""

    // rename in place: the row's editor, this commit
    property bool renaming: false
    property string renamePath: ""
    function commitRename(entry, text) {
      const name = String(text).trim();
      treeHost.renaming = false;
      list.forceActiveFocus();
      if (!entry || name === "" || name === entry.name) return;
      const from = entry.path;
      const to = Terminus.joinPath(from.slice(0, from.lastIndexOf("/")), name);
      tree.run(Terminus.renameCommand(from, name), () => tree.pathChanged(from, to));
    }
    function endRename(cancel) {
      treeHost.renaming = false;
      list.forceActiveFocus();
    }

    function openMenuAt(item, m) {
      menu.at = item.mapToItem(null, m.x, m.y);
      menu.open = true;
    }
  }

  readonly property real rowH: treeHost.rowH

  // ── the toolbar ────────────────────────────────────────────────────
  // The root's name on the left, the verbs on the right, in the band colour
  // of a tab strip so the two read as one line across the window.
  component ToolGlyph: Item {
    id: tg
    required property string glyph
    required property string tip
    property string key: ""
    property bool on: false
    signal hit()
    width: Math.max(tree.toolbarHeight - 8, tree.toolbarGlyphSize + 10)
    height: tree.toolbarHeight - 8
    Rectangle {
      anchors.fill: parent
      radius: 4
      color: tgHover.hovered ? Qt.rgba(1, 1, 1, 0.07) : "transparent"
    }
    Text {
      anchors.centerIn: parent
      font.family: Zenon.faceMono
      font.pixelSize: tree.toolbarGlyphSize
      color: tg.on ? Zenon.cyan : tgHover.hovered ? Zenon.white : Zenon.muted
      text: tg.glyph
    }
    HoverHandler {
      id: tgHover
      cursorShape: Qt.PointingHandCursor
      onHoveredChanged: hovered ? tips.show(tg, tg.tip, tg.key) : tips.hide(tg)
    }
    TapHandler { onTapped: tg.hit() }
  }
  WindowTip { id: tips; window: tree.window }
  Rectangle {
    id: bar
    visible: tree.toolbar
    width: parent.width
    height: tree.toolbar ? tree.toolbarHeight : 0
    y: tree.toolbarBottom ? tree.height - height : 0
    color: tree.toolbarColor
    // the hairline on the side the list is
    Rectangle {
      y: tree.toolbarBottom ? 0 : parent.height - 1
      width: parent.width
      height: 1
      color: Zenon.border
    }
    Text {
      anchors.left: parent.left
      anchors.leftMargin: 12
      anchors.right: tools.left
      anchors.rightMargin: 8
      anchors.verticalCenter: parent.verticalCenter
      elide: Text.ElideRight
      font.family: Zenon.face
      font.pixelSize: tree.fontSize
      font.weight: Font.Medium
      color: "#a3a9bd"
      text: tree.rootPath.slice(tree.rootPath.lastIndexOf("/") + 1)
    }
    Row {
      id: tools
      anchors.right: parent.right
      anchors.rightMargin: 6
      anchors.verticalCenter: parent.verticalCenter
      spacing: 0
      ToolGlyph { glyph: "󰝒"; tip: "New file"; key: "a"; onHit: tree.beginNew(false) }
      ToolGlyph { glyph: "󰉗"; tip: "New directory"; key: "A"; onHit: tree.beginNew(true) }
      ToolGlyph { glyph: "󰆤"; tip: "Reveal the open file"; key: "r"; onHit: tree.revealCurrent() }
      ToolGlyph { glyph: "󰘕"; tip: "Collapse all"; key: "c"; onHit: tree.collapseAll() }
      ToolGlyph { glyph: "󰘓"; tip: "Hidden files"; key: "."; on: tree.showHidden
                  onHit: tree.showHidden = !tree.showHidden }
      ToolGlyph { glyph: "󰑐"; tip: "Refresh"; onHit: tree.refresh() }
    }
  }

  ListView {
    id: list
    anchors.fill: parent
    // a breath under the band, as terminus' lists start below their bar
    anchors.topMargin: tree.toolbarBottom ? 6 : bar.height + (tree.toolbar ? 6 : 0)
    anchors.bottomMargin: (errorBar.visible ? errorBar.height : 0)
      + (tree.toolbarBottom ? bar.height : 0)
    clip: true
    focus: true
    model: tree.flat
    currentIndex: tree.sel
    boundsBehavior: Flickable.StopAtBounds
    onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

    Keys.onPressed: (event) => {
      if (treeHost.renaming) return;
      const n = tree.flat.length;
      const r = tree.flat[tree.sel];
      const k = event.key, t = event.text;
      event.accepted = true;
      // AT AN END, ONE MORE WRAPS ROUND to the other — on a fresh press
      // only: a held key stops at the end rather than racing round and round
      if (k === Qt.Key_Down || t === "j")
        tree.sel = tree.sel >= n - 1 && !event.isAutoRepeat ? 0 : Math.min(n - 1, tree.sel + 1);
      else if (k === Qt.Key_Up || t === "k")
        tree.sel = tree.sel <= 0 && !event.isAutoRepeat ? Math.max(0, n - 1) : Math.max(0, tree.sel - 1);
      else if (k === Qt.Key_Return || k === Qt.Key_Enter || t === "o") tree.activate(tree.sel);
      else if (k === Qt.Key_Right || t === "l") {
        if (r && r.e.isDir) { if (!tree.isOpen(r.e.path)) tree.setOpen(r.e.path, true); else tree.sel = Math.min(n - 1, tree.sel + 1); }
        else tree.activate(tree.sel);
      } else if (k === Qt.Key_Left || t === "h") {
        if (r && r.e.isDir && tree.isOpen(r.e.path)) tree.setOpen(r.e.path, false);
        else if (r && r.depth > 0) {
          for (let i = tree.sel - 1; i >= 0; --i) if (tree.flat[i].depth === r.depth - 1) { tree.sel = i; break; }
        }
      }
      else if (t === "g") tree.sel = 0;
      else if (t === "G") tree.sel = Math.max(0, n - 1);
      else if (t === "a") tree.beginNew(false);
      else if (t === "A") tree.beginNew(true);
      else if (t === "c") tree.collapseAll();
      else if (t === "r") tree.revealCurrent();
      else if (t === "R" || k === Qt.Key_F2) tree.beginRename();
      else if (t === "d") tree.trashSel();
      else if (t === "y") { const p = tree.selPath(); if (p) Quickshell.execDetached(["sh", "-c", Terminus.copyPathCommand(p)]); }
      else if (t === ".") tree.showHidden = !tree.showHidden;
      else if (k === Qt.Key_Escape) tree.dismissed();
      else if ((t === "q" || (tree.hideKey !== "" && t === tree.hideKey)) && tree.hideable)
        tree.hideRequested();
      else event.accepted = false;
    }

    // ── the cursor: terminus' bar, sliding between rows ───────────────
    // On the keyboard's row while the tree has the keyboard, and on the file
    // the editor is showing while it does not.
    //
    // "HAS THE KEYBOARD" WITHIN ITS OWN WINDOW, not activeFocus: that goes
    // whenever the window does, so every alt-tab away moved the bar to the
    // editor's file (or took it away) and back again. `focus` is the window's
    // own record of where the keys go, kept while it is in the background.
    readonly property bool held: list.focus && tree.focus
    SelectBar {
      view: list
      index: list.held ? tree.sel : tree.flat.findIndex((r) => r.e.path === tree.currentPath)
      rowH: treeHost.rowH
      on: list.held || tree.flat.some((r) => r.e.path === tree.currentPath)
    }

    delegate: EntryRow {
      id: row
      required property var modelData
      required property int index
      host: treeHost
      width: list.width
      entry: row.modelData.e
      depth: row.modelData.depth
      guide: row.modelData.guide
      inTree: true
      branch: row.modelData.e.isDir
      expanded: tree.isOpen(row.modelData.e.path)
      hollow: treeHost.dirEmpty[row.modelData.e.path] === true
      showMeta: false
      // the cursor is the keyboard's row while the tree has the keyboard, and
      // otherwise the file the editor is showing
      current: list.held ? row.index === tree.sel
        : row.modelData.e.path === tree.currentPath
      live: list.held
      // never the outlined, passive cursor: the bar above is always the
      // cursor here, focused or not
      passive: false
      onToggled: { tree.sel = row.index; tree.toggle(row.modelData.e.path); }
      onChosen: (right, shift, ctrl) => {
        list.forceActiveFocus();
        tree.sel = row.index;
      }
      // double click, as in terminus: a file opens, a directory opens or closes
      onOpened: tree.activate(row.index)
    }
  }

  // ── the wheel and the scrollbar, as every list in the shell has them ─
  // morpheus' Elastic (Finder's rubber band and the smooth notch) and the
  // windows' ScrollRail. Declared after the list and laid over it: a child of
  // a Flickable scrolls away with its rows and never sees the wheel.
  ElasticScroll { anchors.fill: list; view: list }
  ScrollRail {
    target: list
    anchors.right: list.right
    anchors.top: list.top
    anchors.bottom: list.bottom
  }

  // ── the inline name field ──────────────────────────────────────────
  Rectangle {
    visible: tree.editing !== ""
    x: 6
    width: tree.width - 12
    height: tree.rowH
    y: list.y + Math.max(0, Math.min(list.height - height, (tree.sel + 1) * tree.rowH - list.contentY))
    radius: 4
    color: Qt.rgba(0.05, 0.055, 0.065, 0.98)
    border.width: 1
    border.color: Zenon.cyan
    TextInput {
      id: nameField
      anchors.fill: parent
      anchors.leftMargin: 8
      anchors.rightMargin: 8
      verticalAlignment: TextInput.AlignVCenter
      font.family: Zenon.face
      font.pixelSize: tree.fontSize
      color: Zenon.white
      selectionColor: Qt.rgba(Zenon.magenta.r, Zenon.magenta.g, Zenon.magenta.b, 0.5)
      cursorDelegate: Caret { field: nameField }
      clip: true
      Keys.onReturnPressed: tree.commitEdit()
      Keys.onEnterPressed: tree.commitEdit()
      Keys.onEscapePressed: { tree.editing = ""; list.forceActiveFocus(); }
      // clicking away cancels; the window going to the background does not
      onActiveFocusChanged: if (!activeFocus && nameField.Window.active && tree.editing !== "") tree.editing = ""
    }
    Text {
      visible: nameField.text === "" && tree.editing === "new"
      anchors.verticalCenter: parent.verticalCenter
      x: 8
      font.family: Zenon.face
      font.pixelSize: tree.fontSize
      color: Zenon.muted
      text: tree.editDirectory ? "directory name" : "name — end with / for a directory"
    }
  }

  // ── a failure, said once ───────────────────────────────────────────
  Rectangle {
    id: errorBar
    visible: tree.error !== ""
    anchors.bottom: parent.bottom
    anchors.bottomMargin: tree.toolbarBottom ? bar.height : 0
    width: parent.width
    height: tree.rowH
    color: Qt.rgba(Zenon.red.r, Zenon.red.g, Zenon.red.b, 0.15)
    Text {
      anchors.fill: parent
      anchors.leftMargin: 10
      verticalAlignment: Text.AlignVCenter
      elide: Text.ElideRight
      font.family: Zenon.face
      font.pixelSize: tree.fontSize - 1
      color: Zenon.red
      text: tree.error
    }
  }

  // ── the context menu ───────────────────────────────────────────────
  CardPopup {
    id: menu
    window: tree.window
    readonly property var target: tree.flat[tree.sel] ? tree.flat[tree.sel].e : null
    model: [
      { text: menu.target && menu.target.isDir ? "Open directory" : "Open" },
      { text: "New file or directory…" },
      { isSeparator: true },
      { text: "Rename…" },
      { text: "Move to trash" },
      { isSeparator: true },
      { text: "Copy path" },
      { text: "Show in terminus" },
    ]
    onChosen: (i) => {
      menu.open = false;
      const p = tree.selPath();
      switch (i) {
        case 0: tree.activate(tree.sel); break;
        case 1: tree.beginNew(false); break;
        case 3: tree.beginRename(); break;
        case 4: tree.trashSel(); break;
        case 6: if (p) Quickshell.execDetached(["sh", "-c", Terminus.copyPathCommand(p)]); break;
        case 7: if (p) Quickshell.execDetached(["qs", "ipc", "call", "Terminus", "open",
                  menu.target && menu.target.isDir ? p : p.slice(0, p.lastIndexOf("/"))]); break;
      }
    }
  }
}
