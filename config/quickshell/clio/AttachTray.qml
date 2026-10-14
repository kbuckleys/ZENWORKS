// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE TRAY — every picture and file already in Clio, in a bubble hung from
// its button in the note's toolbar, to use again: dragged out onto the note
// (where it goes in at the line, as anything dropped from outside does —
// BlockEditor's DropArea), or clicked, which puts it in at the caret. The
// suite's Bubble (sticky, so the pointer can cross into it) and its drag
// card; the drag is a real one, text/uri-list, so it reaches terminus and
// other windows too.

import QtQuick
import Quickshell.Widgets
import "../morpheus"
import "../terminus"
import "../morpheus/icons.js" as Icons

Bubble {
  id: tray
  property var win: null
  readonly property var mgr: tray.win ? tray.win.mgr : null
  sticky: true
  fit: false
  cardWidth: 452
  signal used(var item)

  // the newest first, each file once (the same file put in twice is one)
  readonly property var items: {
    // (kept while it closes: emptied then, the card shrank to its title)
    if (!tray.visible || !tray.mgr) return [];
    const out = [], seen = {};
    const notes = tray.mgr.notes.slice().sort((a, b) => b.modified - a.modified);
    for (const n of notes) {
      if (n.deleted || n.sealed || !n.blocks) continue;
      for (const b of n.blocks) {
        if (!b.src || seen[b.src]) continue;
        seen[b.src] = true;
        out.push({ src: b.src, name: b.name || b.src.replace(/.*\//, ""), pic: b.k === "image" || b.k === "sketch",
                   size: b.size || 0, path: tray.mgr.base + "/" + b.src });
      }
    }
    return out;
  }

  Row {
    spacing: 10
    Text { anchors.verticalCenter: parent.verticalCenter; text: "\u{F03E2}"; color: Zenon.cyan; font.family: Zenon.glyphFace; font.pixelSize: Zenon.px(15) }
    Text { anchors.verticalCenter: parent.verticalCenter; text: "Pictures and files"; color: Zenon.ink; font.family: Zenon.face; font.weight: Font.Bold; font.pixelSize: Zenon.px(15) }
    Text { anchors.verticalCenter: parent.verticalCenter; text: "drag onto the note, or click"; color: Zenon.muted; font.family: Zenon.face; font.weight: Zenon.weight; font.pixelSize: Zenon.px(12) }
  }

  Text {
    visible: tray.items.length === 0
    width: 424
    text: "Nothing put in a note yet."
    color: Zenon.muted
    font.family: Zenon.face
    font.weight: Zenon.weight
    font.pixelSize: Zenon.px(13)
  }

  Flickable {
    id: flick
    visible: tray.items.length > 0
    width: 424
    height: Math.min(grid.height, 340)
    contentHeight: grid.height
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height
    Grid {
      id: grid
      columns: 4
      spacing: 8
      Repeater {
        model: tray.items
        delegate: Item {
          id: tile
          required property var modelData
          width: 100
          height: 100
          ClippingRectangle {
            id: face
            anchors.fill: parent
            radius: 8
            color: Zenon.wash(0.06)
            border.width: 1
            border.color: tileMa.containsMouse ? Zenon.alpha(Zenon.cyan, 0.7) : Zenon.border
            Image {
              anchors.fill: parent
              visible: tile.modelData.pic
              source: tile.modelData.pic ? "file://" + tile.modelData.path : ""
              sourceSize.width: 220
              fillMode: Image.PreserveAspectCrop
              asynchronous: true
            }
            Column {
              visible: !tile.modelData.pic
              anchors.centerIn: parent
              width: parent.width - 12
              spacing: 4
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Icons.glyphFor({ name: tile.modelData.name }) || "\u{F0214}"
                color: Zenon.cyan
                font.family: Zenon.glyphFace
                font.pixelSize: Zenon.px(26)
              }
              Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideMiddle
                text: tile.modelData.name
                color: Zenon.soft
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.pixelSize: Zenon.px(11)
              }
            }
          }
          MouseArea {
            id: tileMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.OpenHandCursor
            property point at
            property bool carried: false
            onPressed: (m) => { tileMa.at = Qt.point(m.x, m.y); tileMa.carried = false; }
            onPositionChanged: (m) => {
              if (!pressed || tileMa.carried) return;
              if (Math.abs(m.x - tileMa.at.x) + Math.abs(m.y - tileMa.at.y) < 8) return;
              tileMa.carried = true;
              tray.carry(tile.modelData, m.x, m.y);
            }
            onClicked: if (!tileMa.carried) tray.used(tile.modelData)
          }
        }
      }
    }
  }

  // ── THE DRAG ──
  // terminus' shape (dragProxy): source and keys both set, copy only, the
  // card's picture taken before the drag goes active
  function carry(it, hx, hy) {
    proxy.uris = Strings.fileUrl(it.path);
    card.label = it.name;
    card.glyph = Icons.glyphFor({ name: it.name }) || "\u{F0214}";
    card.thumb = it.pic ? "file://" + it.path : "";
    card.picture((url) => {
      proxy.Drag.imageSource = url;
      proxy.Drag.hotSpot = Qt.point(20, 20);
      proxy.Drag.active = true;
    });
  }
  // (in a room of no size: the bubble stacks what it is given)
  Item {
    width: 0
    height: 0
    Item {
      id: proxy
      width: 1
      height: 1
      property string uris: ""
      Drag.active: false
      Drag.source: proxy
      Drag.keys: ["text/uri-list"]
      Drag.mimeData: ({ "text/uri-list": proxy.uris })
      Drag.supportedActions: Qt.CopyAction
      Drag.dragType: Drag.Automatic
      Drag.onDragFinished: proxy.Drag.active = false
    }
    DragCard { id: card; x: -4000; ink: Zenon.cyan }
  }
}
