// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// REPOSITORIES — the ones opened before (newest first) and the ones found on
// disk, and the ways to a new one: open a directory, clone from an address,
// or start one (git init) where you choose.
//
// THE OVERVIEW (user, 2026-10-14): each one opened before at a glance —
// its branch, what changed, what is to push or pull, its forge and its
// checks (delphi/core summaries, CI from the forge) — and the ones with
// something to do gathered first, under Needs attention. Fetch all asks
// every remote quietly, so the ↓ counts are what is there now.
//
// Finding looks a few levels down from home (delphi/core repo.scan: hidden
// directories other than .config skipped, a repository not looked inside),
// streaming what it finds as it goes.
//
//   return open · d forget (off delphi's lists; files and forge untouched —
//   for one no longer kept up; listed under Forgotten, d there brings it back)
//   shift d delete (the directory to the trash, after asking) · right click
//   A listed one whose files went (directory gone, or no .git) is marked
//   missing; d removes it from every list, and "Remove missing" all of them.
//   o open a directory · c clone · i new repository · f find on disk
//   r fetch all · a archive on its forge · / filter

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
  readonly property string subtitle: pg.fetchTotal > 0 ? "Fetching " + Math.min(pg.fetchDone + 1, pg.fetchTotal) + " of " + pg.fetchTotal + "…"
    : pg.scanning ? "Looking…"
    : pg.needy > 0 ? pg.needy + (pg.needy === 1 ? " needs" : " need") + " attention"
    : pg.win && pg.win.mgr.recents.length > 0 ? "All caught up" : "None open"
  readonly property var hints: [["return", "open"], ["o", "open a directory"], ["c", "clone"], ["i", "new"],
                                ["f", "find on disk"], ["r", "fetch all"]].concat(pg.hubOfRow(pg.row) ? [["a", "archive"]] : []).concat([ ["d", pg.row && pg.missing[pg.row.root] ? "remove" : pg.row && pg.row.kind === "forgotten" ? "remember" : "forget"], ["shift d", "delete"], ["/", "filter"]])
  readonly property var buttons: [
    { label: "Remove " + pg.lost.length + " missing", ink: Zenon.yellow, visible: pg.lost.length > 1, run: () => pg.dropMissing() },
    { label: "Delete", ink: Zenon.red, visible: !!pg.row && pg.missing[pg.row.root] !== "gone", run: () => pg.trash(pg.row) },
    { label: pg.row && pg.missing[pg.row.root] ? "Remove" : pg.row && pg.row.kind === "forgotten" ? "Remember" : "Forget",
      visible: !!pg.row, run: () => pg.forget(pg.row) },
    { label: "Find on disk", visible: !pg.scanning, run: () => pg.scan() },
    { label: "Fetch all", visible: pg.fetchTotal === 0 && !!pg.win && pg.win.mgr.recents.length > 0, run: () => pg.fetchAll() },
    { label: "New", run: () => pg.init() },
    { label: "Clone", run: () => pg.clone() },
    { label: "Open", ink: Zenon.cyan, primary: true, run: () => pg.win.chooseRepo() },
  ]
  function takeFocus() { if (!filter.focused && pg.win) pg.win.focusKeys(); }

  property var found: []
  // root → "gone" | "plain", for the listed ones whose files went
  // (delphi/core missing), asked whenever the lists change
  property var missing: ({})
  readonly property var lost: Object.keys(pg.missing)
  function checkMissing() {
    if (!pg.win || !pg.win.mgr) return;
    const roots = pg.win.mgr.recents.map((r) => r.root).concat(pg.win.mgr.hidden);
    pg.win.mgr.call("missing", null, { roots: roots }, (ok, res) => { if (pg && ok) pg.missing = res || {}; });
    pg.summarise();
  }
  Connections {
    target: pg.win ? pg.win.mgr : null
    function onRecentsChanged() { Qt.callLater(pg.checkMissing); }
    function onHiddenChanged() { Qt.callLater(pg.checkMissing); }
  }
  onVisibleChanged: if (pg.visible) pg.checkMissing()
  // the window is handed in after the page is made: ask once it is here
  onWinChanged: Qt.callLater(pg.checkMissing)
  function dropMissing() {
    const n = pg.lost.length;
    for (const root of pg.lost) pg.win.mgr.drop(root);
    pg.win.say("Removed " + n + " missing " + (n === 1 ? "repository" : "repositories"));
  }
  // ── AT A GLANCE ──────────────────────────────────────────────────────
  // root → summary (branch, changed, ahead/behind, state, remotes), for
  // the ones opened before; asked with the missing ones
  property var sums: ({})
  function summarise() {
    if (!pg.win || !pg.win.mgr) return;
    const roots = pg.win.mgr.recents.map((r) => r.root);
    pg.win.mgr.call("summaries", null, { roots: roots }, (ok, res) => {
      if (!pg || !ok) return;
      const o = {};
      for (const x of res) {
        o[x.root] = x;
        const h = D.hubOf(x.remotes, true);
        if (h && x.oid) pg.win.mgr.ciAsk(h.forge, h.full, [x.oid]);
      }
      pg.sums = o;
    });
  }
  // its forge repository (its own: origin first), from the summary
  function hubOfRow(r) {
    if (!r || !pg.sums[r.root]) return null;
    pg.win.mgr.servers;
    return D.hubOf(pg.sums[r.root].remotes, true);
  }
  function ciOfRow(r) {
    const h = pg.hubOfRow(r), x = r ? pg.sums[r.root] : null;
    if (!h || !x || !x.oid) return null;
    pg.win.mgr.ci;
    return pg.win.mgr.ciOf(h.forge, h.full, x.oid);
  }
  function attentionOfRow(r) {
    if (!r) return [];
    if (pg.missing[r.root] === "gone") return [{ word: "gone from disk", ink: "yellow" }];
    if (pg.missing[r.root] === "plain") return [{ word: "no longer a repository", ink: "yellow" }];
    return D.attentionOf(pg.sums[r.root], pg.ciOfRow(r));
  }
  readonly property int needy: (pg.win ? pg.win.mgr.recents : []).filter((r) => pg.attentionOfRow(r).length > 0).length

  // FETCH ALL: every one opened before, quietly (delphi/core fetch_quiet:
  // nothing asked, a failure skipped), three at a time, then summarised
  property int fetchTotal: 0
  property int fetchDone: 0
  property int fetchFailed: 0
  function fetchAll() {
    const roots = pg.win.mgr.recents.map((r) => r.root).filter((root) => !pg.missing[root] && pg.sums[root] && pg.sums[root].remotes.length > 0);
    if (roots.length === 0) { pg.win.say("Nothing here has a remote to fetch from"); return; }
    pg.fetchTotal = roots.length;
    pg.fetchDone = 0;
    pg.fetchFailed = 0;
    const queue = roots.slice();
    const next = () => {
      if (!pg || queue.length === 0) return;
      const root = queue.shift();
      pg.win.mgr.call("fetchQuiet", root, {}, (ok) => {
        if (!pg) return;
        if (ok) pg.win.mgr.noteFetched(root); else pg.fetchFailed++;
        pg.fetchDone++;
        if (pg.fetchDone >= pg.fetchTotal) {
          const failed = pg.fetchFailed;
          pg.fetchTotal = 0;
          pg.summarise();
          if (pg.win.root !== "") pg.win.refresh();
          pg.win.say("Fetched " + (roots.length - failed) + " of " + roots.length + (failed > 0 ? " — " + failed + " could not be reached quietly; open one and Fetch to see why" : ""), failed > 0);
        } else next();
      });
    };
    for (let i = 0; i < Math.min(3, roots.length); i++) next();
  }

  // ARCHIVE: the forge's copy read-only, kept (DelphiWindow.archiveOnForge);
  // the one here forgotten too when asked
  function archive(r) {
    const h = pg.hubOfRow(r);
    if (!h) { pg.win.say("No GitHub, GitLab or Codeberg repository behind " + (r ? r.name : "this"), true); return; }
    pg.win.archiveOnForge(h, { root: r.root, name: r.name });
  }

  property bool scanning: false
  property int scanJob: -1
  property string query: ""
  readonly property var rows: {
    const q = pg.query.toLowerCase();
    const keep = (r) => q === "" || (r.name + " " + r.root).toLowerCase().indexOf(q) >= 0;
    const out = [];
    const recent = (pg.win && pg.win.mgr ? pg.win.mgr.recents : []).filter(keep);
    // the ones with something to do first, then the rest
    const needs = recent.filter((r) => pg.attentionOfRow(r).length > 0);
    const calm = recent.filter((r) => pg.attentionOfRow(r).length === 0);
    if (needs.length) {
      out.push({ head: true, title: "Needs attention", count: needs.length });
      for (const r of needs) out.push({ kind: "recent", root: r.root, name: r.name, at: r.at });
    }
    if (calm.length) {
      out.push({ head: true, title: needs.length ? "Up to date" : "Opened before", count: calm.length });
      for (const r of calm) out.push({ kind: "recent", root: r.root, name: r.name, at: r.at });
    }
    const seen = {};
    for (const r of recent) seen[r.root] = true;
    const gone = pg.win && pg.win.mgr ? pg.win.mgr.hidden : [];
    const more = pg.found.filter((r) => !seen[r.root] && gone.indexOf(r.root) < 0 && keep(r));
    if (more.length) {
      out.push({ head: true, title: "Found on disk", count: more.length });
      for (const r of more) out.push({ kind: "found", root: r.root, name: r.name });
    }
    // the forgotten, last and dimmed: the way back, rather than gone for good
    const forgot = gone.map((root) => ({ root: root, name: D.baseName(root) })).filter(keep);
    if (forgot.length) {
      out.push({ head: true, title: "Forgotten", count: forgot.length });
      for (const r of forgot) out.push({ kind: "forgotten", root: r.root, name: r.name });
    }
    return out;
  }
  property int sel: -1
  // the chosen one by its root as well: rows move between Needs attention
  // and Up to date as the summaries come, and the choice goes with its row
  property string selRoot: ""
  readonly property var row: pg.sel >= 0 && pg.sel < pg.rows.length && !pg.rows[pg.sel].head ? pg.rows[pg.sel] : null
  onRowsChanged: {
    const i = pg.selRoot !== "" ? pg.rows.findIndex((r) => !r.head && r.root === pg.selRoot) : -1;
    if (i >= 0) pg.sel = i;
    else if (!pg.row) pg.sel = D.nextFile(pg.rows, -1, 1);
  }
  function moveTo(i) {
    if (i < 0 || i >= pg.rows.length || pg.rows[i].head) return;
    pg.sel = i;
    pg.selRoot = pg.rows[i].root;
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
  Component.onCompleted: { pg.checkMissing(); if (pg.win && pg.win.mgr.recents.length < 3) Qt.callLater(pg.scan); }

  // FORGET: off delphi's lists, nothing on disk or on its forge touched —
  // for one no longer kept up, or opened by mistake (the open one closes).
  // On a forgotten row it is the way back: remembered, not opened.
  function forget(r) {
    if (!r) return;
    if (pg.missing[r.root]) { pg.win.mgr.drop(r.root); pg.win.say("Removed " + r.name + " from Delphi"); return; }
    if (r.kind === "forgotten") { pg.win.mgr.unforget(r.root); pg.win.say("Remembered " + r.name); return; }
    pg.win.forgetRepo(r.root, r.name);
  }
  // the right-click menu: the same things the keys and buttons do
  function rowMenu(item, index) {
    const r = pg.rows[index];
    if (!r || r.head) return;
    pg.moveTo(index);
    const gone = r.kind === "forgotten";
    if (pg.missing[r.root]) {
      const items = [{ text: "Remove from Delphi", icon: "\uF00D", mark: "d", run: () => pg.forget(r) }];
      if (pg.lost.length > 1) items.push({ text: "Remove all " + pg.lost.length + " missing", icon: "\uF00D", run: () => pg.dropMissing() });
      if (pg.missing[r.root] === "plain") items.push({ isSeparator: true },
        { text: "Show in terminus", icon: "\uF07C", run: () => pg.win.reveal(r.root) });
      const p = item.mapToItem(pg, 40, item.height);
      rowPop.open(p.x, p.y, items, index);
      return;
    }
    const items = [{ text: "Open", icon: "\uF401", mark: "return", run: () => pg.win.openRepo(r.root) },
                   { text: "Show in terminus", icon: "\uF07C", run: () => pg.win.reveal(r.root) },
                   { text: "Copy its path", icon: "\uF0C5", run: () => pg.win.copy(r.root, "the path") },
                   { isSeparator: true }];
    const h = pg.hubOfRow(r);
    if (h) items.push({ text: "Archive on " + (D.FORGES[h.forge] ? D.FORGES[h.forge].name : h.host) + "…", icon: "\uF187", mark: "a", run: () => pg.archive(r) },
                      { isSeparator: true });
    items.push(gone ? { text: "Remember", icon: "\uF06E", mark: "d", run: () => pg.forget(r) }
                        : { text: "Forget — files and forge untouched", icon: "\uF070", mark: "d", run: () => pg.forget(r) },
                   { text: "Delete…", icon: "\uF1F8", mark: "shift d", danger: true, run: () => pg.trash(r) });
    const p = item.mapToItem(pg, 40, item.height);
    rowPop.open(p.x, p.y, items, index);
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
        // off every list, Forgotten too: there is nothing left to remember
        pg.win.mgr.forget(trasher.root);
        pg.win.mgr.unforget(trasher.root);
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
    if (k === Qt.Key_R) { if (pg.fetchTotal === 0) pg.fetchAll(); return true; }
    if (k === Qt.Key_Up || k === Qt.Key_K) { pg.moveTo(D.nextFile(pg.rows, pg.sel, -1)); return true; }
    if (k === Qt.Key_Down || k === Qt.Key_J) { pg.moveTo(D.nextFile(pg.rows, pg.sel, 1)); return true; }
    if (!pg.row) return false;
    if (k === Qt.Key_Return || k === Qt.Key_Enter) { pg.win.openRepo(pg.row.root); return true; }
    if (k === Qt.Key_A && pg.hubOfRow(pg.row)) { pg.archive(pg.row); return true; }
    if ((k === Qt.Key_D && (e.modifiers & Qt.ShiftModifier)) && pg.missing[pg.row.root] === "gone") return true;
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
      GroupHead {
        visible: !!rrow.r.head
        title: rrow.r.head ? rrow.r.title : ""
        count: rrow.r.head ? rrow.r.count : -1
      }
      Item {
        anchors.fill: parent
        visible: !rrow.r.head
        readonly property bool here: !!pg.win && rrow.r.root === pg.win.root
        readonly property string lostAs: pg.missing[rrow.r.root] || ""
        opacity: rrow.r.kind === "forgotten" ? 0.55 : 1
        Text {
          id: rg
          x: 24
          anchors.verticalCenter: parent.verticalCenter
          text: ""
          color: parent.lostAs !== "" ? Zenon.yellow : parent.here ? Zenon.cyan : Zenon.accentMuted
          font.family: Zenon.glyphFace
          font.pixelSize: Zenon.px(17)
        }
        // its forge and what its checks said of its head, on the right
        Row {
          id: tail
          anchors.right: parent.right
          anchors.rightMargin: 24
          anchors.verticalCenter: parent.verticalCenter
          spacing: 10
          readonly property var hub: pg.hubOfRow(rrow.r)
          CiDot { anchors.verticalCenter: parent.verticalCenter; c: pg.ciOfRow(rrow.r) }
          Text {
            visible: !!tail.hub
            anchors.verticalCenter: parent.verticalCenter
            text: tail.hub && D.FORGES[tail.hub.forge] ? D.FORGES[tail.hub.forge].glyph : ""
            color: Zenon.accentMuted
            font.family: Zenon.glyphFace
            font.pixelSize: Zenon.px(15)
          }
        }
        Column {
          anchors.left: rg.right
          anchors.leftMargin: 14
          anchors.right: tail.left
          anchors.rightMargin: 14
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
          // what needs doing, each in its colour (or when it was last
          // opened, when nothing does), its branch, then where it is
          Text {
            width: parent.width
            elide: Text.ElideRight
            textFormat: Text.StyledText
            readonly property var sum: pg.sums[rrow.r.root] || null
            readonly property var needs: pg.attentionOfRow(rrow.r)
            text: {
              const dot = "&nbsp;&nbsp;·&nbsp;&nbsp;";
              // what needs doing first: a long path would elide it away
              const parts = needs.map((a) => "<font color='" + Zenon.hex(Zenon[a.ink]) + "'>" + D.esc(a.word) + "</font>");
              if (sum && sum.branch) parts.push("<font color='" + Zenon.hex(Zenon.accentSoft) + "'>" + D.esc(sum.branch) + "</font>");
              if (needs.length === 0 && rrow.r.at) parts.push(D.ago(Math.floor(rrow.r.at / 1000), Date.now()));
              parts.push(D.esc(D.tilde(rrow.r.root, pg.win.home)));
              return parts.join(dot);
            }
            color: Zenon.accentMuted
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(13)
          }
        }
        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          onClicked: (m) => { if (m.button === Qt.RightButton) { pg.rowMenu(rrow, rrow.index); return; } pg.moveTo(rrow.index); pg.win.focusKeys(); }
          onDoubleClicked: pg.win.openRepo(rrow.r.root)
        }
      }
    }
    footer: Item { width: list.width; height: pg.scanning && pg.rows.length > 0 ? 50 : 0; Working { anchors.centerIn: parent; running: pg.scanning && pg.rows.length > 0 } }
    Working { anchors.centerIn: parent; running: pg.scanning && pg.rows.length === 0; visible: running }
    EmptyMark {
      anchors.centerIn: parent
      visible: pg.rows.length === 0 && !pg.scanning
      filtered: pg.query !== ""
      word: pg.query !== "" ? "" : "No repositories yet — open, clone or start one"
    }
  }
  ElasticScroll { anchors.fill: list; view: list }
  PopMenu {
    id: rowPop
    anchors.fill: parent
    window: pg.win
    cardWidth: 320
    onClosed: pg.takeFocus()
  }
  Scrollbar { flick: list; anchors.right: list.right; anchors.top: list.top; anchors.bottom: list.bottom }
}
