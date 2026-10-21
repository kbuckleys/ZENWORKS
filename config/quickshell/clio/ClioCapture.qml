// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// QUICK NOTE — a line or two put down without opening Clio's window: a card
// on the main monitor (oracle's Display), on a layer above everything, with
// the keyboard. Into today's journal entry (added at its end, the entry
// begun if there is none — from the daily template when one is set), or as
// a note of its own. Return keeps it, shift+return is a new line, tab
// changes where it goes, Esc lets it go. `qs ipc call Clio capture` (and
// Cynosure's "Quick note").

import QtQuick
import Quickshell
import Quickshell.Wayland
import "../morpheus"
import "../terminus"
import "../oracle"
import "notes.js" as N

PanelWindow {
  id: cap
  property var mgr: null
  property bool open: false
  property string into: "today"          // today | note

  screen: Oracle.pickScreen("")
  visible: cap.open || cardK > 0.01
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  anchors { top: true; bottom: true; left: true; right: true }
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.namespace: "clio-capture"
  WlrLayershell.keyboardFocus: cap.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

  property real cardK: cap.open ? 1 : 0
  Behavior on cardK { NumberAnimation { duration: Zenon.normal; easing.type: Easing.OutCubic } }

  function show(into) {
    if (into) cap.into = into;
    field.text = "";
    cap.open = true;
    Qt.callLater(() => field.forceActiveFocus());
  }
  function hide() { cap.open = false; }

  function keep() {
    const t = field.text.replace(/\s+$/, "");
    if (t.trim() === "" || !cap.mgr) { cap.hide(); return; }
    const go = () => {
      const lines = t.split("\n").map((l) => N.block("body", N.escape(l)));
      if (cap.into === "note") {
        cap.mgr.newNote("", [N.block(cap.mgr.startWith, N.escape(t.split("\n")[0]))].concat(lines.slice(1)));
        cap.mgr.said("Kept as a note");
      } else cap.mgr.addToToday(lines);
      cap.mgr.flush();
    };
    if (cap.mgr.loaded) go(); else cap.mgr.load(go);
    cap.hide();
  }

  // a click off the card lets it go
  MouseArea { anchors.fill: parent; enabled: cap.open; onClicked: cap.hide() }

  Rectangle {
    id: card
    width: Math.min(620, cap.width - 80)
    height: col.implicitHeight + 32
    x: Math.round((cap.width - width) / 2)
    y: Math.round(cap.height * 0.22) - (1 - cap.cardK) * 14
    opacity: cap.cardK
    scale: 0.96 + 0.04 * cap.cardK
    radius: Zenon.rad(11)
    color: Zenon.panelBg
    border.width: 1
    border.color: Zenon.border
    MouseArea { anchors.fill: parent }    // a click on the card stays on it

    Column {
      id: col
      x: 18
      y: 16
      width: parent.width - 36
      spacing: 12
      Item {
        width: parent.width
        height: 30
        Row {
          anchors.verticalCenter: parent.verticalCenter
          spacing: 10
          Text { anchors.verticalCenter: parent.verticalCenter; text: ""; color: Zenon.sand; font.family: Zenon.glyphFace; font.pixelSize: Zenon.px(18) }
          Text { anchors.verticalCenter: parent.verticalCenter; text: "Quick note"; color: Zenon.ink; font.family: Zenon.face; font.weight: Font.Bold; font.pixelSize: Zenon.px(16) }
        }
        Segments {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          options: [["today", "Today's entry"], ["note", "A new note"]]
          current: cap.into
          textSize: Zenon.px(12)
          onChose: (v) => { cap.into = v; field.forceActiveFocus(); }
        }
      }
      Rectangle {
        width: parent.width
        height: Math.max(90, Math.min(260, field.implicitHeight + 24))
        radius: Zenon.windowRadius
        color: Zenon.wash(0.05)
        border.width: 1
        border.color: Zenon.border
        Flickable {
          id: flick
          anchors.fill: parent
          anchors.margins: 12
          contentHeight: field.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          TextEdit {
            id: field
            width: flick.width
            wrapMode: TextEdit.Wrap
            color: Zenon.ink
            selectionColor: Zenon.alpha(Zenon.cyan, 0.32)
            selectedTextColor: color
            font.family: cap.mgr ? cap.mgr.faceFor(cap.into === "today") : Zenon.face
            font.pixelSize: Zenon.px(16)
            cursorDelegate: Caret { field: field }
            onCursorRectangleChanged: {
              const r = field.cursorRectangle;
              if (r.y < flick.contentY) flick.contentY = r.y;
              else if (r.y + r.height > flick.contentY + flick.height) flick.contentY = r.y + r.height - flick.height;
            }
            Keys.onPressed: (e) => {
              if (e.key === Qt.Key_Escape) { cap.hide(); e.accepted = true; return; }
              if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && !(e.modifiers & Qt.ShiftModifier)) { cap.keep(); e.accepted = true; return; }
              if (e.key === Qt.Key_Tab) { cap.into = cap.into === "today" ? "note" : "today"; e.accepted = true; }
            }
            Text {
              visible: field.text === ""
              text: cap.into === "today" ? "What happened, what you thought…" : "Something to keep…"
              color: Zenon.accentMuted
              font: field.font
            }
          }
        }
        HeldRing { anchors.fill: parent; radius: parent.radius; z: 10; on: field.activeFocus }
      }
      Item {
        width: parent.width
        height: 32
        HintRow {
          anchors.verticalCenter: parent.verticalCenter
          rows: [["return", "keep"], ["shift return", "new line"], ["tab", "where"], ["esc", "let go"]]
          maxWidth: parent.width - keepBtn.width - 16
        }
        DialogButton {
          id: keepBtn
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          label: "Keep"
          ink: Zenon.cyan
          primary: true
          onClicked: cap.keep()
        }
      }
    }
  }
}
