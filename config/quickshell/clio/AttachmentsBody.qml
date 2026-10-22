// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// EVERY PICTURE AND FILE — Apple's "View Attachments": what every note and
// entry holds, as a grid (pictures and sketches) or a list (files). A click
// goes to the note it is in; a double click opens the file itself.

import QtQuick
import Quickshell.Widgets
import "../morpheus"
import "../terminus"
import "notes.js" as N
import "../morpheus/icons.js" as Icons

Item {
  id: ab
  property var win: null
  property bool shown: false
  signal closed()
  property string kind: "pictures"
  readonly property var items: {
    if (!ab.shown || !ab.win) return [];
    const out = [];
    for (const n of ab.win.mgr.notes) {
      if (n.deleted || n.sealed || !n.blocks) continue;
      for (const b of n.blocks) {
        if (!b.src) continue;
        const pic = b.k === "image" || b.k === "sketch";
        if (pic !== (ab.kind === "pictures")) continue;
        out.push({ note: n, b: b });
      }
    }
    out.sort((a, b) => b.note.modified - a.note.modified);
    return out;
  }

  Row {
    id: top
    x: 20
    y: 16
    spacing: 12
    Text { anchors.verticalCenter: parent.verticalCenter; text: ""; color: Zenon.cyan; font.family: Zenon.glyphFace; font.pixelSize: Zenon.px(18) }
    Text { anchors.verticalCenter: parent.verticalCenter; text: "Pictures and files"; color: Zenon.ink; font.family: Zenon.face; font.weight: Font.Bold; font.pixelSize: Zenon.px(19) }
    Segments { anchors.verticalCenter: parent.verticalCenter; options: [["pictures", "Pictures"], ["files", "Files"]]; current: ab.kind; textSize: Zenon.px(12); onChose: (v) => ab.kind = v }
  }
  DialogButton { anchors.right: parent.right; anchors.rightMargin: 20; y: 16; label: "Close"; onClicked: ab.closed() }

  GridView {
    id: grid
    visible: ab.kind === "pictures"
    anchors.fill: parent
    anchors.topMargin: 62
    anchors.margins: 16
    clip: true
    cellWidth: Math.floor(width / Math.max(1, Math.floor(width / 150)))
    cellHeight: cellWidth
    model: ab.kind === "pictures" ? ab.items : []
    delegate: Item {
      required property var modelData
      width: grid.cellWidth
      height: grid.cellHeight
      ClippingRectangle {
        anchors.fill: parent
        anchors.margins: 4
        radius: Zenon.windowRadius
        color: Zenon.wash(0.05)
        Image {
          anchors.fill: parent
          source: "file://" + ab.win.mgr.base + "/" + modelData.b.src
          sourceSize.width: 300
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          // faded in as it arrives, not popped in (2026-10-17)
          opacity: status === Image.Ready ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: Zenon.ms(180); easing.type: Easing.OutCubic } }
        }
        Rectangle {
          anchors.bottom: parent.bottom
          width: parent.width
          height: 22
          color: Zenon.hud(0.75)
          Text {
            anchors.fill: parent
            anchors.leftMargin: 6
            anchors.rightMargin: 6
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            text: N.titleOf(modelData.note, "Entry")
            color: Zenon.ink
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(11)
          }
        }
      }
      MouseArea {
        anchors.fill: parent
        onClicked: { ab.closed(); ab.win.openNote(modelData.note.id); }
        onDoubleClicked: ab.win.openFile(modelData.b)
      }
    }
  }
  ListView {
    id: files
    visible: ab.kind === "files"
    anchors.fill: parent
    anchors.topMargin: 62
    anchors.margins: 16
    clip: true
    model: ab.kind === "files" ? ab.items : []
    delegate: Item {
      required property var modelData
      width: files.width
      height: 46
      Row {
        x: 6
        anchors.verticalCenter: parent.verticalCenter
        spacing: 12
        Text { anchors.verticalCenter: parent.verticalCenter; text: Icons.glyphFor({ name: modelData.b.name || "" }) || ""; color: Zenon.cyan; font.family: Zenon.glyphFace; font.pixelSize: Zenon.px(18) }
        Column {
          anchors.verticalCenter: parent.verticalCenter
          Text { text: modelData.b.name || "file"; color: Zenon.ink; font.family: Zenon.face; font.weight: Font.DemiBold; font.pixelSize: Zenon.px(14) }
          Text { text: N.sizeText(modelData.b.size) + "  ·  in " + N.titleOf(modelData.note, "an entry"); color: Zenon.accentMuted; font.family: Zenon.face; font.weight: Zenon.weight; font.pixelSize: Zenon.px(12) }
        }
      }
      MouseArea {
        anchors.fill: parent
        onClicked: { ab.closed(); ab.win.openNote(modelData.note.id); }
        onDoubleClicked: ab.win.openFile(modelData.b)
      }
    }
  }
  // the wheel and the bar, as every list has them; the bar on the card's edge
  ElasticScroll { anchors.fill: grid; view: grid; visible: grid.visible }
  ElasticScroll { anchors.fill: files; view: files; visible: files.visible }
  Scrollbar { flick: grid; visible: grid.visible; anchors.right: parent.right; anchors.top: grid.top; anchors.bottom: grid.bottom }
  Scrollbar { flick: files; visible: files.visible; anchors.right: parent.right; anchors.top: files.top; anchors.bottom: files.bottom }
  EmptyState { anchors.centerIn: parent; visible: ab.items.length === 0; text: ab.kind === "pictures" ? "No pictures" : "No files" }
}
