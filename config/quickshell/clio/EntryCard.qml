// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ONE JOURNAL ENTRY ON THE TIMELINE — its pictures across the top (one
// large, or a row of them), its title and first lines, then its day, how
// it felt, and its bookmark: Apple's card. Clicked, it opens in the pane;
// right clicked, the entry's menu.

import QtQuick
import QtQuick.Effects
import Quickshell.Widgets
import "../morpheus"
import "../terminus"
import "notes.js" as N

Rectangle {
  id: card
  property var win: null
  property var note: null
  property bool here: false
  readonly property var d: card.note && card.note.d ? card.note.d : ({ title: "", preview: "", images: [], words: 0 })
  readonly property var pics: card.note && !card.note.sealed ? card.d.images.slice(0, 4) : []
  readonly property var mood: card.note && card.note.mood ? N.moodOf(card.note.mood.v) : null
  // the journal's privacy (Settings, "Blur previews"): the words and
  // pictures frosted until the pointer is on the card or it is the one open
  readonly property bool veiled: !!card.win && card.win.mgr.journalBlur && !card.here && !cardHover.hovered
  HoverHandler { id: cardHover }

  // a page's air: a little more round the words than a list row has
  height: col.implicitHeight + 32
  radius: Zenon.windowRadius + 4
  color: card.here ? Zenon.alpha(Zenon.cyan, 0.10) : Zenon.wash(0.04)
  border.width: card.here ? 2 : 1
  border.color: card.here ? Zenon.alpha(Zenon.cyan, 0.55) : Zenon.border

  // the mood, as a thin edge down the card's left: a journal scrolled
  // through reads as its weather
  Rectangle {
    visible: !!card.mood
    x: 5
    y: 14
    width: 3
    height: parent.height - 28
    radius: 1.5
    color: card.mood ? Zenon.alpha(Zenon[card.mood.ink] || Zenon.accentMuted, 0.85) : "transparent"
  }

  Column {
    id: col
    x: 16
    y: 16
    width: parent.width - 32
    spacing: 10

    // the pictures: one wide, or up to four in a row
    Row {
      visible: card.pics.length > 0
      width: parent.width
      spacing: 4
      layer.enabled: card.veiled
      layer.effect: MultiEffect { blurEnabled: true; blur: 1; blurMax: 40 }
      Repeater {
        model: card.pics
        delegate: ClippingRectangle {
          id: frame
          required property string modelData
          width: (col.width - 4 * (card.pics.length - 1)) / card.pics.length
          // one alone at its own shape (a wide banner is not cropped to
          // its middle), within reason; several as tiles
          height: card.pics.length > 1 ? Math.round(width * 0.9)
            : shot.implicitWidth > 0 ? Math.round(Math.max(60, Math.min(col.width * 0.62, width * shot.implicitHeight / shot.implicitWidth)))
            : Math.round(col.width * 0.5)
          radius: Zenon.windowRadius
          color: Zenon.wash(0.05)
          // (`frame`, not parent: inside a ClippingRectangle the parent is
          // its contentItem, which has no modelData)
          Image {
            id: shot
            anchors.fill: parent
            source: card.win ? "file://" + card.win.mgr.base + "/" + frame.modelData : ""
            sourceSize.width: 420
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            // faded in as it arrives, not popped in (2026-10-17)
            opacity: status === Image.Ready ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Zenon.ms(180); easing.type: Easing.OutCubic } }
          }
        }
      }
    }
    Text {
      visible: text !== ""
      width: parent.width
      elide: Text.ElideRight
      text: card.note ? (card.note.sealed ? "  Locked entry" : card.d.title) : ""
      color: Zenon.ink
      font.family: card.note && !card.note.sealed && card.win ? card.win.mgr.faceFor(true) : Zenon.face
      font.weight: Font.Bold
      font.pixelSize: Zenon.px(16)
    }
    Text {
      visible: text !== ""
      width: parent.width
      wrapMode: Text.Wrap
      maximumLineCount: 4
      elide: Text.ElideRight
      text: card.note && !card.note.sealed ? card.d.preview : ""
      layer.enabled: card.veiled
      layer.effect: MultiEffect { blurEnabled: true; blur: 1; blurMax: 20 }
      color: Zenon.accentSoft
      font.family: card.win ? card.win.mgr.faceFor(true) : Zenon.face
      // the second row bold, as in the notes list (user, 2026-10-17)
      font.weight: Font.Bold
      font.pixelSize: Zenon.px(14)
      lineHeight: 1.08
    }
    // when it was last edited, in full, on every card as a list row has it
    // (NoteRowBody; user, 2026-10-17)
    Text {
      visible: !!card.note && !!card.note.modified
      width: parent.width
      elide: Text.ElideRight
      text: visible ? N.dateTime(card.note.modified) : ""
      color: Zenon.accentMuted
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(12)
    }
    ContentMarks {
      visible: items.length > 0 && !!card.note && !card.note.sealed
      d: card.d
      shownPics: card.pics.length
    }
    Text {
      visible: !!card.note && card.note.prompt !== "" && !card.note.sealed
      width: parent.width
      elide: Text.ElideRight
      text: card.note ? "\u{F0336}  " + card.note.prompt : ""
      color: Zenon.magenta
      opacity: 0.85
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.italic: true
      font.pixelSize: Zenon.px(12)
    }
    Item {
      width: parent.width
      height: 22
      Text {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: card.note ? N.DAYS[new Date(card.note.date).getDay()] + ", " + new Date(card.note.date).getDate() + " "
          + N.MONTHS[new Date(card.note.date).getMonth()].slice(0, 3) : ""
        color: Zenon.accentMuted
        font.family: Zenon.face
        font.weight: Font.DemiBold
        font.pixelSize: Zenon.px(12)
      }
      Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        Rectangle {
          visible: !!card.mood
          anchors.verticalCenter: parent.verticalCenter
          width: moodWord.implicitWidth + 16
          height: 22
          radius: height / 2
          color: card.mood ? Zenon.alpha(Zenon[card.mood.ink] || Zenon.accentMuted, 0.16) : "transparent"
          Text {
            id: moodWord
            anchors.centerIn: parent
            text: card.mood ? card.mood.label : ""
            color: card.mood ? Zenon[card.mood.ink] || Zenon.accentMuted : Zenon.accentMuted
            font.family: Zenon.face
            font.weight: Font.DemiBold
            font.pixelSize: Zenon.px(11)
          }
        }
        Text {
          visible: !!card.note && !!card.note.bookmark
          anchors.verticalCenter: parent.verticalCenter
          text: ""
          color: Zenon.sand
          font.family: Zenon.glyphFace
          font.pixelSize: Zenon.px(13)
        }
      }
    }
  }
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    // carried to the Trash, or to another journal (win.carry)
    property point at
    property bool moving: false
    onPressed: (m) => { at = Qt.point(m.x, m.y); moving = false; }
    onPositionChanged: (m) => {
      if (!pressed || m.buttons !== Qt.LeftButton || !card.note) return;
      if (!moving && Math.abs(m.x - at.x) + Math.abs(m.y - at.y) > 8) moving = true;
      if (moving) card.win.carry(card.note, this, m);
    }
    onReleased: (m) => { if (moving) card.win.land(this, m); moving = false; }
    onClicked: (m) => {
      if (!card.note || moving) return;
      if (m.button === Qt.RightButton) { const p = mapToItem(card.win.stageItem, m.x, m.y); card.win.noteMenu(card.note, p.x, p.y); return; }
      card.win.choose(card.note.id);
      card.win.refocus();
    }
    onDoubleClicked: { card.win.choose(card.note.id); card.win.paneRef.focusEditor(false); }
  }
  HeldRing { anchors.fill: parent; radius: parent.radius; on: !!card.note && card.win.menuRef.isOpen && card.win.menuHeld === card.note.id }
}
