// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// MINERVA — the reader: PDFs and EPUBs, and the library of what you have
// opened, each where you left it, with its bookmarks and highlights. The
// owl of Minerva, who reads by lamplight.
//
// THIS IS THE PART THAT IS ALWAYS IN THE SHELL: the library (minerva.json),
// the ipc handler, its .desktop entry (what opens PDFs and EPUBs), and the
// two helpers the window asks — core/epub.py, which unpacks a book, and
// pdftoppm for a PDF's cover. The window is compiled on first use and let
// go of when it closes.
//
// PDFs are drawn by Qt's own PDF module, which Arch ships only inside
// qt6-webengine; a machine without it gets EPUBs at once and, on its first
// PDF, the offer to install it through Ceres (user, 2026-10-20).
//
//   `qs ipc call Minerva open <paths>`   those files (newline-separated)
//   `qs ipc call Minerva library`        the library
//   minerva/bin/minerva [file…]          the same, and minerva.desktop

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../morpheus"
import "../morpheus/lagnotes.js" as LagNotes
import "../morpheus/hypr.js" as Hypr
import "../ceres"
import "minerva.js" as M

Scope {
  id: mgr

  // terminus (Open…'s picker) and clio (highlights), handed in by shell.qml
  property var fileManager: null
  property var notebook: null

  // ── THE LIBRARY ────────────────────────────────────────────────────
  property var books: []
  property var settings: M.defaults()
  FileView {
    id: libFile
    path: Quickshell.statePath("minerva.json")
    blockLoading: true
    printErrors: false
  }
  Timer { id: saveTimer; interval: 600; onTriggered: libFile.setText(M.serializeLibrary({ books: mgr.books, settings: mgr.settings })) }
  function save() { saveTimer.restart(); }
  function bookOf(path) { return M.bookOf(mgr.books, path); }
  function touch(path, fields) { mgr.books = M.upsert(mgr.books, path, fields); mgr.save(); }
  function change(path, fields) { mgr.books = M.update(mgr.books, path, fields); mgr.save(); }
  function forget(path) { mgr.books = M.remove(mgr.books, path); mgr.save(); }
  function setSetting(key, value) {
    const s = Object.assign({}, mgr.settings);
    s[key] = value;
    mgr.settings = M.cleanSettings(s);
    mgr.save();
  }

  // ── THE SERIF ──────────────────────────────────────────────────────
  // By name, asked of fontconfig once: inside the shell the generic
  // "serif" lands on the suite's own (monospace) face — morpheus/
  // GlyphFallback's rule outranks it — and a book set in that read as code.
  property string serifFace: "serif"
  Process {
    running: true
    command: ["fc-match", "-f", "%{family[0]}", "serif"]
    stdout: StdioCollector {
      id: serifOut
      waitForEnd: true
      onStreamFinished: { const f = serifOut.text.trim(); if (f !== "") mgr.serifFace = f; }
    }
  }

  // ── QT PDF: THERE, OR TO BE INSTALLED ──────────────────────────────
  property bool pdfReady: false
  property bool pdfKnown: false
  Process {
    id: pdfCheck
    running: true
    command: ["sh", "-c", "for d in /usr/lib/qt6/qml /usr/lib64/qt6/qml \"$(qtpaths6 --query QT_INSTALL_QML 2>/dev/null)\"; do "
      + "[ -n \"$d\" ] && [ -f \"$d/QtQuick/Pdf/qmldir\" ] && exit 0; done; exit 1"]
    onExited: (code) => { mgr.pdfReady = code === 0; mgr.pdfKnown = true; }
  }
  readonly property bool settingUp: Ceres.installing !== null || Ceres.txBusy
  function setupPdf(done) {
    if (mgr.settingUp) return false;
    return Ceres.install(["qt6-webengine"], "for PDFs in Minerva", (ok) => {
      pdfCheck.running = true;
      if (done) done(ok);
    });
  }

  // ── AN EPUB, UNPACKED ──────────────────────────────────────────────
  // into the cache, one directory per book (by path, size and time — a
  // book changed on disk is unpacked again); fn(book | null, why)
  readonly property string cacheDir: Paths.cacheDir() + "/quickshell/minerva"
  // one-off helpers, made per ask and destroyed when answered
  Component { id: procComp; Process {} }
  Component { id: collComp; StdioCollector { waitForEnd: true } }
  function openEpub(path, fn) {
    const p = procComp.createObject(mgr);
    const out = collComp.createObject(p);
    p.stdout = out;
    out.streamFinished.connect(() => {
      let j = null;
      try { j = JSON.parse(out.text); } catch (e) {}
      if (j && !j.error) fn(j, ""); else fn(null, j && j.error ? j.error : "This book could not be read");
      p.destroy();
    });
    p.command = ["python3", "-I", Quickshell.shellDir + "/minerva/core/epub.py", "open", path,
                 mgr.cacheDir + "/epub/" + Qt.md5(path)];
    p.running = true;
  }
  function findInBook(dir, words, fn) {
    findProc.fn = fn;
    findProc.command = ["python3", "-I", Quickshell.shellDir + "/minerva/core/epub.py", "find", dir, words];
    findProc.running = true;
  }
  Process {
    id: findProc
    property var fn: null
    stdout: StdioCollector {
      id: findOut
      waitForEnd: true
      onStreamFinished: {
        let j = [];
        try { j = JSON.parse(findOut.text); } catch (e) {}
        if (findProc.fn) findProc.fn(Array.isArray(j) ? j : []);
      }
    }
  }

  // ── A PDF'S COVER ──────────────────────────────────────────────────
  // its first page, small, for the library; fn(fileUrl)
  function pdfCover(path, fn) {
    const out = mgr.cacheDir + "/covers/" + Qt.md5(path);
    const p = procComp.createObject(mgr);
    p.command = ["sh", "-c", "mkdir -p \"$(dirname \"$2\")\"; [ -s \"$2.png\" ] || pdftoppm -f 1 -l 1 -singlefile -png -scale-to 360 \"$1\" \"$2\" 2>/dev/null; [ -s \"$2.png\" ]",
                 "sh", path, out];
    p.exited.connect((code) => { if (code === 0) fn("file://" + out + ".png"); p.destroy(); });
    p.running = true;
  }

  // ── HIGHLIGHTS INTO CLIO ───────────────────────────────────────────
  function toClio(book, text, where, done) {
    if (!mgr.notebook || !text) return false;
    mgr.notebook.appendQuote(book, text, where, done);
    return true;
  }
  function showInClio(id, text) { if (mgr.notebook) mgr.notebook.openAt(id, text); }

  // ── ITS .desktop ENTRY, AND THE DEFAULT FOR BOOKS ──────────────────
  // What opens a PDF and an EPUB (user, 2026-10-20) — but on a machine
  // where something else was CHOSEN for them, only where nothing was, as
  // alexandria does for fonts: a choice made in Oracle stays made.
  readonly property var mimes: ["application/pdf", "application/epub+zip", "application/x-pdf"]
  Process {
    running: true
    command: ["sh", "-c", Desktop.installCommand("minerva", {
      Type: "Application",
      Name: "Minerva",
      GenericName: "Reader",
      Comment: "Read PDFs and EPUBs, with bookmarks and highlights, in ZENWORKS",
      Icon: "accessories-ebook-reader",
      Categories: ["Office", "Viewer", "Literature"],
      Keywords: ["pdf", "epub", "ebook", "book", "reader", "document", "read"],
      Exec: Desktop.execLine(Quickshell.shellDir + "/minerva/bin/minerva", "%F"),
      Terminal: "false",
      StartupNotify: "false",
      MimeType: mgr.mimes,
    }) + "\nfor m in \"$@\"; do\n"
      + "  [ -n \"$(xdg-mime query default \"$m\" 2>/dev/null)\" ] || gio mime \"$m\" minerva.desktop >/dev/null 2>&1\n"
      + "done\nexit 0\n", "sh"].concat(mgr.mimes)
  }

  // ── THE WINDOW ─────────────────────────────────────────────────────
  // One, reused: a second book opened replaces the first (the library has
  // the way back). Floating by its title (hypr/lua/rules.lua: "minerva").
  property var win: null
  LazyComponent {
    id: lazy
    source: Qt.resolvedUrl("MinervaWindow.qml")
    tag: "minerva"
  }
  function withWindow(fn) {
    lazy.withReady(() => {
      let fresh = false;
      if (!mgr.win) {
        const t0 = Date.now();
        mgr.win = lazy.comp.createObject(mgr, { mgr: mgr });
        LagNotes.mark("minerva window", t0);
        if (!mgr.win) return;
        fresh = true;
      }
      const was = !fresh && mgr.win.visible;
      fn(mgr.win);
      mgr.win.visible = true;
      if (was) Hyprland.dispatch(Hypr.focusTitle("minerva"));
    });
  }
  function retire(w) {
    if (mgr.win === w) mgr.win = null;
    if (!mgr.win && lazy.waiting.length === 0) lazy.comp = null;
  }

  function open(paths) {
    const list = String(paths || "").split("\n").map((p) => p.trim()).filter((p) => p !== "" && M.kindOf(p) !== "");
    if (list.length === 0) { mgr.library(); return; }
    // every one into the library; the last one opened
    for (let i = 0; i < list.length - 1; ++i) mgr.touch(list[i], {});
    mgr.withWindow((w) => w.read(list[list.length - 1]));
  }
  function library() { mgr.withWindow((w) => w.toLibrary()); }
  // the book read last, where it was left; the library when there is none
  function last() {
    const b = mgr.books.find((x) => !!x.path);
    if (b) mgr.withWindow((w) => w.read(b.path)); else mgr.library();
  }

  IpcHandler {
    target: "Minerva"
    function open(paths: string): string { mgr.open(paths); return "ok"; }
    function library(): string { mgr.library(); return "ok"; }
    function last(): string { mgr.last(); return "ok"; }
  }

  Component.onCompleted: {
    const lib = M.parseLibrary(libFile.text());
    mgr.books = lib.books;
    mgr.settings = lib.settings;
  }
}
