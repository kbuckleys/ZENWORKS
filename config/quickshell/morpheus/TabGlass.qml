// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE GLASS UNDER A TAB STRIP (terminus' and plato's, 2026-10-11).
// An inactive tab is thin glass with the desktop through it (`away`); the
// active one is the window's own ground (`here`), exactly what the bar under
// it stands on. The thin glass STOPS either side of the active cell rather
// than lying under it: laid under it and topped up to the window's alpha
// (Zenon.tabOver), the tab kept the glass's navy and sat bluer than the bar.
//
// Under the cell the thin glass fades out as the cell fades in, so a cell
// rebuilt or still arriving never leaves a hole.
//
//     TabGlass { cell: strip.hereCell; here: Zenon.layerBg }
//
// `cell` is the active tab's Item, in this item's coordinates (the strip's,
// when this is laid at the strip's place).
import QtQuick
import "."

Item {
  id: glass
  property Item cell: null
  property color away: Zenon.alpha(Zenon.tabAwayInk, Zenon.tabAway(Zenon.layerBg.a))
  property color here: Zenon.layerBg

  readonly property real cellX: cell ? Math.max(0, Math.min(width, cell.x)) : width
  readonly property real cellR: cell ? Math.max(cellX, Math.min(width, cell.x + cell.width)) : width
  readonly property real cellInk: cell ? cell.opacity : 0

  Rectangle {
    width: glass.cellX
    height: parent.height
    color: glass.away
  }
  Rectangle {
    x: glass.cellR
    width: parent.width - x
    height: parent.height
    color: glass.away
  }
  Rectangle {
    x: glass.cellX
    width: glass.cellR - glass.cellX
    height: parent.height
    opacity: 1 - glass.cellInk
    color: glass.away
  }
  Rectangle {
    visible: !!glass.cell
    x: glass.cellX
    width: glass.cellR - glass.cellX
    height: parent.height
    opacity: glass.cellInk
    color: glass.here
  }
}
