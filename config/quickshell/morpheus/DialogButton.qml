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
//   ink       the color it speaks in — its label, its fill, its ring
//   primary   the default answer: filled a little, ringed, and breathing
//   ready     false grays it out and stops it answering

import QtQuick
import QtQuick.Effects
import "."

Rectangle {
  id: btn
  property string label: ""
  property color ink: Zenon.muted
  property bool primary: false
  property bool ready: true
  // the label is a glyph (a Nerd icon), the button square-ish round it
  property bool glyph: false
  signal clicked()
  // so a card can keep its keyboard highlight and the pointer in step
  signal hovered()

  implicitWidth: btn.glyph ? Math.max(36, btnText.implicitWidth + 20) : Math.max(96, btnText.implicitWidth + 34)
  implicitHeight: 28
  radius: Zenon.radiusControl
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
  // A GRAY BUTTON IS NOT A DIMMED ONE (user, 2026-10-12: Back beside a
  // lit Close "almost looks dimmed"). Muted ink is the disabled look's own
  // color, so a plain button speaking in it reads as switched off: it
  // says its word in the foreground ink instead, on the theme's own wash
  // (lighter on a dark theme, darker on a light one) rather than a tint
  // of gray. Only a button that is not ready keeps the muted word.
  // the plain gray, neutral or in the accent (user, 2026-10-15: the
  // windows' grays follow the accent now)
  readonly property bool plain: Qt.colorEqual(btn.ink, Zenon.muted) || Qt.colorEqual(btn.ink, Zenon.accentMuted)
  readonly property color word: btn.plain ? Zenon.white : btn.ink
  // PRESSED, DARKENED (user, 2026-10-15): the shade and dimmed word of
  // terminus' ClearChip and Segments — every button in the suite presses
  // the same way (it was its own ink, deeper)
  color: !btn.ready ? "transparent"
    : btnArea.pressed && !btn.primary ? Zenon.pressFill
    : btn.plain ? Zenon.buttonRest(btn.primary)
    : Qt.rgba(btn.ink.r, btn.ink.g, btn.ink.b, btn.primary ? 0.14 : 0.10)
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
    id: glow
    anchors.fill: parent
    z: -1
    radius: parent.radius
    blur: 14
    spread: 1
    color: Qt.rgba(btn.ink.r, btn.ink.g, btn.ink.b, 0.55)
    visible: pulseRing.visible && !btnArea.pressed
    opacity: pulseRing.opacity
  }
  // PRESSED, THE GLOW OUTSIDE ONLY (user, 2026-10-15): the darkened fill is
  // see-through, and the glow under it lit the button from inside. While
  // held, the same glow with the button's own shape cut out of it — a
  // layer only for as long as the press, so the resting glow stays free.
  Item {
    id: glowCut
    readonly property real room: 24
    anchors.fill: parent
    anchors.margins: -room
    z: -1
    visible: pulseRing.visible && btnArea.pressed
    Item {
      id: glowSrc
      anchors.fill: parent
      visible: false
      layer.enabled: glowCut.visible
      RectangularShadow {
        anchors.fill: parent
        anchors.margins: glowCut.room
        radius: btn.radius
        blur: glow.blur
        spread: glow.spread
        color: glow.color
      }
    }
    Item {
      id: glowHole
      anchors.fill: parent
      visible: false
      layer.enabled: glowCut.visible
      Rectangle {
        anchors.fill: parent
        anchors.margins: glowCut.room
        radius: btn.radius
        antialiasing: true
      }
    }
    MultiEffect {
      anchors.fill: parent
      source: glowSrc
      maskEnabled: true
      maskInverted: true
      maskSource: glowHole
      maskThresholdMin: 0.5
      maskSpreadAtMin: 1.0
      opacity: pulseRing.opacity
    }
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

  // A LIT BUTTON PRESSED IS SIMPLY DARKENED (user, 2026-10-17): its own
  // resting color with black over it — no other color. The suite's gray
  // press (pressFill) on a vibrant, glowing button read as a gray slab.
  Rectangle {
    anchors.fill: parent
    radius: parent.radius
    color: Zenon.shadowRgb
    opacity: btnArea.pressed && btn.primary && btn.ready ? Zenon.pressShade : 0
    visible: opacity > 0
  }

  Text {
    id: btnText
    anchors.centerIn: parent
    text: btn.label
    // a lit button, darkened under the finger, keeps its word whole
    color: btn.ready ? btn.word : Zenon.muted
    opacity: btnArea.pressed && !btn.primary ? Zenon.pressDim : 1
    font.family: btn.glyph ? Zenon.glyphFace : Zenon.face
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
