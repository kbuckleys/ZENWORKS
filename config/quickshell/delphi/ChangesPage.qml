// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// CHANGES — the files that differ, in the order they are worked through
// (conflicts, then what is not staged, then what is), the chosen one's diff
// beside them, and the message under them.
//
// Each file is marked as terminus marks it beside its name (terminus.js
// gitMark/gitInk) and wears its own glyph, so a file looks the same here as
// in the file manager and in plato's tree.
//
//   the list   ↑↓ files · space stage / unstage · d discard · e edit in plato
//              a stage all · shift a unstage all · tab the diff · c message
//   the diff   ↑↓ lines · shift ↑↓ a range · [ ] hunks · space stage the
//              range or the hunk · l just this line · d discard it · e edit
//              here · esc back to the list
//   message    ctrl return commit · esc back to the list

import QtQuick
import Quickshell
import "../morpheus"
import "../terminus"
import "../picasso"
import "delphi.js" as D
import "../terminus/terminus.js" as Terminus
import "../morpheus/icons.js" as Icons

Item {
  id: pg
  property var win: null

  readonly property var rows: D.flatten(D.sections(pg.win ? pg.win.st : null))
  property int cur: -1
  readonly property var file: pg.cur >= 0 && pg.cur < pg.rows.length && !pg.rows[pg.cur].head ? pg.rows[pg.cur] : null
  property string area: "list"     // list | diff | message
  readonly property int stagedCount: pg.win && pg.win.st ? pg.win.st.staged.length : 0

  readonly property string title: "Changes"
  readonly property string subtitle: !pg.win || !pg.win.st ? ""
    : pg.win.branchName + (pg.win.branch && pg.win.branch.upstream
      ? "  →  " + pg.win.branch.upstream : "")
  readonly property var hints: pg.area === "message"
    ? [["ctrl return", "commit"], ["esc", "back"]]
    : pg.area === "diff"
    ? [["space", diff.ranged ? "lines" : "hunk"], ["l", "line"], ["shift ↑↓", "range"], ["[ ]", "hunks"],
       ["d", "discard"], ["e", "edit"], ["tab", "files"]]
    : [["space", pg.file && pg.file.area === "staged" ? "unstage" : "stage"], ["a", "stage all"],
       ["d", "discard"], ["e", "edit"], ["tab", "diff"], ["c", "message"]]
  readonly property var buttons: [
    { label: "Discard", ink: Zenon.red, visible: !!pg.file && pg.file.area !== "staged" && pg.file.area !== "conflict", run: () => pg.discard() },
    { label: pg.file && pg.file.area === "staged" ? "Unstage" : "Stage", visible: !!pg.file && pg.file.area !== "conflict", run: () => pg.toggle() },
  ]

  function takeFocus() {
    if (pg.area === "message") msgWell.claim();
    else if (pg.win) pg.win.focusKeys();
  }

  // ── following the list as it changes ──────────────────────────────────
  // The file you were on stays chosen across a refresh; a file staged away
  // leaves the cursor where the work is (delphi.js reseat).
  property var want: null
  onRowsChanged: {
    const i = D.reseat(pg.rows, pg.want, pg.cur);
    pg.cur = i;
    if (pg.file) pg.want = { path: pg.file.path, sec: pg.file.sec };
    pg.loadDiff();
  }
  function moveTo(i) {
    if (i < 0 || i >= pg.rows.length || pg.rows[i].head) return;
    pg.cur = i;
    pg.want = { path: pg.rows[i].path, sec: pg.rows[i].sec };
    list.positionViewAtIndex(i, ListView.Contain);
    diffWait.restart();
  }
  function step(d) { pg.moveTo(D.nextFile(pg.rows, pg.cur, d)); }

  // ── the diff beside ────────────────────────────────────────────────────
  property var diffFiles: []
  property int diffMore: -1
  property string diffFor: ""
  property bool diffLoading: false
  Timer { id: diffWait; interval: 50; onTriggered: pg.loadDiff() }
  function argsFor(f) {
    return { path: f.path, staged: f.area === "staged", untracked: f.area === "untracked", budget: 6000 };
  }
  function loadDiff() {
    const f = pg.file;
    if (!f || !pg.win || f.area === "conflict") { pg.diffFiles = []; pg.diffFor = ""; pg.diffMore = -1; return; }
    const key = f.area + ":" + f.path;
    const fresh = key !== pg.diffFor;
    pg.diffLoading = true;
    pg.win.mgr.call("diff", pg.win.root, pg.argsFor(f), (ok, res) => { if (!pg) return;
      if (!pg.file || pg.file.area + ":" + pg.file.path !== key) return;
      pg.diffLoading = false;
      pg.diffFiles = ok ? res.files : [];
      pg.diffMore = ok && res.more !== null ? res.more : -1;
      pg.diffFor = key;
      if (fresh) diff.toFirst();
    });
  }
  function moreDiff() {
    const f = pg.file;
    if (!f || pg.diffMore < 0) return;
    const key = pg.diffFor;
    pg.win.mgr.call("diff", pg.win.root, Object.assign(pg.argsFor(f), { start: pg.diffMore }), (ok, res) => { if (!pg) return;
      if (!ok || key !== pg.diffFor) return;
      const a = pg.diffFiles.slice();
      for (const g of res.files) {
        const last = a[a.length - 1];
        if (last && last.new === g.new) a[a.length - 1] = Object.assign({}, last, { hunks: last.hunks.concat(g.hunks) });
        else a.push(g);
      }
      pg.diffFiles = a;
      pg.diffMore = res.more !== null ? res.more : -1;
    });
  }

  // ── doing ──────────────────────────────────────────────────────────────
  function toggle() {
    const f = pg.file;
    if (!f) return;
    if (f.area === "staged") pg.win.act("unstage", { paths: [f.path] }, {});
    else if (f.area !== "conflict") pg.win.act("stage", { paths: [f.path] }, {});
  }
  function stageAll() { pg.win.act("stageAll", {}, { said: "Staged everything" }); }
  function unstageAll() { pg.win.act("unstageAll", {}, { said: "Unstaged everything" }); }
  // part of the file: the range, or the hunk under the cursor, or one line
  function stagePart(oneLine) {
    const f = pg.file;
    const chosen = oneLine ? diff.chosenLine() : diff.chosen();
    if (!f || !chosen) return;
    const op = f.area === "staged" ? "unstageLines" : "stageLines";
    const args = { path: f.path, chosen: chosen };
    if (f.area === "untracked") args.untracked = true;
    pg.win.act(op, args, { then: () => { diff.anchor = -1; } });
  }
  function discard() {
    const f = pg.file;
    if (!f || f.area === "staged" || f.area === "conflict") return;
    const part = pg.area === "diff" && f.area !== "untracked" ? (diff.ranged ? diff.chosen() : diff.chosen()) : null;
    if (f.area === "untracked") {
      pg.win.confirm({ question: "Delete " + f.name + "?", glyph: "", ink: Zenon.red,
        detail: "It is new — git has never seen it, so there is no copy to bring back.",
        items: [f.path], verb: "Delete", then: () => pg.win.act("clean", { paths: [f.path] }, { said: "Deleted " + f.name }) });
      return;
    }
    if (part) {
      pg.win.confirm({ question: diff.ranged ? "Discard these lines?" : "Discard this hunk?", glyph: "", ink: Zenon.red,
        detail: "Your edit to " + f.name + " there is undone in the file.", verb: "Discard",
        then: () => pg.win.act("discardLines", { path: f.path, chosen: part }, {}) });
      return;
    }
    pg.win.confirm({ question: "Discard your changes to " + f.name + "?", glyph: "", ink: Zenon.red,
      detail: "The file goes back to how it was staged (or committed). Unstaged edits are not kept anywhere.",
      items: [f.path], verb: "Discard", then: () => pg.win.act("discard", { paths: [f.path] }, { said: "Discarded " + f.name }) });
  }
  function edit() {
    const f = pg.file;
    if (!f || f.kind === "deleted") return;
    pg.win.edit(pg.win.abs(pg.area === "diff" && diff.pathAtCursor !== "" ? diff.pathAtCursor : f.path));
  }
  // a conflict: one side whole, or the file as edited (markers gone) marked done
  function resolve(how) {
    const f = pg.file;
    if (!f || f.area !== "conflict") return;
    if (how === "ours" || how === "theirs") pg.win.act("take", { path: f.path, side: how }, { said: "Took " + how + " for " + f.name });
    else pg.win.act("markResolved", { paths: [f.path] }, { said: f.name + " resolved" });
  }

  // ── committing ─────────────────────────────────────────────────────────
  property bool amend: false
  readonly property var note: D.messageNote(msgWell.text)
  readonly property bool canCommit: pg.note.ok && (pg.stagedCount > 0 || pg.amend)
    && !!pg.win && !!pg.win.st && pg.win.st.conflicts.length === 0
  onAmendChanged: {
    if (pg.amend && msgWell.text.trim() === "") {
      pg.win.mgr.call("lastMessage", pg.win.root, {}, (ok, m) => { if (!pg) return; if (ok && msgWell.text.trim() === "") msgWell.text = m; });
    }
  }
  function commit() {
    if (!pg.canCommit) {
      if (pg.stagedCount === 0 && !pg.amend) pg.win.say("Nothing staged to commit", true);
      else if (!pg.note.ok) { pg.area = "message"; pg.takeFocus(); }
      return;
    }
    const id = pg.win.info && pg.win.info.identity;
    if (id && (id.name === "" || id.email === "")) { pg.win.askIdentity(() => pg.commit()); return; }
    const text = msgWell.text;
    const amending = pg.amend;
    pg.win.act("commit", { message: text, amend: amending }, {
      label: "Committing",
      said: amending ? "Amended" : "Committed",
      then: () => { msgWell.text = ""; pg.win.draft = ""; pg.amend = false; pg.area = "list"; pg.takeFocus(); } });
  }

  // ── keys ───────────────────────────────────────────────────────────────
  function key(e) {
    const k = e.key, ctrl = e.modifiers & Qt.ControlModifier, shift = e.modifiers & Qt.ShiftModifier;
    if (ctrl && (k === Qt.Key_Return || k === Qt.Key_Enter)) { pg.commit(); return true; }
    if (ctrl) return false;
    if (pg.area === "diff") {
      if (k === Qt.Key_Escape) { if (diff.anchor >= 0) diff.anchor = -1; else pg.area = "list"; return true; }
      if (k === Qt.Key_Tab || k === Qt.Key_Backtab) { pg.area = "list"; return true; }
      if (k === Qt.Key_Up || k === Qt.Key_K) { diff.move(-1, !!shift); return true; }
      if (k === Qt.Key_Down || k === Qt.Key_J) { diff.move(1, !!shift); return true; }
      if (k === Qt.Key_PageUp) { diff.page(-1); return true; }
      if (k === Qt.Key_PageDown) { diff.page(1); return true; }
      if (k === Qt.Key_BracketLeft) { diff.jumpHunk(-1); return true; }
      if (k === Qt.Key_BracketRight) { diff.jumpHunk(1); return true; }
      if (k === Qt.Key_N) { diff.jump(shift ? -1 : 1); return true; }
      if (k === Qt.Key_Space || k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_S || k === Qt.Key_U) { pg.stagePart(false); return true; }
      if (k === Qt.Key_L) { pg.stagePart(true); return true; }
      if (k === Qt.Key_D) { pg.discard(); return true; }
      if (k === Qt.Key_E) { pg.edit(); return true; }
      if (k === Qt.Key_C) { pg.area = "message"; pg.takeFocus(); return true; }
      return false;
    }
    if (k === Qt.Key_Up || k === Qt.Key_K) { pg.step(-1); return true; }
    if (k === Qt.Key_Down || k === Qt.Key_J) { pg.step(1); return true; }
    if (k === Qt.Key_Home) { pg.moveTo(D.nextFile(pg.rows, -1, 1)); return true; }
    if (k === Qt.Key_End) { pg.moveTo(D.nextFile(pg.rows, pg.rows.length, -1)); return true; }
    if (k === Qt.Key_Space || k === Qt.Key_Return || k === Qt.Key_Enter) { pg.toggle(); return true; }
    if (k === Qt.Key_Tab || k === Qt.Key_Right || k === Qt.Key_L) { if (pg.file) pg.area = "diff"; return true; }
    if (k === Qt.Key_A) { if (shift) pg.unstageAll(); else pg.stageAll(); return true; }
    if (k === Qt.Key_D) { pg.discard(); return true; }
    if (k === Qt.Key_E) { pg.edit(); return true; }
    if (k === Qt.Key_C) { pg.area = "message"; pg.takeFocus(); return true; }
    if (pg.file && pg.file.area === "conflict") {
      if (k === Qt.Key_O) { pg.resolve("ours"); return true; }
      if (k === Qt.Key_T) { pg.resolve("theirs"); return true; }
      if (k === Qt.Key_R) { pg.resolve("done"); return true; }
    }
    return false;
  }
  onAreaChanged: Qt.callLater(pg.takeFocus)

  // ── the files ──────────────────────────────────────────────────────────
  Item {
    id: left
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: Math.round(Math.min(440, Math.max(320, pg.width * 0.32)))

    ListView {
      id: list
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.bottom: box.top
      clip: true
      topMargin: 6
      bottomMargin: 6
      boundsBehavior: Flickable.StopAtBounds
      model: pg.rows
      readonly property int rowH: Math.round(Zenon.px(15) * 2.1)
      SelectBar {
        view: list
        host: pg.win
        index: Math.max(0, pg.cur)
        rowH: list.rowH
        on: pg.cur >= 0
        color: pg.area === "list" ? pg.win.hiFill : Zenon.wash(0.05)
        radius: Zenon.windowRadius
        inset: 8
      }
      delegate: Item {
        id: frow
        required property var modelData
        required property int index
        readonly property var r: frow.modelData
        width: list.width
        height: list.rowH

        // ── a section's head ──
        Item {
          anchors.fill: parent
          visible: !!frow.r.head
          Text {
            x: 16
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 3
            text: frow.r.head ? frow.r.title.toUpperCase() + "   " + frow.r.count : ""
            color: frow.r.id === "conflict" ? Zenon.red : Zenon.muted
            font.family: Zenon.face
            font.weight: Font.Bold
            font.letterSpacing: 1
            font.features: { "tnum": 1 }
            font.pixelSize: Zenon.px(12)
          }
          Text {
            visible: !!frow.r.head && frow.r.count > 0 && frow.r.id !== "conflict"
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 3
            text: frow.r.id === "staged" ? "Unstage all" : "Stage all"
            color: headMa.containsMouse ? Zenon.cyan : Zenon.muted
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(13)
            MouseArea {
              id: headMa
              anchors.fill: parent
              anchors.margins: -6
              hoverEnabled: true
              onClicked: frow.r.id === "staged" ? pg.unstageAll() : pg.stageAll()
            }
          }
        }

        // ── a file ──
        Item {
          anchors.fill: parent
          visible: !frow.r.head
          readonly property var probe: ({ name: frow.r.name || "", path: frow.r.path || "", size: 1 })
          Text {
            id: fglyph
            x: 20
            width: 22
            anchors.verticalCenter: parent.verticalCenter
            text: frow.r.head ? "" : Terminus.glyphOf(parent.probe, Icons)
            color: frow.r.head ? Zenon.muted : Zenon[Terminus.inkKeyOf(parent.probe)]
            font.family: Zenon.glyphFace
            font.pixelSize: Zenon.px(15)
          }
          Text {
            id: fname
            anchors.left: fglyph.right
            anchors.leftMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, parent.width - x - fmark.width - 34)
            elide: Text.ElideMiddle
            text: frow.r.name || ""
            color: frow.r.kind === "deleted" ? Zenon.muted : Zenon.ink
            font.strikeout: frow.r.kind === "deleted"
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(15)
          }
          Text {
            anchors.left: fname.right
            anchors.leftMargin: 8
            anchors.right: fmark.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideLeft
            text: (frow.r.from ? "from " + frow.r.from + "  " : "") + (frow.r.dir || "")
            color: Zenon.muted
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(13)
          }
          // terminus' git letter, in terminus' git ink
          Text {
            id: fmark
            anchors.right: parent.right
            anchors.rightMargin: 20
            anchors.verticalCenter: parent.verticalCenter
            text: frow.r.head ? "" : Terminus.gitMark(frow.r.state)
            color: Terminus.gitInk(frow.r.state)
            font.family: Zenon.glyphMono
            font.weight: Font.Bold
            font.pixelSize: Zenon.px(14)
          }
          HoverHandler {
            onHoveredChanged: hovered && !frow.r.head
              ? pg.win.tip(fname, frow.r.path, frow.r.how || frow.r.word) : pg.win.untip(fname)
          }
          MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            onClicked: { pg.area = "list"; pg.moveTo(frow.index); pg.takeFocus(); }
            onDoubleClicked: { pg.moveTo(frow.index); pg.toggle(); }
          }
        }
      }
      EmptyMark {
        anchors.centerIn: parent
        visible: !!pg.win && !!pg.win.st && pg.rows.every((r) => r.head)
        word: "Nothing to commit"
      }
    }
    ElasticScroll { anchors.fill: list; view: list }
    Scrollbar { flick: list; anchors.right: list.right; anchors.top: list.top; anchors.bottom: list.bottom }

    // ── the message ──────────────────────────────────────────────────────
    Item {
      id: box
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: 196
      Rectangle { width: parent.width; height: 1; color: Zenon.border }

      MessageWell {
        id: msgWell
        x: 12
        y: 12
        width: parent.width - 24
        height: 112
        ghost: pg.stagedCount > 0 ? "What these " + (pg.stagedCount === 1 ? "changes do" : pg.stagedCount + " files' changes do")
          + " — a short first line, then more after a blank line" : "Stage something to commit, then say what it does"
        // the subject's length, as it is typed: 50 is the habit, 72 the wall
        note: pg.note.text
        noteInk: Zenon[pg.note.ink]
        passKeys: (e) => pg.win.key(e)
        // the draft lives on the window: a trip to History and back keeps it
        Component.onCompleted: msgWell.text = pg.win ? pg.win.draft : ""
        onTextChanged: if (pg.win) pg.win.draft = msgWell.text
        onFocusedChanged: if (msgWell.focused) pg.area = "message"
        onSubmitted: pg.commit()
        onEscaped: pg.area = "list"
        onTabbed: pg.area = "list"
      }
      Switch {
        anchors.left: msgWell.left
        anchors.top: msgWell.bottom
        anchors.topMargin: 16
        width: 200
        height: 28
        label: "Amend the last commit"
        on: pg.amend
        onToggled: pg.amend = !pg.amend
      }
      DialogButton {
        anchors.right: msgWell.right
        anchors.top: msgWell.bottom
        anchors.topMargin: 14
        label: pg.amend ? "Amend" : pg.stagedCount > 0 ? "Commit " + pg.stagedCount : "Commit"
        ink: Zenon.cyan
        primary: pg.canCommit
        ready: pg.canCommit
        onClicked: pg.commit()
      }
    }
  }
  Rectangle { x: left.width; width: 1; height: parent.height; color: Zenon.border }

  // ── the diff ───────────────────────────────────────────────────────────
  DiffView {
    id: diff
    anchors.left: left.right
    anchors.leftMargin: 1
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    visible: !pg.file || pg.file.area !== "conflict"
    host: pg.win
    files: pg.diffFiles
    more: pg.diffMore >= 0
    editable: !!pg.file && pg.file.area !== "conflict"
    empty: !pg.file ? "" : pg.diffLoading ? "" : "No changes"
    onActivated: (chosen) => { pg.area = "diff"; pg.stagePart(false); }
    onWantMore: pg.moreDiff()
    // a click in the diff is working in the diff
    onTouched: pg.area = "diff"
  }
  // the edge the diff wears while it has the keys
  Rectangle {
    anchors.fill: diff
    visible: pg.area === "diff" && diff.visible
    color: "transparent"
    border.width: 1
    border.color: Zenon.alpha(Zenon.cyan, 0.35)
  }

  // ── a conflict: what each side did, and the ways out ───────────────────
  Column {
    visible: !!pg.file && pg.file.area === "conflict"
    anchors.centerIn: diff
    width: Math.min(460, diff.width - 60)
    spacing: 14
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      text: ""
      color: Zenon.red
      font.family: Zenon.glyphFace
      font.pixelSize: Zenon.px(40)
    }
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.Wrap
      text: pg.file ? pg.file.name + " — " + pg.file.how : ""
      color: Zenon.ink
      font.family: Zenon.face
      font.weight: Font.Bold
      font.pixelSize: Zenon.px(18)
    }
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.Wrap
      text: "Take one side whole, or edit the file in plato — keep what you want between the <<<<<<< and >>>>>>> marks, delete the marks — then mark it resolved."
      color: Zenon.muted
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(14)
    }
    Flow {
      anchors.horizontalCenter: parent.horizontalCenter
      width: Math.min(parent.width, implicitWidth)
      spacing: 8
      DialogButton { label: "Take ours"; onClicked: pg.resolve("ours") }
      DialogButton { label: "Take theirs"; onClicked: pg.resolve("theirs") }
      DialogButton { label: "Edit in plato"; ink: Zenon.cyan; onClicked: pg.edit() }
      DialogButton { label: "Mark resolved"; ink: Zenon.green; primary: true; onClicked: pg.resolve("done") }
    }
  }
}
