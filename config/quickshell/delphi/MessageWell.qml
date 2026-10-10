// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A WELL FOR SOME LINES OF WRITING — delphi's every multi-line text: the
// commit message (Changes), a comment on a pull request or an issue, the
// body of a new one (FormBody's `lines` field). The suite's caret, its
// ghost text while empty, a note in the corner (the subject's length).
//
//     MessageWell { ghost: "…"; note: "48"; noteInk: Zenon.muted
//                   onSubmitted: …        // ctrl+return
//                   onEscaped: …          // esc
//                   onTabbed: …; onBackTabbed: … }
//
// Keys it does not use with ctrl held go to `passKeys(e)` (the window's
// page keys), when given.

import QtQuick
import "../morpheus"
import "../terminus"

Rectangle {
  id: mw
  property alias text: edit.text
  readonly property alias edit: edit
  readonly property bool focused: edit.activeFocus
  property string ghost: ""
  property string note: ""
  property color noteInk: Zenon.muted
  property real textSize: Zenon.px(15)
  property var passKeys: null
  signal submitted()
  signal escaped()
  signal tabbed()
  signal backTabbed()
  function claim() { edit.forceActiveFocus(); }

  radius: Zenon.windowRadius
  color: Zenon.wash(0.05)
  border.width: 1
  border.color: Zenon.border
  Behavior on border.color { ColorAnimation { duration: Zenon.fast } }

  Flickable {
    id: flick
    anchors.fill: parent
    anchors.margins: 10
    clip: true
    contentWidth: width
    contentHeight: edit.height
    boundsBehavior: Flickable.StopAtBounds
    TextEdit {
      id: edit
      width: flick.width
      // the whole well, not only its lines: a click anywhere in it types
      // there — at one line high, only the first line of the ghost text
      // took a click (user, 2026-10-11)
      height: Math.max(edit.implicitHeight, flick.height)
      wrapMode: TextEdit.Wrap
      textFormat: TextEdit.PlainText
      selectByMouse: true
      cursorDelegate: Caret { field: edit }
      color: Zenon.ink
      selectionColor: Zenon.alpha(Zenon.cyan, 0.4)
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: mw.textSize
      onCursorRectangleChanged: {
        const r = edit.cursorRectangle;
        if (r.y < flick.contentY) flick.contentY = r.y;
        else if (r.y + r.height > flick.contentY + flick.height)
          flick.contentY = r.y + r.height - flick.height;
      }
      Keys.onPressed: (e) => {
        const ctrl = e.modifiers & Qt.ControlModifier;
        if (ctrl && (e.key === Qt.Key_Return || e.key === Qt.Key_Enter)) { e.accepted = true; mw.submitted(); return; }
        if (e.key === Qt.Key_Escape) { e.accepted = true; mw.escaped(); return; }
        if (e.key === Qt.Key_Tab) { e.accepted = true; mw.tabbed(); return; }
        if (e.key === Qt.Key_Backtab) { e.accepted = true; mw.backTabbed(); return; }
        if (ctrl && mw.passKeys && mw.passKeys(e)) e.accepted = true;
      }
      Text {
        visible: edit.text === ""
        width: parent.width
        wrapMode: Text.Wrap
        text: mw.ghost
        color: Zenon.muted
        font: edit.font
      }
    }
  }
  Text {
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: 8
    visible: mw.note !== ""
    text: mw.note
    color: mw.noteInk
    font.family: Zenon.face
    font.weight: Zenon.weight
    font.features: { "tnum": 1 }
    font.pixelSize: Zenon.px(13)
  }
  // focused for typing: terminus' held ring (user, 2026-10-11 — every
  // text field wears it, its own border staying neutral)
  HeldRing { anchors.fill: parent; radius: parent.radius; z: 10; on: edit.activeFocus }
}
