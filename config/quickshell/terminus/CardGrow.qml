// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// The other half. A card that grows the last few percent into place reads
// as arriving; one that only slides reads as being moved.
// (Its own file since quick look moved out of TerminusWindow — both use it.)

import QtQuick
import "../morpheus"

Scale {
  required property bool shown
  // The card being scaled, so the growth happens about its middle. Not
  // `parent` — a Transform has no parent to ask.
  property Item card: null
  origin.x: card ? card.width / 2 : 0
  origin.y: card ? card.height / 2 : 0
  xScale: shown ? 1 : 0.96
  yScale: shown ? 1 : 0.96
  Behavior on xScale {
    NumberAnimation {
      duration: shown ? Zenon.normal : Zenon.fast
      easing.type: Zenon.travelEase
    }
  }
  Behavior on yScale {
    NumberAnimation {
      duration: shown ? Zenon.normal : Zenon.fast
      easing.type: Zenon.travelEase
    }
  }
}
