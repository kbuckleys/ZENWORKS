// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ONE ROW OF CLIO'S SETTINGS — what it is (and a line saying more) on the
// left, its control on the right.

import QtQuick
import "../morpheus"

Item {
  id: line
  property string label: ""
  property string note: ""
  default property alias tool: slot.data
  height: Math.max(32, words.implicitHeight)
  Column {
    id: words
    anchors.verticalCenter: parent.verticalCenter
    width: parent.width - slot.width - 16
    Text { text: line.label; color: Zenon.ink; font.family: Zenon.face; font.weight: Font.DemiBold; font.pixelSize: Zenon.px(14) }
    Text { visible: text !== ""; width: parent.width; wrapMode: Text.Wrap; text: line.note; color: Zenon.muted; font.family: Zenon.face; font.weight: Zenon.weight; font.pixelSize: Zenon.px(12) }
  }
  Item {
    id: slot
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    width: childrenRect.width
    height: childrenRect.height
  }
}
