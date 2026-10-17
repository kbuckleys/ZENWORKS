// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// AN ITEM'S FACE — the site's own mark where the font has one (C.markOf),
// else its kind's glyph, in its kind's color, on nothing (no chip).
// The list's rows, the detail's head and Quick Access all wear it, so an
// item looks the same wherever it is met.
//
//     ItemTile { item: row.modelData; size: 34 }
//     ItemTile { glyph: "…"; ink: "green"; size: 56 }   // a platform's

import QtQuick
import "../morpheus"
import "calypso.js" as C

Rectangle {
  id: tile
  property var item: null
  property int size: 34
  // given outright instead of an item (a platform, an account)
  property string glyph: ""
  property string ink: ""
  // the row it is on is chosen: a shade stronger
  property bool lit: false
  // (kept for callers; nothing is drawn round the glyph any more)
  property bool ringed: false
  readonly property var mark: C.markOf(tile.item)
  readonly property string slot: tile.ink !== "" ? tile.ink : tile.mark.ink
  readonly property color hue: Zenon[tile.slot] !== undefined ? Zenon[tile.slot] : Zenon.accentMuted

  width: tile.size
  height: tile.size
  // NO CHIP: the glyph stands alone in its kind's color (user,
  // 2026-10-12: "lose the chips around glyphs in all of calypso") — sized
  // up to fill the square a tinted tile used to
  color: Zenon.alpha(tile.hue, 0)

  Text {
    anchors.centerIn: parent
    text: tile.glyph !== "" ? tile.glyph : tile.mark.glyph
    color: tile.hue
    font.family: Zenon.glyphFace
    font.pixelSize: Math.round(tile.size * 0.66)
    opacity: tile.lit ? 1 : 0.85
  }
}
