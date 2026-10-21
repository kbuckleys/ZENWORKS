// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// The reader's sidebar: a PDF's pages, small (user, 2026-10-21: "it doesn't
// even display pages"), then four lists — the book's contents, your
// bookmarks, your highlights, and the hits of a find. A row is a place: a
// click goes there. A highlight that went to Clio says so, and its right
// click shows it there.

import QtQuick
import "../morpheus"
import "minerva.js" as M

Item {
  id: side

  // pages (a PDF's) · contents · marks · highlights · find
  property string tab: "contents"
  // a PDF's pages: the page's own small-page component (this file cannot
  // import QtQuick.Pdf), how many, which is open, and each one's shape
  property Component thumb: null
  property int pageCount: 0
  property int current: 0
  property var aspectOf: (i) => 1.414
  property var outline: []
  property var bookmarks: []
  property var highlights: []
  property var hits: []
  property string kind: "pdf"
  property var chapters: []
  property string findWords: ""
  property string serif: Zenon.face
  signal go(var where, var row)
  signal dropMark(string id, string list)
  signal showNote(var mark)

  readonly property var tabs: (side.kind === "pdf" ? [{ id: "pages", glyph: "\u{F1518}", tip: "Pages" }] : []).concat([
    { id: "contents", glyph: "\u{F0836}", tip: "Contents" },
    { id: "marks", glyph: "\u{F00C0}", tip: "Bookmarks" },
    { id: "highlights", glyph: "\u{F0652}", tip: "Highlights" },
    { id: "find", glyph: "\u{F0349}", tip: "Find" }
  ])
  // an EPUB has no pages tab to be on
  onKindChanged: if (side.kind !== "pdf" && side.tab === "pages") side.tab = "contents"
  readonly property var rows: side.tab === "contents" ? side.outline
    : side.tab === "marks" ? M.sortMarks(side.bookmarks)
    : side.tab === "highlights" ? M.sortMarks(side.highlights) : side.hits
  property int sel: -1
  onTabChanged: side.sel = -1

  // the four tabs, as a row of glyphs
  Row {
    id: tabRow
    x: 12
    y: 10
    spacing: 4
    Repeater {
      model: side.tabs
      delegate: Rectangle {
        required property var modelData
        readonly property bool here: side.tab === modelData.id
        width: (side.width - 24 - 4 * (side.tabs.length - 1)) / side.tabs.length
        height: 34
        radius: Zenon.radiusControl
        color: tabPress.pressed ? Zenon.pressTile(here) : here ? Zenon.menuHi : "transparent"
        Text {
          anchors.centerIn: parent
          text: parent.modelData.glyph
          color: parent.here ? Zenon.cyan : Zenon.accentMuted
          font.family: Zenon.glyphFace
          font.pixelSize: Zenon.px(16)
        }
        // how many, beside the glyph, for the three that count
        Text {
          anchors.right: parent.right
          anchors.rightMargin: 6
          anchors.top: parent.top
          anchors.topMargin: 3
          readonly property int n: parent.modelData.id === "marks" ? side.bookmarks.length
            : parent.modelData.id === "highlights" ? side.highlights.length
            : parent.modelData.id === "find" ? side.hits.length : 0
          visible: n > 0
          text: n > 99 ? "99+" : String(n)
          color: Zenon.accentMuted
          font.family: Zenon.face
          font.pixelSize: Zenon.px(10)
        }
        MouseArea { id: tabPress; anchors.fill: parent; onClicked: side.tab = parent.modelData.id }
      }
    }
  }
  SectionLabel {
    id: tabName
    x: 20
    anchors.top: tabRow.bottom
    anchors.topMargin: 14
    text: (side.tabs.find((t) => t.id === side.tab) || side.tabs[0]).tip
      + (side.tab === "find" && side.findWords !== "" ? " · “" + side.findWords + "”" : "")
  }

  EmptyState {
    anchors.top: tabName.bottom
    anchors.topMargin: 30
    x: 20
    width: side.width - 40
    visible: side.tab !== "pages" && side.rows.length === 0
    text: side.tab === "contents" ? "This book has no contents"
      : side.tab === "marks" ? "No bookmarks — ctrl d marks the page you are on"
      : side.tab === "highlights" ? "No highlights — select some words, then ctrl h"
      : side.findWords === "" ? "ctrl f finds words in the book" : "Nothing found"
  }

  // ── THE PAGES ──────────────────────────────────────────────────────────
  // only those in view are drawn; the open one is ringed and kept in view
  ListView {
    id: pages
    anchors.top: tabName.bottom
    anchors.topMargin: 8
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    visible: side.tab === "pages"
    clip: true
    model: side.tab === "pages" && side.thumb ? side.pageCount : 0
    spacing: 4
    bottomMargin: 12
    readonly property int thumbW: Math.min(170, side.width - 80)
    ElasticScroll { view: pages }
    delegate: Item {
      id: pageRow
      required property int index
      readonly property bool here: pageRow.index === side.current
      width: pages.width
      height: Math.round(pages.thumbW * side.aspectOf(pageRow.index)) + 34
      Rectangle {
        id: frame
        anchors.horizontalCenter: parent.horizontalCenter
        y: 4
        width: pages.thumbW + 8
        height: Math.round(pages.thumbW * side.aspectOf(pageRow.index)) + 8
        radius: Zenon.radiusControl
        color: pageRow.here ? Zenon.menuHi : "transparent"
        border.width: pageRow.here ? 2 : 0
        border.color: Zenon.cyan
        Loader {
          x: 4
          y: 4
          width: pages.thumbW
          height: parent.height - 8
          sourceComponent: side.thumb
          onLoaded: item.pageIx = Qt.binding(() => pageRow.index)
          onItemChanged: if (item) { item.anchors.fill = item.parent; }
        }
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: frame.bottom
        anchors.topMargin: 4
        text: String(pageRow.index + 1)
        color: pageRow.here ? Zenon.cyan : Zenon.accentMuted
        font.family: Zenon.face
        font.weight: pageRow.here ? Zenon.titleWeight : Zenon.weight
        font.pixelSize: Zenon.px(12)
      }
      MouseArea {
        anchors.fill: parent
        onClicked: side.go({ page: pageRow.index }, null)
      }
    }
  }
  Scrollbar { visible: pages.visible; flick: pages; anchors.right: parent.right; anchors.top: pages.top; anchors.bottom: pages.bottom }
  // the open page stays in sight as you read
  onCurrentChanged: if (side.tab === "pages") pagesFollow.restart()
  onTabChanged: if (side.tab === "pages") pagesFollow.restart()
  Timer { id: pagesFollow; interval: 0; onTriggered: if (pages.count > side.current) pages.positionViewAtIndex(side.current, ListView.Contain) }

  ListView {
    id: list
    visible: side.tab !== "pages"
    anchors.top: tabName.bottom
    anchors.topMargin: 8
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    clip: true
    // by count: the lists are rebuilt as the book moves
    model: side.rows.length
    ElasticScroll { view: list }
    CursorBand { follows: list; index: side.sel; shown: side.sel >= 0 }
    delegate: Item {
      id: row
      required property int index
      readonly property var r: side.rows[index] || null
      readonly property bool isMark: side.tab === "marks" || side.tab === "highlights"
      width: list.width
      height: side.tab === "contents" ? 34 : rowCol.implicitHeight + 16
      Column {
        id: rowCol
        x: 20 + (side.tab === "contents" && row.r ? Math.min(4, row.r.depth) * 14 : 0)
        width: row.width - x - 20
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3
        Text {
          width: parent.width
          elide: Text.ElideRight
          visible: side.tab === "contents"
          text: row.r && side.tab === "contents" ? row.r.label : ""
          color: row.index === side.sel ? Zenon.ink : (row.r && row.r.depth > 0 ? Zenon.accentSoft : Zenon.white)
          font.family: Zenon.face
          font.weight: row.r && row.r.depth === 0 ? 600 : Zenon.weight
          font.pixelSize: Zenon.px(14)
        }
        // a mark or a hit: where, then its words
        Text {
          visible: side.tab !== "contents"
          text: !row.r || side.tab === "contents" ? "" : M.whereWords(side.kind, row.r.where, side.chapters)
            + (side.tab === "highlights" && row.r.note ? "  ·  in Clio" : "")
          color: Zenon.accentMuted
          font.family: Zenon.face
          font.weight: 600
          font.pixelSize: Zenon.px(12)
        }
        Text {
          width: parent.width
          visible: side.tab !== "contents" && text !== ""
          wrapMode: Text.WordWrap
          maximumLineCount: side.tab === "find" ? 3 : 5
          elide: Text.ElideRight
          textFormat: side.tab === "find" ? Text.StyledText : Text.PlainText
          text: !row.r || side.tab === "contents" ? ""
            : side.tab === "find" ? M.litSnippet(row.r.snippet || "", side.findWords, Zenon.cyan)
            : side.tab === "highlights" ? "“" + (row.r.text || "") + "”" : (row.r.text || "")
          color: Zenon.white
          font.family: side.tab === "highlights" ? side.serif : Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(14)
        }
      }
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (m) => {
          side.sel = row.index;
          if (!row.r) return;
          if (m.button === Qt.RightButton) {
            if (side.tab === "highlights" && row.r.note) side.showNote(row.r);
            else if (row.isMark) side.dropMark(row.r.id, side.tab);
            return;
          }
          side.go(row.r.where, row.r);
        }
      }
    }
  }
  Scrollbar { visible: list.visible; flick: list; anchors.right: parent.right; anchors.top: list.top; anchors.bottom: list.bottom }
}
