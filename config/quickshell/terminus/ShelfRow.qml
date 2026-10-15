// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A SHELF IN A SIDEBAR — a glyph, a word and a count, one of a short column
// of places to look: alexandria's shelves (all, bookmarks, mono, yours…),
// delphi's pages (changes, history, branches…). The one here wears the
// window's highlight fill and lights its glyph cyan. No hover wash: a
// sidebar row does not light under the pointer, as terminus' do not
// (user, 2026-10-10).
//
//     ShelfRow { width: col.width; glyph: "…"; label: "Bookmarks"
//                count: "12"; here: win.shelf === "fav"; fill: win.hiFill
//                onClicked: win.setShelf("fav") }
//
// Out of AlexandriaWindow.qml (2026-10-10), where it was the shelves'
// inline delegate, when delphi wanted the same column.

import QtQuick
import "../morpheus"

Rectangle {
  id: shelf
  property string glyph: ""
  property string label: ""
  // what is on it: a number, or a word ("3 ahead"); empty, nothing
  property string count: ""
  property color countInk: Zenon.accentMuted
  property bool here: false
  property color fill: Zenon.alpha(Zenon.cyan, 0.12)
  // the glyph's way in from the left, and the count's from the right: more
  // when the row runs edge to edge (delphi's), so the words stay put
  property int indent: 10
  // and the count's alone, for rows indented by depth (clio's folders)
  property int countIndent: shelf.indent
  // a glyph's own colour at rest (a journal's, a sticky's); unset, muted
  property color glyphInk: "transparent"
  signal clicked()

  height: 30
  radius: Zenon.windowRadius
  color: shelf.here ? shelf.fill : Zenon.alpha(Zenon.cyan, 0)
  Behavior on color { ColorAnimation { duration: Zenon.fast } }
  Text {
    id: shelfGlyph
    anchors.left: parent.left
    anchors.leftMargin: shelf.indent
    anchors.verticalCenter: parent.verticalCenter
    width: 20
    text: shelf.glyph
    color: shelf.here ? Zenon.cyan : shelf.glyphInk.a > 0 ? shelf.glyphInk : Zenon.accentMuted
    font.family: Zenon.glyphFace
    font.pixelSize: Zenon.px(14)
  }
  Text {
    anchors.left: shelfGlyph.right
    anchors.leftMargin: 8
    anchors.right: shelfCount.left
    anchors.rightMargin: 8
    anchors.verticalCenter: parent.verticalCenter
    elide: Text.ElideRight
    text: shelf.label
    color: shelf.here ? Zenon.ink : Zenon.accentSoft
    font.family: Zenon.face
    font.weight: Zenon.weight
    font.pixelSize: Zenon.px(14)
  }
  Text {
    id: shelfCount
    anchors.right: parent.right
    anchors.rightMargin: shelf.countIndent
    anchors.verticalCenter: parent.verticalCenter
    text: shelf.count
    color: shelf.countInk
    font.family: Zenon.face
    font.weight: Zenon.weight
    font.features: { "tnum": 1 }
    font.pixelSize: Zenon.px(12)
  }
  MouseArea {
    anchors.fill: parent
    onClicked: shelf.clicked()
  }
}
