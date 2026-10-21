// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// Minerva's library: every book you have opened, the last one read first —
// its cover (an EPUB's own, a PDF's first page), its title and author, how
// far through you are, and when you last read it. Typing filters it.

import QtQuick
import "../morpheus"
import "minerva.js" as M

Item {
  id: lib

  property var mgr: null
  property string query: ""
  property int sel: 0
  signal chosen(string path)
  signal forgot(string path)

  readonly property var shown: {
    const q = lib.query.trim().toLowerCase();
    const all = lib.mgr ? lib.mgr.books : [];
    return q === "" ? all : all.filter((b) => (b.title + " " + b.author + " " + b.path).toLowerCase().indexOf(q) >= 0);
  }
  onShownChanged: if (lib.sel >= lib.shown.length) lib.sel = Math.max(0, lib.shown.length - 1)

  readonly property int cellW: 188
  // THE CELL IS AS TALL AS WHAT IT HOLDS (user, 2026-10-21: the cursor did
  // not reach the labels): the cover grows with the column's width, so a
  // fixed 320 let the three lines under a wide one hang out of the cell
  FontMetrics { id: titleFm; font.family: Zenon.face; font.weight: Zenon.titleWeight; font.pixelSize: Zenon.px(14) }
  FontMetrics { id: smallFm; font.family: Zenon.face; font.weight: Zenon.weight; font.pixelSize: Zenon.px(12) }
  readonly property int cellH: 16 + Math.round((Math.floor(grid.width / lib.cols) - 36) * 1.42)
    + 10 + Math.ceil(titleFm.height + 2 * smallFm.height) + 4 + 18
  readonly property int cols: Math.max(1, Math.floor((grid.width) / lib.cellW))
  function move(dx, dy) {
    const n = lib.shown.length;
    if (n === 0) return;
    lib.sel = Math.max(0, Math.min(n - 1, lib.sel + dx + dy * lib.cols));
    grid.positionViewAtIndex(lib.sel, GridView.Contain);
  }
  function current() { return lib.shown[lib.sel] || null; }

  EmptyState {
    anchors.centerIn: parent
    width: Math.min(parent.width - 80, 520)
    visible: lib.shown.length === 0
    text: lib.query !== "" ? "Nothing in the library matches “" + lib.query + "”"
      : "No books yet — Open… (ctrl o) picks a PDF or an EPUB, and anything opened from Terminus lands here"
  }

  GridView {
    id: grid
    anchors.fill: parent
    anchors.leftMargin: 24
    anchors.rightMargin: 12
    anchors.topMargin: 20
    clip: true
    cellWidth: Math.floor(width / lib.cols)
    cellHeight: lib.cellH
    // by count: the library is a new array whenever a place is saved
    model: lib.shown.length
    ElasticScroll { view: grid }
    CursorBand { follows: grid; index: lib.sel; radius: Zenon.radiusCard; insetX: 6; insetY: 6 }
    delegate: Item {
      id: cell
      required property int index
      readonly property var book: lib.shown[index] || null
      width: grid.cellWidth
      height: grid.cellHeight

      // the cover: its own, or the title set on a plain board
      Rectangle {
        id: coverBox
        anchors.horizontalCenter: parent.horizontalCenter
        y: 16
        width: grid.cellWidth - 36
        height: Math.round(width * 1.42)
        radius: Zenon.radiusControl
        color: Zenon.wash(0.06)
        border.width: 1
        border.color: Zenon.border
        clip: true
        property string src: ""
        Component.onCompleted: coverBox.fetch()
        Connections { target: cell; function onBookChanged() { coverBox.fetch(); } }
        function fetch() {
          const b = cell.book;
          coverBox.src = "";
          if (!b) return;
          if (b.cover) coverBox.src = b.cover;
          else if (b.kind === "pdf" && lib.mgr) {
            const path = b.path;
            lib.mgr.pdfCover(path, (url) => {
              if (cell.book && cell.book.path === path) { coverBox.src = url; lib.mgr.change(path, { cover: url }); }
            });
          }
        }
        Image {
          anchors.fill: parent
          source: coverBox.src
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          sourceSize.width: 360
          visible: status === Image.Ready
        }
        Column {
          anchors.centerIn: parent
          width: parent.width - 24
          spacing: 8
          visible: coverBox.src === ""
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: cell.book && cell.book.kind === "pdf" ? "\u{F0226}" : "\u{F05DA}"
            color: Zenon.accentMuted
            font.family: Zenon.glyphFace
            font.pixelSize: Zenon.px(30)
          }
          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            maximumLineCount: 4
            elide: Text.ElideRight
            text: cell.book ? cell.book.title : ""
            color: Zenon.ink
            font.family: lib.mgr ? lib.mgr.serifFace : Zenon.face
            font.pixelSize: Zenon.px(15)
          }
        }
        // how far through: a band along the cover's foot
        Rectangle {
          anchors.bottom: parent.bottom
          width: parent.width * (cell.book ? cell.book.progress : 0)
          height: 4
          color: Zenon.cyan
          visible: !!cell.book && cell.book.progress > 0
        }
      }
      Column {
        anchors.top: coverBox.bottom
        anchors.topMargin: 10
        anchors.horizontalCenter: parent.horizontalCenter
        width: coverBox.width
        spacing: 2
        Text {
          width: parent.width
          elide: Text.ElideRight
          text: cell.book ? cell.book.title : ""
          color: index === lib.sel ? Zenon.ink : Zenon.white
          font.family: Zenon.face
          font.weight: Zenon.titleWeight
          font.pixelSize: Zenon.px(14)
        }
        Text {
          width: parent.width
          elide: Text.ElideRight
          text: !cell.book ? "" : [cell.book.author, M.KINDS[cell.book.kind]].filter((x) => x).join("  ·  ")
          color: Zenon.accentMuted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(12)
        }
        Text {
          width: parent.width
          elide: Text.ElideRight
          text: !cell.book ? "" : (cell.book.progress > 0 ? M.percentWords(cell.book.progress) + "  ·  " : "New  ·  ")
            + M.openedWords(cell.book.opened)
          color: Zenon.accentMuted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(12)
        }
      }
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (m) => {
          lib.sel = cell.index;
          if (m.button === Qt.RightButton) { if (cell.book) lib.forgot(cell.book.path); }
          else if (cell.book) lib.chosen(cell.book.path);
        }
      }
    }
  }
  Scrollbar { flick: grid; anchors.right: parent.right; anchors.top: grid.top; anchors.bottom: grid.bottom }
}
