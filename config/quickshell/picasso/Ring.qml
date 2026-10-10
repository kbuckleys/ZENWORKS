// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// The keyboard's ring, around whatever it is lit on. One of picasso's
// controls — see Seg — shared by the focus card and the viewer.

import QtQuick
import "../morpheus"

Rectangle {
  property bool on: false
  anchors.fill: parent
  anchors.margins: -3
  radius: 7
  color: "transparent"
  border.width: 2
  border.color: Zenon.cyan
  visible: on
}
