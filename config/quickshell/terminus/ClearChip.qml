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
  // pressed from outside: a tab's own MouseArea takes the press over its ×
  property bool held: false
  readonly property bool down: press.pressed || chip.held
  signal clicked()

  visible: chip.shown
  width: Math.round(chip.size * 1.25)
  height: width
  radius: width / 2
  // the ink's own colour, faint: a disc that reads on dark glass and on
  // light alike (a wash, white over, vanished on a light theme)
  // PRESSED, DARKENED (user, 2026-10-14): the disc goes to shade and the
  // cross dims, as a button pressed in
  color: chip.down ? Zenon.darken(0.35) : Zenon.alpha(Zenon.ink, 0.16)
  // ── THE CROSS IS DRAWN, NOT TYPED (user, 2026-10-14) ──────────────
  // The glyph (nf-fa-times) was centred by its line box, not its ink, so
  // the × sat off the disc's middle — worst at the tabs' size. Two strokes
  // crossing at the disc's centre cannot miss it.
  Repeater {
    model: [45, -45]
    Rectangle {
      required property var modelData
      anchors.centerIn: parent
      width: Math.round(chip.width * 0.46)
      height: Math.max(1.5, chip.size / 10)
      radius: height / 2
      rotation: modelData
      antialiasing: true
      color: Zenon.ink
      opacity: chip.down ? 0.55 : 0.8
    }
  }
  MouseArea {
    id: press
    // a little past the chip: it is small, and missing it types
    anchors.fill: parent
    anchors.margins: -4
    onClicked: chip.clicked()
  }
}
