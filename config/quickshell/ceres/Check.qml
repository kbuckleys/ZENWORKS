// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// The Installed checkbox's look: a box with a tick, cyan when on. Settings'
// flags and repos, and setup's "Also add Flatpak apps" — out of ConfigView,
// where it was an inline component, so setup could have the same box.

import QtQuick
import "../morpheus"

Row {
  id: ck
  property bool lit: false
  property string label: ""
  property bool enabled2: true
  signal toggled()
  spacing: 8
  opacity: ck.enabled2 ? 1 : 0.4
  Rectangle {
    anchors.verticalCenter: parent.verticalCenter
    width: 18
    height: 18
    radius: Zenon.windowRadius - 1
    color: ck.lit ? Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.2) : "transparent"
    border.width: 1
    border.color: ck.lit ? Zenon.cyan : Zenon.accentKey
    Text {
      anchors.centerIn: parent
      visible: ck.lit
      text: ""
      color: Zenon.cyan
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(11)
    }
  }
  Text {
    visible: ck.label !== ""
    anchors.verticalCenter: parent.verticalCenter
    text: ck.label
    color: ck.lit ? Zenon.white : Zenon.accentKey
    font.family: Zenon.face
    font.weight: Zenon.weight
    font.pixelSize: Zenon.px(15)
  }
  TapHandler { enabled: ck.enabled2; onTapped: ck.toggled() }
}
