// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A BAR BUTTON AS A CHIP (user, 2026-10-17) — the view switch's pill
// (Segments) for a glyph that is pressed rather than chosen: the same faint
// wash, the same lit fill when its thing is on, and pressed, the darkened
// shade and dimmed ink every switch in the suite presses with. One or more
// parts in one pill, a hairline between them (back | forward).
//
//     BarChip { parts: [{ glyph: "", lit: menuOpen }]
//               onClicked: (i) => … }
//
// A part may say `ok: false` — drawn faint and not answering — `size`
// for its glyph's pixel size, and `held: true` to stay pressed for as long
// as what it opened is open (the hamburger's menu, the sort menu).
// `heavy: true` thickens a glyph the font only has in one weight (back |
// forward's chevrons): a hairline outline in its own ink, since the symbol
// face ignores font.weight.

import QtQuick
import "../morpheus"

Item {
  id: chip
  property var parts: []
  property real textSize: Zenon.px(13)
  property real partW: 30
  signal clicked(int index)

  implicitWidth: rep.count * chip.partW + 2
  implicitHeight: Math.round(chip.textSize * 2.1)
  width: implicitWidth
  height: implicitHeight

  Rectangle {
    anchors.fill: parent
    radius: Zenon.windowRadius
    color: Zenon.wash(0.04)
  }

  Row {
    x: 1
    y: 1
    height: chip.height - 2
    Repeater {
      id: rep
      model: chip.parts
      delegate: Item {
        id: part
        required property var modelData
        required property int index
        readonly property bool ok: part.modelData.ok !== false
        readonly property bool lit: !!part.modelData.lit
        readonly property bool down: (press.pressed || !!part.modelData.held) && part.ok
        width: chip.partW
        height: parent.height
        Rectangle {
          visible: part.index > 0
          width: 1
          height: parent.height - 10
          anchors.verticalCenter: parent.verticalCenter
          color: Zenon.border
        }
        // lit: its thing is on (the sidebar out, the menu open, split)
        Rectangle {
          x: 1
          y: 2
          width: parent.width - 2
          height: parent.height - 4
          radius: Zenon.rad(3)
          color: Zenon.alpha(Zenon.cyan, 0.16)
          opacity: part.lit ? 1 : 0
          visible: opacity > 0.01
          Behavior on opacity { NumberAnimation { duration: Zenon.fast } }
        }
        // PRESSED, DARKENED, as Segments and ClearChip are
        Rectangle {
          x: 1
          y: 2
          width: parent.width - 2
          height: parent.height - 4
          radius: Zenon.rad(3)
          color: Zenon.pressFill
          visible: part.down
        }
        Text {
          anchors.centerIn: parent
          text: part.modelData.glyph || ""
          color: part.lit ? Zenon.cyan
            : (Zenon.accentMuted)
          opacity: !part.ok ? 0.35 : part.down ? Zenon.pressDim : 1
          Behavior on color { ColorAnimation { duration: Zenon.fast } }
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: part.modelData.size || Zenon.px(15)
          style: part.modelData.heavy ? Text.Outline : Text.Normal
          styleColor: color
        }
        HoverHandler { id: hov; enabled: part.ok }
        MouseArea {
          id: press
          anchors.fill: parent
          enabled: part.ok
          onClicked: chip.clicked(part.index)
        }
      }
    }
  }
}
