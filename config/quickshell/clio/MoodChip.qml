// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A WORD TO TICK — one of a mood's feelings, or what it was about.

import QtQuick
import "../morpheus"

Rectangle {
  id: chip
  property string word: ""
  property bool on: false
  property color ink: Zenon.cyan
  signal clicked()
  width: label.implicitWidth + 22
  height: 28
  radius: 14
  color: chip.on ? Zenon.alpha(chip.ink, 0.2) : Zenon.wash(0.05)
  border.width: 1
  border.color: chip.on ? Zenon.alpha(chip.ink, 0.7) : Zenon.border
  Text {
    id: label
    anchors.centerIn: parent
    text: chip.word
    color: chip.on ? Zenon.ink : Zenon.accentSoft
    font.family: Zenon.face
    font.weight: chip.on ? Font.DemiBold : Zenon.weight
    font.pixelSize: Zenon.px(13)
  }
  MouseArea { anchors.fill: parent; onClicked: chip.clicked() }
}
