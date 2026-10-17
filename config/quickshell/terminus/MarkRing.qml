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
  // no check badge in the corner any more: the ring and the wash say it
  // (user, 2026-10-17, terminus and picasso alike)
}
