// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A verb on the batch-rename card. Chip-shaped, like every other small
// pressable thing in this window, and able to stay LIT — the two on the
// right are switches and the rest are one-shot actions, but a user should
// not have to learn two shapes to find that out: the lit ones are the ones
// that are still true after you let go.
//
// Shared, as BulkDrop is.

import QtQuick
import "../morpheus"

Rectangle {
  id: verb
  property string label: ""
  property bool on: false
  // Nothing to do, said quietly. Still pressable — a disabled control you
  // cannot press and cannot ask why is worse than one that does nothing.
  property bool dim: false
  signal clicked()

  opacity: verb.dim ? 0.4 : 1
  Behavior on opacity { NumberAnimation { duration: Zenon.fast } }
  implicitWidth: verbText.implicitWidth + 18
  implicitHeight: 26
  radius: Zenon.windowRadius
  // No hover tint — the suite's buttons answer only at rest, lit and
  // pressed (user, 2026-10-11); pressed is the wash Segments presses with.
  color: verb.on ? Zenon.alpha(Zenon.cyan, 0.16)
    : verbPress.pressed ? Zenon.pressWash(0.12) : Zenon.wash(0.04)
  border.width: 1
  border.color: verb.on ? Zenon.cyan : Zenon.border
  Behavior on color { ColorAnimation { duration: Zenon.fast } }
  Behavior on border.color { ColorAnimation { duration: Zenon.fast } }

  Text {
    textFormat: Text.PlainText
    id: verbText
    anchors.centerIn: parent
    text: verb.label
    color: verb.on ? Zenon.cyan : Zenon.white
    font.family: Zenon.face
    font.weight: Zenon.weight
    font.pixelSize: Zenon.px(13)
  }

  MouseArea {
    id: verbPress
    anchors.fill: parent
    onClicked: verb.clicked()
  }
}
