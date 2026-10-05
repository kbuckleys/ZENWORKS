// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// MARKRING — a tile marked (ticked) for what comes next: a light wash over
// the picture, a ring in the cursor's ink a little out from it, and a tick
// on its corner. Laid exactly over the picture (or the glyph's square):
//
//     MarkRing { anchors.fill: pic; on: marked }
//
// The picture is meant to step back inside the ring — the caller scales the
// box holding both (0.9), so the ring and the tick shrink with it and the
// gap reads as the picture having been picked up. Shared by terminus' grid
// and picasso's gallery.

import QtQuick
import "../morpheus"

Item {
  id: mark
  property bool on: false
  property real radius: Zenon.windowRadius

  opacity: mark.on ? 1 : 0
  visible: opacity > 0.01
  Behavior on opacity { NumberAnimation { duration: Zenon.fast; easing.type: Easing.OutCubic } }

  Rectangle {
    anchors.fill: parent
    radius: mark.radius
    color: Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.10)
  }
  Rectangle {
    anchors.fill: parent
    anchors.margins: -5
    radius: mark.radius + 5
    color: "transparent"
    border.width: 2
    border.color: Zenon.cyan
  }
  Rectangle {
    x: parent.width - width + 6
    y: -6
    width: 22
    height: 22
    radius: 11
    color: Zenon.cyan
    scale: mark.on ? 1 : 0.4
    Behavior on scale { NumberAnimation { duration: Zenon.normal; easing.type: Easing.OutBack } }
    Text {
      anchors.centerIn: parent
      text: ""
      color: Zenon.black
      font.family: Zenon.face
      font.pixelSize: 12
    }
  }
}
