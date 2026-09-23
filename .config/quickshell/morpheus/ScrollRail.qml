// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE SCROLLBAR, AS THE WINDOWS WEAR IT — morpheus/Scrollbar with the
// windows' settings. Not a second design: terminus and ceres take the one
// scrollbar with a 10px grab (their rows run columns to the edge, and a wide
// grab would take those clicks) and the wheel passed through to the list's
// own smooth scroll.
//
//     ScrollRail { target: list; anchors.right: ...; anchors.top: ...; anchors.bottom: ... }

import QtQuick
import "."

Scrollbar {
  id: rail
  required property Flickable target
  flick: rail.target
  thickness: 10
  grabPad: 0
  handleWheel: false
}
