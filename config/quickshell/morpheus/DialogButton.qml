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
  // at rest, and pressed — the pressed one is the point: a button that
  // looks the same under the finger as at rest has not confirmed anything.
  // NO HOVER TINT (user, 2026-10-11): the suite's buttons do not light up
  // as the pointer passes; the `hovered` signal still tells a card where
  // the pointer is.
  // The plain button wears a faint wash of its ink at rest (user,
  // 2026-10-12: "a little more prominent") — bare, it was a hairline round
  // a word and read as a label, not something to press. The default answer
  // keeps a stronger wash, plus its ring and glow.
  //
  // A GREY BUTTON IS NOT A DIMMED ONE (user, 2026-10-12: Back beside a
  // lit Close "almost looks dimmed"). Muted ink is the disabled look's own
  // colour, so a plain button speaking in it reads as switched off: it
  // says its word in the foreground ink instead, on the theme's own wash
  // (lighter on a dark theme, darker on a light one) rather than a tint
  // of grey. Only a button that is not ready keeps the muted word.
  readonly property bool plain: Qt.colorEqual(btn.ink, Zenon.muted)
  readonly property color word: btn.plain ? Zenon.white : btn.ink
  color: !btn.ready ? "transparent"
    : btn.plain && !btnArea.pressed ? Zenon.wash(btn.primary ? 0.16 : 0.12)
    : Qt.rgba(btn.ink.r, btn.ink.g, btn.ink.b,
              btnArea.pressed ? 0.45 : (btn.primary ? 0.14 : 0.10))
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

  // The pulse lives on a child rather than on the button, so pressing can
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
      // ONLY WHERE IT CAN BE SEEN. An infinite animation ticks the GUI
      // thread every frame wherever it is; in a hidden dialog it did so for
      // nothing, and in a window that is on screen it made that window
      // redraw continuously behind a dialog nobody had open. A profile caught
      // ~20 of these running at once (~1,900 updates a second, 2026-10-09).
      // `visible` covers a hidden ancestor; the window covers a hidden window.
      running: btn.primary && btn.ready && btn.visible
        && btn.Window.visibility !== Window.Hidden
      loops: Animation.Infinite
      NumberAnimation { to: 0.15; duration: 900; easing.type: Easing.InOutQuad }
      NumberAnimation { to: 0.85; duration: 900; easing.type: Easing.InOutQuad }
    }
  }

  Text {
    id: btnText
    anchors.centerIn: parent
    text: btn.label
    color: btn.ready ? btn.word : Zenon.muted
    font.family: Zenon.face
    font.weight: Font.Bold
    font.pixelSize: Zenon.px(15)
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
