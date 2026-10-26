// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// One of the quick panel's four tiles: the thing's glyph, its name, what it
// is doing, and — where it has a list (networks, devices, connections) — a
// chevron that opens it.
//
// ONE ACCENT (user, 2026-10-26: "more zenworks"): a tile that is on is
// filled with the theme's accent and everything on it is onAccent, as the
// bar's special workspace and Chronos' today are; off, it is the panel's own
// faint wash. The four colours it had (cyan, blue, green, yellow) were a
// control centre's, not the suite's.
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
  // under the panel's keyboard cursor: the band (CursorBand) slides behind
  // the tiles, which hides it under a filled one, so a lit tile shows it by
  // going a step lighter
  property bool picked: false
  signal pressed()
  signal listed()

  // WHICH CORNERS ARE ROUND: only the grid's outer ones; where two tiles
  // meet, the corners are square (user, 2026-10-27). The popup says which
  // (HermesPopup.cornerRound): [topLeft, topRight, bottomLeft, bottomRight]
  property var round: [true, true, true, true]
  readonly property real rTL: t.round[0] ? Zenon.radiusCard : 0
  readonly property real rTR: t.round[1] ? Zenon.radiusCard : 0
  readonly property real rBL: t.round[2] ? Zenon.radiusCard : 0
  readonly property real rBR: t.round[3] ? Zenon.radiusCard : 0

  readonly property bool on: !!t.tile && t.tile.on
  readonly property bool ready: !!t.tile && t.tile.ready
  // what is drawn on the tile: onAccent on the fill, the panel's inks off it
  readonly property color ink: t.on ? Zenon.onAccent : t.ready ? Zenon.ink : Zenon.accentMuted
  readonly property color subInk: t.on ? Zenon.alpha(Zenon.onAccent, 0.72) : Zenon.accentMuted

  Rectangle {
    anchors.fill: parent
    topLeftRadius: t.rTL
    topRightRadius: t.rTR
    bottomLeftRadius: t.rBL
    bottomRightRadius: t.rBR
    color: t.on ? (tilePress.pressed ? Zenon.mix(Zenon.cyan, Zenon.onAccent, 0.18)
                   : t.picked ? Zenon.mix(Zenon.cyan, Zenon.white, 0.16) : Zenon.cyan)
      : tilePress.pressed ? Zenon.pressTile(false) : Zenon.wash(0.04)
    border.width: t.on ? 0 : 1
    border.color: Zenon.border
    Behavior on color { ColorAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }
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
    color: t.ink
    font.family: Zenon.glyphFace
    font.pixelSize: Zenon.px(18)
  }

  // ONE LINE (user, 2026-10-27: "these can be one liners"): the name, and
  // what it is at after it, quieter — "Wired  1 Gb/s"
  Row {
    anchors.left: disc.right
    anchors.leftMargin: 10
    anchors.right: chevron.visible ? chevron.left : parent.right
    anchors.rightMargin: 8
    anchors.verticalCenter: parent.verticalCenter
    spacing: 8
    Text {
      id: tileTitle
      anchors.baseline: tileSub.baseline
      width: Math.min(implicitWidth, parent.width)
      elide: Text.ElideRight
      text: t.tile ? t.tile.title : ""
      color: t.ink
      font.family: Zenon.face
      font.weight: Zenon.titleWeight
      font.pixelSize: Zenon.px(15)
    }
    Text {
      id: tileSub
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(0, parent.width - tileTitle.width - parent.spacing)
      elide: Text.ElideRight
      text: t.tile ? t.tile.sub : ""
      color: t.subInk
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
  ChosenFlash { id: tileFlash; topLeftRadius: t.rTL; topRightRadius: t.rTR; bottomLeftRadius: t.rBL; bottomRightRadius: t.rBR }

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
      color: t.on ? Zenon.alpha(Zenon.onAccent, 0.22) : Zenon.border
    }
    Text {
      anchors.centerIn: parent
      text: ""
      color: t.on ? (listPress.pressed ? Zenon.onAccent : t.subInk)
        : listPress.pressed ? Zenon.ink : Zenon.accentMuted
      font.family: Zenon.glyphFace
      font.pixelSize: Zenon.px(12)
    }
    MouseArea { id: listPress; anchors.fill: parent; onClicked: t.listed() }
  }
}
