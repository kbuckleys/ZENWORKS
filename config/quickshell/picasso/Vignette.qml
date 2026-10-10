// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// VIGNETTE — the edges of a picture darkened towards the corners, the way a
// lens falls off. Worn by the background (see Scene) and by the card's
// preview, so the two agree.
//
// NOT AN EFFECT PASS. It is one shape laid on top, filled with a radial
// gradient that runs from clear in the middle to dark at the rim — the same
// kind of thing as the dim, which is a black rectangle laid on top. Nothing
// is copied offscreen. And it is only built while `amount` is above zero, so
// a picture without one pays nothing for its being possible.
//
// ELLIPTICAL, to the shape of what it covers: the gradient is drawn in a
// square and the square is stretched to the item, so on a wide screen the
// falloff reaches the sides and the top at the same point rather than
// eating into the sides first.

import QtQuick
import QtQuick.Shapes

Item {
  id: vig

  // 0 .. 1 — how far in it reaches and how dark the rim gets, together
  property real amount: 0

  Loader {
    anchors.fill: parent
    active: vig.amount > 0 && vig.width > 0 && vig.height > 0
    sourceComponent: Shape {
      id: shape
      // a square the height of the item, stretched across its width
      readonly property real side: vig.height
      width: shape.side
      height: shape.side
      transform: Scale { xScale: vig.width / Math.max(1, shape.side) }

      ShapePath {
        strokeWidth: -1
        strokeColor: "transparent"
        fillGradient: RadialGradient {
          centerX: shape.side / 2
          centerY: shape.side / 2
          focalX: shape.side / 2
          focalY: shape.side / 2
          // to the corners: half the diagonal of the square
          centerRadius: shape.side / Math.SQRT2
          focalRadius: 0
          // Clear through the middle, then an eased fall to the rim. The
          // clear core shrinks and the rim darkens as the amount rises, so
          // one slider does what a lens's size and strength would.
          GradientStop { position: 0; color: "transparent" }
          GradientStop { position: 0.62 - 0.3 * vig.amount; color: "transparent" }
          GradientStop {
            position: 0.86 - 0.12 * vig.amount
            color: Qt.rgba(0, 0, 0, (0.3 + 0.55 * vig.amount) * 0.45)
          }
          GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.3 + 0.55 * vig.amount) }
        }
        startX: 0; startY: 0
        PathLine { x: shape.side; y: 0 }
        PathLine { x: shape.side; y: shape.side }
        PathLine { x: 0; y: shape.side }
        PathLine { x: 0; y: 0 }
      }
    }
  }
}
