// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// The bar's view of the jobs: JobsCard, hanging off JobsModule on hover, the
// way NowPlayingPanel hangs off the audio group — held open while the pointer
// is on either, with the same short grace for crossing the gap between them.

import QtQuick
import "."

CursorAnchor {
  id: panel

  interactive: true
  hitArea: card
  gap: 6

  property bool sourceHovered: false

  readonly property bool wanted: (panel.sourceHovered || card.hovered)
    && Jobs.model.count > 0
  property bool held: false
  onWantedChanged: {
    if (panel.wanted) { panel.held = true; unlatch.stop(); }
    else unlatch.restart();
  }
  Timer {
    id: unlatch
    interval: 220
    onTriggered: {
      panel.held = panel.wanted;
      // read once the pointer has left it, as terminus' drawer does
      if (!panel.held) Jobs.clearEnded();
    }
  }
  show: panel.held

  pad: Zenon.menuShadowPad
  implicitWidth: card.width + Zenon.menuShadowPad * 2
  implicitHeight: card.height + Zenon.menuShadowPad * 2

  MenuShadow {
    panel: card
    cornerRadius: card.radius
    opacity: card.opacity
  }

  JobsCard {
    id: card
    x: Zenon.menuShadowPad
    y: Zenon.menuShadowPad
    opacity: panel.showFactor
    shown: panel.showFactor
  }
}
