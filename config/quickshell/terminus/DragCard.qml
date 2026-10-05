// What the pointer carries while something is dragged out of the suite: a
// small card with the thing's glyph (or a thumbnail of it), its name, and a
// count when there is more than one. One card for terminus, artemis, folio
// and picasso, so a drag looks the same wherever it starts.
//
// A platform drag has no picture unless one is given to it: Drag.imageSource
// takes a URL, and grabToImage renders a live item into one. So the card is
// drawn for real — off to one side and fully transparent, but in the scene,
// because grabToImage renders an item's subtree and an item that is
// `visible: false` is not in the graph to render.
//
// Use: fill the properties in, then picture(then) — and start the drag from
// inside `then`, with the url it is handed. Drag.imageSource is read when
// Drag.active turns true and grabToImage answers a frame later, so the other
// way round every drag carries the previous one's picture.
import QtQuick
import Quickshell.Widgets
import "../morpheus"

Item {
  id: card

  property string label: ""
  property string glyph: ""
  property color ink: Zenon.white
  // above 1, rides along as a badge — "1" beside a filename is noise
  property int count: 1
  // a picture of the thing, in the glyph's place, when there is one
  property string thumb: ""

  // Held so the grab result is not collected: Drag.imageSource points at a
  // url that lives exactly as long as this object does.
  property var grab: null

  function picture(then) {
    // A failed grab is not a reason to refuse the drag; it just goes without
    // a picture.
    if (!card.grabToImage((res) => { card.grab = res; then(res.url); }))
      then("");
  }

  opacity: 0
  z: -100
  x: -4000
  height: 38

  // SIZED FROM THE TEXT, NOT FROM A LAID-OUT ROW.
  //
  // grabToImage sizes its target from the item's width at the moment it is
  // CALLED, and the caller fills the labels in in that same tick. A Row sets
  // its own width during polish, at the end of the frame — so the first drag
  // of a session would carry a card cut to the width it had before the labels
  // existed. implicitWidth on a Text is re-evaluated synchronously, so by the
  // time grabToImage looks the width is right; which is also why the children
  // are anchored rather than positioned.
  readonly property real pad: 12
  readonly property bool pictured: card.thumb !== ""
  readonly property real lead: card.pictured ? thumbBox.width : glyphText.implicitWidth
  width: (card.pictured ? 5 : card.pad) + card.lead
    + (card.lead > 0 ? 8 : 0) + labelText.implicitWidth + card.pad
    + (card.count > 1 ? 8 + badge.width : 0)

  Rectangle {
    anchors.fill: parent
    radius: 6
    color: Zenon.layerBg
    border.width: 1
    border.color: Zenon.border
  }

  Text {
    id: glyphText
    visible: !card.pictured
    anchors.left: parent.left
    anchors.leftMargin: card.pad
    anchors.verticalCenter: parent.verticalCenter
    text: card.glyph
    color: card.ink
    font.family: Zenon.faceFixed
    font.pixelSize: 16
  }

  // Inset by the same 5px all round, so the picture sits in the card's
  // corner the way the card sits round it. Synchronous: it has to be drawn
  // in the one frame the grab looks at.
  ClippingRectangle {
    id: thumbBox
    visible: card.pictured
    anchors.left: parent.left
    anchors.leftMargin: 5
    anchors.verticalCenter: parent.verticalCenter
    width: card.height - 10
    height: card.height - 10
    radius: 3
    color: Zenon.black
    Image {
      anchors.fill: parent
      source: card.thumb
      asynchronous: false
      cache: false
      fillMode: Image.PreserveAspectCrop
      sourceSize.width: 2 * thumbBox.width
      sourceSize.height: 2 * thumbBox.height
    }
  }

  Text {
    id: labelText
    anchors.left: parent.left
    anchors.leftMargin: (card.pictured ? 5 : card.pad) + card.lead + (card.lead > 0 ? 8 : 0)
    anchors.verticalCenter: parent.verticalCenter
    text: card.label
    color: Zenon.white
    font.family: Zenon.face
    font.pixelSize: 15
  }

  Rectangle {
    id: badge
    anchors.left: labelText.right
    anchors.leftMargin: 8
    anchors.verticalCenter: parent.verticalCenter
    visible: card.count > 1
    width: countText.implicitWidth + 12
    height: 20
    radius: 10
    color: Zenon.cyan

    Text {
      id: countText
      anchors.centerIn: parent
      text: card.count
      color: Zenon.black
      font.family: Zenon.face
      font.pixelSize: 13
      font.weight: Font.Medium
    }
  }
}
