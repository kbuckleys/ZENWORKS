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
  // too narrow for the words and the control side by side (the window at
  // its smallest — user, 2026-10-14: the control ran over its label): the
  // control under the words, at the right, as a phone's settings fold
  readonly property bool stacked: head.implicitWidth + 16 + slot.width > line.width
  height: line.stacked ? words.implicitHeight + 6 + slot.height : Math.max(32, words.implicitHeight)
  Column {
    id: words
    y: line.stacked ? 0 : Math.round((line.height - height) / 2)
    width: line.stacked ? line.width : line.width - slot.width - 16
    Text { textFormat: Text.PlainText; id: head; text: line.label; color: Zenon.ink; font.family: Zenon.face; font.weight: Font.DemiBold; font.pixelSize: Zenon.px(14) }
    Text { textFormat: Text.PlainText; visible: text !== ""; width: parent.width; wrapMode: Text.Wrap; text: line.note; color: Zenon.accentMuted; font.family: Zenon.face; font.weight: Zenon.weight; font.pixelSize: Zenon.px(12) }
  }
  Item {
    id: slot
    anchors.right: parent.right
    y: line.stacked ? words.implicitHeight + 6 : Math.round((line.height - height) / 2)
    width: childrenRect.width
    height: childrenRect.height
  }
}
