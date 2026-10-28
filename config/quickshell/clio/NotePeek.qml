// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A NOTE, PEEKED AT — the suite's speech bubble (terminus/Bubble) over
// something that stands for a note: a Recent row in the sidebar, a link to
// a note in the editor. Its title, where it lives and when, its first
// lines, its first picture; nothing of a locked one but its name.
//
//     NotePeek { win: win; target: row; note: n; shown: … }
//
// Shown a moment after the pointer arrives (the holder's wait), gone as
// it leaves.

import QtQuick
import Quickshell.Widgets
import "../morpheus"
import "../terminus"
import "notes.js" as N

Bubble {
  id: peek
  property var win: null
  property var note: null
  readonly property var mgr: peek.win ? peek.win.mgr : null
  window: peek.win
  cardWidth: 340
  readonly property bool closed: !!peek.note && (!!peek.note.sealed
    || peek.note.kind === "entry" && !!peek.win && peek.win.journalLocked(peek.note.journal))
  readonly property var d: peek.note ? (peek.note.d || N.derive(peek.note)) : ({ title: "", preview: "", images: [] })

  Row {
    spacing: 8
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: peek.closed ? "" : peek.note && peek.note.kind === "entry" ? "\u{F0B64}" : "\u{F09ED}"
      color: peek.closed ? Zenon.yellow : Zenon.cyan
      font.family: Zenon.glyphFace
      font.pixelSize: Zenon.px(14)
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: Math.min(implicitWidth, 280)
      elide: Text.ElideRight
      text: !peek.note ? "" : peek.note.kind === "entry" ? N.titleOf(peek.note, N.dateLong(peek.note.date)) : N.titleOf(peek.note)
      color: Zenon.ink
      font.family: Zenon.face
      font.weight: Font.Bold
      font.pixelSize: Zenon.px(15)
    }
  }
  Text {
    text: !peek.note || !peek.win ? ""
      : (peek.note.kind === "entry" ? (peek.mgr.journalOf(peek.note.journal) || {}).name || "Journal" : peek.win.folderName(peek.note.folder))
        + "  ·  " + (peek.note.kind === "entry" ? N.dateLong(peek.note.date) : "Edited " + N.dateShort(peek.note.modified, Date.now()))
    color: Zenon.accentMuted
    font.family: Zenon.face
    font.weight: Zenon.weight
    font.pixelSize: Zenon.px(12)
  }
  Text {
    textFormat: Text.PlainText
    visible: text !== ""
    width: 312
    wrapMode: Text.Wrap
    maximumLineCount: 4
    elide: Text.ElideRight
    text: peek.closed ? "Locked — open it with the Clio password." : peek.d.preview
    color: peek.closed ? Zenon.accentMuted : Zenon.accentSoft
    font.family: Zenon.face
    font.weight: Zenon.weight
    font.italic: peek.closed
    font.pixelSize: Zenon.px(13)
  }
  ClippingRectangle {
    visible: !peek.closed && peek.d.images.length > 0
    width: 312
    height: visible ? 120 : 0
    radius: Zenon.windowRadius
    color: Zenon.wash(0.05)
    Image {
      anchors.fill: parent
      source: parent.visible && peek.mgr ? "file://" + peek.mgr.base + "/" + peek.d.images[0] : ""
      sourceSize.width: 640
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
    }
  }
}
