// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// Plato's cards are TERMINUS' SHEETS: morpheus' Sheet, hanging from the tab
// strip (or the window's top edge, with no strip), dropping in and going back
// the way it came — with terminus' scrim behind it, its shield that takes a
// click away as Esc, and its footer of key chips under a hairline. The
// picker, the leader menu and the plugin manager are each one of these, so
// a card in plato is the same object as a card in terminus.
//
//     PlatoSheet { shown: …; fromTop: …; cardW: 620; cardH: rows * 30 + 12
//                  hints: [["↑↓", "move"], ["esc", "close"]]; onDismissed: … }
//
// cardH is what the CONTENT wants; the footer is added to it here.
//
// fromBottom turns it over (morpheus Sheet's own switch): the card rises out
// of the top of the status bar, `toBottom` px up from the window's foot —
// where the leader menu and the key hints live, by the keys being typed.

import QtQuick
import "../../morpheus"

Item {
  id: layer
  // what the card frosts over (see morpheus/Sheet): the editor, from the
  // window; null for the plain black card
  property Item backdrop: null
  // where its card is and how far in, for the bar it splices out of
  readonly property real cardInk: sheet.cardInk
  readonly property real drawnX: sheet.drawnX
  readonly property real drawnW: sheet.drawnW
  anchors.fill: parent

  property bool shown: false
  property real fromTop: 0
  property bool fromBottom: false
  property real toBottom: 0
  // a modal sheet dims the window and takes a click away as `dismissed`;
  // one that is not (the key hints) is only the card, and every click and
  // key goes on past it as if it were not there
  property bool modal: true
  property real cardW: 620
  property real cardH: 200
  // the footer: a line of text (the query, a state), then key chips
  property string footText: ""
  property color footInk: Zenon.muted
  property var hints: []
  // no footer at all (the leader menu): no hairline, no chips
  property bool foot: true
  readonly property real footH: layer.foot ? 34 : 0
  // HOW MANY COLUMNS FIT. A sheet of columns (the leader menu, the key
  // hints) asks for `want` of them `colW` wide; a window too narrow for
  // that many gets fewer, down to one — the card's own 20 of padding and
  // the 40 Sheet keeps clear of the window's sides taken off first.
  function fitColumns(want, colW) {
    return Math.max(1, Math.min(want, Math.floor((layer.width - 60) / colW)));
  }
  // the rows of the sheet's lists, as terminus' palette has them
  readonly property int rowH: 30
  default property alias body: content.data

  // Which end it comes from, changed WITHOUT the card travelling between
  // them (Sheet.noGlide): `set` makes the change (a picker opened from the
  // status line after one opened from the tab strip).
  function setEnd(set) {
    sheet.noGlide = true;
    set();
    sheet.noGlide = false;
  }

  // a click away from the card: whoever owns the sheet decides what that is
  signal dismissed()

  z: 300
  visible: layer.shown || sheet.cardInk > 0.01

  Rectangle {
    anchors.fill: parent
    anchors.topMargin: layer.fromTop
    anchors.bottomMargin: layer.fromBottom ? layer.toBottom : 0
    color: Zenon.darken(0.32)
    visible: layer.modal
    opacity: sheet.cardInk
  }
  InputShield {
    visible: layer.shown && layer.modal
    keepTop: layer.fromTop
    onClicked: layer.dismissed()
  }

  Sheet {
    backdrop: layer.backdrop   // frosted over it — see morpheus/Sheet
    // over code, not pictures: lines of text blurred as far as terminus'
    // thumbnails are, under as much black, came out as a plain black card.
    // Frosted properly and stacked (Sheet.gain), so the code reads as soft
    // streaks of its colours — blurred only a little it stayed legible.
    // As dark as terminus' sheets: Sheet's own glass (0.8), not a lighter
    // one of plato's (the user asked, 2026-10-08)
    blur: 30
    gain: 3
    id: sheet
    shown: layer.shown
    fromTop: layer.fromTop
    fromBottom: layer.fromBottom
    toBottom: layer.toBottom
    cardW: layer.cardW
    cardH: layer.cardH + layer.footH + (layer.foot ? 1 : 0)

    Item {
      id: content
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.bottom: layer.foot ? rule.top : parent.bottom
    }
    Rectangle {
      id: rule
      visible: layer.foot
      anchors.bottom: foot.top
      anchors.left: parent.left
      anchors.right: parent.right
      height: 1
      color: Zenon.border
    }
    Item {
      id: foot
      visible: layer.foot
      anchors.bottom: parent.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      height: layer.footH
      Row {
        anchors.centerIn: parent
        spacing: 12
        Text {
          visible: text !== ""
          anchors.verticalCenter: parent.verticalCenter
          rightPadding: 2
          text: layer.footText
          color: layer.footInk
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: 13
          elide: Text.ElideRight
          width: Math.min(implicitWidth, layer.cardW * 0.5)
        }
        Repeater {
          model: layer.hints
          delegate: Row {
            id: pair
            required property var modelData
            spacing: 5
            KeyCap {
              anchors.verticalCenter: parent.verticalCenter
              label: pair.modelData[0]
              fontSize: 11
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: pair.modelData[1]
              color: Zenon.muted
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: 13
            }
          }
        }
      }
    }
  }
}
