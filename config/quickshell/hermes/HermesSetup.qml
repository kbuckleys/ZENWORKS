// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A piece Hermes needs and this machine has not got: what it is, what
// setting it up does, and the one button that does it (through Ceres).
// Without an `action` it only says why, for hardware that is not there.

import QtQuick
import "../morpheus"
import "../terminus"

Column {
  id: s

  property string glyph: ""
  property string title: ""
  property string body: ""
  property string action: ""
  // a second, plain answer beside the first ("Turn off Bluetooth")
  property string action2: ""
  property bool busy: false
  property color ink: Zenon.cyan
  signal go()
  signal go2()

  spacing: 10

  Text {
    anchors.horizontalCenter: parent.horizontalCenter
    text: s.glyph
    color: s.action !== "" ? s.ink : Zenon.accentMuted
    font.family: Zenon.glyphFace
    font.pixelSize: Zenon.px(40)
  }
  Text {
    textFormat: Text.PlainText
    anchors.horizontalCenter: parent.horizontalCenter
    text: s.title
    color: Zenon.ink
    font.family: Zenon.face
    font.weight: Zenon.titleWeight
    font.pixelSize: Zenon.px(18)
  }
  EmptyState {
    width: Math.min(parent.width, 520)
    anchors.horizontalCenter: parent.horizontalCenter
    text: s.body
    visible: s.body !== ""
  }
  Item { width: 1; height: 4; visible: s.action !== "" }
  Row {
    anchors.horizontalCenter: parent.horizontalCenter
    spacing: 10
    visible: s.action !== ""
    DialogButton {
      visible: s.action2 !== ""
      label: s.action2
      ready: !s.busy
      onClicked: s.go2()
    }
    BusyButton {
      label: s.action
      primary: true
      busy: s.busy
      busyText: "Setting up…"
      onClicked: s.go()
    }
  }
}
