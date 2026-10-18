// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// REMOVE, AS A TRASH GLYPH — StoreGet's corners and press, in red, and
// square, and after Open wherever an installed app shows both — the
// category cards and the app's page alike (user, 2026-10-18). The glyph is
// terminus' Trash (trash_can_outline). It only asks: the window's confirm
// sheet says what goes before anything runs (StoreView.remove).

import QtQuick
import "../morpheus"

Rectangle {
  id: rm
  property bool busy: false
  property bool big: false
  signal removed()

  readonly property bool ready: !rm.busy

  width: rm.big ? 32 : 28
  height: width
  radius: Zenon.windowRadius
  color: !rm.ready ? Qt.tint(Zenon.ground, Zenon.wash(0.05))
    : rmMa.pressed ? Qt.tint(Zenon.ground, Zenon.pressFill)
    : Zenon.mix(Zenon.ground, Zenon.red, rm.big ? 0.22 : 0.16)
  border.width: 1
  border.color: rm.ready ? Zenon.alpha(Zenon.red, 0.5) : Zenon.border
  Behavior on color { ColorAnimation { duration: Zenon.ms(110) } }

  Text {
    anchors.centerIn: parent
    text: "\u{F0A7A}"
    color: rm.ready ? Zenon.red : Zenon.accentMuted
    font.family: Zenon.glyphFace
    font.pixelSize: Zenon.px(rm.big ? 18 : 16)
  }

  MouseArea {
    id: rmMa
    anchors.fill: parent
    enabled: rm.ready
    onClicked: rm.removed()
  }
}
