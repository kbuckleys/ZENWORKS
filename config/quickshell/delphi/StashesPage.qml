// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// STASHES — work put aside: newest first, what each one changed beside it.
//
//   n stash now · return apply · p pop (apply and drop) · d drop
//   b a branch from it (for one that no longer applies cleanly)

import QtQuick
import "../morpheus"
import "../terminus"
import "delphi.js" as D

Item {
  id: pg
  property var win: null

  readonly property string title: "Stashes"
  readonly property string subtitle: pg.stashes.length === 0 ? "Nothing put aside"
    : pg.stashes.length + (pg.stashes.length === 1 ? " stash" : " stashes")
  readonly property var hints: [["n", "stash now"], ["return", "apply"], ["p", "pop"], ["d", "drop"], ["b", "branch"]]
  readonly property var buttons: [
    { label: "Drop", ink: Zenon.red, visible: !!pg.stash, run: () => pg.drop() },
    { label: "Apply", visible: !!pg.stash, run: () => pg.apply(false) },
    { label: "Stash changes", ink: Zenon.cyan, primary: true, run: () => pg.push() },
  ]
  function takeFocus() { if (pg.win) pg.win.focusKeys(); }

  property var stashes: []
  property int sel: 0
  readonly property var stash: pg.sel >= 0 && pg.sel < pg.stashes.length ? pg.stashes[pg.sel] : null
  property var diffFiles: []

  function reload() {
    if (!pg.win || pg.win.root === "") return;
    pg.win.mgr.call("stashes", pg.win.root, {}, (ok, list) => { if (!pg) return;
      if (!ok) return;
      pg.stashes = list;
      pg.sel = Math.max(0, Math.min(pg.sel, list.length - 1));
      pg.loadDiff();
    });
  }
  Component.onCompleted: Qt.callLater(pg.reload)
  Connections {
    target: pg.win
    function onStatusEpochChanged() { pg.reload(); }
  }
  function loadDiff() {
    const s = pg.stash;
    if (!s) { pg.diffFiles = []; return; }
    const sha = s.sha;
    pg.win.mgr.call("show", pg.win.root, { rev: sha, budget: 6000 }, (ok, res) => { if (!pg) return;
      if (ok && pg.stash && pg.stash.sha === sha) { pg.diffFiles = res.files; diff.toFirst(); }
    });
  }
  function moveTo(i) {
    if (pg.stashes.length === 0) return;
    pg.sel = Math.max(0, Math.min(pg.stashes.length - 1, i));
    list.positionViewAtIndex(pg.sel, ListView.Contain);
    pg.loadDiff();
  }

  function push() {
    pg.win.ask({ title: "Put your changes aside", glyph: "",
      fields: [{ key: "msg", label: "What it is", hint: "optional", optional: true }],
      toggles: [{ key: "untracked", label: "New files too", value: true },
                { key: "staged", label: "Only what is staged", value: false }],
      verb: "Stash",
      then: (v) => pg.win.act("stashPush", { message: v.msg.trim() || null, untracked: !!v.untracked, stagedOnly: !!v.staged },
                              { said: "Stashed" }) });
  }
  function apply(pop) {
    const s = pg.stash;
    if (!s) return;
    pg.win.act("stashApply", { ref: s.ref, pop: pop }, { said: pop ? "Popped " + s.ref : "Applied " + s.ref,
      failed: (err) => pg.win.fail("It does not apply cleanly", "Make a branch from it instead (b): its changes, on the commit they were made on.", err) });
  }
  function drop() {
    const s = pg.stash;
    if (!s) return;
    pg.win.confirm({ question: "Drop " + s.ref + "?", glyph: "", ink: Zenon.red,
      detail: s.message, verb: "Drop", then: () => pg.win.act("stashDrop", { ref: s.ref }, { said: "Dropped" }) });
  }
  function branch() {
    const s = pg.stash;
    if (!s) return;
    pg.win.ask({ title: "A branch from " + s.ref, glyph: "",
      detail: "Made on the commit the stash was taken on, its changes applied there, and the stash dropped.",
      fields: [{ key: "name", label: "Name", hint: "wip/what-it-was" }], verb: "Create",
      then: (v) => pg.win.act("stashBranch", { name: v.name.trim(), ref: s.ref }, { said: "On " + v.name.trim() }) });
  }

  function key(e) {
    const k = e.key;
    if (e.modifiers & Qt.ControlModifier) return false;
    if (k === Qt.Key_N) { pg.push(); return true; }
    if (k === Qt.Key_Up || k === Qt.Key_K) { pg.moveTo(pg.sel - 1); return true; }
    if (k === Qt.Key_Down || k === Qt.Key_J) { pg.moveTo(pg.sel + 1); return true; }
    if (k === Qt.Key_PageUp) { diff.page(-1); return true; }
    if (k === Qt.Key_PageDown) { diff.page(1); return true; }
    if (k === Qt.Key_Return || k === Qt.Key_Enter) { pg.apply(false); return true; }
    if (k === Qt.Key_P) { pg.apply(true); return true; }
    if (k === Qt.Key_D || k === Qt.Key_Delete) { pg.drop(); return true; }
    if (k === Qt.Key_B) { pg.branch(); return true; }
    return false;
  }

  ListView {
    id: list
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: Math.round(Math.min(460, pg.width * 0.36))
    clip: true
    topMargin: 8
    bottomMargin: 8
    boundsBehavior: Flickable.StopAtBounds
    model: pg.stashes
    readonly property int rowH: Math.round(Zenon.px(15) * 3.2)
    SelectBar { view: list; host: pg.win; index: pg.sel; rowH: list.rowH; color: pg.win.hiFill; radius: Zenon.windowRadius; inset: 8 }
    delegate: Item {
      id: srow
      required property var modelData
      required property int index
      width: list.width
      height: list.rowH
      Column {
        x: 22
        width: parent.width - 44
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3
        Text {
          width: parent.width
          elide: Text.ElideRight
          text: srow.modelData.message.replace(/^(WIP )?[Oo]n [^:]+: /, "")
          color: srow.index === pg.sel ? Zenon.ink : Zenon.soft
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(15)
        }
        Text {
          width: parent.width
          elide: Text.ElideRight
          text: srow.modelData.ref + "  ·  " + D.ago(srow.modelData.when, Date.now())
            + ((srow.modelData.message.match(/^(?:WIP )?[Oo]n ([^:]+):/) || [])[1] ? "  ·  on " + srow.modelData.message.match(/^(?:WIP )?[Oo]n ([^:]+):/)[1] : "")
          color: Zenon.muted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(13)
        }
      }
      MouseArea {
        anchors.fill: parent
        onClicked: { pg.moveTo(srow.index); pg.win.focusKeys(); }
        onDoubleClicked: pg.apply(false)
      }
    }
    EmptyMark { anchors.centerIn: parent; visible: pg.stashes.length === 0; word: "Nothing stashed" }
  }
  ElasticScroll { anchors.fill: list; view: list }
  Scrollbar { flick: list; anchors.right: list.right; anchors.top: list.top; anchors.bottom: list.bottom }
  Rectangle { x: list.width; width: 1; height: parent.height; color: Zenon.border }

  DiffView {
    id: diff
    anchors.left: list.right
    anchors.leftMargin: 1
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    host: pg.win
    files: pg.diffFiles
    empty: pg.stash ? "No changes to tracked files" : ""
  }
}
