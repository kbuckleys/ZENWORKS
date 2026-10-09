// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE QUESTION ON A CONFIRMATION SHEET — what goes inside the Sheet, shared
// by terminus and picasso's viewer so the two ask alike. Picasso's look, the
// one the user preferred: the question in the card, its mark beside it, a
// muted line under it, the files it is about one to a line, and the answers
// at the bottom right.
//
//     Sheet { cardH: body.implicitHeight
//       ConfirmBody { id: body; width: parent.width
//         question: …; detail: …; items: [names]
//         choices: [{ label, ink }, …, { label: "Cancel", ink }]
//         onChose: (i) => … } }
//
// `choices` in order of preference — the first is the primary one, Cancel
// last — and drawn the other way round, so the way out is on the left and
// the verb at the far right, where a hand ends up. `pick` is the one Return
// takes (the holder moves it with the keys); a hover moves it too.
//
// `detail` is a line, or [key, line] when the line is about a key — "u",
// "brings it back" — and then the key is drawn on its cap (morpheus/KeyCap),
// so it reads as a key rather than as a stray letter at the start of a
// sentence.
//
// `headless`, for a holder whose bar already says the question (terminus,
// whose bar is the sheet's titlebar): no question in the card, and the
// line and the answers share one row — the line at the left, the answers at
// the right — under the files, if there are any.

import QtQuick
import "../morpheus"
import "terminus.js" as Terminus
import "../morpheus/icons.js" as Icons

Item {
  id: cb

  property string question: ""
  property string glyph: ""
  property color glyphInk: Zenon.white
  property var detail: ""
  property bool headless: false
  readonly property string detailKey: Array.isArray(cb.detail) ? String(cb.detail[0]) : ""
  readonly property string detailLine: Array.isArray(cb.detail) ? String(cb.detail[1])
    : String(cb.detail || "")
  readonly property bool hasDetail: cb.detailKey !== "" || cb.detailLine !== ""
  // what it is about, one a line — the first `maxItems`, then how many more.
  // A string is a line as it is (a partition and its size); a FILE is an
  // object with a name — terminus' own rows, or { name, isDir } — and is
  // drawn as a listing draws it: its glyph, in its colour, beside the name.
  property var items: []
  property int maxItems: 8
  property var choices: []
  property int pick: 0
  signal chose(int i)
  signal picked(int i)

  readonly property int shownItems: Math.min(cb.items.length, cb.maxItems)
  implicitHeight: cb.headless
    ? (cb.items.length > 0 ? 14 + list.height : 0) + 14 + answers.height + 14
    : 18 + head.height
      + (cb.hasDetail ? 8 + detailText.height : 0)
      + (cb.items.length > 0 ? 12 + list.height : 0)
      + 20 + 32 + 14
  // HEADLESS, AS WIDE AS ITS ONE ROW: the line and the answers side by side
  // with room between, so the holder can size the card to say it unclipped.
  // Off the line's NATURAL width (a Text's implicitWidth ignores the width
  // it is given), so asking for this never feeds back through the card.
  implicitWidth: 18 + (detailCap.visible ? detailCap.implicitWidth + detailText.spacing : 0)
    + lineText.implicitWidth + 24 + answers.implicitWidth + 14

  Row {
    id: head
    visible: !cb.headless
    x: 18
    y: 18
    width: cb.width - 36
    spacing: 10
    Text {
      id: mark
      visible: cb.glyph !== ""
      text: cb.glyph
      color: cb.glyphInk
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(16)
      anchors.verticalCenter: qText.lineCount === 1 ? qText.verticalCenter : undefined
    }
    Text {
      id: qText
      width: head.width - (mark.visible ? mark.width + head.spacing : 0)
      text: cb.question
      color: Zenon.white
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(16)
      wrapMode: Text.Wrap
      maximumLineCount: 2
      elide: Text.ElideRight
    }
  }

  Row {
    id: detailText
    visible: cb.hasDetail
    readonly property real room: cb.headless
      ? cb.width - 18 - 24 - answers.width - 14 : cb.width - 36
    x: 18
    // headless, on the answers' line, centred against them
    y: cb.headless ? answers.y + Math.round((answers.height - height) / 2)
      : head.y + head.height + 8
    spacing: 7
    KeyCap {
      id: detailCap
      anchors.verticalCenter: parent.verticalCenter
      label: cb.detailKey
      fontSize: 12
    }
    Text {
      id: lineText
      anchors.verticalCenter: parent.verticalCenter
      width: Math.min(implicitWidth, detailText.room
        - (detailCap.visible ? detailCap.width + detailText.spacing : 0))
      text: cb.detailLine
      color: Zenon.muted
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(13)
      wrapMode: cb.headless ? Text.NoWrap : Text.Wrap
      maximumLineCount: cb.headless ? 1 : 3
      elide: Text.ElideRight
    }
  }


  // the files, one a line, in a well of their own
  Rectangle {
    id: list
    visible: cb.items.length > 0
    x: 18
    y: cb.headless ? 14
      : (cb.hasDetail ? detailText.y + detailText.height : head.y + head.height) + 12
    width: cb.width - 36
    height: listCol.implicitHeight + 12
    radius: Zenon.windowRadius
    color: Zenon.wash(0.04)
    border.width: 1
    border.color: Zenon.border
    Column {
      id: listCol
      x: 12
      y: 6
      width: list.width - 24
      Repeater {
        model: cb.items.slice(0, cb.maxItems)
        delegate: Item {
          id: itemRow
          required property var modelData
          readonly property bool file: !!modelData && typeof modelData === "object"
          // the row's own glyph when it carries one (an enriched row), and
          // worked out from the name as terminus does when it does not
          readonly property string glyph: !itemRow.file ? ""
            : (modelData.glyph || Terminus.glyphOf(modelData, Icons))
          width: listCol.width
          height: 22
          Text {
            id: itemGlyph
            visible: itemRow.glyph !== ""
            width: visible ? 22 : 0
            height: parent.height
            verticalAlignment: Text.AlignVCenter
            text: itemRow.glyph
            color: !itemRow.file ? Zenon.white
              : Zenon[itemRow.modelData.inkKey || Terminus.inkKeyOf(itemRow.modelData)]
            font.family: Zenon.faceMono
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(14)
          }
          Text {
            x: itemGlyph.width
            width: parent.width - x
            height: parent.height
            verticalAlignment: Text.AlignVCenter
            text: itemRow.file ? String(itemRow.modelData.name) : String(itemRow.modelData)
            color: Zenon.white
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(14)
            elide: Text.ElideMiddle
          }
        }
      }
      Text {
        visible: cb.items.length > cb.maxItems
        width: listCol.width
        height: 22
        verticalAlignment: Text.AlignVCenter
        text: "and " + (cb.items.length - cb.maxItems) + " more"
        color: Zenon.muted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(13)
      }
    }
  }

  Row {
    id: answers
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: 14
    spacing: 8
    layoutDirection: Qt.RightToLeft
    Repeater {
      model: cb.choices
      delegate: DialogButton {
        required property var modelData
        required property int index
        label: modelData.label
        ink: modelData.ink
        primary: index === cb.pick
        onHovered: cb.picked(index)
        onClicked: cb.chose(index)
      }
    }
  }
}
