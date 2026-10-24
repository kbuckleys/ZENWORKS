// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// MINERVA'S WINDOW — the library, or a book being read.
//
//   the library   every book opened or found, the one to go on with over
//                 the rest (MinervaLibrary)
//   reading       the book (MinervaPdf, MinervaBook — an EPUB or a text —
//                 or MinervaComic: the same face to this window), a sidebar
//                 of its pages, contents, your bookmarks, your highlights
//                 and a find's hits (MinervaSide), and a head that says
//                 where you are
//
// A highlight is the words selected, in a colour, with what you write on
// it, kept with the book and filed into Clio, one note per book
// ("Highlights · <title>"); a note of your own on a page goes there too.
// The place you were is kept as you read, and a book opens where you left
// it. The time you spend in it is counted (Info).
//
// 2026-10-21 round (user: "UI/UX polish as well as more features"): right
// clicks are menus everywhere (nothing is removed by one any more, and a
// removal is undone with ctrl z); the selection gets a bar of its own —
// colours, a note, Lexi's look-up and translation, copy; the page's colours
// and a two-page spread are in the Aa card; focus mode hides everything but
// the page; reading aloud; shelves, states, sorting and watched directories
// in the library; Info for a book and for the library's reading.
//
//   ← → / page keys / space   turn       ctrl f   find (return: the next)
//   ctrl d   bookmark here               ctrl h   highlight (ctrl 1-5: a colour)
//   ctrl n   a note on this page         ctrl k   look up · ctrl t translate
//   ctrl r   read aloud                  f11      focus mode
//   ctrl + − 0   size                    ctrl b   the sidebar
//   ctrl i   Info                        ctrl z   undo (ctrl shift z: redo)
//   ctrl l   the library                 ctrl o   open a file
//   esc      a card, the find, focus, then the library, then closes

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "../morpheus"
import "../morpheus/undo"
import "../morpheus/hypr.js" as Hypr
import "../morpheus/controls" as Ctl
import "../terminus"
import "minerva.js" as M
import "../morpheus/room.js" as Room

FloatingWindow {
  id: mw
  title: "minerva"
  color: Zenon.alpha(Zenon.layerBg, 0)
  minimumSize: Qt.size(820, 560)

  property var mgr: null
  // the window's tooltip, for what is loaded by file (MinervaTools)
  readonly property var tipRef: tip
  // the bar the library's rows run on under (its ScrollEdges)
  readonly property Item footItem: foot
  readonly property bool sideOpen: mw.mode === "reading" && mw.settings.sidebar && !mw.focusMode

  onVisibleChanged: if (!mw.visible) Qt.callLater(() => { mw.keepSize(); mw.keep(); voice.stop(); if (mw.focusMode) mw.setFocus(false); if (mw.mgr) mw.mgr.retire(mw); mw.destroy(); })
  onClosed: mw.visible = false

  // ── ITS OWN SIZE, LESS THE SIDEBAR (user, 2026-10-21) ──────────────────
  // Minerva opens on the library, where there is no sidebar, so the size to
  // come back at is the window's less the room the sidebar took. Hyprland's
  // persistent_size could not be told that: it kept the size of the window
  // as it closed, and giving the room back first did not help (the close
  // landed mid-animation and the wide size was kept anyway). So Minerva
  // keeps its own (settings.winSize) and hypr/lua/rules.lua no longer keeps
  // one for it. Only a floating window's: a tiled, maximized or fullscreen
  // one is the layout's size, not ours.
  implicitWidth: mw.settings.winSize ? mw.settings.winSize[0] : 1280
  implicitHeight: mw.settings.winSize ? mw.settings.winSize[1] : 880
  function keepSize() {
    if (!mw.mgr || sideLayout.laidOut || mw.focusMode) return;
    mw.mgr.setSetting("winSize", [Math.round(mw.width - Math.max(0, mw.sideGrew)), Math.round(mw.height)]);
  }

  // lower (user, 2026-10-21): the tools sit in it now, not under it
  readonly property int headH: 48
  readonly property int sideW: 300
  readonly property var settings: mw.mgr ? mw.mgr.settings : M.defaults()

  // ── WHAT IS OPEN ───────────────────────────────────────────────────────
  property string mode: "library"     // library · reading
  property string path: ""
  readonly property string kind: M.kindOf(mw.path)
  readonly property bool paged: M.paged(mw.kind)
  readonly property var book: mw.mgr && mw.path !== "" ? mw.mgr.bookOf(mw.path) : null
  readonly property var page: viewLoader.item
  property var epub: null             // epub.py's book.json, for an EPUB or a text
  property var comic: null            // books.py's comic.json
  property string failure: ""
  readonly property bool needsPdf: mw.kind === "pdf" && !!mw.mgr && mw.mgr.pdfKnown && !mw.mgr.pdfReady
  readonly property var chapters: mw.epub ? mw.epub.chapters : []

  // the page's colours, and the highlights' by name
  // NIGHT IS THE THEME'S DARK SIDE (user, 2026-10-22: it should follow the
  // theme's tone): a dark theme's own ground, ink and link; a light theme's
  // ink and ground the other way round, so night stays dark in its tones
  readonly property var nightTone: Zenon.light
    ? { bg: Zenon.alpha(Zenon.ink, 1), ink: Zenon.alpha(Zenon.ground, 1), link: Qt.lighter(Zenon.link, 1.6) }
    : { bg: Zenon.alpha(Zenon.ground, 1), ink: Zenon.ink, link: Zenon.link }
  readonly property var look: M.themeOf(mw.settings.theme, mw.kind, { bg: Zenon.layerBg, ink: Zenon.ink, link: Zenon.link, night: mw.nightTone })
  readonly property var inks: ({ yellow: Zenon.yellow, green: Zenon.green, blue: Zenon.blue, pink: Zenon.pink, magenta: Zenon.magenta })
  readonly property var colorNames: ({ yellow: "Yellow", green: "Green", blue: "Blue", pink: "Pink", magenta: "Purple" })
  property string hiColor: "yellow"

  function read(p) {
    mw.keep();
    mw.failure = "";
    mw.epub = null;
    mw.comic = null;
    mw.findText = "";
    findField.text = "";
    lookup.shown = false;
    mw.path = p;
    mw.mode = "reading";
    mw.mgr.touch(p, { opened: Date.now() });
    viewLoader.sourceComponent = undefined;
    // a PDF or a comic opens on its pages, a book on its contents
    side.tab = mw.paged ? "pages" : "contents";
    if (mw.kind === "epub" || mw.kind === "text") {
      const opened = (b, why) => {
        if (mw.path !== p) return;
        if (!b) { mw.failure = why || "This book could not be read"; return; }
        mw.epub = b;
        mw.mgr.change(p, Object.assign({ title: b.title || M.nameOf(p) }, b.author ? { author: b.author } : {}, b.cover ? { cover: b.cover } : {}));
        viewLoader.sourceComponent = bookComp;
      };
      if (mw.kind === "epub") mw.mgr.openEpub(p, opened); else mw.mgr.openText(p, opened);
    } else if (mw.kind === "comic") {
      mw.mgr.openComic(p, (c, why) => {
        if (mw.path !== p) return;
        if (!c) { mw.failure = why || "This comic could not be read"; return; }
        mw.comic = c;
        if (c.pages.length > 0 && !(mw.book && mw.book.cover)) mw.mgr.change(p, { cover: "file://" + c.pages[0].file });
        viewLoader.sourceComponent = comicComp;
      });
    } else if (mw.mgr.pdfReady) {
      viewLoader.setSource("MinervaPdf.qml", { path: p, startAt: mw.book ? mw.book.pos : null, zoomMode: mw.settings.zoom });
    }
    mw.stir();
    keys.forceActiveFocus();
  }
  // Qt PDF arriving (installed from here) opens the PDF that asked for it
  Connections {
    target: mw.mgr
    function onPdfReadyChanged() { if (mw.mgr.pdfReady && mw.mode === "reading" && mw.kind === "pdf" && !mw.page) mw.read(mw.path); }
  }
  function toLibrary() {
    mw.keep();
    voice.stop();
    if (mw.focusMode) mw.setFocus(false);
    mw.mode = "library";
    mw.path = "";
    lookup.shown = false;
    mw.typeOpen = false;
    viewLoader.sourceComponent = undefined;
    if (mw.mgr) mw.mgr.scan();
    keys.forceActiveFocus();
  }
  // where you are, kept (also on the way out)
  function keep() {
    if (!mw.page || !mw.page.ready || mw.path === "") return;
    mw.placeChanged(mw.page.where);
  }
  function placeChanged(where) {
    if (!mw.mgr || mw.path === "") return;
    const progress = mw.paged ? M.pdfProgress(where.page || 0, mw.page ? mw.page.pageCount : 1)
      : M.epubProgress(mw.chapters, where.chapter || 0, where.frac || 0);
    mw.mgr.change(mw.path, { pos: where, progress: progress });
  }

  Component {
    id: bookComp
    MinervaBook {
      book: mw.epub
      mgr: mw.mgr
      startAt: mw.book ? mw.book.pos : null
      settings: mw.settings
      insetTop: readBox.insetTop
      insetRight: readBox.insetRight
      insetBottom: readBox.insetBottom
      look: mw.look
      highlights: mw.book ? mw.book.highlights : []
      inks: mw.inks
    }
  }
  Component {
    id: comicComp
    MinervaComic {
      book: mw.comic
      startAt: mw.book ? mw.book.pos : null
      zoomMode: typeof mw.settings.zoom === "number" ? mw.settings.zoom : "page"
      spread: mw.settings.spread
      insetTop: readBox.insetTop
      insetRight: readBox.insetRight
      insetBottom: readBox.insetBottom
    }
  }
  Connections {
    target: mw.page
    ignoreUnknownSignals: true
    function onMoved(where) { mw.placeChanged(where); mw.syncMeta(); mw.stir(); }
    function onFailed(why) { mw.failure = why; }
    function onZoomChosen(z) { if (mw.mgr) mw.mgr.setSetting("zoom", z); }
    function onReadyChanged() { mw.syncMeta(); }
    function onHiTapped(id) { mw.setSidebar(true); side.reveal(id, "highlights"); }
    function onMenuAsked(x, y) { mw.pageMenu(mw.page, x, y); }
  }
  // a PDF's own title and author, when it has them — asked when it is
  // ready AND as it moves, since ready can come before this is listening
  function syncMeta() {
    if (mw.kind !== "pdf" || !mw.page || !mw.page.ready || !mw.page.title || !mw.book) return;
    if (mw.book.title !== mw.page.title || mw.book.author !== mw.page.author)
      mw.mgr.change(mw.path, { title: mw.page.title, author: mw.page.author });
  }

  // ── TIME SPENT ─────────────────────────────────────────────────────────
  // counted while the book is open and something happened in it in the
  // last three minutes (a turn, a scroll, a key) — or it is being read aloud
  property real stirred: 0
  function stir() { mw.stirred = Date.now(); }
  Timer {
    interval: 20000
    repeat: true
    running: mw.mode === "reading" && mw.visible && !!mw.page
    onTriggered: if (voice.on || Date.now() - mw.stirred < 180000) mw.mgr.spent(mw.path, interval)
  }

  // ── UNDO ───────────────────────────────────────────────────────────────
  // the library as it was before a removal, a mark dropped, a shelf gone
  UndoStack { id: undo; limit: 50 }
  function snapshot() { undo.record(mw.mgr.books.slice()); }
  function undoNow(redo) {
    const s = redo ? undo.redo(mw.mgr.books.slice()) : undo.undo(mw.mgr.books.slice());
    if (s === undefined) { mw.say(redo ? "Nothing to redo" : "Nothing to undo", true); return; }
    mw.mgr.books = s;
    mw.mgr.save();
    mw.say(redo ? "Redone" : "Undone");
  }

  // ── MARKS ──────────────────────────────────────────────────────────────
  readonly property var hereMark: mw.book && mw.page && mw.page.ready ? M.markHere(mw.book.bookmarks, mw.page.where) : null
  function placeWords(where) { return M.whereWords(mw.kind, where, mw.chapters); }
  function toggleBookmark() {
    if (!mw.book || !mw.page || !mw.page.ready) return;
    if (mw.hereMark) { mw.snapshot(); mw.mgr.change(mw.path, { bookmarks: M.dropMark(mw.book.bookmarks, mw.hereMark.id) }); mw.say("Bookmark removed — ctrl z puts it back"); return; }
    mw.mgr.change(mw.path, { bookmarks: M.addMark(mw.book.bookmarks, mw.page.where, "", Date.now()) });
    mw.say("Bookmarked " + mw.placeWords(mw.page.where));
  }
  // the selection as a highlight, in a colour; its id
  function highlight(color) {
    if (!mw.book || !mw.page || !mw.page.selectionMark) return "";
    const m = mw.page.selectionMark();
    const text = m ? String(m.text).replace(/\s+/g, " ").trim() : "";
    if (text === "") { mw.say("Select some words first", true); return ""; }
    if (color) mw.hiColor = color;
    const list = M.addMark(mw.book.highlights, m.where, text, Date.now(), Object.assign({ color: mw.hiColor }, m.quads ? { quads: m.quads } : {}));
    const id = list[list.length - 1].id;
    mw.mgr.change(mw.path, { highlights: list });
    const filed = mw.mgr.toClio(mw.book.title, text, mw.book.title + " · " + mw.placeWords(m.where), (noteId) => {
      const b = mw.mgr.bookOf(mw.path);
      if (b) mw.mgr.change(mw.path, { highlights: M.setMark(b.highlights, id, { note: noteId }) });
    });
    mw.page.clearSelection();
    mw.say(filed ? "Highlighted — and filed in Clio" : "Highlighted");
    return id;
  }
  function markOf(id, list) {
    if (!mw.book) return null;
    return (list === "marks" ? mw.book.bookmarks : mw.book.highlights).find((m) => m.id === id) || null;
  }
  function setMark(id, list, fields) {
    if (!mw.book) return;
    if (list === "marks") mw.mgr.change(mw.path, { bookmarks: M.setMark(mw.book.bookmarks, id, fields) });
    else mw.mgr.change(mw.path, { highlights: M.setMark(mw.book.highlights, id, fields) });
  }
  function dropMark(id, list) {
    if (!mw.book) return;
    mw.snapshot();
    if (list === "marks") mw.mgr.change(mw.path, { bookmarks: M.dropMark(mw.book.bookmarks, id) });
    else mw.mgr.change(mw.path, { highlights: M.dropMark(mw.book.highlights, id) });
    mw.say((list === "marks" ? "Bookmark" : "Highlight") + " removed — ctrl z puts it back");
  }
  // a highlight filed in Clio after the fact (Clio was not there, or it
  // failed): every one without a note
  function fileUnfiled() {
    if (!mw.book) return;
    const left = mw.book.highlights.filter((h) => !h.note);
    if (left.length === 0) { mw.say("Every highlight is in Clio already"); return; }
    for (const h of M.sortMarks(left)) {
      const id = h.id;
      mw.mgr.toClio(mw.book.title, h.text, mw.book.title + " · " + mw.placeWords(h.where), (noteId) => {
        const b = mw.mgr.bookOf(mw.path);
        if (b) mw.mgr.change(mw.path, { highlights: M.setMark(b.highlights, id, { note: noteId }) });
      }, h.comment);
    }
    mw.say(left.length === 1 ? "1 highlight filed in Clio" : left.length + " highlights filed in Clio");
  }
  function openInClio() {
    const h = mw.book ? mw.book.highlights.find((x) => x.note) : null;
    if (!h) { mw.say("Nothing from this book is in Clio yet", true); return; }
    mw.mgr.showInClio(h.note, "");
  }
  function exportHighlights() {
    if (!mw.book || mw.book.highlights.length === 0) { mw.say("No highlights to export", true); return; }
    if (!mw.mgr.fileManager) return;
    const book = mw.book, chapters = mw.chapters;
    mw.mgr.fileManager.choose(false, mw.path.replace(/\/[^/]*$/, ""), (paths) => {
      if (!paths || paths.length === 0) return;
      writer.write(paths[0], M.highlightsMarkdown(book, chapters));
      mw.say("Highlights saved as Markdown");
    }, book.title.replace(/[\/]/g, "-") + " — highlights.md");
  }
  AtomicWriter { id: writer; tag: "minerva-export" }

  // ── NOTES: on a highlight, or on a page ────────────────────────────────
  // asked on a sheet; `target` { id, list } for a mark's, null for a new
  // note on this page (kept as a bookmark that says it, and filed in Clio)
  property var noteFor: undefined
  function askNote(target) {
    mw.noteFor = target || null;
    const m = target ? mw.markOf(target.id, target.list) : null;
    noteEdit.text = m ? m.comment : "";
    mw.noteSheetOpen = true;
    Qt.callLater(() => { noteEdit.forceActiveFocus(); noteEdit.cursorPosition = noteEdit.length; });
  }
  property bool noteSheetOpen: false
  function saveNote() {
    const text = noteEdit.text.trim();
    const t = mw.noteFor;
    mw.noteSheetOpen = false;
    keys.forceActiveFocus();
    if (!mw.book) return;
    if (t) {
      const m = mw.markOf(t.id, t.list);
      if (!m || m.comment === text) return;
      mw.setMark(t.id, t.list, { comment: text });
      if (text !== "" && m.note) mw.mgr.toClio(mw.book.title, "", "On “" + m.text.slice(0, 60) + (m.text.length > 60 ? "…" : "") + "” · " + mw.placeWords(m.where), null, text);
      mw.say(text === "" ? "Note removed" : m.note ? "Note kept — and added in Clio" : "Note kept");
      return;
    }
    if (text === "" || !mw.page) return;
    const where = mw.page.where;
    mw.mgr.change(mw.path, { bookmarks: M.addMark(mw.book.bookmarks, where, text, Date.now(), { comment: text }) });
    const filed = mw.mgr.toClio(mw.book.title, "", mw.placeWords(where), null, text);
    mw.say(filed ? "Note kept here — and filed in Clio" : "Note kept here");
  }

  // ── A NAME, ASKED (a new shelf) ────────────────────────────────────────
  property var askDone: null
  property string askTitle: ""
  function askName(title, ghost, done) {
    mw.askTitle = title;
    nameField.ghost = ghost;
    nameField.text = "";
    mw.askDone = done;
    Qt.callLater(() => nameField.claim());
  }
  function answerName(ok) {
    const done = mw.askDone, text = nameField.text.trim();
    mw.askDone = null;
    keys.forceActiveFocus();
    if (ok && done && text !== "") done(text);
  }

  // ── FIND ───────────────────────────────────────────────────────────────
  property string findText: ""
  function find(words) {
    mw.findText = words;
    if (mw.page) mw.page.find(words);
    if (words !== "") { mw.setSidebar(true); side.tab = "find"; }
  }

  // ── LOOK UP, TRANSLATE (Lexi's) ────────────────────────────────────────
  function lookUp(mode) {
    const t = mw.page ? String(mw.page.selected || "").trim() : "";
    if (t === "") { mw.say("Select a word first", true); return; }
    lookup.ask(t, mode);
  }

  // ── FOCUS MODE ─────────────────────────────────────────────────────────
  // only the page: no head, no sidebar, no foot, the window fullscreen
  property bool focusMode: false
  function setFocus(on) {
    if (on === mw.focusMode) return;
    mw.focusMode = on;
    Hyprland.dispatch(Hypr.fullscreen());
    if (on) mw.say("Focus mode — f11 or esc to leave");
  }

  // ── WHAT WAS JUST DONE, SAID ONCE ─────────────────────────────────────
  property string said: ""
  property bool saidBad: false
  function say(t, bad) { mw.said = t; mw.saidBad = !!bad; sayTimer.restart(); }
  Timer { id: sayTimer; interval: 2800; onTriggered: mw.said = "" }

  function setSidebar(on) { if (mw.mgr) mw.mgr.setSetting("sidebar", on); }

  // ── THE WINDOW MAKES ROOM FOR ITS SIDEBAR, AS TERMINUS' AND PLATO'S DO ──
  // The same logic through the same functions (morpheus/room.js;
  // see plato's makeRoom for the whole story): a
  // floating window widens by the sidebar, to the right since that is where
  // it stands, so the page holds still; closing gives exactly that back.
  // Tiled, fullscreen or maximized, the layout owns the size and the
  // sidebar just slides. While Hyprland resizes, the page keeps its width
  // (sideKeepW) and the sidebar is what the window has gained.
  //
  // Focus mode is not a toggle of the sidebar: it hides it inside a
  // fullscreen window, and nothing is resized for it (`roomOpen`).
  readonly property bool roomOpen: mw.mode === "reading" && mw.settings.sidebar
  onRoomOpenChanged: mw.sideRoom(mw.roomOpen)
  property int sideGrew: 0
  property int sideWant: 0
  property bool sideFor: false
  property bool sidePending: false
  property real sideKeepW: -1
  property bool sideFollowing: false
  property int sideTarget: 0
  function releaseSideFollow() {
    mw.sideFollowing = false;
    mw.sideKeepW = -1;
    sideCeiling.stop();
  }
  LayoutProbe { id: sideLayout; title: mw.title }
  Timer { id: sideCeiling; interval: 1500; onTriggered: mw.releaseSideFollow() }
  // landed: the slide stays off until the sidebar has taken the width the
  // window just gained (plato's onWidthChanged, the other order)
  onWidthChanged: if (mw.sideKeepW >= 0 && mw.sideTarget > 0 && Math.abs(mw.width - mw.sideTarget) < 1) {
    mw.sideKeepW = -1;
    mw.sideFollowing = false;
    sideCeiling.stop();
  }
  function sideRoom(shown) {
    if (!keys.Window.active || mw.focusMode) return;
    if (sideLayout.laidOut) { mw.sideGrew = 0; return; }
    if (shown) {
      if (mw.sideGrew > 0) return;
      mw.sideWant = mw.width + mw.sideW;
    } else if (mw.sideGrew > 0) mw.sideWant = mw.width - mw.sideGrew;
    // already out when the window floated: closing still gives it back
    else if (sideBox.width > 0.5) mw.sideWant = mw.width - Math.round(sideBox.width);
    else return;
    mw.sideFollowing = true;
    mw.sideKeepW = mw.width - sideBox.width;
    mw.sideTarget = 0;
    sideCeiling.restart();
    mw.sideFor = shown;
    mw.sidePending = true;
    sideFitProc.running = false;
    sideFitProc.running = true;
  }
  Process {
    id: sideFitProc
    command: ["sh", "-c", "hyprctl -j activewindow; echo '@@mons'; hyprctl -j monitors"]
    stdout: StdioCollector {
      id: sideFitOut
      onStreamFinished: {
        if (!mw.sidePending) return;
        // asked for a state we have since toggled out of
        if (mw.sideFor !== mw.roomOpen) { mw.sidePending = false; return; }
        const parts = sideFitOut.text.split("@@mons");
        let w = null, mons = null;
        try { w = JSON.parse(parts[0]); mons = JSON.parse(parts[1]); } catch (e) { mw.releaseSideFollow(); return; }
        // the focused window is the one toggled; anything else is not ours
        if (!w || w.class !== "org.quickshell" || w.title !== mw.title) { mw.releaseSideFollow(); return; }
        mw.sidePending = false;
        sideLayout.note(w);
        const room = Room.make(w, mons, mw.sideWant, 16, 820, "right");
        if (!room) mw.releaseSideFollow();
        else {
          mw.sideTarget = w.size[0] + room.dw;
          Room.dispatches(w.address, room).forEach((d) => Hyprland.dispatch(d));
        }
        mw.sideGrew = mw.sideFor && room ? room.dw : 0;
      }
    }
  }
  function openFile() {
    if (!mw.mgr || !mw.mgr.fileManager) return;
    mw.mgr.fileManager.choose(false, mw.path !== "" ? mw.path.replace(/\/[^/]*$/, "") : Quickshell.env("HOME"), (paths) => {
      if (paths && paths.length > 0) mw.mgr.open(paths.join("\n"));
    }, "", true);
  }

  // ── MENUS ──────────────────────────────────────────────────────────────
  // under a button, or where the pointer was
  // the button stays pressed while its menu is up (menu.held), as
  // terminus' do — see heldBy
  function openMenu(item, items) {
    const p = item.mapToItem(menu, 0, item.height + 4);
    menu.open(p.x, p.y, items, item);
  }
  function heldBy(item) { return menu.isOpen && menu.held === item; }
  function menuAt(item, x, y, items) {
    const p = item.mapToItem(menu, x, y);
    menu.open(p.x, p.y, items);
  }
  readonly property var glyphs: ({
    copy: "\u{F018F}", marker: "\u{F0652}", note: "\u{F11D7}", lookup: "\u{F0E84}", translate: "\u{F05CA}",
    bookmark: "\u{F00C0}", voice: "\u{F050A}", focus: "\u{F0293}", info: "\u{F064E}", terminus: "\u{F0DCF}",
    clio: "\u{F0EBF}", export: "\u{F102E}", remove: "\u{F09E7}", shelf: "\u{F125F}", check: "\u{F012C}",
    go: "\u{F05DA}", watch: "\u{F178A}", more: "\u{F01D8}", stats: "\u{F0128}", aa: "\u{F027F}", plus: "\u{F05DB}"
  })
  function colorRows(run) {
    return M.COLORS.map((c) => ({ text: mw.colorNames[c], icon: "\u{F0765}", iconInk: mw.inks[c], mark: c === mw.hiColor ? "✓" : "", run: () => run(c) }));
  }
  // the page's own: what is selected, and this page
  function pageMenu(item, x, y) {
    const sel = mw.page && String(mw.page.selected || "") !== "";
    const items = [];
    if (sel) {
      items.push({ text: "Copy", icon: mw.glyphs.copy, mark: "ctrl c", run: () => mw.page.copy() });
      items.push({ text: "Highlight", icon: mw.glyphs.marker, mark: "ctrl h", children: mw.colorRows((c) => mw.highlight(c)) });
      items.push({ text: "Highlight with a note…", icon: mw.glyphs.note, run: () => { const id = mw.highlight(); if (id) mw.askNote({ id: id, list: "highlights" }); } });
      items.push({ text: "Look up", icon: mw.glyphs.lookup, mark: "ctrl k", run: () => mw.lookUp("define") });
      items.push({ text: "Translate", icon: mw.glyphs.translate, mark: "ctrl t", run: () => mw.lookUp("translate") });
      items.push({ isSeparator: true });
    }
    items.push({ text: mw.hereMark ? "Remove the bookmark" : "Bookmark this page", icon: mw.glyphs.bookmark, mark: "ctrl d", run: () => mw.toggleBookmark() });
    items.push({ text: "A note on this page…", icon: mw.glyphs.note, mark: "ctrl n", run: () => mw.askNote(null) });
    if (mw.kind !== "comic") items.push({ text: voice.on ? "Stop reading aloud" : "Read aloud from here", icon: mw.glyphs.voice, mark: "ctrl r", run: () => voice.toggle() });
    mw.menuAt(item, x, y, items);
  }
  // a row in the sidebar
  function rowMenu(r, list, x, y) {
    const items = [{ text: "Go there", icon: mw.glyphs.go, run: () => mw.page && (list === "find" ? mw.page.showHit(r) : mw.page.goTo(r.anchor ? Object.assign({}, r.where, { anchor: r.anchor }) : r.where)) }];
    if (list === "highlights") {
      items.push({ text: "Color", icon: mw.glyphs.marker, children: mw.colorRows((c) => mw.setMark(r.id, list, { color: c })) });
      items.push({ text: r.comment ? "Edit the note…" : "Add a note…", icon: mw.glyphs.note, run: () => mw.askNote({ id: r.id, list: list }) });
      items.push({ text: "Copy the words", icon: mw.glyphs.copy, run: () => mw.copyText(r.text) });
      items.push({ text: "Look up", icon: mw.glyphs.lookup, enabled: r.text.split(" ").length <= 3, run: () => lookup.ask(r.text, "define") });
      items.push({ text: "Translate", icon: mw.glyphs.translate, run: () => lookup.ask(r.text, "translate") });
      if (r.note) items.push({ text: "Show in Clio", icon: mw.glyphs.clio, run: () => mw.mgr.showInClio(r.note, r.text) });
      else if (mw.mgr.hasClio) items.push({ text: "File in Clio", icon: mw.glyphs.clio, run: () => mw.fileUnfiled() });
    }
    if (list === "marks") items.push({ text: r.comment ? "Edit the note…" : "Add a note…", icon: mw.glyphs.note, run: () => mw.askNote({ id: r.id, list: list }) });
    if (list === "marks" || list === "highlights") {
      items.push({ isSeparator: true });
      items.push({ text: "Remove", icon: mw.glyphs.remove, mark: "delete", danger: true, run: () => mw.dropMark(r.id, list) });
    }
    mw.menuAt(side, x, y, items);
  }
  // a book in the library — or, when it is one of several marked, all of them
  function bookMenu(b, x, y) {
    if (!b) return;
    if (lib.markedCount > 1 && lib.marked[b.path]) { mw.booksMenu(lib.chosenBooks(), x, y); return; }
    const finished = b.finished > 0;
    mw.menuAt(lib, x, y, [
      { text: b.opened > 0 ? "Continue" : "Read", icon: mw.glyphs.go, mark: "return", run: () => mw.read(b.path) },
      { text: finished ? "Not finished" : "Mark as finished", icon: mw.glyphs.check, run: () => {
          mw.mgr.change(b.path, finished ? { finished: 0 } : { finished: Date.now(), progress: 1 });
          mw.say(finished ? "Back to reading" : "Finished — well read"); } },
      { text: "Shelves", icon: mw.glyphs.shelf, children: mw.mgr.settings.shelves.map((s) => ({
          text: s, mark: b.shelves.indexOf(s) >= 0 ? "✓" : "", run: () => mw.mgr.toggleShelf(b.path, s)
        })).concat(mw.mgr.settings.shelves.length ? [{ isSeparator: true }] : []).concat([{
          text: "New shelf…", icon: mw.glyphs.plus, run: () => mw.askName("A new shelf", "its name", (n) => { const s = mw.mgr.addShelf(n); mw.mgr.toggleShelf(b.path, s); mw.say("On " + s); })
        }]) },
      { isSeparator: true },
      { text: "Show in Terminus", icon: mw.glyphs.terminus, enabled: !!mw.mgr.fileManager, run: () => mw.mgr.fileManager.reveal(b.path) },
      { text: "Info", icon: mw.glyphs.info, mark: "ctrl i", run: () => mw.showInfo(b.path) },
      { isSeparator: true },
      { text: "Remove from the library", icon: mw.glyphs.remove, mark: "delete", danger: true, run: () => mw.forget(b.path) }
    ]);
  }
  function forget(path) {
    mw.snapshot();
    mw.mgr.forget(path);
    mw.say("Removed from the library — the file is untouched (ctrl z puts it back)");
  }
  // several books at once (the library's marks): one undo for all of them
  function forgetMany(list) {
    if (list.length === 0) return;
    if (list.length === 1) { mw.forget(list[0].path); return; }
    mw.snapshot();
    for (const b of list) mw.mgr.forget(b.path);
    lib.clearMarks();
    mw.say(list.length + " books removed from the library — the files are untouched (ctrl z puts them back)");
  }
  function booksMenu(list, x, y) {
    const n = list.length;
    const all = (pred) => list.every(pred);
    mw.menuAt(lib, x, y, [
      { text: "Mark " + n + " as finished", icon: mw.glyphs.check, enabled: !all((b) => b.finished > 0), run: () => {
          mw.snapshot(); for (const b of list) if (!(b.finished > 0)) mw.mgr.change(b.path, { finished: Date.now(), progress: 1 }); mw.say(n + " books finished"); } },
      { text: "Not finished", icon: mw.glyphs.check, enabled: list.some((b) => b.finished > 0), run: () => {
          mw.snapshot(); for (const b of list) if (b.finished > 0) mw.mgr.change(b.path, { finished: 0 }); mw.say("Back to reading"); } },
      // a shelf ticked when all of them are on it; choosing it puts all on
      // it, or takes all off when all were
      { text: "Shelves", icon: mw.glyphs.shelf, children: mw.mgr.settings.shelves.map((s) => {
          const on = all((b) => b.shelves.indexOf(s) >= 0);
          return { text: s, mark: on ? "✓" : list.some((b) => b.shelves.indexOf(s) >= 0) ? "–" : "", run: () => {
            for (const b of list) if ((b.shelves.indexOf(s) >= 0) === on) mw.mgr.toggleShelf(b.path, s);
            mw.say(on ? n + " books off " + s : n + " books on " + s); } };
        }).concat(mw.mgr.settings.shelves.length ? [{ isSeparator: true }] : []).concat([{
          text: "New shelf…", icon: mw.glyphs.plus, run: () => mw.askName("A new shelf", "its name", (name) => {
            const s = mw.mgr.addShelf(name); for (const b of list) if (b.shelves.indexOf(s) < 0) mw.mgr.toggleShelf(b.path, s); mw.say(n + " books on " + s); })
        }]) },
      { isSeparator: true },
      { text: "Remove " + n + " from the library", icon: mw.glyphs.remove, mark: "delete", danger: true, run: () => mw.forgetMany(list) }
    ]);
  }
  function shelfMenu(item) {
    const sh = mw.settings.shelf;
    const items = [{ text: "All shelves", mark: sh === "" ? "✓" : "", run: () => mw.mgr.setSetting("shelf", "") }]
      .concat(mw.settings.shelves.map((s) => ({
        text: s + "  ·  " + mw.mgr.books.filter((b) => b.shelves.indexOf(s) >= 0).length,
        icon: mw.glyphs.shelf, mark: s === sh ? "✓" : "", run: () => mw.mgr.setSetting("shelf", s)
      })))
      .concat([{ isSeparator: true },
        { text: "New shelf…", icon: mw.glyphs.plus, run: () => mw.askName("A new shelf", "its name", (n) => mw.mgr.setSetting("shelf", mw.mgr.addShelf(n))) }]);
    if (sh !== "") items.push({ text: "Delete the shelf “" + sh + "”", icon: mw.glyphs.remove, danger: true, run: () => {
      mw.snapshot(); mw.mgr.dropShelf(sh); mw.say("Shelf deleted — its books are still in the library"); } });
    mw.openMenu(item, items);
  }
  // nothing watched yet: straight to the picker, a menu of one row being
  // no menu (user, 2026-10-21); once something is, the menu — stop, add, look
  function watchDir() {
    const home = Quickshell.env("HOME");
    if (!mw.mgr.fileManager) return;
    mw.mgr.fileManager.choose(true, home, (paths) => {
      if (!paths || !paths.length) return;
      mw.mgr.setSetting("watch", mw.settings.watch.concat(paths));
      mw.say("Watching " + paths[0].replace(/.*\//, "") + " — its books join the library");
    });
  }
  // a directory no longer watched; the books found there that were never
  // opened can go with it (one undo for the lot)
  function unwatch(d, drop) {
    if (drop.length > 0) mw.snapshot();
    mw.mgr.setSetting("watch", mw.settings.watch.filter((x) => x !== d));
    for (const b of drop) mw.mgr.forget(b.path);
    const name = d.replace(/.*\//, "");
    mw.say(drop.length > 0 ? "No longer watching " + name + " — " + drop.length + " unread " + (drop.length === 1 ? "book" : "books") + " removed (ctrl z puts them back)"
                           : "No longer watching " + name + " — its books stay in the library");
  }
  function watchMenu(item) {
    if (mw.settings.watch.length === 0) { mw.watchDir(); return; }
    const home = Quickshell.env("HOME");
    // each watched directory a branch that says what it does (user,
    // 2026-10-21: a row that stopped watching on a click was not findable)
    const items = mw.settings.watch.map((d) => {
      const under = mw.mgr.books.filter((bk) => bk.path.indexOf(d + "/") === 0);
      const unread = under.filter((bk) => !(bk.opened > 0));
      return {
        text: d.indexOf(home) === 0 ? "~" + d.slice(home.length) : d, icon: mw.glyphs.watch,
        children: [
          { text: "Show in Terminus", icon: mw.glyphs.terminus, enabled: !!mw.mgr.fileManager, run: () => mw.mgr.fileManager.reveal(d) },
          { isSeparator: true },
          { text: "Stop watching", icon: mw.glyphs.remove, danger: true, run: () => mw.unwatch(d, []) }
        ].concat(unread.length === 0 ? [] : [
          { text: unread.length === 1 ? "Stop watching, and remove its 1 unread book" : "Stop watching, and remove its " + unread.length + " unread books",
            icon: mw.glyphs.remove, danger: true, run: () => mw.unwatch(d, unread) }
        ])
      };
    });
    if (items.length) items.push({ isSeparator: true });
    items.push({ text: "Watch a directory…", icon: mw.glyphs.plus, enabled: !!mw.mgr.fileManager, run: () => mw.watchDir() });
    if (mw.settings.watch.length) items.push({ text: mw.mgr.scanning ? "Looking…" : "Look again now", enabled: !mw.mgr.scanning, run: () => mw.mgr.scan() });
    mw.openMenu(item, items);
  }
  function moreMenu(item) {
    const n = mw.book ? mw.book.highlights.length : 0;
    mw.openMenu(item, [
      { text: voice.on ? "Stop reading aloud" : "Read aloud", icon: mw.glyphs.voice, mark: "ctrl r", enabled: mw.kind !== "comic", run: () => voice.toggle() },
      { text: "Focus mode", icon: mw.glyphs.focus, mark: "f11", run: () => mw.setFocus(true) },
      { text: "A note on this page…", icon: mw.glyphs.note, mark: "ctrl n", run: () => mw.askNote(null) },
      { isSeparator: true },
      { text: "Open the highlights in Clio", icon: mw.glyphs.clio, enabled: n > 0 && mw.mgr.hasClio, run: () => mw.openInClio() },
      { text: "File the rest in Clio", icon: mw.glyphs.clio, enabled: n > 0 && mw.mgr.hasClio, run: () => mw.fileUnfiled() },
      { text: "Export the highlights…", icon: mw.glyphs.export, enabled: n > 0, run: () => mw.exportHighlights() },
      { isSeparator: true },
      { text: "Show in Terminus", icon: mw.glyphs.terminus, enabled: !!mw.mgr.fileManager, run: () => mw.mgr.fileManager.reveal(mw.path) },
      { text: "Info", icon: mw.glyphs.info, mark: "ctrl i", run: () => mw.showInfo(mw.path) }
    ]);
  }
  function copyText(t) { copier.text = t; copier.selectAll(); copier.copy(); mw.say("Copied"); }
  TextEdit { id: copier; visible: false; cursorDelegate: Caret { field: copier } }

  // ── INFO ───────────────────────────────────────────────────────────────
  property string infoPath: ""
  property bool infoOpen: false
  function showInfo(p) { mw.infoPath = p || ""; mw.infoOpen = true; keys.forceActiveFocus(); }
  readonly property var infoBook: mw.infoOpen && mw.infoPath !== "" && mw.mgr ? mw.mgr.bookOf(mw.infoPath) : null

  // ── KEYS ───────────────────────────────────────────────────────────────
  Item {
    id: keys
    focus: true
    Keys.onPressed: (e) => {
      const ctrl = e.modifiers & Qt.ControlModifier;
      const shift = e.modifiers & Qt.ShiftModifier;
      e.accepted = true;
      mw.stir();
      if (mw.infoOpen && (e.key === Qt.Key_Escape || (ctrl && e.key === Qt.Key_I))) { mw.infoOpen = false; return; }
      if (ctrl && e.key === Qt.Key_O) { mw.openFile(); return; }
      if (ctrl && e.key === Qt.Key_Z) { mw.undoNow(!!shift); return; }
      if (mw.mode === "library") {
        if (e.key === Qt.Key_Escape) { if (lib.markedCount > 0) lib.clearMarks(); else if (lib.query !== "") lib.query = ""; else mw.visible = false; return; }
        if (ctrl && e.key === Qt.Key_A) { lib.markAll(); return; }
        if (e.key === Qt.Key_Left) { lib.move(-1, 0); return; }
        if (e.key === Qt.Key_Right) { lib.move(1, 0); return; }
        if (e.key === Qt.Key_Up) { lib.move(0, -1); return; }
        if (e.key === Qt.Key_Down) { lib.move(0, 1); return; }
        if (ctrl && (e.key === Qt.Key_Return || e.key === Qt.Key_Enter)) { lib.goOn(); return; }
        if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { lib.choose(lib.sel); return; }
        if (ctrl && e.key === Qt.Key_I) { const b = lib.current(); mw.showInfo(b ? b.path : ""); return; }
        if (e.key === Qt.Key_Delete) { mw.forgetMany(lib.chosenBooks()); return; }
        if (e.key === Qt.Key_Menu) { const b = lib.current(); if (b) mw.bookMenu(lib.markedCount > 1 ? lib.chosenBooks()[0] : b, lib.width / 2, lib.height / 3); return; }
        if (e.key === Qt.Key_Backspace) { lib.query = lib.query.slice(0, -1); return; }
        if (e.text && e.text.length > 0 && !ctrl && e.text.charCodeAt(0) >= 32) { lib.query += e.text; lib.sel = 0; return; }
        e.accepted = false;
        return;
      }
      if (e.key === Qt.Key_Escape) {
        if (lookup.shown) { lookup.shown = false; return; }
        if (mw.typeOpen) { mw.typeOpen = false; return; }
        if (mw.findText !== "") { findField.text = ""; mw.find(""); return; }
        if (mw.focusMode) { mw.setFocus(false); return; }
        if (voice.on) { voice.stop(); return; }
        mw.toLibrary();
        return;
      }
      if (e.key === Qt.Key_F11) { mw.setFocus(!mw.focusMode); return; }
      if (ctrl && e.key === Qt.Key_L) { mw.toLibrary(); return; }
      if (ctrl && e.key === Qt.Key_F) { if (mw.focusMode) mw.setFocus(false); findField.forceActiveFocus(); findField.selectAll(); return; }
      if (ctrl && e.key === Qt.Key_B) { mw.setSidebar(!mw.settings.sidebar); return; }
      if (ctrl && e.key === Qt.Key_D) { mw.toggleBookmark(); return; }
      if (ctrl && e.key === Qt.Key_H) { mw.highlight(); return; }
      if (ctrl && e.key >= Qt.Key_1 && e.key <= Qt.Key_5) { mw.highlight(M.COLORS[e.key - Qt.Key_1]); return; }
      if (ctrl && e.key === Qt.Key_N) { mw.askNote(null); return; }
      if (ctrl && e.key === Qt.Key_K) { mw.lookUp("define"); return; }
      if (ctrl && e.key === Qt.Key_T) { mw.lookUp("translate"); return; }
      if (ctrl && e.key === Qt.Key_R) { voice.toggle(); return; }
      if (ctrl && e.key === Qt.Key_I) { mw.showInfo(mw.path); return; }
      if (ctrl && e.key === Qt.Key_C) { if (mw.page) mw.page.copy(); return; }
      if (ctrl && (e.key === Qt.Key_Plus || e.key === Qt.Key_Equal)) { if (mw.page) mw.page.zoomBy(1.15); return; }
      if (ctrl && e.key === Qt.Key_Minus) { if (mw.page) mw.page.zoomBy(1 / 1.15); return; }
      if (ctrl && e.key === Qt.Key_0) { if (mw.page) mw.page.fit("width"); return; }
      if (!mw.page) { e.accepted = false; return; }
      if (voice.on && e.key === Qt.Key_Space) { voice.pause(); return; }
      if (e.key === Qt.Key_Right || e.key === Qt.Key_PageDown || e.key === Qt.Key_Space) { mw.page.step(1); return; }
      if (e.key === Qt.Key_Left || e.key === Qt.Key_PageUp) { mw.page.step(-1); return; }
      if (e.key === Qt.Key_Home) { mw.page.goTo(mw.paged ? { page: 0 } : { chapter: 0, frac: 0 }); return; }
      if (e.key === Qt.Key_End) { mw.page.goTo(mw.paged ? { page: mw.page.pageCount - 1 } : { chapter: mw.page.pageCount - 1, frac: 1 }); return; }
      if (e.key === Qt.Key_Delete && side.sel >= 0 && (side.tab === "marks" || side.tab === "highlights")) {
        const r = side.rows[side.sel]; if (r) mw.dropMark(r.id, side.tab); return;
      }
      e.accepted = false;
    }
  }

  // ── THE STAGE ──────────────────────────────────────────────────────────
  Item {
    id: stage
    anchors.fill: parent
    // the window's ground, less the sidebar: laid under it too, the sidebar
    // came out solid, with no frost through it (user, 2026-10-21)
    Rectangle { width: parent.width - sideBox.width; height: parent.height; color: Zenon.layerBg }

    // ── the head ─────────────────────────────────────────────────────────
    Item {
      id: head
      width: parent.width - sideBox.width
      height: mw.focusMode ? 0 : mw.headH
      visible: !mw.focusMode
      z: 3
      Rectangle { anchors.fill: parent; color: Zenon.headBg }
      Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Zenon.border }
      // how far through, along the head's foot
      Rectangle {
        anchors.bottom: parent.bottom
        visible: mw.mode === "reading" && !!mw.book
        width: parent.width * (mw.book ? mw.book.progress : 0)
        height: 2
        color: Zenon.cyan
        Behavior on width { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }
      }
      Text {
        id: owl
        x: 20
        anchors.verticalCenter: parent.verticalCenter
        // back to the library: md-chevron_left, bolder (user, 2026-10-21)
        text: mw.mode === "reading" ? "\u{F0141}" : "\u{F03D2}"
        color: mw.mode === "reading" ? Zenon.white : Zenon.cyan
        opacity: owlPress.pressed ? Zenon.pressDim : 1
        font.family: Zenon.glyphFace
        font.pixelSize: Zenon.px(mw.mode === "reading" ? 26 : 20)
        // the suite's press: a pressFill tile under the chevron
        Rectangle {
          anchors.centerIn: parent
          width: parent.height + 4
          height: width
          z: -1
          radius: Zenon.windowRadius
          visible: owlPress.pressed
          color: Zenon.pressFill
        }
        MouseArea { id: owlPress; anchors.fill: parent; anchors.margins: -10; enabled: mw.mode === "reading"; onClicked: mw.toLibrary() }
        HoverHandler { enabled: mw.mode === "reading"; onHoveredChanged: hovered ? tip.show(owl, "Library", "ctrl l") : tip.hide(owl) }
      }
      Text {
        id: headTitle
        anchors.left: owl.right
        anchors.leftMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, head.width * (mw.mode === "reading" ? 0.24 : 0.4))
        elide: Text.ElideRight
        text: mw.mode === "library" ? "Library" : mw.book ? mw.book.title : M.nameOf(mw.path)
        color: Zenon.ink
        font.family: Zenon.face
        font.weight: Zenon.titleWeight
        font.pixelSize: Zenon.px(18)
      }
      Text {
        anchors.left: headTitle.right
        anchors.leftMargin: 12
        anchors.baseline: headTitle.baseline
        anchors.right: headTools.left
        anchors.rightMargin: 16
        visible: mw.mode === "library" || !mw.page || !mw.page.ready
        elide: Text.ElideRight
        text: mw.mode === "library"
          ? (mw.mgr ? (mw.mgr.books.length === 1 ? "1 book" : mw.mgr.books.length + " books") : "")
            + (lib.markedCount > 0 ? "  ·  " + lib.markedCount + " selected" : "")
            + (lib.query !== "" ? "  ·  “" + lib.query + "”" : "")
            + (mw.mgr && mw.mgr.scanning ? "  ·  looking in watched directories…" : "")
          : (mw.book && mw.book.author ? mw.book.author : "")
        color: Zenon.accentMuted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(14)
      }
      // ── THE READING TOOLS (user, 2026-10-21) ───────────────────────────
      // by its file, not its type name: a type new to minerva's qmldir is
      // not seen until the shell restarts
      Loader {
        id: navTools
        anchors.left: headTitle.right
        anchors.leftMargin: 18
        anchors.verticalCenter: parent.verticalCenter
        active: mw.mode === "reading"
        visible: !!mw.page && mw.page.ready && x + width < headTools.x - 12
        source: "MinervaTools.qml"
        onLoaded: { navTools.item.win = mw; navTools.item.done.connect(() => keys.forceActiveFocus()); }
      }
      // THE FIVE BUTTONS ONE WIDTH (user, 2026-10-21: "the Aa button is too
      // wide"): Aa, bookmark, read aloud, more, sidebar — together as wide as
      // the sidebar they stand in, less its margins either side
      readonly property real toolW: Math.floor((mw.sideW - 2 * 14 - 4 * 8) / 5)
      Row {
        id: headTools
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        // find, a field that is always there while reading; the buttons
        // beside it stand as tall (30)
        Rectangle {
          visible: mw.mode === "reading" && mw.kind !== "comic"
          width: 200
          height: 30
          radius: Zenon.windowRadius
          color: Zenon.wash(0.06)
          border.width: 1
          border.color: Zenon.border
          HeldRing { anchors.fill: parent; on: findField.activeFocus }
          Text {
            id: findGlyph
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            text: "\u{F0349}"
            color: Zenon.accentMuted
            font.family: Zenon.glyphFace
            font.pixelSize: Zenon.px(14)
          }
          TextInput {
            id: findField
            anchors.left: findGlyph.right
            anchors.leftMargin: 8
            anchors.right: findClear.left
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            clip: true
            color: Zenon.ink
            selectionColor: Zenon.cyan
            selectedTextColor: Zenon.onAccent
            font.family: Zenon.face
            font.pixelSize: Zenon.px(14)
            cursorDelegate: Caret { field: findField }
            Text {
              anchors.fill: parent
              verticalAlignment: Text.AlignVCenter
              visible: findField.text === "" && !findField.activeFocus
              text: "Find"
              color: Zenon.accentMuted
              font: findField.font
            }
            Keys.onPressed: (e) => {
              if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                if (findField.text !== mw.findText) mw.find(findField.text);
                else if (mw.page) (e.modifiers & Qt.ShiftModifier) ? mw.page.findPrev() : mw.page.findNext();
                e.accepted = true;
              } else if (e.key === Qt.Key_Escape) {
                findField.text = "";
                mw.find("");
                keys.forceActiveFocus();
                e.accepted = true;
              }
            }
          }
          // terminus' clear chip, as every search field wears it: the words
          // and the find both go, and the field keeps the keys
          ClearChip {
            id: findClear
            size: Zenon.px(14)
            shown: findField.text !== ""
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            onClicked: { findField.text = ""; mw.find(""); findField.forceActiveFocus(); }
          }
        }
        // the five reading buttons stand here while the sidebar is shut,
        // and in its toolbar while it is open (sideTools)
        Item {
          id: headSlot
          visible: mw.mode === "reading"
          width: tools5.parent === headSlot ? tools5.implicitWidth : 0
          height: 30
        }
        // the library's own
        DialogButton {
          id: statsBtn
          implicitHeight: 30
          visible: mw.mode === "library"
          glyph: true
          label: mw.glyphs.stats
          onClicked: mw.showInfo("")
          HoverHandler { onHoveredChanged: hovered ? tip.show(statsBtn, "Your reading") : tip.hide(statsBtn) }
        }
        DialogButton {
          id: watchBtn
          implicitHeight: 30
          visible: mw.mode === "library"
          label: mw.glyphs.watch + "  Watch…"
          ink: mw.settings.watch.length > 0 ? Zenon.cyan : Zenon.muted
          held: mw.heldBy(watchBtn)
        onClicked: mw.watchMenu(watchBtn)
          HoverHandler { onHoveredChanged: hovered ? tip.show(watchBtn, "Directories whose books join the library by themselves") : tip.hide(watchBtn) }
        }
        DialogButton {
          implicitHeight: 30
          visible: mw.mode === "library"
          label: "Open…"
          ink: Zenon.cyan
          ready: !!mw.mgr && !!mw.mgr.fileManager
          onClicked: mw.openFile()
        }
      }
    }

    // ── the library ──────────────────────────────────────────────────────
    MinervaLibrary {
      id: lib
      anchors.top: head.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: foot.top
      opacity: mw.mode === "library" ? 1 : 0
      visible: opacity > 0
      Behavior on opacity { NumberAnimation { duration: Zenon.normal; easing.type: Easing.OutCubic } }
      mgr: mw.mgr
      win: mw
      onChosen: (p) => mw.read(p)
      onMenuAsked: (b, x, y) => mw.bookMenu(b, x, y)
    }

    // ── reading ──────────────────────────────────────────────────────────
    Item {
      id: sideBox
      // on the right (user, 2026-10-21): the page's left edge is where
      // reading starts, and nothing should stand in front of it
      // THE WINDOW'S WHOLE HEIGHT (user, 2026-10-21), as terminus' and
      // plato's: the head and the hint bar end at it, and the reading
      // buttons stand in its own toolbar
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      // while Hyprland resizes the window for it, the sidebar is whatever
      // the window has gained (see sideKeepW); otherwise it slides on its own
      width: mw.sideKeepW >= 0 ? Math.max(0, Math.min(mw.sideW, mw.width - mw.sideKeepW))
        : mw.sideOpen ? mw.sideW : 0
      visible: width > 0
      // terminus' sidebar's slide
      Behavior on width {
        enabled: !mw.sideFollowing
        NumberAnimation { duration: Math.round(Zenon.normal * 1.4); easing.type: Zenon.travelEase }
      }
      clip: true
      z: 2
      // an inactive tab's thinner glass and the sheet's veil, as plato's
      // tree and terminus' sidebar wear them, over the window's blur
      // and what of the page runs on under it, frosted beneath both
      Frost { anchors.fill: parent; z: -1; source: readBox; active: mw.mode === "reading" && !!mw.page && !mw.focusMode
        visible: active; scrim: 0; track: [sideBox.x, sideBox.width] }
      Rectangle { anchors.fill: parent; color: Zenon.alpha(Zenon.tabAwayInk, Zenon.tabAway(Zenon.layerBg.a)) }
      Rectangle { anchors.fill: parent; color: Zenon.ground; opacity: 0.6 }
      Rectangle { anchors.left: parent.left; width: 1; height: parent.height; color: Zenon.border; z: 5 }
      Item {
        id: sideTools
        z: 4
        x: sideBox.width - mw.sideW
        width: mw.sideW
        height: mw.headH
      }
      MinervaSide {
        id: side
        x: sideBox.width - mw.sideW
        y: mw.headH
        width: mw.sideW
        height: parent.height - mw.headH
        tip: tip
        chromeTop: -mw.headH
        kind: mw.paged ? "pdf" : "epub"
        outline: mw.page ? mw.page.outline : []
        bookmarks: mw.book ? mw.book.bookmarks : []
        highlights: mw.book ? mw.book.highlights : []
        hits: mw.page ? mw.page.hits : []
        chapters: mw.chapters
        findWords: mw.findText
        inks: mw.inks
        serif: mw.mgr ? mw.mgr.serifFace : Zenon.face
        thumb: mw.paged && mw.page && mw.page.thumb ? mw.page.thumb : null
        pageCount: mw.paged && mw.page ? mw.page.pageCount : 0
        current: mw.paged && mw.page ? mw.page.where.page || 0 : 0
        aspectOf: (i) => mw.page && mw.page.aspectOf ? mw.page.aspectOf(i) : 1.414
        onGo: (where, row) => {
          if (!mw.page) return;
          if (side.tab === "find") mw.page.showHit(row);
          else mw.page.goTo(row && row.anchor ? Object.assign({}, where, { anchor: row.anchor }) : where);
          keys.forceActiveFocus();
        }
        onRowMenu: (r, list, x, y) => mw.rowMenu(r, list, x, y)
      }
    }
    Item {
      id: readBox
      // the pages are clipped to the box: a page's picture can be larger
      // than the view while it is laid out. Between the bars: what scrolls
      // past them goes on under them as terminus' rows do, frosted by the
      // ScrollEdges below — the insets stay for a view that wants room
      clip: true
      anchors.top: head.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: foot.top
      readonly property real insetTop: 0
      // ON UNDER THE SIDEBAR (user, 2026-10-21): a page zoomed past the view
      // carries on under it, frosted there (sideBox's Frost), and sits clear
      // of it at rest
      readonly property real insetRight: sideBox.width
      readonly property real insetBottom: 0
      // the middle of what shows between them
      readonly property real midX: -readBox.insetRight / 2
      readonly property real midY: (readBox.insetTop - readBox.insetBottom) / 2
      // a book opening comes up into place
      opacity: mw.mode === "reading" ? 1 : 0
      scale: mw.mode === "reading" ? 1 : 0.985
      visible: opacity > 0
      Behavior on opacity { NumberAnimation { duration: Zenon.normal * 1.5; easing.type: Easing.OutCubic } }
      Behavior on scale { NumberAnimation { duration: Zenon.normal * 1.5; easing.type: Easing.OutCubic } }
      Loader {
        id: viewLoader
        anchors.fill: parent
        onLoaded: {
          metaSoon.restart();
          // a PDF is set from its file: what follows the window, bound here
          viewLoader.item.insetTop = Qt.binding(() => readBox.insetTop);
          viewLoader.item.insetRight = Qt.binding(() => readBox.insetRight);
          viewLoader.item.insetBottom = Qt.binding(() => readBox.insetBottom);
          if (mw.kind === "pdf") {
            viewLoader.item.spread = Qt.binding(() => mw.settings.spread);
            viewLoader.item.look = Qt.binding(() => mw.look);
            viewLoader.item.highlights = Qt.binding(() => mw.book ? mw.book.highlights : []);
            viewLoader.item.inks = Qt.binding(() => mw.inks);
          }
        }
        onStatusChanged: if (viewLoader.status === Loader.Error) mw.failure = "This PDF could not be shown"
      }
      // Qt PDF missing: what it takes, and the button that does it
      Column {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.horizontalCenterOffset: readBox.midX
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: readBox.midY
        width: Math.min(parent.width - 80, 520)
        spacing: 10
        visible: mw.needsPdf
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: "\u{F0226}"
          color: Zenon.cyan
          font.family: Zenon.glyphFace
          font.pixelSize: Zenon.px(40)
        }
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: "PDFs need Qt PDF"
          color: Zenon.ink
          font.family: Zenon.face
          font.weight: Zenon.titleWeight
          font.pixelSize: Zenon.px(18)
        }
        EmptyState {
          width: parent.width
          text: "Qt's PDF module comes inside qt6-webengine on Arch (about 120 MB). EPUBs, comics and texts need nothing; Ceres installs it once, and this PDF opens."
        }
        Item { width: 1; height: 4 }
        BusyButton {
          anchors.horizontalCenter: parent.horizontalCenter
          label: "Install Qt PDF"
          ink: Zenon.cyan
          primary: true
          busy: !!mw.mgr && mw.mgr.settingUp
          busyText: "Installing…"
          onClicked: if (!mw.mgr.setupPdf((ok) => mw.say(ok ? "Qt PDF is installed" : "Qt PDF was not installed", !ok))) mw.say("Ceres is busy — try again in a moment", true)
        }
      }
      // the book could not be read, or is still being unpacked
      EmptyState {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.horizontalCenterOffset: readBox.midX
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: readBox.midY
        width: Math.min(parent.width - 80, 520)
        visible: mw.failure !== "" || (!mw.needsPdf && !mw.page && mw.mode === "reading")
        text: mw.failure !== "" ? mw.failure : "Opening…"
      }

      // ── THE SELECTION'S BAR ────────────────────────────────────────────
      // words selected: their colours, a note, Lexi, copy — over the foot
      Rectangle {
        id: selBar
        readonly property bool on: !!mw.page && String(mw.page.selected || "") !== "" && mw.kind !== "comic"
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.horizontalCenterOffset: readBox.midX
        anchors.bottom: parent.bottom
        anchors.bottomMargin: readBox.insetBottom + 16
        width: selRow.implicitWidth + 20
        height: 44
        radius: Zenon.windowRadius
        color: Zenon.hud(0.94)
        border.width: 1
        border.color: Zenon.border
        z: 4
        opacity: selBar.on ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Zenon.normal; easing.type: Easing.OutCubic } }
        Row {
          id: selRow
          anchors.centerIn: parent
          spacing: 6
          Repeater {
            model: M.COLORS
            delegate: Rectangle {
              id: dot
              required property string modelData
              required property int index
              anchors.verticalCenter: parent.verticalCenter
              width: 22
              height: 22
              radius: 11
              color: mw.inks[dot.modelData]
              border.width: dot.modelData === mw.hiColor ? 2 : 0
              border.color: Zenon.ink
              scale: dotPress.pressed ? 0.88 : 1
              MouseArea { id: dotPress; anchors.fill: parent; anchors.margins: -3; onClicked: mw.highlight(dot.modelData) }
              HoverHandler { onHoveredChanged: hovered ? tip.show(dot, "Highlight in " + mw.colorNames[dot.modelData].toLowerCase(), "ctrl " + (dot.index + 1)) : tip.hide(dot) }
            }
          }
          Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 1; height: 22; color: Zenon.border }
          DialogButton {
            implicitHeight: 30
            label: "Note"
            onClicked: { const id = mw.highlight(); if (id) mw.askNote({ id: id, list: "highlights" }); }
          }
          DialogButton { implicitHeight: 30; label: "Look up"; onClicked: mw.lookUp("define") }
          DialogButton { implicitHeight: 30; label: "Translate"; onClicked: mw.lookUp("translate") }
          DialogButton { implicitHeight: 30; label: "Copy"; onClicked: { if (mw.page) mw.page.copy(); mw.say("Copied"); } }
        }
      }

      // ── READING ALOUD: its controls while it reads ─────────────────────
      Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.horizontalCenterOffset: readBox.midX
        anchors.bottom: parent.bottom
        anchors.bottomMargin: readBox.insetBottom + (selBar.on ? 70 : 16)
        width: voiceRow.implicitWidth + 24
        height: 44
        radius: Zenon.windowRadius
        color: Zenon.hud(0.94)
        border.width: 1
        border.color: Zenon.alpha(Zenon.cyan, 0.5)
        z: 4
        opacity: voice.on ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Zenon.normal; easing.type: Easing.OutCubic } }
        Row {
          id: voiceRow
          anchors.centerIn: parent
          spacing: 6
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: voice.paused ? "Paused" : "Reading aloud"
            color: Zenon.cyan
            font.family: Zenon.face
            font.weight: Font.DemiBold
            font.pixelSize: Zenon.px(14)
            rightPadding: 6
          }
          DialogButton { implicitHeight: 30; glyph: true; label: "\u{F04AE}"; onClicked: voice.skip(-1) }
          DialogButton { implicitHeight: 30; glyph: true; label: voice.paused ? "\u{F040A}" : "\u{F03E4}"; onClicked: voice.pause() }
          DialogButton { implicitHeight: 30; glyph: true; label: "\u{F04AD}"; onClicked: voice.skip(1) }
          DialogButton { implicitHeight: 30; glyph: true; label: "\u{F04DB}"; ink: Zenon.red; onClicked: voice.stop() }
        }
      }

      // in focus mode, where you are — faint, in the corner
      Text {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 14
        visible: mw.focusMode && !!mw.page && mw.page.ready
        text: !mw.page || !mw.page.ready ? "" : mw.paged ? (mw.page.where.page + 1) + " / " + mw.page.pageCount
          : M.percentWords(mw.book ? mw.book.progress : 0)
        color: Zenon.alpha(Qt.lighter(mw.look.ink, 1), 0.45)
        font.family: Zenon.face
        font.pixelSize: Zenon.px(12)
      }
    }

    // ── THE FIVE READING BUTTONS ───────────────────────────────────────
    // in the sidebar's toolbar while it is open, at the head's right end
    // while it is shut (user, 2026-10-21); the find stays in the head
    Row {
      id: tools5
      parent: mw.sideOpen ? sideTools : headSlot
      anchors.centerIn: parent
      spacing: 8
      visible: mw.mode === "reading"
      DialogButton {
        id: aaBtn
        implicitWidth: head.toolW
        implicitHeight: 30
        visible: mw.mode === "reading"
        label: "Aa"
        ink: mw.typeOpen ? Zenon.cyan : Zenon.muted
        held: mw.typeOpen
        onClicked: mw.typeOpen = !mw.typeOpen
        HoverHandler { onHoveredChanged: hovered ? tip.show(aaBtn, "The page: its colors and layout") : tip.hide(aaBtn) }
      }
      DialogButton {
        id: markBtn
        implicitWidth: head.toolW
        implicitHeight: 30
        visible: mw.mode === "reading" && !!mw.page
        glyph: true
        label: mw.hereMark ? "\u{F00C0}" : "\u{F00C3}"
        ink: mw.hereMark ? Zenon.cyan : Zenon.muted
        onClicked: mw.toggleBookmark()
        HoverHandler { onHoveredChanged: hovered ? tip.show(markBtn, mw.hereMark ? "Remove the bookmark" : "Bookmark this page", "ctrl d") : tip.hide(markBtn) }
      }
      DialogButton {
        id: voiceBtn
        implicitWidth: head.toolW
        implicitHeight: 30
        visible: mw.mode === "reading" && mw.kind !== "comic" && !!mw.page
        glyph: true
        label: mw.glyphs.voice
        ink: voice.on ? Zenon.cyan : Zenon.muted
        onClicked: voice.toggle()
        HoverHandler { onHoveredChanged: hovered ? tip.show(voiceBtn, voice.on ? "Stop reading aloud" : "Read aloud", "ctrl r") : tip.hide(voiceBtn) }
      }
      DialogButton {
        id: moreBtn
        implicitWidth: head.toolW
        implicitHeight: 30
        visible: mw.mode === "reading"
        glyph: true
        label: mw.glyphs.more
        held: mw.heldBy(moreBtn)
        onClicked: mw.moreMenu(moreBtn)
        HoverHandler { onHoveredChanged: hovered ? tip.show(moreBtn, "More") : tip.hide(moreBtn) }
      }
      DialogButton {
        id: sideBtn
        implicitWidth: head.toolW
        implicitHeight: 30
        visible: mw.mode === "reading"
        glyph: true
        // the panel shown or not (user's glyphs, 2026-10-21)
        label: mw.settings.sidebar ? "" : ""
        ink: mw.settings.sidebar ? Zenon.cyan : Zenon.muted
        onClicked: mw.setSidebar(!mw.settings.sidebar)
        HoverHandler { onHoveredChanged: hovered ? tip.show(sideBtn, "Sidebar", "ctrl b") : tip.hide(sideBtn) }
      }
    }

    // ── THE CARDS OVER THE PAGE ──────────────────────────────────────────
    // out here, beside the reading box rather than in it, so their frost
    // can be OF it; a click anywhere else puts the page card away
    InputShield { visible: mw.typeOpen && mw.mode === "reading"; z: 4.5; onClicked: { mw.typeOpen = false; keys.forceActiveFocus(); } }
    // ── THE PAGE CARD: its colours, its layout, its type ───────────────
    Rectangle {
      visible: opacity > 0
      opacity: mw.typeOpen ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: Zenon.normal; easing.type: Easing.OutCubic } }
      anchors.top: readBox.top
      anchors.topMargin: readBox.insetTop + 12
      anchors.right: readBox.right
      anchors.rightMargin: readBox.insetRight + 12
      width: 330
      height: typeCol.implicitHeight + 28
      radius: Zenon.radiusCard
      // frosted (user, 2026-10-21): the page it is over, blurred under it,
      // in the sidebar's glass (user, 2026-10-22: in the head's, it washed
      // out over a white page) — an inactive tab's thinner glass, then the
      // sheet's veil, as sideBox wears them
      color: Zenon.alpha(Zenon.tabAwayInk, Zenon.tabAway(Zenon.layerBg.a))
      border.width: 1
      border.color: Zenon.border
      z: 5
      // tracked: it moves with the sidebar, and a stale mapping frosted the
      // wrong strip of the page (the scroll thumb, user 2026-10-21)
      Frost { anchors.fill: parent; z: -1; source: readBox; active: parent.visible; visible: active; radius: parent.radius
        scrim: 0; track: [parent.x, parent.y, parent.width] }
      // inside the border, which it would otherwise dim
      Rectangle { anchors.fill: parent; anchors.margins: 1; radius: parent.radius - 1; color: Zenon.ground; opacity: 0.6 }
      // its clicks are its own, not the shield's under it
      MouseArea { anchors.fill: parent; z: -0.5 }
      Column {
        id: typeCol
        x: 6
        y: 14
        width: parent.width - 12
        spacing: 6
        SectionLabel { x: 14; text: "Colors" }
        Segments {
          x: 14
          options: [["auto", "Auto"], ["paper", "Paper"], ["sepia", "Sepia"], ["night", "Night"]]
          current: mw.settings.theme
          onChose: (v) => mw.mgr.setSetting("theme", v)
        }
        Text {
          x: 14
          width: parent.width - 28
          wrapMode: Text.WordWrap
          text: mw.kind === "comic" ? "A comic stays as it was drawn"
            : mw.settings.theme === "auto" ? (mw.paged ? "As printed" : "In the shell's own colors") : ""
          visible: text !== ""
          color: Zenon.accentMuted
          font.family: Zenon.face
          font.pixelSize: Zenon.px(12)
        }
        Item { width: 1; height: 4; visible: mw.paged }
        SectionLabel { x: 14; text: "Pages"; visible: mw.paged }
        Segments {
          x: 14
          visible: mw.paged
          options: [["off", "One"], ["on", "Two"], ["cover", "Two, cover alone"]]
          current: mw.settings.spread
          onChose: (v) => mw.mgr.setSetting("spread", v)
        }
        Item { width: 1; height: 4; visible: !mw.paged }
        SectionLabel { x: 14; text: "Type"; visible: !mw.paged }
        PrefSlider {
          width: parent.width
          visible: !mw.paged
          label: "Size"
          labelW: 96
          value: mw.settings.fontSize
          from: 12
          to: 40
          wheelStep: 1
          readout: String(mw.settings.fontSize)
          neutral: M.defaults().fontSize
          onMoved: (v) => mw.mgr.setSetting("fontSize", Math.round(v))
        }
        PrefSlider {
          width: parent.width
          visible: !mw.paged
          label: "Spacing"
          labelW: 96
          value: mw.settings.lineHeight
          from: 1.1
          to: 2.4
          wheelStep: 0.1
          readout: mw.settings.lineHeight.toFixed(1)
          neutral: M.defaults().lineHeight
          onMoved: (v) => mw.mgr.setSetting("lineHeight", v)
        }
        PrefSlider {
          width: parent.width
          visible: !mw.paged
          label: "Measure"
          labelW: 96
          value: mw.settings.width
          from: 420
          to: 1400
          wheelStep: 40
          readout: String(mw.settings.width)
          neutral: M.defaults().width
          onMoved: (v) => mw.mgr.setSetting("width", v)
        }
        Item {
          width: parent.width
          height: 36
          visible: !mw.paged
          Ctl.Check {
            x: 14
            anchors.verticalCenter: parent.verticalCenter
            label: "Serif type"
            lit: mw.settings.serif
            onToggled: mw.mgr.setSetting("serif", !mw.settings.serif)
          }
        }
        SectionLabel { x: 14; text: "Reading aloud"; visible: mw.kind !== "comic" }
        PrefSlider {
          width: parent.width
          visible: mw.kind !== "comic"
          label: "Pace"
          labelW: 96
          value: mw.settings.speakRate
          from: 0.5
          to: 2
          wheelStep: 0.1
          readout: mw.settings.speakRate.toFixed(1) + "×"
          neutral: 1
          onMoved: (v) => mw.mgr.setSetting("speakRate", v)
        }
      }
    }

    // ── LEXI'S CARD ────────────────────────────────────────────────────
    MinervaLookup {
      id: lookup
      win: mw
      glass: readBox
      visible: mw.mode === "reading" && opacity > 0
      anchors.top: readBox.top
      anchors.topMargin: readBox.insetTop + 12
      anchors.right: readBox.right
      anchors.rightMargin: readBox.insetRight + 12
      z: 6
      onClosed: keys.forceActiveFocus()
    }

    // ── what was just done, said once ────────────────────────────────────
    Ctl.Said {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.horizontalCenterOffset: readBox.visible ? readBox.midX : 0
      anchors.top: head.bottom
      anchors.topMargin: 14
      z: 7
      maxWidth: 620
      text: mw.said
      bad: mw.saidBad
      ground: 0.9
    }

    // ── WHAT SCROLLS GOES UNDER THE BARS, FROSTED ──────────────────────
    // the page's view carries on under the head and the hint bar as
    // terminus' rows do (ScrollEdge: laid under the bars, over nothing else).
    // UNDER THE SIDEBAR TOO (z 1.5, below sideBox's 2): the view runs on
    // under it, so these span it, and over it they washed out its toolbar
    // and drew a seam above its tabs (user, 2026-10-21); the sidebar frosts
    // its own stretch
    ScrollEdge {
      view: mw.page && mw.page.view ? mw.page.view : null
      follow: true
      chromeTop: 0
      z: 1.5
      visible: mw.mode === "reading" && !mw.focusMode && !!mw.page
    }
    ScrollEdge {
      view: mw.page && mw.page.view ? mw.page.view : null
      below: true
      follow: true
      bar: foot
      z: 1.5
      visible: mw.mode === "reading" && !mw.focusMode && !!mw.page
    }
    HintBar {
      id: foot
      z: 3
      anchors.bottom: parent.bottom
      anchors.left: parent.left
      width: parent.width - sideBox.width
      height: mw.focusMode ? 0 : implicitHeight
      visible: !mw.focusMode
      rows: mw.mode === "library"
        ? [["arrows", "choose"], ["return", "read"], ["ctrl click", "select"], ["ctrl a", "all"], ["type", "filter"], ["delete", "remove"], ["ctrl i", "info"], ["ctrl o", "open"], ["esc", "close"]]
        : [["← →", "turn"], ["ctrl f", "find"], ["ctrl h", "highlight"], ["ctrl k", "look up"], ["ctrl n", "note"], ["ctrl r", "read aloud"],
           ["f11", "focus"], ["esc", "library"]]
      // where you are and what is left, at the right end
      Text {
        anchors.verticalCenter: parent.verticalCenter
        rightPadding: 6
        visible: text !== ""
        text: {
          if (mw.mode !== "reading" || !mw.page || !mw.page.ready || !mw.book) return "";
          const left = M.timeLeft(mw.book);
          return [mw.paged ? "Page " + ((mw.page.where.page || 0) + 1) + " of " + mw.page.pageCount
                           : (mw.chapters[mw.page.where.chapter] && mw.chapters[mw.page.where.chapter].title) || "Chapter " + ((mw.page.where.chapter || 0) + 1),
                  M.percentWords(mw.book.progress),
                  left > 0 ? M.spanWords(left) + " left" : ""].filter((x) => x).join("  ·  ");
        }
        color: Zenon.accentMuted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(13)
      }
    }

    // the right-click menus, and the names on the buttons
    PopMenu { id: menu; anchors.fill: parent; window: mw; onClosed: keys.forceActiveFocus() }
  }
  WindowTip { id: tip; window: mw }
  MinervaVoice { id: voice; win: mw; onSaid: (t, bad) => mw.say(t, bad) }

  // ── A NOTE, WRITTEN ────────────────────────────────────────────────────
  InputShield { visible: mw.noteSheetOpen; onClicked: { mw.noteSheetOpen = false; keys.forceActiveFocus(); } }
  Sheet {
    // frosted over the window's content (user, 2026-10-21), as clio's
    backdrop: stage
    shown: mw.noteSheetOpen
    fromTop: head.height
    cardW: Math.min(mw.width - 80, 560)
    cardH: noteCol.implicitHeight + 40
    Column {
      id: noteCol
      x: 22
      y: 20
      width: parent.width - 44
      spacing: 14
      Keys.onEscapePressed: { mw.noteSheetOpen = false; keys.forceActiveFocus(); }
      Text {
        text: !mw.noteFor ? "A note on " + (mw.page && mw.page.ready ? mw.placeWords(mw.page.where).replace(/ · \d+%$/, "") : "this page")
          : mw.noteFor.list === "marks" ? "A note on the bookmark" : "A note on the highlight"
        color: Zenon.ink
        font.family: Zenon.face
        font.weight: Zenon.titleWeight
        font.pixelSize: Zenon.px(19)
      }
      Text {
        width: parent.width
        visible: !!mw.noteFor && mw.noteFor.list === "highlights"
        maximumLineCount: 3
        elide: Text.ElideRight
        wrapMode: Text.WordWrap
        text: { const m = mw.noteFor ? mw.markOf(mw.noteFor.id, mw.noteFor.list) : null; return m ? "“" + m.text + "”" : ""; }
        color: Zenon.accentMuted
        font.family: mw.mgr ? mw.mgr.serifFace : Zenon.face
        font.pixelSize: Zenon.px(14)
      }
      Rectangle {
        width: parent.width
        height: Math.max(110, noteEdit.contentHeight + 20)
        radius: Zenon.radiusControl
        color: Zenon.wash(0.06)
        border.width: 1
        border.color: Zenon.border
        HeldRing { anchors.fill: parent; on: noteEdit.activeFocus }
        TextEdit {
          id: noteEdit
          x: 10
          y: 10
          width: parent.width - 20
          wrapMode: TextEdit.Wrap
          color: Zenon.ink
          selectionColor: Zenon.cyan
          selectedTextColor: Zenon.onAccent
          font.family: Zenon.face
          font.pixelSize: Zenon.px(15)
          cursorDelegate: Caret { field: noteEdit }
          Keys.onPressed: (e) => {
            if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && (e.modifiers & Qt.ControlModifier)) { e.accepted = true; mw.saveNote(); }
          }
          Text {
            visible: noteEdit.text === ""
            text: "What you think of it"
            color: Zenon.accentMuted
            font: noteEdit.font
          }
        }
      }
      Row {
        spacing: 8
        DialogButton { label: "Cancel"; onClicked: { mw.noteSheetOpen = false; keys.forceActiveFocus(); } }
        DialogButton {
          label: mw.mgr && mw.mgr.hasClio && !mw.noteFor ? "Keep, and file in Clio" : "Keep"
          ink: Zenon.cyan
          primary: true
          onClicked: mw.saveNote()
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          leftPadding: 8
          text: "ctrl return"
          color: Zenon.accentMuted
          font.family: Zenon.face
          font.pixelSize: Zenon.px(12)
        }
      }
    }
  }

  // ── A NAME ─────────────────────────────────────────────────────────────
  InputShield { visible: !!mw.askDone; onClicked: mw.answerName(false) }
  Sheet {
    // frosted over the window's content (user, 2026-10-21), as clio's
    backdrop: stage
    shown: !!mw.askDone
    fromTop: head.height
    cardW: Math.min(mw.width - 80, 460)
    cardH: nameCol.implicitHeight + 40
    Column {
      id: nameCol
      x: 22
      y: 20
      width: parent.width - 44
      spacing: 14
      Keys.onEscapePressed: mw.answerName(false)
      Text {
        text: mw.askTitle
        color: Zenon.ink
        font.family: Zenon.face
        font.weight: Zenon.titleWeight
        font.pixelSize: Zenon.px(19)
      }
      BulkField {
        id: nameField
        width: parent.width
        onAccepted: mw.answerName(true)
      }
      Row {
        spacing: 8
        DialogButton { label: "Cancel"; onClicked: mw.answerName(false) }
        DialogButton { label: "Make"; ink: Zenon.cyan; primary: true; onClicked: mw.answerName(true) }
      }
    }
  }

  // ── INFO ───────────────────────────────────────────────────────────────
  InputShield { visible: mw.infoOpen; onClicked: { mw.infoOpen = false; keys.forceActiveFocus(); } }
  Sheet {
    // frosted over the window's content (user, 2026-10-21), as clio's
    backdrop: stage
    shown: mw.infoOpen
    fromTop: head.height
    cardW: Math.min(mw.width - 80, 600)
    cardH: Math.min(mw.height - head.height - 60, infoCol.implicitHeight + 44)
    MinervaInfo {
      id: infoCol
      x: 24
      y: 22
      width: parent.width - 48
      mgr: mw.mgr
      book: mw.infoBook
      chapters: mw.infoBook && mw.infoBook.path === mw.path ? mw.chapters : []
      pages: mw.infoBook && mw.infoBook.path === mw.path && mw.page && mw.paged ? mw.page.pageCount : 0
    }
  }

  property bool typeOpen: false
  Timer { id: metaSoon; interval: 500; repeat: true; property int tries: 0
    onTriggered: { mw.syncMeta(); if (++metaSoon.tries > 8 || (mw.page && mw.page.ready)) { metaSoon.stop(); metaSoon.tries = 0; } } }
}
