// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE FILES OF AN UPLOAD UNDER WAY, one a row — the head's bubble: the
// file's own glyph (terminus'), its name, where it lands in the repository,
// its size, and where it has got to (waiting, going, sent, failed). The
// breakdown before it is a tree (morpheus' FileTree, of the given paths).
//
//     UploadRows { entries: [{ name, path, size, state }]; maxRows: 8 }
//
// Taller than maxRows rows, it scrolls (the shell's wheel).

import QtQuick
import "../morpheus"
import "delphi.js" as D
import "../terminus/terminus.js" as Terminus
import "../morpheus/icons.js" as Icons

Item {
  id: ur
  property var entries: []
  property int maxRows: 8
  readonly property real rowH: Math.round(Zenon.px(14) * 2.1)
  implicitHeight: Math.min(ur.entries.length, ur.maxRows) * ur.rowH + (ur.entries.length > 0 ? 12 : 0)
  visible: ur.entries.length > 0

  Rectangle {
    anchors.fill: parent
    radius: Zenon.windowRadius
    color: Zenon.wash(0.04)
    border.width: 1
    border.color: Zenon.border
  }
  ListView {
    id: list
    anchors.fill: parent
    anchors.margins: 6
    clip: true
    interactive: false
    boundsBehavior: Flickable.StopAtBounds
    model: ur.entries
    delegate: Item {
      id: row
      required property var modelData
      readonly property var e: row.modelData
      readonly property var probe: ({ name: row.e.name || D.baseName(row.e.path), path: row.e.path, size: Math.max(1, row.e.size) })
      width: list.width
      height: ur.rowH
      Text {
        id: glyph
        x: 6
        width: 20
        anchors.verticalCenter: parent.verticalCenter
        text: Terminus.glyphOf(row.probe, Icons)
        color: Zenon[Terminus.inkKeyOf(row.probe)]
        font.family: Zenon.glyphFace
        font.pixelSize: Zenon.px(14)
      }
      Text {
        textFormat: Text.PlainText
        id: nameText
        anchors.left: glyph.right
        anchors.leftMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, parent.width * 0.42)
        elide: Text.ElideMiddle
        text: row.probe.name
        color: row.e.state === "failed" ? Zenon.red : Zenon.ink
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(14)
      }
      // where it lands, when that is not simply its own name at the top
      Text {
        textFormat: Text.PlainText
        anchors.left: nameText.right
        anchors.leftMargin: 8
        anchors.right: size.left
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideMiddle
        text: row.e.path !== row.probe.name ? "→  " + row.e.path : ""
        color: Zenon.accentMuted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(13)
      }
      Text {
        id: size
        anchors.right: mark.left
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        text: row.e.size >= 0 ? Terminus.formatSize(row.e.size) : ""
        color: Zenon.accentMuted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.features: { "tnum": 1 }
        font.pixelSize: Zenon.px(13)
      }
      // what happens to it, or where it has got to
      Item {
        id: mark
        anchors.right: parent.right
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        width: Zenon.px(64)
        height: parent.height
        Working {
          visible: row.e.state === "sending"
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          running: visible
          ink: Zenon.cyan
          dot: 4
          gap: 3
        }
        Text {
          visible: row.e.state !== "sending"
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: row.e.state === "sent" ? "" : row.e.state === "failed" ? "" : "•"
          color: row.e.state === "sent" ? Zenon.green : row.e.state === "failed" ? Zenon.red : Zenon.dimInk
          font.family: Zenon.glyphFace
          font.pixelSize: Zenon.px(13)
        }
      }
    }
  }
  // the file under way kept in sight, unless `follow` is off (the pointer
  // on the bubble, scrolling it)
  property bool follow: true
  onEntriesChanged: {
    if (!ur.follow) return;
    const i = ur.entries.findIndex((e) => e.state === "sending");
    if (i >= 0) list.positionViewAtIndex(i, ListView.Contain);
  }
  ElasticScroll { anchors.fill: list; view: list }
  Scrollbar { flick: list; anchors.right: parent.right; anchors.top: list.top; anchors.bottom: list.bottom }
}
