// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// WHAT CERES WANTS YOU TO KNOW, IN ITS OWN BAR — a failed check, a reboot or
// a service restart owed, news unread (Ceres.noteItems). None of them is an
// update, so they sit in a bar of their own rather than as loose lines that
// read like part of the list. Each row wears its own level; the bar wears
// the worst of them. A note that can be answered carries its answer: `act`
// the button's word, `run` the Ceres function that does it (the stale
// services' "Restart service" — user, 2026-10-15).
//
// The window's Updates tab and the bar's quick-access panel both show it
// (user, 2026-10-15: the panel had them as plain red lines), so it is one
// piece; each says how large its words are.

import QtQuick
import "../morpheus"
import "."

Rectangle {
  id: bar

  property var items: Ceres.noteItems
  property int textSize: Zenon.px(16)
  property int glyphSize: Zenon.px(15)
  property int rowH: 24

  function inkOf(level) {
    return level === "bad" ? Zenon.red : level === "warn" ? Zenon.yellow : Zenon.blue;
  }
  function glyphOf(level) {
    return level === "bad" ? "" : level === "warn" ? "" : "\u{F064E}";
  }
  readonly property color worst: {
    if (bar.items.some(n => n.level === "bad")) return Zenon.red;
    if (bar.items.some(n => n.level === "warn")) return Zenon.yellow;
    return Zenon.blue;
  }

  implicitHeight: bar.items.length ? noteCol.implicitHeight + 16 : 0
  height: implicitHeight
  radius: Zenon.windowRadius
  color: Qt.rgba(bar.worst.r, bar.worst.g, bar.worst.b, 0.10)
  border.width: 1
  border.color: Qt.rgba(bar.worst.r, bar.worst.g, bar.worst.b, 0.45)

  Column {
    id: noteCol
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: 12
    anchors.rightMargin: 12
    spacing: 4
    Repeater {
      model: bar.items
      delegate: Row {
        id: noteRow
        required property var modelData
        width: noteCol.width
        height: noteAct.visible ? bar.rowH + 6 : bar.rowH
        spacing: 10
        Text {
          width: 18
          anchors.verticalCenter: parent.verticalCenter
          horizontalAlignment: Text.AlignHCenter
          text: bar.glyphOf(noteRow.modelData.level)
          color: bar.inkOf(noteRow.modelData.level)
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: bar.glyphSize
        }
        Text {
          width: parent.width - 28 - (noteAct.visible ? noteAct.width + 10 : 0)
          anchors.verticalCenter: parent.verticalCenter
          elide: Text.ElideRight
          text: noteRow.modelData.text
          color: Zenon.white
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: bar.textSize
        }
        DialogButton {
          id: noteAct
          visible: !!noteRow.modelData.act
          anchors.verticalCenter: parent.verticalCenter
          label: noteRow.modelData.act || ""
          ink: bar.inkOf(noteRow.modelData.level)
          ready: !Ceres.txBusy
          onClicked: if (noteRow.modelData.run && Ceres[noteRow.modelData.run]) Ceres[noteRow.modelData.run]()
        }
      }
    }
  }
}
