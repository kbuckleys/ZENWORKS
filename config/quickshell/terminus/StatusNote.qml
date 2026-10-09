// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE WHOLE OF A MESSAGE THE STATUS CHIP HAD TO CUT. The chip is capped at a
// share of the bar and elides; this hangs under it while the pointer is on
// it, the same text wrapped to a readable measure, in the chip's own tone. A
// click on the chip copies it (the holder's job — see statusChipMa).
//
//     StatusNote { parent: window.contentItem; z: 60
//       anchorItem: chip; text: …; bad: …; open: hovered && cut }
//
// Placed from the chip each time it opens, right edges aligned and kept
// inside the window — the chip sits at the right of the bar.

import QtQuick
import "../morpheus"

Item {
  id: note

  property Item anchorItem: null
  property string text: ""
  property bool bad: false
  property bool open: false
  readonly property color tone: note.bad ? Zenon.red : Zenon.sand

  width: Math.min(460, (parent ? parent.width : 460) - 24)
  height: card.height
  visible: card.opacity > 0.01

  function place() {
    if (!note.anchorItem || !note.parent) return;
    const p = note.anchorItem.mapToItem(note.parent, note.anchorItem.width, note.anchorItem.height);
    note.x = Math.max(12, Math.min(p.x - note.width, note.parent.width - note.width - 12));
    note.y = p.y + 6;
  }
  onOpenChanged: if (note.open) note.place()

  Rectangle {
    id: card
    width: note.width
    height: words.implicitHeight + 20
    radius: Zenon.windowRadius
    color: Zenon.black
    border.width: 1
    border.color: Qt.rgba(note.tone.r, note.tone.g, note.tone.b, 0.45)
    opacity: note.open ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }
    transform: Translate {
      y: note.open ? 0 : -4
      Behavior on y { NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }
    }

    Rectangle {
      anchors.fill: parent
      radius: parent.radius
      color: Qt.rgba(note.tone.r, note.tone.g, note.tone.b, 0.08)
    }

    Text {
      id: words
      x: 12
      y: 10
      width: card.width - 24
      text: note.text
      wrapMode: Text.WrapAtWordBoundaryOrAnywhere
      color: note.tone
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(13)
      lineHeight: 1.15
    }
  }
}
