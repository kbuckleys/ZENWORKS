// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// TOPSHADE — a soft shade falling from the bar onto a view once it is
// scrolled, so the bar reads as above the rows rather than cut into them.
// Nothing at the top of the listing, where there is nothing under the bar.
//
//     TopShade { view: list; x: list.x; y: list.y; width: list.width }
//
// A sibling of the view, over it — a Flickable's own children scroll with
// its content. Terminus' list, grid and columns; picasso's gallery.

import QtQuick
import "../morpheus"

Rectangle {
  id: shade
  property Flickable view: null
  property bool on: true
  height: 22
  z: 4
  readonly property bool scrolled: !!shade.view && shade.view.contentY - shade.view.originY > 2
  opacity: shade.on && shade.scrolled ? 1 : 0
  visible: opacity > 0.01
  Behavior on opacity { NumberAnimation { duration: Zenon.normal; easing.type: Easing.OutCubic } }
  gradient: Gradient {
    GradientStop { position: 0; color: Zenon.darken(0.32) }
    GradientStop { position: 1; color: "transparent" }
  }
}
