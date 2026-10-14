// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┘┴└─┘
// https://github.com/kbuckleys/
//
// One transport button — previous, play/pause, next. Shared by the song
// toast's hover row and the now-playing panel, which drew the same three
// glyphs with the same hover behaviour twice.

import QtQuick
import QtQuick.Effects
import "."

Text {
  id: key

  property string glyph: ""
  property color ink: Zenon.white
  property int size: 20
  signal activated()
  // ── A KEY THAT WANTS NOTICING (2026-10-13) ──────────────────────────
  // `glow` 0..1: a blurred bloom of the glyph behind it, terminus' jobs
  // glyph's; `breathe` keeps it rising and falling while the key is there.
  // A glowing key stands at full strength, not dimmed until pointed at.
  property real glow: 0
  property bool breathe: false

  text: key.glyph
  color: key.ink
  font.family: Zenon.face
  font.weight: Font.Bold
  font.pixelSize: key.size
  // dim until pointed at, so a row of three reads as three targets rather
  // than three decorations
  opacity: keyArea.containsMouse || key.glow > 0 || key.breathe ? 1 : 0.55
  Behavior on opacity { NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }

  property real bloom: key.breathe ? 0.35 : key.glow
  SequentialAnimation on bloom {
    running: key.breathe && key.visible
    loops: Animation.Infinite
    NumberAnimation { to: 0.95; duration: 880; easing.type: Easing.InOutQuad }
    NumberAnimation { to: 0.35; duration: 880; easing.type: Easing.InOutQuad }
  }
  Item {
    z: -1
    anchors.centerIn: parent
    width: key.size * 2.2
    height: width
    opacity: key.bloom
    visible: opacity > 0.01
    scale: 1.0 + 0.4 * key.bloom
    layer.enabled: visible
    layer.effect: MultiEffect {
      blurEnabled: true
      blurMax: 48
      blur: 1.0
      brightness: 0.5
      saturation: 0.4
      autoPaddingEnabled: true
    }
    Text {
      anchors.centerIn: parent
      text: key.glyph
      color: key.ink
      font: key.font
    }
  }

  MouseArea {
    id: keyArea
    anchors.fill: parent
    // a glyph is a small target; grow the hit area past its ink
    anchors.margins: -6
    hoverEnabled: true
    onClicked: key.activated()
  }
}
