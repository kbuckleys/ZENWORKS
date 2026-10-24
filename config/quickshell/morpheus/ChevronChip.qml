// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A FOLD'S CHEVRON ON A DISC — ClearChip's disc, so a "this opens" mark
// reads as plainly as the × that clears a field and the + that adds a tab
// (user, 2026-10-24: a bare chevron was easy to miss). Points right shut,
// turns down open.
//
//     ChevronChip { size: Zenon.px(13); open: thing.open
//                   onClicked: thing.open = !thing.open }
//
// Drawn, not typed, for ClearChip's reason: a glyph centers by its line box,
// not its ink. `onClicked` is there for a chip that is the whole target; one
// beside a label whose row already takes the click leaves it alone and sets
// `passive`, so the press reaches the row.

import QtQuick

Rectangle {
  id: chip
  property real size: 14
  property bool open: false
  // pressed from outside: the row it sits in takes the press
  property bool held: false
  // the row does the clicking; the chip only shows the state
  property bool passive: false
  // the stroke's own ink; muted beside a label, as the bare chevron was
  property color ink: Zenon.ink
  readonly property bool down: press.pressed || chip.held
  signal clicked()

  width: Math.round(chip.size * 1.25)
  height: width
  radius: width / 2
  color: chip.down ? Zenon.pressFill : Zenon.alpha(Zenon.ink, 0.16)

  // a ">" whose two strokes meet at the apex, the pair centered on the disc
  Item {
    id: mark
    anchors.centerIn: parent
    width: chip.width
    height: chip.height
    rotation: chip.open ? 90 : 0
    Behavior on rotation { NumberAnimation { duration: Zenon.menuFade; easing.type: Easing.OutCubic } }
    readonly property real len: Math.round(chip.size * 0.42)
    readonly property real thick: Math.max(1.5, chip.size / 9)
    // the strokes' 45° run, half a stroke across
    readonly property real run: mark.len * 0.3536
    Repeater {
      model: [45, -45]
      Rectangle {
        required property var modelData
        width: mark.len
        height: mark.thick
        radius: height / 2
        antialiasing: true
        rotation: modelData
        // each stroke's center: back from the apex (a run right of the
        // disc's middle) along its own slope, which lands on the middle
        x: mark.width / 2 - width / 2
        y: mark.height / 2 - (modelData > 0 ? mark.run : -mark.run) - height / 2
        color: chip.ink
        opacity: chip.down ? Zenon.pressDim : 0.8
      }
    }
  }
  MouseArea {
    id: press
    visible: !chip.passive
    anchors.fill: parent
    anchors.margins: -4
    onClicked: chip.clicked()
  }
}
