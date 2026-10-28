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
  // the label's and the empty box's inks, and the label's size — for a
  // Check standing among controls that speak in another (picasso's foot,
  // in the accent beside its chips: user, 2026-10-25)
  property color offInk: Zenon.accentKey
  property color litInk: Zenon.white
  property real textSize: Zenon.px(15)
  property bool kbOn: false
  // pressed from outside: a holder that takes the tap itself (a whole
  // settings row, a wider hit area) and turns this one's off says so here
  property bool held: false
  readonly property bool down: ckTap.pressed || ck.held
  signal toggled()
  spacing: 8
  opacity: ck.enabled2 ? 1 : Zenon.disabledDim
  Rectangle {
    id: ckBox
    anchors.verticalCenter: parent.verticalCenter
    width: 18
    height: 18
    radius: Zenon.rad(4)
    // pressed, darkened — the suite's press (user, 2026-10-17). No tint
    // when on: the ringed border and tick say it (user, 2026-10-21)
    color: ck.down ? Zenon.pressFill : "transparent"
    Behavior on color { ColorAnimation { duration: Zenon.fast } }
    // a touch heavier than a hairline (user, 2026-10-21)
    border.width: 1.5
    border.color: ck.lit ? ck.ink : ck.offInk
    Text {
      anchors.centerIn: parent
      visible: ck.lit
      text: ""
      color: ck.ink
      opacity: ck.down ? Zenon.pressDim : 1
      font.family: Zenon.face
      font.weight: Font.Bold
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
    textFormat: Text.PlainText
    visible: ck.label !== ""
    anchors.verticalCenter: parent.verticalCenter
    text: ck.label
    color: ck.lit ? ck.litInk : ck.offInk
    opacity: ck.down ? Zenon.pressDim : 1
    font.family: Zenon.face
    font.weight: Zenon.weight
    font.pixelSize: ck.textSize
  }
  TapHandler { id: ckTap; enabled: ck.enabled2; onTapped: ck.toggled() }
}
