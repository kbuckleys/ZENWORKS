// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE BUTTON — terminus' dialog button, and now everyone's. It was an inline
// component of TerminusWindow; ceres wanted the same one, and two copies of a
// button are two buttons the day one of them is changed. So it lives here,
// and terminus and ceres both use this file.
//
//   ink       the colour it speaks in — its label, its fill, its ring
//   primary   the default answer: filled a little, ringed, and breathing
//   ready     false greys it out and stops it answering

import QtQuick
import QtQuick.Effects
import "."

Rectangle {
  id: btn
  property string label: ""
  property color ink: Zenon.muted
  property bool primary: false
  property bool ready: true
  signal clicked()
  // so a card can keep its keyboard highlight and the pointer in step
  signal hovered()

  implicitWidth: Math.max(96, btnText.implicitWidth + 34)
  implicitHeight: 28
  radius: 4
  // three states, and the pressed one is the point: a button that looks the
  // same under the finger as it does under the pointer has not confirmed
  // anything
  color: !btn.ready ? "transparent"
    : Qt.rgba(btn.ink.r, btn.ink.g, btn.ink.b,
              btnArea.pressed ? 0.45 : (btnHover.hovered ? 0.22
                : (btn.primary ? 0.12 : 0.0)))
  border.width: 1
  border.color: Zenon.border
  opacity: btn.ready ? 1 : 0.55

  Behavior on color {
    ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease }
  }

  // ── AND IT GLOWS ─────────────────────────────────────────────────
  // A soft light of the button's own ink behind it, breathing with the
  // ring: the default answer should read as lit, not only outlined. One
  // blurred shape — no layer, no second animation — and it follows the
  // ring's opacity rather than keeping time of its own, so the two can
  // never drift apart. Behind the button (z -1), so the label sits on top.
  RectangularShadow {
    anchors.fill: parent
    z: -1
    radius: parent.radius
    blur: 14
    spread: 1
    color: Qt.rgba(btn.ink.r, btn.ink.g, btn.ink.b, 0.55)
    visible: pulseRing.visible
    opacity: pulseRing.opacity
  }

  // The pulse lives on a child rather than on the button, so hovering can
  // brighten it without fighting an animation for the same property.
  //
  // In the button's INK, not the shared border: it is a cue — this is the
  // default — and one of the special cases the one-border rule leaves be.
  Rectangle {
    id: pulseRing
    anchors.fill: parent
    radius: parent.radius
    color: "transparent"
    border.width: 1
    border.color: btn.ink
    visible: btn.primary && btn.ready
    SequentialAnimation on opacity {
      running: btn.primary && btn.ready
      loops: Animation.Infinite
      NumberAnimation { to: 0.15; duration: 900; easing.type: Easing.InOutQuad }
      NumberAnimation { to: 0.85; duration: 900; easing.type: Easing.InOutQuad }
    }
  }

  Text {
    id: btnText
    anchors.centerIn: parent
    text: btn.label
    color: btn.ready ? btn.ink : Zenon.muted
    font.family: Zenon.face
    font.weight: Font.Bold
    font.pixelSize: 15
  }

  HoverHandler {
    id: btnHover
    enabled: btn.ready
    onHoveredChanged: if (hovered) btn.hovered()
  }
  MouseArea {
    id: btnArea
    anchors.fill: parent
    enabled: btn.ready
    onClicked: btn.clicked()
  }
}
