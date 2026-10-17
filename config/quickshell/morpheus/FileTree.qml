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
// OR A TREE OF GIVEN PATHS, not read from disk: `given` a list of
// { path: "dir/name", size, … } relative to rootPath (which then only names
// the top). Every directory is made from the paths and shown open; nothing
// is read, watched or edited, and there is no menu. `noteOf(entry)` →
// { text, ink } writes a word at a row's right end, in `noteWidth`.
// Delphi's upload breakdown: where each file lands in the repository.
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
  // status line), and its color — the tab strip's band by default, or the
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

  // a tree of given paths instead of the disk (see the top); null: the disk
  // (asked as `given !== null` wherever it is acted on: a binding of its
  // own lagged behind givenChanged, and the paths were never planted)
  property var given: null
  property var noteOf: null
  property int noteWidth: 0
  onGivenChanged: if (tree.given !== null) tree.reset()

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
  // the directories read that are repositories (TreeHost.repoDirs)
  property var repoDirs: ({})

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
    tree.branchMoved(p);
    tree.openDirs = o;
    if (want && tree.kids["k:" + p] === undefined) tree.readKids(p);
    watcher.restartSoon();
  }
  function toggle(p) { tree.setOpen(p, !tree.isOpen(p)); }

  // ── A BRANCH OPENING OR CLOSING SLIDES (user, 2026-10-17) ─────────────
  // terminus' list does it (Pane.branchMoved): the rows below glide from
  // their old places to their new ones, and an opening branch's own rows
  // come down out of the directory's row, fading in. The model is a plain
  // array, so every change builds the rows afresh — each reads where its
  // path stood (`prevAt`) as it is made. Held a while, as a branch not read
  // yet lands a moment after it is opened.
  property var prevAt: ({})
  property string branchPath: ""
  property int branchAt: -1
  function branchMoved(p) {
    const at = ({});
    let b = -1;
    for (let i = 0; i < tree.flat.length; ++i) {
      at["k:" + tree.flat[i].e.path] = i;
      if (tree.flat[i].e.path === p) b = i;
    }
    if (b < 0) return;
    tree.prevAt = at;
    tree.branchAt = b;
    tree.branchPath = p;
    branchOff.restart();
  }
  Timer {
    id: branchOff
    interval: 700
    onTriggered: { tree.branchPath = ""; tree.prevAt = ({}); }
  }
  function inBranch(path) {
    const b = tree.branchPath;
    return b !== "" && String(path).indexOf(b === "/" ? "/" : b + "/") === 0;
  }

  // ── reading directories: one `find` at a time, in the order asked ──────
  property var queue: []
  function readKids(p) {
    if (tree.given !== null) return;
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
        // a listing begun before the tree was handed its paths (the root
        // came first) must not land on the planted tree
        if (tree.given !== null) return;
        const rows = Terminus.enrich(Terminus.sortEntries(
          Terminus.parseListing(listed.text, lister.dir), "name", false, true, true, ({})), Icons);
        const k = Object.assign({}, tree.kids);
        k["k:" + lister.dir] = rows;
        tree.kids = k;
        tree.repoDirs = Terminus.mergeRepos(tree.repoDirs, lister.dir, Terminus.parseRepos(listed.text, lister.dir));
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
    if (tree.given !== null || tree.rootPath === "" || gitProc.running) return;
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
      if (tree.rootPath === "" || tree.given !== null) return;
      // on the next tick: stopped and started in one, a Process may not
      // notice it was ever stopped, and keeps watching the old set
      Qt.callLater(() => {
        watcher.command = Paths.tether(["inotifywait", "-m", "-q", "-e", "create,delete,moved_to,moved_from",
          "--format", "%w"].concat(dirs));
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
    if (tree.given !== null) { tree.plant(); return; }
    tree.kids = ({});
    tree.revealed = ({});
    tree.openDirs = ({});
    tree.git = ({});
    tree.repoDirs = ({});
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
  // The given paths as the tree: their directories made, every one open,
  // each level in terminus' order with terminus' glyphs, as a listing is.
  function plant() {
    const root = tree.rootPath;
    tree.queue = [];
    const kids = ({}), open = ({}), made = ({});
    const put = (dir, e) => { (kids["k:" + dir] = kids["k:" + dir] || []).push(e); };
    kids["k:" + root] = [];
    for (const g of tree.given || []) {
      const parts = String(g.path || "").split("/").filter((x) => x !== "");
      if (parts.length === 0) continue;
      let dir = root;
      for (let i = 0; i < parts.length - 1; ++i) {
        const p = dir + "/" + parts[i];
        if (!made[p]) {
          made[p] = true;
          open["k:" + p] = true;
          put(dir, { name: parts[i], path: p, isDir: true, isLink: false, broken: false, isExec: false,
                     mode: 0, isHidden: parts[i].charAt(0) === ".", size: 0, mtime: 0 });
        }
        dir = p;
      }
      const name = parts[parts.length - 1];
      put(dir, Object.assign({ isLink: false, broken: false, isExec: false, mode: 0, mtime: 0 }, g,
                             { name: name, path: dir + "/" + name, isDir: false,
                               isHidden: name.charAt(0) === ".", size: Math.max(0, g.size || 0) }));
    }
    for (const k in kids)
      kids[k] = Terminus.enrich(Terminus.sortEntries(kids[k], "name", false, true, true, ({})), Icons);
    tree.revealed = ({});
    tree.git = ({});
    tree.repoDirs = ({});
    tree.kids = kids;
    tree.openDirs = open;
    tree.sel = 0;
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
  onCurrentPathChanged: { tree.opening = ""; tree.reveal(tree.currentPath); }

  // ── THE FILE ON ITS WAY TO THE EDITOR ──────────────────────────────
  // Opening a file hands the keyboard to the editor, which turns the bar
  // from the keyboard's row to the editor's file — and for the moment
  // before the caller's currentPath catches up, that was still the OLD
  // file: a double click flicked the bar back to it and over again
  // (user, 2026-10-09). So the bar reads the file being opened until
  // currentPath arrives, or a beat passes and it never will.
  property string opening: ""
  readonly property string shownPath: tree.opening !== "" ? tree.opening : tree.currentPath
  Timer { id: openingDone; interval: 1500; onTriggered: tree.opening = "" }

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
  // The row the verbs act on: the cursor's, or for the length of one verb
  // chosen from a held row's menu, that row (heldBox — a plain field, so
  // setting it notifies nothing and the bar never moves; user, 2026-10-09).
  readonly property var heldBox: ({ i: -1 })
  function actAt() { return tree.heldBox.i >= 0 ? tree.heldBox.i : tree.sel; }
  function selPath() { const r = tree.flat[tree.actAt()]; return r ? r.e.path : ""; }
  // keep: leave the cursor where it is (Open from a held row's menu)
  function activate(i, keep) {
    const r = tree.flat[i];
    if (!r) return;
    if (!keep) tree.sel = i;
    if (r.e.isDir) tree.toggle(r.e.path);
    else {
      if (r.e.path !== tree.currentPath) { tree.opening = r.e.path; openingDone.restart(); }
      tree.fileActivated(r.e.path);
    }
  }

  // ── editing the tree ───────────────────────────────────────────────
  // One command at a time, with a message on failure; the watcher sees the
  // result and the listing follows on its own.
  property string error: ""
  function run(cmd, after) {
    runner.after = after || null;
    // a script string, or terminus' { script, args } (trashCommand is one —
    // handed to sh -c as it was, it ran "[object Object]")
    runner.command = typeof cmd === "string" ? ["sh", "-c", cmd] : Terminus.shArgv(cmd);
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
    const r = tree.flat[tree.actAt()];
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
    const r = tree.flat[tree.actAt()];
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
  // A path renamed from outside the row — plato's properties sheet, its
  // title (user, 2026-10-15) — the same move the row's edit makes. `then`
  // gets the new path once it is done.
  function renamePath(from, text, then) {
    const name = String(text).trim();
    if (!from || name === "" || name === Terminus.basename(from)) return;
    const to = Terminus.joinPath(from.slice(0, from.lastIndexOf("/")), name);
    tree.run(Terminus.renameCommand(from, name), () => {
      tree.pathChanged(from, to);
      if (then) then(to);
    });
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
  // The row reads what it needs to know about its window off `host`:
  // terminus/TreeHost, the host for a tree outside terminus' window — here
  // with git on when the root is in a repository, and this tree's rename in
  // place and menu.
  TreeHost {
    id: treeHost
    fontSize: tree.fontSize
    root: tree.rootPath
    marks: tree.git
    repoDirs: tree.repoDirs
    namePeek: (row, entry) => namePeek.show(row, entry)
    noteWidth: tree.noteWidth
    // a directory read and found empty shows no chevron, as in terminus
    empties: {
      const out = {};
      for (const k in tree.kids) if (tree.kids[k].length === 0) out[k.slice(2)] = true;
      return out;
    }
    renameCommit: (entry, text) => {
      treeHost.renaming = false;
      list.forceActiveFocus();
      if (entry) tree.renamePath(entry.path, text);
    }
    renameEnd: (cancel) => { treeHost.renaming = false; list.forceActiveFocus(); }
    // only while the card is up, however it closes
    sideMenuAt: menu.open ? treeHost.menuItem : null
    menuOpen: (item, m) => tree.openMenu(item.mapToItem(null, m.x, m.y))
  }

  readonly property real rowH: treeHost.rowH

  // ── the toolbar ────────────────────────────────────────────────────
  // The root's name on the left, the verbs on the right, in the band color
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
      color: tgHover.hovered ? Zenon.wash(0.07) : "transparent"
    }
    Text {
      anchors.centerIn: parent
      font.family: Zenon.faceMono
      font.weight: Zenon.weight
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
  // a name the sidebar's width cut short, shown whole (terminus/NamePeek)
  NamePeek { id: namePeek; window: tree.window }
  // ── THE ROWS GO ON UNDER THE TOOLBAR, frosted ─────────────────────
  // as under every bar in the shell (user, 2026-10-14: plato's tree bar
  // was the one that stayed clear). Declared before the bar: its glyphs
  // draw over the frost.
  ScrollEdge {
    view: list
    follow: true
    below: tree.toolbarBottom
    bar: bar
    visible: tree.toolbar
  }
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
      color: Zenon.keyInk
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
      else if ((k === Qt.Key_Return || k === Qt.Key_Enter) && (event.modifiers & Qt.AltModifier)) {
        const p = tree.selPath();
        if (tree.props && p) tree.propsWanted(p);
      }
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
      // a tree of given paths only moves, opens and closes
      else if (tree.given !== null && k !== Qt.Key_Escape) event.accepted = false;
      else if (t === "a") tree.beginNew(false);
      else if (t === "A") tree.beginNew(true);
      else if (t === "c") tree.collapseAll();
      else if (t === "r") tree.revealCurrent();
      else if (t === "R" || k === Qt.Key_F2) tree.beginRename();
      else if (t === "d") tree.trashSel();
      else if (t === "y") { const p = tree.selPath(); if (p) Quickshell.execDetached(["sh", "-c", Terminus.copyPathCommand(p)]); }
      else if (t === ".") tree.showHidden = !tree.showHidden;
      else if (k === Qt.Key_Escape) tree.dismissed();
      // the menu key: the row's menu, hung under the row
      else if (k === Qt.Key_Menu || (k === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier))) {
        const at = list.itemAtIndex(tree.sel);
        treeHost.menuItem = at;
        tree.heldAt = -1;
        tree.openMenu(at ? at.mapToItem(null, 24, at.height) : list.mapToItem(null, 24, 0));
      }
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
    // The menu takes the keys while it is up (menuKeys), and the bar must
    // not leave the row the menu is about for the editor's file meanwhile —
    // a right click slid it to the open file, often at the bottom.
    // While the menu is up the bar keeps the mode it had when it opened
    // (menuHadKeys): the menu taking the keys must not move it either.
    readonly property bool held: menu.open ? tree.menuHadKeys : (list.focus && tree.focus)
    SelectBar {
      view: list
      index: list.held ? tree.sel : tree.flat.findIndex((r) => r.e.path === tree.shownPath)
      rowH: treeHost.rowH
      on: list.held || tree.flat.some((r) => r.e.path === tree.shownPath)
      // the theme's accent, as terminus' sidebar wears it (user, 2026-10-14)
      color: Zenon.alpha(Zenon.cyan, 0.12)
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
        : row.modelData.e.path === tree.shownPath
      live: list.held
      // never the outlined, passive cursor: the bar above is always the
      // cursor here, focused or not
      passive: false
      onToggled: { tree.sel = row.index; tree.toggle(row.modelData.e.path); }
      // the slide, as it is built — see branchMoved
      Glide { id: rowGlide; limit: list.height; duration: 220 }
      z: tree.inBranch(row.modelData.e.path) ? -1 : 0
      NumberAnimation {
        id: rowFade
        target: row
        property: "opacity"
        from: 0
        to: 1
        duration: 220
        easing.type: Easing.OutCubic
      }
      Component.onCompleted: {
        if (tree.branchPath === "") return;
        const was = tree.prevAt["k:" + row.modelData.e.path];
        if (was !== undefined) {
          if (was !== row.index) rowGlide.from(0, (was - row.index) * treeHost.rowH);
        } else if (tree.inBranch(row.modelData.e.path) && tree.branchAt >= 0) {
          rowGlide.from(0, (tree.branchAt - row.index) * treeHost.rowH);
          rowFade.restart();
        }
      }
      onChosen: (right, shift, ctrl) => {
        // A right click holds the row for its menu and leaves the cursor
        // AND the keyboard be (user, 2026-10-09) — see heldAt. Taking the
        // focus here flipped the bar from the editor's file to tree.sel,
        // wherever that had last been left.
        if (right) { tree.heldAt = row.index; return; }
        list.forceActiveFocus();
        tree.sel = row.index;
      }
      // double click, as in terminus: a file opens, a directory opens or closes
      onOpened: tree.activate(row.index)
      // the holder's word at the right end (given paths: new, replaces)
      Text {
        visible: !!tree.noteOf
        readonly property var note: tree.noteOf ? tree.noteOf(row.modelData.e) : null
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        width: tree.noteWidth - 12
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideLeft
        text: note ? note.text : ""
        color: note && note.ink ? note.ink : Zenon.muted
        textFormat: Text.StyledText
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.features: { "tnum": 1 }
        font.pixelSize: tree.fontSize - 2
      }
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
    color: Zenon.alpha(Zenon.card, 0.98)
    border.width: 1
    border.color: Zenon.border
    TextInput {
      id: nameField
      anchors.fill: parent
      anchors.leftMargin: 8
      anchors.rightMargin: 8
      verticalAlignment: TextInput.AlignVCenter
      font.family: Zenon.face
      font.weight: Zenon.weight
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
      font.weight: Zenon.weight
      font.pixelSize: tree.fontSize
      color: Zenon.muted
      text: tree.editDirectory ? "directory name" : "name — end with / for a directory"
    }
    // focused for typing: terminus' held ring (user, 2026-10-11 — every
    // text field wears it, its own border staying neutral)
    HeldRing { anchors.fill: parent; radius: parent.radius; z: 10; on: nameField.activeFocus }
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
      font.weight: Zenon.weight
      font.pixelSize: tree.fontSize - 1
      color: Zenon.red
      text: tree.error
    }
  }

  // ── the context menu ───────────────────────────────────────────────
  // What can be done to the row under the click, with the key beside each
  // verb the tree already has, so the menu teaches the keys too. A caller
  // adds its own verbs (`extraItems`, after Open): plato's splits, search in
  // a directory, pins. Rows: { text, icon, hint?, when?: "file" | "dir",
  // run(path, isDir) }.
  //
  // PUT AWAY by a click anywhere outside it — morpheus' InputShield over the
  // whole window, so that click is not also a click on a row or in the
  // editor — or by Esc (the card is its own surface and never has the keys,
  // so they are caught here while it is up, and any other key closes it too).
  property var extraItems: []
  // A Properties row (and alt+return on a row), for a holder that shows a
  // properties card: the tree asks, the holder shows (plato: PropsSheet).
  property bool props: false
  signal propsWanted(string path)
  function menuItems() {
    const r = tree.flat[tree.heldAt >= 0 ? tree.heldAt : tree.sel];
    const e = r ? r.e : null;
    const p = e ? e.path : tree.rootPath;
    const isDir = e ? e.isDir : true;
    const dir = isDir ? p : p.slice(0, p.lastIndexOf("/"));
    const sh = (cmd) => () => Quickshell.execDetached(["sh", "-c", cmd]);
    const rel = tree.rootPath !== "" && p.indexOf(tree.rootPath + "/") === 0
      ? p.slice(tree.rootPath.length + 1) : p;
    const extra = (tree.extraItems || []).filter((x) => x.isSeparator
      || !x.when || (x.when === "dir") === isDir)
      .map((x) => x.isSeparator ? x : Object.assign({}, x, { run: () => x.run(p, isDir) }));
    const out = [
      { text: !isDir ? "Open" : tree.isOpen(p) ? "Close directory" : "Open directory",
        icon: isDir ? "\u{F0770}" : "\u{F0214}", hint: "↵", run: () => tree.activate(tree.actAt(), true) },
    ].concat(extra).concat([
      { isSeparator: true },
      { text: "New file…", icon: "\u{F0415}", hint: "a", run: () => tree.beginNew(false) },
      { text: "New directory…", icon: "\u{F0B9D}", hint: "A", run: () => tree.beginNew(true) },
      { text: "Duplicate", icon: "\u{F0191}", enabled: !!e, run: () => tree.duplicateSel() },
      { isSeparator: true },
      { text: "Rename…", icon: "\u{F0CB5}", hint: "R", enabled: !!e, run: () => tree.beginRename() },
      { text: "Move to trash", icon: "\u{F0A7A}", hint: "d", enabled: !!e, run: () => tree.trashSel() },
      { isSeparator: true },
      { text: "Copy path", icon: "\u{F506}", hint: "y", run: sh(Terminus.copyPathCommand(p)) },
      { text: "Copy relative path", icon: "\u{F506}", enabled: rel !== p, run: sh(Terminus.copyPathCommand(rel)) },
      { text: "Copy name", icon: "\u{F506}", run: sh(Terminus.copyPathCommand(p.slice(p.lastIndexOf("/") + 1))) },
      { isSeparator: true },
    ]);
    if (tree.props) out.push(
      { text: "Info", icon: "\u{F064E}", hint: "alt ↵", run: () => tree.propsWanted(p) },
      { isSeparator: true });
    if (!isDir) out.push({ text: "Open with its app", icon: "\u{F03CC}",
      run: () => tree.run(Terminus.openOrAskCommand(p)) });
    out.push(
      { text: "Show in terminus", icon: "\u{F024B}",
        run: () => Quickshell.execDetached(["qs", "ipc", "call", "Terminus", "reveal", p]) },
      { text: "Terminal here", icon: "\u{F018D}", run: sh(Terminus.shellCommand(dir, "")) },
      { isSeparator: true },
      { text: tree.showHidden ? "Hide hidden files" : "Show hidden files", icon: "\u{F0209}", hint: ".",
        run: () => { tree.showHidden = !tree.showHidden; } },
      { text: "Collapse everything", icon: "\u{F0C49}", hint: "c", run: () => tree.collapseAll() },
    );
    return out;
  }
  // a copy beside it, named as terminus' Keep both names one: "a (1).txt"
  function duplicateSel() {
    const r = tree.flat[tree.actAt()];
    if (!r) return;
    const p = r.e.path;
    const dir = p.slice(0, p.lastIndexOf("/"));
    const name = Terminus.freeNameKeeping(tree.kids["k:" + dir] || [], r.e.name);
    const q = (x) => "'" + String(x).replace(/'/g, "'\\''") + "'";
    tree.run("cp -an -- " + q(p) + " " + q(Terminus.joinPath(dir, name)), () => tree.readKids(dir));
  }

  property var menuRows: []
  // The row a right click asked about while the cursor stays put; its menu
  // is about it (menuItems), and only a verb chosen brings the cursor over,
  // since the verbs act on tree.sel. -1 for the keyboard's menu.
  property int heldAt: -1
  // Whether the tree had the keyboard as the menu opened, and what did if
  // it did not: the menu borrows the keys and hands them back to whoever
  // had them, so a right click from the editor leaves you in the editor.
  property bool menuHadKeys: false
  property Item _focusBack: null
  function noteFocus() {
    if (menu.open) return;
    tree.menuHadKeys = list.focus && tree.focus;
    tree._focusBack = tree.menuHadKeys ? null : tree.Window.activeFocusItem;
  }
  function openMenu(at) {
    if (tree.given !== null) return;
    tree.noteFocus();
    tree.menuRows = tree.menuItems();
    menu.at = at;
    menu.open = true;
    menuKeys.forceActiveFocus();
  }
  function closeMenu() {
    tree.heldAt = -1;
    if (!menu.open) return;
    menu.open = false;
    const back = tree._menuBack;
    tree._menuBack = null;
    const was = tree._focusBack;
    tree._focusBack = null;
    if (back) back();
    else if (was) was.forceActiveFocus();
    else list.forceActiveFocus();
  }
  // Someone else's rows on the tree's menu — a properties card's "open
  // with" list ({ label, key?, act, sep? }) — and where the keys go after.
  property var _menuBack: null
  function openRows(at, rows, back) {
    tree.menuRows = (rows || []).map((r) => r.sep ? { isSeparator: true }
      : { text: r.label, hint: r.key || "", run: r.act });
    tree.noteFocus();
    tree._menuBack = back || null;
    tree.heldAt = -1;
    menu.at = at;
    menu.open = true;
    menuKeys.forceActiveFocus();
  }
  InputShield {
    parent: tree.window ? tree.window.contentItem : tree
    anchors.fill: parent
    visible: menu.open
    z: 1000
    onClicked: tree.closeMenu()
  }
  Item {
    id: menuKeys
    Keys.onPressed: (event) => {
      event.accepted = true;
      tree.closeMenu();
    }
  }
  CardPopup {
    id: menu
    window: tree.window
    fit: true
    cardWidth: 220
    model: tree.menuRows.map((it) => it.isSeparator ? { isSeparator: true }
      : { text: it.text, icon: it.icon, hint: it.hint || "", enabled: it.enabled !== false })
    onChosen: (i) => {
      const it = tree.menuRows[i];
      const h = tree.heldAt;
      tree.closeMenu();
      // the verb acts on the held row; the cursor stays (heldBox)
      if (it && it.run && it.enabled !== false) {
        tree.heldBox.i = h >= 0 && h < tree.flat.length ? h : -1;
        try { it.run(); } finally { tree.heldBox.i = -1; }
      }
    }
  }
}
