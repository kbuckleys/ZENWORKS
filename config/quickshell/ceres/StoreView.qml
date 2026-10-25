// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE STORE — Ceres' first tab: apps, not packages (user, 2026-10-14).
//
// The Packages tab is still where every package is, searched by name; this
// is the other way in — what an app is, what it looks like, who makes it —
// for the desktop applications the catalogs describe:
//
//   the sidebar   Discover, the sections (Create, Work, Play …), Installed
//   Discover      after the Mac App Store (user, 2026-10-14): features
//                 turning over, a row of artwork, then shelves three rows
//                 deep — what Arch uses most and the best of each section,
//                 Play as pictures (polished apps only — see ceres-store)
//   a section     every app in it, the polished first
//   a search      typed, as everywhere in Ceres; names, packages, summaries,
//                 developers and keywords
//   an app        its page: screenshots, description, what is new, the
//                 facts — and in its banner, Get / Open / Remove and its links
//
// NOTHING IS INSTALLED FROM IN HERE. Get and Remove hand a Packages row to the
// window (changeAsked), which opens the same confirm sheet, password and log
// as the Packages tab — one way a change happens, whichever tab asked.
//
// The catalog is ceres/bin/ceres-store's; the rules — sections, search,
// shelves, the keys — are store.js's, and tested there.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import "../morpheus"
import "../morpheus/controls" as Controls
import "../terminus" as Term
import "../oracle"
import "."
import "ceres.js" as Cer
import "store.js" as St

Item {
  id: store

  // the search, held by the window with the other tabs' filters
  property string query: ""
  // pacman's own record, for a page's version and sizes (scripts/ceres.sh)
  property string script: ""
  signal changeAsked(var row)
  // a Flathub app to install or remove: the window's Flatpak sheet asks
  // where (for everyone, or just you) and shows what it may touch
  signal flatpakAsked(var app, bool remove)
  signal released()
  // a section chosen while a search was typed: the window clears the search
  signal searchLeft()

  readonly property string tool: Quickshell.shellDir + "/ceres/bin/ceres-store"
  readonly property bool busy: Ceres.txBusy

  // ── the catalog ──────────────────────────────────────────────────────
  property var apps: []
  property bool loading: false
  property bool loaded: false
  property bool failed: false
  function load() {
    if (listProc.running) { listProc.again = true; return; }
    store.loading = true;
    listProc.running = true;
  }
  // after a change: what is installed is what moved
  function refresh() { if (store.loaded) store.load(); }
  Process {
    id: listProc
    property bool again: false
    command: [store.tool, "list"]
    onExited: (code) => {
      store.loading = false;
      if (code !== 0 && !store.loaded) store.failed = true;
      if (listProc.again) { listProc.again = false; Qt.callLater(store.load); }
    }
    stdout: StdioCollector {
      id: listOut
      onStreamFinished: {
        try {
          store.apps = JSON.parse(listOut.text).apps || [];
          store.loaded = true;
          store.failed = false;
        } catch (e) {
          if (!store.loaded) store.failed = true;
          return;
        }
        // the page open on an app shows it as it is now — its facts too, a
        // job having changed them (an install, an override)
        if (store.app) { store.app = store.apps.find(a => a.key === store.app.key) || store.app; store.facts(); }
      }
    }
  }

  // ── where we are ───────────────────────────────────────────────────────
  property string section: "discover"
  property var app: null                  // the app whose page is open
  property int sel: 0
  readonly property bool searching: store.query.trim() !== ""
  readonly property string view: store.app ? "page"
    : store.searching ? "search"
    : store.section === "discover" ? "discover" : "grid"

  function showSection(key) {
    if (key === store.section && !store.app) return;
    store.remember();
    store.place(key, null);
  }
  // where you are, without remembering where you were — the history's own
  function place(key, a) {
    store.section = key;
    store.lightbox = "";
    if (a) { store.show(a); return; }
    store.app = null;
    store.sel = 0;
    grid.positionViewAtBeginning();
    discover.contentY = 0;
  }

  // ── BACK AND FORWARD (user, 2026-10-14: mouse 4 and 5) ─────────────────
  // Every section and page you go to, as a browser keeps them: back steps
  // to the last, forward undoes a back, and going somewhere new drops what
  // was ahead. A page is kept by its app's key, so after a job it comes
  // back as the catalog now has it.
  property var trail: []
  property var ahead: []
  function here() { return { section: store.section, app: store.app ? store.app.key : "" }; }
  function remember() {
    store.trail = store.trail.concat([store.here()]).slice(-50);
    store.ahead = [];
  }
  function go(st) {
    store.place(st.section, st.app ? store.apps.find(x => x.key === st.app) || null : null);
  }
  function stepBack() {
    if (store.lightbox !== "") { store.closeShot(); return true; }
    if (!store.trail.length) {
      if (!store.app) return false;
      store.ahead = store.ahead.concat([store.here()]);
      store.place(store.section, null);
      return true;
    }
    const to = store.trail[store.trail.length - 1];
    store.trail = store.trail.slice(0, -1);
    store.ahead = store.ahead.concat([store.here()]);
    store.go(to);
    return true;
  }
  function stepForward() {
    if (!store.ahead.length) return false;
    const to = store.ahead[store.ahead.length - 1];
    store.ahead = store.ahead.slice(0, -1);
    store.trail = store.trail.concat([store.here()]);
    store.go(to);
    return true;
  }
  onQueryChanged: { store.sel = 0; if (store.app && store.searching) store.app = null; }

  // ── the grid's measure, shared by the shelves ──────────────────────────
  readonly property real pad: 18
  readonly property real minCard: 300
  readonly property int cols: Math.max(1, Math.floor((content.width - store.pad * 2) / store.minCard))
  readonly property real cardW: (content.width - store.pad * 2) / store.cols

  // ── what each view shows ───────────────────────────────────────────────
  readonly property int today: Math.floor(Date.now() / 86400000)
  // the artwork row, four across when there is room
  readonly property int artCols: Math.max(2, Math.min(4, Math.floor((content.width - store.pad * 2) / 230)))
  readonly property real artW: (content.width - store.pad * 2 - (store.artCols - 1) * 20) / store.artCols
  // THE FRONT PAGE IN ONE BINDING. As three, a new catalog laid the shelves
  // out three times over — once for the catalog, again when the features
  // caught up, again for the artwork — and every pass rebuilt every shelf's
  // cards: ~120 ms of a ~220 ms stall the first time the Store was shown
  // (profiled offscreen, 2026-10-18). The features are handed on only when
  // they are other apps, so a resize does not turn the carousel back.
  readonly property var front: {
    const f = St.features(store.apps, store.today, 5);
    const s = St.stories(store.apps, f, store.artCols);
    return { features: f, stories: s, shelves: St.shelves(store.apps, store.cols, f.concat(s), 3, store.artCols) };
  }
  property var features: []
  onFrontChanged: {
    const f = store.front.features;
    if (f.length !== store.features.length || f.some((a, i) => a !== store.features[i])) store.features = f;
  }
  readonly property var stories: store.front.stories
  readonly property var shelves: store.front.shelves
  // THE KEYS WALK A SECTION'S GRID, OR A SEARCH'S. Discover had a cursor of
  // its own across the carousel, artwork and shelves — not really useful
  // (user, 2026-10-15), and gone: there the arrows scroll the page.
  readonly property var gridApps: store.searching ? St.search(store.apps, store.query)
    : store.section === "discover" ? [] : St.sectionApps(store.apps, store.section)
  readonly property var walked: store.view === "discover" ? [] : store.gridApps
  readonly property var walkRows: St.chunkRows(store.gridApps.length, store.cols)
  onWalkedChanged: if (store.sel >= store.walked.length) store.sel = Math.max(0, store.walked.length - 1)
  // the front page's pictures, fetched as soon as it knows which they are
  // NEVER WHILE THE VIEW IS BEING BUILT: a Process started from a binding's
  // first settling read as running and never ran, and every picture after
  // it waited in the queue behind it. After the catalog, on the next turn.
  onFeaturesChanged: if (store.loaded) Qt.callLater(store.fetchArt)
  onShelvesChanged: if (store.loaded) Qt.callLater(store.fetchArt)
  onLoadedChanged: if (store.loaded) Qt.callLater(store.fetchArt)
  function fetchArt() {
    // (called as the bindings first settle: some may not be there yet)
    const urls = (store.features || []).concat(store.stories || [])
      .concat([].concat.apply([], (store.shelves || []).filter(s => s.art).map(s => s.apps)))
      .map(a => a.shot).filter(u => u);
    if (urls.length) store.fetchShots(urls, false);
  }
  // the app under the keys' cursor; on Discover, the one featured
  readonly property var current: store.view === "discover" ? (heroView.app || null) : (store.walked[store.sel] || null)

  // ── doing ──────────────────────────────────────────────────────────────
  function get(a) {
    if (!a || a.installed || store.busy) return;
    if (a.source === "flatpak") store.flatpakAsked(a, false);
    else store.changeAsked(St.changeRow(a, false));
  }
  function remove(a) {
    if (!a || !a.installed || store.busy) return;
    if (a.source === "flatpak") store.flatpakAsked(a, true);
    else store.changeAsked(St.changeRow(a, true));
  }
  // a Flatpak runs by its id — its desktop entry is under Flatpak's exports,
  // which the session's search path need not hold
  function launch(a) {
    if (!a) return;
    if (a.source === "flatpak") Quickshell.execDetached(["flatpak", "run", a.pkg]);
    else if (a.launch) Quickshell.execDetached(["sh", "-c", Desktop.launchCommand(a.launch, "")]);
  }
  function act(a) { if (!a) return; if (a.installed) store.launch(a); else store.get(a); }

  // ── an app's page ──────────────────────────────────────────────────────
  property var detail: null
  property var info: null
  property var shots: ({})                 // url → local file, as they land
  function open(a) {
    if (!a) return;
    store.remember();
    store.show(a);
  }
  function show(a) {
    store.app = a;
    store.variant = St.openingSource(a, Ceres.preferSource);
    store.detail = null;
    page.contentY = 0;
    // A NEW PAGE STOPS THE LAST ONE'S ASKING: a Process already running
    // ignores `running = true`, and a quick back-and-forth showed the
    // previous app's details on this one's page
    detailProc.running = false;
    detailProc.command = [store.tool, "detail", a.key];
    detailProc.running = true;
    store.facts();
    store.released();
  }
  // the source the page shows the app from — the card's own, or another
  // its switch picked (St.asSource); its facts follow it
  property string variant: ""
  readonly property var shown: St.asSource(store.app, store.variant)
  onVariantChanged: if (store.app) store.facts()
  // STOPPED, THEN STARTED ON THE NEXT TURN: a Process told to stop and
  // start in one breath stayed stopped, and a page switched to Flathub kept
  // the AUR's version and never read its sandbox. Each ask is numbered; an
  // answer for an older one is dropped.
  property int factSeq: 0
  function facts() {
    store.factSeq++;
    store.info = null;
    store.perms = null;
    infoProc.running = false;
    metaProc.running = false;
    const seq = store.factSeq;
    Qt.callLater(() => store.askFacts(seq));
  }
  function askFacts(seq) {
    const a = store.shown;
    if (!a || seq !== store.factSeq) return;
    infoProc.seq = seq;
    metaProc.seq = seq;
    if (a.source === "flatpak") {
      infoProc.flatpak = true;
      infoProc.command = ["flatpak", "remote-info", "--system", "flathub", a.pkg];
      infoProc.running = true;
      // installed: its own metadata, and your overrides laid over it —
      // what it may touch NOW; not installed: what Flathub says it asks for
      metaProc.command = a.installed
        ? ["sh", "-c", "flatpak info --" + (a.scope === "user" ? "user" : "system") + " --show-metadata " + Cer.q(a.pkg)
            + " 2>/dev/null; echo '@@override'; flatpak override --" + (a.scope === "user" ? "user" : "system")
            + " --show " + Cer.q(a.pkg) + " 2>/dev/null; true"]
        : ["flatpak", "remote-info", "--system", "--show-metadata", "flathub", a.pkg];
      metaProc.running = true;
    } else if (store.script !== "") {
      infoProc.flatpak = false;
      infoProc.command = ["sh", "-c", Cer.infoCommand(store.script, a.pkg, a.repo)];
      infoProc.running = true;
    }
  }
  // a screenshot, large, over the page; Esc or a click puts it back
  property string lightbox: ""
  // the page's screenshots, in order, for ← → and the lightbox's own
  // previous / next (user, 2026-10-17: no closing one to open the next)
  property var lightboxFiles: []
  // A SCREENSHOT OPENS OUT OF ITS THUMBNAIL AND GOES BACK INTO IT (user,
  // 2026-10-19: "zoom previews in and out when i open them"): where the
  // thumbnail is, handed to the lightbox, which grows the picture from there
  function openShot(item, file, files) {
    store.lightboxFiles = files;
    const r = item.mapToItem(lightboxBox, 0, 0, item.width, item.height);
    store.lightbox = file;
    lightboxBox.zoomIn(r);
  }
  function closeShot() { lightboxBox.zoomOut(); }
  readonly property int lightboxAt: store.lightboxFiles.indexOf(store.lightbox)
  function lightboxStep(d) {
    const i = store.lightboxAt + d;
    if (store.lightboxAt < 0) return false;
    if (i < 0 || i >= store.lightboxFiles.length) { lightboxBox.bump(d); return false; }
    lightboxBox.step(d);
    // the thumbnail it came out of is not this one: it closes shrinking
    // toward the middle instead of into another picture's box
    const f = lightboxBox.full;
    lightboxBox.from = Qt.rect(f.x + f.width * 0.1, f.y + f.height * 0.1, f.width * 0.8, f.height * 0.8);
    store.lightbox = store.lightboxFiles[i];
    Qt.callLater(lightboxBox.enter);
    return true;
  }
  Process {
    id: detailProc
    stdout: StdioCollector {
      id: detailOut
      onStreamFinished: {
        try { store.detail = JSON.parse(detailOut.text); } catch (e) { store.detail = {}; }
        store.fetchShots((store.detail.shots || []).map(s => s.url), true);
      }
    }
  }
  Process {
    id: infoProc
    property bool flatpak: false
    property int seq: -1
    stdout: StdioCollector {
      id: infoOut
      onStreamFinished: if (infoProc.seq === store.factSeq)
        store.info = infoProc.flatpak ? St.remoteInfo(infoOut.text) : Cer.parseInfo(infoOut.text).map
    }
  }
  // what a Flatpak may touch, from its metadata — null until read
  property var perms: null
  Process {
    id: metaProc
    property int seq: -1
    stdout: StdioCollector {
      id: metaOut
      onStreamFinished: {
        if (metaProc.seq !== store.factSeq) return;
        const t = metaOut.text, i = t.indexOf("@@override");
        store.perms = i < 0 ? St.permissions(t, "") : St.permissions(t.slice(0, i), t.slice(i));
      }
    }
  }

  // ── A PERMISSION, SWITCHED (user, 2026-10-15) ───────────────────────────
  // An override, as Flatpak keeps them: yours, at once and with no
  // password, then read back; the system's, through Ceres' password sheet
  // as any change of the system's is (and read back when that job is done —
  // see refresh). Reset takes every override away.
  function setPerm(row, on) {
    const a = store.shown;
    if (!a || !a.installed || a.source !== "flatpak") return;
    const flag = St.overrideFlag(row, on);
    if (!flag) return;
    store.override(St.overrideSteps(a.pkg, a.scope, flag), "change what " + a.name + " may touch");
  }
  function resetPerms() {
    const a = store.shown;
    if (!a || !a.installed || a.source !== "flatpak") return;
    store.override(St.overrideResetSteps(a.pkg, a.scope), "put " + a.name + "'s access back as it asks");
  }
  function override(steps, label) {
    if (steps[0][0] === "@user") {
      permProc.running = false;
      permProc.command = ["sh", "-c", steps[0][1]];
      Qt.callLater(() => { permProc.running = true; });
    } else if (!store.busy) Ceres.request(steps, label, 0);
  }
  Process {
    id: permProc
    onExited: store.facts()
  }
  // Screenshots come over the network once and are kept (ceres-store
  // shots); each is drawn the moment its file lands, in its place.
  //
  // TWO LINES, NOT ONE (user, 2026-10-14: "previews don't load"): the page's
  // own screenshots waited in one queue behind the front page's twenty
  // pictures, and one slow server held the lot. A page fetches on its own
  // line, and a page opened meanwhile replaces what was waiting there; the
  // front page's pictures queue on the other.
  function fetchShots(urls, forPage) {
    const want = urls.filter(u => u && !(u in store.shots));
    if (!want.length) return;
    const proc = forPage ? pageShots : artShots;
    if (proc.running) {
      proc.waiting = forPage ? want : proc.waiting.concat(want);
      return;
    }
    proc.command = [store.tool, "shots"].concat(want);
    proc.running = true;
  }
  function landed(line) {
    const i = line.indexOf("\t");
    if (i < 0) return;
    const url = line.slice(0, i), file = line.slice(i + 1);
    const m = Object.assign({}, store.shots);
    m[url] = file;
    store.shots = m;
    // one of the page's own would not come: its twin's are fetched now
    const d = store.detail;
    if (file === "" && d && (d.shots || []).some(x => x.url === url) && (d.fallbackShots || []).length)
      store.fetchShots(d.fallbackShots, true);
  }
  Process {
    id: pageShots
    property var waiting: []
    onExited: {
      if (!pageShots.waiting.length) return;
      const q = pageShots.waiting;
      pageShots.waiting = [];
      Qt.callLater(() => store.fetchShots(q, true));
    }
    stdout: SplitParser { onRead: (line) => store.landed(line) }
  }
  Process {
    id: artShots
    property var waiting: []
    onExited: {
      if (!artShots.waiting.length) return;
      const q = artShots.waiting;
      artShots.waiting = [];
      Qt.callLater(() => store.fetchShots(q, false));
    }
    stdout: SplitParser { onRead: (line) => store.landed(line) }
  }

  // ── the keys ───────────────────────────────────────────────────────────
  // ← → across, ↑ ↓ a row, ↵ the app's page (or Get / Open on it), alt ↑ ↓
  // the sections. Anything else is the window's: typing searches.
  function key(event) {
    const k = event.key, alt = event.modifiers & Qt.AltModifier;
    if (alt && (k === Qt.Key_Up || k === Qt.Key_Down)) {
      const keys = St.SECTIONS.map(s => s[0]);
      const i = keys.indexOf(store.section) + (k === Qt.Key_Down ? 1 : -1);
      if (i >= 0 && i < keys.length) store.showSection(keys[i]);
      return true;
    }
    if (store.lightbox !== "" && (k === Qt.Key_Left || k === Qt.Key_Right)) {
      store.lightboxStep(k === Qt.Key_Right ? 1 : -1);
      return true;
    }
    if (store.view === "page") {
      // the page's source, not the card's: Spotify switched to Flathub
      // is Flathub's to get
      if (k === Qt.Key_Return || k === Qt.Key_Enter) { store.act(store.shown); return true; }
      if (k === Qt.Key_Down || k === Qt.Key_PageDown) { page.flick(0, k === Qt.Key_PageDown ? -2600 : -900); return true; }
      if (k === Qt.Key_Up || k === Qt.Key_PageUp) { page.flick(0, k === Qt.Key_PageUp ? 2600 : 900); return true; }
      return false;
    }
    const dir = k === Qt.Key_Right ? "right" : k === Qt.Key_Left ? "left" : k === Qt.Key_Down ? "down"
      : k === Qt.Key_Up ? "up" : k === Qt.Key_PageDown ? "pagedown" : k === Qt.Key_PageUp ? "pageup" : "";
    if (dir !== "") {
      // Discover: across turns the carousel, up and down scroll the page
      if (store.view === "discover") {
        if (dir === "left" || dir === "right") heroView.turn(dir === "left" ? -1 : 1);
        else discover.flick(0, dir === "down" ? -900 : dir === "up" ? 900 : dir === "pagedown" ? -2600 : 2600);
        return true;
      }
      store.sel = St.stepRows(store.sel, dir, store.walkRows);
      grid.positionViewAtIndex(store.sel, GridView.Contain);
      return true;
    }
    if ((k === Qt.Key_Return || k === Qt.Key_Enter) && store.current) {
      if (event.modifiers & Qt.ControlModifier) store.act(store.current);
      else store.open(store.current);
      return true;
    }
    return false;
  }
  // Esc: off the page first; then the window's own steps
  // Esc: off the lightbox, off the page; the window's own steps after that
  function back() {
    if (store.lightbox !== "") { store.closeShot(); return true; }
    if (store.app) { store.stepBack(); return true; }
    return false;
  }



  // ── the sidebar ────────────────────────────────────────────────────────
  Item {
    id: side
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: 210

    // the sections scroll when the window is too low for them all (user,
    // 2026-10-25: very low screens)
    Flickable {
      id: sideFlick
      anchors.fill: parent
      clip: true
      contentHeight: sideCol.implicitHeight + 22
      boundsBehavior: Flickable.StopAtBounds
      ElasticScroll { view: sideFlick }
      ScrollRail {
        target: sideFlick
        parent: sideFlick
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
      }
    Column {
      id: sideCol
      x: 10
      y: 12
      width: sideFlick.width - 20
      spacing: 2

      Repeater {
        model: St.SECTIONS
        // terminus/ShelfRow, the suite's sidebar row (it was a copy of it),
        // with its press; the line over Installed rides on top
        delegate: Term.ShelfRow {
          id: srow
          required property var modelData
          required property int index
          width: parent.width
          glyph: srow.modelData[2]
          label: srow.modelData[1]
          here: store.section === srow.modelData[0] && !store.searching
          count: srow.modelData[0] === "installed" && store.loaded
            ? String(store.apps.filter(a => a.installed).length) : ""
          onClicked: {
            if (store.searching) store.searchLeft();
            store.showSection(srow.modelData[0]);
            store.released();
          }
          Rectangle {
            visible: srow.modelData[0] === "installed"
            anchors.bottom: parent.top
            anchors.bottomMargin: 1
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: Zenon.border
          }
        }
      }
    }
    }
  }
  Rectangle {
    id: sideRule
    anchors.left: side.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: 1
    color: Zenon.border
  }

  // ── the content ────────────────────────────────────────────────────────
  Item {
    id: content
    anchors.left: sideRule.right
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom

    // not yet, or not at all
    Column {
      anchors.centerIn: parent
      visible: !store.loaded
      spacing: 12
      Working {
        anchors.horizontalCenter: parent.horizontalCenter
        running: store.loading
        visible: store.loading
        ink: Zenon.cyan
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: store.failed ? "The app catalog could not be read" : "Reading the app catalog…"
        color: store.failed ? Zenon.red : Zenon.accentMuted
        font.family: Zenon.face
        font.weight: Font.Bold
        font.pixelSize: Zenon.px(16)
      }
    }

    // ── Discover ──────────────────────────────────────────────────────
    Flickable {
      id: discover
      anchors.fill: parent
      visible: store.loaded && store.view === "discover"
      clip: true
      contentHeight: discCol.implicitHeight + 24
      boundsBehavior: Flickable.StopAtBounds
      ElasticScroll { view: discover }
      ScrollRail {
        target: discover
        parent: discover
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
      }

      Column {
        id: discCol
        x: store.pad
        y: 16
        width: discover.width - store.pad * 2
        spacing: 26

        // NO TITLE: the sidebar says where you are (user, 2026-10-14)
        // ── the features ──────────────────────────────────────────────
        StoreHero {
          id: heroView
          visible: store.features.length > 0
          width: parent.width
          height: Math.round(Math.max(280, Math.min(460, width * 0.42)))
          apps: store.features
          shots: store.shots
          busy: store.busy
          onOpened: (a) => store.open(a)
          onGot: (a) => store.get(a)
          onLaunched: (a) => store.launch(a)
          onRemoved: (a) => store.remove(a)
        }

        // ── the artwork row ───────────────────────────────────────────
        Row {
          visible: store.stories.length > 0
          spacing: 20
          Repeater {
            model: store.stories
            delegate: StoreArt {
              required property var modelData
              width: store.artW
              app: modelData
              file: store.shots[modelData.shot] || ""
              onOpened: store.open(modelData)
            }
          }
        }

        // ── the shelves ───────────────────────────────────────────────
        Repeater {
          id: shelfRep
          model: store.shelves
          delegate: Column {
            id: shelf
            required property var modelData
            required property int index
            width: discCol.width
            spacing: 10
            // the heading is the way in: "Create ›" opens the section
            Item {
              id: shelfHead
              width: headRow.implicitWidth
              height: 30
              Row {
              id: headRow
              anchors.fill: parent
              spacing: 6
              leftPadding: 4
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: shelf.modelData.title
                color: Zenon.white
                font.family: Zenon.face
                font.weight: Font.Bold
                font.pixelSize: Zenon.px(20)
              }
              Text {
                visible: shelf.modelData.key !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: "\u203A"
                color: Zenon.accentMuted
                font.family: Zenon.face
                font.weight: Font.Bold
                font.pixelSize: Zenon.px(22)
              }
              }
              MouseArea {
                id: headMa
                anchors.fill: parent
                enabled: shelf.modelData.key !== ""
                onClicked: store.showSection(shelf.modelData.key)
              }
            }
            // apps, three rows deep
            Grid {
              visible: !shelf.modelData.art
              columns: store.cols
              Repeater {
                model: shelf.modelData.art ? [] : shelf.modelData.apps
                delegate: StoreCard {
                  required property var modelData
                  required property int index
                  width: store.cardW
                  height: 92
                  app: modelData
                  busy: store.busy
                  removable: true
                  onOpened: store.open(modelData)
                  onGot: store.get(modelData)
                  onLaunched: store.launch(modelData)
                  onRemoved: store.remove(modelData)
                }
              }
            }
            // or pictures
            Row {
              visible: shelf.modelData.art
              spacing: 20
              Repeater {
                model: shelf.modelData.art ? shelf.modelData.apps : []
                delegate: StoreArt {
                  required property var modelData
                  width: store.artW
                  app: modelData
                  file: store.shots[modelData.shot] || ""
                  onOpened: store.open(modelData)
                }
              }
            }
          }
        }
      }
    }

    // ── a section, or a search ────────────────────────────────────────
    Item {
      id: gridView
      anchors.fill: parent
      visible: store.loaded && (store.view === "grid" || store.view === "search")

      // NO TITLE over a section or a search: the sidebar says which section
      // and the search field what was typed (user, 2026-10-14). A search
      // that found nothing says so in the middle — see below.
      Item { id: gridTitle; width: 1; height: 4 }

      GridView {
        id: grid
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: gridTitle.bottom
        anchors.bottom: parent.bottom
        anchors.topMargin: 10
        leftMargin: store.pad
        rightMargin: store.pad
        bottomMargin: 16
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        cellWidth: store.cardW
        cellHeight: 92
        cacheBuffer: 400
        model: gridView.visible ? store.gridApps : []
        ElasticScroll { view: grid }
        ScrollRail {
          target: grid
          parent: grid
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.bottom: parent.bottom
        }
        delegate: StoreCard {
          required property var modelData
          required property int index
          width: grid.cellWidth
          height: grid.cellHeight
          app: modelData
          busy: store.busy
          here: index === store.sel
          removable: true
          onOpened: { store.sel = index; store.open(modelData); }
          onGot: store.get(modelData)
          onLaunched: store.launch(modelData)
          onRemoved: store.remove(modelData)
        }
      }

      EmptyState {
        anchors.centerIn: parent
        visible: store.gridApps.length === 0
        text: store.searching ? "No apps for \u201C" + store.query.trim() + "\u201D"
          : store.section === "installed" ? "No apps from the catalog are installed" : "Nothing here yet"
      }
    }

    // ── an app's page ─────────────────────────────────────────────────
    Flickable {
      id: page
      anchors.fill: parent
      visible: store.loaded && store.view === "page"
      clip: true
      contentHeight: pageCol.implicitHeight + 40
      boundsBehavior: Flickable.StopAtBounds
      ElasticScroll { view: page }
      ScrollRail {
        target: page
        parent: page
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
      }

      readonly property var a: store.shown
      readonly property bool aur: !!page.a && page.a.source === "aur"
      // a Flatpak that is here: its permissions are switches
      readonly property bool permsLive: !!page.a && page.a.source === "flatpak" && !!page.a.installed
      // the app's own brand color when its catalog gives one; else the
      // color of its icon (user, 2026-10-14), else the accent
      readonly property color brand: page.a && page.a.color ? page.a.color
        : iconTint.found.a > 0 ? iconTint.found : Zenon.cyan

      // ── THE ICON'S COLOR, sampled once a page ─────────────────────────
      // Drawn at 16×16 and averaged over its vivid pixels — weighted by
      // saturation and brightness, so Spotify's green wins over its black,
      // and a gray icon gives nothing (the accent stands in). 256 pixels,
      // once per page opened: nothing to keep or cache.
      Canvas {
        id: iconTint
        readonly property string src: !page.a ? ""
          : page.a.icon ? "file://" + page.a.icon
          : page.a.stock ? Quickshell.iconPath(page.a.stock, true) : ""
        property color found: "transparent"
        width: 16
        height: 16
        opacity: 0.01
        renderStrategy: Canvas.Immediate
        renderTarget: Canvas.Image
        onSrcChanged: {
          iconTint.found = "transparent";
          if (iconTint.src === "") return;
          if (iconTint.isImageLoaded(iconTint.src)) iconTint.requestPaint();
          else iconTint.loadImage(iconTint.src);
        }
        onImageLoaded: iconTint.requestPaint()
        onPaint: {
          if (iconTint.src === "" || !iconTint.isImageLoaded(iconTint.src)) return;
          const ctx = iconTint.getContext("2d");
          ctx.clearRect(0, 0, 16, 16);
          ctx.drawImage(iconTint.src, 0, 0, 16, 16);
          const d = ctx.getImageData(0, 0, 16, 16).data;
          let r = 0, g = 0, b = 0, w = 0;
          for (let i = 0; i < d.length; i += 4) {
            if (d[i + 3] < 160) continue;
            const R = d[i] / 255, G = d[i + 1] / 255, B = d[i + 2] / 255;
            const mx = Math.max(R, G, B), mn = Math.min(R, G, B);
            const sat = mx > 0 ? (mx - mn) / mx : 0;
            if (mx < 0.18 || sat < 0.22) continue;
            const k = sat * mx;
            r += R * k; g += G * k; b += B * k; w += k;
          }
          iconTint.found = w > 2 ? Qt.rgba(r / w, g / w, b / w, 1) : "transparent";
        }
      }
      readonly property real colW: Math.min(1320, page.width - 64)

      Column {
        id: pageCol
        x: Math.round((page.width - page.colW) / 2)
        y: 14
        width: page.colW
        spacing: 24

        // ── the banner, in the app's own color (the App Store's head) ──
        Rectangle {
          id: banner
          width: parent.width
          height: Math.max(220, bannerRow.implicitHeight + 64, bannerLinks.visible ? bannerLinks.implicitHeight + 64 : 0)
          radius: Zenon.windowRadius
          border.width: 1
          border.color: Zenon.border
          gradient: Gradient {
            orientation: Gradient.Horizontal
            // quiet (user, 2026-10-14: it was twice this)
            GradientStop { position: 0.0; color: Zenon.alpha(page.brand, 0.20) }
            GradientStop { position: 0.55; color: Zenon.alpha(page.brand, 0.09) }
            GradientStop { position: 1.0; color: Zenon.alpha(page.brand, 0.03) }
          }
          Row {
            id: bannerRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 40
            anchors.rightMargin: bannerLinks.visible ? 40 + bannerLinks.width + 32 : 40
            anchors.verticalCenter: parent.verticalCenter
            spacing: 34
            StoreIcon {
              id: pageIcon
              anchors.verticalCenter: parent.verticalCenter
              app: page.a
              size: 136
            }
            Column {
              width: parent.width - pageIcon.width - 34
              anchors.verticalCenter: parent.verticalCenter
              spacing: 5
              Text {
                width: parent.width
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                text: page.a ? page.a.name : ""
                color: Zenon.white
                font.family: Zenon.face
                font.weight: Font.Bold
                font.pixelSize: Zenon.px(34)
              }
              // its section, in the accent, as Developer Tools is Xcode's
              Text {
                readonly property var sec: St.sectionOf(page.a)
                visible: !!sec
                text: sec ? sec[1] : ""
                color: Zenon.cyan
                font.family: Zenon.face
                font.weight: Font.Bold
                font.pixelSize: Zenon.px(17)
              }
              Text {
                width: parent.width
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                text: page.a ? page.a.summary : ""
                color: Zenon.white
                opacity: 0.85
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.pixelSize: Zenon.px(16)
              }
              Item { width: 1; height: 10 }
              Row {
                spacing: 12
                StoreGet {
                  big: true
                  app: page.a
                  busy: store.busy
                  onGot: store.get(page.a)
                  onLaunched: store.launch(page.a)
                }
                // Remove as the trash glyph, after Open (user, 2026-10-18);
                // Get's own height beside it
                StoreRemove {
                  visible: !!page.a && page.a.installed
                  anchors.verticalCenter: parent.verticalCenter
                  big: true
                  busy: store.busy
                  onRemoved: store.remove(page.a)
                }
                // where it comes from, said in words beside the mark (one
                // source; with more, the switch below says it)
                Row {
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: 7
                  leftPadding: 6
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: St.sourceGlyph(page.a)
                    color: page.aur ? Zenon.magenta : Zenon.blue
                    font.family: Zenon.face
                    font.weight: Zenon.weight
                    font.pixelSize: Zenon.px(16)
                  }
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: St.sourceLabel(page.a)
                    color: Zenon.white
                    opacity: 0.85
                    font.family: Zenon.face
                    font.weight: Zenon.weight
                    font.pixelSize: Zenon.px(15)
                  }
                  // Flathub checks who publishes it; said when it has — a
                  // thing of its own, apart from the source (user, 2026-10-14)
                  Text {
                    visible: !!page.a && !!page.a.verified
                    anchors.verticalCenter: parent.verticalCenter
                    leftPadding: 14
                    text: "\uF058  verified"
                    color: Zenon.green
                    font.family: Zenon.face
                    font.weight: Zenon.weight
                    font.pixelSize: Zenon.px(15)
                  }
                }
              }
              // ── WHERE FROM, when there is a choice ───────────────────
              // The same app from Arch or the AUR, and from Flathub: one
              // card, and here the pick — what each means said under it
              // (user, 2026-10-14). Get, the facts and the sandbox follow.
              Item { width: 1; height: St.sources(store.app).length ? 6 : 0 }
              Term.Segments {
                visible: St.sources(store.app).length > 0
                width: Math.min(parent.width, 560)
                even: true
                strong: true
                textSize: Zenon.px(15)
                ink: Zenon.accentKey
                options: St.sources(store.app)
                // each channel's own mark before its name (user, 2026-10-15)
                glyphOf: (v) => St.sourceGlyph({ source: v })
                current: store.variant
                onChose: (v) => { store.variant = v; store.released(); }
              }
            }
          }

          // ── its links ─────────────────────────────────────────────────
          // IN THE BANNER'S RIGHT, where the gradient stood empty (user,
          // 2026-10-15: "might as well make use of the space"); the name's
          // column gives way to them
          Flow {
            id: bannerLinks
            readonly property var list: St.links(store.detail && store.detail.urls || {})
            visible: list.length > 0
            anchors.right: parent.right
            anchors.rightMargin: 40
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(300, parent.width * 0.3)
            layoutDirection: Qt.RightToLeft
            spacing: 10
            Repeater {
              model: parent.list
              delegate: Rectangle {
                id: link
                required property var modelData
                width: linkRow.implicitWidth + 26
                height: 32
                radius: Zenon.windowRadius
                color: linkMa.pressed ? Zenon.pressFill : Zenon.wash(0.05)   // the suite's press (2026-10-15)
                border.width: 1
                border.color: Zenon.border
                Row {
                  id: linkRow
                  anchors.centerIn: parent
                  spacing: 8
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: link.modelData.glyph
                    color: Zenon.cyan
                    font.family: Zenon.face
                    font.weight: Zenon.weight
                    font.pixelSize: Zenon.px(14)
                  }
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: link.modelData.label
                    color: Zenon.white
                    font.family: Zenon.face
                    font.weight: Zenon.weight
                    font.pixelSize: Zenon.px(15)
                  }
                }
                MouseArea {
                  id: linkMa
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: Qt.openUrlExternally(link.modelData.url)
                }
              }
            }
          }
        }

        // ── the strip: what there is to know at a glance ──────────────
        // The App Store's ratings, age and chart are not ours to have; what
        // is: how much of Arch uses it, the AUR's votes, who makes it, what
        // it is, its license, its size.
        Row {
          id: strip
          readonly property var cells: {
            const a = page.a, i = store.info || {}, d = store.detail || {};
            if (!a) return [];
            const out = [];
            // Arch's share from pkgstats; a Flathub app's own installs, never
            // the ranking figure made from them
            if (a.source === "flatpak") { if (a.installs > 0) out.push(["FLATHUB", St.count(a.installs), "installs a month"]); }
            else if (a.pop > 0) out.push(["ON ARCH", (a.pop >= 10 ? Math.round(a.pop) : Math.round(a.pop * 10) / 10) + "%", "of machines"]);
            if (page.aur && d.votes) out.push(["AUR", String(d.votes), d.votes === 1 ? "vote" : "votes"]);
            const sec = St.sectionOf(a);
            if (sec) out.push(["CATEGORY", sec[2], sec[1]]);
            if (a.dev) out.push(["DEVELOPER", "\uF2BD", a.dev]);
            const lic = St.licence(d.license || i["Licenses"] || "");
            if (lic) out.push(["LICENSE", lic.split(/[ (]/)[0].replace(/-or-later$/, "+"), lic === "Proprietary" ? "proprietary" : "license"]);
            const sz = St.sizeParts(i["Installed Size"] || i["Download Size"] || "");
            if (sz[0]) out.push(["SIZE", sz[0], sz[1]]);
            return out;
          }
          visible: strip.cells.length > 0
          width: parent.width
          Repeater {
            model: strip.cells
            delegate: Item {
              required property var modelData
              required property int index
              width: strip.width / strip.cells.length
              height: 76
              Rectangle {
                visible: index > 0
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 1
                height: 40
                color: Zenon.border
              }
              Column {
                anchors.centerIn: parent
                width: parent.width - 16
                spacing: 3
                Text {
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  text: modelData[0]
                  color: Zenon.accentMuted
                  font.family: Zenon.face
                  font.weight: Zenon.titleWeight
                  font.pixelSize: Zenon.px(11)
                  font.letterSpacing: Zenon.labelSpacing
                }
                Text {
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  elide: Text.ElideRight
                  text: modelData[1]
                  color: Zenon.accentKey
                  font.family: Zenon.face
                  font.weight: Font.Bold
                  font.pixelSize: Zenon.px(21)
                }
                Text {
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  elide: Text.ElideRight
                  text: modelData[2]
                  color: Zenon.accentMuted
                  font.family: Zenon.face
                  font.weight: Zenon.weight
                  font.pixelSize: Zenon.px(13)
                }
              }
            }
          }
        }

        // ── an AUR app, said plainly ──────────────────────────────────
        // Built here from a recipe anyone can submit — what the confirm
        // sheet's PKGBUILD review is for — and described in Flathub's words,
        // since the AUR has none of its own.
        Rectangle {
          visible: page.aur
          width: parent.width
          height: aurNote.implicitHeight + 22
          radius: Zenon.windowRadius
          color: Zenon.alpha(Zenon.magenta, 0.08)
          border.width: 1
          border.color: Zenon.alpha(Zenon.magenta, 0.35)
          Row {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 12
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "\uF415"
              color: Zenon.magenta
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(18)
            }
            Text {
              id: aurNote
              width: parent.width - 40
              wrapMode: Text.Wrap
              textFormat: Text.StyledText
              linkColor: Zenon.link   // a link in it is the theme's (Zenon.link)
              readonly property var d: store.detail || {}
              text: "<b>From the AUR.</b> Built on this computer from a recipe its users maintain"
                + (d.maintainer ? " \u2014 this one by " + d.maintainer : "") + "; you can read the PKGBUILD "
                + "before it builds. Described here by its Flathub listing."
                + (d.outOfDate ? "  <font color='" + Zenon.hex(Zenon.yellow) + "'>Flagged out of date.</font>" : "")
              color: Zenon.accentKey
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(15)
            }
          }
        }

        // ── a Flatpak's sandbox, said plainly ─────────────────────────
        // What it may touch beyond itself, worst first — the holes in its
        // sandbox, from its metadata (St.permissions). Drawing, sound and
        // its own settings every app has, and are not news.
        Rectangle {
          visible: !!page.a && page.a.source === "flatpak" && store.perms !== null
          width: parent.width
          height: permCol.implicitHeight + 24
          radius: Zenon.windowRadius
          color: Zenon.alpha(Zenon.blue, 0.06)
          border.width: 1
          border.color: Zenon.alpha(Zenon.blue, 0.30)
          Column {
            id: permCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 6
            Row {
              spacing: 12
              Text {
                text: "\uF132"
                color: Zenon.blue
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.pixelSize: Zenon.px(17)
              }
              Text {
                width: permCol.width - 40
                wrapMode: Text.Wrap
                textFormat: Text.StyledText
                linkColor: Zenon.link   // a link in it is the theme's (Zenon.link)
                text: !store.perms || store.perms.length === 0
                  ? "<b>Sealed.</b> Runs in Flatpak's sandbox and asks for nothing beyond drawing its window and playing sound."
                  : page.permsLive
                    ? "<b>Runs in Flatpak's sandbox.</b> Untick what it should not have \u2014 it takes effect the next time it starts."
                    : "<b>Runs in Flatpak's sandbox,</b> with access to:"
                color: Zenon.accentKey
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.pixelSize: Zenon.px(15)
              }
            }
            Repeater {
              model: store.perms || []
              delegate: Item {
                id: permRow
                required property var modelData
                width: permCol.width
                height: 26
                // installed: a switch for each — off is an override
                Controls.Check {
                  id: permCheck
                  visible: page.permsLive
                  x: 30
                  anchors.verticalCenter: parent.verticalCenter
                  lit: permRow.modelData.on
                  enabled2: !(store.busy && page.a.scope !== "user")
                  onToggled: store.setPerm(permRow.modelData, !permRow.modelData.on)
                }
                // not installed: what it would have, by how much it reaches
                Rectangle {
                  visible: !page.permsLive
                  x: 30
                  anchors.verticalCenter: parent.verticalCenter
                  width: 7
                  height: 7
                  radius: 3.5
                  color: permRow.modelData.level === "high" ? Zenon.yellow : permRow.modelData.level === "mid" ? Zenon.blue : Zenon.accentMuted
                }
                Text {
                  x: page.permsLive ? 30 + permCheck.width + 10 : 47
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.StyledText
                  linkColor: Zenon.link   // a link in it is the theme's (Zenon.link)
                  text: Cer.esc(permRow.modelData.text)
                    + (permRow.modelData.changed ? "  <font color='" + Zenon.hex(Zenon.cyan) + "'>"
                      + (permRow.modelData.on ? "given by you" : "taken away") + "</font>" : "")
                  color: page.permsLive && !permRow.modelData.on ? Zenon.accentMuted : Zenon.white
                  font.family: Zenon.face
                  font.weight: Zenon.weight
                  font.pixelSize: Zenon.px(15)
                }
              }
            }
            // anything changed: one press puts it all back as the app asks
            Item {
              visible: page.permsLive && (store.perms || []).some(p => p.changed)
              width: permCol.width
              height: visible ? permReset.height + 6 : 0
              DialogButton {
                id: permReset
                x: 30
                anchors.bottom: parent.bottom
                label: "Reset to defaults"
                ink: Zenon.accentMuted
                ready: !(store.busy && !!page.a && page.a.scope !== "user")
                onClicked: store.resetPerms()
              }
            }
          }
        }

        // ── screenshots ───────────────────────────────────────────────
        ListView {
          id: shotList
          // a screenshot that would not come is swapped for its Flathub
          // twin's (ceres-store's fallbackShots), and dropped when there is
          // none — never a frame saying it is missing
          readonly property var list: {
            const d = store.detail;
            if (!d) return [];
            const fb = d.fallbackShots || [];
            const out = [];
            let fi = 0;
            for (const sh of d.shots || []) {
              if (store.shots[sh.url] !== "") { out.push(sh); continue; }
              while (fi < fb.length && store.shots[fb[fi]] === "") fi++;
              if (fi < fb.length) out.push({ url: fb[fi++], caption: sh.caption });
            }
            return out;
          }
          // THREE ACROSS, of one size (the App Store's): a picture of
          // another shape sits inside its frame rather than resizing it
          readonly property real cellW: (shotList.width - 2 * shotList.spacing) / 3
          visible: shotList.list.length > 0
          width: parent.width
          height: visible ? Math.round(shotList.cellW * 0.625) + 30 : 0
          orientation: ListView.Horizontal
          spacing: 18
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          model: shotList.list
          delegate: Column {
            id: shot
            required property var modelData
            readonly property string file: store.shots[shot.modelData.url] || ""
            readonly property real h: Math.round(shotList.cellW * 0.625)
            width: shotFrame.width
            spacing: 8
            ClippingRectangle {
              id: shotFrame
              height: shot.h
              width: shotList.cellW
              radius: Zenon.windowRadius
              color: Zenon.wash(0.04)
              border.width: 1
              border.color: Zenon.border
              Image {
                id: shotImg
                anchors.fill: parent
                source: shot.file !== "" ? "file://" + shot.file : ""
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                sourceSize.height: 700
                smooth: true
                mipmap: true
              }
              MouseArea {
                anchors.fill: parent
                enabled: shot.file !== ""
                onClicked: store.openShot(shotImg, shot.file,
                  shotList.list.map(x => store.shots[x.url] || "").filter(f => f !== ""))
              }
              Working {
                anchors.centerIn: parent
                running: shot.file === "" && !(shot.modelData.url in store.shots)
                visible: running
                ink: Zenon.accentMuted
              }
            }
            Text {
              width: shotFrame.width
              elide: Text.ElideRight
              text: shot.modelData.caption || ""
              color: Zenon.accentMuted
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(14)
            }
          }
          ElasticScroll { view: shotList }
        }

        // ── what it is: a few lines, and the rest behind "more" ───────
        Column {
          id: about
          property bool open: false
          readonly property real fold: 150
          readonly property bool long: aboutBlocks.implicitHeight > about.fold + 40
          width: parent.width
          spacing: 6
          // FOLDED, IT FADES (user, 2026-10-14/15). The TEXT fades — a fade
          // painted in the window's color drew a dark band on its glass — and
          // without an effect: MultiEffect's mask, then OpacityMask, left it
          // cut off on screen. The fold is the words to just above the edge,
          // then the last stretch again in thin strips, each a copy of the
          // words clipped to its slice and fainter than the one above.
          readonly property real fadeH: 64
          readonly property int strips: 16
          readonly property bool folded: about.long && !about.open
          Item {
            id: aboutClip
            width: parent.width
            height: about.folded ? about.fold : aboutBlocks.implicitHeight
            Item {
              width: parent.width
              height: about.folded ? about.fold - about.fadeH : parent.height
              clip: true
              StoreBlocks {
                id: aboutBlocks
                width: parent.width
                blocks: store.detail ? store.detail.desc || [] : []
              }
            }
            Repeater {
              model: about.folded ? about.strips : 0
              delegate: Item {
                required property int index
                readonly property real sliceH: about.fadeH / about.strips
                y: about.fold - about.fadeH + index * sliceH
                width: aboutClip.width
                height: sliceH
                clip: true
                opacity: 1 - (index + 1) / (about.strips + 1)
                StoreBlocks {
                  y: -parent.y
                  width: aboutClip.width
                  blocks: aboutBlocks.blocks
                }
              }
            }
          }
          // and a chevron unfolds it — turned over once it is open
          Rectangle {
            visible: about.long
            anchors.horizontalCenter: parent.horizontalCenter
            width: 44
            height: 24
            radius: Zenon.windowRadius
            color: moreMa.pressed ? Zenon.pressFill : Zenon.wash(0.06)   // the suite's press (2026-10-15)
            border.width: 1
            border.color: Zenon.border
            Text {
              anchors.centerIn: parent
              text: "\uF078"
              color: Zenon.cyan
              rotation: about.open ? 180 : 0
              Behavior on rotation { NumberAnimation { duration: Zenon.ms(220); easing.type: Easing.OutCubic } }
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(12)
            }
            MouseArea {
              id: moreMa
              anchors.fill: parent
              anchors.margins: -6
              onClicked: about.open = !about.open
            }
          }
          Connections {
            target: store
            function onAppChanged() { about.open = false; }
          }
        }

        // ── what is new ───────────────────────────────────────────────
        Column {
          readonly property var rel: store.detail && store.detail.releases && store.detail.releases.length
            ? store.detail.releases[0] : null
          visible: !!rel
          width: parent.width
          spacing: 8
          Text {
            text: "What’s New"
            color: Zenon.white
            font.family: Zenon.face
            font.weight: Font.Bold
            font.pixelSize: Zenon.px(20)
          }
          Text {
            text: parent.rel ? "Version " + parent.rel.version
              + (parent.rel.date ? "  ·  " + St.releaseDate(parent.rel.date) : "") : ""
            color: Zenon.accentMuted
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(14)
          }
          StoreBlocks {
            width: parent.width
            blocks: parent.rel ? parent.rel.notes : []
          }
        }

        // ── the facts ─────────────────────────────────────────────────
        // no heading (user, 2026-10-14): a hairline parts them from the
        // words above
        Column {
          width: parent.width
          spacing: 18
          Rectangle {
            width: parent.width
            height: 1
            color: Zenon.border
          }
          Grid {
            id: facts
            // not `rows`: that is Grid's own row count, shadowed
            readonly property var factRows: {
              const a = page.a, i = store.info || {};
              if (!a) return [];
              const out = [];
              if (a.dev) out.push(["Developer", a.dev]);
              out.push(["Source", St.sourceLabel(a)]);
              out.push(["Package", a.pkg]);
              if (i["Version"]) out.push(["Version", i["Version"]]);
              if (i["Download Size"] && !a.installed) out.push(["Download", i["Download Size"]]);
              if (i["Installed Size"]) out.push(["Size", i["Installed Size"]]);
              const lic = St.licence(store.detail && store.detail.license || i["Licenses"] || "");
              if (lic) out.push(["License", lic]);
              if (a.cats && a.cats.length) out.push(["Category", a.cats.slice(0, 3).join(", ")]);
              const d = store.detail || {};
              if (page.aur && d.votes) out.push(["AUR votes", String(d.votes)]);
              if (page.aur && d.maintainer) out.push(["Maintainer", d.maintainer]);
              if (a.alts && a.alts.length) out.push(["Other builds", a.alts.join(", ")]);
              return out;
            }
            columns: page.colW > 700 ? 4 : 2
            columnSpacing: 26
            rowSpacing: 14
            Repeater {
              model: facts.factRows
              delegate: Column {
                required property var modelData
                width: (page.colW - facts.columnSpacing * (facts.columns - 1)) / facts.columns
                spacing: 2
                Text {
                  text: modelData[0]
                  color: Zenon.accentMuted
                  font.family: Zenon.face
                  font.weight: Zenon.weight
                  font.pixelSize: Zenon.px(13)
                }
                Text {
                  width: parent.width
                  wrapMode: Text.Wrap
                  text: modelData[1]
                  color: Zenon.white
                  font.family: Zenon.face
                  font.weight: Zenon.weight
                  font.pixelSize: Zenon.px(15)
                }
              }
            }
          }
        }
      }
    }

    // ── WHAT THE STORE NEEDS FIRST (user, 2026-10-25) ────────────────
    // Said here, in the Store's own tab, with its Install button — not as
    // Setup in Updates: the packages only the Store wants (Ceres.storeNeeds,
    // Cer.DEPS `store`), over the content until they are in. Installed,
    // Ceres looks again and the catalog is read.
    Rectangle {
      anchors.fill: parent
      visible: Ceres.storeNeeds.length > 0
      color: Zenon.layerBg
      MouseArea { anchors.fill: parent }
      Column {
        anchors.centerIn: parent
        width: Math.min(parent.width - 80, Zenon.px(15) * 34)
        spacing: 14
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: "\u{F0D68}"
          color: Zenon.cyan
          font.family: Zenon.face
          font.pixelSize: Zenon.px(40)
        }
        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.Wrap
          text: "The Store needs " + Cer.nameList(Ceres.storeNeeds.map((m) => m.pkg), 3) + " first"
          color: Zenon.ink
          font.family: Zenon.face
          font.weight: Font.Bold
          font.pixelSize: Zenon.px(17)
        }
        Repeater {
          model: Ceres.storeNeeds
          delegate: Text {
            required property var modelData
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: modelData.pkg + " — " + modelData.why.join("; ")
            color: Zenon.accentMuted
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(14)
          }
        }
        DialogButton {
          anchors.horizontalCenter: parent.horizontalCenter
          label: Ceres.installing ? "Installing…" : "Install"
          ink: Zenon.cyan
          primary: true
          ready: !Ceres.installing && !Ceres.txBusy
          onClicked: {
            const pkgs = Ceres.storeNeeds.map((m) => m.pkg);
            Ceres.install(pkgs, "for the Store", (ok) => {
              Ceres.checkDeps();
              if (!ok) return;
              store.failed = false;
              store.load();
            });
          }
        }
      }
    }
  }

  // ── a screenshot, large ────────────────────────────────────────────────
  // A step slides, as picasso's viewer does (ViewerWindow's enterK): the
  // next shot comes in from the side it lies on once it is decoded, the
  // last goes out the other way (`ghost`, the same url again, a cache hit),
  // and stepping past either end pulls the shot that way and back.
  Rectangle {
    id: lightboxBox
    anchors.fill: content
    visible: store.lightbox !== ""
    color: Zenon.alpha(Zenon.layerBg, 0.94 * lightboxBox.zk)
    clip: true
    readonly property int slideMs: Math.round(200 * Oracle.motionScale)
    // ── IN FROM THE THUMBNAIL, OUT TO IT ────────────────────────────────
    // zk 0 is the thumbnail's own box (`from`), 1 the whole view; the picture
    // is laid between the two, the backdrop fades with it, and a close waits
    // for the way back before the lightbox goes
    property rect from: Qt.rect(0, 0, 0, 0)
    property real zk: 1
    readonly property rect full: Qt.rect(28, 28, Math.max(0, width - 56), Math.max(0, height - 56))
    function zoomIn(r) {
      lightboxBox.from = r;
      zoomAnim.stop();
      lightboxBox.zk = r.width > 0 ? 0 : 1;
      zoomAnim.to = 1;
      zoomAnim.restart();
    }
    function zoomOut() {
      if (lightboxBox.from.width <= 0 || lightboxBox.k < 1) { store.lightbox = ""; return; }
      zoomAnim.to = 0;
      zoomAnim.restart();
    }
    NumberAnimation {
      id: zoomAnim
      target: lightboxBox; property: "zk"
      duration: Zenon.ms(170); easing.type: Easing.OutCubic   // brisker (user, 2026-10-19)
      onFinished: if (lightboxBox.zk <= 0.001) { store.lightbox = ""; lightboxBox.zk = 1; }
    }
    property string ghost: ""
    property int dir: 0
    property real k: 1
    property real bumpX: 0
    property int bumpDir: 0
    function step(d) {
      enterAnim.stop();
      lightboxBox.ghost = store.lightbox;
      lightboxBox.dir = d;
      lightboxBox.k = 0;
    }
    function enter() {
      if (lightboxBox.k < 1 && !enterAnim.running && shownImg.status === Image.Ready) enterAnim.restart();
    }
    function bump(d) {
      lightboxBox.bumpDir = d;
      bumpAnim.restart();
    }
    onVisibleChanged: if (!visible) { enterAnim.stop(); lightboxBox.ghost = ""; lightboxBox.k = 1; }
    NumberAnimation { id: enterAnim; target: lightboxBox; property: "k"; to: 1
                      duration: lightboxBox.slideMs; easing.type: Easing.OutCubic
                      onFinished: lightboxBox.ghost = "" }
    SequentialAnimation {
      id: bumpAnim
      NumberAnimation { target: lightboxBox; property: "bumpX"; to: -lightboxBox.bumpDir * 28
                        duration: Math.round(90 * Oracle.motionScale); easing.type: Easing.OutCubic }
      NumberAnimation { target: lightboxBox; property: "bumpX"; to: 0
                        duration: Math.round(320 * Oracle.motionScale); easing.type: Easing.OutCubic }
    }
    // the shot stepped away from, sliding off as the next slides in
    Image {
      anchors.fill: parent
      anchors.margins: 28
      visible: lightboxBox.ghost !== ""
      source: lightboxBox.ghost !== "" ? "file://" + lightboxBox.ghost : ""
      fillMode: Image.PreserveAspectFit
      // a cache hit: asked exactly as the shown one was
      asynchronous: false
      cache: true
      smooth: true
      mipmap: true
      transform: Translate { x: -lightboxBox.k * lightboxBox.dir * lightboxBox.width }
    }
    Image {
      id: shownImg
      x: lightboxBox.from.x + (lightboxBox.full.x - lightboxBox.from.x) * lightboxBox.zk
      y: lightboxBox.from.y + (lightboxBox.full.y - lightboxBox.from.y) * lightboxBox.zk
      width: lightboxBox.from.width + (lightboxBox.full.width - lightboxBox.from.width) * lightboxBox.zk
      height: lightboxBox.from.height + (lightboxBox.full.height - lightboxBox.from.height) * lightboxBox.zk
      source: store.lightbox !== "" ? "file://" + store.lightbox : ""
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      cache: true
      smooth: true
      mipmap: true
      // held off until decoded, so the last stays put meanwhile, never a gap
      opacity: lightboxBox.k < 1 && status !== Image.Ready ? 0 : 1
      onStatusChanged: if (status === Image.Ready) lightboxBox.enter()
      transform: Translate { x: (1 - lightboxBox.k) * lightboxBox.dir * lightboxBox.width + lightboxBox.bumpX }
    }
    MouseArea {
      anchors.fill: parent
      onClicked: store.closeShot()
    }
    // previous and next, picasso's edge tabs (morpheus/EdgeTab)
    EdgeTab {
      edge: "left"
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      shown: store.lightboxAt > 0 && lightboxBox.zk > 0.99
      onClicked: { store.lightboxStep(-1); store.released(); }
    }
    EdgeTab {
      edge: "right"
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      shown: store.lightboxAt >= 0 && store.lightboxAt < store.lightboxFiles.length - 1 && lightboxBox.zk > 0.99
      onClicked: { store.lightboxStep(1); store.released(); }
    }
  }

  // mouse 4 and 5, anywhere over the Store; every other button passes by
  MouseArea {
    anchors.fill: parent
    z: 100
    acceptedButtons: Qt.BackButton | Qt.ForwardButton
    onClicked: (m) => {
      if (m.button === Qt.BackButton) store.stepBack();
      else store.stepForward();
      store.released();
    }
  }

  // the views the window frosts under its head and foot
  readonly property var edgeViews: [discover, grid, page]
}
