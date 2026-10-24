// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// The reader's sidebar: a PDF's pages, small (user, 2026-10-21: "it doesn't
// even display pages"), then four lists — the book's contents, your
// bookmarks, your highlights, and the hits of a find. A row is a place: a
// click goes there. A highlight wears its colour down its edge and what you
// wrote on it under its words; a right click on a mark is its menu (the
// window's: go, colour, note, Clio, remove — 2026-10-21, it used to remove
// at once).

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
  property var inks: ({})
  // the window's tooltip, for the tabs' names; and where the toolbar above
  // this begins, in its coordinates (the buttons over the tabs)
  property var tip: null
  property real chromeTop: 0
  signal go(var where, var row)
  // a right click on a row: the row, its list, where (in this item)
  signal rowMenu(var row, string list, real x, real y)

  // a highlight clicked on the page: its row, shown and chosen
  function reveal(id, list) {
    side.tab = list || "highlights";
    Qt.callLater(() => {
      const i = side.rows.findIndex((r) => r.id === id);
      if (i < 0) return;
      side.sel = i;
      side.glideTo(list_, listWheel, i);
    });
  }

  readonly property var tabs: (side.kind === "pdf" ? [{ id: "pages", glyph: "\u{F1518}", tip: "Pages" }] : []).concat([
    { id: "contents", glyph: "\u{F0836}", tip: "Contents" },
    { id: "marks", glyph: "\uF47A", tip: "Bookmarks" },
    { id: "highlights", glyph: "\u{F0652}", tip: "Highlights" },
    { id: "find", glyph: "\u{F0349}", tip: "Find" }
  ])
  // an EPUB has no pages tab to be on
  onKindChanged: if (side.kind !== "pdf" && side.tab === "pages") side.tab = "contents"
  readonly property var rows: side.tab === "contents" ? side.outline
    : side.tab === "marks" ? M.sortMarks(side.bookmarks)
    : side.tab === "highlights" ? M.sortMarks(side.highlights) : side.hits
  property int sel: -1
  onTabChanged: { rowFlash.cancel(); side.sel = -1; if (side.tab === "pages") { pagesFollow.jump = true; pagesFollow.restart(); } }

  // ── GLIDING THERE (user, 2026-10-21: it jumped) ────────────────────────
  // where positionViewAtIndex would put row i, asked and put back, then
  // reached by the wheel's own follow (morpheus/Elastic's glide) — the same
  // feel as scrolling there by hand
  function glideTo(view, wheel, i) {
    const was = view.contentY;
    view.positionViewAtIndex(i, ListView.Contain);
    const to = view.contentY;
    view.contentY = was;
    if (Math.abs(to - was) < 1) return;
    wheel.elastic._glide.aim(view, to);
  }

  // ── WHAT SCROLLS UP GOES UNDER THE TABS (user, 2026-10-21) ────────────
  // the pages and the lists run on under the tabs and the label, frosted,
  // fading as they rise — the suite's ScrollEdge, from the sidebar's top
  // down to the view (Hestia's recipe: follow, no bar)
  ScrollEdge { view: pages; follow: true; chromeTop: side.chromeTop; visible: pages.visible; z: 1 }
  ScrollEdge { view: list_; follow: true; chromeTop: side.chromeTop; visible: list_.visible; z: 1 }
  // the toolbar's foot, a hairline as the head's (user, 2026-10-21)
  Rectangle { z: 3; y: pages.y - 1; width: side.width; height: 1; color: Zenon.border }

  // the four tabs, as a row of glyphs
  Row {
    id: tabRow
    z: 3
    x: 12
    y: 10
    spacing: 4
    Repeater {
      model: side.tabs
      delegate: Rectangle {
        id: tabCell
        required property var modelData
        readonly property bool here: side.tab === modelData.id
        // its name on hover, where the title under the tabs used to say it
        // (user, 2026-10-21)
        HoverHandler { onHoveredChanged: if (side.tip) { if (hovered) side.tip.show(tabCell, tabCell.modelData.tip); else side.tip.hide(tabCell); } }
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

  EmptyState {
    anchors.top: tabRow.bottom
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
  // a place chosen flashes, then the book goes there (morpheus/RowFlash,
  // user 2026-10-21) — the pages' thumbnails and the lists alike
  RowFlash { id: rowFlash }
  ListView {
    id: pages
    anchors.top: tabRow.bottom
    anchors.topMargin: 8
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    visible: side.tab === "pages"
    clip: true
    model: side.tab === "pages" && side.thumb ? side.pageCount : 0
    spacing: 4
    bottomMargin: 12
    // as wide as the sidebar, less its margins (user, 2026-10-21)
    readonly property int thumbW: side.width - 48
    ElasticScroll { id: pagesWheel; view: pages }
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
        FlashOver { flash: rowFlash; index: pageRow.index; radius: parent.radius }
        // the page is handed over before the small page is made (the
        // loader's own pageIx, read as it is built): set after, Qt's page
        // image kept drawing page 1 in every frame
        Loader {
          x: 4
          y: 4
          width: pages.thumbW
          height: parent.height - 8
          sourceComponent: side.thumb
          property int pageIx: pageRow.index
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
        onClicked: { const i = pageRow.index; rowFlash.flashThen(i, () => side.go({ page: i }, null)); }
      }
    }
  }
  Scrollbar { visible: pages.visible; flick: pages; anchors.right: parent.right; anchors.top: pages.top; anchors.bottom: pages.bottom }
  // the open page stays in sight as you read
  onCurrentChanged: if (side.tab === "pages") pagesFollow.restart()
  // opening the tab puts the page there at once; reading on glides to it
  Timer {
    id: pagesFollow
    interval: 0
    property bool jump: false
    onTriggered: {
      if (pages.count <= side.current) return;
      if (pagesFollow.jump) pages.positionViewAtIndex(side.current, ListView.Contain);
      else side.glideTo(pages, pagesWheel, side.current);
      pagesFollow.jump = false;
    }
  }

  ListView {
    id: list_
    visible: side.tab !== "pages"
    anchors.top: tabRow.bottom
    anchors.topMargin: 8
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    clip: true
    // by count: the lists are rebuilt as the book moves
    model: side.rows.length
    ElasticScroll { id: listWheel; view: list_ }
    CursorBand { follows: list_; index: side.sel; shown: side.sel >= 0 }
    delegate: Item {
      id: row
      required property int index
      readonly property var r: side.rows[index] || null
      readonly property bool isMark: side.tab === "marks" || side.tab === "highlights"
      width: list_.width
      height: side.tab === "contents" ? 34 : rowCol.implicitHeight + 16
      FlashOver { flash: rowFlash; index: row.index }
      // a highlight's colour, down its edge
      Rectangle {
        visible: side.tab === "highlights" && !!row.r
        x: 10
        y: 8
        width: 3
        height: parent.height - 16
        radius: 1.5
        color: row.r && side.inks[row.r.color] ? side.inks[row.r.color] : Zenon.yellow
      }
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
        // what you wrote on it
        Text {
          width: parent.width
          visible: side.tab === "highlights" && !!row.r && row.r.comment !== ""
          wrapMode: Text.WordWrap
          maximumLineCount: 4
          elide: Text.ElideRight
          text: row.r && row.r.comment ? row.r.comment : ""
          color: Zenon.accentSoft
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(13)
        }
      }
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (m) => {
          side.sel = row.index;
          if (!row.r) return;
          if (m.button === Qt.RightButton) {
            const p = mapToItem(side, m.x, m.y);
            side.rowMenu(row.r, side.tab, p.x, p.y);
            return;
          }
          const r = row.r;
          rowFlash.flashThen(row.index, () => side.go(r.where, r));
        }
      }
    }
  }
  Scrollbar { visible: list_.visible; flick: list_; anchors.right: parent.right; anchors.top: list_.top; anchors.bottom: list_.bottom }
}
