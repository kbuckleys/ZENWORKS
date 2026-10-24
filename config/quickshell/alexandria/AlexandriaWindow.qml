// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ALEXANDRIA'S WINDOW. The families down the left, each name set in itself,
// on shelves (all, bookmarks, monospaced, Nerd Fonts, imported, the system's);
// the one chosen on the right, three ways:
//
//   Specimen   your own line, large; every style of the family; a waterfall
//              of sizes; a paragraph to read — in any writing system the
//              face has every letter of (Greek, Cyrillic, Arabic, CJK…)
//   Glyphs     every character the face has, by Unicode block (and by Nerd
//              Fonts' set in the private use area), named, searchable by
//              name or codepoint, copied with a click
//   Info       the shared specimen (terminus' FontSpecimen), the files, the
//              package they came from, what fontconfig says of them
//
// Font files opened from terminus or artemis (bin/alexandria) are a shelf of
// their own, "Opened", with Install. Removing is for your own fonts only —
// to the trash, so it can come back — the system's belong to pacman.
//
// AS THE PICKER (oracle's Font row): a Use button in the foot, and Return.
//
//   ↑ ↓  ctrl+j/k   families        ← →   styles (on Glyphs: the glyph cursor)
//   alt+↑ ↓         families, from Glyphs too
//   tab shift+tab   shelves         ctrl+1 2 3 / ctrl+tab   pages
//   typing          the search      ctrl+e   write your own sample line
//   ctrl + − 0 / ctrl+wheel   the sample's size (on Glyphs: the cells)
//   ctrl+s bookmark     ctrl+c copy the family (on Glyphs: the character)
//   ctrl+click / shift+click / shift+↑↓ / ctrl+a   mark families — Install
//                   and Remove act on every marked one (esc unmarks)
//   ctrl+l (shift: back)   the specimen's language, among the face's own
//   return  Use (picking) · install (Opened) · copy the character (Glyphs;
//           shift: its codepoint)
//   ctrl+o  a font file to look at and install    delete  remove (imported)
//   esc     unwinds, then closes

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../morpheus"
import "../morpheus/controls" as Ctl
import "../terminus"
import "alexandria.js" as A

FloatingWindow {
  id: win
  title: "alexandria"
  // CLEAR, the ground laid in the stage around the sidebar, which wears an
  // inactive tab's thinner glass (user, 2026-10-10, as terminus and plato)
  color: Zenon.alpha(Zenon.layerBg, 0)
  implicitWidth: 1320
  implicitHeight: 860
  minimumSize: Qt.size(820, 520)

  property var mgr: null
  property var fileManager: null

  onVisibleChanged: if (!win.visible) Qt.callLater(() => { if (win.mgr) win.mgr.retire(win); win.destroy(); })
  onClosed: win.visible = false

  // ── THE FAMILIES ───────────────────────────────────────────────────────
  // installed (the manager's scan) and opened (files handed in, read with
  // fc-query, not folded: a file is what it says it is)
  property var loose: []
  property string query: ""
  readonly property string shelf: win.loose.length > 0 && win.shelfOpened ? "opened"
    : (win.mgr ? win.mgr.shelf : "all")
  property bool shelfOpened: false
  readonly property var shelves: (win.loose.length > 0
    ? [{ id: "opened", label: "Opened", glyph: "" }] : []).concat(A.SHELVES)
  readonly property var shown: {
    const fams = win.shelf === "opened"
      ? win.loose.filter((f) => A.familyMatches(f, win.query))
      : A.shelve(win.mgr ? win.mgr.families : [], win.shelf, win.query, win.mgr ? win.mgr.favs : {});
    // picking oracle's Monospace font: only what lays text out on a grid,
    // on every shelf, as its dropdown lists
    return win.picking && win.picking.mono ? fams.filter((f) => f.mono) : fams;
  }
  property int sel: 0
  readonly property var fam: win.sel >= 0 && win.sel < win.shown.length ? win.shown[win.sel] : null
  property int styleIdx: 0
  readonly property var style: win.fam && win.styleIdx >= 0 && win.styleIdx < win.fam.styles.length
    ? win.fam.styles[win.styleIdx] : null
  // the face a family's own name is set in: its regular, upright
  function repOf(f) {
    if (!f || f.styles.length === 0) return null;
    return f.styles[Math.max(0, A.styleNear(f, 400, false))];
  }

  // ── FACES, A FEW AT A FRAME ──────────────────────────────────────────
  // Every row's name is set in its own face, and the first time Qt draws a
  // face it opens and reads the file on the GUI thread: ~5.5 ms a family,
  // measured over all 338 installed. A screenful of rows arriving at once
  // (opening, a search, a fast scroll) asked for twenty-odd at once, and
  // lag.log had alexandria behind runs of 200–400 ms stalls (2026-10-09).
  //
  // So a row starts in the shell's own face and asks for its own here; the
  // gate grants them for ~6 ms a tick, rows on screen first. A face Qt has
  // drawn once is free after that, so a row of a face already seen takes it
  // straight away and scrolling back never swaps anything.
  //
  // The specimen's STYLE rows go through it too, and they were the bigger
  // half: each is the sample in its own style, so a 72-style family (Noto
  // Sans, Noto Serif) opened 72 files and shaped 72 lines in one frame —
  // 100–170 ms measured for the shaping alone, before a glyph was drawn.
  property var facedSeen: ({})
  property var faceQueue: []
  function faceKey(rep) { return rep.family + "\u0001" + rep.style; }
  function askFace(row) {
    win.faceQueue.push(row);
    if (!faceGate.running) faceGate.start();
  }
  Timer {
    id: faceGate
    interval: 16
    repeat: true
    onTriggered: {
      const top = famList.contentY;
      const bottom = top + famList.height;
      // a family row off screen waits; anything else (the styles under the
      // specimen) goes in the order it asked, which is top down
      const onScreen = (r) => {
        try { return !r.inFamList || (r.y + r.height > top && r.y < bottom); } catch (e) { return false; }
      };
      const q = win.faceQueue;
      win.faceQueue = q.filter(onScreen).concat(q.filter((r) => !onScreen(r)));
      const t0 = Date.now();
      while (win.faceQueue.length > 0 && Date.now() - t0 < 6) {
        const row = win.faceQueue.shift();
        // a row scrolled away and destroyed since it asked throws here
        try { row.takeFace(); } catch (e) {}
      }
      if (win.faceQueue.length === 0) stop();
    }
  }
  // Who should be selected, by name, across a rescan or a new filter: the
  // list is rebuilt, the family you were on is not lost.
  property string wantName: ""
  property int wantCss: 400
  // Deferred: `shown` is evaluated lazily, often from inside `fam`, and
  // moving `sel` there would be a binding loop.
  onShownChanged: Qt.callLater(win.reseat)
  // ── THE HIGHLIGHT'S RE-SEAT, as terminus' (see its thawPulse) ──────
  // SelectBar slides on a YAnimator, which runs on the render thread; a
  // workspace switch stops this window's frames and strands a slide in
  // flight between two rows, where it stayed until the next move (user,
  // 2026-10-08). A new list re-seats too: the selection is being put
  // somewhere, not moved, and a slide across a list that changed under
  // it ends on the wrong row as easily as the right one.
  property int thawPulse: 0
  Connections {
    target: Hyprland
    function onFocusedWorkspaceChanged() { win.thawPulse++; }
  }
  // typing a search lands on its best match, not on the family you were on
  property bool toTop: false
  function reseat() {
    const want = win.wantName !== "" ? win.wantName : win.toTop ? "" : win.lastFam;
    win.toTop = false;
    let at = want === "" ? -1 : win.shown.findIndex((f) => f.name === want);
    const hit = at >= 0 && win.wantName !== "" && win.shown[at].name === win.wantName;
    if (at < 0) at = Math.min(Math.max(0, win.sel), win.shown.length - 1);
    win.sel = at;
    win.thawPulse++;
    // the style asked for along with the family (the picker's weight)
    if (hit) {
      win.styleIdx = Math.max(0, A.styleNear(win.fam, win.wantCss, false));
      win.wantName = "";
      win.wantCss = 400;
    }
    famList.positionViewAtIndex(Math.max(0, at), hit ? ListView.Center : ListView.Contain);
  }
  property string lastFam: ""
  onFamChanged: {
    const name = win.fam ? win.fam.name : "";
    if (name === win.lastFam) return;
    win.lastFam = name;
    win.styleIdx = win.fam ? Math.max(0, A.styleNear(win.fam, 400, false)) : 0;
  }
  onStyleChanged: {
    win.loadCharset();
    win.loadFacts();
  }

  function moveFam(d) {
    if (win.shown.length === 0) return;
    win.sel = Math.max(0, Math.min(win.shown.length - 1, win.sel + d));
    famList.positionViewAtIndex(win.sel, ListView.Contain);
  }
  function moveStyle(d) {
    if (!win.fam) return;
    win.styleIdx = Math.max(0, Math.min(win.fam.styles.length - 1, win.styleIdx + d));
  }
  function setShelf(id) {
    win.marked = ({});
    win.shelfOpened = id === "opened";
    if (id !== "opened" && win.mgr) win.mgr.set("shelf", id);
  }
  function stepShelf(d) {
    const ids = win.shelves.map((s) => s.id);
    const at = ids.indexOf(win.shelf);
    win.setShelf(ids[(at + d + ids.length) % ids.length]);
  }
  readonly property string page: win.mgr ? win.mgr.page : "specimen"
  readonly property var pages: [["specimen", "Specimen", ""], ["glyphs", "Glyphs", "\u{F15FD}"], ["info", "Info", "\u{F064E}"]]
  function setPage(p) {
    if (win.mgr) win.mgr.set("page", p);
    if (p === "glyphs" && win.mgr) win.mgr.needNames();
    Qt.callLater(win.refocus);
  }
  function refocus() {
    if (sampleField.activeFocus) return;
    if (win.page === "glyphs") glyphField.forceActiveFocus();
    else famField.forceActiveFocus();
  }
  // THE highlight — the selected family, shelf, style, group and glyph all
  // wear this one fill, so "this one" reads the same everywhere
  readonly property color hiFill: Zenon.menuHi
  readonly property bool fav: !!(win.fam && win.mgr && win.mgr.favs[win.fam.name])
  function toggleFav() { if (win.fam && win.mgr && !win.fam.loose) win.mgr.setFav(win.fam.name, !win.fav); }

  // ── MARKED FAMILIES ────────────────────────────────────────────────────
  // Many at once, for Install and Remove: ctrl+click one, shift+click (or
  // shift+↑↓) a run, ctrl+a all of the shelf. By name; a shelf change lets
  // them go, and only the marked ones still shown count — a search does not
  // hide a family from the batch it is about to go into.
  property var marked: ({})
  readonly property var markedFams: win.shown.filter((f) => !!win.marked[f.name])
  function setMarks(names, on) {
    const m = Object.assign({}, win.marked);
    for (const n of names) { if (on) m[n] = true; else delete m[n]; }
    win.marked = m;
  }
  function toggleMark(i) {
    const f = win.shown[i];
    if (f) win.setMarks([f.name], !win.marked[f.name]);
  }
  function markRun(from, to) {
    const a = Math.max(0, Math.min(from, to)), b = Math.min(win.shown.length - 1, Math.max(from, to));
    win.setMarks(win.shown.slice(a, b + 1).map((f) => f.name), true);
  }
  function markAll() {
    const all = win.markedFams.length === win.shown.length && win.shown.length > 0;
    win.marked = all ? ({}) : win.shown.reduce((m, f) => { m[f.name] = true; return m; }, {});
  }
  // what Install and Remove act on: the marked, else the one you are on
  readonly property var acting: win.markedFams.length > 0 ? win.markedFams : (win.fam ? [win.fam] : [])
  function famWord(n) { return n === 1 ? "1 family" : n + " families"; }

  // ── FILES HANDED IN ────────────────────────────────────────────────────
  function load(paths) {
    const fonts = (paths || []).filter(A.isFontFile);
    if (fonts.length === 0) {
      if (win.loose.length > 0 && win.shelf === "opened") win.setShelf(win.mgr ? win.mgr.shelf : "all");
      return;
    }
    looseProc.command = ["sh", "-c", "for f in \"$@\"; do fc-query -f '"
      + A.LIST_FORMAT + "' \"$f\" 2>/dev/null; done", "sh"].concat(fonts);
    looseProc.running = true;
  }
  Process {
    id: looseProc
    stdout: StdioCollector {
      id: looseOut
      waitForEnd: true
      onStreamFinished: {
        const got = A.parseList(looseOut.text, Paths.home(), (x) => x);
        for (const f of got) f.loose = true;
        // still there from before, and not handed again: kept
        const names = got.map((f) => f.name);
        win.loose = got.concat(win.loose.filter((f) => names.indexOf(f.name) < 0));
        win.shelfOpened = true;
        // A BATCH ARRIVES MARKED: several families handed in at once (the
        // picker, a drop, terminus) are there to be installed together, so
        // Install reads "Install 6" straight away — esc to take one at a time
        win.marked = got.length > 1
          ? got.filter((f) => !win.isInstalled(f)).reduce((m, f) => { m[f.name] = true; return m; }, {})
          : ({});
        win.query = "";
        win.wantName = got.length > 0 ? got[0].name : "";
        win.reseat();
      }
    }
  }
  // Qt draws a face by name only once it knows the file: an opened one is
  // handed to it here (an installed one Qt read at start, or oracle's scan
  // registered after an install)
  Instantiator {
    model: win.loose.reduce((acc, f) => acc.concat(f.files), [])
    delegate: FontLoader { required property var modelData; source: Strings.fileUrl(modelData) }
  }
  // Is this opened face installed? Its family and style among the installed.
  function installedLike(s) {
    for (const f of (win.mgr ? win.mgr.families : []))
      for (const t of f.styles) if (t.family === s.family && t.style === s.style) return t.file;
    return "";
  }
  function isInstalled(f) { return f.styles.every((s) => win.installedLike(s) !== ""); }
  readonly property bool looseInstalled: !!(win.fam && win.fam.loose && win.isInstalled(win.fam))
  // the opened families Install would put in: the marked, or the one you are on
  readonly property var installable: win.acting.filter((f) => f.loose && !win.isInstalled(f))
  readonly property bool installing: !!win.mgr && win.mgr.busy
  // the words of the work under way, kept while its pill fades out so it
  // does not empty first
  property string busyShown: win.mgr ? win.mgr.busyLabel : ""
  Connections {
    target: win.mgr
    function onBusyLabelChanged() { if (win.mgr.busyLabel !== "") win.busyShown = win.mgr.busyLabel; }
  }

  function installOpened() {
    const fams = win.installable;
    if (fams.length === 0 || !win.mgr) return;
    const name = fams.length === 1 ? fams[0].name : win.famWord(fams.length);
    const files = fams.reduce((acc, f) => acc.concat(f.files.filter((x) => acc.indexOf(x) < 0)), []);
    win.marked = ({});
    win.mgr.install(files, (ok) => win.say(ok ? name + " installed" : "Could not install " + name),
                    fams.length === 1 ? "Installing\u2026" : "Installing " + win.famWord(fams.length) + "\u2026");
  }
  function chooseFile() {
    if (!win.fileManager) return;
    // many at once: every file marked in the picker comes back, and they
    // arrive marked here, so Install takes the lot
    win.fileManager.choose(false, Paths.home() + "/Downloads", (paths) => {
      if (paths && paths.length > 0) win.load(paths);
    }, undefined, true);
  }

  // ── REMOVING (imported only) ──────────────────────────────────────────────
  // the imported among what Remove acts on, and their files
  readonly property var removeFams: win.acting.filter((f) => !f.loose && f.user)
  readonly property var removable: win.removeFams.reduce((acc, f) =>
    acc.concat(f.files.filter((x) => A.isUserFile(x, Paths.home()) && acc.indexOf(x) < 0)), [])
  property bool asking: false
  property int askPick: 1
  function askRemove() {
    if (win.removable.length === 0) {
      if (win.acting.some((f) => !f.loose)) win.say(win.acting.length > 1 ? "System fonts — pacman's to remove" : "A system font — pacman's to remove");
      return;
    }
    win.askPick = 1;
    win.asking = true;
  }
  function answer(yes) {
    win.asking = false;
    if (!yes || !win.mgr) { win.refocus(); return; }
    const fams = win.removeFams;
    const name = fams.length === 1 ? fams[0].name : win.famWord(fams.length);
    const files = win.removable;
    win.marked = ({});
    win.mgr.remove(files, (ok) => win.say(ok ? name + " moved to the trash" : "Could not remove " + name),
                   fams.length === 1 ? "Removing\u2026" : "Removing " + win.famWord(fams.length) + "\u2026");
    win.refocus();
  }

  // ── THE PICKER ─────────────────────────────────────────────────────────
  property var picking: null
  property var pickFn: null
  property bool pickFresh: false
  function beginPick(opts, fn, fresh) {
    win.picking = { title: opts.title || "Choose a font", mono: !!opts.mono };
    win.pickFn = fn || null;
    win.pickFresh = !!fresh;
    win.shelfOpened = false;
    win.query = "";
    if (opts.family) {
      win.wantName = String(opts.family);
      win.wantCss = Number(opts.weight) || 400;
      if (win.mgr && win.mgr.shelf !== "all") win.mgr.set("shelf", "all");
      win.reseat();
    }
    Qt.callLater(win.refocus);
  }
  function usePick() {
    if (!win.picking || !win.fam || !win.style) return;
    const fn = win.pickFn, f = win.fam.name, w = win.style.fcWeight;
    const close = win.pickFresh;
    win.picking = null;
    win.pickFn = null;
    if (fn) { try { fn(f, w); } catch (e) { console.warn("alexandria pick:", e); } }
    if (close) win.visible = false;
    else win.say(f + " chosen");
  }
  function cancelPick() {
    const close = win.pickFresh;
    win.picking = null;
    win.pickFn = null;
    if (close) win.visible = false;
  }

  // ── THE SAMPLE AND ITS SIZE ────────────────────────────────────────────
  // ── THE LANGUAGE IT IS SET IN ──────────────────────────────────────────
  // The scripts this face has every letter of; the one asked for when it is
  // among them, else the face's first (Latin when it has it; an Arabic-only
  // face opens in Arabic). A face without Greek shown "in Greek" would be
  // Qt's fallback font, not this one. Your own line belongs to the script it
  // was written under, and comes back with it.
  readonly property var langs: A.scriptsOf(win.charset)
  readonly property var script: {
    const want = win.mgr ? win.mgr.lang : "latin";
    return win.langs.find((s) => s.id === want) || win.langs[0] || A.SCRIPTS[0];
  }
  function setLang(id) {
    if (!win.mgr) return;
    win.mgr.set("lang", id);
    win.mgr.set("sample", "");
  }
  function stepLang(d) {
    const ids = win.langs.map((s) => s.id);
    if (ids.length < 2) { win.say(win.langs.length === 1 ? "Only " + win.langs[0].label + " in this face" : "No language to switch to"); return; }
    const at = Math.max(0, ids.indexOf(win.script.id));
    win.setLang(ids[(at + d + ids.length) % ids.length]);
  }
  readonly property string sample: win.mgr && win.mgr.sample !== "" && win.script.id === win.mgr.lang
    ? win.mgr.sample : win.script.samples[0]
  readonly property int size: win.mgr ? win.mgr.sampleSize : 56
  readonly property int cell: win.mgr ? win.mgr.glyphSize : 64
  readonly property var sizeSteps: [12, 14, 16, 18, 20, 24, 28, 32, 40, 48, 56, 64, 72, 88, 104, 120, 140, 160]
  // where the size sits along its travel, 0–1, for the head's meter
  readonly property real zoomAt: win.page === "glyphs" ? (win.cell - 36) / (160 - 36)
    : Math.max(0, win.sizeSteps.findIndex((s) => s >= win.size)) / (win.sizeSteps.length - 1)
  function zoomSeek(f) {
    if (!win.mgr) return;
    if (win.page === "glyphs") win.mgr.set("glyphSize", 36 + Math.round(f * (160 - 36) / 8) * 8);
    else win.mgr.set("sampleSize", win.sizeSteps[Math.round(f * (win.sizeSteps.length - 1))]);
  }
  function zoom(d) {
    if (!win.mgr) return;
    if (win.page === "glyphs") {
      win.mgr.set("glyphSize", d === 0 ? 64 : Math.max(36, Math.min(160, win.cell + d * 8)));
    } else {
      const steps = win.sizeSteps;
      let at = steps.findIndex((s) => s >= win.size);
      if (at < 0) at = steps.length - 1;
      win.mgr.set("sampleSize", d === 0 ? 56 : steps[Math.max(0, Math.min(steps.length - 1, at + d))]);
    }
  }
  function nextSample() {
    if (!win.mgr) return;
    const ss = win.script.samples;
    win.mgr.set("lang", win.script.id);
    win.mgr.set("sample", ss[(ss.indexOf(win.sample) + 1) % ss.length]);
  }

  // ── THE FACE'S CHARACTERS ──────────────────────────────────────────────
  property var charset: A.indexOf([])
  property string charsetFor: ""
  function loadCharset() {
    if (!win.style) { win.charset = A.indexOf([]); return; }
    const key = win.style.file + "#" + win.style.index;
    if (key === win.charsetFor) return;
    win.charsetFor = key;
    csProc.running = false;
    csProc.command = ["fc-query", "-i", String(win.style.index), "-f", "%{charset}", win.style.file];
    csProc.running = true;
  }
  Process {
    id: csProc
    stdout: StdioCollector {
      id: csOut
      waitForEnd: true
      onStreamFinished: { win.charset = A.parseCharset(csOut.text); win.group = -1; win.gsel = 0; }
    }
  }
  // only while the glyph page shows — a face of 45,000 characters (CJK)
  // took ~400 ms to group, on every family passed (measured in the shell's
  // own engine, 2026-10-09)
  readonly property var groups: win.page !== "glyphs" ? [] : A.groupsOf(win.charset, win.mgr ? win.mgr.blocks : [])
  property int group: -1
  property string gquery: ""
  property var found: []
  Timer { id: findDelay; interval: 140; onTriggered: win.runSearch() }
  onGqueryChanged: findDelay.restart()
  onCharsetChanged: if (win.gquery !== "") findDelay.restart()
  function runSearch() {
    win.found = win.gquery.trim() === "" ? []
      : A.searchGlyphs(win.charset, win.gquery, win.mgr ? win.mgr.uni : null, win.mgr ? win.mgr.nerd : null);
    win.gsel = 0;
  }
  // what the grid walks: a search's answer, a group, or everything
  readonly property var gix: win.gquery.trim() !== "" ? A.indexOfList(win.found)
    : (win.group >= 0 && win.group < win.groups.length ? A.groupIndex(win.charset, win.groups[win.group]) : win.charset)
  property int gsel: 0
  readonly property int gcp: A.codeAt(win.gix, win.gsel)
  function findGlyphs(q) {
    win.setPage("glyphs");
    win.gquery = String(q || "");
  }
  function moveGlyph(d) {
    if (win.gix.count === 0) return;
    win.gsel = Math.max(0, Math.min(win.gix.count - 1, win.gsel + d));
    glyphGrid.positionViewAtIndex(win.gsel, GridView.Contain);
  }
  function nameOf(cp) {
    return cp < 0 || !win.mgr ? "" : A.glyphName(cp, win.mgr.uni, win.mgr.nerd);
  }
  function nerdOf(cp) {
    const n = win.mgr && win.mgr.nerd[cp];
    return n && n.length > 0 ? n[0] : "";
  }

  // ── FACTS ──────────────────────────────────────────────────────────────
  property var facts: ({})
  function loadFacts() {
    win.facts = ({});
    if (!win.style) return;
    factProc.running = false;
    factProc.command = ["sh", "-c",
      "fc-query -i \"$2\" -f '%{fontversion}\\t%{foundry}\\t%{postscriptname}\\t%{lang}\\t%{capability}\\n' \"$1\" 2>/dev/null | head -n1;"
      + " pacman -Qqo \"$1\" 2>/dev/null | head -n1; du -h \"$1\" 2>/dev/null | cut -f1",
      "sh", win.style.file, String(win.style.index)];
    factProc.running = true;
  }
  Process {
    id: factProc
    stdout: StdioCollector {
      id: factOut
      waitForEnd: true
      onStreamFinished: {
        const l = String(factOut.text).split("\n");
        const f = (l[0] || "").split("\t");
        const v = Number(f[0]);
        win.facts = {
          version: isNaN(v) || v <= 0 ? "" : (v / 65536).toFixed(3).replace(/0+$/, "").replace(/\.$/, ""),
          foundry: f[1] && f[1] !== "unknown" ? f[1] : "",
          postscript: f[2] || "",
          langs: f[3] ? f[3].split("|").filter((x) => x !== "").length : 0,
          features: f[4] ? f[4].replace(/^otlayout:/, "").split(/\s*otlayout:/).join(" ") : "",
          pkg: l.length > 2 ? (l[1] || "") : "",
          size: (l.length > 2 ? l[2] : l[1]) || "",
        };
      }
    }
  }

  // ── COPYING, AND SAYING SO ─────────────────────────────────────────────
  function copy(text, what) {
    Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | wl-copy", "sh", String(text)]);
    win.say("Copied " + (what || text));
  }
  function copyGlyph(asCode) {
    if (win.gcp < 0) return;
    if (asCode) win.copy(A.uplus(win.gcp));
    else win.copy(A.charOf(win.gcp), A.charOf(win.gcp) + "  " + A.uplus(win.gcp));
  }
  property string said: ""
  function say(t) { win.said = t; sayTimer.restart(); }
  Timer { id: sayTimer; interval: 1800; onTriggered: win.said = "" }

  Component.onCompleted: {
    if (win.mgr && win.mgr.page === "glyphs") win.mgr.needNames();
    Qt.callLater(win.refocus);
  }

  // ── KEYS ───────────────────────────────────────────────────────────────
  // Every field hands its keys here first; what is not navigation is typing.
  function navKey(e) {
    const k = e.key, ctrl = e.modifiers & Qt.ControlModifier, alt = e.modifiers & Qt.AltModifier,
          shift = e.modifiers & Qt.ShiftModifier;
    const glyphs = win.page === "glyphs";
    if (win.asking) {
      if (k === Qt.Key_Escape) win.answer(false);
      else if (k === Qt.Key_Return || k === Qt.Key_Enter) win.answer(win.askPick === 0);
      else if (k === Qt.Key_Left || k === Qt.Key_Right || k === Qt.Key_Tab) win.askPick = 1 - win.askPick;
      return true;
    }
    if (k === Qt.Key_Escape) {
      if (win.markedFams.length > 0) win.marked = ({});
      else if (glyphs && win.gquery !== "") win.gquery = "";
      else if (glyphs && win.group >= 0) win.group = -1;
      else if (win.query !== "") win.query = "";
      else if (win.picking) win.cancelPick();
      // outside the picker esc never closes the library
      return true;
    }
    if (ctrl && (k === Qt.Key_Equal || k === Qt.Key_Plus)) { win.zoom(1); return true; }
    if (ctrl && k === Qt.Key_Minus) { win.zoom(-1); return true; }
    if (ctrl && k === Qt.Key_0) { win.zoom(0); return true; }
    if (ctrl && k >= Qt.Key_1 && k <= Qt.Key_3) { win.setPage(win.pages[k - Qt.Key_1][0]); return true; }
    if (ctrl && (k === Qt.Key_Tab || k === Qt.Key_Backtab)) {
      const ids = win.pages.map((p) => p[0]);
      const d = (k === Qt.Key_Backtab || shift) ? -1 : 1;
      win.setPage(ids[(ids.indexOf(win.page) + d + ids.length) % ids.length]);
      return true;
    }
    if (k === Qt.Key_Tab || k === Qt.Key_Backtab) { win.stepShelf(k === Qt.Key_Backtab || shift ? -1 : 1); return true; }
    if (ctrl && k === Qt.Key_S) { win.toggleFav(); return true; }
    if (ctrl && k === Qt.Key_L) { win.setPage("specimen"); win.stepLang(shift ? -1 : 1); return true; }
    if (ctrl && k === Qt.Key_E) { win.setPage("specimen"); sampleField.forceActiveFocus(); sampleField.selectAll(); return true; }
    if (ctrl && k === Qt.Key_O) { win.chooseFile(); return true; }
    if (ctrl && k === Qt.Key_F) { win.refocus(); return true; }
    if (ctrl && k === Qt.Key_A && !glyphs && famField.text === "") { win.markAll(); return true; }
    if (ctrl && k === Qt.Key_C) {
      if (glyphs) win.copyGlyph(false);
      else if (win.fam) win.copy(win.fam.name);
      return true;
    }
    if (k === Qt.Key_Delete) { win.askRemove(); return true; }
    if (alt && (k === Qt.Key_Up || k === Qt.Key_Down)) { win.moveFam(k === Qt.Key_Up ? -1 : 1); return true; }
    if (ctrl && (k === Qt.Key_J || k === Qt.Key_K)) { win.moveFam(k === Qt.Key_K ? -1 : 1); return true; }
    if (glyphs) {
      const cols = glyphGrid.cols;
      if (k === Qt.Key_Left) { win.moveGlyph(-1); return true; }
      if (k === Qt.Key_Right) { win.moveGlyph(1); return true; }
      if (k === Qt.Key_Up) { win.moveGlyph(-cols); return true; }
      if (k === Qt.Key_Down) { win.moveGlyph(cols); return true; }
      if (k === Qt.Key_PageUp) { win.moveGlyph(-cols * 6); return true; }
      if (k === Qt.Key_PageDown) { win.moveGlyph(cols * 6); return true; }
      if (k === Qt.Key_Return || k === Qt.Key_Enter) {
        if (win.picking && ctrl) win.usePick(); else win.copyGlyph(!!shift);
        return true;
      }
      return false;
    }
    if (shift && (k === Qt.Key_Up || k === Qt.Key_Down)) {
      const from = win.sel;
      win.moveFam(k === Qt.Key_Up ? -1 : 1);
      win.markRun(from, win.sel);
      return true;
    }
    if (k === Qt.Key_Up) { win.moveFam(-1); return true; }
    if (k === Qt.Key_Down) { win.moveFam(1); return true; }
    if (k === Qt.Key_PageUp) { win.moveFam(-12); return true; }
    if (k === Qt.Key_PageDown) { win.moveFam(12); return true; }
    if (k === Qt.Key_Left && famField.text === "") { win.moveStyle(-1); return true; }
    if (k === Qt.Key_Right && famField.text === "") { win.moveStyle(1); return true; }
    if (k === Qt.Key_Return || k === Qt.Key_Enter) {
      if (win.picking) win.usePick();
      else if (win.installable.length > 0 && !win.installing) win.installOpened();
      return true;
    }
    return false;
  }

  readonly property var hintRows: {
    if (win.asking) return [["return", "remove"], ["esc", "keep"]];
    const out = [];
    if (win.markedFams.length > 0) out.push(["esc", "unmark " + win.markedFams.length]);
    if (win.picking) out.push(["return", "use"]);
    if (win.page === "glyphs") {
      out.push(["return", "copy"], ["shift return", "codepoint"], ["alt ↑↓", "family"]);
    } else {
      out.push(["↑↓", "family"], ["←→", "style"], ["ctrl e", "your line"]);
      if (win.langs.length > 1) out.push(["ctrl l", "language"]);
      if (win.installable.length > 0) out.push(["return", "install"]);
      out.push(["shift ↑↓", "mark"], ["ctrl a", "mark all"]);
    }
    out.push(["ctrl wheel", "size"], ["ctrl s", "bookmark"], ["tab", "shelf"], ["ctrl tab", "page"]);
    if (win.removable.length > 0) out.push(["delete", "remove"]);
    out.push(["ctrl o", "open a file"]);
    if (win.picking) out.push(["esc", "cancel"]);
    return out;
  }

  // ── DROPPED FILES ──────────────────────────────────────────────────────
  DropArea {
    anchors.fill: parent
    keys: ["text/uri-list"]
    onDropped: (d) => {
      const paths = (d.urls || []).map((u) => decodeURIComponent(String(u).replace(/^file:\/\//, "")));
      win.load(paths);
    }
  }

  // ── THE STAGE ──────────────────────────────────────────────────────────
  Item {
    id: stage
    anchors.fill: parent
    layer.enabled: removeSheet.cardInk > 0.01
    layer.effect: MultiEffect { blurEnabled: true; blurMax: 40; blur: removeSheet.cardInk; autoPaddingEnabled: false }

    // the window's ground, everywhere but the sidebar
    Rectangle {
      z: -1
      x: side.width
      width: parent.width - x
      height: side.height
      color: Zenon.layerBg
    }
    Rectangle {
      z: -1
      y: side.height
      width: parent.width
      height: parent.height - y
      color: Zenon.layerBg
    }

    // ── the shelves and the families ─────────────────────────────────────
    Item {
      id: side
      // THE WINDOW'S WHOLE HEIGHT: the foot starts beside it rather than
      // under it (user, 2026-10-10 — as delphi's)
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: Math.round(Math.min(360, Math.max(260, win.width * 0.24)))

      // TERMINUS' AND PLATO'S TWO LAYERS (user, 2026-10-14: "all must
      // match"): an inactive tab's thinner glass, then the sheet's veil
      // over it. The veil alone left this a pale band beside them.
      Rectangle { anchors.fill: parent; color: Zenon.alpha(Zenon.tabAwayInk, Zenon.tabAway(Zenon.layerBg.a)) }
      Rectangle { anchors.fill: parent; color: Zenon.ground; opacity: 0.6 }
      Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Zenon.border }

      // the search
      Rectangle {
        id: famSearch
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        height: 34
        radius: Zenon.windowRadius
        color: Zenon.wash(0.06)
        border.width: 1
        border.color: Zenon.border
        Behavior on border.color { ColorAnimation { duration: Zenon.fast } }
        Text {
          id: famLens
          anchors.left: parent.left
          anchors.leftMargin: 13
          anchors.verticalCenter: parent.verticalCenter
          text: ""
          color: Zenon.accentMuted
          font.family: Zenon.glyphFace
          font.pixelSize: Zenon.px(13)
        }
        TextInput {
          id: famField
          // the shell's breathing caret, as every field wears
          cursorDelegate: Caret { field: famField }
          anchors.left: famLens.right
          anchors.leftMargin: 9
          anchors.right: famClear.visible ? famClear.left : parent.right
          anchors.rightMargin: famClear.visible ? 8 : 13
          anchors.verticalCenter: parent.verticalCenter
          text: win.query
          onTextChanged: if (win.query !== text) { win.toTop = true; win.query = text; }
          color: Zenon.ink
          selectionColor: Zenon.alpha(Zenon.cyan, 0.4)
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(15)
          clip: true
          Keys.onPressed: (e) => { if (win.navKey(e)) e.accepted = true; }
          Text {
            visible: famField.text === ""
            anchors.verticalCenter: parent.verticalCenter
            text: win.mgr && win.mgr.families.length > 0
              ? "Search " + win.mgr.families.length + " families" : "Reading the fonts…"
            color: Zenon.accentMuted
            font: famField.font
          }
        }
        // focused for typing: terminus' held ring (user, 2026-10-11 — every
        // text field wears it, its own border staying neutral)
        ClearChip {
          id: famClear
          size: Zenon.px(15)
          shown: famField.text !== ""
          anchors.right: parent.right
          anchors.rightMargin: 9
          anchors.verticalCenter: parent.verticalCenter
          onClicked: { famField.text = ""; famField.forceActiveFocus(); }
        }
        HeldRing { anchors.fill: parent; radius: parent.radius; z: 10; on: famField.activeFocus }
      }

      // the shelves
      Column {
        id: shelfCol
        anchors.top: famSearch.bottom
        anchors.topMargin: 10
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        spacing: 1
        Repeater {
          model: win.shelves
          // terminus/ShelfRow — the shelves' row, shared with delphi's pages
          delegate: ShelfRow {
            id: shelfRow
            required property var modelData
            width: shelfCol.width
            glyph: shelfRow.modelData.glyph
            label: shelfRow.modelData.label
            here: win.shelf === shelfRow.modelData.id
            fill: win.hiFill
            count: String(shelfRow.modelData.id === "opened" ? win.loose.length
              : A.shelfCount(win.mgr ? win.mgr.families : [], shelfRow.modelData.id, win.mgr ? win.mgr.favs : {}))
            onClicked: { win.setShelf(shelfRow.modelData.id); win.refocus(); }
          }
        }
      }

      Rectangle {
        id: shelfRule
        anchors.top: shelfCol.bottom
        anchors.topMargin: 10
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Zenon.border
      }

      // the families, each in itself
      ListView {
        id: famList
        anchors.top: shelfRule.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        clip: true
        topMargin: 6
        bottomMargin: 6
        boundsBehavior: Flickable.StopAtBounds
        model: win.shown
        cacheBuffer: 400
        // ONE row height, for the rows and the bar alike, grown with the
        // shell's font size (the line under the name is Zenon.px)
        readonly property int rowH: 37 + Zenon.px(11)
        SelectBar { view: famList; host: win; index: win.sel; rowH: famList.rowH; color: win.hiFill; radius: Zenon.windowRadius; inset: 8 }
        delegate: Item {
          id: famRow
          required property var modelData
          required property int index
          readonly property var rep: win.repOf(famRow.modelData)
          width: famList.width
          height: famList.rowH
          // its own face once the gate grants it — see faceGate
          readonly property bool inFamList: true
          property bool faced: false
          function takeFace() {
            famRow.faced = true;
            // laid out now, so the gate's clock sees what the face cost
            void famName.implicitWidth;
            if (famRow.rep) win.facedSeen[win.faceKey(famRow.rep)] = true;
          }
          Component.onCompleted: {
            if (!famRow.rep || win.facedSeen[win.faceKey(famRow.rep)]) famRow.faced = true;
            else win.askFace(famRow);
          }
          // marked for a batch: a card of its own under the highlight's,
          // inset as the highlight is, ringed so a marked row the cursor is on
          // still reads as both
          readonly property bool ticked: !!win.marked[famRow.modelData.name]
          Rectangle {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            anchors.topMargin: 1
            anchors.bottomMargin: 1
            radius: Zenon.windowRadius
            color: Zenon.alpha(Zenon.cyan, 0.08)
            border.width: 1
            border.color: Zenon.alpha(Zenon.cyan, 0.35)
            opacity: famRow.ticked ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: Zenon.fast } }
          }
          // BY BASELINE, NOT STACKED. The name is set in its own face, and a
          // face's line height is its own business: a tall one (CJK, some
          // display and symbol fonts) made the name's box twice as high and
          // pushed the line under it down into the next row — off the
          // highlight, which stays on the row (user, 2026-10-09). Both lines
          // sit on fixed baselines whatever the face's metrics.
          Text {
            id: famName
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.right: famMarks.left
            anchors.rightMargin: 8
            anchors.baseline: parent.top
            anchors.baselineOffset: 26
            elide: Text.ElideRight
            text: famRow.modelData.name
            color: famRow.index === win.sel ? Zenon.ink : Zenon.accentSoft
            font.family: famRow.faced && famRow.rep ? famRow.rep.family : Zenon.face
            font.styleName: famRow.faced && famRow.rep ? famRow.rep.style : ""
            font.pixelSize: 19
          }
          Text {
            anchors.left: famName.left
            anchors.right: famName.right
            anchors.baseline: parent.top
            anchors.baselineOffset: famList.rowH - 6
            elide: Text.ElideRight
            text: {
              const f = famRow.modelData;
              const bits = [f.styles.length === 1 ? "1 style" : f.styles.length + " styles"];
              if (f.mono) bits.push("mono");
              if (f.loose) bits.push(win.installedLike(f.styles[0]) !== "" ? "installed" : "not installed");
              else if (f.user) bits.push("imported");
              return bits.join("  ·  ");
            }
            color: Zenon.accentMuted
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(11)
          }
          Row {
            id: famMarks
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            Text {
              visible: !!(win.mgr && win.mgr.favs[famRow.modelData.name])
              text: "\uF02E"
              color: Zenon.sand
              font.family: Zenon.glyphFace
              font.pixelSize: Zenon.px(12)
            }
            Text {
              visible: famRow.modelData.nerd
              text: "\u{F0AEC}"
              color: Zenon.magenta
              font.family: Zenon.glyphFace
              font.pixelSize: Zenon.px(12)
            }
            // imported (~/.local/share/fonts): the shelf's own glyph
            Text {
              visible: !!famRow.modelData.user
              text: A.SHELVES.find((s) => s.id === "user").glyph
              color: Zenon.green
              font.family: Zenon.glyphFace
              font.pixelSize: Zenon.px(12)
            }
          }
          MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            onClicked: (m) => {
              if (m.modifiers & Qt.ShiftModifier) win.markRun(win.sel, famRow.index);
              else if (m.modifiers & Qt.ControlModifier) win.toggleMark(famRow.index);
              win.sel = famRow.index;
              win.refocus();
            }
            onDoubleClicked: if (win.picking) win.usePick()
          }
        }
        EmptyState {
          anchors.centerIn: parent
          visible: famList.count === 0 && !!win.mgr && !win.mgr.scanning
          filtered: win.query !== ""
        }
      }
      ElasticScroll { anchors.fill: famList; view: famList }
      Scrollbar { flick: famList; anchors.right: famList.right; anchors.top: famList.top; anchors.bottom: famList.bottom }
      TopShade { view: famList; x: famList.x; y: famList.y; width: famList.width }
    }

    // ── ROWS GO UNDER THE HEAD, AND UP OUT OF THE FOOT ──────────────────
    // morpheus/ScrollEdge, as ceres' and terminus' do: what has scrolled off
    // carries on under the chrome, frosted. Before the head so it draws over
    // them.
    Repeater {
      model: [specFlick, infoFlick]
      delegate: ScrollEdge {
        required property var modelData
        view: modelData
        follow: true
        bar: head
        visible: modelData.visible
      }
    }
    // The glyph grid's chrome is the head AND its own search strip: the grid
    // starts below the search, so its rows go under both, frosted all the way
    // (user, 2026-10-09) — the search field's own wash is translucent, and the
    // body it sits in is drawn after this. Not a bar of its own: only a span
    // to measure, from the head's top down to the grid's.
    Item {
      id: glyphChrome
      x: head.x
      y: head.y
      width: head.width
      height: head.height + glyphGrid.y
    }
    ScrollEdge {
      view: glyphGrid
      follow: true
      bar: glyphChrome
      visible: glyphGrid.visible
    }

    // ── the head ─────────────────────────────────────────────────────────
    Item {
      id: head
      anchors.left: side.right
      anchors.right: parent.right
      anchors.top: parent.top
      height: 64

      Column {
        anchors.left: parent.left
        anchors.leftMargin: 22
        anchors.right: parent.right
        anchors.rightMargin: 32 + headTools.implicitWidth
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        Text {
          width: parent.width
          elide: Text.ElideRight
          text: win.fam ? win.fam.name : ""
          color: Zenon.ink
          font.family: win.style ? win.style.family : Zenon.face
          font.styleName: win.style ? win.style.style : ""
          font.pixelSize: 24
        }
        Text {
          width: parent.width
          elide: Text.ElideRight
          text: win.fam && win.style
            ? A.styleLabel(win.fam, win.style) + "  ·  " + A.weightName(win.style.css) + " " + win.style.css
              + (win.style.mono ? "  ·  monospaced" : "") + (win.picking ? "  ·  " + win.picking.title : "")
            : ""
          color: win.picking ? Zenon.cyan : Zenon.accentMuted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(13)
        }
      }

      // ── THE TOOLS, IN A ROW THAT CLOSES UP ──
      // Whatever is not there takes no room: the bookmark on an opened file
      // (it cannot be bookmarked), the size meter on Info (nothing to size).
      // Anchored side by side, a hidden one left its hole (user, 2026-10-09).
      // Laid out from a FIXED right edge: a Row that shrank to its content
      // jumped right as a whole the moment the meter hid, then its children
      // glided back from where they had been (segments-jump.mp4, 2026-10-11).
      // So the row is wide and right-to-left — children listed right first —
      // and only what stood beside a hidden tool moves.
      Row {
        id: headTools
        anchors.right: parent.right
        anchors.rightMargin: 16
        width: parent.width / 2
        layoutDirection: Qt.RightToLeft
        anchors.verticalCenter: parent.verticalCenter
        spacing: 12
        move: Transition { NumberAnimation { properties: "x"; duration: Zenon.fast; easing.type: Zenon.ease } }

        Rectangle {
          id: favBtn
          anchors.verticalCenter: parent.verticalCenter
          width: 32
          height: 32
          radius: Zenon.windowRadius
          visible: !!win.fam && !win.fam.loose
          color: favMa.pressed ? Zenon.wash(0.08) : Zenon.wash(0.03)
          border.width: 1
          border.color: Zenon.border
          Text {
            anchors.centerIn: parent
            text: win.fav ? "\uF02E" : "\uF097"
            color: win.fav ? Zenon.sand : Zenon.accentMuted
            font.family: Zenon.glyphFace
            font.pixelSize: Zenon.px(15)
          }
          MouseArea {
            id: favMa
            anchors.fill: parent
            hoverEnabled: true
            onClicked: win.toggleFav()
            onContainsMouseChanged: containsMouse ? tips.show(favBtn, win.fav ? "Remove bookmark" : "Bookmark", "ctrl s") : tips.hide(favBtn)
          }
        }

        // the pages: ONE control, three halves — terminus/Segments (the
        // suite's switch, since 2026-10-11): one border, a hairline between,
        // one highlight that slides to the page you are on
        Segments {
          id: tabs
          anchors.verticalCenter: parent.verticalCenter
          height: 32
          textSize: Zenon.px(16)
          ink: Zenon.accentKey
          // [value, label] only: a third field is a note under the word in
          // Segments (since 2026-10-14), so the glyph goes before it instead
          options: win.pages.map((p) => [p[0], p[1]])
          glyphOf: (v) => { const p = win.pages.find((q) => q[0] === v); return p ? p[2] : ""; }
          pad: 24
          current: win.page
          onChose: (v) => win.setPage(v)
          onPointed: (v, at, inside) => {
            const i = win.pages.findIndex((p) => p[0] === v);
            if (inside && i >= 0) tips.show(at, win.pages[i][1], "ctrl " + (i + 1));
            else tips.hide(at);
          }
        }

        // How large: terminus' meter (ZoomMeter.qml), as picasso's bar has it —
        // the sample's size on Specimen, the cells on Glyphs
        Item {
          id: zoomBox
          anchors.verticalCenter: parent.verticalCenter
          visible: win.page !== "info"
          width: zoomMeter.implicitWidth + 20
          height: 32
          ZoomMeter {
            id: zoomMeter
            anchors.centerIn: parent
            value: win.zoomAt
            onSeek: (f) => win.zoomSeek(f)
            onStep: (d) => win.zoom(d)
            onReset: win.zoom(0)
          }
          HoverHandler {
            onHoveredChanged: hovered
              ? tips.show(zoomBox, (win.page === "glyphs" ? "Glyph size  \u00b7  " + win.cell : "Sample size  \u00b7  " + win.size) + "px", "ctrl + \u2212 0")
              : tips.hide(zoomBox)
          }
        }
      }

      Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Zenon.border }
    }

    // ── the pages ────────────────────────────────────────────────────────
    Item {
      id: body
      anchors.left: side.right
      anchors.right: parent.right
      anchors.top: head.bottom
      anchors.bottom: foot.top
      clip: true

      // ── SPECIMEN ──
      Flickable {
        id: specFlick
        anchors.fill: parent
        visible: win.page === "specimen"
        contentWidth: width
        contentHeight: specCol.implicitHeight + 48
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Column {
          id: specCol
          x: 28
          y: 24
          width: specFlick.width - 56
          spacing: 18

          // the specimen's bar: the languages it can be set in, each named in
          // itself, in this face (the suite's switch, terminus/Segments, user
          // 2026-10-20) — in rows of equal parts when there are more than one
          // row holds, a short last row keeping the parts' width — and, on the
          // same row, the sample's own tools
          Item {
            width: parent.width
            height: Math.max(langRows.visible ? langRows.implicitHeight : 0, sampleTools.height)
            Column {
              id: langRows
              anchors.left: parent.left
              anchors.top: parent.top
              width: Math.min(parent.width - sampleTools.width - 12, langRows.perRow * 140)
              spacing: 6
              visible: !!win.style && win.langs.length > 0
              readonly property int perRow: Math.max(1, Math.floor((langRows.parent.width - sampleTools.width - 12) / 140))
              Repeater {
                model: {
                  const out = [];
                  for (let i = 0; i < win.langs.length; i += langRows.perRow)
                    out.push(win.langs.slice(i, i + langRows.perRow).map((l) => [l.id, l.label]));
                  return out;
                }
                delegate: Segments {
                  required property var modelData
                  even: true
                  height: 30
                  width: langRows.width * modelData.length / langRows.perRow
                  textSize: Zenon.px(14)
                  face: win.style ? win.style.family : ""
                  ink: Zenon.accentSoft
                  options: modelData
                  current: win.script.id
                  onChose: (v) => { win.setLang(v); win.refocus(); }
                  onPointed: (v, at, inside) => {
                    const l = win.langs.find((q) => q.id === v);
                    if (inside && l) tips.show(at, l.label, "ctrl l");
                    else tips.hide(at);
                  }
                }
              }
            }
            Row {
              id: sampleTools
              anchors.right: parent.right
              anchors.top: parent.top
              spacing: 6
              Repeater {
                model: [["", "Another sample", () => win.nextSample()],
                        ["", "Write your own", () => { sampleField.forceActiveFocus(); sampleField.selectAll(); }]]
                delegate: Rectangle {
                  id: tool
                  required property var modelData
                  width: 30; height: 30; radius: Zenon.windowRadius
                  color: toolMa.pressed ? Zenon.wash(0.08) : Zenon.wash(0.03)
                  border.width: 1
                  border.color: Zenon.border
                  Text {
                    anchors.centerIn: parent
                    text: tool.modelData[0]
                    color: toolMa.pressed ? Zenon.cyan : Zenon.accentMuted
                    font.family: Zenon.glyphFace
                    font.pixelSize: Zenon.px(13)
                  }
                  MouseArea {
                    id: toolMa
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: tool.modelData[2]()
                    onContainsMouseChanged: containsMouse ? tips.show(tool, tool.modelData[1]) : tips.hide(tool)
                  }
                }
              }
            }
          }

          // your line, at its size — click to write your own
          Item {
            width: parent.width
            height: Math.max(sampleField.contentHeight, win.size * 1.3)
            TextInput {
              id: sampleField
              // the breathing caret, grown with the line it is in
              cursorDelegate: Caret { field: sampleField; width: Math.max(2, Math.round(win.size / 24)) }
              anchors.left: parent.left
              anchors.right: parent.right
              text: win.sample
              wrapMode: TextInput.Wrap
              color: Zenon.ink
              selectionColor: Zenon.alpha(Zenon.cyan, 0.35)
              font.family: win.style ? win.style.family : Zenon.face
              font.styleName: win.style ? win.style.style : ""
              font.pixelSize: win.size
              onTextEdited: if (win.mgr) { win.mgr.set("lang", win.script.id); win.mgr.set("sample", text); }
              Keys.onPressed: (e) => {
                if (e.key === Qt.Key_Escape || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                  e.accepted = true;
                  win.refocus();
                  famField.forceActiveFocus();
                } else if ((e.modifiers & Qt.ControlModifier) && e.key !== Qt.Key_A && e.key !== Qt.Key_C
                           && e.key !== Qt.Key_V && e.key !== Qt.Key_X && e.key !== Qt.Key_Z) {
                  if (win.navKey(e)) e.accepted = true;
                }
              }
            }
          }

          // every style, in its own cut; click to choose it
          Column {
            width: parent.width
            spacing: 2
            visible: !!win.fam
            SectionLabel {
              text: win.fam ? (win.fam.styles.length === 1 ? "1 STYLE" : win.fam.styles.length + " STYLES") : ""
              bottomPadding: 6
            }
            Repeater {
              model: win.fam ? win.fam.styles : []
              delegate: Rectangle {
                id: styleRow
                required property var modelData
                required property int index
                readonly property bool here: styleRow.index === win.styleIdx
                width: parent.width
                height: Math.max(40, styleText.implicitHeight + 16)
                // the sample in its own style once the gate grants it — see
                // faceGate; until then it is not shown at all, rather than
                // shown in the wrong face
                property bool faced: false
                function takeFace() {
                  styleRow.faced = true;
                  void styleText.implicitWidth;
                  win.facedSeen[win.faceKey(styleRow.modelData)] = true;
                }
                Component.onCompleted: {
                  if (win.facedSeen[win.faceKey(styleRow.modelData)]) styleRow.faced = true;
                  else win.askFace(styleRow);
                }
                radius: Zenon.windowRadius
                color: styleRow.here ? win.hiFill : styleMa.pressed ? Zenon.wash(0.05) : Zenon.alpha(Zenon.cyan, 0)
                Behavior on color { ColorAnimation { duration: Zenon.fast } }
                Text {
                  id: styleName
                  x: 12
                  width: 170
                  anchors.verticalCenter: parent.verticalCenter
                  elide: Text.ElideRight
                  text: A.styleLabel(win.fam, styleRow.modelData)
                  color: styleRow.here ? Zenon.cyan : Zenon.accentMuted
                  font.family: Zenon.face
                  font.weight: Zenon.weight
                  font.pixelSize: Zenon.px(12)
                }
                Text {
                  id: styleText
                  anchors.left: styleName.right
                  anchors.leftMargin: 14
                  anchors.right: parent.right
                  anchors.rightMargin: 12
                  anchors.verticalCenter: parent.verticalCenter
                  elide: Text.ElideRight
                  text: win.sample
                  color: Zenon.ink
                  font.family: styleRow.faced ? styleRow.modelData.family : Zenon.face
                  font.styleName: styleRow.faced ? styleRow.modelData.style : ""
                  font.pixelSize: Math.min(win.size, 30)
                  opacity: styleRow.faced ? 1 : 0
                  Behavior on opacity { NumberAnimation { duration: Zenon.fast } }
                }
                MouseArea {
                  id: styleMa
                  anchors.fill: parent
                  hoverEnabled: true
                  onClicked: { win.styleIdx = styleRow.index; win.refocus(); }
                  onDoubleClicked: if (win.picking) win.usePick()
                }
              }
            }
          }

          // the waterfall
          Column {
            width: parent.width
            spacing: 6
            visible: !!win.style
            SectionLabel {
              text: "SIZES"
              bottomPadding: 4
            }
            Repeater {
              model: [72, 48, 36, 28, 22, 18, 15, 13, 11]
              delegate: Row {
                id: fall
                required property int modelData
                spacing: 14
                width: parent.width
                Text {
                  width: 30
                  anchors.baseline: fallLine.baseline
                  horizontalAlignment: Text.AlignRight
                  text: fall.modelData
                  color: Zenon.accentMuted
                  font.family: Zenon.face
                  font.weight: Zenon.weight
                  font.features: { "tnum": 1 }
                  font.pixelSize: Zenon.px(11)
                }
                Text {
                  id: fallLine
                  width: parent.width - 44
                  elide: Text.ElideRight
                  text: win.sample
                  color: Zenon.ink
                  font.family: win.style ? win.style.family : Zenon.face
                  font.styleName: win.style ? win.style.style : ""
                  font.pixelSize: fall.modelData
                }
              }
            }
          }

          // set as text: the alphabet, then a paragraph to read
          Column {
            width: parent.width
            spacing: 10
            visible: !!win.style
            SectionLabel {
              text: "TEXT"
            }
            Text {
              width: parent.width
              wrapMode: Text.Wrap
              text: win.script.alphabet
              color: Zenon.ink
              lineHeight: 1.2
              font.family: win.style ? win.style.family : Zenon.face
              font.styleName: win.style ? win.style.style : ""
              font.pixelSize: 24
            }
            Text {
              width: Math.min(parent.width, 720)
              wrapMode: Text.Wrap
              text: win.script.paragraph
              color: Zenon.accentSoft
              lineHeight: 1.45
              font.family: win.style ? win.style.family : Zenon.face
              font.styleName: win.style ? win.style.style : ""
              font.pixelSize: 16
            }
          }
        }
      }
      ElasticScroll {
        anchors.fill: specFlick
        view: specFlick
        visible: specFlick.visible
        // ctrl+wheel is the size, not the scroll
        intercept: (w) => {
          if (!(w.modifiers & Qt.ControlModifier)) return false;
          win.zoom(w.angleDelta.y > 0 ? 1 : -1);
          return true;
        }
      }
      Scrollbar { flick: specFlick; visible: specFlick.visible; anchors.right: specFlick.right; anchors.top: specFlick.top; anchors.bottom: specFlick.bottom }

      // ── GLYPHS ──
      Item {
        id: glyphPage
        anchors.fill: parent
        visible: win.page === "glyphs"

        // the search over names and codepoints
        Rectangle {
          id: glyphSearch
          anchors.left: parent.left
          anchors.right: detail.left
          anchors.top: parent.top
          anchors.margins: 14
          height: 34
          radius: Zenon.windowRadius
          color: Zenon.wash(0.06)
          border.width: 1
          border.color: Zenon.border
          Text {
            id: glyphLens
            anchors.left: parent.left
            anchors.leftMargin: 13
            anchors.verticalCenter: parent.verticalCenter
            text: ""
            color: Zenon.accentMuted
            font.family: Zenon.glyphFace
            font.pixelSize: Zenon.px(13)
          }
          TextInput {
            id: glyphField
            // the shell's breathing caret, as every field wears
            cursorDelegate: Caret { field: glyphField }
            anchors.left: glyphLens.right
            anchors.leftMargin: 9
            anchors.right: glyphCount.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: win.gquery
            onTextChanged: if (win.gquery !== text) win.gquery = text
            color: Zenon.ink
            selectionColor: Zenon.alpha(Zenon.cyan, 0.4)
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(15)
            clip: true
            Keys.onPressed: (e) => { if (win.navKey(e)) e.accepted = true; }
            Text {
              visible: glyphField.text === ""
              anchors.verticalCenter: parent.verticalCenter
              text: "Search by name, codepoint or character — folder, U+F031, →"
              color: Zenon.accentMuted
              font: glyphField.font
              elide: Text.ElideRight
              width: glyphField.width
            }
          }
          Text {
            id: glyphCount
            anchors.right: glyphClear.visible ? glyphClear.left : parent.right
            anchors.rightMargin: glyphClear.visible ? 10 : 14
            anchors.verticalCenter: parent.verticalCenter
            text: win.gix.count === win.charset.count ? win.charset.count + " glyphs"
              : win.gix.count + " of " + win.charset.count
            color: Zenon.accentMuted
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.features: { "tnum": 1 }
            font.pixelSize: Zenon.px(12)
          }
          ClearChip {
            id: glyphClear
            size: Zenon.px(15)
            shown: glyphField.text !== ""
            anchors.right: parent.right
            anchors.rightMargin: 9
            anchors.verticalCenter: parent.verticalCenter
            onClicked: { glyphField.text = ""; glyphField.forceActiveFocus(); }
          }
          // focused for typing: terminus' held ring (user, 2026-10-11 — every
          // text field wears it, its own border staying neutral)
          HeldRing { anchors.fill: parent; radius: parent.radius; z: 10; on: glyphField.activeFocus }
        }

        GridView {
          id: glyphGrid
          anchors.left: parent.left
          anchors.right: detail.left
          anchors.top: glyphSearch.bottom
          anchors.bottom: parent.bottom
          anchors.topMargin: 10
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          // THE LEFT MARGIN IS INSIDE THE VIEW, not an anchor margin: the
          // frost under the chrome is as wide as the view, and a view set in
          // by 14 left a 14px column of the head unfrosted. The cells are laid
          // over width − pad and moved right by it (each delegate's Translate).
          readonly property real pad: 14
          readonly property int cols: Math.max(1, Math.floor((width - pad) / win.cell))
          readonly property real cw: Math.max(1, (width - pad) / cols)
          cellWidth: cw
          // the glyph, and its codepoint line under it at the Font size
          cellHeight: win.cell + 6 + Zenon.px(10)
          cacheBuffer: 600
          // only on its own page: the pages are hidden, not unloaded, and a
          // hidden grid still built a screenful of cells in every family
          // passed on the way down the list (see faceGate's note)
          model: win.page === "glyphs" ? win.gix.count : 0
          delegate: Item {
            id: gcell
            required property int index
            readonly property int cp: A.codeAt(win.gix, gcell.index)
            readonly property bool here: gcell.index === win.gsel
            width: glyphGrid.cellWidth
            height: glyphGrid.cellHeight
            transform: Translate { x: glyphGrid.pad }
            Rectangle {
              anchors.fill: parent
              anchors.margins: 3
              radius: Zenon.windowRadius
              color: gcell.here ? win.hiFill : gMa.pressed ? Zenon.wash(0.06) : Zenon.wash(0.02)
              border.width: gcell.here ? 1 : 0
              border.color: Zenon.alpha(Zenon.cyan, 0.7)
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              y: 6
              height: win.cell - 4
              verticalAlignment: Text.AlignVCenter
              text: A.charOf(gcell.cp)
              color: Zenon.ink
              font.family: win.style ? win.style.family : Zenon.face
              font.styleName: win.style ? win.style.style : ""
              font.pixelSize: Math.round(win.cell * 0.52)
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: parent.bottom
              anchors.bottomMargin: 6
              text: A.hex(gcell.cp)
              color: gcell.here ? Zenon.cyan : Zenon.accentMuted
              font.family: Zenon.faceMono
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(10)
            }
            MouseArea {
              id: gMa
              anchors.fill: parent
              hoverEnabled: true
              acceptedButtons: Qt.LeftButton | Qt.RightButton
              onClicked: (m) => {
                win.gsel = gcell.index;
                win.copyGlyph(m.button === Qt.RightButton || (m.modifiers & Qt.ShiftModifier));
              }
            }
          }
          EmptyState {
            anchors.centerIn: parent
            visible: glyphGrid.count === 0 && !csProc.running
            filtered: win.gquery !== ""
          }
        }
        ElasticScroll {
          anchors.fill: glyphGrid
          view: glyphGrid
          intercept: (w) => {
            if (!(w.modifiers & Qt.ControlModifier)) return false;
            win.zoom(w.angleDelta.y > 0 ? 1 : -1);
            return true;
          }
        }
        Scrollbar { flick: glyphGrid; anchors.right: glyphGrid.right; anchors.top: glyphGrid.top; anchors.bottom: glyphGrid.bottom }

        // the glyph under the cursor, and the groups
        Item {
          id: detail
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          width: 300
          Rectangle { width: 1; height: parent.height; color: Zenon.border }

          Column {
            id: card
            x: 18
            y: 16
            width: parent.width - 36
            spacing: 10
            visible: win.gcp >= 0
            Rectangle {
              width: parent.width
              height: 150
              radius: Zenon.dialogRadius
              color: Zenon.wash(0.04)
              border.width: 1
              border.color: Zenon.border
              Text {
                anchors.centerIn: parent
                text: A.charOf(win.gcp)
                color: Zenon.ink
                font.family: win.style ? win.style.family : Zenon.face
                font.styleName: win.style ? win.style.style : ""
                font.pixelSize: 96
              }
            }
            Text {
              width: parent.width
              wrapMode: Text.Wrap
              text: win.nameOf(win.gcp) || "unnamed"
              color: Zenon.ink
              font.family: Zenon.face
              font.weight: Font.Bold
              font.pixelSize: Zenon.px(15)
            }
            Text {
              width: parent.width
              elide: Text.ElideRight
              text: A.uplus(win.gcp) + "  ·  " + (A.blockName(win.gcp, win.mgr ? win.mgr.blocks : []) || "—")
              color: Zenon.accentMuted
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(12)
            }
            Repeater {
              model: win.gcp >= 0 ? A.spellings(win.gcp, win.nerdOf(win.gcp)) : []
              delegate: Rectangle {
                id: spell
                required property var modelData
                width: card.width
                height: 28
                radius: Zenon.windowRadius
                color: spellMa.pressed ? Zenon.wash(0.08) : Zenon.wash(0.03)
                Text {
                  anchors.left: parent.left
                  anchors.leftMargin: 10
                  anchors.verticalCenter: parent.verticalCenter
                  text: spell.modelData.label
                  color: Zenon.accentMuted
                  font.family: Zenon.face
                  font.weight: Zenon.weight
                  font.pixelSize: Zenon.px(12)
                }
                Text {
                  anchors.right: copyMark.left
                  anchors.rightMargin: 8
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - 120
                  horizontalAlignment: Text.AlignRight
                  elide: Text.ElideLeft
                  text: spell.modelData.text
                  color: Zenon.ink
                  font.family: spell.modelData.key === "char" && win.style ? win.style.family : Zenon.faceMono
                  font.weight: Zenon.weight
                  font.pixelSize: Zenon.px(13)
                }
                Text {
                  id: copyMark
                  anchors.right: parent.right
                  anchors.rightMargin: 10
                  anchors.verticalCenter: parent.verticalCenter
                  text: ""
                  color: spellMa.pressed ? Zenon.cyan : Zenon.accentMuted
                  font.family: Zenon.glyphFace
                  font.pixelSize: Zenon.px(11)
                }
                MouseArea {
                  id: spellMa
                  anchors.fill: parent
                  hoverEnabled: true
                  onClicked: win.copy(spell.modelData.text)
                }
              }
            }
          }

          SectionLabel {
            id: groupHead
            anchors.top: card.visible ? card.bottom : parent.top
            anchors.topMargin: 18
            x: 18
            text: "GROUPS"
          }
          ListView {
            id: groupList
            anchors.top: groupHead.bottom
            anchors.topMargin: 6
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: [{ name: "Everything", count: win.charset.count }].concat(win.groups)
            delegate: Rectangle {
              id: grow
              required property var modelData
              required property int index
              readonly property bool here: grow.index - 1 === win.group
              width: groupList.width
              height: 28
              radius: Zenon.windowRadius
              color: grow.here ? win.hiFill : growMa.pressed ? Zenon.wash(0.06) : Zenon.alpha(Zenon.cyan, 0)
              Text {
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.right: growN.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: grow.modelData.name
                color: grow.here ? Zenon.ink : Zenon.accentSoft
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.pixelSize: Zenon.px(13)
              }
              Text {
                id: growN
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: grow.modelData.count
                color: Zenon.accentMuted
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.features: { "tnum": 1 }
                font.pixelSize: Zenon.px(11)
              }
              MouseArea {
                id: growMa
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                  win.gquery = "";
                  win.group = grow.index - 1;
                  win.gsel = 0;
                  glyphGrid.positionViewAtBeginning();
                  win.refocus();
                }
              }
            }
          }
          ElasticScroll { anchors.fill: groupList; view: groupList }
          Scrollbar { flick: groupList; visible: groupList.visible; anchors.right: parent.right; anchors.top: groupList.top; anchors.bottom: groupList.bottom }
        }
      }

      // ── INFO ──
      Flickable {
        id: infoFlick
        anchors.fill: parent
        visible: win.page === "info"
        contentWidth: width
        contentHeight: infoCol.implicitHeight + 48
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        Column {
          id: infoCol
          x: 28
          y: 24
          width: Math.min(infoFlick.width - 56, 820)
          spacing: 22

          // the suite's specimen, of the style chosen, from its file
          FontSpecimen {
            width: parent.width
            // only on its own page: hidden, it still rebuilt itself in every
            // face selected — the largest single cost of moving through the
            // list, ~90 ms a family measured offscreen (2026-10-09)
            path: win.page === "info" && win.style ? win.style.file : ""
          }

          // the facts, as a two-column list (label, value)
          Column {
            width: parent.width
            spacing: 6
            Repeater {
              model: {
                if (!win.fam || !win.style) return [];
                const f = win.facts;
                return [
                  ["Family", win.fam.name],
                  ["Also called", win.fam.variants.filter((v) => v !== win.fam.name).join(", ")],
                  ["Style", A.styleLabel(win.fam, win.style) + "  ·  " + A.weightName(win.style.css) + " (" + win.style.css + ")"],
                  ["PostScript", f.postscript || ""],
                  ["Format", win.style.format],
                  ["Version", f.version || ""],
                  ["Foundry", f.foundry || ""],
                  ["Glyphs", win.charset.count > 0 ? String(win.charset.count) : ""],
                  ["Languages", f.langs ? String(f.langs) : ""],
                  ["Scripts", f.features || ""],
                  ["Spacing", win.style.mono ? "monospaced" : "proportional"],
                  ["From", win.fam.loose ? (win.looseInstalled ? "a file — installed" : "a file — not installed")
                    : f.pkg ? "pacman package " + f.pkg : win.fam.user ? "imported" : "the system"],
                  ["File size", f.size || ""],
                ].filter((r) => r[1] !== "");
              }
              delegate: Row {
                id: factRow
                required property var modelData
                spacing: 18
                Text {
                  width: 120
                  text: factRow.modelData[0]
                  color: Zenon.accentMuted
                  font.family: Zenon.face
                  font.weight: Zenon.weight
                  font.pixelSize: Zenon.px(13)
                }
                Text {
                  width: infoCol.width - 138
                  wrapMode: Text.Wrap
                  text: factRow.modelData[1]
                  color: Zenon.ink
                  font.family: Zenon.face
                  font.weight: Zenon.weight
                  font.pixelSize: Zenon.px(13)
                }
              }
            }
          }

          // the files — click one to see it in terminus
          Column {
            width: parent.width
            spacing: 2
            visible: !!win.fam
            SectionLabel {
              text: win.fam ? (win.fam.files.length === 1 ? "1 FILE" : win.fam.files.length + " FILES") : ""
              bottomPadding: 6
            }
            Repeater {
              model: win.fam ? win.fam.files : []
              delegate: Rectangle {
                id: fileRow
                required property var modelData
                width: infoCol.width
                height: 28
                radius: Zenon.windowRadius
                color: fileMa.pressed ? Zenon.wash(0.06) : Zenon.alpha(Zenon.cyan, 0)
                Text {
                  anchors.left: parent.left
                  anchors.leftMargin: 10
                  anchors.right: parent.right
                  anchors.rightMargin: 34
                  anchors.verticalCenter: parent.verticalCenter
                  elide: Text.ElideMiddle
                  text: fileRow.modelData
                  color: win.style && win.style.file === fileRow.modelData ? Zenon.cyan : Zenon.accentSoft
                  font.family: Zenon.faceMono
                  font.weight: Zenon.weight
                  font.pixelSize: Zenon.px(12)
                }
                Text {
                  anchors.right: parent.right
                  anchors.rightMargin: 10
                  anchors.verticalCenter: parent.verticalCenter
                  text: ""
                  color: fileMa.pressed ? Zenon.cyan : Zenon.accentMuted
                  font.family: Zenon.glyphFace
                  font.pixelSize: Zenon.px(12)
                }
                MouseArea {
                  id: fileMa
                  anchors.fill: parent
                  hoverEnabled: true
                  onClicked: if (win.fileManager) win.fileManager.reveal(fileRow.modelData)
                  onContainsMouseChanged: containsMouse ? tips.show(fileRow, "Show in terminus") : tips.hide(fileRow)
                }
              }
            }
          }
        }
      }
      ElasticScroll { anchors.fill: infoFlick; view: infoFlick; visible: infoFlick.visible }
      Scrollbar { flick: infoFlick; visible: infoFlick.visible; anchors.right: infoFlick.right; anchors.top: infoFlick.top; anchors.bottom: infoFlick.bottom }

      EmptyState {
        anchors.centerIn: parent
        visible: !win.fam && !!win.mgr && !win.mgr.scanning
        filtered: true
      }

      // what was just done, said once
      Ctl.Said {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 18
        maxWidth: Infinity
        text: win.said
        pixelSize: Zenon.px(14)
      }
    }

    Repeater {
      // (not the families: the sidebar runs to the window's bottom, past
      // the foot, so its rows have no foot to go under)
      model: [specFlick, infoFlick, glyphGrid, groupList]
      delegate: ScrollEdge {
        required property var modelData
        view: modelData
        below: true
        follow: true
        bar: foot
        visible: modelData.visible && glyphPage.visible === (modelData === glyphGrid || modelData === groupList)
      }
    }

    // ── the foot ─────────────────────────────────────────────────────────
    // morpheus/HintBar, as every strip (ceres' height, ground and rule);
    // the buttons stand at its right end
    HintBar {
      id: foot
      anchors.bottom: parent.bottom
      anchors.left: side.right
      anchors.right: parent.right
      rows: win.hintRows

      // ── OPEN A FONT, OR THE WORK UNDER WAY ──
      // An install is not instant (fc-cache is most of it), so while one
      // is out the button becomes the shell's working dots and what is
      // going on — "Installing 4 families…" — and grows or shrinks to fit
      // it, one shape turning into the other rather than a swap.
      BusyButton {
        id: openSlot
        visible: !win.picking
        anchors.verticalCenter: parent.verticalCenter
        label: "Open a font\u2026"
        busy: win.installing
        busyText: win.busyShown
        busyInk: win.mgr && win.mgr.busyKind === "remove" ? Zenon.red : Zenon.cyan
        onClicked: win.chooseFile()
      }
      DialogButton {
        visible: win.removable.length > 0 && !win.picking && !win.installing
        label: win.removeFams.length > 1 ? "Remove " + win.removeFams.length : "Remove"
        ink: Zenon.red
        onClicked: win.askRemove()
      }
      DialogButton {
        visible: win.installable.length > 0 && !win.installing
        label: win.installable.length > 1 ? "Install " + win.installable.length : "Install"
        ink: Zenon.cyan
        primary: true
        onClicked: win.installOpened()
      }
      DialogButton {
        visible: !!win.picking
        label: "Cancel"
        onClicked: win.cancelPick()
      }
      DialogButton {
        visible: !!win.picking
        label: win.fam ? "Use " + win.fam.name : "Use"
        ink: Zenon.cyan
        primary: true
        ready: !!win.fam && !win.fam.loose
        onClicked: win.usePick()
      }
    }
  }

  // ── REMOVING, ASKED FIRST ──────────────────────────────────────────────
  InputShield { visible: win.asking; onClicked: win.answer(false) }
  Sheet {
    id: removeSheet
    shown: win.asking
    fromTop: head.height
    cardW: 500
    cardH: removeBody.implicitHeight
    ConfirmBody {
      id: removeBody
      width: parent.width
      question: win.removeFams.length === 1 ? "Remove " + win.removeFams[0].name + "?"
        : "Remove " + win.famWord(win.removeFams.length) + "?"
      glyph: ""
      glyphInk: Zenon.red
      detail: "To the trash — it can be brought back from there"
      // one family: its files; many: the families, the files under each counted
      items: win.removeFams.length === 1 ? win.removable.map((f) => f.replace(/.*\//, ""))
        : win.removeFams.map((f) => f.name + (f.files.length > 1 ? "  \u00b7  " + f.files.length + " files" : ""))
      choices: [{ label: "Remove", ink: Zenon.red }, { label: "Cancel", ink: Zenon.accentMuted }]
      pick: win.askPick
      onPicked: (i) => win.askPick = i
      onChose: (i) => win.answer(i === 0)
    }
  }

  WindowTip { id: tips; window: win }
}
