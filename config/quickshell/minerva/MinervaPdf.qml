// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A PDF in minerva: QtQuick.Pdf's pieces (PdfDocument, PdfPageImage,
// PdfSelection, PdfSearchModel, PdfLinkModel — from qt6-webengine) laid out
// by this file. Loaded by the window only once Qt PDF is known to be
// installed — this file does not compile without it, which is why it is
// apart (a Loader, not a child).
//
// ITS OWN PAGES, NOT Qt's PdfMultiPageView (user, 2026-10-21). Qt's view is a
// TableView that guesses its height from the rows it has loaded, so the
// suite's elastic wheel snapped as the guess changed on a long PDF; its own
// Controls scrollbar showed only while IT moved the pages, so ours scrolling
// them hid it; and its column was the page plus its scrollbar's width, which
// put the page off center, wide on the left. Here every page's place is
// known from the start (pagePointSize × zoom, summed), the flickable is the
// suite's (ElasticScroll + Scrollbar), the pages are centered, and only the
// ones near the view are drawn. Qt's docs suggest exactly this: copy its
// assembly and make it yours.
//
// The window talks to a page the same way whatever it shows (MinervaBook
// is the EPUB's, MinervaComic a comic's): `where`, goTo(where), `outline`,
// find(words) and the hits, `selected`, zoomBy/fit — and, for the
// sidebar's Pages, `thumb`.
//
// 2026-10-21: two pages side by side (`spread`, laid out by minerva.js'
// layoutPages, shared with the comics), the page's colours (`look`: a
// sepia or night page is the printed one through morpheus/shaders/
// pagetone), and your highlights drawn on it in their colours — a click
// on one says which (hiTapped), a right click anywhere asks for the menu.

import QtQuick
import QtQuick.Shapes
import QtQuick.Pdf
import "../morpheus"
import "minerva.js" as M

Item {
  id: pg

  property string path: ""
  // where to open at, once the document has pages: { page }
  property var startAt: null
  property string zoomMode: "width"   // "width" | "page" | a number
  property string spread: "off"       // off · on · cover
  // { bg, ink, tone } (minerva.js themeOf): tone puts the page through pagetone
  property var look: ({ bg: "white", ink: "black", tone: false })
  // the frosted head over the pages and the sidebar beside them: the pages
  // run on under both, and sit clear of them at rest
  property real insetTop: 0
  property real insetRight: 0
  property real insetBottom: 0
  readonly property real viewW: flick.width - pg.insetRight
  readonly property real viewH: flick.height - pg.insetTop - pg.insetBottom
  readonly property color paperInk: pg.look.tone ? pg.look.bg : "white"
  // the book's highlights; the colours by name (the window's)
  property var highlights: []
  property var inks: ({})
  signal moved(var where)
  signal failed(string why)
  signal zoomChosen(var zoom)
  signal hiTapped(string id)
  // a right click: where, in this item
  signal menuAsked(real x, real y)

  readonly property bool ready: doc.status === PdfDocument.Ready
  readonly property int pageCount: pg.ready ? doc.pageCount : 0
  readonly property string title: doc.title
  readonly property bool paged: true
  // what scrolls, for the window's frosted edges (ScrollEdge)
  readonly property Item view: flick
  readonly property string author: doc.author
  readonly property var where: ({ page: pg.currentPage })
  property string selected: ""
  // pixels per point; "zoom", because Item already has a `scale`
  property real zoom: 1
  readonly property int zoomPercent: Math.round(pg.zoom * 100)
  // "width" | "page" | "" (a size of its own)
  property string fitting: typeof pg.zoomMode === "number" ? "" : pg.zoomMode

  // ── THE PAGES' PLACES ──────────────────────────────────────────────────
  readonly property int pad: 16
  readonly property int gap: 12
  // every page's size in points, read once the document is in
  readonly property var sizes: {
    const out = [];
    if (!pg.ready) return out;
    for (let i = 0; i < doc.pageCount; ++i) out.push(doc.pagePointSize(i));
    return out;
  }
  // every page's box, one row of one or two at a time (minerva.js)
  readonly property var lay: M.layoutPages(pg.sizes, pg.zoom, pg.spread, pg.pad, pg.gap, pg.viewW, pg.insetTop)
  readonly property var tops: pg.lay.tops
  // the first page of the row at y
  function pageAt(y) { const r = pg.lay.rows[M.rowAt(pg.tops, y)]; return r ? r[0] : 0; }
  function rowOf(p) { return pg.lay.rowOf[p] || 0; }
  // the page under the upper third of the view is the one you are reading
  readonly property int currentPage: pg.pageAt(flick.contentY + pg.insetTop + pg.viewH * 0.35)
  onCurrentPageChanged: if (pg.ready && pg.placed) pg.moved({ page: pg.currentPage })
  // only the pages near the view are drawn — a screenful either side
  readonly property int firstNear: Math.max(0, pg.pageAt(flick.contentY - flick.height))
  readonly property int lastNear: { const r = pg.lay.rows[M.rowAt(pg.tops, flick.contentY + flick.height * 2)]; return r ? r[r.length - 1] : 0; }

  // ── THE CONTENTS, flattened for the sidebar: [{ label, depth, where }] ──
  readonly property var outline: {
    void pg.outlineRev;
    const out = [];
    const walk = (parent, depth) => {
      const n = bookmarks.rowCount(parent);
      for (let i = 0; i < n && out.length < 2000; ++i) {
        const ix = bookmarks.index(i, 0, parent);
        out.push({
          label: bookmarks.data(ix, PdfBookmarkModel.Title) || "",
          depth: depth,
          where: { page: bookmarks.data(ix, PdfBookmarkModel.Page) || 0 }
        });
        walk(ix, depth + 1);
      }
    };
    walk(bookmarks.index(-1, -1), 0);
    return out;
  }
  property int outlineRev: 0
  PdfBookmarkModel {
    id: bookmarks
    document: doc
    onModelReset: pg.outlineRev++
    onRowsInserted: pg.outlineRev++
  }

  // ── FIND ───────────────────────────────────────────────────────────────
  // the hits of the last find: [{ where, snippet, n }] — read when the
  // search model says it changed, not as a binding over it (reading its
  // rows from inside a binding looped: the model updates as it is read)
  property var hits: []
  property string findWords: ""
  function readHits() {
    const m = search, out = [];
    for (let i = 0; i < m.rowCount(); ++i) {
      const ix = m.index(i, 0);
      out.push({
        where: { page: m.data(ix, PdfSearchModel.Page) },
        snippet: (m.data(ix, PdfSearchModel.ContextBefore) || "") + pg.findWords + (m.data(ix, PdfSearchModel.ContextAfter) || ""),
        n: i
      });
    }
    pg.hits = out;
  }
  Timer { id: hitsSoon; interval: 60; onTriggered: pg.readHits() }
  PdfSearchModel {
    id: search
    document: doc
    // the current hit: its page, and the words in the upper third
    onCurrentResultChanged: pg.showCurrentHit()
  }
  // its count is a revision this import does not declare: listened to here
  Connections {
    target: search
    ignoreUnknownSignals: true
    function onCountChanged() { hitsSoon.restart(); }
    function onModelReset() { hitsSoon.restart(); }
    function onRowsInserted() { hitsSoon.restart(); }
  }
  function showCurrentHit() {
    const l = search.currentResultLink;
    if (!l || l.page < 0) return;
    const r = l.rectangles && l.rectangles.length > 0 ? l.rectangles[0] : null;
    pg.show(l.page, r ? Math.max(1, r.y * pg.zoom) : 0, r ? (r.x + r.width / 2) * pg.zoom : -1);
  }
  function find(words) { pg.findWords = words; search.searchString = words; }
  function findNext() { if (search.count > 0) search.currentResult = (search.currentResult + 1) % search.count; }
  function findPrev() { if (search.count > 0) search.currentResult = (search.currentResult - 1 + search.count) % search.count; }
  function showHit(h) { if (!h) return; if (search.currentResult === h.n) pg.showCurrentHit(); else search.currentResult = h.n; }

  // ── THE SELECTION ──────────────────────────────────────────────────────
  // One page's at a time: starting one on another page clears the last.
  property Item selOwner: null
  function copy() { if (pg.selOwner) pg.selOwner.copyOut(); }

  // ── GOING PLACES ───────────────────────────────────────────────────────
  // page p, `dy` pixels into it at the view's upper third (0: its top a
  // margin under the view's), and `cx` across it centered when given
  function show(p, dy, cx) {
    if (!pg.ready || pg.sizes.length === 0) return;
    p = Math.max(0, Math.min(pg.sizes.length - 1, p));
    flick.elastic.halt(flick);
    const r = pg.lay.rects[p];
    const y = dy > 0 ? r.y + dy - pg.insetTop - pg.viewH / 3 : pg.tops[pg.rowOf(p)] - pg.pad - pg.insetTop;
    flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, y));
    if (cx >= 0) flick.contentX = Math.max(0, Math.min(flick.contentWidth - flick.width, r.x + cx - pg.viewW / 2));
  }
  function goTo(w) { if (w && w.page !== undefined) pg.show(w.page, 0, -1); }
  // a row at a time: one page, or the two side by side
  function step(d) {
    const row = pg.lay.rows[Math.max(0, Math.min(pg.lay.rows.length - 1, pg.rowOf(pg.currentPage) + d))];
    if (row) pg.goTo({ page: row[0] });
  }

  // ── THE SIZE ───────────────────────────────────────────────────────────
  // the place you are reading stays where it was on screen
  function setZoom(z) {
    z = Math.max(0.25, Math.min(6, z));
    if (!pg.ready || pg.sizes.length === 0) { pg.zoom = z; return; }
    const anchorY = flick.contentY + flick.height * 0.35;
    const p = pg.pageAt(anchorY);
    const frac = (anchorY - pg.lay.rects[p].y) / Math.max(1, pg.sizes[p].height * pg.zoom);
    const fx = (flick.contentX + flick.width / 2) / Math.max(1, flick.contentWidth);
    flick.elastic.halt(flick);
    pg.zoom = z;
    flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height,
      pg.lay.rects[p].y + frac * pg.sizes[p].height * pg.zoom - flick.height * 0.35));
    flick.contentX = Math.max(0, Math.min(flick.contentWidth - flick.width, fx * flick.contentWidth - flick.width / 2));
  }
  function zoomBy(f) {
    pg.setZoom(pg.zoom * f);
    pg.fitting = "";
    pg.zoomChosen(Math.round(pg.zoom * 100) / 100);
  }
  function fitZoom(mode) {
    if (pg.sizes.length === 0) return 1;
    return M.fitZoom(pg.sizes, pg.spread, mode, pg.rowOf(pg.currentPage), pg.pad, pg.gap, pg.viewW, pg.viewH);
  }
  // a spread chosen: the same page in view, at the fit asked for
  // (a timer, not callLater: it goes with this item if the book closes first)
  onSpreadChanged: if (pg.placed) {
    respread.page = pg.currentPage;
    if (pg.fitting !== "") pg.zoom = pg.fitZoom(pg.fitting);
    respread.restart();
  }
  Timer { id: respread; interval: 0; property int page: 0; onTriggered: pg.show(respread.page, 0, -1) }
  function fit(mode) {
    pg.fitting = mode;
    pg.setZoom(pg.fitZoom(mode));
    pg.zoomChosen(mode);
  }

  PdfDocument {
    id: doc
    source: pg.path !== "" ? Strings.fileUrl(pg.path) : ""
    onStatusChanged: {
      if (doc.status === PdfDocument.Error) pg.failed(doc.error === PdfDocument.IncorrectPassword
        ? "This PDF is locked with a password" : "This PDF could not be read");
      if (doc.status === PdfDocument.Ready) settle.restart();
    }
  }
  // the size and the place once the view has its size: a jump made before
  // the pages are counted lands on page 0
  property bool placed: false
  Timer {
    id: settle
    interval: 30
    onTriggered: {
      pg.zoom = typeof pg.zoomMode === "number" ? pg.zoomMode : pg.fitZoom(pg.zoomMode);
      if (pg.startAt) pg.show(pg.startAt.page || 0, 0, -1);
      pg.placed = true;
    }
  }
  // a window resized (or the sidebar opened) keeps fitting the way it was asked to
  onWidthChanged: if (pg.placed && pg.fitting !== "") refit.restart()
  onInsetRightChanged: if (pg.placed && pg.fitting !== "") refit.restart()
  onInsetTopChanged: if (pg.placed && pg.fitting === "page") refit.restart()
  onHeightChanged: if (pg.placed && pg.fitting === "page") refit.restart()
  Timer { id: refit; interval: 120; onTriggered: if (pg.fitting !== "") pg.setZoom(pg.fitZoom(pg.fitting)) }

  // ── FOR THE SIDEBAR: a page, small ─────────────────────────────────────
  // MinervaSide cannot import QtQuick.Pdf (it would not compile without
  // it), so it is handed this and fills in `pageIx`.
  function aspectOf(i) { const s = pg.sizes[i]; return s ? s.height / Math.max(1, s.width) : 1.414; }
  readonly property Component thumb: Component {
    Rectangle {
      readonly property int pageIx: parent ? parent.pageIx || 0 : 0
      color: pg.paperInk
      PdfPageImage {
        anchors.fill: parent
        document: doc
        currentFrame: parent.pageIx
        asynchronous: true
        fillMode: Image.PreserveAspectFit
        sourceSize.width: Math.round(parent.width * Screen.devicePixelRatio)
        layer.enabled: pg.look.tone
        layer.effect: toneComp
      }
    }
  }
  // the page's colours, laid over the printed page (morpheus/shaders/pagetone)
  Component {
    id: toneComp
    ShaderEffect {
      property color lo: pg.look.ink
      property color hi: pg.look.bg
      property real chroma: 0.55
      fragmentShader: Qt.resolvedUrl("../morpheus/shaders/pagetone.frag.qsb")
    }
  }

  // ── A PAGE'S WORDS, for reading aloud ──────────────────────────────────
  // all of page i's text, by a selection of the whole page made and let go
  Component { id: wholeComp; PdfSelection { document: doc; visible: false } }
  function pageText(i) {
    if (!pg.ready || i < 0 || i >= doc.pageCount) return "";
    const s = wholeComp.createObject(pg, { page: i });
    s.selectAll();
    const t = s.text;
    s.destroy();
    return t;
  }

  // ── THE SELECTION, AS A HIGHLIGHT ──────────────────────────────────────
  // { where, text, quads }: its page, its words and its outline in points
  function selectionMark() {
    const o = pg.selOwner;
    if (!o || pg.selected === "") return null;
    const quads = [];
    const g = o.geometry();
    for (let i = 0; i < g.length; ++i) {
      const poly = [];
      for (let k = 0; k < g[i].length; ++k) poly.push([g[i][k].x, g[i][k].y]);
      quads.push(poly);
    }
    return { where: { page: o.pageIx }, text: pg.selected, quads: quads };
  }
  function clearSelection() { if (pg.selOwner) pg.selOwner.clearSel(); pg.selected = ""; }

  // ── THE VIEW ───────────────────────────────────────────────────────────
  // stops at the sidebar: only the pages themselves run on under it, for
  // its frost (MinervaWindow's sideBox)
  Rectangle { anchors.fill: parent; anchors.rightMargin: pg.insetRight; color: pg.look.tone ? Qt.darker(pg.look.bg, 1.25) : Zenon.ground }
  Flickable {
    id: flick
    anchors.fill: parent
    // the wheel is ElasticScroll's; a drag is a selection's, or, zoomed in
    // past the view, a pan's and shift+drag the selection's (user,
    // 2026-10-21)
    interactive: false
    boundsBehavior: Flickable.StopAtBounds
    contentWidth: pg.lay.contentW + pg.insetRight
    contentHeight: pg.lay.contentH + pg.insetBottom
    readonly property Elastic elastic: wheel.elastic
    readonly property bool wide: flick.contentWidth > flick.width + 1

    DragPan { flick: flick; on: flick.wide }
    Repeater {
      model: pg.pageCount
      delegate: Item {
        id: holder
        required property int index
        readonly property size pts: pg.sizes[holder.index] || Qt.size(1, 1)
        readonly property var box: pg.lay.rects[holder.index] || ({ x: 0, y: 0, w: 1, h: 1 })
        x: holder.box.x
        y: holder.box.y
        width: holder.box.w
        height: holder.box.h
        // the paper, even before it is drawn: the pages never jump
        Rectangle { anchors.fill: parent; color: pg.paperInk; border.width: 1; border.color: Zenon.border }
        Loader {
          anchors.fill: parent
          active: holder.index >= pg.firstNear && holder.index <= pg.lastNear
          sourceComponent: pageComp
          property int pageIx: holder.index
          property size pts: holder.pts
        }
      }
    }
  }

  Component {
    id: pageComp
    Item {
      id: paper
      readonly property int pageIx: parent.pageIx
      readonly property real pageScale: paper.width / Math.max(1, parent.pts.width)
      function copyOut() { sel.copyToClipboard(); }
      function geometry() { return sel.geometry; }

      PdfPageImage {
        id: image
        anchors.fill: parent
        document: doc
        currentFrame: paper.pageIx
        asynchronous: true
        fillMode: Image.PreserveAspectFit
        // drawn at the size it is shown; a zoom redraws it (the old picture,
        // stretched, until the new one is in)
        sourceSize.width: Math.round(paper.width * Screen.devicePixelRatio)
        cache: false
        onSourceSizeChanged: paper.lightHits()
        layer.enabled: pg.look.tone
        layer.effect: toneComp
      }
      // your highlights on this page, in their colours; a click on one
      // says which (the sidebar shows it)
      Repeater {
        model: image.status === Image.Ready ? pg.highlights.filter((h) => h.where.page === paper.pageIx && h.quads) : []
        delegate: Shape {
          id: hiShape
          required property var modelData
          anchors.fill: parent
          containsMode: Shape.FillContains
          ShapePath {
            strokeWidth: -1
            fillColor: Zenon.alpha(pg.inks[hiShape.modelData.color] || Zenon.yellow, 0.38)
            scale: Qt.size(paper.pageScale, paper.pageScale)
            PathMultiline { paths: hiShape.modelData.quads.map((poly) => poly.map((pt) => Qt.point(pt[0], pt[1]))) }
          }
          TapHandler { onTapped: pg.hiTapped(hiShape.modelData.id) }
          // what you wrote on it, a corner mark at its start
          Rectangle {
            visible: hiShape.modelData.comment !== ""
            readonly property var first: hiShape.modelData.quads[0][0]
            x: first[0] * paper.pageScale - 5
            y: first[1] * paper.pageScale - 5
            width: 10
            height: 10
            radius: 5
            color: pg.inks[hiShape.modelData.color] || Zenon.yellow
            border.width: 1
            border.color: Zenon.alpha(Zenon.black, 0.4)
          }
        }
      }
      Shape {
        anchors.fill: parent
        visible: image.status === Image.Ready
        ShapePath {
          strokeWidth: -1
          fillColor: Zenon.alpha(Zenon.yellow, 0.35)
          scale: Qt.size(paper.pageScale, paper.pageScale)
          PathMultiline { id: hiHits }
        }
        ShapePath {
          strokeWidth: -1
          fillColor: Zenon.alpha(Zenon.cyan, 0.35)
          scale: Qt.size(paper.pageScale, paper.pageScale)
          PathMultiline { paths: sel.geometry }
        }
      }
      Connections {
        target: search
        function onCurrentPageBoundingPolygonsChanged() { paper.lightHits(); }
        function onCountChanged() { paper.lightHits(); }
      }
      // a binding would not be told when the words change on another page
      function lightHits() { if (hiHits) hiHits.paths = search.boundingPolygonsOnPage(paper.pageIx); }
      Component.onCompleted: paper.lightHits()
      // the hit you are on, outlined
      Shape {
        anchors.fill: parent
        visible: image.status === Image.Ready && search.currentPage === paper.pageIx
        ShapePath {
          strokeWidth: 2
          strokeColor: Zenon.cyan
          fillColor: "transparent"
          scale: Qt.size(paper.pageScale, paper.pageScale)
          PathMultiline { paths: search.currentResultBoundingPolygons }
        }
      }

      DragHandler {
        id: drag
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.Stylus
        target: null
        acceptedModifiers: flick.wide ? Qt.ShiftModifier : Qt.KeyboardModifierMask
        onActiveChanged: if (drag.active) {
          if (pg.selOwner && pg.selOwner !== paper) pg.selOwner.clearSel();
          pg.selOwner = paper;
        }
      }
      TapHandler {
        id: tap
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.Stylus
        onTapped: if (pg.selOwner === paper) { sel.clear(); pg.selected = ""; }
      }
      TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: (ev) => { const p = paper.mapToItem(pg, ev.position.x, ev.position.y); pg.menuAsked(p.x, p.y); }
      }
      function clearSel() { sel.clear(); }
      PdfSelection {
        id: sel
        anchors.fill: parent
        document: doc
        page: paper.pageIx
        renderScale: paper.pageScale
        from: drag.centroid.pressPosition
        to: drag.centroid.position
        hold: !drag.active && !tap.pressed
        onTextChanged: if (pg.selOwner === paper) pg.selected = sel.text
      }
      Component.onDestruction: if (pg.selOwner === paper) pg.selOwner = null

      // a link: another page of this book, or out to the browser
      Repeater {
        model: PdfLinkModel {
          document: doc
          page: paper.pageIx
        }
        delegate: Item {
          required property rect rectangle
          required property int page
          required property point location
          required property url url
          x: rectangle.x * paper.pageScale
          y: rectangle.y * paper.pageScale
          width: rectangle.width * paper.pageScale
          height: rectangle.height * paper.pageScale
          visible: image.status === Image.Ready
          // the hand only for the web (the suite's cursor rule)
          HoverHandler { cursorShape: parent.page < 0 ? Qt.PointingHandCursor : Qt.ArrowCursor }
          TapHandler {
            onTapped: {
              if (parent.page >= 0) pg.show(parent.page, Math.max(0, parent.location.y) * pg.zoom, -1);
              else Strings.openLink(parent.url.toString());
            }
          }
        }
      }
    }
  }

  // ── THE SUITE'S SCROLL ─────────────────────────────────────────────────
  // Ctrl+wheel stays the zoom it was.
  ElasticScroll {
    id: wheel
    anchors.fill: flick
    view: flick
    intercept: (w) => {
      if (!(w.modifiers & Qt.ControlModifier)) return false;
      pg.zoomBy(w.angleDelta.y > 0 ? 1.1 : 1 / 1.1);
      return true;
    }
  }
  Scrollbar { flick: flick; anchors.right: parent.right; anchors.rightMargin: pg.insetRight; anchors.top: parent.top; anchors.topMargin: pg.insetTop; anchors.bottom: parent.bottom; anchors.bottomMargin: pg.insetBottom }
  Scrollbar {
    flick: flick
    horizontal: true
    visible: flick.contentWidth > flick.width + 1
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.rightMargin: pg.insetRight
    anchors.bottom: parent.bottom
    anchors.bottomMargin: pg.insetBottom
  }
}
