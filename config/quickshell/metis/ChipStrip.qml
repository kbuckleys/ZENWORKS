// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/

import QtQuick
import QtQuick.Effects
import "../morpheus"

// THE ROW OF CHIPS, WHEN THERE ARE MORE THAN FIT. Centred while they fit;
// past that it scrolls sideways — the wheel or a touchpad, with the shell's
// own feel (morpheus ElasticScroll, as howler's filter chips have it) — and
// whichever end has more beyond it fades out instead of being cut off at the
// panel's edge. The fade is ScrollEdge's: a gradient drawn only into a
// texture and used as the mask.
//
//     ChipStrip { Repeater { … MetisChip {} } }
Item {
  id: strip

  default property alias content: row.data
  property int spacing: 6
  // how far each end fades, when there is more past it
  property int fadeW: 32

  // the row's own width — what its chips want, for whoever sizes the panel
  // (it never reads the strip's width, so measuring by it closes no loop)
  readonly property real contentW: row.implicitWidth
  readonly property bool overflow: row.implicitWidth > strip.width + 0.5
  readonly property bool moreLeft: strip.overflow && flick.contentX > 1
  readonly property bool moreRight: strip.overflow
    && flick.contentX < flick.contentWidth - flick.width - 1

  height: 26
  clip: true

  // brings a chip into view — for Tab, which can select one off the edge
  function reveal(item) {
    if (!item || !strip.overflow) return;
    const pad = strip.fadeW;
    let to = flick.contentX;
    if (item.x - pad < to) to = item.x - pad;
    else if (item.x + item.width + pad > to + flick.width) to = item.x + item.width + pad - flick.width;
    to = Math.max(0, Math.min(flick.contentWidth - flick.width, to));
    glide.stop();
    glide.to = to;
    glide.start();
  }

  NumberAnimation {
    id: glide
    target: flick
    property: "contentX"
    duration: Zenon.normal
    easing.type: Easing.OutCubic
  }

  Flickable {
    id: flick
    ElasticScroll { view: flick; horizontal: true; step: 120 }
    anchors.fill: parent
    contentWidth: Math.max(row.implicitWidth, flick.width)
    contentHeight: height
    interactive: strip.overflow
    flickableDirection: Flickable.HorizontalFlick
    boundsBehavior: Flickable.StopAtBounds

    layer.enabled: strip.overflow
    layer.effect: MultiEffect {
      maskEnabled: true
      maskSource: rampTex
      maskThresholdMin: 0.5
      maskSpreadAtMin: 1.0
    }

    Row {
      id: row
      // centred while it fits, from the left once it scrolls
      x: strip.overflow ? 0 : (flick.width - row.implicitWidth) / 2
      spacing: strip.spacing
    }
  }

  // the mask: opaque in the middle, each end fading only if there is more
  // past it
  Rectangle {
    id: ramp
    width: strip.width
    height: strip.height
    readonly property real l: strip.moreLeft ? strip.fadeW / Math.max(1, strip.width) : 0.0001
    readonly property real r: strip.moreRight ? 1 - strip.fadeW / Math.max(1, strip.width) : 0.9999
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0.0; color: strip.moreLeft ? "#00000000" : "#ff000000" }
      GradientStop { position: ramp.l; color: "#ff000000" }
      GradientStop { position: ramp.r; color: "#ff000000" }
      GradientStop { position: 1.0; color: strip.moreRight ? "#00000000" : "#ff000000" }
    }
  }
  ShaderEffectSource {
    id: rampTex
    width: ramp.width
    height: ramp.height
    sourceItem: ramp
    hideSource: true
    visible: false
  }
}
