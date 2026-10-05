// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// One of nvim's floating windows, drawn as a card.
//
// WHOEVER OPENED IT. Hover (K), signature help, completion's documentation,
// a diagnostic's float: nvim decides that a float exists, where, and what is
// in it, and plato draws every one the same way — rows by EditorRow, on a
// card of its own. None of them needed code of its own here.
//
// Placed at nvim's cell position for it, on the editor's grid, and nudged
// back inside the editor if it would hang off an edge: nvim sizes floats to
// its grid, and the card's padding is plato's.

import QtQuick
import "../../morpheus"

Item {
  id: card

  required property var modelData
  required property var ed
  required property real cellW
  required property real cellH
  required property font face
  // where the editor's text column starts, and how far the card may reach
  required property real originX
  required property real areaW
  required property real areaH

  readonly property int pad: 6
  readonly property var f: card.modelData
  // a card with a title (a peek: its file and line) has a band for it
  readonly property string title: card.f.title || ""
  readonly property real headH: card.title !== "" ? 26 : 0

  width: card.f.width * card.cellW + card.pad * 2
  height: Math.max(1, card.f.height) * card.cellH + card.pad * 2 + card.headH
  x: Math.max(0, Math.min(card.areaW - card.width,
    card.originX + card.f.col * card.cellW - card.pad))
  y: Math.max(0, Math.min(card.areaH - card.height, card.f.row * card.cellH - card.pad))
  z: 10 + card.f.z

  Rectangle {
    anchors.fill: parent
    radius: Zenon.windowRadius
    color: Qt.rgba(0.05, 0.055, 0.065, 0.97)
    border.width: 1
    border.color: Zenon.border
  }

  Text {
    visible: card.title !== ""
    x: 12
    y: 0
    height: card.headH
    width: card.width - 24
    verticalAlignment: Text.AlignVCenter
    elide: Text.ElideMiddle
    font.family: Zenon.face
    font.pixelSize: 13
    color: Zenon.muted
    text: card.title + (card.f.cursor ? "    q close · \u21b5 open" : "")
  }
  Rectangle {
    visible: card.title !== ""
    y: card.headH
    x: 1
    width: card.width - 2
    height: 1
    color: Zenon.border
  }

  Item {
    x: card.pad
    y: card.pad + card.headH
    width: card.f.width * card.cellW
    height: card.f.height * card.cellH
    clip: true

    Repeater {
      model: card.f.rows
      Item {
        id: slot
        required property var modelData
        required property int index
        width: parent.width
        height: card.cellH
        EditorRow {
          ed: card.ed
          info: slot.modelData
          cellW: card.cellW
          cellH: card.cellH
          face: card.face
          gutterW: 0
          textX: 0
        }
        y: slot.index * card.cellH
      }
    }

    // the cursor, when it is in here (K K jumps into a hover)
    Rectangle {
      visible: card.f.cursor !== undefined && card.f.cursor !== null
      x: visible ? card.f.cursor.col * card.cellW : 0
      y: visible ? card.f.cursor.row * card.cellH : 0
      width: card.ed.modeName === "insert" ? 2 : card.cellW
      height: card.cellH
      color: Zenon.white
      opacity: 0.85
    }
  }
}
