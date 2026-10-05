// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// PICASSO — the wallpaper store. Quickshell is the daemon itself here: there
// is no swww or hyprpaper to talk to, the background is just another layer
// surface this shell owns. This singleton holds what is chosen and where the
// choices live; PicassoDaemon paints them and PicassoPopup picks them.

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../morpheus"
import "../morpheus/thumbs.js" as Thumbs
import "../oracle"
import "picasso.js" as Art

Singleton {
  id: root

  // ── where the backgrounds are ────────────────────────────────────────
  // WHAT XDG SAYS, not a path written down here. "Pictures" is the
  // specification's own default and xdg-user-dirs is free to have moved it —
  // to Bilder, to Images, onto another disk — and a shell that assumed the
  // English name would find nothing on such a machine and report an empty
  // folder as though the folder were empty.
  //
  // The one piece that is genuinely this shell's own convention is the
  // "Wallpapers" leaf, and it is only a DEFAULT: oracle stores nothing until
  // somebody types a path, and anything typed there wins outright.
  //
  // Trailing slashes are cut because every path built from this joins with one
  // of its own, and "~/Walls//a.png" is a different string from
  // "~/Walls/a.png" — which matters, because that string is the key the
  // per-monitor assignment is stored under.
  readonly property string defaultDir: root.picturesDir + "/Wallpapers"

  readonly property string dir: {
    const d = String(Oracle.backgroundDir || "").replace(/\/+$/, "");
    return d === "" ? root.defaultDir : d;
  }

  // XDG_PICTURES_DIR, from the file xdg-user-dirs actually writes it to —
  // see morpheus/UserDirs.
  readonly property string picturesDir: UserDirs.pictures

  // Where the thumbnails live and how big they are is morpheus/thumbs.js'
  // business, not picasso's — see scan(), which builds both from Thumbs so a
  // wallpaper terminus has already thumbnailed is found here under the same
  // name. Picasso carried its own cacheDir and thumbSize until that move and
  // then kept them, unread, describing a size and a directory neither of which
  // was in use any more.

  // How an image that is not the monitor's shape gets fitted. Cover by
  // default: this setup pairs a 2560x1440 with a rotated 1080x1920, and
  // anything else letterboxes one of them badly.
  //
  // Named rather than numbered — "crop" is a thing a person can choose,
  // Image.PreserveAspectCrop is a number that happens to be 2 — so the
  // translation happens here, where Image is already in scope, and the name is
  // what travels through oracle and through the picker.
  //
  // The ORDER is the ring alt+f walks, and it is not alphabetical: it runs
  // from the one that always fills the screen to the ones that increasingly
  // do not, so stepping through it is stepping along a single axis rather
  // than shuffling a bag of words.
  // ── CAPTURE ──────────────────────────────────────────────────────────
  // The screenshot, the colour picker and the annotation window are picasso's
  // too — pictures of the screen, and a picture of one pixel of it. This
  // singleton only says they were asked for; PicassoCapture, PicassoPicker
  // and PicassoAnnotator each answer their own signal, so anything in the
  // shell can reach them without knowing where they live (terminus asks for
  // an annotation straight from its context menu).
  signal shotRequested(string mode)
  signal pickRequested()
  signal annotateRequested(string path)
  // ── THE VIEWER ───────────────────────────────────────────────────────
  // Every picture on the machine, not only the wallpapers: PicassoViewer
  // opens a window on it with its folder as the gallery. Annotation is one of
  // the viewer's modes now, so annotateRequested lands there too.
  //
  // `paths` is one path, or several joined by newlines — several is a
  // gallery of just those, the way a file manager hands over a selection.
  signal viewRequested(string paths)
  // And the way back: a picture from the viewer made a background goes
  // through the picker's own card — its monitors, span, fit and slideshow —
  // carrying whatever look was dialled in the viewer, staged, not applied.
  // `adopt`, when given, says `path` is a scratch render (a selection) to be
  // written into adopt.dir as adopt.name only if the card is applied — see
  // PicassoPopup.focusAdopt.
  signal setterRequested(string path, var look, var adopt)

  // Where screenshots land: XDG's pictures directory, then Screenshots — the
  // folder hyprshot.lua used, found the same way.
  readonly property string shotDir: root.picturesDir + "/Screenshots"

  // THE POINTER, kept out of the picture. Cursors are drawn in software here
  // (zoom.lua), into the frame itself, so no capture can leave one out —
  // hyprland is told to stop drawing it for the moment of the capture
  // instead. Through eval: the lua config refuses `hyprctl keyword`.
  function cursorCmd(visible) {
    return "hyprctl -q eval 'hl.config({ cursor = { invisible = " + (visible ? "false" : "true") + " } })'";
  }
  function showCursor(visible) { Quickshell.execDetached(["sh", "-c", root.cursorCmd(visible)]); }

  function shoot(mode) { root.shotRequested(mode || "region"); }
  function pick() { root.pickRequested(); }
  function annotate(path) { if (path && path !== "") root.annotateRequested(path); }
  // "" is the viewer opened on its own: the pictures folder, as a gallery
  function view(paths) { root.viewRequested(paths || ""); }
  function setAsWallpaper(path, look, adopt) {
    if (path && path !== "") root.setterRequested(path, look || ({}), adopt || null);
  }

  readonly property var fitModes: ["crop", "fit", "stretch", "pad", "tile"]
  readonly property var fitLabels: ({
    crop: "cropped", fit: "fitted", stretch: "stretched",
    pad: "centred", tile: "tiled"
  })

  // ── PER MONITOR, like the image itself ───────────────────────────────
  // One global fit is wrong the moment two monitors are different shapes,
  // which is the exact case picasso already handled for the image: this setup
  // pairs a 2560x1440 with a rotated 1080x1920, and an image that wants
  // cropping on one wants centring on the other.
  //
  // Two layers, and only two. `fits` holds the monitors that have been given
  // an answer of their own; everything else takes oracle's, which is the
  // DEFAULT rather than a fourth place to look. A monitor that has never been
  // touched therefore follows the setting, and one that has been set stays
  // set — including across replugging, because the key is the name.
  property var fits: ({})

  readonly property string defaultFit: {
    const m = Oracle.backgroundFit;
    return root.fitModes.indexOf(m) >= 0 ? m : "crop";
  }

  function fitFor(screenName) {
    const f = root.fits[screenName];
    return root.fitModes.indexOf(f) >= 0 ? f : root.defaultFit;
  }

  function fitLabelFor(screenName) {
    return root.fitLabels[root.fitFor(screenName)];
  }

  // Named rather than numbered on the way in, and numbered on the way out —
  // Image.PreserveAspectCrop is a number that happens to be 2, and nothing
  // outside this function should have to know that.
  function fillModeFor(screenName) {
    const m = root.fitFor(screenName);
    if (m === "fit") return Image.PreserveAspectFit;
    if (m === "stretch") return Image.Stretch;
    if (m === "pad") return Image.Pad;
    if (m === "tile") return Image.Tile;
    return Image.PreserveAspectCrop;
  }

  // One monitor's answer.
  function setFitFor(screenName, fit) {
    if (root.fitModes.indexOf(fit) < 0) return;
    const next = Object.assign({}, root.fits);
    next[screenName] = fit;
    root.fits = next;
    saveTimer.restart();
  }

  // Every monitor's answer: the default moves AND the overrides are cleared,
  // for the same reason setAll clears the per-monitor images. "All monitors"
  // that quietly left an old override in place would be a lie.
  function setFitAll(fit) {
    if (root.fitModes.indexOf(fit) < 0) return;
    root.fits = ({});
    Oracle.set("backgroundFit", fit);
    saveTimer.restart();
  }

  // Every monitor at once, which is what the context menu's "All monitors"
  // row asks for.
  function cycleFit() {
    const i = root.fitModes.indexOf(root.defaultFit);
    root.setFitAll(root.fitModes[(i + 1) % root.fitModes.length]);
  }

  // ONE MONITOR'S RING, which is what the picker's status line walks now.
  // It used to walk the one above, and that had a cost that was invisible
  // until you owned two screens: setFitAll clears the per-monitor answers,
  // so tiling one monitor from its own menu and then stepping the ring on
  // the other quietly threw the first away. A ring in a panel that is
  // itself on a monitor has an obvious subject, and this is it.
  function cycleFitFor(screenName) {
    if (!screenName || screenName === root.fallbackKey) { root.cycleFit(); return; }
    const i = root.fitModes.indexOf(root.fitFor(screenName));
    root.setFitFor(screenName, root.fitModes[(i + 1) % root.fitModes.length]);
  }

  readonly property var extensions: ["jpg", "jpeg", "png", "webp", "bmp", "gif", "jxl", "avif"]

  // every wallpaper found, sorted, newest scan wins
  property var files: []
  property bool scanning: false

  // ── what is on screen ────────────────────────────────────────────────
  // monitor name -> path, plus "*" for the one every other monitor uses.
  // Keyed by name rather than index because a monitor's index changes when
  // you unplug the other one, and the wallpaper should not follow it.
  property var assignment: ({})

  readonly property string fallbackKey: "*"

  // Trigger for replaying the wallpaper zoom on unlock — bumped by shell
  // when Cerberus releases the session, watched by PicassoDaemon per-screen.
  property int introTick: 0
  property int holdTick: 0
  function replayIntro() { root.introTick++ }
  function holdIntro() { root.holdTick++ }

  // ── ordering ─────────────────────────────────────────────────────────
  // Newest first by default: a wallpaper you just dropped in is the one you
  // are most likely opening the picker to find. Held here rather than in the
  // popup so the choice survives closing and reopening it.
  readonly property var sortModes: ["recent", "name", "size"]
  property int sortIndex: 0
  readonly property string sortMode: root.sortModes[root.sortIndex]

  function cycleSort() {
    root.sortIndex = (root.sortIndex + 1) % root.sortModes.length;
  }

  function wallpaperFor(screenName) {
    const a = root.assignment;
    if (a[screenName]) return a[screenName];
    if (a[root.fallbackKey]) return a[root.fallbackKey];
    return "";
  }

  // one wallpaper everywhere: clears the per-monitor overrides too, otherwise
  // "set everywhere" would quietly leave an old override in place — and the
  // span, which is one more override by another name
  function setAll(path) {
    root.assignment = { [root.fallbackKey]: path };
    root.span = null;
    saveTimer.restart();
  }

  // A monitor given a picture of its own has left whatever span it was in,
  // and a span with a monitor missing is not the picture anyone chose — so
  // the span goes, and the others keep the image fitted to themselves.
  function setFor(screenName, path) {
    const next = Object.assign({}, root.assignment);
    next[screenName] = path;
    root.assignment = next;
    if (root.span && root.span.screens.indexOf(screenName) >= 0) root.span = null;
    saveTimer.restart();
  }

  // ── SPANNING ─────────────────────────────────────────────────────────
  // One picture laid across several monitors as though they were one: each
  // shows the slice of it that falls where the monitor actually sits. The
  // monitors still get the path in the ordinary assignment, so everything
  // that only asks "what is on this screen" keeps working; the span is the
  // extra fact that it is a slice.
  property var span: null

  function setSpan(path, screens) {
    const names = (screens || []).slice();
    if (names.length < 2) { if (names.length === 1) root.setFor(names[0], path); return; }
    const next = Object.assign({}, root.assignment);
    for (const n of names) next[n] = path;
    root.assignment = next;
    root.span = { path: path, screens: names };
    saveTimer.restart();
  }

  // The desk this monitor is a slice of, in global coordinates — or null
  // when it is not spanned, or when fewer than two of the span's monitors
  // are connected (a span of one is just the monitor).
  function spanRectFor(screenName) {
    const sp = root.span;
    if (!sp || sp.screens.indexOf(screenName) < 0) return null;
    if (root.wallpaperFor(screenName) !== sp.path) return null;
    const rects = [];
    const all = Quickshell.screens;
    for (let i = 0; i < all.length; ++i)
      if (sp.screens.indexOf(all[i].name) >= 0)
        rects.push({ x: all[i].x, y: all[i].y, w: all[i].width, h: all[i].height });
    return rects.length >= 2 ? Art.boundsOf(rects) : null;
  }

  // ── THE LOOK ─────────────────────────────────────────────────────────
  // Everything past the picture and its fit — turned, mirrored, which part a
  // crop keeps, what fills the space around it, dimmed, blurred, greyed,
  // tinted. Per monitor, like the fit, and stored as only what differs from
  // the defaults (see picasso.js lookDefaults).
  property var looks: ({})

  function lookFor(screenName) {
    return Art.lookOf(root.looks[screenName]);
  }

  function setLookFor(screenName, patch) {
    const next = Object.assign({}, root.looks);
    const merged = Art.lookDiff(Object.assign(Art.lookOf(next[screenName]), patch));
    if (Object.keys(merged).length === 0) delete next[screenName];
    else next[screenName] = merged;
    root.looks = next;
    saveTimer.restart();
  }

  function thumbFor(path) {
    const f = root.files;
    for (let i = 0; i < f.length; ++i) if (f[i].path === path) return f[i].thumb;
    return "";
  }

  // ── the picture's own colour ─────────────────────────────────────────
  // For the backdrop and the tint that follow the image. The average of the
  // whole picture, read off its thumbnail — a 480px file answers in a few
  // milliseconds where the original would take half a second.
  property var accents: ({})
  // Mutated in place, never reassigned: accentFor is called from bindings,
  // and a binding that wrote a property it had just read would be a loop.
  // Nothing needs to hear about the queue changing, only about `accents`.
  readonly property var accentQueue: []
  readonly property var accentAsked: ({})

  // "#rrggbb", or "" while it is being worked out
  function accentFor(path) {
    if (!path || Art.isColor(path)) return Art.colorOf(path);
    const a = root.accents[path];
    if (a !== undefined) return a || "";
    if (!root.accentAsked[path]) {
      root.accentAsked[path] = true;
      root.accentQueue.push(path);
      Qt.callLater(root.runAccents);
    }
    return "";
  }

  function runAccents() {
    if (accentProc.running || root.accentQueue.length === 0) return;
    const args = [];
    for (const p of root.accentQueue.splice(0)) {
      const t = root.thumbFor(p);
      args.push(p, t !== "" ? t : p);
    }
    accentProc.command = ["sh", "-c",
      'while [ $# -gt 1 ]; do printf \'%s\\t%s\\n\' "$1" "$(magick "$2[0]" -resize 1x1\\! -format \'%[hex:u.p{0,0}]\' info: 2>/dev/null)"; shift 2; done',
      "sh"].concat(args);
    accentProc.running = true;
  }

  Process {
    id: accentProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        const next = Object.assign({}, root.accents);
        for (const line of String(text || "").split("\n")) {
          const tab = line.indexOf("\t");
          if (tab < 0) continue;
          // null, not "", for a file that has no answer, so it is not asked again
          next[line.slice(0, tab)] = Art.normHex(line.slice(tab + 1).slice(0, 6)) || null;
        }
        root.accents = next;
      }
    }
    onRunningChanged: if (!running) Qt.callLater(root.runAccents)
  }

  // ── SAVED COLOURS ────────────────────────────────────────────────────
  // The ones made in the picker's colour tab, after the presets.
  property var colors: []

  function addColor(hex) {
    const h = Art.normHex(hex);
    if (h === "" || root.colors.indexOf(h) >= 0) return;
    root.colors = root.colors.concat([h]);
    saveTimer.restart();
  }

  function removeColor(hex) {
    root.colors = root.colors.filter((c) => c !== hex);
    saveTimer.restart();
  }

  // ── THE SLIDESHOW ────────────────────────────────────────────────────
  // { minutes, shuffle, query, screens, span } or null. `query` is the
  // filter it draws from, "" for everything; `screens` the monitors it
  // changes, empty for all of them; `span` lays each picture across them.
  // It survives a restart, and starts counting again from the restart.
  property var slideshow: null

  function startSlideshow(cfg) {
    root.slideshow = {
      minutes: Math.max(1, cfg.minutes || 15),
      shuffle: !!cfg.shuffle,
      query: cfg.query || "",
      screens: (cfg.screens || []).slice(),
      span: !!cfg.span
    };
    slideTimer.restart();
    saveTimer.restart();
  }

  function stopSlideshow() {
    root.slideshow = null;
    saveTimer.restart();
  }

  function slidePool() {
    const ss = root.slideshow;
    if (!ss) return [];
    return Art.sortRows(Art.filter(root.files, ss.query, root.dir),
                        root.sortMode, root.dir).map((f) => f.path);
  }

  function nextSlide() {
    const ss = root.slideshow;
    if (!ss) return;
    const all = [];
    for (let i = 0; i < Quickshell.screens.length; ++i) all.push(Quickshell.screens[i].name);
    const names = ss.screens.length > 0 ? ss.screens.filter((n) => all.indexOf(n) >= 0) : all;
    if (names.length === 0) return;
    const next = Art.nextSlide(root.slidePool(), root.wallpaperFor(names[0]), ss.shuffle);
    if (next === "") return;
    if (ss.span && names.length > 1) root.setSpan(next, names);
    else if (names.length === all.length) root.setAll(next);
    else for (const n of names) root.setFor(n, next);
  }

  Timer {
    id: slideTimer
    interval: root.slideshow ? root.slideshow.minutes * 60000 : 60000
    repeat: true
    running: root.slideshow !== null
    onTriggered: root.nextSlide()
  }

  // ── scanning ─────────────────────────────────────────────────────────

  // Scan and thumbnail in one pass. It generates only what is missing, so the
  // cost is paid once per new wallpaper and never again — the picker used to
  // re-decode every full-size original on every filter keystroke.
  //
  // The cache key is path+mtime+size, which means replacing a wallpaper with a
  // different image of the same name produces a NEW cache filename. That is
  // what lets the picker turn Qt's image cache back on: a changed file is
  // never the same URL, so a decode failure can never be cached against it.
  function scan() {
    // one at a time, and a rescan asked for meanwhile — a file dropped into
    // the folder, the popup opened — runs when this one ends rather than
    // being a no-op restart that left the new file out until the next open
    if (scanProc.running) { scanProc.again = true; return; }
    root.scanning = true;
    const exts = root.extensions.join("\\|");
    const dirQ = Strings.shellQuote(root.dir);
    // The KEY AND THE SIZE ARE NOT PICASSO'S ANY MORE. Both come from
    // morpheus/thumbs.js, so a wallpaper terminus has already thumbnailed is
    // found here under the name terminus' generator gave it, and vice versa.
    // find only has to produce the path now: the shared expression stats the
    // file itself, which is also what guarantees both sides hash exactly the
    // same bytes rather than two spellings of the same mtime.
    scanProc.command = ["sh", "-c",
      'mkdir -p ' + Strings.shellQuote(Thumbs.dir()) + '; ' +
      // Recursive: wallpapers arrive in per-pack subdirectories, and a
      // depth limit silently hid most of them. Dot-directories are pruned so
      // a stray .thumbnails or version-control dir is not treated as art.
      'find ' + dirQ + " -type f -not -path '*/.*' -iregex '.*\\.\\(" + exts + "\\)$' " +
      "-print 2>/dev/null | sort | " +
      'while IFS= read -r p; do ' +
      '  set -- "$p"; ' +
      Thumbs.keyExpr() +
      // Touched when it already exists — see the note in Thumbs.generate
      // on why an untouched thumbnail is one the sweep deletes.
      '  if [ -s "$out" ]; then touch -c "$out"; else magick "$1"[0] -auto-orient -thumbnail '
        + Thumbs.size() + 'x' + Thumbs.size() + ' -strip "$out" 2>/dev/null; fi; ' +
      // path, thumb, mtime, size — the last two so the picker can order by
      // them without going back to the disk on every sort change
      '  if [ -s "$out" ]; then printf \'%s\\t%s\\t%s\\t%s\\n\' "$1" "$out" "$mt" "$sz"; ' +
      '  else printf \'%s\\t\\t%s\\t%s\\n\' "$1" "$mt" "$sz"; fi; ' +
      'done; ' +
      // The pool is shared, so "delete anything no wallpaper claims" would
      // delete every thumbnail terminus made. Age is the only question either
      // side can answer about the other's entries.
      Thumbs.sweep(30)];
    scanProc.running = true;
  }

  Process {
    id: scanProc
    property bool again: false
    onExited: if (scanProc.again) { scanProc.again = false; Qt.callLater(root.scan); }
    stdout: StdioCollector {
      waitForEnd: true
      // `text` is StdioCollector's own property, not a signal parameter.
      // Declaring it as one shadowed the property with undefined, and the
      // scan quietly returned nothing at all.
      onStreamFinished: {
        root.files = Art.parseRows(text);
        root.scanning = false;
      }
    }
  }

  // The top of the tree is watched, so dropping a new image or a new pack in
  // pre-generates its thumbnail before the picker is ever opened. Only the top:
  // a watch per subdirectory would be a lot of machinery for a head start, and
  // the picker rescans on open regardless, so nothing is ever missed — a file
  // added deep in the tree just pays its 0.2s thumbnail on first open.
  FileView {
    id: dirWatch
    path: root.dir
    watchChanges: true
    printErrors: false
    onFileChanged: rescanDebounce.restart()
  }

  Timer {
    id: rescanDebounce
    // copying a batch of files in fires this repeatedly; scan once at the end
    interval: 500
    onTriggered: root.scan()
  }

  // ── persistence ──────────────────────────────────────────────────────

  FileView {
    id: stateFile
    path: Quickshell.statePath("picasso.json")
    blockLoading: true
    printErrors: false
  }

  Timer {
    id: saveTimer
    interval: 250
    onTriggered: stateFile.setText(Art.serializeState({
      assignment: root.assignment, fits: root.fits, looks: root.looks,
      span: root.span, colors: root.colors, slideshow: root.slideshow
    }))
  }

  // Pointed somewhere else, the list on screen is about a directory that is no
  // longer the one in use. dirWatch follows the new path on its own — it is
  // bound to this — but a watch only reports CHANGES to a directory, and
  // arriving at one is not a change to it, so the first scan has to be asked
  // for. Through the same debounce a file drop uses, so a path that lands in
  // two writes is still one scan.
  onDirChanged: rescanDebounce.restart()

  Component.onCompleted: {
    // parseState reads the old bare-map file as well as the current one, so
    // an install that predates per-monitor fit loads with its wallpapers
    // intact and no fits set — which is exactly what it had.
    const st = Art.parseState(stateFile.text());
    root.assignment = st.assignment;
    root.fits = st.fits;
    root.looks = st.looks;
    root.span = st.span;
    root.colors = st.colors;
    root.slideshow = st.slideshow;
    root.scan();
  }
}
