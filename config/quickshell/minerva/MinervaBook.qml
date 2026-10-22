// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// An EPUB in minerva: one chapter at a time, as core/epub.py rewrote it,
// set in the shell's colours on a measure you choose — a column of text
// down the middle of the page, not the page's whole width.
//
// The same face to the window as MinervaPdf: `where` ({ chapter, frac }),
// goTo(where), `outline`, find(words) and its hits, `selected`, and
// zoomBy (the type's size). Reaching the end of a chapter and going on
// turns to the next; links between chapters are followed. A plain text or
// a Markdown file comes here too, set by epub.py's `text` as a book.
//
// 2026-10-21: the page's colours (`look`, minerva.js themeOf), your
// highlights drawn behind their words (their span in the chapter's plain
// text, kept as where.start/end) and a click on one said (hiTapped), a
// right click asks for the menu, and the sentence being read aloud is lit
// (light(start, end)).

import QtQuick
import Quickshell.Io
import "../morpheus"
import "minerva.js" as M

Item {
  id: bk

  // epub.py's book.json, and the manager (for finding across chapters)
  property var book: null
  property var mgr: null
  property var startAt: null
  property var settings: M.defaults()
  // { bg, ink, link } — the page's colours
  property var look: ({ bg: Zenon.layerBg, ink: Zenon.ink, link: Zenon.link })
  property var highlights: []
  property var inks: ({})
  // the frosted head and the sidebar: the text runs on under both
  property real insetTop: 0
  property real insetRight: 0
  property real insetBottom: 0
  signal moved(var where)
  signal failed(string why)
  signal hiTapped(string id)
  signal menuAsked(real x, real y)
  // a chapter set and laid out (reading aloud goes on from here)
  signal chapterShown(int n)
  readonly property bool paged: false
  // what scrolls, for the window's frosted edges (ScrollEdge)
  readonly property Item view: flick

  property int chapter: -1
  readonly property bool ready: !!bk.book && bk.chapter >= 0
  readonly property int pageCount: bk.book ? bk.book.chapters.length : 0
  readonly property string title: bk.book ? bk.book.title : ""
  readonly property string author: bk.book ? bk.book.author : ""
  readonly property real frac: flick.contentHeight > flick.height
    ? Math.max(0, Math.min(1, flick.contentY / (flick.contentHeight - flick.height))) : 0
  readonly property var where: ({ chapter: Math.max(0, bk.chapter), frac: bk.frac })
  readonly property string selected: edit.selectedText
  readonly property var outline: !bk.book ? [] : bk.book.toc.map((t) => ({
    label: t.label, depth: t.depth, where: { chapter: t.chapter, frac: 0 }, anchor: t.anchor
  }))
  property var hits: []
  property string findWords: ""

  // ── TURNING TO A CHAPTER ───────────────────────────────────────────────
  // `then` once it is set and laid out: a place in it (frac, an anchor, a
  // hit's words)
  property var _then: null
  function show(n, then) {
    if (!bk.book || n < 0 || n >= bk.book.chapters.length) return;
    bk._then = then || null;
    if (n === bk.chapter && chapterFile.got) { place.restart(); return; }
    bk.chapter = n;
    chapterFile.path = bk.book.dir + "/ch/" + bk.book.chapters[n].file;
  }
  FileView {
    id: chapterFile
    property bool got: false
    blockLoading: true
    printErrors: false
    onPathChanged: chapterFile.got = false
    onLoaded: {
      chapterFile.got = true;
      edit.text = bk.html();
      flick.contentY = 0;
      place.restart();
    }
    onLoadFailed: bk.failed("A chapter of this book could not be read")
  }
  // laid out a beat after the text is set
  Timer {
    id: place
    interval: 40
    onTriggered: {
      const t = bk._then;
      bk._then = null;
      bk.layoutRev++;
      bk.chapterShown(bk.chapter);
      if (!t) return;
      if (t.frac !== undefined) flick.contentY = t.frac * Math.max(0, flick.contentHeight - flick.height);
      if (t.anchor) bk.toAnchor(t.anchor);
      if (t.words) bk.toWords(t.words, t.nth || 0);
    }
  }
  // the words in the chapter as set, to find a place by
  function plain() { return edit.getText(0, edit.length); }
  function scrollToPos(pos) {
    const r = edit.positionToRectangle(Math.max(0, pos));
    flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, page.y + r.y - flick.height / 3));
  }
  function toWords(words, nth) {
    const hay = bk.plain().toLowerCase(), q = String(words).toLowerCase();
    let at = -1;
    for (let i = 0; i <= nth; ++i) { at = hay.indexOf(q, at + 1); if (at < 0) break; }
    if (at < 0) at = hay.indexOf(q);
    if (at < 0) return;
    edit.select(at, at + q.length);
    bk.scrollToPos(at);
  }
  // an anchor: found by the words after it in the chapter's own text
  function toAnchor(name) {
    const src = chapterFile.text();
    const i = src.indexOf('<a name="' + name + '"></a>');
    if (i < 0) return;
    const after = src.slice(i).replace(/<[^>]*>/g, " ").replace(/&[a-z#0-9]+;/gi, " ").replace(/\s+/g, " ").trim().slice(0, 40);
    const at = after ? bk.plain().indexOf(after.split(" ").slice(0, 5).join(" ")) : -1;
    if (at >= 0) bk.scrollToPos(at);
  }

  function goTo(w) {
    if (!w) return;
    bk.show(Math.max(0, Math.min(bk.pageCount - 1, w.chapter || 0)), { frac: w.frac || 0, anchor: w.anchor || "" });
  }
  function step(d) {
    // a page's worth down; past the end, the next chapter
    const pageH = (flick.height - bk.insetTop - bk.insetBottom) * 0.9;
    if (d > 0) {
      if (flick.contentY + flick.height >= flick.contentHeight - 2) bk.show(bk.chapter + 1, { frac: 0 });
      else flick.contentY = Math.min(flick.contentHeight - flick.height, flick.contentY + pageH);
    } else {
      if (flick.contentY <= 1) bk.show(bk.chapter - 1, { frac: 1 });
      else flick.contentY = Math.max(0, flick.contentY - pageH);
    }
  }
  function chapterBy(d) { bk.show(bk.chapter + d, { frac: 0 }); }

  // ── FINDING ────────────────────────────────────────────────────────────
  // across every chapter, by core/epub.py's find
  function find(words) {
    bk.findWords = words;
    if (!bk.mgr || !bk.book || words.trim() === "") { bk.hits = []; return; }
    bk.mgr.findInBook(bk.book.dir, words, (list) => {
      // the nth hit in its chapter, so showing it finds the right one
      const seen = {};
      bk.hits = list.map((h) => {
        const nth = seen[h.chapter] || 0;
        seen[h.chapter] = nth + 1;
        return { where: { chapter: h.chapter, frac: 0 }, snippet: h.snippet, words: words, nth: nth };
      });
    });
  }
  property int hitAt: -1
  function showHit(h) { if (h) bk.show(h.where.chapter, { words: h.words, nth: h.nth }); }
  function findNext() { if (bk.hits.length) { bk.hitAt = (bk.hitAt + 1) % bk.hits.length; bk.showHit(bk.hits[bk.hitAt]); } }
  function findPrev() { if (bk.hits.length) { bk.hitAt = (bk.hitAt - 1 + bk.hits.length) % bk.hits.length; bk.showHit(bk.hits[bk.hitAt]); } }
  function copy() { edit.copy(); }
  function zoomBy(f) {
    if (bk.mgr) bk.mgr.setSetting("fontSize", Math.round(bk.settings.fontSize * (f > 1 ? 1.08 : 1 / 1.08)));
  }
  function fit(mode) {}

  onBookChanged: if (bk.book && bk.book.chapters.length > 0) {
    const s = bk.startAt || { chapter: 0, frac: 0 };
    bk.chapter = -1;
    bk.show(Math.max(0, Math.min(bk.book.chapters.length - 1, s.chapter || 0)), { frac: s.frac || 0 });
  }
  function html() { return M.chapterHtml(chapterFile.text(), bk.look.ink, bk.look.link, bk.settings.lineHeight); }
  // the colours or the spacing changed (a theme, the shell's or the
  // page's): the chapter set again, where it was
  function reset() {
    if (!chapterFile.got || edit.text === "") return;
    const h = bk.html();
    if (h !== edit.text) { const f = bk.frac; edit.text = h; bk._then = { frac: f }; place.restart(); }
  }
  onLookChanged: bk.reset()
  onSettingsChanged: bk.reset()

  // ── WORDS ON THE PAGE, BOXED ───────────────────────────────────────────
  // a span of the chapter as the boxes its lines make, in the page's
  // coordinates — a highlight's, or the sentence read aloud. Bumped as the
  // text is laid out again (a size, a measure, a chapter).
  property int layoutRev: 0
  function boxes(start, end) {
    void bk.layoutRev;
    const out = [];
    start = Math.max(0, start); end = Math.min(edit.length, end);
    if (end <= start || end - start > 6000) return out;
    let cur = null;
    for (let i = start; i < end; ++i) {
      // a line's break is no word: a span ending on one stops at the word
      if (/[\n\u2029\u2028]/.test(edit.getText(i, i + 1))) continue;
      const a = edit.positionToRectangle(i), b = edit.positionToRectangle(i + 1);
      const right = Math.abs(b.y - a.y) < 1 ? b.x : a.x + Math.max(4, a.height * 0.3);
      if (cur && Math.abs(a.y - cur.y) < 1) cur.r = Math.max(cur.r, right);
      else { if (cur) out.push(cur); cur = { x: a.x, y: a.y, r: right, h: a.height }; }
    }
    if (cur) out.push(cur);
    return out.map((c) => ({ x: c.x, y: c.y, w: Math.max(2, c.r - c.x), h: c.h }));
  }
  readonly property var shownHighlights: bk.highlights.filter((h) => h.where.chapter === bk.chapter && h.where.end > h.where.start)
  // the selection, as a highlight: { where, text }
  function selectionMark() {
    if (edit.selectedText === "") return null;
    return { where: { chapter: bk.chapter, frac: bk.frac, start: edit.selectionStart, end: edit.selectionEnd }, text: edit.selectedText };
  }
  function clearSelection() { edit.deselect(); }

  // ── READ ALOUD ─────────────────────────────────────────────────────────
  // the chapter's words, where the view starts in them, and the sentence lit
  function plainText() { return bk.plain(); }
  function topPos() { return Math.max(0, edit.positionAt(0, flick.contentY - page.y + 8)); }
  property var lit: null
  function light(start, end) {
    bk.lit = start < end ? { start: start, end: end } : null;
    if (!bk.lit) return;
    const r = edit.positionToRectangle(start);
    const top = page.y + r.y;
    if (top < flick.contentY + bk.insetTop + 40 || top > flick.contentY + flick.height * 0.7)
      flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, top - flick.height / 3));
  }
  // where you are, said as it changes (the library keeps it)
  onWhereChanged: if (bk.ready) movedSoon.restart()
  Timer { id: movedSoon; interval: 400; onTriggered: bk.moved(bk.where) }

  // ── THE PAGE ───────────────────────────────────────────────────────────
  // stops at the sidebar: only the pages themselves run on under it, for
  // its frost (MinervaWindow's sideBox)
  Rectangle { anchors.fill: parent; anchors.rightMargin: bk.insetRight; color: bk.look.bg }
  Flickable {
    id: flick
    anchors.fill: parent
    contentWidth: width
    contentHeight: page.height + 120 + bk.insetTop + bk.insetBottom
    boundsBehavior: Flickable.StopAtBounds
    clip: true
    Item {
      id: page
      width: Math.min(flick.width - bk.insetRight - 80, bk.settings.width)
      x: (flick.width - bk.insetRight - width) / 2
      y: 48 + bk.insetTop
      height: edit.contentHeight + 40
      // behind the words: your highlights, then the sentence read aloud
      Repeater {
        model: bk.shownHighlights
        delegate: Item {
          id: hl
          required property var modelData
          Repeater {
            model: bk.boxes(hl.modelData.where.start, hl.modelData.where.end)
            delegate: Rectangle {
              required property var modelData
              x: modelData.x - 1
              y: modelData.y
              width: modelData.w + 2
              height: modelData.h
              radius: Zenon.rad(3)
              color: Zenon.alpha(bk.inks[hl.modelData.color] || Zenon.yellow, 0.34)
            }
          }
          // what you wrote on it: a dot in the margin by its first line
          Rectangle {
            visible: hl.modelData.comment !== ""
            readonly property var first: bk.boxes(hl.modelData.where.start, hl.modelData.where.start + 1)[0] || ({ y: -100, h: 0 })
            x: -18
            y: first.y + first.h / 2 - 4
            width: 8
            height: 8
            radius: 4
            color: bk.inks[hl.modelData.color] || Zenon.yellow
          }
        }
      }
      Repeater {
        model: bk.lit ? bk.boxes(bk.lit.start, bk.lit.end) : []
        delegate: Rectangle {
          required property var modelData
          x: modelData.x - 2
          y: modelData.y
          width: modelData.w + 4
          height: modelData.h
          radius: Zenon.rad(3)
          color: Zenon.alpha(Zenon.cyan, 0.22)
          border.width: 1
          border.color: Zenon.alpha(Zenon.cyan, 0.5)
        }
      }
      TextEdit {
        id: edit
        width: parent.width
        readOnly: true
        selectByMouse: true
        textFormat: TextEdit.RichText
        wrapMode: TextEdit.Wrap
        color: bk.look.ink
        selectionColor: Zenon.alpha(Zenon.cyan, 0.45)
        selectedTextColor: bk.look.ink
        font.family: bk.settings.serif && bk.mgr ? bk.mgr.serifFace : Zenon.face
        font.pixelSize: bk.settings.fontSize
        onContentHeightChanged: bk.layoutRev++
        onWidthChanged: bk.layoutRev++
        // a click on a highlight (not a drag): which one
        TapHandler {
          onTapped: (ev) => {
            if (edit.selectedText !== "") return;
            const at = edit.positionAt(ev.position.x, ev.position.y);
            const h = bk.shownHighlights.find((m) => at >= m.where.start && at < m.where.end);
            if (h) bk.hiTapped(h.id);
          }
        }
        TapHandler {
          acceptedButtons: Qt.RightButton
          onTapped: (ev) => { const p = edit.mapToItem(bk, ev.position.x, ev.position.y); bk.menuAsked(p.x, p.y); }
        }
        onLinkActivated: (link) => {
          const to = M.internalLink(link);
          if (to) bk.show(to.chapter, { frac: 0, anchor: to.anchor });
          else if (/^(https?|mailto):/.test(link)) Qt.openUrlExternally(link);
        }
      }
    }
    // the end of a chapter says what comes next, and goes there on a click
    Text {
      x: page.x
      y: page.y + page.height + 10
      width: page.width
      horizontalAlignment: Text.AlignHCenter
      visible: bk.ready && bk.chapter < bk.pageCount - 1
      text: bk.ready && bk.chapter < bk.pageCount - 1
        ? "Next: " + (bk.book.chapters[bk.chapter + 1].title || "Chapter " + (bk.chapter + 2)) + "  ›" : ""
      // (the ink as a colour again: through minerva.js it can come back a string)
      color: nextPress.pressed ? bk.look.ink : Zenon.alpha(Qt.lighter(bk.look.ink, 1), 0.6)
      font.family: Zenon.face
      font.weight: 600
      font.pixelSize: Zenon.px(15)
      MouseArea { id: nextPress; anchors.fill: parent; anchors.margins: -10; onClicked: bk.chapterBy(1) }
    }
  }
  ElasticScroll { anchors.fill: flick; view: flick }
  Scrollbar { flick: flick; anchors.right: flick.right; anchors.rightMargin: bk.insetRight; anchors.top: flick.top; anchors.topMargin: bk.insetTop; anchors.bottom: flick.bottom; anchors.bottomMargin: bk.insetBottom }
}
