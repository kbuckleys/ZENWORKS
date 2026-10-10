// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// BRANCHES — yours, the remotes', and the tags, in one list: what each
// points at, how long ago, and (yours) how far ahead of and behind what it
// follows; the one checked out ringed, one checked out in another worktree
// marked with where.
//
//   return  switch to it (a remote one: a branch of yours following it)
//   n new branch · r rename · d delete · m merge into yours · b rebase
//   yours onto it · / filter · menu: everything else

import QtQuick
import "../morpheus"
import "../terminus"
import "delphi.js" as D

Item {
  id: pg
  property var win: null

  readonly property string title: "Branches"
  readonly property string subtitle: pg.win ? "on " + pg.win.branchName : ""
  readonly property var hints: [["return", pg.row && pg.row.kind === "remote" ? "track" : "switch"], ["n", "new"],
    ["m", "merge in"], ["b", "rebase onto"], ["r", "rename"], ["d", "delete"], ["/", "filter"], ["menu", "more"]]
  readonly property var buttons: [
    { label: "New branch", ink: Zenon.cyan, run: () => pg.create(null) },
  ]
  function takeFocus() { if (!filter.focused && pg.win) pg.win.focusKeys(); }

  property string query: ""
  readonly property var rows: {
    const r = pg.win ? pg.win.refs : { local: [], remote: [], tags: [] };
    const q = pg.query.toLowerCase();
    const keep = (b) => q === "" || b.name.toLowerCase().indexOf(q) >= 0;
    const out = [];
    const sec = (title, list, kind) => {
      const l = list.filter(keep);
      if (l.length === 0) return;
      out.push({ head: true, title: title, count: l.length });
      for (const b of l) out.push(Object.assign({ kind: kind }, b));
    };
    sec("Yours", r.local.slice().sort((a, b) => (b.current - a.current) || (b.when - a.when)), "local");
    sec("Remote", r.remote.slice().sort((a, b) => b.when - a.when), "remote");
    sec("Tags", r.tags.slice().sort((a, b) => b.when - a.when), "tag");
    return out;
  }
  property int sel: -1
  property string wantName: ""
  readonly property var row: pg.sel >= 0 && pg.sel < pg.rows.length && !pg.rows[pg.sel].head ? pg.rows[pg.sel] : null
  onRowsChanged: {
    let i = pg.wantName !== "" ? pg.rows.findIndex((r) => !r.head && r.kind + ":" + r.name === pg.wantName) : -1;
    if (i < 0) i = D.nextFile(pg.rows, Math.max(-1, Math.min(pg.sel, pg.rows.length) - 1), 1);
    pg.sel = i;
  }
  function moveTo(i) {
    if (i < 0 || i >= pg.rows.length || pg.rows[i].head) return;
    pg.sel = i;
    pg.wantName = pg.rows[i].kind + ":" + pg.rows[i].name;
    list.positionViewAtIndex(i, ListView.Contain);
  }

  // ── doing ──────────────────────────────────────────────────────────────
  function open(b) {
    if (!b) return;
    if (b.kind === "local") {
      if (b.current) return;
      if (b.worktree) { pg.win.say(b.name + " is checked out in " + D.tilde(b.worktree, pg.win.home), true); return; }
      pg.win.act("switch", { name: b.name }, { label: "Switching", said: "On " + b.name });
    } else if (b.kind === "remote") {
      const local = b.name.split("/").slice(1).join("/");
      if (pg.win.refs.local.some((l) => l.name === local)) {
        pg.win.act("switch", { name: local }, { said: "On " + local });
      } else {
        pg.win.act("branchTrack", { remoteBranch: b.name }, { said: "On " + local + ", following " + b.name });
      }
    } else {
      pg.win.confirm({ question: "Check out " + b.name + "?", glyph: "",
        detail: "Detached at the tag: make a branch there before committing.",
        verb: "Check out", then: () => pg.win.act("switch", { name: b.name, detach: true }, { said: "At " + b.name }) });
    }
  }
  function create(from) {
    const start = from ? from.name : "";
    pg.win.ask({ title: from ? "A branch from " + from.name : "A new branch", glyph: "",
      detail: from ? "" : "From where you are now (" + pg.win.branchName + ").",
      fields: [{ key: "name", label: "Name", hint: "feature/what-it-is" }],
      toggles: [{ key: "switch", label: "Switch to it", value: true }], verb: "Create",
      then: (v) => {
        const n = v.name.trim();
        pg.wantName = "local:" + n;
        pg.win.act("branchCreate", start ? { name: n, start: start, switch: v["switch"] } : { name: n, switch: v["switch"] },
                   { said: "Branch " + n + " created" });
      } });
  }
  function rename(b) {
    if (!b || b.kind !== "local") return;
    pg.win.ask({ title: "Rename " + b.name, glyph: "",
      fields: [{ key: "name", label: "New name", value: b.name }], verb: "Rename",
      then: (v) => { pg.wantName = "local:" + v.name.trim(); pg.win.act("branchRename", { old: b.name, "new": v.name.trim() }, {}); } });
  }
  function remove(b) {
    if (!b) return;
    if (b.kind === "tag") {
      pg.win.confirm({ question: "Delete the tag " + b.name + "?", glyph: "", ink: Zenon.red,
        detail: "Here only — a tag already pushed stays on the remote.", verb: "Delete",
        then: () => pg.win.act("tagDelete", { name: b.name }, { said: "Deleted " + b.name }) });
      return;
    }
    if (b.kind !== "local" || b.current) {
      pg.win.say(b.current ? "You are on it — switch to another branch first" : "Delete a remote branch from the remote itself", true);
      return;
    }
    pg.win.confirm({ question: "Delete " + b.name + "?", glyph: "", ink: Zenon.red,
      detail: "Only when its commits are already in another branch; git refuses otherwise, and you will be asked again.",
      verb: "Delete", then: () => pg.win.act("branchDelete", { name: b.name }, {
        said: "Deleted " + b.name,
        failed: (err) => {
          if (/not fully merged/.test(String(err && err.error))) {
            pg.win.confirm({ question: b.name + " has commits nowhere else", glyph: "", ink: Zenon.red,
              detail: "Deleting it anyway loses them (they linger in the reflog for a while).",
              verb: "Delete anyway", then: () => pg.win.act("branchDelete", { name: b.name, force: true }, { said: "Deleted " + b.name }) });
          } else pg.win.fail("Delete did not work", null, err);
        } }) });
  }
  function merge(b) {
    if (!b || b.current) return;
    pg.win.ask({ title: "Merge " + b.name + " into " + pg.win.branchName + "?", glyph: "",
      toggles: [{ key: "noff", label: "Always make a merge commit", value: false },
                { key: "squash", label: "Squash it into one change (staged, not committed)", value: false }],
      verb: "Merge",
      then: (v) => pg.win.act("merge", { rev: b.name, ff: v.noff ? "no-ff" : "ff", squash: !!v.squash }, {
        label: "Merging",
        then: (r) => pg.win.say(r && r.conflicts ? "Stopped on conflicts — resolve them in Changes" : "Merged " + b.name, r && r.conflicts) }) });
  }
  function rebaseOnto(b) {
    if (!b || b.current) return;
    pg.win.confirm({ question: "Rebase " + pg.win.branchName + " onto " + b.name + "?", glyph: "",
      detail: "Your commits are replayed on top of it — new commits, so a branch already pushed needs a force-push after.",
      verb: "Rebase", then: () => pg.win.act("rebase", { onto: b.name }, { label: "Rebasing",
        then: (r) => pg.win.say(r && r.conflicts ? "Stopped on conflicts — resolve them in Changes" : "Rebased onto " + b.name, r && r.conflicts) }) });
  }
  function follow(b) {
    pg.win.ask({ title: b.name + " follows…", glyph: "",
      detail: "The remote branch pull takes from and push sends to. Empty: none.",
      fields: [{ key: "up", label: "Upstream", value: b.upstream || "", hint: "origin/" + b.name, optional: true }],
      verb: "Set", then: (v) => pg.win.act("setUpstream", { branch: b.name, upstream: v.up.trim() }, {}) });
  }
  function tag(b) {
    pg.win.ask({ title: "Tag " + (b ? b.name : pg.win.branchName), glyph: "",
      fields: [{ key: "name", label: "Name", hint: "v1.0.0" },
               { key: "msg", label: "Message", hint: "optional — makes it an annotated tag", optional: true }],
      verb: "Tag", then: (v) => pg.win.act("tagCreate", { name: v.name.trim(), rev: b ? b.sha : "HEAD", message: v.msg.trim() || null },
                                          { said: "Tagged " + v.name.trim() }) });
  }
  function menuFor(b) {
    const items = [];
    if (b.kind === "local") {
      items.push({ text: b.current ? "Checked out" : "Switch to it", icon: "", mark: "return", enabled: !b.current && !b.worktree, run: () => pg.open(b) });
    } else if (b.kind === "remote") {
      items.push({ text: "Switch to a branch following it", icon: "", mark: "return", run: () => pg.open(b) });
    } else {
      items.push({ text: "Check out", icon: "", mark: "return", run: () => pg.open(b) });
    }
    items.push({ text: "New branch from here…", icon: "", run: () => pg.create(b) });
    items.push({ isSeparator: true });
    items.push({ text: "Merge into " + pg.win.branchName + "…", icon: "", mark: "m", enabled: !b.current, run: () => pg.merge(b) });
    items.push({ text: "Rebase " + pg.win.branchName + " onto it…", icon: "", mark: "b", enabled: !b.current, run: () => pg.rebaseOnto(b) });
    if (b.kind === "local") {
      items.push({ isSeparator: true });
      items.push({ text: "Follows…" + (b.upstream ? "  " + b.upstream : ""), icon: "", run: () => pg.follow(b) });
      items.push({ text: "Push", icon: "", enabled: !!b.upstream || pg.win.remotes.length > 0,
                   run: () => pg.win.act("push", b.upstream ? { remote: b.upstream.split("/")[0], branch: b.name }
                                                           : { remote: pg.win.remotes[0].name, branch: b.name, setUpstream: true },
                                         { label: "Pushing", network: true, said: "Pushed " + b.name }) });
      items.push({ text: "Tag it…", icon: "", run: () => pg.tag(b) });
      items.push({ text: "Rename…", icon: "", mark: "r", run: () => pg.rename(b) });
      items.push({ text: "Delete…", icon: "", mark: "d", danger: true, enabled: !b.current, run: () => pg.remove(b) });
    } else if (b.kind === "tag") {
      items.push({ isSeparator: true });
      items.push({ text: "Push the tag", icon: "", enabled: pg.win.remotes.length > 0,
                   run: () => pg.win.act("push", { remote: pg.win.remotes[0].name, branch: "refs/tags/" + b.name }, { label: "Pushing", network: true, said: "Pushed " + b.name }) });
      items.push({ text: "Delete…", icon: "", mark: "d", danger: true, run: () => pg.remove(b) });
    }
    items.push({ isSeparator: true });
    items.push({ text: "Copy the name", icon: "", run: () => pg.win.copy(b.name) });
    return items;
  }

  function key(e) {
    const k = e.key, ctrl = e.modifiers & Qt.ControlModifier, shift = e.modifiers & Qt.ShiftModifier;
    if (ctrl) return false;
    if (k === Qt.Key_Slash) { filter.claim(); return true; }
    if (k === Qt.Key_Up || k === Qt.Key_K) { pg.moveTo(D.nextFile(pg.rows, pg.sel, -1)); return true; }
    if (k === Qt.Key_Down || k === Qt.Key_J) { pg.moveTo(D.nextFile(pg.rows, pg.sel, 1)); return true; }
    if (k === Qt.Key_N) { pg.create(null); return true; }
    if (!pg.row) return false;
    if (k === Qt.Key_Return || k === Qt.Key_Enter) { pg.open(pg.row); return true; }
    if (k === Qt.Key_R) { pg.rename(pg.row); return true; }
    if (k === Qt.Key_D || k === Qt.Key_Delete) { pg.remove(pg.row); return true; }
    if (k === Qt.Key_M) { pg.merge(pg.row); return true; }
    if (k === Qt.Key_B) { pg.rebaseOnto(pg.row); return true; }
    if (k === Qt.Key_Menu || (shift && k === Qt.Key_F10)) {
      const it = list.itemAtIndex(pg.sel);
      const p = it ? it.mapToItem(pg, 60, it.height) : Qt.point(60, 60);
      menu.open(p.x, p.y, pg.menuFor(pg.row), pg.sel);
      return true;
    }
    if (k === Qt.Key_Escape && pg.query !== "") { filter.text = ""; pg.query = ""; return true; }
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
    ghost: "  Filter branches and tags  ( / )"
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
    bottomMargin: 6
    boundsBehavior: Flickable.StopAtBounds
    model: pg.rows
    readonly property int rowH: Math.round(Zenon.px(15) * 2.4)
    SelectBar { view: list; host: pg.win; index: Math.max(0, pg.sel); on: pg.sel >= 0; rowH: list.rowH; color: pg.win.hiFill; radius: Zenon.windowRadius; inset: 8 }
    delegate: Item {
      id: brow
      required property var modelData
      required property int index
      readonly property var b: brow.modelData
      width: list.width
      height: list.rowH
      Text {
        visible: !!brow.b.head
        x: 22
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: 4
        text: brow.b.head ? brow.b.title.toUpperCase() + "   " + brow.b.count : ""
        color: Zenon.muted
        font.family: Zenon.face
        font.weight: Font.Bold
        font.letterSpacing: 1
        font.features: { "tnum": 1 }
        font.pixelSize: Zenon.px(12)
      }
      Item {
        anchors.fill: parent
        visible: !brow.b.head
        Text {
          id: bg_
          x: 24
          width: 22
          anchors.verticalCenter: parent.verticalCenter
          text: brow.b.kind === "tag" ? "" : brow.b.kind === "remote" ? "" : ""
          color: brow.b.current ? Zenon.cyan : brow.b.kind === "tag" ? Zenon.sand : brow.b.kind === "remote" ? Zenon.blue : Zenon.green
          font.family: Zenon.glyphFace
          font.pixelSize: Zenon.px(15)
        }
        Text {
          id: bname
          anchors.left: bg_.right
          anchors.leftMargin: 6
          anchors.verticalCenter: parent.verticalCenter
          width: Math.min(implicitWidth, parent.width * 0.38)
          elide: Text.ElideMiddle
          text: brow.b.name || ""
          color: brow.b.current ? Zenon.cyan : Zenon.ink
          font.family: Zenon.face
          font.weight: brow.b.current ? Font.Bold : Zenon.weight
          font.pixelSize: Zenon.px(15)
        }
        // how it stands against what it follows
        Text {
          id: track
          anchors.left: bname.right
          anchors.leftMargin: 10
          anchors.verticalCenter: parent.verticalCenter
          text: brow.b.kind !== "local" ? "" : brow.b.gone ? "upstream gone"
            : (brow.b.ahead > 0 ? "↑" + brow.b.ahead + " " : "") + (brow.b.behind > 0 ? "↓" + brow.b.behind : "")
              + (brow.b.worktree && !brow.b.current ? "   " + D.baseName(brow.b.worktree) : "")
          color: brow.b.gone ? Zenon.red : Zenon.yellow
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.features: { "tnum": 1 }
          font.pixelSize: Zenon.px(13)
        }
        Text {
          anchors.left: track.right
          anchors.leftMargin: 14
          anchors.right: bwhen.left
          anchors.rightMargin: 14
          anchors.verticalCenter: parent.verticalCenter
          elide: Text.ElideRight
          text: brow.b.subject || ""
          color: Zenon.muted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(14)
        }
        Text {
          id: bwhen
          anchors.right: parent.right
          anchors.rightMargin: 24
          anchors.verticalCenter: parent.verticalCenter
          text: brow.b.when ? D.ago(brow.b.when, Date.now()) : ""
          color: Zenon.muted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.features: { "tnum": 1 }
          font.pixelSize: Zenon.px(13)
        }
        HeldRing { anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8; on: menu.isOpen && menu.held === brow.index }
        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          onClicked: (m) => {
            if (m.button === Qt.RightButton) {
              const p = mapToItem(pg, m.x, m.y);
              menu.open(p.x, p.y, pg.menuFor(brow.b), brow.index);
              return;
            }
            pg.moveTo(brow.index);
            pg.win.focusKeys();
          }
          onDoubleClicked: pg.open(brow.b)
        }
      }
    }
    EmptyMark {
      anchors.centerIn: parent
      visible: pg.rows.length === 0
      filtered: pg.query !== ""
      word: pg.query !== "" ? "" : "No branches yet — make the first commit"
    }
  }
  ElasticScroll { anchors.fill: list; view: list }
  Scrollbar { flick: list; anchors.right: list.right; anchors.top: list.top; anchors.bottom: list.bottom }

  PopMenu {
    id: menu
    anchors.fill: parent
    window: pg.win
    cardWidth: 280
    onClosed: pg.win.focusKeys()
  }
}
