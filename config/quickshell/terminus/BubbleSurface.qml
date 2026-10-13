// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A BUBBLE, FOR A WINDOW THAT IS NOT QUICKSHELL'S — terminus/Bubble's API and
// its card (BubbleCard) on morpheus/surface/PopupSurface instead of
// quickshell's PopupWindow: iris' site settings, its downloads. So it is the
// shell's bubble — its own popup surface, frosted by the compositor, its
// shadow and fade — not one drawn inside the window.
//
//     BubbleSurface { host: win; target: chip; shown: …; cardWidth: 360
//                     Text { … }  Segments { … } }      // stacked, 10 apart
//
// Hung under the target, centred on it and kept inside the host window, its
// tail at the target's middle. `grab`: a bubble opened by a click, to be
// used — it takes the pointer, and a click anywhere else puts it away
// (`dismissed`). Without, it is a hover's: `sticky` holds it up while the
// pointer is on it (after a moment's grace to cross the gap), as Bubble's.

import QtQuick
import QtQuick.Window
import "../morpheus/surface"
import "../morpheus"

PopupSurface {
  id: bub
  property Item target: null
  property bool shown: false
  property real cardWidth: 380
  property bool fit: true
  property bool sticky: false
  readonly property bool over: face.over
  default property alias bubbleContent: face.content
  // the card itself, for a holder that measures against it
  readonly property Item card: face.card

  Timer { id: graceTimer; interval: 350 }
  onShownChanged: if (!bub.shown && bub.sticky) graceTimer.restart()
  open: bub.shown || (bub.sticky && !bub.grab && (face.over || graceTimer.running))

  // where the target is, read as it opens (a binding round mapToItem does
  // not re-run when the geometry under it moves)
  property point targetAt: Qt.point(0, 0)
  function measure() {
    if (!bub.target || !bub.host) return;
    const p = bub.target.mapToItem(null, bub.target.width / 2, bub.target.height);
    bub.targetAt = p;
  }
  onOpenChanged: if (bub.open) bub.measure()
  Component.onCompleted: bub.measure()

  width: face.implicitWidth
  height: face.implicitHeight
  // centred under the target, slid back inside the host window
  readonly property real leftX: Math.max(0, Math.min((bub.host ? bub.host.width : 0) - bub.width,
                                                       bub.targetAt.x - bub.width / 2))
  at: Qt.point(bub.leftX, bub.targetAt.y + 2)

  // the card, into the surface by name: this file's own default (what a
  // holder puts in it) is the card's content
  content: BubbleCard {
    id: face
    anchors.fill: parent
    shade: bub.shade
    cardWidth: bub.cardWidth
    fit: bub.fit
    sticky: bub.sticky || bub.grab
    aim: bub.targetAt.x - bub.leftX
  }
}
