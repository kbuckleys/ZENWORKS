// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// REPOSITORIES — the ones opened before (newest first) and the ones found on
// disk, and the ways to a new one: open a directory, clone from an address,
// or start one (git init) where you choose.
//
// Finding looks a few levels down from home (delphi/core repo.scan: hidden
// directories other than .config skipped, a repository not looked inside),
// streaming what it finds as it goes.
//
//   return open · d forget (off delphi's lists; the files stay)
//   shift d delete (the directory to the trash, after asking)
//   o open a directory · c clone · i new repository · f find on disk
//   / filter

import QtQuick
import "../morpheus"
import "../terminus"
import "delphi.js" as D
import "../terminus/terminus.js" as Terminus
import Quickshell.Io

Item {
  id: pg
  property var win: null
  // the views whose rows carry on up under the window's head, frosted
  // (DelphiWindow's ScrollEdges) — only those with nothing but controls
  // between them and the head: a view under a title would paint over it
  readonly property var edgeViews: [list]

  readonly property string title: "Repositories"
  readonly property string subtitle: pg.scanning ? "Looking…" : pg.win && pg.win.root !== "" ? "Now: " + D.tilde(pg.win.root, pg.win.home) : "None open"
  readonly property var hints: [["return", "open"], ["o", "open a directory"], ["c", "clone"], ["i", "new"],
                                ["f", "find on disk"], ["d", "forget"], ["shift d", "delete"], ["/", "filter"]]
  readonly property var buttons: [
    { label: "Delete", ink: Zenon.red, visible: !!pg.row, run: () => pg.trash(pg.row) },
    { label: "Forget", visible: !!pg.row, run: () => pg.forget(pg.row) },
    { label: "Find on disk", visible: !pg.scanning, run: () => pg.scan() },
    { label: "New", run: () => pg.init() },
    { label: "Clone", run: () => pg.clone() },
    { label: "Open", ink: Zenon.cyan, primary: true, run: () => pg.win.chooseRepo() },
  ]
  function takeFocus() { if (!filter.focused && pg.win) pg.win.focusKeys(); }

  property var found: []
  property bool scanning: false
  property int scanJob: -1
  property string query: ""
  readonly property var rows: {
    const q = pg.query.toLowerCase();
    const keep = (r) => q === "" || (r.name + " " + r.root).toLowerCase().indexOf(q) >= 0;
    const out = [];
    const recent = (pg.win && pg.win.mgr ? pg.win.mgr.recents : []).filter(keep);
    if (recent.length) {
      out.push({ head: true, title: "Opened before", count: recent.length });
      for (const r of recent) out.push({ kind: "recent", root: r.root, name: r.name, at: r.at });
    }
    const seen = {};
    for (const r of recent) seen[r.root] = true;
    const gone = pg.win && pg.win.mgr ? pg.win.mgr.hidden : [];
    const more = pg.found.filter((r) => !seen[r.root] && gone.indexOf(r.root) < 0 && keep(r));
    if (more.length) {
      out.push({ head: true, title: "Found on disk", count: more.length });
      for (const r of more) out.push({ kind: "found", root: r.root, name: r.name });
    }
    return out;
  }
  property int sel: -1
  readonly property var row: pg.sel >= 0 && pg.sel < pg.rows.length && !pg.rows[pg.sel].head ? pg.rows[pg.sel] : null
  onRowsChanged: if (!pg.row) pg.sel = D.nextFile(pg.rows, -1, 1)
  function moveTo(i) {
    if (i < 0 || i >= pg.rows.length || pg.rows[i].head) return;
    pg.sel = i;
    list.positionViewAtIndex(i, ListView.Contain);
  }

  function scan() {
    if (pg.scanning) return;
    pg.scanning = true;
    pg.found = [];
    pg.scanJob = pg.win.mgr.call("scan", null, { roots: pg.win.mgr.scanRoots, depth: 4 }, (ok, res) => { if (!pg) return;
      pg.scanning = false;
      if (ok) pg.found = res;
    }, (ev) => { if (!pg) return; if (ev.found) pg.found = pg.found.concat([ev.found]); });
  }
  Component.onDestruction: if (pg.scanning && pg.win) pg.win.mgr.cancel(pg.scanJob)
  Component.onCompleted: if (pg.win && pg.win.mgr.recents.length < 3) Qt.callLater(pg.scan)

  // FORGET: off delphi's lists, nothing on disk touched — for one opened or
  // made by mistake. Said with the way back, since it asks nothing.
  function forget(r) {
    if (!r) return;
    pg.win.mgr.forget(r.root);
    pg.win.say("Forgot " + r.name + " — its files are where they were; open it to bring it back");
  }
  // DELETE: the whole directory to the trash (terminus' own command, gio
  // trash — so the trash can give it back), after a card that says what
  // goes and whether its forge still has it. The one open here is closed first.
  function trash(r) {
    if (!r) return;
    pg.win.mgr.call("remotes", r.root, {}, (ok, rs) => {
      if (!pg) return;
      const remote = ok && rs.length > 0 ? D.remoteOf(rs[0].fetch || rs[0].push) : null;
      pg.win.confirm({ question: "Delete " + r.name + "?", glyph: "", ink: Zenon.red,
        detail: "The directory and everything in it — its history, and any work not pushed — go to the trash. "
          + (remote ? "The copy on " + remote.host + " (" + remote.full + ") is not touched." : "It has no remote: this is the only copy."),
        items: [D.tilde(r.root, pg.win.home)], verb: "Move to trash",
        then: () => {
          if (pg.win.root === r.root) { pg.win.unwatch(); pg.win.closeRepo(); }
          trasher.root = r.root;
          trasher.name = r.name;
          // terminus' command is { script, args }, run through its shArgv
          trasher.command = Terminus.shArgv(Terminus.trashCommand([r.root]));
          trasher.running = true;
        } });
    });
  }
  Process {
    id: trasher
    property string root: ""
    property string name: ""
    stderr: StdioCollector { id: trashErr }
    onExited: (code) => {
      if (code === 0) {
        pg.win.mgr.forget(trasher.root);
        pg.found = pg.found.filter((f) => f.root !== trasher.root);
        pg.win.say("Moved " + trasher.name + " to the trash");
      } else pg.win.fail("Could not delete " + trasher.name, null, { error: String(trashErr.text).trim() || "gio trash failed" });
    }
  }

  function clone() {
    pg.win.ask({ title: "Clone a repository", glyph: "",
      detail: "Its address — https://… or git@… — from GitHub, GitLab, Codeberg or anywhere. Your own ones are on the Accounts page.",
      fields: [{ key: "url", label: "Address", hint: "https://codeberg.org/someone/something.git" },
               { key: "into", label: "Into the directory", value: pg.win.home + "/", path: true }],
      toggles: [{ key: "light", label: "History without file contents (much faster for huge repositories)", value: false }],
      verb: "Clone",
      then: (v) => {
        const url = v.url.trim();
        const dest = v.into.trim().replace(/\/$/, "") + "/" + D.cloneName(url);
        pg.win.act("clone", { url: url, dest: dest, blobless: !!v.light }, { repo: null, label: "Cloning " + D.cloneName(url),
          network: true, refresh: false, said: "Cloned into " + D.tilde(dest, pg.win.home), then: () => pg.win.openRepo(dest) });
      } });
  }
  function init() {
    pg.win.ask({ title: "A new repository", glyph: "",
      detail: "An empty repository in a directory — made if it is not there yet. To publish it, the Accounts page.",
      fields: [{ key: "path", label: "Directory", value: pg.win.home + "/", path: true },
               { key: "branch", label: "First branch", value: "main" }],
      verb: "Create",
      then: (v) => pg.win.act("init", { path: v.path.trim(), branch: v.branch.trim() || null }, { repo: null, refresh: false,
        said: "Created", then: (info) => pg.win.openRepo(info.root) }) });
  }

  function key(e) {
    const k = e.key;
    if (e.modifiers & Qt.ControlModifier) return false;
    if (k === Qt.Key_Slash) { filter.claim(); return true; }
    if (k === Qt.Key_O) { pg.win.chooseRepo(); return true; }
    if (k === Qt.Key_C) { pg.clone(); return true; }
    if (k === Qt.Key_I) { pg.init(); return true; }
    if (k === Qt.Key_F) { pg.scan(); return true; }
    if (k === Qt.Key_Up || k === Qt.Key_K) { pg.moveTo(D.nextFile(pg.rows, pg.sel, -1)); return true; }
    if (k === Qt.Key_Down || k === Qt.Key_J) { pg.moveTo(D.nextFile(pg.rows, pg.sel, 1)); return true; }
    if (!pg.row) return false;
    if (k === Qt.Key_Return || k === Qt.Key_Enter) { pg.win.openRepo(pg.row.root); return true; }
    if ((k === Qt.Key_D && (e.modifiers & Qt.ShiftModifier)) || (k === Qt.Key_Delete && (e.modifiers & Qt.ShiftModifier))) { pg.trash(pg.row); return true; }
    if (k === Qt.Key_D || k === Qt.Key_Delete) { pg.forget(pg.row); return true; }
    if (k === Qt.Key_Escape && pg.query !== "") { filter.text = ""; return true; }
    return false;
  }

  BulkField {
    id: filter
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: 12
    height: 32
    textSize: Zenon.px(15)
    ghost: "  Filter  ( / )"
    clearable: true
    onTextChanged: pg.query = filter.text.trim()
    onAccepted: pg.win.focusKeys()
    Keys.onEscapePressed: { filter.text = ""; pg.win.focusKeys(); }
    Keys.onDownPressed: pg.win.focusKeys()
  }
  ListView {
    id: list
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: filter.bottom
    anchors.topMargin: 8
    anchors.bottom: parent.bottom
    clip: true
    bottomMargin: 8
    boundsBehavior: Flickable.StopAtBounds
    model: pg.rows
    readonly property int rowH: Math.round(Zenon.px(15) * 3.2)
    SelectBar { view: list; host: pg.win; index: Math.max(0, pg.sel); on: pg.sel >= 0; rowH: list.rowH; color: pg.win.hiFill; radius: Zenon.windowRadius; inset: 8 }
    delegate: Item {
      id: rrow
      required property var modelData
      required property int index
      readonly property var r: rrow.modelData
      width: list.width
      height: list.rowH
      Text {
        visible: !!rrow.r.head
        x: 22
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: 6
        text: rrow.r.head ? rrow.r.title.toUpperCase() + "   " + rrow.r.count : ""
        color: Zenon.muted
        font.family: Zenon.face
        font.weight: Font.Bold
        font.letterSpacing: 1
        font.features: { "tnum": 1 }
        font.pixelSize: Zenon.px(12)
      }
      Item {
        anchors.fill: parent
        visible: !rrow.r.head
        readonly property bool here: !!pg.win && rrow.r.root === pg.win.root
        Text {
          id: rg
          x: 24
          anchors.verticalCenter: parent.verticalCenter
          text: ""
          color: parent.here ? Zenon.cyan : Zenon.muted
          font.family: Zenon.glyphFace
          font.pixelSize: Zenon.px(17)
        }
        Column {
          anchors.left: rg.right
          anchors.leftMargin: 14
          anchors.right: parent.right
          anchors.rightMargin: 24
          anchors.verticalCenter: parent.verticalCenter
          spacing: 3
          Text {
            width: parent.width
            elide: Text.ElideRight
            text: (rrow.r.name || "") + (parent.parent.here ? "   ·   open" : "")
            color: parent.parent.here ? Zenon.cyan : Zenon.ink
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(16)
          }
          Text {
            width: parent.width
            elide: Text.ElideMiddle
            text: D.tilde(rrow.r.root, pg.win.home) + (rrow.r.at ? "   ·   " + D.ago(Math.floor(rrow.r.at / 1000), Date.now()) : "")
            color: Zenon.muted
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(13)
          }
        }
        MouseArea {
          anchors.fill: parent
          onClicked: { pg.moveTo(rrow.index); pg.win.focusKeys(); }
          onDoubleClicked: pg.win.openRepo(rrow.r.root)
        }
      }
    }
    footer: Item { width: list.width; height: pg.scanning ? 50 : 0; Working { anchors.centerIn: parent; running: pg.scanning } }
    EmptyMark {
      anchors.centerIn: parent
      visible: pg.rows.length === 0 && !pg.scanning
      filtered: pg.query !== ""
      word: pg.query !== "" ? "" : "No repositories yet — open, clone or start one"
    }
  }
  ElasticScroll { anchors.fill: list; view: list }
  Scrollbar { flick: list; anchors.right: list.right; anchors.top: list.top; anchors.bottom: list.bottom }
}
