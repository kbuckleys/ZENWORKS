// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A FEW CHOICES, ONE OF THEM ON — one bordered pill split into its options,
// the chosen one tinted in the accent. For a view's handful of ways to look
// (open or closed, whose, which history, which forge), where a row of
// separate buttons sprawled and wrapped into a stack (user, 2026-10-11).
// Sized by its words; no hover (the suite's buttons do not answer one).
//
//     Segments { options: [["open", "Open"], ["closed", "Closed"]]
//                current: pg.showing; onChose: (v) => pg.showing = v }
//
// terminus' PrefSeg is the settings panel's own (enrolled with its window
// for the keyboard); this is the one for anywhere else.

import QtQuick
import "../morpheus"

Rectangle {
  id: segs
  // [[value, label], …]
  property var options: []
  property string current: ""
  property real textSize: Zenon.px(14)
  signal chose(string value)

  implicitWidth: row.implicitWidth + 2
  implicitHeight: Math.round(segs.textSize * 2.1)
  width: implicitWidth
  height: implicitHeight
  radius: Zenon.windowRadius
  color: Zenon.wash(0.04)
  border.width: 1
  border.color: Zenon.border

  Row {
    id: row
    x: 1
    y: 1
    height: segs.height - 2
    Repeater {
      model: segs.options
      delegate: Item {
        id: one
        required property var modelData
        required property int index
        readonly property bool on: segs.current === one.modelData[0]
        width: label.implicitWidth + 28
        height: row.height
        // between two options, a hairline
        Rectangle {
          visible: one.index > 0
          width: 1
          height: parent.height - 10
          anchors.verticalCenter: parent.verticalCenter
          color: Zenon.border
        }
        Rectangle {
          anchors.fill: parent
          anchors.margins: 2
          radius: Math.max(0, segs.radius - 2)
          color: one.on ? Zenon.alpha(Zenon.cyan, 0.16) : "transparent"
          Behavior on color { ColorAnimation { duration: Zenon.fast } }
        }
        Text {
          id: label
          anchors.centerIn: parent
          text: one.modelData[1]
          color: one.on ? Zenon.cyan : Zenon.muted
          font.family: Zenon.face
          font.weight: Font.Bold
          font.features: { "tnum": 1 }
          font.pixelSize: segs.textSize
        }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: segs.chose(one.modelData[0])
        }
      }
    }
  }
}
