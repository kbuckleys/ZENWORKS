// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A FIT, DRAWN: a screen 26 wide and what the picture does inside it —
// crop, fit, stretch, pad (center) or tile. The focus card's Fit switch wears
// it (Segments' `art`), and so does Oracle's Background › Fit (2026-10-27:
// one drawing for one setting, wherever it is set).
//
//   FitGlyph { mode: "pad"; ink: Zenon.accentMuted }

import QtQuick
import "../morpheus"

Item {
  id: glyph
  property string mode: "crop"
  property color ink: Zenon.accentMuted
  implicitWidth: 26
  implicitHeight: 16
  readonly property color fill: Qt.rgba(glyph.ink.r, glyph.ink.g, glyph.ink.b, 0.55)

  // crop: the picture runs past both sides, and what is cut is ghosted
  Rectangle {
    visible: glyph.mode === "crop"
    x: -6; y: 0; width: glyph.width + 12; height: glyph.height
    radius: 1
    color: "transparent"
    border.width: 1
    border.color: Qt.rgba(glyph.ink.r, glyph.ink.g, glyph.ink.b, 0.3)
  }
  Item {
    anchors.fill: parent
    clip: true
    Rectangle {
      visible: glyph.mode === "crop" || glyph.mode === "stretch"
      anchors.fill: parent
      color: glyph.fill
    }
    Rectangle {
      visible: glyph.mode === "fit"
      anchors.centerIn: parent
      width: parent.width - 2; height: 9
      color: glyph.fill
    }
    Rectangle {
      visible: glyph.mode === "pad"
      anchors.centerIn: parent
      width: 11; height: 7
      color: glyph.fill
    }
    Grid {
      visible: glyph.mode === "tile"
      anchors.fill: parent
      anchors.margins: 1
      columns: 3
      spacing: 1
      Repeater {
        model: 6
        Rectangle { width: 7.3; height: 6.5; color: glyph.fill }
      }
    }
  }
  Text {
    visible: glyph.mode === "stretch"
    anchors.centerIn: parent
    text: ""
    color: Zenon.black
    font.family: Zenon.face
    font.weight: Zenon.weight
    font.pixelSize: Zenon.px(10)
  }
  Rectangle {
    anchors.fill: parent
    radius: Zenon.rad(2)
    color: "transparent"
    border.width: 1
    border.color: glyph.ink
  }
}
