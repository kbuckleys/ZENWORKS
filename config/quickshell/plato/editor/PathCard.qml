// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A PATH'S FILE, IN A CARD. Beside the completion menu while it offers paths
// (CompletionMenu.qml), and beside the pointer resting on a path in the text
// (EditorView's peek): the file through FilePreview — highlighted text, a
// picture, a directory's entries — in a card sized to what it shows, with
// the path under it. Only there once there is something to show: a path to
// nothing, or to a binary, brings up no card at all.

import QtQuick
import Quickshell
import "../../morpheus"

Item {
  id: card

  property string file: ""
  property string codeFamily: Zenon.faceFixed
  property int pixelSize: 14
  property real maxW: 560
  property real maxH: 340
  // a word after the path ("gf opens it in Picasso")
  property string hint: ""

  readonly property string kind: fp.kind
  readonly property bool ready: card.file !== ""
    && (fp.kind === "text" || fp.kind === "dir" || (fp.kind === "image" && fp.imageReady))
  visible: card.ready

  readonly property int pad: 6
  readonly property real captionH: caption.implicitHeight + 6
  readonly property real roomH: card.maxH - card.captionH - card.pad * 2
  // a picture at its own shape, as large as the room lets it be
  readonly property real fit: fp.kind !== "image" || fp.contentW <= 0 ? 1
    : Math.min(1, (card.maxW - card.pad * 2) / fp.contentW, card.roomH / fp.contentH)
  readonly property real bodyW: fp.kind === "image" ? Math.round(fp.contentW * card.fit)
    : Math.min(card.maxW - card.pad * 2, Math.max(220, fp.contentW))
  readonly property real bodyH: fp.kind === "image" ? Math.round(fp.contentH * card.fit)
    : Math.min(card.roomH, fp.contentH)
  width: card.bodyW + card.pad * 2
  height: card.bodyH + card.captionH + card.pad * 2

  Rectangle {
    anchors.fill: parent
    radius: Zenon.windowRadius
    color: Qt.rgba(0.05, 0.055, 0.065, 0.97)
    border.width: 1
    border.color: Zenon.border
  }
  Item {
    x: card.pad
    y: card.pad
    width: card.bodyW
    height: card.bodyH
    clip: true
    FilePreview {
      id: fp
      // text wraps at the card's widest, and the card then takes what it used
      width: fp.kind === "image" ? card.bodyW : card.maxW - card.pad * 2
      height: fp.kind === "image" ? card.bodyH : card.roomH
      file: card.file
      delay: 0
      wrap: true
      codeFamily: card.codeFamily
      pixelSize: card.pixelSize
    }
  }
  Text {
    id: caption
    x: card.pad + 8
    y: card.pad + card.bodyH + 2
    width: card.width - card.pad * 2 - 16
    elide: Text.ElideMiddle
    textFormat: Text.PlainText
    font.family: Zenon.face
    font.pixelSize: 11
    color: Zenon.muted
    readonly property string home: Quickshell.env("HOME")
    text: (card.file.startsWith(caption.home + "/") ? "~" + card.file.slice(caption.home.length) : card.file)
      + (card.hint !== "" ? "  ·  " + card.hint : "")
  }
}
