// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// HIGHLIGHTS — every highlighted phrase in the notebook in one place, each on
// its own marker's color with the note it is in under it; a click opens the
// note at the phrase (win.openAt). A filter narrows them, and a color too.
// The newest note's first. Locked notes keep theirs to themselves.

import QtQuick
import "../morpheus"
import "notes.js" as N

Item {
  id: hb
  property var win: null
  property bool shown: false
  signal closed()
  property string filter: ""
  property string marker: ""
  readonly property var all: hb.shown && hb.win ? N.highlights(hb.win.mgr.notes) : []
  readonly property var rows: hb.all.filter((h) => (hb.marker === "" || h.marker === hb.marker)
    && (hb.filter === "" || (h.text + " " + h.title).toLowerCase().indexOf(hb.filter.toLowerCase()) >= 0))
  onShownChanged: if (hb.shown) { hb.filter = ""; hb.marker = ""; }

  Row {
    x: 20
    y: 16
    spacing: 12
    Text { anchors.verticalCenter: parent.verticalCenter; text: "\u{F0652}"; color: Zenon.sand; font.family: Zenon.glyphFace; font.pixelSize: Zenon.px(18) }
    Text { anchors.verticalCenter: parent.verticalCenter; text: "Highlights"; color: Zenon.ink; font.family: Zenon.face; font.weight: Font.Bold; font.pixelSize: Zenon.px(19) }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: hb.all.length === 0 ? "" : hb.all.length + (hb.all.length === 1 ? " phrase" : " phrases")
      color: Zenon.accentMuted
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(13)
    }
  }
  DialogButton { anchors.right: parent.right; anchors.rightMargin: 20; y: 16; label: "Close"; onClicked: hb.closed() }

  // the colors there are, to narrow by
  Row {
    id: inks
    x: 20
    y: 58
    spacing: 6
    Repeater {
      model: [""].concat(N.MARKERS.filter((m) => hb.all.some((h) => h.marker === m)))
      delegate: Rectangle {
        required property string modelData
        readonly property bool on: hb.marker === modelData
        width: modelData === "" ? allWord.implicitWidth + 20 : 26
        height: 26
        radius: height / 2
        color: modelData === "" ? (on ? Zenon.wash(0.14) : Zenon.wash(0.05)) : Zenon.alpha(Zenon[modelData], on ? 0.75 : 0.35)
        border.width: on ? 2 : 1
        border.color: on ? Zenon.ink : Zenon.border
        Text { id: allWord; visible: modelData === ""; anchors.centerIn: parent; text: "All"; color: Zenon.ink; font.family: Zenon.face; font.weight: Font.DemiBold; font.pixelSize: Zenon.px(12) }
        MouseArea { anchors.fill: parent; onClicked: hb.marker = modelData }
      }
    }
  }
  Rectangle {
    anchors.right: parent.right
    anchors.rightMargin: 20
    y: 56
    width: 220
    height: 30
    radius: Zenon.windowRadius
    color: Zenon.wash(0.06)
    border.width: 1
    border.color: Zenon.border
    TextInput {
      id: field
      anchors.fill: parent
      anchors.leftMargin: 10
      anchors.rightMargin: 10
      verticalAlignment: TextInput.AlignVCenter
      clip: true
      color: Zenon.ink
      font.family: Zenon.face
      font.pixelSize: Zenon.px(14)
      cursorDelegate: Caret { field: field }
      onTextChanged: hb.filter = text
      Text { visible: field.text === ""; anchors.verticalCenter: parent.verticalCenter; text: "Filter"; color: Zenon.accentMuted; font: field.font }
    }
  }

  Flickable {
    id: flick
    anchors.fill: parent
    anchors.topMargin: 100
    anchors.leftMargin: 18
    anchors.rightMargin: 18
    anchors.bottomMargin: 18
    contentHeight: col.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    Column {
      id: col
      width: flick.width
      spacing: 8
      Text {
        visible: hb.rows.length === 0
        topPadding: 30
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: hb.all.length === 0 ? "Nothing highlighted yet — select words and choose a highlight from the color menu" : "Nothing matches \u201C" + hb.filter + "\u201D"
        color: Zenon.accentMuted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(14)
      }
      Repeater {
        model: hb.rows
        delegate: Rectangle {
          id: card
          required property var modelData
          width: col.width
          height: words.implicitHeight + where.implicitHeight + 26
          radius: Zenon.windowRadius
          color: press.pressed ? Zenon.pressWash(0.12) : Zenon.wash(0.04)
          border.width: 1
          border.color: Zenon.border
          Rectangle { x: 0; y: 8; width: 4; height: parent.height - 16; radius: 2; color: Zenon[card.modelData.marker] || Zenon.sand }
          Text {
            id: words
            x: 18
            y: 10
            width: parent.width - 32
            wrapMode: Text.Wrap
            maximumLineCount: 4
            elide: Text.ElideRight
            text: "“" + card.modelData.text + "”"
            color: Zenon.ink
            font.family: Zenon.face
            font.weight: Font.DemiBold
            font.pixelSize: Zenon.px(15)
          }
          Text {
            id: where
            x: 18
            anchors.top: words.bottom
            anchors.topMargin: 4
            width: parent.width - 32
            elide: Text.ElideRight
            text: (card.modelData.kind === "entry" ? "\u{F0B64}  " : "\u{F09ED}  ") + card.modelData.title
              + "  ·  " + N.dateShort(card.modelData.modified, Date.now())
            color: Zenon.accentMuted
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(12)
          }
          MouseArea {
            id: press
            anchors.fill: parent
            hoverEnabled: true
            onClicked: { hb.closed(); hb.win.openAt(card.modelData.id, card.modelData.text); }
          }
        }
      }
    }
  }
  ElasticScroll { anchors.fill: flick; view: flick }
}
