// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE RING AROUND A NAME BEING TYPED. Renaming, and naming a thing just
// made, happen in place — on the row, on the tile — where a bare caret in a
// listing of names is easy to lose: which of these forty is the one taking
// keys? So the field is ringed in the accent, and the ring POPS in (a
// little under size, a little past it, home), the one movement in a still
// list the eye goes to.
//
// Laid out around `target` (the field's Loader) as its sibling, declared
// before it so it sits under the text. `fontPx` sizes the ring to the line
// rather than to the whole row, which would touch its neighbours.
//
// AS WIDE AS WHAT IS TYPED: it hugs the name and grows and shrinks with it,
// never narrower than a few letters (a blank name for a thing just made
// still has its ring) nor wider than the field. `centered` for a field that
// centres its text — the tile's — so the ring stays on the text.

import QtQuick
import "../morpheus"

Rectangle {
  id: ring

  property Item target: null
  property bool on: false
  property real fontPx: 14
  // how far it stands off the text, each side
  property real padX: 6
  property real padY: 4
  // never taller than this: a row's own height, so a ring on a 26px row
  // does not reach into the rows either side of it
  property real maxH: ring.target ? ring.target.height : 0
  property bool centered: false

  // the typed text's own width, from the field the Loader made
  readonly property real textW: ring.target && ring.target.item ? ring.target.item.contentWidth : 0
  readonly property real fieldW: ring.target ? ring.target.width : 0
  readonly property real innerW: Math.min(ring.fieldW, Math.max(ring.fontPx * 3, ring.textW + 2))

  x: !ring.target ? 0
    : Math.round(ring.target.x - ring.padX + (ring.centered ? (ring.fieldW - ring.innerW) / 2 : 0))
  width: ring.target ? Math.round(ring.innerW + 2 * ring.padX) : 0
  // eased, so a keystroke widens it rather than jumping it
  Behavior on width { NumberAnimation { duration: Zenon.brisk; easing.type: Zenon.ease } }
  Behavior on x { enabled: ring.centered; NumberAnimation { duration: Zenon.brisk; easing.type: Zenon.ease } }
  height: Math.min(ring.maxH, Math.round(ring.fontPx * 1.35) + 2 * ring.padY)
  y: ring.target ? Math.round(ring.target.y + (ring.target.height - ring.height) / 2) : 0

  radius: Zenon.windowRadius
  color: Zenon.alpha(Zenon.cyan, 0.08)
  border.width: 1
  border.color: Zenon.cyan

  visible: opacity > 0.01
  opacity: ring.on ? 1 : 0
  scale: ring.on ? 1 : 0.94
  Behavior on opacity { NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }
  Behavior on scale {
    NumberAnimation { duration: Zenon.normal; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
  }
}
