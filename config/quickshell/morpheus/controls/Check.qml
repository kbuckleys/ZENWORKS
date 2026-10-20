// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE SUITE'S CHECKBOX: a box with a tick, in `ink` (cyan) when on, and an
// optional label beside it. It was ceres' (its settings' flags and repos,
// setup's "Also add Flatpak apps", the store); Oracle's Tools wanted the
// same box for picking what to install (user, 2026-10-18: "make it a
// helper"), so it lives here now.
//
//   import "../morpheus/controls"
//   Check { lit: on; label: "Optional"; onToggled: on = !on }
//
// A directory with no qmldir, imported by path, as morpheus/undo is: a type
// added to morpheus/qmldir is not seen until the shell restarts.
//
// THE ONE ON/OFF (user, 2026-10-20: "scrap toggle"): the suite had a
// toggle switch too — picasso's Switch, oracle's and plato's settings,
// terminus' prefs — for the same job. They are all this box now. `kbOn`
// rings it while the keyboard is on it, as picasso's Ring did the switch.
//
// `enabled2`, not `enabled`: Item's own `enabled` would also cut off the tap
// that has to stay to say it is off.

import QtQuick
import ".."

Row {
  id: ck
  property bool lit: false
  property string label: ""
  property bool enabled2: true
  property color ink: Zenon.cyan
  property bool kbOn: false
  signal toggled()
  spacing: 8
  opacity: ck.enabled2 ? 1 : 0.4
  Rectangle {
    id: ckBox
    anchors.verticalCenter: parent.verticalCenter
    width: 18
    height: 18
    radius: Zenon.windowRadius - 1
    // pressed, darkened — the suite's press (user, 2026-10-17)
    color: ckTap.pressed ? Zenon.pressFill
      : ck.lit ? Qt.rgba(ck.ink.r, ck.ink.g, ck.ink.b, 0.2) : "transparent"
    Behavior on color { ColorAnimation { duration: Zenon.fast } }
    border.width: 1
    border.color: ck.lit ? ck.ink : Zenon.accentKey
    Text {
      anchors.centerIn: parent
      visible: ck.lit
      text: ""
      color: ck.ink
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(11)
    }
    // the keyboard is here
    Rectangle {
      visible: ck.kbOn
      anchors.fill: parent
      anchors.margins: -3
      radius: ckBox.radius + 3
      color: "transparent"
      border.width: 2
      border.color: Zenon.cyan
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
  TapHandler { id: ckTap; enabled: ck.enabled2; onTapped: ck.toggled() }
}
