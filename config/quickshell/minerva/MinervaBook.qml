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
// turns to the next; links between chapters are followed.

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
  signal moved(var where)
  signal failed(string why)

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
      edit.text = M.chapterHtml(chapterFile.text(), Zenon.ink, Zenon.link, bk.settings.lineHeight);
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
    const pageH = flick.height * 0.9;
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
  // a theme change re-sets the chapter in the new colours, where it was
  Connections {
    target: Zenon
    function onInkChanged() {
      if (!chapterFile.got) return;
      const f = bk.frac;
      edit.text = M.chapterHtml(chapterFile.text(), Zenon.ink, Zenon.link, bk.settings.lineHeight);
      bk._then = { frac: f };
      place.restart();
    }
  }
  // the spacing changed: the chapter set again, where it was
  onSettingsChanged: if (chapterFile.got && edit.text !== "") {
    const html = M.chapterHtml(chapterFile.text(), Zenon.ink, Zenon.link, bk.settings.lineHeight);
    if (html !== edit.text) { const f = bk.frac; edit.text = html; bk._then = { frac: f }; place.restart(); }
  }
  // where you are, said as it changes (the library keeps it)
  onWhereChanged: if (bk.ready) movedSoon.restart()
  Timer { id: movedSoon; interval: 400; onTriggered: bk.moved(bk.where) }

  // ── THE PAGE ───────────────────────────────────────────────────────────
  Rectangle { anchors.fill: parent; color: Zenon.layerBg }
  Flickable {
    id: flick
    anchors.fill: parent
    contentWidth: width
    contentHeight: page.height + 120
    boundsBehavior: Flickable.StopAtBounds
    clip: true
    Item {
      id: page
      width: Math.min(flick.width - 80, bk.settings.width)
      x: (flick.width - width) / 2
      y: 48
      height: edit.contentHeight + 40
      TextEdit {
        id: edit
        width: parent.width
        readOnly: true
        selectByMouse: true
        textFormat: TextEdit.RichText
        wrapMode: TextEdit.Wrap
        color: Zenon.ink
        selectionColor: Zenon.alpha(Zenon.cyan, 0.45)
        selectedTextColor: Zenon.ink
        font.family: bk.settings.serif && bk.mgr ? bk.mgr.serifFace : Zenon.face
        font.pixelSize: bk.settings.fontSize
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
      color: nextPress.pressed ? Zenon.ink : Zenon.accentMuted
      font.family: Zenon.face
      font.weight: 600
      font.pixelSize: Zenon.px(15)
      MouseArea { id: nextPress; anchors.fill: parent; anchors.margins: -10; onClicked: bk.chapterBy(1) }
    }
  }
  ElasticScroll { anchors.fill: flick; view: flick }
  Scrollbar { flick: flick; anchors.right: flick.right; anchors.top: flick.top; anchors.bottom: flick.bottom }
}
