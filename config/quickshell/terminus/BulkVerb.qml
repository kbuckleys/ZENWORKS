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
  implicitHeight: 24
  radius: Zenon.windowRadius
  color: verb.on
    ? Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.18)
    : (verbHov.hovered ? Zenon.headBg
       : Qt.rgba(Zenon.white.r, Zenon.white.g, Zenon.white.b, 0.05))
  border.width: 1
  border.color: verb.on ? Zenon.cyan : Zenon.border
  Behavior on color { ColorAnimation { duration: Zenon.fast } }
  Behavior on border.color { ColorAnimation { duration: Zenon.fast } }

  Text {
    id: verbText
    anchors.centerIn: parent
    text: verb.label
    color: verb.on ? Zenon.cyan : Zenon.white
    font.family: Zenon.face
    font.pixelSize: 13
  }

  HoverHandler { id: verbHov }
  MouseArea {
    anchors.fill: parent
    onClicked: verb.clicked()
  }
}
