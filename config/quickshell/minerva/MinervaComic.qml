// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A comic in minerva (CBZ, CBR — user, 2026-10-21): its pictures, unpacked
// by core/books.py with their sizes, laid out as a PDF's pages are (minerva
// .js' layoutPages: one to a row, two side by side, or the cover alone),
// on the suite's flickable. Only the pages near the view are loaded.
//
// The same face to the window as MinervaPdf: `where` ({ page }), goTo,
// step, zoomBy/fit, `thumb` and aspectOf for the sidebar's Pages. A comic
// has no words to find, select or highlight; it is always shown as drawn.

import QtQuick
import "../morpheus"
import "minerva.js" as M

Item {
  id: cm

  // books.py's comic.json: { title, pages: [{ file, width, height }] }
  property var book: null
  property var startAt: null
  property string zoomMode: "page"
  property string spread: "off"
  // the frosted head and the sidebar: the pages run on under both
  property real insetTop: 0
  property real insetRight: 0
  property real insetBottom: 0
  readonly property real viewW: strip.width - cm.insetRight
  readonly property real viewH: strip.height - cm.insetTop - cm.insetBottom
  signal moved(var where)
  signal failed(string why)
  signal zoomChosen(var zoom)
  signal menuAsked(real x, real y)

  readonly property bool ready: !!cm.book && cm.placed
  readonly property bool paged: true
  // what scrolls, for the window's frosted edges (ScrollEdge)
  readonly property Item view: strip
  readonly property int pageCount: cm.book ? cm.book.pages.length : 0
  readonly property string title: cm.book ? cm.book.title : ""
  readonly property string author: ""
  readonly property var where: ({ page: cm.currentPage })
  readonly property string selected: ""
  readonly property var outline: []
  readonly property var hits: []
  property real zoom: 1
  readonly property int zoomPercent: Math.round(cm.zoom * 100)
  property string fitting: typeof cm.zoomMode === "number" ? "" : cm.zoomMode
  function find(words) {}
  function findNext() {}
  function findPrev() {}
  function showHit(h) {}
  function copy() {}

  readonly property int pad: 16
  readonly property int gap: 8
  readonly property var sizes: !cm.book ? [] : cm.book.pages.map((p) => ({ width: p.width, height: p.height }))
  readonly property var lay: M.layoutPages(cm.sizes, cm.zoom, cm.spread, cm.pad, cm.gap, cm.viewW, cm.insetTop)
  function rowOf(p) { return cm.lay.rowOf[p] || 0; }
  function pageAt(y) { const r = cm.lay.rows[M.rowAt(cm.lay.tops, y)]; return r ? r[0] : 0; }
  readonly property int currentPage: cm.pageAt(strip.contentY + cm.insetTop + cm.viewH * 0.35)
  onCurrentPageChanged: if (cm.ready) cm.moved({ page: cm.currentPage })
  readonly property int firstNear: Math.max(0, cm.pageAt(strip.contentY - strip.height))
  readonly property int lastNear: { const r = cm.lay.rows[M.rowAt(cm.lay.tops, strip.contentY + strip.height * 2)]; return r ? r[r.length - 1] : 0; }

  function show(p) {
    if (cm.sizes.length === 0) return;
    p = Math.max(0, Math.min(cm.sizes.length - 1, p));
    strip.elastic.halt(flick);
    strip.contentY = Math.max(0, Math.min(strip.contentHeight - strip.height, cm.lay.tops[cm.rowOf(p)] - cm.pad - cm.insetTop));
  }
  function goTo(w) { if (w && w.page !== undefined) cm.show(w.page); }
  function step(d) {
    const row = cm.lay.rows[Math.max(0, Math.min(cm.lay.rows.length - 1, cm.rowOf(cm.currentPage) + d))];
    if (row) cm.show(row[0]);
  }

  function setZoom(z) {
    z = Math.max(0.05, Math.min(6, z));
    const p = cm.currentPage;
    strip.elastic.halt(flick);
    cm.zoom = z;
    cm.show(p);
  }
  function fitZoom(mode) {
    return cm.sizes.length === 0 ? 1 : M.fitZoom(cm.sizes, cm.spread, mode, cm.rowOf(cm.currentPage), cm.pad, cm.gap, cm.viewW, cm.viewH);
  }
  function zoomBy(f) { cm.setZoom(cm.zoom * f); cm.fitting = ""; cm.zoomChosen(Math.round(cm.zoom * 100) / 100); }
  function fit(mode) { cm.fitting = mode; cm.setZoom(cm.fitZoom(mode)); cm.zoomChosen(mode); }
  // (a timer, not callLater: it goes with this item if the book closes first)
  onSpreadChanged: if (cm.placed) { respread.page = cm.currentPage; if (cm.fitting !== "") cm.zoom = cm.fitZoom(cm.fitting); respread.restart(); }
  Timer { id: respread; interval: 0; property int page: 0; onTriggered: cm.show(respread.page) }

  property bool placed: false
  onBookChanged: if (cm.book) settle.restart()
  Timer {
    id: settle
    interval: 30
    onTriggered: {
      cm.zoom = typeof cm.zoomMode === "number" ? cm.zoomMode : cm.fitZoom(cm.zoomMode);
      cm.placed = true;
      if (cm.startAt) cm.show(cm.startAt.page || 0);
    }
  }
  onWidthChanged: if (cm.placed && cm.fitting !== "") refit.restart()
  onInsetRightChanged: if (cm.placed && cm.fitting !== "") refit.restart()
  onInsetTopChanged: if (cm.placed && cm.fitting === "page") refit.restart()
  onHeightChanged: if (cm.placed && cm.fitting === "page") refit.restart()
  Timer { id: refit; interval: 120; onTriggered: if (cm.fitting !== "") cm.setZoom(cm.fitZoom(cm.fitting)) }

  function aspectOf(i) { const s = cm.sizes[i]; return s ? s.height / Math.max(1, s.width) : 1.5; }
  readonly property Component thumb: Component {
    Image {
      readonly property int pageIx: parent ? parent.pageIx || 0 : 0
      source: cm.book && cm.book.pages[pageIx] ? "file://" + cm.book.pages[pageIx].file : ""
      asynchronous: true
      fillMode: Image.PreserveAspectFit
      sourceSize.width: Math.round(width * Screen.devicePixelRatio)
    }
  }

  Rectangle { anchors.fill: parent; color: Zenon.ground }
  Flickable {
    id: strip
    anchors.fill: parent
    interactive: false
    boundsBehavior: Flickable.StopAtBounds
    contentWidth: cm.lay.contentW + cm.insetRight
    contentHeight: cm.lay.contentH + cm.insetBottom
    readonly property Elastic elastic: wheel.elastic
    Repeater {
      model: cm.pageCount
      delegate: Item {
        id: holder
        required property int index
        readonly property var box: cm.lay.rects[holder.index] || ({ x: 0, y: 0, w: 1, h: 1 })
        x: holder.box.x
        y: holder.box.y
        width: holder.box.w
        height: holder.box.h
        Rectangle { anchors.fill: parent; color: Zenon.wash(0.06) }
        TapHandler {
          acceptedButtons: Qt.RightButton
          onTapped: (ev) => { const p = holder.mapToItem(cm, ev.position.x, ev.position.y); cm.menuAsked(p.x, p.y); }
        }
        Loader {
          anchors.fill: parent
          active: holder.index >= cm.firstNear && holder.index <= cm.lastNear
          sourceComponent: Image {
            source: "file://" + cm.book.pages[holder.index].file
            asynchronous: true
            fillMode: Image.PreserveAspectFit
            sourceSize.width: Math.round(holder.width * Screen.devicePixelRatio)
            smooth: true
            mipmap: true
          }
        }
      }
    }
  }
  ElasticScroll {
    id: wheel
    anchors.fill: strip
    view: strip
    intercept: (w) => {
      if (!(w.modifiers & Qt.ControlModifier)) return false;
      cm.zoomBy(w.angleDelta.y > 0 ? 1.1 : 1 / 1.1);
      return true;
    }
  }
  Scrollbar { flick: strip; anchors.right: parent.right; anchors.rightMargin: cm.insetRight; anchors.top: parent.top; anchors.topMargin: cm.insetTop; anchors.bottom: parent.bottom; anchors.bottomMargin: cm.insetBottom }
  Scrollbar {
    flick: strip
    horizontal: true
    visible: strip.contentWidth > strip.width + 1
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.rightMargin: cm.insetRight
    anchors.bottom: parent.bottom
    anchors.bottomMargin: cm.insetBottom
  }
}
