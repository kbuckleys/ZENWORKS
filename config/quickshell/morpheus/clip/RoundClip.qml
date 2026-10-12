// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A ROUNDED CLIP IN PLAIN QT QUICK — what quickshell's ClippingRectangle does,
// without quickshell, so a part that needs one (Sheet) loads in iris as well
// as in the shell. Same three layers as ClippingRectangle's shader:
//
//   inside      the background, then the content over it, cut to the area
//               inside the border (the border's inner edge, radius − width)
//   the border  a Rectangle's own ring, laid over that
//
// The content is inset by the border on every side, as ClippingRectangle's
// is (contentInsideBorder), so a card that gives its body cardW × cardH still
// adds the border to its own size. The cut is a MultiEffect mask (QtQuick's,
// already used across the suite): like ClippingRectangle, the content is
// drawn through a texture, so keep the clip on whole pixels.
//
// Only what Sheet uses: color, radius, border, children. Directory of its own
// so a live reload finds it (a new morpheus/qmldir line needs a restart).

import QtQuick
import QtQuick.Effects

Item {
  id: root

  // under the content, inside the border
  property color color: "transparent"
  property real radius: 0
  // the ring: border.width / border.color, as on a Rectangle
  readonly property alias border: frame.border
  // not `data`: that is Item's own, and overriding it is a warning in Qt 6.12
  default property alias contentData: content.data
  readonly property alias contentItem: content

  Item {
    id: inside
    anchors.fill: parent
    layer.enabled: true
    // sampled smoothly while a sheet scales in, as ClippingRectangle's
    // texture is (a layer's default is nearest: text went ragged mid-scale)
    layer.smooth: true
    layer.effect: MultiEffect {
      maskEnabled: true
      maskSource: cut
      // the mask's antialiased edge, as a ramp: MultiEffect smoothsteps over
      // [min − spread/2, min + spread/2], so this is smoothstep(0, 1, alpha)
      // — measured, the nearest it comes to ClippingRectangle's linear cut
      // (equal at 0, ½ and 1; within 25/255 on an edge pixel between)
      maskThresholdMin: 0.5
      maskSpreadAtMin: 1.0
    }

    Rectangle {
      anchors.fill: parent
      color: root.color
    }

    Item {
      id: content
      anchors.fill: parent
      anchors.margins: frame.border.width
    }
  }

  // the area inside the border, which is what the content is cut to
  Item {
    id: cut
    anchors.fill: parent
    visible: false
    layer.enabled: true
    layer.smooth: true

    Rectangle {
      anchors.fill: parent
      anchors.margins: frame.border.width
      radius: Math.max(0, root.radius - frame.border.width)
      antialiasing: true
    }
  }

  Rectangle {
    id: frame
    anchors.fill: parent
    color: "transparent"
    radius: root.radius
    antialiasing: true
  }
}
