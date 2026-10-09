// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ALEXANDRIA — the font book: every typeface installed, set in itself; every
// character a face has, named and copyable; fonts installed and removed. And
// the font picker: oracle's Font row opens it to choose (pick()).
//
// THIS IS THE PART THAT IS ALWAYS IN THE SHELL, which is almost nothing: an
// ipc handler, its .desktop entry, and what every window shares (the
// bookmarks, the sample, the sizes). The window type is compiled on the
// first open and let go of when its window closes — plato's rule, an
// application nobody has opened costs nothing.
//
// Reached through:
//   `qs ipc call Alexandria open ""`       the library
//   `qs ipc call Alexandria open <paths>`  font files (newline-separated):
//                                         a look at them, and Install —
//                                         bin/alexandria, its .desktop entry,
//                                         which is how terminus and artemis
//                                         open a font
//   `qs ipc call Alexandria glyphs <q>`    the glyphs page, searching
//   pick({ title, family, weight }, fn)   oracle: fn(family, fcWeight)

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../morpheus"
import "../morpheus/lagnotes.js" as LagNotes
import "../oracle"
import "alexandria.js" as A
import "../oracle/oracle.js" as Ora

Scope {
  id: mgr

  // terminus, handed in by shell.qml, for Show in terminus and Open a font…
  property var fileManager: null

  // ── ITS .desktop ENTRY, AND THE DEFAULT FOR FONTS ──────────────────
  // Written into ~/.local/share/applications when missing, with this
  // machine's path (Desktop.installCommand), as plato's and picasso's are.
  // And made what opens a font — but only for a type nobody has chosen an
  // application for: a choice made in oracle's Default apps stays made.
  readonly property var mimes: ["font/ttf", "font/otf", "font/collection", "font/sfnt",
                                "font/woff", "font/woff2", "application/x-font-ttf",
                                "application/x-font-otf", "application/x-font-type1"]
  Process {
    running: true
    command: ["sh", "-c", Desktop.installCommand("alexandria", {
      Type: "Application",
      Name: "Alexandria",
      GenericName: "Font Book",
      Comment: "Browse, compare and install fonts and their glyphs, in ZENWORKS",
      Icon: "font-x-generic",
      Categories: ["Utility", "Viewer"],
      Keywords: ["font", "typeface", "glyph", "character", "unicode", "nerd", "install"],
      Exec: Desktop.execLine(Quickshell.shellDir + "/alexandria/bin/alexandria", "%F"),
      Terminal: "false",
      StartupNotify: "false",
      MimeType: mgr.mimes,
    }) + "\nfor m in \"$@\"; do\n"
      + "  [ -n \"$(xdg-mime query default \"$m\" 2>/dev/null)\" ] || gio mime \"$m\" alexandria.desktop >/dev/null 2>&1\n"
      + "done\nexit 0\n", "sh"].concat(mgr.mimes)
  }

  // ── WHAT EVERY WINDOW SHARES, KEPT ─────────────────────────────────
  property var favs: ({})
  property string sample: ""
  // the writing system the specimen is set in (A.SCRIPTS), when the face has it
  property string lang: "latin"
  // the specimen's sample size, and the glyph grid's cell — ctrl+wheel,
  // ctrl + − 0 in the window
  property int sampleSize: 56
  property int glyphSize: 64
  property string shelf: "all"
  property string page: "specimen"
  FileView {
    id: stateFile
    path: Quickshell.statePath("alexandria.json")
    blockLoading: true
    printErrors: false
  }
  Component.onCompleted: {
    try {
      const st = JSON.parse(stateFile.text() || "{}");
      if (st.favs && typeof st.favs === "object") mgr.favs = st.favs;
      if (typeof st.sample === "string") mgr.sample = st.sample;
      if (typeof st.lang === "string") mgr.lang = A.scriptOf(st.lang).id;
      if (st.sampleSize >= 12 && st.sampleSize <= 160) mgr.sampleSize = st.sampleSize;
      if (st.glyphSize >= 36 && st.glyphSize <= 160) mgr.glyphSize = st.glyphSize;
      if (A.SHELVES.some((s) => s.id === st.shelf)) mgr.shelf = st.shelf;
      if (["specimen", "glyphs", "info"].indexOf(st.page) >= 0) mgr.page = st.page;
    } catch (e) {}
  }
  function keep_() { keepTimer.restart(); }
  Timer {
    id: keepTimer
    interval: 400
    onTriggered: stateFile.setText(JSON.stringify({
      favs: mgr.favs, sample: mgr.sample, lang: mgr.lang, sampleSize: mgr.sampleSize,
      glyphSize: mgr.glyphSize, shelf: mgr.shelf, page: mgr.page }))
  }
  function setFav(name, on) {
    const f = Object.assign({}, mgr.favs);
    if (on) f[name] = true; else delete f[name];
    mgr.favs = f;
    mgr.keep_();
  }
  function set(key, value) {
    if (mgr[key] === value) return;
    mgr[key] = value;
    mgr.keep_();
  }

  // ── THE INSTALLED FONTS ────────────────────────────────────────────
  // fc-list, folded into families by oracle's own rule (Ora.familyOf), so a
  // family here is a family in oracle's Font list. Scanned when a window
  // opens and after every install or removal, never at startup.
  property var families: []
  property bool scanning: false
  // asked again while one is out (an install landed mid-scan): once more
  // after it, or the new family would be missing until the next open
  property bool _again: false
  property string _lastList: ""
  function scan() {
    if (listProc.running) { mgr._again = true; return; }
    mgr.scanning = true;
    listProc.running = true;
  }
  Process {
    id: listProc
    command: ["sh", "-c", A.listCommand()]
    stdout: StdioCollector {
      id: listOut
      waitForEnd: true
      onStreamFinished: {
        // THE SAME LIST IS THE SAME FAMILIES. A scan runs every time a window
        // opens, and folding fc-list into families is ~115 ms on the GUI
        // thread (qmlprofiler, 2026-10-09); with nothing installed or removed
        // since, the bytes are identical and the families are kept as they
        // are — the same objects, so nothing bound to them rebuilds either.
        if (listOut.text !== mgr._lastList || mgr.families.length === 0) {
          mgr._lastList = listOut.text;
          mgr.families = A.parseList(listOut.text, Paths.home(), Ora.familyOf);
        }
        mgr.scanning = false;
        if (mgr._again) { mgr._again = false; mgr.scan(); return; }
        mgr.landed_();
      }
    }
  }

  // ── WHAT A CHARACTER IS CALLED ─────────────────────────────────────
  // Unicode's names and blocks, from the files the unicode-character-database
  // package puts in /usr/share/unicode; Nerd Fonts' names from its
  // glyphnames.json, fetched once into the cache. Read on the first visit to
  // a glyphs page, and kept for the session.
  property var uni: null
  property var blocks: []
  property var nerd: ({})
  property bool namesAsked: false
  function needNames() {
    if (mgr.namesAsked) return;
    mgr.namesAsked = true;
    uniFile.path = "/usr/share/unicode/UnicodeData.txt";
    blockFile.path = "/usr/share/unicode/Blocks.txt";
    nerdFile.path = mgr.nerdPath;
  }
  readonly property string nerdPath: Paths.cacheDir() + "/alexandria/glyphnames.json"
  FileView {
    id: uniFile
    printErrors: false
    onLoaded: mgr.uni = A.parseUnicodeData(uniFile.text())
  }
  FileView {
    id: blockFile
    printErrors: false
    onLoaded: mgr.blocks = A.parseBlocks(blockFile.text())
  }
  FileView {
    id: nerdFile
    printErrors: false
    onLoaded: mgr.nerd = A.parseNerdNames(nerdFile.text())
    // not fetched yet: fetched, once (a week-old copy is fetched again)
    onLoadFailed: nerdFetch.running = true
  }
  Process {
    id: nerdFetch
    command: ["sh", "-c", "mkdir -p \"$(dirname \"$1\")\" && curl -fsSL --max-time 30 -o \"$1.part\" \"$2\" && mv -f \"$1.part\" \"$1\"",
              "sh", mgr.nerdPath, A.NERD_NAMES_URL]
    onExited: (code) => { if (code === 0) nerdFile.reload(); }
  }
  Process {
    running: true
    command: ["sh", "-c", "find \"$1\" -mtime +7 -delete 2>/dev/null; exit 0", "sh", mgr.nerdPath]
  }

  // ── INSTALLING, REMOVING ───────────────────────────────────────────
  // Then fontconfig and oracle are told: oracle's scan hands a family new
  // since the shell started to Qt (Oracle._registerNew), after which it
  // draws by name anywhere in the shell — here too.
  //
  // ONE AT A TIME, IN A QUEUE: a batch from the window and terminus' Install
  // can arrive together, and fc-cache is the slow half of each — none is
  // dropped for arriving while another runs. `busy` and `busyLabel` are what
  // the window's foot shows while one is out ("Installing…").
  //   install(files, then, label)   then(ok, installedPaths)
  //   remove(files, then, label)    then(ok, [])
  property bool busy: false
  property string busyKind: ""
  property string busyLabel: ""
  property var _jobs: []
  property var _after: null
  function install(files, then, label) { mgr.queue_("install", files, then, label); }
  function remove(files, then, label) {
    mgr.queue_("remove", (files || []).filter((f) => A.isUserFile(f, Paths.home())), then, label);
  }
  function queue_(kind, files, then, label) {
    if (!files || files.length === 0) { if (then) then(false, []); return; }
    mgr._jobs.push({ kind: kind, files: files, then: then || null,
                     label: label || (kind === "install" ? "Installing\u2026" : "Removing\u2026") });
    mgr.next_();
  }
  function next_() {
    if (mgr.busy || mgr._jobs.length === 0) return;
    const j = mgr._jobs.shift();
    mgr._after = j.then;
    mgr.busyKind = j.kind;
    mgr.busyLabel = j.label;
    mgr.busy = true;
    if (j.kind === "install") {
      installProc.command = ["sh", "-c", A.installCommand(j.files, Paths.home()), "sh"].concat(j.files);
      installProc.running = true;
    } else {
      removeProc.command = ["sh", "-c", A.removeCommand(j.files, Paths.home()), "sh"].concat(j.files);
      removeProc.running = true;
    }
  }
  Process {
    id: installProc
    stdout: StdioCollector { id: installOut; waitForEnd: true }
    onExited: (code) => mgr.settle_(code, String(installOut.text).split("\n").filter((l) => l !== ""))
  }
  Process {
    id: removeProc
    onExited: (code) => mgr.settle_(code, [])
  }
  // Busy until the rescan has the change in it, not just until the files
  // moved: otherwise an installed font's Install button came back for the
  // moment between the two.
  property var _post: null
  function settle_(code, paths) {
    mgr._post = { then: mgr._after, ok: code === 0, paths: paths };
    mgr._after = null;
    Oracle.scanFonts();
    mgr.scan();
  }
  function landed_() {
    const p = mgr._post;
    if (!p) return;
    mgr._post = null;
    mgr.busy = false;
    mgr.busyKind = "";
    mgr.busyLabel = "";
    if (p.then) { try { p.then(p.ok, p.paths); } catch (e) { console.warn("alexandria:", e); } }
    mgr.next_();
  }

  // ── THE WINDOW ─────────────────────────────────────────────────────
  // One, reused: a second font opened lands in the window already up.
  // Floating (hypr/lua/rules.lua, title "alexandria"), like oracle's.
  property var win: null
  property var _comp: null
  property var _waiting: []
  function _withComponent(fn) {
    if (mgr._comp && mgr._comp.status === Component.Ready) { fn(); return; }
    mgr._waiting.push(fn);
    if (mgr._comp) return;
    const comp = Qt.createComponent(Qt.resolvedUrl("AlexandriaWindow.qml"), Component.Asynchronous);
    mgr._comp = comp;
    const settle = () => {
      if (comp.status === Component.Loading) return;
      const queued = mgr._waiting;
      mgr._waiting = [];
      if (comp.status !== Component.Ready) {
        console.warn("alexandria:", comp.errorString());
        mgr._comp = null;
        return;
      }
      for (const f of queued) f();
    };
    if (comp.status === Component.Loading) comp.statusChanged.connect(settle);
    else settle();
  }
  function withWindow(fn) {
    mgr._withComponent(() => {
      let fresh = false;
      if (!mgr.win) {
        const t0 = Date.now();
        mgr.win = mgr._comp.createObject(mgr, { mgr: mgr, fileManager: mgr.fileManager });
        LagNotes.mark("alexandria window", t0);
        if (!mgr.win) return;
        fresh = true;
      }
      fn(mgr.win, fresh);
      mgr.win.visible = true;
      if (!fresh) Hyprland.dispatch('hl.dsp.focus({ window = "title:^(alexandria)$" })');
    });
  }
  // its window closed: the type goes with it
  function retire(w) {
    if (mgr.win === w) mgr.win = null;
    if (!mgr.win && mgr._waiting.length === 0) mgr._comp = null;
  }

  function open(paths) {
    const list = String(paths || "").split("\n").map((p) => p.trim()).filter((p) => p !== "");
    mgr.scan();
    mgr.withWindow((w) => w.load(list));
  }
  function glyphs(query) {
    mgr.scan();
    mgr.withWindow((w) => w.findGlyphs(query));
  }
  // The font picker: the library on `family`, the style nearest `weight`
  // (CSS), and a Use button; `fn(family, fcWeight)` when one is chosen.
  function pick(opts, fn) {
    mgr.scan();
    mgr.withWindow((w, fresh) => w.beginPick(opts || {}, fn, fresh));
  }

  IpcHandler {
    target: "Alexandria"
    function open(paths: string): string { mgr.open(paths); return "ok"; }
    function glyphs(query: string): string { mgr.glyphs(query); return "ok"; }
  }
}
