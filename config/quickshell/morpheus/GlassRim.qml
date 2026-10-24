// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE GLASS RIM — light along a card's top edge, fading out before the
// corners turn (see Zenon.rim). Dropped into a rounded Rectangle as a child;
// it reads the parent's radius. Tooltip's card and terminus' TipCard wore
// two copies of it (2026-10-24).

import QtQuick
import "."

Rectangle {
  id: rim
  readonly property real cornerRadius: (rim.parent as Rectangle)?.radius ?? 0
  z: 100
  x: rim.cornerRadius
  y: 1
  width: Math.max(0, (rim.parent ? rim.parent.width : 0) - 2 * rim.cornerRadius)
  height: 1
  gradient: Gradient {
    orientation: Gradient.Horizontal
    GradientStop { position: 0.0; color: Zenon.alpha(Zenon.rim, 0) }
    GradientStop { position: 0.25; color: Zenon.rim }
    GradientStop { position: 0.75; color: Zenon.rim }
    GradientStop { position: 1.0; color: Zenon.alpha(Zenon.rim, 0) }
  }
}
