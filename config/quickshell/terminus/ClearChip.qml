// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A SEARCH'S CLEAR CHIP — a small round × inside a field's right end, there
// while the field holds text, that empties it (user, 2026-10-11). BulkField
// wears it when `clearable`; a field of its own (alexandria's searches)
// places one the same way and makes room for it:
//
//     ClearChip { size: Zenon.px(15); shown: field.text !== ""
//                 anchors.right: parent.right; anchors.rightMargin: 8
//                 anchors.verticalCenter: parent.verticalCenter
//                 onClicked: field.text = "" }
//
// Pressed, it darkens; no hover, as the suite's controls answer none.

import QtQuick
import "../morpheus"

Rectangle {
  id: chip
  // the field's text size: the chip is a little bigger than its letters
  property real size: 14
  property bool shown: true
  signal clicked()

  visible: chip.shown
  width: Math.round(chip.size * 1.25)
  height: width
  radius: width / 2
  // the ink's own colour, faint: a disc that reads on dark glass and on
  // light alike (a wash, white over, vanished on a light theme)
  color: Zenon.alpha(Zenon.ink, press.pressed ? 0.3 : 0.16)
  Text {
    anchors.centerIn: parent
    text: ""
    color: Zenon.ink
    opacity: 0.8
    font.family: Zenon.glyphFace
    font.pixelSize: Math.round(chip.size * 0.7)
  }
  MouseArea {
    id: press
    // a little past the chip: it is small, and missing it types
    anchors.fill: parent
    anchors.margins: -4
    onClicked: chip.clicked()
  }
}
