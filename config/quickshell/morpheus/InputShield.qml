// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE SHIELD A MODAL CARD STANDS BEHIND — swallows every button, the wheel
// and hover, and calls a still click away from the card `clicked()`. Moved
// out of TerminusWindow with Sheet, which it goes with.

import QtQuick
import "."

Item {
  id: shield
  anchors.fill: parent

  // HOW MUCH OF THE TOP IS THE SHEET'S OWN HEAD. A sheet morphs the tab
  // strip and the path bar into its header, so those pixels READ as the
  // card's title while sitting outside the card — and a shield that
  // dismissed on any click dismissed when you clicked the sheet's own
  // title. Clicks up there are still swallowed; they just do not count as
  // clicking away. Left at 0 for anything that is not a sheet.
  property real keepTop: 0
  // The card this shield is behind, if it has one. A press that starts ON
  // it is never clicking away — even on a part of the card that takes no
  // input of its own, which is where the shield underneath would otherwise
  // hear it.
  property Item keep: null
  signal clicked()

  // Swallows EVERYTHING, the head band included: the point of the shield
  // is that nothing behind a modal reacts, and that is as true of the
  // header as it is of the listing.
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.AllButtons
    // claimed as well, so nothing behind lights up under the pointer
    hoverEnabled: true
    WheelHandler {
      // every device, and nothing passed on
      onWheel: (e) => { e.accepted = true; }
    }
  }

  // CLICKING AWAY, which is only ever the part below the chrome. Declared
  // second so it takes the clicks in its own band off the swallower above.
  //
  // ── A DRAG IS NOT A CLICK ──────────────────────────────────────────
  // MouseArea calls it clicked whenever the release lands inside it,
  // however far the pointer travelled — so dragging across quick look
  // (to scroll, to pull the page strip, or just a hand that moved) and
  // letting go shut it. Only a press that stays put, and did not start
  // on the card, is the click that means "put this away".
  MouseArea {
    id: away
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.top: parent.top
    anchors.topMargin: shield.keepTop
    acceptedButtons: Qt.AllButtons
    property point from: Qt.point(0, 0)
    property bool onCard: false
    onPressed: (m) => {
      away.from = Qt.point(m.x, m.y);
      const k = shield.keep;
      away.onCard = !!k && k.visible
        && k.contains(k.mapFromItem(away, m.x, m.y));
    }
    onClicked: (m) => {
      if (away.onCard) return;
      if (Math.abs(m.x - away.from.x) > 6 || Math.abs(m.y - away.from.y) > 6) return;
      shield.clicked();
    }
  }
}
