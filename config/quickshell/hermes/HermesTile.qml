// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// One of the quick panel's four tiles: the thing's glyph in its own colour
// while it is on, its name, what it is doing, and — where it has a list
// (networks, devices, connections) — a chevron that opens it.
//
//   tile: { id, glyph, title, sub, on, ready, list }
//
// The tile is the switch (pressed); the chevron is the list (listed). A
// tile whose piece is not set up is dimmed and says where to set it up.

import QtQuick
import "../morpheus"

Item {
  id: t

  property var tile: null
  signal pressed()
  signal listed()

  readonly property bool on: !!t.tile && t.tile.on
  readonly property bool ready: !!t.tile && t.tile.ready
  // each thing in its own colour, as the bar's meters are told apart
  readonly property color ink: !t.tile ? Zenon.cyan
    : ({ net: Zenon.cyan, bt: Zenon.blue, vpn: Zenon.green, night: Zenon.yellow })[t.tile.id] || Zenon.cyan

  Rectangle {
    anchors.fill: parent
    radius: Zenon.radiusCard
    color: tilePress.pressed ? Zenon.pressTile(t.on) : t.on ? Zenon.alpha(t.ink, 0.14) : Zenon.wash(0.04)
    border.width: 1
    border.color: t.on ? Zenon.alpha(t.ink, 0.45) : Zenon.border
  }

  // the glyph bare, in the tile's colour while on (user, 2026-10-20: no
  // circle chips around them)
  Text {
    id: disc
    x: 16
    width: 30
    anchors.verticalCenter: parent.verticalCenter
    horizontalAlignment: Text.AlignHCenter
    text: t.tile ? t.tile.glyph : ""
    color: t.on ? t.ink : t.ready ? Zenon.ink : Zenon.accentMuted
    font.family: Zenon.glyphFace
    font.pixelSize: Zenon.px(22)
  }

  Column {
    anchors.left: disc.right
    anchors.leftMargin: 11
    anchors.right: chevron.visible ? chevron.left : parent.right
    anchors.rightMargin: 8
    anchors.verticalCenter: parent.verticalCenter
    spacing: 1
    Text {
      width: parent.width
      elide: Text.ElideRight
      text: t.tile ? t.tile.title : ""
      color: t.ready ? Zenon.ink : Zenon.accentMuted
      font.family: Zenon.face
      font.weight: Zenon.titleWeight
      font.pixelSize: Zenon.px(15)
    }
    Text {
      width: parent.width
      elide: Text.ElideRight
      text: t.tile ? t.tile.sub : ""
      color: t.on ? t.ink : Zenon.accentMuted
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(13)
    }
  }

  MouseArea {
    id: tilePress
    anchors.fill: parent
    onClicked: t.pressed()
  }
  // the grids' flash (morpheus/ChosenFlash), in the tile's own corners:
  // the popup fires it, then the switch is thrown
  readonly property alias flash: tileFlash
  ChosenFlash { id: tileFlash; radius: Zenon.radiusCard }

  // the list, past the tile's own switch: on top of it, so it wins
  Item {
    id: chevron
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: 34
    visible: !!t.tile && t.tile.list !== ""
    Rectangle {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: 1
      height: parent.height - 24
      color: Zenon.border
    }
    Text {
      anchors.centerIn: parent
      text: ""
      color: listPress.pressed ? Zenon.ink : Zenon.accentMuted
      font.family: Zenon.glyphFace
      font.pixelSize: Zenon.px(12)
    }
    MouseArea { id: listPress; anchors.fill: parent; onClicked: t.listed() }
  }
}
