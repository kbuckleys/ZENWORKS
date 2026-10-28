// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// One fact in a Hermes card: its name on the left, the value beside it —
// selectable, so an address can be copied out. Hidden with nothing to say.
// Full width in a card's body, its own inset inside.

import QtQuick
import "../morpheus"

Item {
  id: f

  property string label: ""
  property string value: ""
  property real labelW: 140

  width: parent ? parent.width : 0
  height: f.value !== "" ? Math.max(30, val.contentHeight + 10) : 0
  visible: f.value !== ""

  Text {
    textFormat: Text.PlainText
    x: 18
    width: f.labelW
    y: 5
    text: f.label
    color: Zenon.accentMuted
    font.family: Zenon.face
    font.weight: Zenon.weight
    font.pixelSize: Zenon.px(14)
  }
  TextEdit {
    id: val
    x: 18 + f.labelW
    y: 5
    width: f.width - x - 18
    text: f.value
    readOnly: true
    selectByMouse: true
    wrapMode: TextEdit.Wrap
    color: Zenon.ink
    selectionColor: Zenon.cyan
    selectedTextColor: Zenon.onAccent
    font.family: Zenon.face
    font.weight: Zenon.weight
    font.pixelSize: Zenon.px(14)
  }
}
