// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// WORKTREES — the other checkouts of this one repository: a second branch
// open in a directory of its own, sharing the history, so a fix can be made
// without putting the work in progress aside.
//
//   n new worktree · return open it in delphi · t show it in terminus
//   d remove (the directory; the branch stays) · p prune ones whose
//   directory is gone

import QtQuick
import "../morpheus"
import "../terminus"
import "delphi.js" as D

Item {
  id: pg
  property var win: null
  // the views whose rows carry on up under the window's head, frosted
  // (DelphiWindow's ScrollEdges) — only those with nothing but controls
  // between them and the head: a view under a title would paint over it
  readonly property var edgeViews: [list]

  readonly property string title: "Worktrees"
  readonly property string subtitle: pg.trees.length <= 1 ? "Only this checkout" : pg.trees.length + " checkouts of this repository"
  readonly property var hints: [["n", "new"], ["return", "open"], ["t", "terminus"], ["d", "remove"], ["p", "prune"]]
  readonly property var buttons: [
    { label: "Remove", ink: Zenon.red, visible: !!pg.tree && !pg.tree.main && !pg.tree.current, run: () => pg.remove() },
    { label: "New worktree", ink: Zenon.cyan, primary: true, run: () => pg.add() },
  ]
  function takeFocus() { if (pg.win) pg.win.focusKeys(); }

  property var trees: []
  property int sel: 0
  readonly property var tree: pg.sel >= 0 && pg.sel < pg.trees.length ? pg.trees[pg.sel] : null
  function reload() {
    if (!pg.win || pg.win.root === "") return;
    pg.win.mgr.call("worktrees", pg.win.root, {}, (ok, list) => { if (!pg) return;
      if (!ok) return;
      pg.trees = list;
      pg.sel = Math.max(0, Math.min(pg.sel, list.length - 1));
    });
  }
  Component.onCompleted: Qt.callLater(pg.reload)
  Connections {
    target: pg.win
    function onRefsEpochChanged() { pg.reload(); }
  }

  function add() {
    const parent = pg.win.root.replace(/\/[^/]*$/, "");
    pg.win.ask({ title: "A new worktree", glyph: "",
      detail: "A directory of its own, on a branch of its own. Name an existing branch to check it out there, or a new one to make it.",
      fields: [{ key: "branch", label: "Branch", hint: "fix/the-thing" },
               { key: "path", label: "Directory", value: parent + "/" + pg.win.repoName + "-", path: true,
                 pathTail: pg.win.repoName + "-" }],
      verb: "Create",
      then: (v) => {
        const b = v.branch.trim(), p = v.path.trim();
        const exists = pg.win.refs.local.some((l) => l.name === b);
        pg.win.act("worktreeAdd", exists ? { path: p, branch: b } : { path: p, newBranch: b },
                   { said: "Worktree at " + D.tilde(p, pg.win.home), then: () => pg.reload() });
      } });
  }
  function remove() {
    const t = pg.tree;
    if (!t || t.main || t.current) return;
    pg.win.confirm({ question: "Remove the worktree at " + D.baseName(t.path) + "?", glyph: "", ink: Zenon.red,
      detail: "Its directory goes; the branch " + (t.branch || "") + " and its commits stay. Refused if it has uncommitted changes.",
      items: [D.tilde(t.path, pg.win.home)], verb: "Remove",
      then: () => pg.win.act("worktreeRemove", { path: t.path }, { said: "Removed", then: () => pg.reload() }) });
  }

  function key(e) {
    const k = e.key;
    if (e.modifiers & Qt.ControlModifier) return false;
    if (k === Qt.Key_N) { pg.add(); return true; }
    if (k === Qt.Key_Up || k === Qt.Key_K) { pg.sel = Math.max(0, pg.sel - 1); return true; }
    if (k === Qt.Key_Down || k === Qt.Key_J) { pg.sel = Math.min(pg.trees.length - 1, pg.sel + 1); return true; }
    if (!pg.tree) return false;
    if (k === Qt.Key_Return || k === Qt.Key_Enter) { pg.win.openRepo(pg.tree.path); return true; }
    if (k === Qt.Key_T) { pg.win.reveal(pg.tree.path); return true; }
    if (k === Qt.Key_D || k === Qt.Key_Delete) { pg.remove(); return true; }
    if (k === Qt.Key_P) { pg.win.act("worktreePrune", {}, { said: "Pruned", then: () => pg.reload() }); return true; }
    return false;
  }

  ListView {
    id: list
    anchors.fill: parent
    clip: true
    topMargin: 10
    bottomMargin: 10
    boundsBehavior: Flickable.StopAtBounds
    model: pg.trees
    readonly property int rowH: Math.round(Zenon.px(15) * 3.4)
    SelectBar { view: list; host: pg.win; index: pg.sel; rowH: list.rowH; color: pg.win.hiFill; radius: Zenon.windowRadius; inset: 8 }
    delegate: Item {
      id: trow
      required property var modelData
      required property int index
      readonly property var t: trow.modelData
      width: list.width
      height: list.rowH
      Text {
        id: tg
        x: 24
        anchors.verticalCenter: parent.verticalCenter
        text: ""
        color: trow.t.current ? Zenon.cyan : trow.t.prunable ? Zenon.red : Zenon.muted
        font.family: Zenon.glyphFace
        font.pixelSize: Zenon.px(19)
      }
      Column {
        anchors.left: tg.right
        anchors.leftMargin: 14
        anchors.right: parent.right
        anchors.rightMargin: 24
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3
        Text {
          width: parent.width
          elide: Text.ElideRight
          text: (trow.t.branch || (trow.t.detached ? "detached at " + D.short(trow.t.sha) : trow.t.bare ? "bare" : ""))
            + (trow.t.main ? "   ·   main checkout" : "") + (trow.t.current ? "   ·   this window" : "")
          color: trow.t.current ? Zenon.cyan : Zenon.ink
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(16)
        }
        Text {
          width: parent.width
          elide: Text.ElideMiddle
          text: D.tilde(trow.t.path, pg.win.home) + (trow.t.prunable ? "   ·   directory gone — prune it" : "")
            + (trow.t.locked ? "   ·   locked" : "")
          color: trow.t.prunable ? Zenon.red : Zenon.muted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(13)
        }
      }
      MouseArea {
        anchors.fill: parent
        onClicked: { pg.sel = trow.index; pg.win.focusKeys(); }
        onDoubleClicked: pg.win.openRepo(trow.t.path)
      }
    }
  }
  ElasticScroll { anchors.fill: list; view: list }
  Scrollbar { flick: list; anchors.right: list.right; anchors.top: list.top; anchors.bottom: list.bottom }
}
