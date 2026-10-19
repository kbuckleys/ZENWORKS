// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// MARKRING — the grid cursor's look: a rounded box in an ink (its rim
// solid, its fill at 0.55) or a fill (ringed in the same tint, three times
// as strong), else the plain border. SelectCell's travelling box IS one of
// these, and a tile marked (ticked) for what comes next wears one in the
// same place, so a drag box or a shift/ctrl pick lights every tile it took
// exactly as the cursor lights the one it is on (user, 2026-10-18 — it was
// a ring round the picture, which stepped back inside it; both gone).
//
//     MarkRing { anchors.fill: box; fill: term.hiFill; on: marked }
//
// Behind the tile's content, as the cursor is. Shared by terminus' grid and
// picasso's gallery.

import QtQuick
import "../morpheus"

Rectangle {
  id: mark
  property bool on: true
  // as SelectCell's: unset, the shared rule's border
  property color ink: "transparent"
  readonly property bool inked: mark.ink.a > 0
  property color fill: "transparent"
  readonly property bool filledIn: mark.fill.a > 0

  radius: Zenon.windowRadius
  color: mark.inked ? Qt.rgba(mark.ink.r, mark.ink.g, mark.ink.b, 0.55)
    : mark.filledIn ? mark.fill : Zenon.border
  border.width: 1
  border.color: mark.inked ? mark.ink
    : mark.filledIn ? Qt.rgba(mark.fill.r, mark.fill.g, mark.fill.b, Math.min(1, mark.fill.a * 3))
    : Zenon.border

  opacity: mark.on ? 1 : 0
  visible: opacity > 0.01
  Behavior on opacity { NumberAnimation { duration: Zenon.fast; easing.type: Easing.OutCubic } }
}
