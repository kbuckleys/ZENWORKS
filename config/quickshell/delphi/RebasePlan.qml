// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// REWORKING COMMITS — an interactive rebase, planned here instead of in a
// todo file. The commits after the one you started from, oldest at the top
// (the order they are replayed in), each with what to do with it:
//
//   pick     keep it as it is              reword   keep it, new message
//   squash   fold into the one above,      fixup    fold into the one above,
//            messages joined                        its message dropped
//   edit     stop there, to change it      drop     leave it out
//
// Reorder by dragging a row or alt ↑↓. Run hands the plan to the backend as
// one `git rebase -i` (delphi/core repo.rebase_interactive: the todo is
// written from the plan, rewords amend from a file — no editor ever opens).
// Conflicts on the way stop it as any rebase stops: the sidebar says so,
// Changes lists them, Continue carries on.

import QtQuick
import "../morpheus"
import "../terminus"
import "delphi.js" as D

Item {
  id: plan
  property var win: null
  property bool active: false
  property string base: ""
  property var steps: []
  property int sel: 0
  signal finished()
  visible: plan.active

  readonly property var acts: [
    { id: "pick", key: "p", ink: "cyan", word: "keep" },
    { id: "reword", key: "r", ink: "blue", word: "new message" },
    { id: "edit", key: "e", ink: "yellow", word: "stop to change it" },
    { id: "squash", key: "s", ink: "magenta", word: "fold in, keep its message" },
    { id: "fixup", key: "f", ink: "magenta", word: "fold in, drop its message" },
    { id: "drop", key: "d", ink: "red", word: "leave out" },
  ]
  function actOf(id) { return plan.acts.find((a) => a.id === id) || plan.acts[0]; }
  // a fold needs a commit above it to fold into
  readonly property string problem: {
    const kept = plan.steps.filter((s) => s.action !== "drop");
    if (kept.length === 0) return "Every commit is dropped";
    if (kept[0].action === "squash" || kept[0].action === "fixup") return "The first commit has nothing above it to fold into";
    if (plan.steps.some((s) => s.action === "reword" && String(s.message || "").trim() === "")) return "A reword has no message";
    return "";
  }
  readonly property bool changed: plan.steps.some((s, i) => s.action !== "pick" || s.order !== i || s.message)

  readonly property var hints: [["p r e s f d", "what to do"], ["alt ↑↓", "move"], ["return", "message"],
                                ["ctrl return", "run"], ["esc", "cancel"]]
  readonly property var buttons: [
    { label: "Cancel", run: () => plan.cancel() },
    { label: "Run", ink: Zenon.cyan, primary: true, ready: plan.problem === "" && plan.changed, run: () => plan.run() },
  ]

  function begin(base, steps) {
    plan.base = base;
    plan.steps = steps.map((s, i) => ({ sha: s.sha, subject: s.subject, action: "pick", message: "", order: i }));
    plan.sel = 0;
    plan.active = true;
    Qt.callLater(plan.takeFocus);
  }
  function cancel() { plan.active = false; plan.finished(); }
  function takeFocus() { if (plan.win) plan.win.focusKeys(); }
  function setAct(id) {
    const s = plan.steps.slice();
    if (!s[plan.sel]) return;
    s[plan.sel] = Object.assign({}, s[plan.sel], { action: id });
    plan.steps = s;
    if (id === "reword" && !s[plan.sel].message) plan.reword();
  }
  function shift(d) {
    const i = plan.sel, j = i + d;
    if (j < 0 || j >= plan.steps.length) return;
    const s = plan.steps.slice();
    const t = s[i]; s[i] = s[j]; s[j] = t;
    plan.steps = s;
    plan.sel = j;
  }
  function reword() {
    const st = plan.steps[plan.sel];
    if (!st) return;
    const i = plan.sel;
    // The subject is what is retyped (a one-line field); the body below it
    // is kept as it was.
    plan.win.mgr.call("message", plan.win.root, { sha: st.sha }, (ok, m) => { if (!plan) return;
      const whole = st.message || (ok ? m.body : st.subject);
      const cut = whole.indexOf("\n");
      const rest = cut < 0 ? "" : whole.slice(cut).replace(/^\s+/, "");
      plan.win.ask({ title: "New message for " + D.short(st.sha), glyph: "\uF044",
        detail: rest !== "" ? "The body under it stays as it is." : "",
        fields: [{ key: "subject", label: "Subject", value: D.subjectOf(whole) }],
        verb: "Use",
        then: (v) => {
          const s = plan.steps.slice();
          const msg = v.subject.trim() + (rest !== "" ? "\n\n" + rest : "");
          s[i] = Object.assign({}, s[i], { action: "reword", message: msg });
          plan.steps = s;
        } });
    });
  }
  function run() {
    if (plan.problem !== "" || !plan.changed) return;
    const steps = plan.steps.map((s) => s.action === "reword" ? { action: "reword", sha: s.sha, message: s.message }
                                                              : { action: s.action, sha: s.sha });
    plan.win.act("rebaseInteractive", { base: plan.base, plan: steps }, {
      label: "Reworking",
      then: (r) => {
        plan.active = false;
        plan.finished();
        if (r && r.conflicts) plan.win.say("Stopped on conflicts — resolve them in Changes, then Continue", true);
        else if (r && r.state && r.state.op === "rebase") plan.win.say("Stopped to edit — change it, then Continue in the sidebar");
        else plan.win.say("Reworked " + steps.length + " commits");
      } });
  }
  function key(e) {
    const k = e.key, ctrl = e.modifiers & Qt.ControlModifier, alt = e.modifiers & Qt.AltModifier;
    if (ctrl && (k === Qt.Key_Return || k === Qt.Key_Enter)) { plan.run(); return true; }
    if (ctrl) return false;
    if (k === Qt.Key_Escape) { plan.cancel(); return true; }
    if (alt && k === Qt.Key_Up) { plan.shift(-1); return true; }
    if (alt && k === Qt.Key_Down) { plan.shift(1); return true; }
    if (k === Qt.Key_Up || k === Qt.Key_K) { plan.sel = Math.max(0, plan.sel - 1); return true; }
    if (k === Qt.Key_Down || k === Qt.Key_J) { plan.sel = Math.min(plan.steps.length - 1, plan.sel + 1); return true; }
    if (k === Qt.Key_Return || k === Qt.Key_Enter) { plan.reword(); return true; }
    for (const a of plan.acts) {
      if (e.text === a.key) { plan.setAct(a.id); return true; }
    }
    return false;
  }

  Rectangle { anchors.fill: parent; color: Zenon.layerBg }

  Text {
    id: note
    x: 22
    y: 14
    width: parent.width - 44
    wrapMode: Text.Wrap
    text: plan.problem !== "" ? plan.problem
      : "Oldest first — the order they are replayed in. Nothing changes until Run; Abort in the sidebar undoes a run that stopped."
    color: plan.problem !== "" ? Zenon.red : Zenon.accentMuted
    font.family: Zenon.face
    font.weight: Zenon.weight
    font.pixelSize: Zenon.px(14)
  }

  ListView {
    id: list
    anchors.top: note.bottom
    anchors.topMargin: 12
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    model: plan.steps
    readonly property int rowH: Math.round(Zenon.px(15) * 2.6)
    SelectBar { view: list; host: plan.win; index: plan.sel; rowH: list.rowH; color: plan.win ? plan.win.hiFill : "transparent" }
    delegate: Item {
      id: srow
      required property var modelData
      required property int index
      readonly property var a: plan.actOf(srow.modelData.action)
      readonly property bool folds: srow.modelData.action === "squash" || srow.modelData.action === "fixup"
      width: list.width
      height: list.rowH
      opacity: srow.modelData.action === "drop" ? 0.45 : 1

      // the action: one segment lit of six, clickable
      Row {
        id: segs
        x: 18 + (srow.folds ? 22 : 0)
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        Behavior on x { NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }
        Repeater {
          model: plan.acts
          delegate: Rectangle {
            required property var modelData
            readonly property bool on: srow.modelData.action === modelData.id
            width: Zenon.px(22)
            height: Zenon.px(22)
            radius: 4
            color: on ? Zenon.alpha(Zenon[modelData.ink], 0.25) : Zenon.wash(0.04)
            border.width: on ? 1 : 0
            border.color: Zenon[modelData.ink]
            Text {
              anchors.centerIn: parent
              text: modelData.key
              color: parent.on ? Zenon[modelData.ink] : Zenon.accentMuted
              font.family: Zenon.faceMono
              font.weight: Font.Bold
              font.pixelSize: Zenon.px(13)
            }
            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              onClicked: { plan.sel = srow.index; plan.setAct(modelData.id); }
              onContainsMouseChanged: containsMouse ? plan.win.tip(parent, modelData.id + " — " + modelData.word, modelData.key) : plan.win.untip(parent)
            }
          }
        }
      }
      Text {
        id: sha
        anchors.left: segs.right
        anchors.leftMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        text: D.short(srow.modelData.sha)
        color: Zenon.accentMuted
        font.family: Zenon.faceFixed
        font.pixelSize: Zenon.px(14)
      }
      Text {
        anchors.left: sha.right
        anchors.leftMargin: 14
        anchors.right: word.left
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideRight
        text: srow.modelData.action === "reword" && srow.modelData.message
          ? D.subjectOf(srow.modelData.message) : srow.modelData.subject
        color: srow.modelData.action === "reword" && srow.modelData.message ? Zenon.blue : Zenon.ink
        font.strikeout: srow.modelData.action === "drop"
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(15)
      }
      Text {
        id: word
        anchors.right: parent.right
        anchors.rightMargin: 20
        anchors.verticalCenter: parent.verticalCenter
        text: srow.a.word
        color: Zenon[srow.a.ink]
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(13)
      }
      // dragging a row moves it
      MouseArea {
        anchors.left: sha.left
        anchors.right: parent.right
        height: parent.height
        property real from: 0
        onPressed: (m) => { plan.sel = srow.index; from = m.y; plan.takeFocus(); }
        onPositionChanged: (m) => {
          const d = Math.round((m.y - from) / list.rowH);
          if (d !== 0) { plan.shift(d > 0 ? 1 : -1); from += (d > 0 ? 1 : -1) * list.rowH; }
        }
        onDoubleClicked: plan.reword()
      }
    }
  }
  ElasticScroll { anchors.fill: list; view: list }
  Scrollbar { flick: list; anchors.right: list.right; anchors.top: list.top; anchors.bottom: list.bottom }
}
