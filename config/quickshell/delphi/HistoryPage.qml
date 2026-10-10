// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// HISTORY — every branch's commits on one graph, newest first, read a page
// at a time from one `git log` the backend keeps open (so the 100 000th
// commit costs what the first did); the chosen commit beside them: its
// message, its files, and a file's diff.
//
// From a commit (its menu, or the keys): copy its id, a branch there, check
// it out, cherry-pick it onto yours, revert it, move your branch to it, or
// rework everything after it — reorder, reword, squash, drop — in the plan
// (RebasePlan.qml), which runs as one interactive rebase.
//
//   ↑↓ commits · tab its files · / search messages · c copy id · b branch
//   here · p cherry-pick · i rework from here · menu: everything else

import QtQuick
import Quickshell
import "../morpheus"
import "../terminus"
import "delphi.js" as D
import "../terminus/terminus.js" as Terminus
import "../morpheus/icons.js" as Icons

Item {
  id: pg
  property var win: null

  readonly property string title: pg.planning ? "Rework " + plan.steps.length + " commits" : "History"
  readonly property string subtitle: pg.planning ? "onto " + D.short(plan.base) + "  ·  drag or alt ↑↓ to reorder"
    : pg.commits.length + (pg.ended ? "" : "+") + " commits" + (pg.query !== "" ? " matching “" + pg.query + "”" : "")
  readonly property var hints: pg.planning ? plan.hints
    : pg.area === "files" ? [["↑↓", "files"], ["shift ↑↓", "diff"], ["e", "edit"], ["tab", "commits"]]
    : [["↑↓", "commits"], ["tab", "files"], ["/", "search"], ["c", "copy id"], ["b", "branch here"],
       ["p", "cherry-pick"], ["i", "rework from here"], ["menu", "more"]]
  readonly property var buttons: pg.planning ? plan.buttons : []

  function takeFocus() {
    if (pg.planning) plan.takeFocus();
    else if (search.focused) return;
    else if (pg.win) pg.win.focusKeys();
  }

  // ── THE LOG ────────────────────────────────────────────────────────────
  property var commits: []
  property int session: -1
  property bool ended: false
  property bool paging: false
  property string query: ""
  property int sel: 0
  readonly property var commit: pg.sel >= 0 && pg.sel < pg.commits.length ? pg.commits[pg.sel] : null
  property string wantSha: ""
  readonly property string headSha: pg.win && pg.win.branch ? pg.win.branch.oid || "" : ""

  function reload() {
    if (!pg.win || pg.win.root === "") return;
    if (pg.commit) pg.wantSha = pg.commit.sha;
    if (pg.session >= 0) pg.win.mgr.call("logClose", pg.win.root, { session: pg.session });
    pg.session = -1;
    pg.ended = false;
    const args = pg.query !== "" ? { grep: pg.query } : {};
    const root = pg.win.root;
    pg.win.mgr.call("logOpen", root, args, (ok, res) => { if (!pg) return;
      if (!ok || root !== pg.win.root) return;
      pg.session = res.session;
      pg.commits = [];
      pg.more(true);
    });
  }
  function more(first) {
    if (pg.session < 0 || pg.ended || pg.paging) return;
    pg.paging = true;
    const sid = pg.session;
    pg.win.mgr.call("logPage", pg.win.root, { session: sid, count: first ? 400 : 600 }, (ok, res) => { if (!pg) return;
      pg.paging = false;
      if (!ok || sid !== pg.session) return;
      pg.commits = pg.commits.concat(res.commits);
      pg.ended = res.end;
      if (first) {
        const i = pg.wantSha !== "" ? pg.commits.findIndex((c) => c.sha === pg.wantSha) : -1;
        pg.sel = Math.max(0, i);
        pg.wantSha = "";
        list.positionViewAtIndex(pg.sel, ListView.Contain);
        pg.loadCommit();
      }
    });
  }
  Component.onCompleted: Qt.callLater(pg.reload)
  Component.onDestruction: if (pg.session >= 0 && pg.win) pg.win.mgr.call("logClose", pg.win.root, { session: pg.session })
  Connections {
    target: pg.win
    function onRefsEpochChanged() { if (!pg.planning) pg.reload(); }
    function onRepoEpochChanged() { pg.commits = []; pg.reload(); }
  }

  function moveTo(i) {
    if (pg.commits.length === 0) return;
    pg.sel = Math.max(0, Math.min(pg.commits.length - 1, i));
    list.positionViewAtIndex(pg.sel, ListView.Contain);
    if (pg.sel > pg.commits.length - 80) pg.more(false);
    detailWait.restart();
  }

  // ── THE COMMIT ─────────────────────────────────────────────────────────
  property var message: null
  property var files: []
  property int fileSel: 0
  property var diffFiles: []
  property string area: "commits"
  Timer { id: detailWait; interval: 60; onTriggered: pg.loadCommit() }
  function loadCommit() {
    const c = pg.commit;
    if (!c) { pg.message = null; pg.files = []; pg.diffFiles = []; return; }
    const sha = c.sha;
    pg.win.mgr.call("message", pg.win.root, { sha: sha }, (ok, m) => { if (!pg) return; if (ok && pg.commit && pg.commit.sha === sha) pg.message = m; });
    pg.win.mgr.call("files", pg.win.root, { sha: sha }, (ok, fs) => { if (!pg) return;
      if (!ok || !pg.commit || pg.commit.sha !== sha) return;
      pg.files = fs;
      pg.fileSel = 0;
      pg.loadFileDiff();
    });
  }
  function loadFileDiff() {
    const c = pg.commit, f = pg.files[pg.fileSel];
    if (!c || !f) { pg.diffFiles = []; return; }
    const sha = c.sha, path = f.path;
    pg.win.mgr.call("show", pg.win.root, { rev: sha, path: path, budget: 6000 }, (ok, res) => { if (!pg) return;
      if (ok && pg.commit && pg.commit.sha === sha && pg.files[pg.fileSel] && pg.files[pg.fileSel].path === path) {
        pg.diffFiles = res.files;
        diff.toFirst();
      }
    });
  }
  function moveFile(d) {
    if (pg.files.length === 0) return;
    pg.fileSel = Math.max(0, Math.min(pg.files.length - 1, pg.fileSel + d));
    fileList.positionViewAtIndex(pg.fileSel, ListView.Contain);
    pg.loadFileDiff();
  }

  // ── WHAT CAN BE DONE FROM A COMMIT ─────────────────────────────────────
  function branchHere(c) {
    pg.win.ask({ title: "A branch at " + D.short(c.sha), glyph: "",
      detail: c.subject, fields: [{ key: "name", label: "Name", hint: "feature/what-it-is" }],
      toggles: [{ key: "switch", label: "Switch to it", value: true }], verb: "Create",
      then: (v) => pg.win.act("branchCreate", { name: v.name.trim(), start: c.sha, switch: v["switch"] },
                              { said: "Branch " + v.name.trim() + " created" }) });
  }
  function checkout(c) {
    pg.win.confirm({ question: "Check out " + D.short(c.sha) + "?", glyph: "",
      detail: "Detached: you are on the commit, not on a branch. Make a branch there before committing, or the commits are easy to lose.",
      verb: "Check out", then: () => pg.win.act("switch", { name: c.sha, detach: true }, { said: "On " + D.short(c.sha) }) });
  }
  function cherryPick(c) {
    pg.win.act("cherryPick", { shas: [c.sha] }, { label: "Cherry-picking",
      then: (r) => pg.win.say(r && r.conflicts ? "Stopped on conflicts — resolve them in Changes" : "Picked " + D.short(c.sha) + " onto " + pg.win.branchName, r && r.conflicts) });
  }
  function revert(c) {
    pg.win.confirm({ question: "Revert " + D.short(c.sha) + "?", glyph: "",
      detail: "A new commit that undoes it: “" + c.subject + "”", verb: "Revert",
      then: () => pg.win.act("revert", { sha: c.sha }, { then: (r) => pg.win.say(r && r.conflicts ? "Stopped on conflicts — resolve them in Changes" : "Reverted", r && r.conflicts) }) });
  }
  function resetTo(c) {
    pg.win.ask({ title: "Move " + pg.win.branchName + " to " + D.short(c.sha) + "?", glyph: "", ink: Zenon.red,
      detail: "The commits after it leave the branch. Soft keeps their changes staged, mixed keeps them unstaged; hard throws them away, and your uncommitted work with them.",
      toggles: [{ key: "hard", label: "Hard — discard the changes too", value: false },
                { key: "soft", label: "Soft — keep them staged", value: false }],
      verb: "Move", verbInk: Zenon.red,
      then: (v) => pg.win.act("reset", { rev: c.sha, mode: v.hard ? "hard" : v.soft ? "soft" : "mixed" }, { said: "Moved to " + D.short(c.sha) }) });
  }
  function rework(c) {
    if (pg.win.st && (pg.win.st.staged.length + pg.win.st.unstaged.length) > 0) {
      pg.win.say("Commit or stash your changes first", true);
      return;
    }
    pg.win.mgr.call("rebasePlan", pg.win.root, { base: c.sha }, (ok, steps) => { if (!pg) return;
      if (!ok || steps.length === 0) { pg.win.say("Nothing after " + D.short(c.sha) + " to rework", true); return; }
      plan.begin(c.sha, steps);
    });
  }
  readonly property bool planning: plan.active

  function menuFor(c) {
    const here = c.sha === pg.headSha;
    return [
      { text: "Copy id", icon: "", mark: "c", run: () => pg.win.copy(c.sha, D.short(c.sha)) },
      { text: "Copy message", icon: "", run: () => pg.win.copy(c.subject, "the message") },
      { isSeparator: true },
      { text: "Branch here…", icon: "", mark: "b", run: () => pg.branchHere(c) },
      { text: "Check out", icon: "", enabled: !here, run: () => pg.checkout(c) },
      { text: "Cherry-pick onto " + pg.win.branchName, icon: "", mark: "p", enabled: !here, run: () => pg.cherryPick(c) },
      { text: "Revert", icon: "", run: () => pg.revert(c) },
      { isSeparator: true },
      { text: "Rework the commits after it…", icon: "", mark: "i", enabled: !here, run: () => pg.rework(c) },
      { text: "Move " + pg.win.branchName + " here…", icon: "", enabled: !here, danger: true, run: () => pg.resetTo(c) },
    ];
  }

  // ── KEYS ───────────────────────────────────────────────────────────────
  function key(e) {
    if (pg.planning) return plan.key(e);
    const k = e.key, ctrl = e.modifiers & Qt.ControlModifier, shift = e.modifiers & Qt.ShiftModifier;
    if (ctrl) return false;
    if (k === Qt.Key_Slash) { search.claim(); return true; }
    if (k === Qt.Key_Tab || k === Qt.Key_Backtab) { pg.area = pg.area === "files" ? "commits" : "files"; return true; }
    if (pg.area === "files") {
      if (shift && (k === Qt.Key_Up || k === Qt.Key_Down)) { diff.move(k === Qt.Key_Up ? -1 : 1, false); return true; }
      if (k === Qt.Key_Up || k === Qt.Key_K) { pg.moveFile(-1); return true; }
      if (k === Qt.Key_Down || k === Qt.Key_J) { pg.moveFile(1); return true; }
      if (k === Qt.Key_PageUp) { diff.page(-1); return true; }
      if (k === Qt.Key_PageDown) { diff.page(1); return true; }
      if (k === Qt.Key_E && pg.files[pg.fileSel]) { pg.win.edit(pg.win.abs(pg.files[pg.fileSel].path)); return true; }
      if (k === Qt.Key_Escape) { pg.area = "commits"; return true; }
      return false;
    }
    if (k === Qt.Key_Up || k === Qt.Key_K) { pg.moveTo(pg.sel - 1); return true; }
    if (k === Qt.Key_Down || k === Qt.Key_J) { pg.moveTo(pg.sel + 1); return true; }
    if (k === Qt.Key_PageUp) { pg.moveTo(pg.sel - 15); return true; }
    if (k === Qt.Key_PageDown) { pg.moveTo(pg.sel + 15); return true; }
    if (k === Qt.Key_Home) { pg.moveTo(0); return true; }
    if (k === Qt.Key_End) { pg.moveTo(pg.commits.length - 1); return true; }
    if (!pg.commit) return false;
    if (k === Qt.Key_C) { pg.win.copy(pg.commit.sha, D.short(pg.commit.sha)); return true; }
    if (k === Qt.Key_B) { pg.branchHere(pg.commit); return true; }
    if (k === Qt.Key_P) { pg.cherryPick(pg.commit); return true; }
    if (k === Qt.Key_I) { pg.rework(pg.commit); return true; }
    if (k === Qt.Key_Menu || (shift && k === Qt.Key_F10)) {
      const it = list.itemAtIndex(pg.sel);
      const p = it ? it.mapToItem(pg, 60, it.height) : Qt.point(60, 60);
      menu.open(p.x, p.y, pg.menuFor(pg.commit), pg.sel);
      return true;
    }
    if (k === Qt.Key_Escape && pg.query !== "") { search.text = ""; pg.query = ""; pg.reload(); return true; }
    return false;
  }

  // ── the commits ────────────────────────────────────────────────────────
  Item {
    id: left
    visible: !pg.planning
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: Math.round(pg.width * 0.56)

    BulkField {
      id: search
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: 12
      height: 32
      textSize: Zenon.px(15)
      ghost: "  Search messages  ( / )"
      onAccepted: { pg.query = search.text.trim(); pg.reload(); pg.win.focusKeys(); }
      Keys.onEscapePressed: { search.text = ""; if (pg.query !== "") { pg.query = ""; pg.reload(); } pg.win.focusKeys(); }
    }

    ListView {
      id: list
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: search.bottom
      anchors.topMargin: 8
      anchors.bottom: parent.bottom
      clip: true
      bottomMargin: 6
      boundsBehavior: Flickable.StopAtBounds
      model: pg.commits
      cacheBuffer: 800
      reuseItems: true
      readonly property int rowH: Math.round(Zenon.px(15) * 2.2)
      onContentYChanged: if (contentY + height > contentHeight - 600) pg.more(false)
      SelectBar { view: list; host: pg.win; index: pg.sel; rowH: list.rowH; color: pg.area === "commits" ? pg.win.hiFill : Zenon.wash(0.05) }
      delegate: Item {
        id: crow
        required property var modelData
        required property int index
        readonly property var c: crow.modelData
        width: list.width
        height: list.rowH
        GraphCell {
          id: gcell
          x: 8
          height: parent.height
          g: crow.c.graph
          merge: crow.c.parents.length > 1
          head: crow.c.sha === pg.headSha
        }
        Row {
          id: chipRow
          anchors.left: gcell.right
          anchors.leftMargin: 6
          anchors.verticalCenter: parent.verticalCenter
          spacing: 5
          Repeater {
            model: D.chips(crow.c.refs).slice(0, 3)
            delegate: Rectangle {
              required property var modelData
              height: Zenon.px(19)
              width: chipText.implicitWidth + 14
              radius: 4
              color: Zenon.alpha(Zenon[modelData.ink], modelData.here ? 0.22 : 0.12)
              border.width: modelData.here ? 1 : 0
              border.color: Zenon[modelData.ink]
              Text {
                id: chipText
                anchors.centerIn: parent
                text: modelData.glyph + " " + modelData.label
                color: Zenon[modelData.ink]
                font.family: Zenon.face
                font.weight: Font.Bold
                font.pixelSize: Zenon.px(12)
              }
            }
          }
        }
        Text {
          anchors.left: chipRow.right
          anchors.leftMargin: chipRow.width > 0 ? 8 : 0
          anchors.right: who.left
          anchors.rightMargin: 12
          anchors.verticalCenter: parent.verticalCenter
          elide: Text.ElideRight
          text: crow.c.subject
          color: crow.index === pg.sel ? Zenon.ink : Zenon.soft
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(15)
        }
        Text {
          id: who
          anchors.right: when.left
          anchors.rightMargin: 12
          anchors.verticalCenter: parent.verticalCenter
          width: Math.min(implicitWidth, 130)
          elide: Text.ElideRight
          text: crow.c.author
          color: Zenon.muted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(13)
        }
        Text {
          id: when
          anchors.right: parent.right
          anchors.rightMargin: 16
          anchors.verticalCenter: parent.verticalCenter
          width: Zenon.px(64)
          horizontalAlignment: Text.AlignRight
          text: D.ago(crow.c.when, Date.now())
          color: Zenon.muted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.features: { "tnum": 1 }
          font.pixelSize: Zenon.px(13)
        }
        HeldRing { anchors.fill: parent; anchors.margins: 2; on: menu.isOpen && menu.held === crow.index }
        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          onClicked: (m) => {
            if (m.button === Qt.RightButton) {
              const p = mapToItem(pg, m.x, m.y);
              menu.open(p.x, p.y, pg.menuFor(crow.c), crow.index);
              return;
            }
            pg.area = "commits";
            pg.moveTo(crow.index);
            pg.win.focusKeys();
          }
        }
      }
      footer: Item {
        width: list.width
        height: pg.ended ? 0 : 40
        Working { anchors.centerIn: parent; running: pg.paging }
      }
      EmptyMark {
        anchors.centerIn: parent
        visible: pg.commits.length === 0 && pg.ended
        filtered: pg.query !== ""
        word: pg.query !== "" ? "" : "No commits yet"
      }
    }
    ElasticScroll { anchors.fill: list; view: list }
    Scrollbar { flick: list; anchors.right: list.right; anchors.top: list.top; anchors.bottom: list.bottom }
  }
  Rectangle { visible: !pg.planning; x: left.width; width: 1; height: parent.height; color: Zenon.border }

  // ── the commit ─────────────────────────────────────────────────────────
  Item {
    id: right
    visible: !pg.planning
    anchors.left: left.right
    anchors.leftMargin: 1
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom

    Column {
      id: headCol
      x: 18
      y: 14
      width: parent.width - 36
      spacing: 6
      visible: !!pg.commit
      Text {
        width: parent.width
        wrapMode: Text.Wrap
        maximumLineCount: 3
        elide: Text.ElideRight
        text: pg.commit ? pg.commit.subject : ""
        color: Zenon.ink
        font.family: Zenon.face
        font.weight: Font.Bold
        font.pixelSize: Zenon.px(17)
      }
      Text {
        width: parent.width
        elide: Text.ElideRight
        text: !pg.commit ? "" : pg.commit.author + "  ·  " + D.stamp(pg.commit.when) + "  ·  " + D.short(pg.commit.sha)
          + (pg.commit.parents.length > 1 ? "  ·  merge of " + pg.commit.parents.length : "")
          + (pg.message && pg.message.signature === "G" ? "  ·   signed" : "")
        color: Zenon.muted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(13)
        MouseArea { anchors.fill: parent; onClicked: if (pg.commit) pg.win.copy(pg.commit.sha, D.short(pg.commit.sha)) }
      }
      // the body, when there is more than the subject
      Flickable {
        id: bodyFlick
        width: parent.width
        height: Math.min(bodyText.implicitHeight, 120)
        visible: bodyText.text !== ""
        clip: true
        contentHeight: bodyText.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        Text {
          id: bodyText
          width: bodyFlick.width
          wrapMode: Text.Wrap
          textFormat: Text.PlainText
          text: {
            if (!pg.message) return "";
            const b = pg.message.body;
            const i = b.indexOf("\n");
            return i < 0 ? "" : b.slice(i + 1).replace(/^\s+/, "");
          }
          color: Zenon.soft
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(14)
        }
      }
    }
    Rectangle { id: headRule; y: headCol.y + headCol.height + 12; width: parent.width; height: 1; color: Zenon.border; visible: !!pg.commit }

    // its files
    ListView {
      id: fileList
      anchors.top: headRule.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      height: Math.min(contentHeight + 8, Math.round(right.height * 0.3))
      clip: true
      topMargin: 4
      bottomMargin: 4
      boundsBehavior: Flickable.StopAtBounds
      model: pg.files
      readonly property int rowH: Math.round(Zenon.px(14) * 2)
      SelectBar { view: fileList; host: pg.win; index: pg.fileSel; rowH: fileList.rowH; color: pg.area === "files" ? pg.win.hiFill : Zenon.wash(0.05) }
      delegate: Item {
        id: frow
        required property var modelData
        required property int index
        readonly property var probe: ({ name: D.baseName(frow.modelData.path), path: frow.modelData.path, size: 1 })
        width: fileList.width
        height: fileList.rowH
        Text {
          id: fg
          x: 18
          width: 20
          anchors.verticalCenter: parent.verticalCenter
          text: Terminus.glyphOf(frow.probe, Icons)
          color: Zenon[Terminus.inkKeyOf(frow.probe)]
          font.family: Zenon.glyphFace
          font.pixelSize: Zenon.px(14)
        }
        Text {
          anchors.left: fg.right
          anchors.leftMargin: 6
          anchors.right: counts.left
          anchors.rightMargin: 10
          anchors.verticalCenter: parent.verticalCenter
          elide: Text.ElideMiddle
          text: (frow.modelData.from ? frow.modelData.from + "  →  " : "") + frow.modelData.path
          color: frow.index === pg.fileSel ? Zenon.ink : Zenon.soft
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(14)
        }
        Text {
          id: counts
          anchors.right: parent.right
          anchors.rightMargin: 18
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.StyledText
          text: frow.modelData.added === null ? "binary"
            : "<font color=\"" + Zenon.hex(Zenon.green) + "\">+" + frow.modelData.added + "</font>  "
              + "<font color=\"" + Zenon.hex(Zenon.red) + "\">−" + frow.modelData.deleted + "</font>"
          color: Zenon.muted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.features: { "tnum": 1 }
          font.pixelSize: Zenon.px(13)
        }
        MouseArea {
          anchors.fill: parent
          onClicked: { pg.area = "files"; pg.fileSel = frow.index; pg.loadFileDiff(); pg.win.focusKeys(); }
          onDoubleClicked: pg.win.edit(pg.win.abs(frow.modelData.path))
        }
      }
    }
    Rectangle { id: filesRule; anchors.top: fileList.bottom; width: parent.width; height: 1; color: Zenon.border; visible: pg.files.length > 0 }

    DiffView {
      id: diff
      anchors.top: filesRule.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      host: pg.win
      files: pg.diffFiles
      editable: false
      empty: ""
    }
  }

  // ── reworking the commits after one ────────────────────────────────────
  RebasePlan {
    id: plan
    anchors.fill: parent
    win: pg.win
    onFinished: { pg.reload(); Qt.callLater(pg.takeFocus); }
  }

  PopMenu {
    id: menu
    anchors.fill: parent
    window: pg.win
    cardWidth: 260
    onClosed: pg.win.focusKeys()
  }
}
