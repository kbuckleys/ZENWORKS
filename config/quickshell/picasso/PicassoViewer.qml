// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE VIEWER — the part of it that is always in the shell, which is almost
// nothing: two signals answered and an empty list.
//
// NOT BUILT AT STARTUP, for the rule plato set: an application nobody has
// opened costs nothing. The window type is compiled asynchronously on the
// first Picasso.view (or annotate), and let go of again when the last window
// closes — see ViewerWindow.qml for everything a window does.
//
// ONE VIEWER WINDOW, REUSED. Clicking through pictures in terminus opens each in
// the window already up rather than stacking a new one per click — unless
// that window is in the middle of something (marks or an edit nobody has
// saved), which is never thrown away to make room: then a second one opens.
//
// Reached through:
//   Picasso.view(paths)        paths separated by newlines — bin/picasso-view,
//                              its .desktop entry, `qs ipc call Picasso view`
//   Picasso.annotate(path)     the screenshot toast, terminus and folio: a
//                              window of its own, straight into annotation

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "../morpheus"
import "../morpheus/lagnotes.js" as LagNotes
import "viewer.js" as V

Scope {
  id: mgr

  // terminus, handed in by shell.qml, for Save New's dialog and "show in
  // directory"
  property var fileManager: null

  // ── ITS .desktop ENTRY ─────────────────────────────────────────────
  // Not shipped as a file: written into ~/.local/share/applications on
  // startup when it is missing, with this machine's path to bin/picasso-view (see
  // Desktop.installCommand). That is what file managers, artemis and
  // `gio mime` find it by. One already there is left alone.
  Process {
    running: true
    command: ["sh", "-c", Desktop.installCommand("picasso-view", {
      Type: "Application",
      Name: "Picasso",
      GenericName: "Image Viewer",
      Comment: "View, edit and annotate pictures, in ZENWORKS",
      Icon: "image-viewer",
      Categories: ["Graphics", "Viewer", "Photography"],
      Keywords: ["image", "viewer", "picture", "photo", "gallery", "annotate"],
      Exec: Desktop.execLine(Quickshell.shellDir + "/picasso/bin/picasso-view", "%F"),
      Terminal: "false",
      StartupNotify: "false",
      MimeType: [
        "image/png", "image/jpeg", "image/jpg", "image/gif", "image/webp",
        "image/bmp", "image/tiff", "image/tif", "image/svg+xml", "image/avif",
        "image/heif", "image/heic", "image/jxl", "image/x-exr",
        "image/x-portable-pixmap", "image/x-tga", "image/x-qoi",
        "image/x-portable-anymap", "image/x-dicom", "image/x-canon-cr2",
        "image/x-nikon-nef", "image/x-adobe-dng", "image/x-sony-arw",
        "image/x-fuji-raf", "image/vnd.adobe.photoshop", "image/x-xcf",
        "image/x-icon", "image/x-ico", "image/qoi"
      ],
    })]
  }

  // ── THE ORDER, AND THE SLIDESHOW'S PACE ────────────────────────────
  // One for every window and every mode — the gallery, the picture and its
  // strip are the same directory in the same order — and kept across restarts:
  // "Newest" chosen once stays chosen, and so do a slideshow's seconds and
  // its shuffle. A window reads them and writes them back through setSort
  // and setSlides.
  property string sortKey: "name"
  property int slideSecs: 4
  property bool shuffle: false
  // the strip of the directory under a picture — up and down, or its handle
  property bool stripShown: true
  // the gallery's tile size, as terminus' grid zoom (0.7–2.4) — one for
  // every window, kept across restarts
  property real galleryZoom: 1.0
  // runs of pictures taken moments apart, folded into one tile in the gallery
  property bool groupBursts: false
  // tags and the star written to an .xmp beside each picture too, for
  // darktable, digiKam, Lightroom — see tags.js' sidecars
  property bool xmpSidecars: false
  // the directories last looked at, newest first — the Places menu
  property var recent: []
  FileView {
    id: stateFile
    path: Quickshell.statePath("picasso-view.json")
    blockLoading: true
    printErrors: false
  }
  Component.onCompleted: {
    mgr.loadHashes_();
    try {
      const st = JSON.parse(stateFile.text() || "{}");
      if (["name", "time", "size", "taken"].indexOf(st.sort) >= 0) mgr.sortKey = st.sort;
      if (V.SLIDE_SECS.indexOf(st.slideSecs) >= 0) mgr.slideSecs = st.slideSecs;
      mgr.shuffle = st.shuffle === true;
      mgr.stripShown = st.strip !== false;
      if (typeof st.galleryZoom === "number" && st.galleryZoom >= 0.7 && st.galleryZoom <= 2.4) mgr.galleryZoom = st.galleryZoom;
      mgr.groupBursts = st.bursts === true;
      mgr.xmpSidecars = st.xmp === true;
      if (Array.isArray(st.recent)) mgr.recent = st.recent.filter((d) => typeof d === "string").slice(0, 10);
    } catch (e) {}
  }
  function keep_() {
    stateFile.setText(JSON.stringify({ sort: mgr.sortKey, slideSecs: mgr.slideSecs, shuffle: mgr.shuffle,
                                     strip: mgr.stripShown, bursts: mgr.groupBursts, xmp: mgr.xmpSidecars,
                                     galleryZoom: mgr.galleryZoom,
                                     recent: mgr.recent }));
  }
  function setSort(key) {
    if (mgr.sortKey === key) return;
    mgr.sortKey = key;
    mgr.keep_();
  }
  function setSlides(secs, shuffle) {
    if (V.SLIDE_SECS.indexOf(secs) >= 0) mgr.slideSecs = secs;
    mgr.shuffle = !!shuffle;
    mgr.keep_();
  }

  function setBursts(on) { mgr.groupBursts = !!on; mgr.keep_(); }
  function setXmp(on) { mgr.xmpSidecars = !!on; mgr.keep_(); }
  function noteRecent(dir) {
    const next = V.noteRecent(mgr.recent, dir, 10);
    if (next.join("\n") === mgr.recent.join("\n")) return;
    mgr.recent = next;
    mgr.keep_();
  }

  // ── WHAT EVERY WINDOW CAN REUSE ────────────────────────────────────
  // When and where each picture was taken (exiftool), and how each one
  // looks in 64 bits (the alike search) — by path, with the size and time
  // the answer was for, so a picture written since is asked again. Held for
  // the session; the hashes are kept on disk too, being slow to make.
  property var meta: ({})
  property var hashes: ({})
  function sigOf(r) { return (r.size || 0) + ":" + (r.mtime || 0); }
  function noteMeta(got, rows) {
    const next = Object.assign({}, mgr.meta);
    for (const r of rows) next[r.path] = Object.assign({ sig: mgr.sigOf(r) }, got[r.path] || { t: null, lat: null, lon: null });
    mgr.meta = next;
  }
  function noteHashes(got, rows) {
    const next = Object.assign({}, mgr.hashes);
    for (const r of rows) if (got[r.path]) next[r.path] = Object.assign({ sig: mgr.sigOf(r) }, got[r.path]);
    mgr.hashes = next;
    hashFile.setText(JSON.stringify(mgr.hashes));
  }
  FileView {
    id: hashFile
    path: Paths.cacheDir() + "/picasso/alike.json"
    blockLoading: true
    printErrors: false
  }
  function loadHashes_() {
    try { mgr.hashes = JSON.parse(hashFile.text() || "{}") || {}; } catch (e) { mgr.hashes = ({}); }
  }

  // Which of the optional tools this machine has (viewer.js EXTRA_TOOLS):
  // their menu rows are offered only when they are.
  property var tools: ({})
  Process {
    running: true
    command: ["sh", "-c", V.toolsCommand()]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: mgr.tools = V.parseTools(text) }
  }
  // The copies made before a file is written over (see the viewer's undo),
  // a day after they were made, are gone.
  Process {
    running: true
    command: ["sh", "-c", 'find "$1" -type f -mmin +1440 -delete 2>/dev/null; exit 0', "sh", Paths.cacheDir() + "/picasso/undo"]
  }

  // Written once a burst of zoom steps has settled, not per step.
  function setGalleryZoom(z) {
    if (Math.abs(mgr.galleryZoom - z) < 0.001) return;
    mgr.galleryZoom = z;
    zoomKeep.restart();
  }
  Timer { id: zoomKeep; interval: 600; onTriggered: mgr.keep_() }

  function setStrip(on) {
    if (mgr.stripShown === !!on) return;
    mgr.stripShown = !!on;
    mgr.keep_();
  }

  property var wins: []
  property var _comp: null
  property var _waiting: []

  Connections {
    target: Picasso
    function onViewRequested(paths) { mgr.open(paths, "view"); }
    function onAnnotateRequested(path) { mgr.open(path, "annotate"); }
  }

  // Run `fn` once the window type is compiled, compiling it if this is the
  // first window since the viewer was last closed.
  function _withComponent(fn) {
    if (mgr._comp && mgr._comp.status === Component.Ready) { fn(); return; }
    mgr._waiting.push(fn);
    if (mgr._comp) return;
    const comp = Qt.createComponent(Qt.resolvedUrl("ViewerWindow.qml"), Component.Asynchronous);
    mgr._comp = comp;
    const settle = () => {
      if (comp.status === Component.Loading) return;
      const queued = mgr._waiting;
      mgr._waiting = [];
      if (comp.status !== Component.Ready) {
        console.warn("picasso viewer:", comp.errorString());
        mgr._comp = null;
        return;
      }
      for (const f of queued) f();
    };
    if (comp.status === Component.Loading) comp.statusChanged.connect(settle);
    else settle();
  }

  function open(paths, mode) {
    // Opened on its own — from the launcher, with nothing handed over — it
    // opens on the pictures directory XDG names, as a gallery of it.
    let list = V.parsePaths(paths);
    if (list.length === 0) {
      if (mode === "annotate" || Picasso.picturesDir === "") return;
      list = [Picasso.picturesDir];
    }
    // An annotation asked for from outside — the toast, terminus, folio — is
    // a window of its own, the picture and nothing else, gone when the marks
    // are done. It never takes over a viewer somebody is already looking
    // through, and a viewer request never lands in one of these.
    if (mode === "annotate") { mgr.spawn(list.slice(0, 1), mode, true); return; }
    const views = mgr.wins.filter((w) => !w.solo);
    const last = views.length > 0 ? views[views.length - 1] : null;
    if (last && !last.busy) {
      last.load(list, mode);
      Hyprland.dispatch('hl.dsp.focus({ window = "title:^(picasso-view)$" })');
      return;
    }
    mgr.spawn(list, mode, false);
  }

  function spawn(list, mode, solo) {
    mgr._withComponent(() => {
      const t0 = Date.now();
      const w = mgr._comp.createObject(mgr, { mgr: mgr, fileManager: mgr.fileManager, solo: solo });
      if (!w) return;
      LagNotes.mark("picasso window", t0);
      mgr.wins = mgr.wins.concat([w]);
      const t1 = Date.now();
      w.load(list, mode);
      w.visible = true;
      LagNotes.mark("picasso load+show", t1);
    });
  }

  // A window that has closed. The last one takes the compiled type with it.
  function retire(w) {
    mgr.wins = mgr.wins.filter((x) => x !== w);
    if (mgr.wins.length === 0 && mgr._waiting.length === 0) mgr._comp = null;
  }
}
