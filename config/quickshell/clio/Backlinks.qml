// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// LINKED FROM — under a note, the notes and entries that link to it (with
// >>), each a row that opens it. Nothing at all while none do.

import QtQuick
import "../morpheus"
import "notes.js" as N

Column {
  id: bl
  property var pane: null
  readonly property var mgr: bl.pane ? bl.pane.mgr : null
  readonly property var from: bl.mgr && bl.pane.note && !bl.pane.isSticky ? N.linksTo(bl.mgr.notes, bl.pane.note.id) : []
  visible: bl.from.length > 0
  topPadding: 28
  spacing: 4

  Rectangle { width: parent.width; height: 1; color: Zenon.border }
  Text {
    topPadding: 10
    bottomPadding: 4
    text: "\u{F0339}  Linked from"
    color: Zenon.accentMuted
    font.family: Zenon.face
    font.weight: Font.Bold
    font.pixelSize: Zenon.px(12)
  }
  Repeater {
    model: bl.from
    delegate: Rectangle {
      id: row
      required property var modelData
      width: bl.width
      height: 34
      radius: Zenon.windowRadius
      color: rowMa.containsMouse ? Zenon.wash(0.06) : "transparent"
      Row {
        x: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 10
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: row.modelData.kind === "entry" ? "\u{F0B64}" : "\u{F11D7}"
          color: row.modelData.kind === "entry" ? Zenon.magenta : Zenon.cyan
          font.family: Zenon.glyphFace
          font.pixelSize: Zenon.px(14)
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: Math.min(implicitWidth, bl.width - 160)
          elide: Text.ElideRight
          text: N.titleOf(row.modelData, row.modelData.kind === "entry" ? N.dateLong(row.modelData.date) : "New Note")
          color: Zenon.ink
          font.family: Zenon.face
          font.weight: Font.DemiBold
          font.pixelSize: Zenon.px(14)
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: N.dateShort(row.modelData.modified, Date.now())
          color: Zenon.accentMuted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(12)
        }
      }
      MouseArea { id: rowMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: bl.pane.win.openNote(row.modelData.id) }
    }
  }
}
