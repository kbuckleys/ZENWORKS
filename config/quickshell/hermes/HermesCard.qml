// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A card in Hermes' window: a heading with a glyph, something on its right
// (a switch, a button), and what it holds below.
//
//   HermesCard { glyph: …; title: "Wi-Fi"; trailing: [ Check {…} ]
//                HermesFact { … } }

import QtQuick
import "../morpheus"

Rectangle {
  id: card

  property string glyph: ""
  property string title: ""
  property string note: ""
  property color glyphInk: Zenon.cyan
  // what stands at the heading's right
  property alias trailing: trail.data
  // the body: whatever is declared inside the card
  default property alias content: body.data
  // padding inside the card, either side of the body
  property real inset: 18
  // the glyph and title as one line in the card's middle (a card that only
  // says something: hestia's "Everything is running as it should")
  property bool centered: false

  width: parent ? parent.width : 0
  // nothing below the heading: the card is the heading's own height, so its
  // line sits in the middle (it had 4px under it — user, 2026-10-21)
  height: head.height + body.implicitHeight + (body.implicitHeight > 0 ? 14 : 0)
  radius: Zenon.radiusCard
  color: Zenon.wash(0.04)
  border.width: 1
  border.color: Zenon.border

  Item {
    id: head
    width: parent.width
    height: 50
    Text {
      id: headGlyph
      x: card.centered ? Math.round((card.width - headGlyph.implicitWidth - 12 - headTitle.implicitWidth) / 2) : card.inset
      anchors.verticalCenter: parent.verticalCenter
      text: card.glyph
      color: card.glyphInk
      font.family: Zenon.glyphFace
      font.pixelSize: Zenon.px(18)
    }
    Text {
      textFormat: Text.PlainText
      id: headTitle
      anchors.left: headGlyph.right
      anchors.leftMargin: 12
      anchors.verticalCenter: parent.verticalCenter
      text: card.title
      color: Zenon.ink
      font.family: Zenon.face
      font.weight: Zenon.titleWeight
      font.pixelSize: Zenon.px(16)
    }
    Text {
      anchors.left: headTitle.right
      anchors.leftMargin: 10
      anchors.right: trail.left
      anchors.rightMargin: 12
      anchors.baseline: headTitle.baseline
      elide: Text.ElideRight
      text: card.note
      color: Zenon.accentMuted
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(13)
    }
    Row {
      id: trail
      anchors.right: parent.right
      anchors.rightMargin: card.inset - 4
      anchors.verticalCenter: parent.verticalCenter
      spacing: 8
    }
  }

  Column {
    id: body
    anchors.top: head.bottom
    x: 0
    width: parent.width
  }
}
