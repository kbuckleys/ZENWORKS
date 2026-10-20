// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE WINDOW BEHIND A SHEET, SET BACK — one darken (Zenon.sheetDim) over a
// box, with the card cut out of it. Every Sheet lays its own (see
// morpheus/Sheet's dim), so no window carries a scrim of its own.
//
//     SheetDim { x: …; y: …; width: …; height: …; ink: card.opacity
//                holeX: …; holeY: …; holeW: …; holeH: … }
//
// THE CARD IS A HOLE, not something drawn over the dim: a glass card
// (terminus', picasso's) lets what is under it through, so a dim behind it
// darkened the card too — and the bar it hangs from, which is not dimmed,
// stopped being the same glass at the seam. The hole is in the PARENT's
// coordinates (the sheet's), so a caller hands over the card's box as drawn
// and never has to know where this box starts. Whatever of the hole falls
// outside the box (a hanging card's cut corners, above the bar) is clipped.
//
// No hole (holeW 0) is a plain darkened box: the strip beside a bar.

import QtQuick
import QtQuick.Shapes
import "."

Item {
  id: dim
  // how far in: the card's own fade, so the window goes back as it arrives
  property real ink: 1
  // the box's own corners — a popup's rounded panel
  property real radius: 0
  property real holeX: 0
  property real holeY: 0
  property real holeW: 0
  property real holeH: 0
  property real holeRadius: Zenon.dialogRadius

  opacity: dim.ink
  visible: dim.ink > 0.001 && dim.width > 0 && dim.height > 0
  clip: true

  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      fillRule: ShapePath.OddEvenFill
      fillColor: Zenon.darken(Zenon.sheetDim)
      strokeColor: "transparent"
      strokeWidth: 0
      PathRectangle {
        width: dim.width
        height: dim.height
        radius: dim.radius
      }
      PathRectangle {
        x: dim.holeX - dim.x
        y: dim.holeY - dim.y
        width: dim.holeW
        height: dim.holeH
        radius: dim.holeW > 0 ? dim.holeRadius : 0
      }
    }
  }
}
