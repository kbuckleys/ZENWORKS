// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// The bar's view of the jobs: JobsCard, in the suite's bubble (terminus/
// Bubble) with its tail on JobsModule, as terminus' drawer and iris'
// downloads hang theirs (user, 2026-10-13). Sticky: held up while the
// pointer is on the module or crosses onto the card, with the bubble's own
// grace for the gap. Standing on the bar when the bar is at the bottom.

import QtQuick
import Quickshell
import "."
import "../terminus" as Term

Term.Bubble {
  id: panel

  // the bar item it hangs from, and whether the pointer is on it
  property Item anchorItem: null
  property bool sourceHovered: false

  window: panel.anchorItem ? panel.anchorItem.QsWindow.window : null
  target: panel.anchorItem
  shown: panel.sourceHovered && Jobs.model.count > 0
  sticky: true
  fit: false
  cardWidth: 400
  up: !Zenon.barTop
  // read once the pointer has left it, as terminus' drawer does
  onOpenChanged: if (!panel.open) Jobs.clearEnded()

  JobsCard {
    width: 372
    bare: true
  }
}
