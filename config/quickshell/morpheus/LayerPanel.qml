// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// LAYERPANEL — the body of a LayerPopup, everything but its ground.
//
// Where the panel sits (off the bar's edge by the same lift as the pill), how
// it grows (out of that edge, on the layer's panelX/panelY), how it fades,
// the click-eater under it and its shadow. That was written out in twelve
// layers, identical down to the comments; each now declares its size, its
// ground and whatever is its own.
//
// The ground (the ClippingRectangle with the color, the border and the
// content) stays in the layer: no two of them agree on it.

import QtQuick
import "."

Item {
  id: root

  // the LayerPopup this is the body of
  required property var host
  // what the shadow follows: the layer's ground
  property Item ground: null
  property real shadowRadius: Zenon.pillRadius

  // a press anywhere on the panel that nothing above took
  signal pressed()

  // Zenon.slow is the pill's own height easing in shell.qml; if these drift
  // apart the panel visibly detaches from its background mid-resize
  Behavior on height { NumberAnimation { duration: Zenon.slow; easing.type: Zenon.ease } }
  // Either edge. A layer opens out of the pill, so it has to be on the
  // same one, off whichever it is by the same lift. Placed by y, NOT by a
  // top/bottom anchor pair: flipping two anchors at runtime updates one
  // before the other, for that instant both apply and stretch the panel to
  // the screen, and that stretch overwrites — and so unbinds — `height`.
  // The panel then stayed screen-tall until the shell was restarted.
  anchors.horizontalCenter: parent.horizontalCenter
  y: Zenon.barTop ? Zenon.edgeLift(root.host.morphMode, root.host.screen, root.host.statusbar)
    : parent.height - height - Zenon.edgeLift(root.host.morphMode, root.host.screen, root.host.statusbar)
  z: 1
  opacity: root.host.contentFade
  transform: Scale {
    origin.x: root.width / 2
    // grows out of the edge the bar is on, which is the edge it came from
    origin.y: Zenon.barTop ? 0 : root.height
    xScale: root.host.panelX
    yScale: root.host.panelY
  }

  MouseArea { anchors.fill: parent; onPressed: root.pressed() }

  LayerShadow {
    panel: root.ground
    cornerRadius: root.shadowRadius
    morphed: root.host.morphMode
  }
}
