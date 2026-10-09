// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE VIEWER'S WINDOW. One picture large, the rest of its directory in a strip
// underneath; or the whole directory as a gallery. Three modes:
//
//   view       the picture, zoomed and panned; the strip; the edit panel
//   gallery    every picture in the directory as a grid
//   annotate   Annotator, over the whole window — marks drawn on the picture
//
// NOTHING OF ITS OWN WHERE PICASSO ALREADY HAS IT. The edit is a picasso.js
// look shown through Scene — the same object and the same painter a
// background wears, set with the same LookEditor — plus a turn, a mirror and
// a crop. Saving grabs a Scene at the picture's own size, so the file is
// what the preview showed. "Set as background" is the picker's own card,
// opened on this picture with the edit staged. The directory listing, the image
// test, the sort, the trash and the formatting are terminus.js'; the
// thumbnails are morpheus/thumbs.js' shared pool.
//
// The wheel zooms, towards the pointer — except over the strip, where it
// scrolls the strip.
//
//   ← → h l  space   previous, next      home end   first, last
//     (zoomed in, ← → h l pan instead — space still steps)
//   backspace   back to the gallery
//   ↑ ↓ k j pan    alt+j puts the strip under the picture away, alt+k
//     brings it back (its handle too)
//   + - 0 1 2   zoom in, out, fit, actual size, double     a double click too
//   return   actual size, or back to the fit when it is there
//   z lock the zoom — the next picture opens at the same size and place
//   g gallery   e edit   c crop   C trim black borders   r R turn   m mirror   a annotate
//   \ held: the picture without its edit
//   v compare — beside the next picture, or the two marked; shift+← →
//     walks the other half, tab swaps them
//   x mark   * star   t tags   F2 rename   / or ctrl+f filter (words, #tag, ★,
//     is:video is:picture is:marked is:directory — the gallery's directories too)
//   alt+return   properties — terminus' card (PropsCard.qml)
//   p  , .  pause an animation, step its frames   [ ] slideshow slower, faster
//   right click: the picture's menu, or the selection's — copy, save, crop,
//   convert (terminus' targets), background, zoom to it, read its text
//   w set as background   s slideshow (right click it: pace, shuffle)
//   esc unwinds, one thing at a time — and on a picture with nothing left
//     to unwind goes back to its gallery; in the gallery it closes
//   i info   b hide the bars
//   f fullscreen — the picture alone on black, no bars; f or esc back
//   ctrl held: the loupe — the part under the pointer, closer (ctrl+wheel)
//   W the monitors' outlines — what each would show of it as a background
//   ' places — the pictures directories, terminus' bookmarks, the ones of late
//   a video plays: p pauses, , . five seconds back and on, m mutes
//   o show in terminus   d (or delete) to the trash, u brings it back
//   D (or shift+delete) deletes for good — it asks first, and there is no undo
//   ctrl+c copy   ctrl+shift+c path   ctrl+v look at what the clipboard holds
//   ctrl+s save the edit   ctrl+shift+s save it as new   esc back out (never closes — q does)
//   y copies the colour under the pointer — zoomed past 400%, where each of
//     the picture's pixels is drawn sharp, and past 1200% gridded
//
// The gallery's tiles zoom as terminus' grid does: ctrl+wheel, + - 0 (ctrl
// too), or the meter in the bar (terminus' ZoomMeter), which reads the
// picture's zoom on a picture.
//
// The gallery: space or x marks (ctrl+click, shift+click, ctrl+a too, or a
// box dragged out from anywhere off the thumbnails, as terminus' is) and
// right click is the picture's menu — or the marked pictures', or the
// directory's. Delete, F2, t, * and ctrl+c act on the marked pictures when
// there are any. Pictures drag out of the gallery, and up out of the strip,
// as files.
//
// The directory is watched (terminus' watch): a picture landing in it, renamed
// or deleted elsewhere, is in the listing without asking.
//
// The gallery can be in the order the pictures were TAKEN (the camera's
// date, exiftool's), in sections by day or month with a scrubber down its
// side; bursts can fold into their first; and Find alike pictures shows only
// the near-duplicates, group by group, the best of each named. M is the map
// of where they were taken (MapView.qml, OpenStreetMap's tiles). u undoes
// the trash and anything written over in place — a save, a turn, marks.

import QtQuick
import QtQuick.Window
import QtQuick.Effects
import QtMultimedia
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Widgets
import "../morpheus"
import "../terminus"
import "../oracle"
import "../morpheus/thumbs.js" as Thumbs
import "../terminus/terminus.js" as Terminus
import "../terminus/tags.js" as Tags
import "../morpheus/icons.js" as Icons
import "capture.js" as Cap
import "picasso.js" as Art
import "viewer.js" as V

FloatingWindow {
  id: win
  title: "picasso-view"
  color: win.full ? "#000000" : Zenon.layerBg
  implicitWidth: 1400
  implicitHeight: 900
  minimumSize: Qt.size(640, 420)

  property var mgr: null
  property var fileManager: null
  // An annotation window on its own — opened from a screenshot's toast or a
  // file manager's Annotate: the one picture, no directory, and closed when the
  // marks are done. See PicassoViewer.open.
  property bool solo: false

  // A closed window is done with, not hidden: each is its own, and a full
  // resolution photo is a lot to keep for nobody.
  onVisibleChanged: if (!win.visible) Qt.callLater(() => { if (win.mgr) win.mgr.retire(win); win.destroy(); })
  // Closed by the compositor — super+q — is reported as `closed` with
  // `visible` still true; see the same note in ceres/CeresWindow.qml.
  onClosed: win.visible = false

  // ── what is shown ──────────────────────────────────────────────────────
  // Rows are terminus.js listing rows: { name, path, size, mtime, … }.
  // `allRows` is the directory; `rows` is what the filter leaves of it — and
  // everything else (stepping, the strip, the gallery) is about `rows`.
  property var allRows: []
  property var rows: []
  property int index: -1
  // The directories beside the pictures, for the gallery — led by the way up.
  // ~/Pictures on its own holds nothing BUT directories (Screenshots,
  // Backgrounds), and a gallery that could not go into them would open on
  // an empty page. Not in a gallery of picked files: those have no directory.
  property var directories: []
  // Laid out for the grid (viewer.js galleryLayout): a section — a date, a
  // burst, a group of alike pictures — starts a fresh line, padded to it
  // with empty cells, its heading a chip on its first picture. A folded
  // burst shows only its first.
  readonly property int gcols: Math.max(1, Math.round(grid.width / (190 * win.gzoom)))

  // ── the gallery's zoom — terminus' grid zoom ──────────────────────────
  // The same number terminus' thumbZoom is, on the same scale: a cell is
  // about 190 × 168 at 1, 0.7 to 2.4 in steps of 0.1, eased so a burst of
  // steps is one change of size. ctrl+wheel, + - 0 (ctrl too) and the meter
  // in the bar move it; it is the manager's, so every window and the next
  // session share it.
  readonly property real gzoomMin: 0.7
  readonly property real gzoomMax: 2.4
  property real gzoom: win.mgr ? win.mgr.galleryZoom : 1.0
  Behavior on gzoom { NumberAnimation { duration: Zenon.normal; easing.type: Easing.OutCubic } }
  function gzoomSet(z) {
    const v = Math.round(Math.max(win.gzoomMin, Math.min(win.gzoomMax, z)) * 100) / 100;
    if (win.mgr) win.mgr.setGalleryZoom(v);
    // the cursor's tile is kept in sight while the cells resize under it
    gzoomFollow.restart();
  }
  function gzoomBy(d) { win.gzoomSet((win.mgr ? win.mgr.galleryZoom : win.gzoom) + d); }
  Timer { id: gzoomFollow; interval: Zenon.normal + 60 }
  onGzoomChanged: if (gzoomFollow.running && win.mode === "gallery") grid.positionViewAtIndex(win.gidx, GridView.Contain)
  readonly property var layout: V.galleryLayout(win.shownDirectories, win.rows, win.gcols, win.sectionAt, win.hiddenRows)
  readonly property var galleryItems: win.layout.items
  readonly property var rowIndex: {
    const o = {};
    for (let i = 0; i < win.rows.length; ++i) o[win.rows[i].path] = i;
    return o;
  }
  // The gallery's cell for a picture — a folded burst's member is on its
  // first — or -1.
  function itemOfPath(p) {
    const at = win.layout.at[p];
    if (at !== undefined) return at;
    const ri = win.rowIndex[p];
    if (ri === undefined) return -1;
    for (const b of win.burstList) if (ri > b.start && ri < b.start + b.n) {
      const first = win.layout.at[win.rows[b.start].path];
      return first === undefined ? -1 : first;
    }
    return -1;
  }
  function rowOfItem(gi) {
    const it = win.galleryItems[gi];
    if (!it || it.isDir || it.isFill) return -1;
    const ri = win.rowIndex[it.path];
    return ri === undefined ? -1 : ri;
  }
  onLayoutChanged: {
    notePos.restart();   // where each tile now is — see tilePos
    const it = win.galleryItems[win.gidx];
    if (it && it.isDir) return;
    const at = win.itemOfPath(win.path);
    if (at >= 0 && at !== win.gidx) win.gidx = at;
  }
  // the gallery's cursor, over directories and pictures both; on a picture it
  // is the picture shown
  property int gidx: 0
  property string dir: ""
  // the paths asked for, when there were several — a gallery of just those
  property var picked: []
  readonly property var row: win.index >= 0 && win.index < win.rows.length ? win.rows[win.index] : null
  // Set with the index, by go() — not bound to it. New rows (a refresh, the
  // filter) can move the picture to another index, and a binding would show
  // whatever passed through that index for a moment on the way.
  property string path: ""

  property string mode: "view"
  property bool chrome: true
  property bool infoShown: false
  property bool panelShown: false
  property bool playing: false
  // the slideshow's pace and order, the manager's like the sort
  readonly property int slideSecs: win.mgr ? win.mgr.slideSecs : 4
  readonly property bool shuffle: win.mgr ? win.mgr.shuffle : false
  // the strip under the picture — the manager's, kept like the sort
  readonly property bool stripShown: win.mgr ? win.mgr.stripShown : true
  function toggleStrip() { if (win.mgr) win.mgr.setStrip(!win.stripShown); }
  onStripShownChanged: Qt.callLater(() => win.refit(true))
  // the next picture opens at the zoom and place this one is at
  property bool zoomLock: false
  // \ held: the picture without its look
  property bool peekOriginal: false
  // an animation stopped on a frame
  property bool gifPaused: false
  // the manager's, shared by every window and kept — see PicassoViewer
  readonly property string sortKey: win.mgr ? win.mgr.sortKey : "name"
  onSortKeyChanged: win.resort()
  // the file a solo annotation was last saved to — where Back lands
  property string soloFile: ""

  // ── the edit ───────────────────────────────────────────────────────────
  // Only the keys that were touched, over the defaults: a look, exactly as a
  // monitor stores one. The crop is in the SAVED picture's pixels.
  property var stageLook: ({})
  readonly property var look: Art.lookOf(win.stageLook)
  property var crop: null
  property bool cropping: false
  // a crop set up on purpose — the edit panel's ratios, the crop tool —
  // rather than a box merely dragged out on the picture; see `precious`
  property bool cropStaged: false
  property string cropRatio: "free"
  // a fine turn, in degrees, the picture grown to cover — see straightenScale
  property real straighten: 0
  property bool straightening: false
  Timer { id: straightenSeen; interval: 1400; onTriggered: win.straightening = false }
  // the crop's ratios, and one more per monitor when they differ
  readonly property var screenList: Quickshell.screens.map((sc) => ({ name: sc.name, width: sc.width, height: sc.height }))
  readonly property var cropRatios: V.CROP_RATIOS.concat(V.screenRatios(win.screenList))
  property string editingColor: ""
  property string customTint: "#7a8cff"
  readonly property bool edited: Object.keys(Art.lookDiff(win.look)).length > 0 || win.crop !== null || win.straighten !== 0

  // Worth asking about before it is dropped: a look, or a crop set up in the
  // edit panel. A box merely dragged out on the picture is a selection — it
  // goes with the picture, unasked, the way a selection does anywhere.
  readonly property bool precious: Object.keys(Art.lookDiff(win.look)).length > 0
    || (win.crop !== null && win.cropStaged) || win.straighten !== 0

  // In the middle of something that must not be thrown away — the manager
  // opens a second window rather than reuse this one.
  readonly property bool busy: win.precious
    || (win.mode === "annotate" && annLoader.item && annLoader.item.dirty)

  function setLook(key, value) {
    const next = Object.assign({}, win.stageLook);
    next[key] = value;
    win.stageLook = next;
    // a turn moves every side of the picture, and a crop drawn against the
    // old sides would land somewhere nobody chose
    if (key === "rotate" && win.crop) win.crop = null;
  }
  function resetEdit() {
    win.stageLook = ({});
    win.crop = null;
    win.cropping = false;
    win.cropStaged = false;
    win.straighten = 0;
    win.editingColor = "";
  }
  function turn(d) { if (!win.stillOnly()) return; win.setLook("rotate", (win.look.rotate + d + 360) % 360); win.fitted = true; win.refit(true); }

  // ── the picture's own size, and turned ────────────────────────────────
  readonly property var img: imgLoader.item
  // A video is looked at here — played, zoomed, stepped past — never edited.
  readonly property bool isVid: Terminus.isVideo(Terminus.basename(win.path))
  readonly property var vid: vidLoader.item
  property bool muted: false
  readonly property real nw: win.isVid ? (win.vid ? win.vid.vw : 0) : (win.img ? win.img.implicitWidth : 0)
  readonly property real nh: win.isVid ? (win.vid ? win.vid.vh : 0) : (win.img ? win.img.implicitHeight : 0)
  readonly property var turned: V.turnedSize(win.nw, win.nh, win.look.rotate)
  readonly property real tw: win.turned.w
  readonly property real th: win.turned.h
  readonly property bool loaded: win.isVid ? (win.vid !== null && win.nw > 0)
    : (win.img !== null && win.img.status === Image.Ready && win.nw > 0)
  // Says so and answers false for a video: what is asked of it is for pictures.
  function stillOnly() {
    if (!win.isVid) return true;
    win.say("a video is only looked at here");
    return false;
  }

  // When Qt cannot decode it, thumbs.js renders a 1600px copy through
  // ImageMagick and that is shown instead — looked at, not edited: saving
  // an edit of the copy would save a smaller picture than the one opened.
  property string fallback: ""
  property int reloadTick: 0
  readonly property string stageUrl: win.path === "" ? ""
    : (win.fallback !== "" ? "file://" + win.fallback : win.urlOf(win.path))
  // Every picture by the same url — the stage, the read-ahead and the
  // compare ask for one picture the same way, so Qt's cache answers all three.
  // Always with the query, even at 0: a strip tile shows a small picture by
  // its plain url (no thumbnail is made of one), and sharing its texture
  // with the stage's — mipmapped, the tile's not — is a fight over filtering.
  function urlOf(p) { return Strings.fileUrl(p) + "?" + win.reloadTick; }
  // A picture pasted from the clipboard lives in the runtime directory until
  // somebody saves it — Save New works on it unedited.
  readonly property bool scratch: win.path.indexOf(Paths.runtimeDir() + "/picasso-view/") === 0
  readonly property bool animated: /\.(gif|webp|apng|mng)$/i.test(win.path)
  readonly property bool vector: /\.svgz?$/i.test(win.path)

  // ── zoom and pan ──────────────────────────────────────────────────────
  // The view is { z, x, y } kept as three numbers so each can glide; see
  // viewer.js for the arithmetic. `fitted` follows the window: resized, the
  // picture is fitted again rather than left where the old size put it.
  property real vz: 1
  property real vx: 0
  property real vy: 0
  property bool fitted: true
  property int glide: 0
  readonly property real margin: win.chrome ? 16 : 0

  function setView(v, ms) {
    win.glide = ms || 0;
    win.vz = v.z; win.vx = v.x; win.vy = v.y;
  }
  function fitZ() {
    return V.fitScale(win.tw, win.th, stage.width - 2 * win.margin, stage.height - 2 * win.margin, 1);
  }
  function refit(anim) {
    if (!win.fitted || win.tw <= 0) return;
    const v = V.fitView(win.tw, win.th, stage.width - 2 * win.margin, stage.height - 2 * win.margin, 1);
    win.setView({ z: v.z, x: v.x + win.margin, y: v.y + win.margin }, anim ? Zenon.normal : 0);
  }
  function zoomTo(z, px, py, ms) {
    if (win.tw <= 0) return;
    win.sayZoom();
    const f = win.fitZ();
    // back down to the fit is back to fitted: it follows the window again
    if (z <= f * 1.001) { win.fitted = true; win.refit(ms > 0); return; }
    win.fitted = false;
    const cx = px === undefined ? stage.width / 2 : px, cy = py === undefined ? stage.height / 2 : py;
    win.setView(V.zoomAbout({ z: win.vz, x: win.vx, y: win.vy }, z, cx, cy,
                            win.tw, win.th, stage.width, stage.height), ms);
  }
  // a stop up (1) or down (-1) the zoom's stops, or back to the fit (0)
  function zoomStep(d) {
    if (d === 0) { win.fitted = true; win.refit(true); win.sayZoom(); return; }
    win.zoomTo(V.stepZoom(win.vz, d), undefined, undefined, Zenon.normal);
  }
  function panBy(dx, dy) {
    if (win.fitted) return;
    win.setView(V.clampView({ z: win.vz, x: win.vx + dx, y: win.vy + dy },
                            win.tw, win.th, stage.width, stage.height), 0);
  }

  // ── the keys' pan ─────────────────────────────────────────────────────
  // Held, an arrow (or h j k l) moves the picture on every frame from the
  // press — not a jump per key repeat, which waited out the repeat delay
  // first. It gathers speed while held and coasts to a stop let go of, so a
  // tap is still a short, smooth nudge.
  property var panHeld: ({})          // key → [dx, dy], the keys down now
  property real panVx: 0
  property real panVy: 0
  property real panFor: 0             // seconds the keys have been held
  function panKey(k, dx, dy, auto) {
    if (auto || k in win.panHeld) return;
    const h = Object.assign({}, win.panHeld); h[k] = [dx, dy];
    if (Object.keys(win.panHeld).length === 0) win.panFor = 0;
    win.panHeld = h;
    // moving from this frame: the first step is not left to the next tick
    const v = 900;
    if (dx !== 0 && Math.sign(win.panVx) !== dx) win.panVx = dx * v;
    if (dy !== 0 && Math.sign(win.panVy) !== dy) win.panVy = dy * v;
  }
  function panRelease(k) {
    if (!(k in win.panHeld)) return false;
    const h = Object.assign({}, win.panHeld); delete h[k];
    win.panHeld = h;
    return true;
  }
  function panStop() { win.panHeld = ({}); win.panVx = 0; win.panVy = 0; }
  // the keys' release never comes once the focus has gone (another window)
  Connections { target: keys; function onActiveFocusChanged() { if (!keys.activeFocus) win.panStop(); } }
  onFittedChanged: if (win.fitted) win.panStop()
  FrameAnimation {
    running: Object.keys(win.panHeld).length > 0 || win.panVx !== 0 || win.panVy !== 0
    onTriggered: {
      const dt = Math.min(frameTime, 0.05);
      let tx = 0, ty = 0;
      for (const k in win.panHeld) { tx += win.panHeld[k][0]; ty += win.panHeld[k][1]; }
      tx = Math.sign(tx); ty = Math.sign(ty);
      win.panFor += dt;
      // 900 px/s at once, up to 2400 over the first 0.6 s held
      const top = 900 + 1500 * Math.min(1, win.panFor / 0.6);
      // held: straight to speed; let go of: a quick ease to rest
      const ease = 1 - Math.exp(-dt / 0.07);
      win.panVx = tx !== 0 ? tx * top : win.panVx * (1 - ease);
      win.panVy = ty !== 0 ? ty * top : win.panVy * (1 - ease);
      if (Math.abs(win.panVx) < 20) win.panVx = 0;
      if (Math.abs(win.panVy) < 20) win.panVy = 0;
      if (win.fitted) { win.panStop(); return; }
      win.panBy(win.panVx * dt, win.panVy * dt);
    }
  }

  onTwChanged: { win.fitted = true; win.refit(false); }
  onThChanged: { win.fitted = true; win.refit(false); }
  onChromeChanged: Qt.callLater(() => win.refit(true))
  onPanelShownChanged: Qt.callLater(() => win.refit(true))

  // ── notes in the bar ──────────────────────────────────────────────────
  property string note: ""
  Timer { id: noteClear; interval: 3000; onTriggered: win.note = "" }
  function say(t, ms) { win.note = t; noteClear.interval = ms || 3000; noteClear.restart(); }

  // ── loading ───────────────────────────────────────────────────────────
  // One path: its directory, opened at it (or a directory, opened at its first
  // picture). Several: just those, in the order given.
  function load(list, mode) {
    win.leave(() => {
      win.forgetDirectory();
      win.picked = list.length > 1 || win.solo ? list.slice() : [];
      win.want = list[0];
      win.startMode = mode || "view";
      win.list();
    });
  }
  property string want: ""
  property string startMode: "view"
  property string compareAfter: ""
  property string cameFrom: ""

  // ── back and forward, as terminus has them ──────────────────────────
  // The top bar's back arrow, and mouse 4 / mouse 5. Back from a picture is
  // its gallery; back in a gallery is the directory you were in before — or,
  // with none, the one above. Forward retraces it, a picture included.
  // `history` holds directories left; `ahead` holds { dir } or { view: path }.
  property var history: []
  property var ahead: []
  readonly property string upDir: win.picked.length === 0 && win.dir !== "" && win.dir !== "/"
    ? Terminus.dirname(win.dir) : ""
  readonly property bool canBack: win.mode === "map"
    || (win.mode === "view" ? !win.solo && win.galleryItems.length > 0
        : win.mode === "gallery" && (win.history.length > 0 || win.upDir !== ""))
  function goUp() { if (win.upDir !== "") win.openDirectory(win.upDir); }
  function navBack() {
    if (win.mode === "map") { win.mode = win.mapFrom !== "" ? win.mapFrom : "gallery"; return; }
    if (win.mode === "view") {
      if (win.solo || win.galleryItems.length === 0) return;
      if (win.path !== "") win.ahead = win.ahead.concat([{ view: win.path }]);
      win.mode = "gallery";
      return;
    }
    if (win.mode !== "gallery") return;
    const h = win.history;
    const to = h.length > 0 ? h[h.length - 1] : win.upDir;
    if (to === "") return;
    if (h.length > 0) win.history = h.slice(0, -1);
    if (win.dir !== "") win.ahead = win.ahead.concat([{ dir: win.dir }]);
    win.openDirectory(to, true);
  }
  function navForward() {
    const a = win.ahead;
    if (a.length === 0) return;
    const e = a[a.length - 1];
    if (e.view !== undefined) {
      const i = win.rows.findIndex((r) => r.path === e.view);
      if (win.mode !== "gallery" || i < 0) { win.ahead = []; return; }
      win.ahead = a.slice(0, -1);
      win.go(i);
      win.mode = "view";
      return;
    }
    if (win.mode !== "gallery") return;
    win.ahead = a.slice(0, -1);
    if (win.dir !== "") win.history = win.history.concat([win.dir]);
    win.openDirectory(e.dir, true);
  }

  // Into a directory, from the gallery — or up out of one, landing on it.
  function openDirectory(path, keepHistory) {
    // a step of your own starts a new way forward, as a browser's does
    if (!keepHistory) {
      if (win.picked.length === 0 && win.dir !== "") win.history = win.history.concat([win.dir]);
      win.ahead = [];
    }
    win.leave(() => {
      win.forgetDirectory();
      win.cameFrom = win.dir;
      win.picked = [];
      win.want = path;
      win.startMode = "gallery";
      win.list();
    });
  }
  // What the gallery's cursor is on, acted on: a directory is gone into, a
  // picture is looked at.
  // ── THE CELL THAT WAS OPENED, LIT ─────────────────────────────────────
  // terminus' open flare: a cyan ring and wash that come up and fade on
  // smooth curves. On the cell a picture leaves from (while the gallery is
  // still fading under the flight) and the cell it lands back in.
  property string flarePath: ""
  property int flarePulse: 0
  function flare(p) {
    if (!p) return;
    win.flarePath = p;
    win.flarePulse++;
  }

  function galleryOpen(i) {
    const it = win.galleryItems[i];
    if (!it || it.isFill) return;
    win.flare(it.path);
    if (it.isDir) { win.openDirectory(it.path); return; }
    const ri = win.rowOfItem(i);
    // a folded burst opens out first; its pictures are then each a cell
    const b = win.burstAt[ri];
    if (b && !b.open) { win.foldBurst(b.key, false); return; }
    win.go(ri);
    win.mode = "view";
  }
  function gallerySel(i) {
    const n = win.galleryItems.length;
    if (n === 0) return;
    win.gidx = Math.max(0, Math.min(n - 1, i));
    const ri = win.rowOfItem(win.gidx);
    if (ri >= 0) win.go(ri);
  }
  function gallerySeek(d) {
    win.gallerySel(V.gallerySeek(win.galleryItems, win.gidx, d, win.gcols));
  }

  // ── when they were taken ──────────────────────────────────────────────
  // exiftool, once per picture per version of it, kept by the manager for
  // every window (PicassoViewer.meta). The date order, the bursts and the
  // map read it; without exiftool the file's own time stands in.
  readonly property var meta: win.mgr ? win.mgr.meta : ({})
  property var metaWaiters: []
  property bool metaBusy: false
  property bool metaWarned: false
  function needMeta(then) {
    if (!win.mgr) return;
    const rows = win.allRows.filter((r) => { const m = win.meta[r.path]; return !m || m.sig !== win.mgr.sigOf(r); });
    if (rows.length === 0) return;
    if (!win.exiftool) {
      if (!win.metaWarned) win.say("dates from the files themselves — exiftool reads the camera's own", 6000);
      win.metaWarned = true;
      return;
    }
    if (then) win.metaWaiters = win.metaWaiters.concat([then]);
    if (win.metaBusy) return;
    win.metaBusy = true;
    if (rows.length > 40) win.say("reading when " + rows.length + " pictures were taken…", 60000);
    win.capture(V.metaArgv(rows.map((r) => r.path)), (text) => {
      win.mgr.noteMeta(V.parseMeta(text), rows);
      win.metaBusy = false;
      if (rows.length > 40) win.say("");
      const ws = win.metaWaiters;
      win.metaWaiters = [];
      for (const f of ws) f();
    });
  }
  readonly property bool wantsTimes: win.sortKey === "taken" || !!(win.mgr && win.mgr.groupBursts)
  onWantsTimesChanged: if (win.wantsTimes) win.needMeta(() => win.resort())
  readonly property var rowTimes: win.wantsTimes ? win.rows.map((r) => V.takenOf(r, win.meta)) : []

  // ── bursts ────────────────────────────────────────────────────────────
  // Three or more taken within two seconds of each other, in the order shown,
  // folded into their first — unless opened (by its key, the first's path).
  property var openBursts: ({})
  readonly property var burstList: win.mgr && win.mgr.groupBursts && !win.dupes ? V.bursts(win.rowTimes, 2) : []
  // { first row index: { n, key, open } }
  readonly property var burstAt: {
    const o = {};
    for (const b of win.burstList) {
      const key = win.rows[b.start].path;
      o[b.start] = { n: b.n, key: key, open: !!win.openBursts[key] };
    }
    return o;
  }
  readonly property var hiddenRows: {
    const o = {};
    for (const b of win.burstList)
      if (!win.openBursts[win.rows[b.start].path]) for (let i = b.start + 1; i < b.start + b.n; ++i) o[i] = true;
    return o;
  }
  function foldBurst(key, fold) {
    const next = Object.assign({}, win.openBursts);
    if (fold) delete next[key]; else next[key] = true;
    win.openBursts = next;
  }

  // ── sections ──────────────────────────────────────────────────────────
  // { row index: { text, kind, … } } — the dates in the date order, an opened
  // burst, a group of alike pictures.
  readonly property var sectionAt: {
    const out = {};
    if (win.dupes) {
      let last = -1;
      for (let i = 0; i < win.rows.length; ++i) {
        const g = win.dupes.groupOf[win.rows[i].path];
        if (g === undefined || g === last) continue;
        last = g;
        const keep = win.dupes.groups[g].filter((p) => win.dupes.keep[p])[0] || "";
        out[i] = { kind: "dupe", text: "alike  \u00b7  " + win.dupes.groups[g].length,
                   sub: keep !== "" ? "best: " + Terminus.basename(keep) : "" };
      }
      return out;
    }
    if (win.sortKey === "taken" && win.rowTimes.length === win.rows.length) {
      const scale = V.sectionScale(win.rowTimes);
      let last = null;
      for (let i = 0; i < win.rows.length; ++i) {
        const sec = V.sectionOf(win.rowTimes[i], scale);
        if (sec.key === last) continue;
        last = sec.key;
        out[i] = Object.assign({ kind: "date" }, sec);
      }
    }
    for (const b of win.burstList) {
      const key = win.rows[b.start].path;
      if (!win.openBursts[key]) continue;
      const date = out[b.start];
      out[b.start] = Object.assign({}, date || {}, { kind: date ? "date" : "burst", burst: key,
        text: (date ? date.text + "  \u00b7  " : "") + "burst of " + b.n });
      if (b.start + b.n < win.rows.length && !out[b.start + b.n]) out[b.start + b.n] = { kind: "gap", text: "" };
    }
    return out;
  }
  // The date sections, for the scrubber down the gallery's side.
  readonly property var dateMarks: {
    const out = [];
    for (const k in win.layout.chips) {
      const c = win.layout.chips[k];
      if (c.kind === "date") out.push({ gi: Number(k), short: c.short, text: c.text });
    }
    out.sort((a, b) => a.gi - b.gi);
    return out;
  }

  // ── alike pictures ────────────────────────────────────────────────────
  // Each picture's difference hash (viewer.js dhashFromPgm), made once and
  // kept by the manager; then the groups of those within a few bits of each
  // other. Shown as the gallery of just them, group by group, the best of
  // each named — and one row of the menu marks all the rest, for the trash.
  property var dupes: null
  property bool dupesBusy: false
  property var dupeGot: ({})
  function findDupes() {
    if (win.dupesBusy || !win.mgr) return;
    const rows = win.allRows.filter((r) => !Terminus.isVideo(r.name));
    const need = rows.filter((r) => { const h = win.mgr.hashes[r.path]; return !h || h.sig !== win.mgr.sigOf(r); });
    if (need.length === 0) { win.showDupes(); return; }
    win.dupesBusy = true;
    win.dupeGot = ({});
    dupeProc.rows = need;
    dupeProc.done = 0;
    win.say("comparing " + rows.length + " pictures…", 600000);
    dupeProc.command = ["sh", "-c", V.dhashCommand(), "sh"].concat(need.map((r) => r.path));
    dupeProc.running = true;
  }
  Process {
    id: dupeProc
    property var rows: []
    property int done: 0
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: (line) => {
        const got = V.parseHashes(line);
        for (const k in got) win.dupeGot[k] = got[k];
        dupeProc.done++;
        if (dupeProc.done % 20 === 0) win.say("comparing  \u00b7  " + dupeProc.done + " of " + dupeProc.rows.length + " read", 600000);
      }
    }
    onExited: {
      win.mgr.noteHashes(win.dupeGot, dupeProc.rows);
      win.dupesBusy = false;
      win.showDupes();
    }
  }
  function showDupes() {
    const items = win.allRows.filter((r) => !Terminus.isVideo(r.name)).map((r) => {
      const h = win.mgr.hashes[r.path] || {};
      return { path: r.path, size: r.size, mtime: r.mtime, hash: h.hash || "", w: h.w || 0, h: h.h || 0 };
    });
    const groups = V.alikeGroups(items);
    if (groups.length === 0) { win.say("no alike pictures here"); return; }
    const keep = {}, groupOf = {};
    groups.forEach((g, i) => { keep[V.keeperOf(g).path] = true; for (const x of g) groupOf[x.path] = i; });
    win.dupes = { groups: groups.map((g) => g.map((x) => x.path)), keep: keep, groupOf: groupOf };
    win.marks = ({});
    win.applyFilter();
    win.mode = "gallery";
    const n = groups.reduce((a, g) => a + g.length, 0);
    win.say(n + " alike, in " + groups.length + (groups.length === 1 ? " group" : " groups")
            + "  \u00b7  right click: mark all but the best  \u00b7  esc leaves", 10000);
  }
  function leaveDupes() {
    win.dupes = null;
    win.applyFilter();
  }
  function markAllButBest() {
    if (!win.dupes) return;
    const next = {};
    for (const g of win.dupes.groups) for (const p of g) if (!win.dupes.keep[p]) next[p] = true;
    win.marks = next;
    win.say(Object.keys(next).length + " marked  \u00b7  delete sends them to the trash, u brings them back", 8000);
  }

  // What belonged to the directory being left: its marks, its filter, the
  // picture it was being compared with.
  function forgetDirectory() {
    win.marks = ({});
    win.filterText = "";
    win.filterOpen = false;
    win.compare = false;
    win.cmpPath = "";
  }

  function list() {
    listProc.refresh = false;
    win.listArgs();
    listProc.running = true;
  }
  // The same listing again, quietly — the directory changed under the window
  // (see the watch). The picture shown stays shown, and nothing is reset.
  function refresh() {
    if (win.want === "" || listProc.running) { win.refreshAgain = listProc.running; return; }
    listProc.refresh = true;
    win.listArgs();
    listProc.running = true;
  }
  property bool refreshAgain: false
  function listArgs() {
    if (win.picked.length > 0) {
      listProc.dirOf = "";
      listProc.command = Terminus.statArgv(win.picked);
    } else {
      // A picture opens its directory; anything else asked for is taken to BE
      // the directory — the launcher only ever hands over pictures, and a
      // directory is what `picasso-view ~/Pictures` means.
      const b = Terminus.basename(win.want);
      const d = Terminus.isImage(b) || Terminus.isVideo(b) ? Terminus.dirname(win.want) : win.want;
      listProc.dirOf = d;
      listProc.command = ["sh", "-c", Terminus.listCommand(d)];
    }
  }

  Process {
    id: listProc
    property string dirOf: ""
    property bool refresh: false
    onRunningChanged: if (!running && win.refreshAgain) { win.refreshAgain = false; Qt.callLater(win.refresh); }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        const t = String(text || ""), d = listProc.dirOf;
        const all = d !== "" ? Terminus.parseListing(t, d) : Terminus.parseStat(t);
        let rows = all.filter((r) => !r.isDir && !r.isHidden && (Terminus.isImage(r.name) || Terminus.isVideo(r.name)));
        // the .xmp files beside them, where other programs keep their tags
        const side = {};
        for (const r of all) if (!r.isDir && /\.xmp$/i.test(r.name)) side[r.path] = true;
        win.sidecars = side;
        let dirs = [];
        if (d !== "") {
          dirs = Terminus.sortEntries(all.filter((r) => r.isDir && !r.isHidden),
                                      "name", false, false, true, null);
        }
        if (win.picked.length > 0)
          rows.sort((a, b) => win.picked.indexOf(a.path) - win.picked.indexOf(b.path));
        else rows = win.sorted(rows);
        win.allRows = rows;
        win.readTags();
        if (win.wantsTimes) win.needMeta(() => win.resort());
        // a refresh: the same directory, read again — only what changed moves
        if (listProc.refresh) {
          listProc.refresh = false;
          if (win.sigOf(dirs) !== win.sigOf(win.directories)) win.directories = dirs;
          win.setRows(win.filtered(rows));
          return;
        }
        // the tiles made for it now come up one after another (see `cell`)
        win.staggering = true;
        staggerOff.restart();
        win.directories = dirs;
        win.dir = d !== "" ? d : (rows.length > 0 ? Terminus.dirname(rows[0].path) : "");
        rows = win.filtered(rows);
        win.rows = rows;
        const at = V.indexOfPath(rows, win.want);
        win.go(at >= 0 ? at : 0, true);
        // A directory asked for opens as the gallery — so does one with no
        // pictures of its own, which has only its directories to show.
        const directoryAsked = at < 0 && win.want === d;
        // "show": a slideshow of what was asked for — the menus' Slideshow
        // of these, of this directory
        const show = win.startMode === "show" && rows.length > 0;
        win.mode = show ? "view"
          : rows.length > 0 && win.startMode === "annotate" ? "annotate"
          : (win.startMode === "gallery" || directoryAsked || rows.length === 0) ? "gallery"
          : (win.mode === "annotate" ? "view" : win.mode);
        if (show) win.playing = true;
        // the gallery's cursor: on the directory just come up out of, or on
        // the picture being shown
        const came = V.indexOfPath(dirs, win.cameFrom);
        const atPic = win.itemOfPath(win.path);
        win.gidx = came >= 0 ? came : (atPic >= 0 ? atPic : 0);
        win.cameFrom = "";
        win.startMode = "view";
        if (rows.length === 0 && dirs.length === 0) win.say("no pictures here");
        if (d !== "" && win.mgr) win.mgr.noteRecent(d);
        // a copy just made beside the picture — enhanced, cut out, upscaled —
        // shown beside it
        if (win.compareAfter !== "") {
          const c = win.compareAfter;
          win.compareAfter = "";
          if (V.indexOfPath(rows, c) >= 0) Qt.callLater(() => win.startCompare(c));
        }
      }
    }
  }

  function sorted(rows) {
    // when taken — the camera's date, else the file's — newest first
    if (win.sortKey === "taken")
      return rows.slice().sort((a, b) => (V.takenOf(b, win.meta) - V.takenOf(a, win.meta))
                                         || String(a.name).localeCompare(String(b.name)));
    return Terminus.sortEntries(rows, win.sortKey, win.sortKey !== "name", false, true, null);
  }
  function sortBy(key) { if (win.mgr) win.mgr.setSort(key); }
  function resort() {
    win.reflow();
    if (win.picked.length > 0 || win.allRows.length === 0) return;
    win.allRows = win.sorted(win.allRows);
    win.setRows(win.filtered(win.allRows));
  }

  // ── the filter ────────────────────────────────────────────────────────
  // Words against the name (terminus' filterEntries, so the order is kept),
  // and #tags the picture must carry — see viewer.js splitFilter.
  property string filterText: ""
  property bool filterOpen: false
  // the filter's plain words — what the gallery's names light up
  readonly property string filterWords: V.splitFilter(win.filterText).text
  function filtered(rows) {
    const f = V.splitFilter(win.filterText);
    let out = Terminus.filterEntries(rows, f.text, true, "");
    if (f.tags.length > 0) out = out.filter((r) => V.hasAllTags(win.tags[r.path], f.tags));
    // is:video, is:picture, is:marked — and is:directory, which keeps none
    for (const k of f.kinds) {
      if (k === "video") out = out.filter((r) => Terminus.isVideo(r.name));
      else if (k === "picture") out = out.filter((r) => !Terminus.isVideo(r.name));
      else if (k === "marked") out = out.filter((r) => !!win.marks[r.path]);
      else if (k === "folder") out = [];
    }
    // the alike pictures only, group by group
    if (win.dupes) {
      const byPath = {};
      for (const r of out) byPath[r.path] = r;
      out = [];
      for (const g of win.dupes.groups) for (const p of g) if (byPath[p]) out.push(byPath[p]);
    }
    return out;
  }
  function applyFilter() { win.reflow(); win.setRows(win.filtered(win.allRows)); }
  // The gallery's directories, narrowed by the filter's words too — a
  // search for "2024" finds the directory as well as the pictures. Tags and
  // kinds are about pictures, so a filter with any leaves no directory, except
  // is:directory, which leaves only them.
  readonly property var shownDirectories: {
    const f = V.splitFilter(win.filterText);
    const onlyDirs = f.kinds.length > 0 && f.kinds.every((k) => k === "folder");
    if (f.tags.length > 0 || (f.kinds.length > 0 && !onlyDirs)) return [];
    return f.text === "" ? win.directories : Terminus.filterEntries(win.directories, f.text, true, "");
  }
  onMarksChanged: if (V.splitFilter(win.filterText).kinds.indexOf("marked") >= 0) win.applyFilter()
  function setFilter(t) {
    if (t === win.filterText) return;
    win.filterText = t;
    win.applyFilter();
  }

  // Enough of a listing to tell whether it changed.
  function sigOf(rows) {
    return rows.map((r) => r.path + "\u001f" + (r.mtime || 0) + "\u001f" + (r.size || 0)).join("\n");
  }

  // New rows in, the picture shown kept if it is still among them — at
  // whatever index it is at now. Gone (trashed, renamed elsewhere, filtered
  // out), the one that took its place is shown. The same rows again are not
  // set at all: a model set is every tile rebuilt, and a tag written fires
  // the watch without the listing having changed.
  function setRows(rows) {
    if (win.sigOf(rows) !== win.sigOf(win.rows)) win.rows = rows;
    const at = V.indexOfPath(win.rows, win.path);
    if (at >= 0) win.index = at;
    else win.go(Math.min(Math.max(0, win.index), win.rows.length - 1), true);
    if (win.cmpPath !== "" && V.indexOfPath(win.rows, win.cmpPath) < 0) win.compare = false;
    const n = win.galleryItems.length;
    const on = win.galleryItems[win.gidx];
    if (win.mode !== "gallery" || !on || !on.isDir) {
      const at = win.itemOfPath(win.path);
      win.gidx = at >= 0 ? at : Math.min(win.gidx, Math.max(0, n - 1));
    }
    win.rehold();
  }

  // To picture `i`. `force` skips the question about an unsaved edit — the
  // caller has asked it already.
  function go(i, force) {
    if (win.rows.length === 0) { win.index = -1; win.path = ""; win.resetEdit(); return; }
    const to = Math.max(0, Math.min(win.rows.length - 1, i));
    if (!force && to === win.index) return;
    const doIt = () => {
      // locked, the place on this picture is taken to the next
      const keep = win.zoomLock && !win.fitted && win.loaded
        ? Object.assign({ z: win.vz }, V.centreOf({ z: win.vz, x: win.vx, y: win.vy },
                                                  win.tw, win.th, stage.width, stage.height))
        : null;
      // a step seen: the last picture slides off, this one comes in after it
      const d = to > win.index ? 1 : -1;
      const seen = win.mode === "view" && win.index >= 0 && !win.flyingIn;
      win.ghost = seen && win.loaded && !win.isVid && win.straighten === 0
        && win.look.rotate === 0 && !win.look.mirror
        ? { url: win.stageUrl, x: pic.x, y: pic.y, w: pic.width, h: pic.height, d: d } : null;
      win.enterDir = seen ? d : 0;
      enterAnim.stop();
      win.enterK = 0;
      win.resetEdit();
      win.fallback = "";
      win.gifPaused = false;
      win.pixel = null;
      win.index = to;
      win.path = win.rows[to].path;
      win.fitted = true;
      win.refit(false);
      win.pendingView = keep;
      Qt.callLater(win.applyPending);
      Qt.callLater(win.enter);
      win.rehold();
      if (win.infoShown) win.askExif();
    };
    if (force) doIt(); else win.leave(doIt);
  }
  function step(d) {
    if (win.rows.length === 0) return;
    // past either end, a person stepping is told so by the picture itself
    if (!win.playing && (win.index + d < 0 || win.index + d >= win.rows.length)) { win.bump(d); return; }
    // the slideshow goes round — shuffled, picasso.js' pick, as the
    // background's slideshow picks; a person stepping stops at the ends
    if (win.playing && win.shuffle && d > 0 && win.rows.length > 2) {
      const next = Art.nextSlide(win.rows.map((r) => r.path), win.path, true);
      win.go(V.indexOfPath(win.rows, next));
    } else if (win.playing) win.go((win.index + d + win.rows.length) % win.rows.length);
    else win.go(win.index + d);
  }

  // ── a step, seen ──────────────────────────────────────────────────────
  // The picture left slides a little the way it went and fades (`ghost`, a
  // second Image of the same url, so Qt's cache answers it at once); the
  // next comes in from the other side as it is decoded (`enterK`, 0 → 1).
  // Opened from the gallery it flies out of its tile instead (`flyIn`).
  readonly property int stepMs: Math.round(130 * Oracle.motionScale)
  readonly property int flyMs: Math.round(140 * Oracle.motionScale)
  property var ghost: null
  property int enterDir: 0
  property real enterK: 1
  // how far the picture is pushed off its place: the step's slide, or the
  // bump at either end of the directory
  property real bumpX: 0
  // A step is a SLIDE, no fade: the next picture comes in from the side it
  // lies on, the last one goes out the other way, both whole — and only once
  // the next is decoded, so the last stays in place meanwhile, never a gap.
  readonly property int slideMs: Math.round(200 * Oracle.motionScale)
  readonly property real slideX: (1 - win.enterK) * win.enterDir * stage.width + win.bumpX
  NumberAnimation { id: enterAnim; target: win; property: "enterK"; to: 1
                    duration: win.enterDir !== 0 ? win.slideMs : win.stepMs; easing.type: Easing.OutCubic
                    onFinished: win.ghost = null }
  function enter() {
    if (win.loaded && !win.flyingIn && win.enterK < 1) enterAnim.restart();
  }
  // stepped past the first or the last: pulled that way, and back
  property int bumpDir: 0
  function bump(d) {
    if (win.mode !== "view") return;
    win.bumpDir = d;
    bumpAnim.restart();
    win.say(d > 0 ? "the last picture" : "the first picture", 1200);
  }
  SequentialAnimation {
    id: bumpAnim
    NumberAnimation { target: win; property: "bumpX"; to: -win.bumpDir * 28
                      duration: Math.round(90 * Oracle.motionScale); easing.type: Easing.OutCubic }
    NumberAnimation { target: win; property: "bumpX"; to: 0
                      duration: Math.round(320 * Oracle.motionScale); easing.type: Easing.OutBack; easing.overshoot: 2.2 }
  }

  // a directory just listed: its first tiles rise in turn
  property bool staggering: false
  Timer { id: staggerOff; interval: 500; onTriggered: win.staggering = false }

  // ── A REORDER GLIDES ──────────────────────────────────────────────────
  // The grid's model is an array, so a filter or a new order makes every
  // tile again — and they used to jump. `tilePos` is where each path's tile
  // was in the last layout (grid content coordinates), noted a tick after
  // each layout so a tile made by the change still reads the old one; while
  // `reflowing` a tile that was there before starts at its old place and
  // glides to the new one, and one that was not fades in.
  property var tilePos: ({})
  property bool reflowing: false
  Timer { id: reflowOff; interval: 450; onTriggered: win.reflowing = false }
  // not while a directory is arriving (its tiles rise in turn instead) —
  // a resort as its dates come in is not you reordering anything
  function reflow() {
    if (win.staggering) return;
    win.reflowing = true;
    reflowOff.restart();
  }
  Timer {
    id: notePos
    interval: 0
    onTriggered: {
      const out = {}, items = win.layout.items, c = win.gcols;
      const cw = grid.cellWidth, ch = grid.cellHeight;
      for (let i = 0; i < items.length; ++i)
        if (items[i].path) out[items[i].path] = { x: (i % c) * cw, y: Math.floor(i / c) * ch };
      win.tilePos = out;
    }
  }

  // ── from a tile, and back into it ────────────────────────────────────
  // Between the gallery and a picture, the picture flies: out of its tile
  // to where it will be shown, and back into its tile on the way out. The
  // flyer is a copy laid over everything for the flight; the real picture
  // (or its tile) takes over where it lands.
  property bool flyingIn: false
  // the tile hidden while the picture flies back into it
  property string flyTarget: ""
  property string lastMode: "view"
  function thumbUrl(p) {
    const t = win.thumbs[p];
    return t && t !== "-" ? "file://" + t : "";
  }
  // where a picture of this shape will be shown, fitted, in the stage
  function guessRect(ratio) {
    const rw = stage.width - 2 * win.margin, rh = stage.height - 2 * win.margin;
    if (!(ratio > 0) || rw <= 0 || rh <= 0) return null;
    const w = rw / rh > ratio ? rh * ratio : rw, h = w / ratio;
    return { x: win.margin + (rw - w) / 2, y: win.margin + (rh - h) / 2, w: w, h: h };
  }
  function flyIn() {
    const cell = grid.itemAtIndex(win.itemOfPath(win.path));
    const th = cell ? cell.thumbItem : null;
    if (!th || !th.visible || !th.measured || win.isVid) return;
    const url = win.thumbUrl(win.path);
    if (url === "") return;
    const r = win.loaded ? { x: pic.x, y: pic.y, w: pic.width, h: pic.height } : win.guessRect(th.ratio);
    if (!r) return;
    const from = th.mapToItem(flyLayer, 0, 0, th.width, th.height);
    const to = stage.mapToItem(flyLayer, r.x, r.y);
    win.flyingIn = true;
    win.enterDir = 0;
    galleryOut.restart();
    flyLayer.launch(url, false, from, Qt.rect(to.x, to.y, r.w, r.h), th.radius, win.picRadius);
  }
  function flyOut() {
    const gi = win.itemOfPath(win.path);
    if (gi < 0 || !win.loaded || win.isVid) return;
    grid.positionViewAtIndex(gi, GridView.Contain);
    grid.forceLayout();
    const cell = grid.itemAtIndex(gi);
    const th = cell ? cell.thumbItem : null;
    if (!th || !th.measured) return;
    // a zoomed picture leaves from where it would sit fitted
    const r = win.fitted ? { x: pic.x, y: pic.y, w: pic.width, h: pic.height } : win.guessRect(win.tw / win.th);
    if (!r) return;
    const sharp = win.fallback === "" && win.straighten === 0 && win.look.rotate === 0 && !win.look.mirror;
    const url = sharp ? win.stageUrl : win.thumbUrl(win.path);
    if (url === "") return;
    const from = stage.mapToItem(flyLayer, r.x, r.y);
    const to = th.mapToItem(flyLayer, 0, 0, th.width, th.height);
    win.flyTarget = win.path;
    flyLayer.launch(url, true, Qt.rect(from.x, from.y, r.w, r.h), to, win.picRadius, th.radius);
    galleryOut.stop();
    galleryFade.restart();
  }
  function landed(back) {
    if (back) { win.flare(win.flyTarget); win.flyTarget = ""; return; }
    // The picture (or its stand-in) is put down at full strength under the
    // flyer, and only the flyer fades: two halves fading across each other
    // let the dark window through, and the picture dipped as it landed.
    enterAnim.stop();
    win.enterK = 1;
    win.flyingIn = false;
  }

  // ── the zoom, shown ───────────────────────────────────────────────────
  // The bar's percentage counts to its new value as the picture glides, and
  // a zoom asked for is said once more, large, over the picture.
  property real shownZoom: win.vz * 100
  Behavior on shownZoom { NumberAnimation { duration: Zenon.slow; easing.type: Easing.OutCubic } }
  property bool zoomSaid: false
  Timer { id: zoomSaidOff; interval: 750; onTriggered: win.zoomSaid = false }
  function sayZoom() {
    if (win.mode !== "view" || !win.loaded) return;
    win.zoomSaid = true;
    zoomSaidOff.restart();
  }

  // the fitted picture's corners, rounded while there is room round it
  readonly property real picRadius: win.chrome ? 4 : 0
  // a picture that may have see-through parts sits on a checkerboard
  readonly property bool mayAlpha: /\.(png|webp|gif|apng|svgz?|avif|tiff?|ico|jxl|qoi|tga)$/i.test(win.path)

  // ── the zoom, locked ──────────────────────────────────────────────────
  // The place go() took from the last picture, put on this one once it is
  // decoded — after its own size has fitted it (onTwChanged), hence later.
  property var pendingView: null
  function applyPending() {
    const p = win.pendingView;
    if (!p || !win.loaded) return;
    win.pendingView = null;
    win.fitted = false;
    win.setView(V.viewAt(p.z, p.fx, p.fy, win.tw, win.th, stage.width, stage.height), 0);
  }
  onLoadedChanged: if (win.loaded) { Qt.callLater(win.applyPending); Qt.callLater(win.enter); }
  onZoomLockChanged: win.say(win.zoomLock ? "zoom locked — the next picture opens at this size and place"
                                          : "zoom unlocked")

  // Anything that would drop an unsaved edit asks first.
  function leave(then) {
    if (!win.precious) { then(); return; }
    confirm.ask("Leave without saving the edit?", "Discard", Zenon.red, () => { win.resetEdit(); then(); });
  }

  function close() {
    if (win.mode === "annotate" && annLoader.item) { annLoader.item.close(); return; }
    win.leave(() => { win.visible = false; });
  }

  // ── thumbnails, from the shared pool ──────────────────────────────────
  // Asked for by the tiles that are actually made — the strip and the grid
  // only build what is near the view — and batched, so scrolling a directory
  // of two thousand photos renders the ones on screen, not all of them.
  property var thumbs: ({})
  property var thumbQueue: []

  function wantThumb(p) {
    if (p in win.thumbs || win.thumbQueue.indexOf(p) >= 0) return;
    win.thumbQueue.push(p);
    thumbKick.restart();
  }
  Timer { id: thumbKick; interval: 30; onTriggered: win.runThumbs() }

  function runThumbs() {
    if (thumbProc.running || win.thumbQueue.length === 0) return;
    const batch = win.thumbQueue.splice(0, 48);
    thumbProc.batch = batch;
    thumbProc.command = ["sh", "-c",
      Thumbs.generate(batch.map((p) => ({ kind: Terminus.isVideo(Terminus.basename(p)) ? "v" : "i", src: p })), false)];
    thumbProc.running = true;
  }

  Process {
    id: thumbProc
    property var batch: []
    // ── AS EACH ONE LANDS ────────────────────────────────────────────
    // A tile waits for its thumbnail (`wait`), and the batch used to be
    // heard of only once all 48 were made — so the gallery sat blank and
    // then filled a block at a time. Each line is one that exists now;
    // they are handed over every few frames (thumbFlush), as terminus does.
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: (line) => {
        const cut = line.indexOf("\t");
        if (cut <= 0) return;
        win.thumbPending[line.slice(0, cut)] = line.slice(cut + 1);
        if (!thumbFlush.running) thumbFlush.start();
      }
    }
    onRunningChanged: {
      if (running) return;
      thumbFlush.stop();
      // not reported is not made: "" lets the tile fall back to the original
      for (const p of thumbProc.batch)
        if (!(p in win.thumbPending) && !(p in win.thumbs)) win.thumbPending[p] = "";
      win.takeThumbs();
      Qt.callLater(win.runThumbs);
    }
  }
  property var thumbPending: ({})
  Timer { id: thumbFlush; interval: 70; onTriggered: win.takeThumbs() }
  function takeThumbs() {
    const got = win.thumbPending;
    win.thumbPending = ({});
    let any = false;
    for (const k in got) { any = true; break; }
    if (!any) return;
    win.thumbs = Object.assign({}, win.thumbs, got);
  }

  // ── the directory, watched ───────────────────────────────────────────────
  // terminus' watch (Terminus.watchArgv) on the directory shown. A screenshot
  // landing, a picture renamed or deleted elsewhere, tags written — the
  // listing is read again, quietly, and the picture shown stays shown. A
  // file written over has its thumbnail dropped, and is shown afresh if it
  // is the one on screen and nobody is editing it.
  readonly property string watchDir: win.visible && win.picked.length === 0 ? win.dir : ""
  onWatchDirChanged: {
    watchProc.running = false;
    if (win.watchDir === "") return;
    watchProc.command = Terminus.watchArgv([win.watchDir]);
    watchProc.running = true;
  }
  property var written: ({})
  Process {
    id: watchProc
    stdout: SplitParser {
      splitMarker: "\n"
      // "<dir>/ EVENT[,EVENT] name"
      onRead: (line) => {
        const s = String(line), head = win.watchDir + "/ ";
        if (s.indexOf(head) === 0) {
          const rest = s.slice(head.length), cut = rest.indexOf(" ");
          if (cut > 0 && rest.slice(0, cut).indexOf("CLOSE_WRITE") >= 0)
            win.written[Terminus.joinPath(win.watchDir, rest.slice(cut + 1))] = true;
        }
        watchSettle.restart();
      }
    }
  }
  // One copy is a stream of events; one read answers all of it.
  Timer {
    id: watchSettle
    interval: 300
    onTriggered: {
      const changed = win.written;
      win.written = ({});
      const next = Object.assign({}, win.thumbs);
      let any = false;
      for (const p in changed) if (p in next) { delete next[p]; any = true; }
      if (any) {
        win.thumbs = next;
        for (const p in changed) if (V.indexOfPath(win.allRows, p) >= 0) win.wantThumb(p);
      }
      if (changed[win.path] && !win.edited) win.reloadTick++;
      win.refresh();
    }
  }

  // ── the neighbours, read ahead ────────────────────────────────────────
  // The picture shown and the ones either side, decoded in the background
  // into Qt's pixmap cache and HELD there: the stage asks for the same url
  // at the same size and finds it waiting, so stepping through a directory of
  // big photos does not blank and fade on every step. Held, because Qt
  // keeps an unreferenced picture only while it is under 2 MB — a slot let
  // go of is a decode thrown away. Three slots, kept where they are as the
  // window moves along: a step changes one of them.
  // Stills only — an animation or a vector loads its own — and nothing so
  // big that holding three of it is the wrong trade.
  property var holdPaths: ["", "", ""]
  function holdable(r) {
    return !!r && !/\.(gif|webp|apng|mng|svgz?)$/i.test(r.path) && !Terminus.qtBlind(r.name) && !Terminus.isVideo(r.name)
      && (r.size || 0) < 60000000;
  }
  function rehold() {
    const want = [win.index, win.index + 1, win.index - 1]
      .filter((i) => i >= 0 && i < win.rows.length && win.holdable(win.rows[i]))
      .map((i) => win.rows[i].path);
    const next = win.holdPaths.map((p) => want.indexOf(p) >= 0 ? p : "");
    for (const p of want) if (next.indexOf(p) < 0) {
      const free = next.indexOf("");
      if (free >= 0) next[free] = p;
    }
    if (next.join("\n") !== win.holdPaths.join("\n")) win.holdPaths = next;
  }
  Repeater {
    model: 3
    delegate: Image {
      required property int index
      visible: false
      asynchronous: true
      cache: true
      autoTransform: true
      // as the stage's still asks — the size is part of the cache's key
      sourceSize.width: 0
      source: win.holdPaths[index] !== "" ? win.urlOf(win.holdPaths[index]) : ""
    }
  }

  // ── marks ─────────────────────────────────────────────────────────────
  // Marked pictures, by path. What the trash, the tags, a copy and a drag
  // act on when there are any — see targets().
  property var marks: ({})
  // the gallery cell whose thumbnail the pointer is on, or -1 — a drag there
  // takes the file out; anywhere else it draws the marking box
  property int hoverThumb: -1
  readonly property int markCount: Object.keys(win.marks).length
  // in the directory's order, not the order they were marked in
  function markedPaths() {
    return win.allRows.filter((r) => win.marks[r.path]).map((r) => r.path);
  }
  function setMarks(next) { win.marks = next; }
  function toggleMark(p) {
    if (!p) return;
    const next = Object.assign({}, win.marks);
    if (next[p]) delete next[p]; else next[p] = true;
    win.marks = next;
  }
  // gallery indices, both ends in
  function markRange(a, b) {
    const next = Object.assign({}, win.marks);
    for (let i = Math.min(a, b); i <= Math.max(a, b); ++i) {
      const it = win.galleryItems[i];
      if (it && !it.isDir && !it.isFill) next[it.path] = true;
    }
    win.marks = next;
  }
  function markAll() {
    const next = {};
    for (const r of win.rows) next[r.path] = true;
    win.marks = next;
  }
  // What an action is about: the marked pictures, when there are some and
  // `p` is among them (or nothing in particular was named) — else `p`, and
  // nothing at all when that is nothing (the gallery's cursor on a directory).
  function targets(p) {
    const m = win.markedPaths();
    if (m.length > 0 && (!p || win.marks[p])) return m;
    return p ? [p] : [];
  }
  function some(ps) { return ps.length === 1 ? Terminus.basename(ps[0]) : ps.length + " pictures"; }

  // ── tags ──────────────────────────────────────────────────────────────
  // terminus' (tags.js): user.xdg.tags on the files themselves, so a picture
  // starred here is starred in terminus' tag pages too. Read for the directory
  // after every listing; written back as they change. "favourite" is the
  // star — V.FAVOURITE.
  property var tags: ({})
  // .xmp files in the directory ({ path: true }), and what the ones beside the
  // pictures say ({ picture: { names, rating } }) — see tags.js' sidecars
  property var sidecars: ({})
  property var sideInfo: ({})
  readonly property bool exiftool: !!(win.mgr && win.mgr.tools.exiftool)
  function readTags() {
    tagProc.running = false;
    if (win.allRows.length === 0) { win.tags = ({}); return; }
    tagProc.command = Tags.readTagsArgv(win.allRows.map((r) => r.path));
    tagProc.running = true;
  }
  Process {
    id: tagProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        win.tags = Tags.parseTagDump(text);
        if (V.splitFilter(win.filterText).tags.length > 0) win.applyFilter();
        win.readSidecars();
      }
    }
  }
  // The sidecars' tags, put together with the attribute's — a tag in
  // either is a tag. Written back to both (writeTags), so the two agree.
  function readSidecars() {
    const xs = Object.keys(win.sidecars);
    if (xs.length === 0 || !win.exiftool) { win.sideInfo = ({}); return; }
    win.capture(Tags.readSidecarsArgv(xs), (text) => {
      const info = Tags.parseSidecars(text, win.allRows.map((r) => r.path));
      win.sideInfo = info;
      const next = Object.assign({}, win.tags);
      for (const p in info) {
        const names = Tags.normalise((next[p] || []).concat(info[p].names));
        if (names.length > 0) next[p] = names;
      }
      win.tags = next;
      if (V.splitFilter(win.filterText).tags.length > 0) win.applyFilter();
    });
  }
  function hasSidecar(p) { return Tags.sidecarFor(p, win.sidecars) in win.sidecars; }
  function writeSidecars(pairs) {
    if (!win.exiftool) return;
    const want = pairs.filter((e) => (win.mgr && win.mgr.xmpSidecars) || win.hasSidecar(e.path));
    if (want.length === 0) return;
    win.run(Tags.writeSidecarsArgv(want.map((e) => ({
      path: e.path, names: e.names,
      rating: Tags.sidecarRating(e.names.indexOf(V.FAVOURITE) >= 0, (win.sideInfo[e.path] || {}).rating || 0)
    })), win.sidecars), (code) => { if (code !== 0) win.say("the tags are saved, but an .xmp beside them could not be written"); });
  }

  function writeTags(pairs, said) {
    if (pairs.length === 0) return;
    const next = Object.assign({}, win.tags);
    for (const e of pairs) {
      if (e.names.length > 0) next[e.path] = e.names;
      else delete next[e.path];
    }
    win.tags = next;
    if (V.splitFilter(win.filterText).tags.length > 0) win.applyFilter();
    win.run(["sh", "-c", Tags.writeManyCommand(pairs)], (code) => {
      if (code !== 0) { win.say("could not write the tags — this filesystem may not keep them"); win.readTags(); return; }
      win.writeSidecars(pairs);
      if (said) win.say(said);
    });
  }
  function starred(p) { return V.hasAllTags(win.tags[p], [V.FAVOURITE]) && !!p; }
  function toggleStar(p) {
    const ps = win.targets(p);
    if (ps.length === 0) return;
    const t = Tags.toggleAcross(win.tags, ps, V.FAVOURITE);
    win.writeTags(t.pairs, (t.added ? "\u2605 " : "unstarred ") + win.some(ps));
  }
  function editTags(p) {
    const ps = win.targets(p);
    if (ps.length === 0) return;
    const one = ps.length === 1;
    confirm.askText(one ? "Tags for " + Terminus.basename(ps[0]) : "Add tags to " + ps.length + " pictures",
      one ? (win.tags[ps[0]] || []).join(", ") : "", "Save", (text) => {
        const typed = Tags.splitTags(text);
        win.writeTags(ps.map((q) => ({ path: q,
          names: Tags.normalise(one ? typed : (win.tags[q] || []).concat(typed)) })), "tags saved");
      }, "commas between them · red, green, blue … wear their colour · favourite is the star");
  }

  // Qt could not decode it: the one-off big render, as terminus' quick look
  // makes for the same files.
  function renderFallback() {
    if (win.fallback !== "" || bigProc.running || win.path === "") return;
    bigProc.forPath = win.path;
    bigProc.command = ["sh", "-c", Thumbs.generate([{ kind: "i", src: win.path }], true)];
    bigProc.running = true;
  }
  Process {
    id: bigProc
    property string forPath: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        const made = Thumbs.parseMade(text)[bigProc.forPath] || "";
        if (bigProc.forPath !== win.path) return;
        if (made !== "") { win.fallback = made; win.say("shown from a 1600px copy — Qt cannot open this format"); }
        else win.say("this picture cannot be opened");
      }
    }
  }

  // ── what the camera said ──────────────────────────────────────────────
  property var exif: []
  // where it was taken, when it says — { lat, lon } or null
  property var gps: null
  // red, green, blue and light, from a small copy — viewer.js histogram
  property var hist: null
  // its most used colours, [{ n, hex }] — viewer.js parsePalette
  property var palette: []
  function askExif() {
    win.exif = [];
    win.gps = null;
    win.hist = null;
    win.palette = [];
    if (win.path === "" || win.isVid) return;
    paletteProc.forPath = win.path;
    paletteProc.command = ["magick", "-define", "jpeg:size=256x256", win.path + "[0]", "-resize", "160x160",
      "+dither", "-colors", "8", "-format", "%c", "histogram:info:-"];
    paletteProc.running = true;
    exifProc.forPath = win.path;
    exifProc.command = ["magick", "identify", "-format",
      "Model=%[EXIF:Model]\\nLensModel=%[EXIF:LensModel]\\nDateTimeOriginal=%[EXIF:DateTimeOriginal]\\n"
      + "ExposureTime=%[EXIF:ExposureTime]\\nFNumber=%[EXIF:FNumber]\\n"
      + "PhotographicSensitivity=%[EXIF:PhotographicSensitivity]\\nFocalLength=%[EXIF:FocalLength]\\n"
      + "GPSLatitude=%[EXIF:GPSLatitude]\\nGPSLatitudeRef=%[EXIF:GPSLatitudeRef]\\n"
      + "GPSLongitude=%[EXIF:GPSLongitude]\\nGPSLongitudeRef=%[EXIF:GPSLongitudeRef]\\n",
      win.path + "[0]"];
    exifProc.running = true;
    // jpeg:size lets the decoder hand back a small picture to begin with —
    // a tenth of a second for a 40-megapixel photo
    histProc.forPath = win.path;
    histProc.command = ["magick", "-define", "jpeg:size=256x256", win.path + "[0]",
      "-sample", "128x128>", "-depth", "8", "-compress", "none", "ppm:-"];
    histProc.running = true;
  }
  Process {
    id: exifProc
    property string forPath: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (exifProc.forPath === win.path) {
        win.exif = V.parseExif(text);
        win.gps = V.parseGps(text);
      }
    }
  }
  Process {
    id: histProc
    property string forPath: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (histProc.forPath === win.path) win.hist = V.histogram(text, 64)
    }
  }
  Process {
    id: paletteProc
    property string forPath: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (paletteProc.forPath === win.path) win.palette = V.parsePalette(text).slice(0, 8)
    }
  }
  function copyPalette() {
    if (win.palette.length === 0) return;
    const t = win.palette.map((c) => c.hex).join(" ");
    Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | wl-copy", "sh", t]);
    win.say("the palette is on the clipboard  \u00b7  " + t);
  }
  onInfoShownChanged: if (win.infoShown) win.askExif()

  // ── things done to the file ───────────────────────────────────────────
  function run(argv, then) {
    const p = actComp.createObject(win, { command: argv, then: then || null });
    if (p) p.running = true;
  }
  Component {
    id: actComp
    Process {
      property var then: null
      onExited: (code) => { if (then) then(code); destroy(); }
    }
  }

  // As run(), with what it printed: then(text), once it has finished.
  function capture(argv, then) {
    const p = capComp.createObject(win, { command: argv, then: then });
    if (p) p.running = true;
  }
  Component {
    id: capComp
    Process {
      id: cap
      property var then: null
      stdout: StdioCollector {
        waitForEnd: true
        onStreamFinished: { if (cap.then) cap.then(String(text || "")); cap.destroy(); }
      }
    }
  }

  function copyImage() {
    if (win.path === "") return;
    win.run(["sh", "-c", "wl-copy < \"$1\"", "sh", win.path]);
    win.say("copied to the clipboard");
  }
  function copyPath() {
    if (win.path === "") return;
    Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | wl-copy", "sh", win.path]);
    win.say("path copied");
  }
  // In the image editor oracle's Default Apps names, by its desktop id —
  // Desktop.launchCommand, so a stale user entry falls through to the
  // system's copy rather than doing nothing.
  function editIn() {
    if (win.path === "" || Oracle.imageEditor === "") return;
    Quickshell.execDetached(["sh", "-c", Desktop.launchCommand(Oracle.imageEditor, win.path)]);
  }
  function reveal() {
    if (win.dir === "") return;
    win.run(["qs", "ipc", "call", "Terminus", "reveal", win.path !== "" ? win.path : win.dir + "/"]);
  }
  // The files themselves onto the clipboard, as terminus copies them — to
  // paste into a directory, a chat, a mail.
  function copyFiles(ps) {
    if (ps.length === 0) return;
    win.run(Terminus.shArgv(Terminus.clipboardCopyCommand(ps, false)));
    win.say(ps.length === 1 ? "copied as a file" : ps.length + " pictures copied as files");
  }

  // ── the trash, and back out of it ─────────────────────────────────────
  // No question first: the answer to a mistake is `u`, which puts back what
  // went last — terminus' restore, by the paths it came from.
  // Asked first, on a sheet naming them — yellow, as terminus inks a trash:
  // it can be undone (u), unlike a delete.
  function trash(ps) {
    if (!ps || ps.length === 0) return;
    confirm.ask("Move " + win.some(ps) + " to the trash?", "Trash", Zenon.yellow, () => win.trashNow(ps),
                ["u", "brings " + (ps.length === 1 ? "it" : "them") + " back"], win.listed(ps), "\uf014");
  }
  // What a sheet is about, one a line — when there are several; one is
  // named in the question itself. As files, so the sheet draws each one's
  // glyph beside it (terminus/ConfirmBody).
  function listed(ps) { return ps.length > 1 ? ps.map((q) => ({ name: Terminus.basename(q), isDir: false })) : []; }
  function trashNow(ps) {
    win.run(Terminus.shArgv(Terminus.trashCommand(ps)), (code) => {
      if (code !== 0) { win.say("could not move " + win.some(ps) + " to the trash"); win.refresh(); return; }
      win.pushUndo({ kind: "trash", paths: ps });
      win.dropRows(ps);
      win.say((ps.length === 1 ? "moved to the trash" : ps.length + " moved to the trash")
              + "  \u00b7  u brings " + (ps.length === 1 ? "it" : "them") + " back", 8000);
    });
  }
  // ── deleting for good ─────────────────────────────────────────────────
  // terminus' delete — gone, not to the trash, so u cannot bring it back.
  // Red, as terminus inks what cannot be undone.
  function deleteForever(ps) {
    if (!ps || ps.length === 0) return;
    confirm.ask("Delete " + win.some(ps) + " for good?", "Delete", Zenon.red, () => {
      win.run(Terminus.shArgv(Terminus.deleteCommand(ps)), (code) => {
        win.say(code !== 0 ? "could not delete " + win.some(ps)
                : (ps.length === 1 ? Terminus.basename(ps[0]) + " deleted" : ps.length + " deleted"));
        win.dropRows(ps);
        if (code !== 0) win.refresh();
      });
    }, "this cannot be undone — they do not go to the trash", win.listed(ps), "\uf00d");
  }

  // ── undo ──────────────────────────────────────────────────────────
  // What went last, put back: pictures trashed, or a file written over in
  // place — a save, a turn, marks saved on themselves — from the copy kept
  // just before (keepCopies). Twenty deep; the copies live in the cache and
  // are swept a day later (PicassoViewer).
  property var undoStack: []
  readonly property string undoDir: Paths.cacheDir() + "/picasso/undo"
  function pushUndo(e) {
    const next = win.undoStack.concat([e]);
    while (next.length > 20) next.shift();
    win.undoStack = next;
  }
  // `ps` copied aside, then `then()` — or, when the copy fails, nothing
  // written at all.
  function keepCopies(ps, then) {
    const stamp = String(Date.now());
    const pairs = ps.map((p, i) => [p, V.backupName(win.undoDir, p, stamp + "-" + i)]);
    const args = [win.undoDir];
    for (const q of pairs) args.push(q[0], q[1]);
    win.run(["sh", "-c", V.backupCommand(), "sh"].concat(args), (code) => {
      if (code !== 0) { win.say("could not keep a copy of the original first — nothing was written"); return; }
      win.pushUndo({ kind: "over", pairs: pairs.map((q) => [q[1], q[0]]) });
      then();
    });
  }
  function untrash() { win.undo(); }
  function undo() {
    const e = win.undoStack[win.undoStack.length - 1];
    if (!e) { win.say("nothing to undo"); return; }
    win.undoStack = win.undoStack.slice(0, -1);
    if (e.kind === "trash") { win.untrashPaths(e.paths); return; }
    const args = [];
    for (const q of e.pairs) args.push(q[0], q[1]);
    const ps = e.pairs.map((q) => q[1]);
    win.run(["sh", "-c", V.restoreCommand(), "sh"].concat(args), (code) => {
      const next = Object.assign({}, win.thumbs);
      for (const p of ps) delete next[p];
      win.thumbs = next;
      for (const p of ps) win.wantThumb(p);
      if (ps.indexOf(win.path) >= 0) { win.resetEdit(); win.reloadTick++; }
      win.say(code !== 0 ? "could not put everything back" : "put back as it was  \u00b7  " + win.some(ps));
    });
  }
  function untrashPaths(ps) {
    win.run(Terminus.shArgv(Terminus.restoreCommand(ps, "path")), (code) => {
      win.say(code !== 0 ? "could not bring everything back"
              : (ps.length === 1 ? Terminus.basename(ps[0]) + " is back" : ps.length + " are back"));
      win.want = ps[0];
      win.startMode = win.mode;
      win.list();
    });
  }
  // Paths gone from the directory — trashed, moved away — out of the rows.
  function dropRows(ps) {
    const gone = {};
    for (const q of ps) gone[q] = true;
    const m = Object.assign({}, win.marks);
    for (const q of ps) delete m[q];
    win.marks = m;
    if (gone[win.path]) win.resetEdit();
    win.allRows = win.allRows.filter((r) => !gone[r.path]);
    win.setRows(win.filtered(win.allRows));
  }

  // ── renaming ──────────────────────────────────────────────────────────
  // terminus' rename, which will not land on a name already taken. The row
  // is changed in place, so the picture stays shown — and its edit kept.
  function rename(p) {
    if (!p) return;
    const name = Terminus.basename(p);
    const dot = name.lastIndexOf(".");
    confirm.askText("Rename " + name, name, "Rename", (text) => {
      const n = String(text).trim();
      if (n === name) return;
      const err = Terminus.nameError(n);
      if (err !== "") { win.say(err); return; }
      win.run(["sh", "-c", Terminus.renameCommand(p, n)], (code) => {
        if (code !== 0) { win.say("could not rename it — is " + n + " taken?"); return; }
        const to = Terminus.joinPath(Terminus.dirname(p), n);
        const move = (o) => { if (!(p in o)) return o; const c = Object.assign({}, o); c[to] = c[p]; delete c[p]; return c; };
        win.marks = move(win.marks);
        win.tags = move(win.tags);
        win.thumbs = move(win.thumbs);
        if (win.picked.length > 0) win.picked = win.picked.map((q) => q === p ? to : q);
        if (win.cmpPath === p) win.cmpPath = to;
        win.allRows = win.allRows.map((r) => r.path !== p ? r
          : Object.assign({}, r, { name: n, path: to, hay: undefined }));
        if (win.picked.length === 0) win.allRows = win.sorted(win.allRows);
        if (win.path === p) win.path = to;
        win.setRows(win.filtered(win.allRows));
        win.say("renamed to " + n);
      });
    }, "", dot > 0 ? dot : name.length);
  }

  // ── renaming several ──────────────────────────────────────────────────
  // terminus' own batch rename — the same card (terminus/BulkRename.qml),
  // opened on the marked pictures; one alone is the plain rename above.
  // The moves it hands back run through terminus' bulkRenameApply, and
  // the marks, tags and the picture shown follow their files.
  function bulkRename(ps) {
    if (ps.length === 0) return;
    if (ps.length === 1) { win.rename(ps[0]); return; }
    bulkCard.begin(ps.map((q) => Terminus.basename(q)), ps);
  }
  function renamedMany(moves) {
    if (moves.length === 0) { win.say("no names changed"); return; }
    win.run(Terminus.shArgv(Terminus.bulkRenameApply(moves)), (code) => {
      const to = {};
      for (const m of moves) to[m[0]] = m[1];
      const move = (o) => {
        const c = {};
        for (const k in o) c[to[k] || k] = o[k];
        return c;
      };
      win.marks = move(win.marks);
      win.tags = move(win.tags);
      win.thumbs = move(win.thumbs);
      if (win.picked.length > 0) win.picked = win.picked.map((q) => to[q] || q);
      if (to[win.cmpPath]) win.cmpPath = to[win.cmpPath];
      if (to[win.path]) { win.path = to[win.path]; win.want = win.path; }
      win.say(code !== 0 ? "some could not be renamed — a name was taken" : moves.length + " renamed");
      win.refresh();
    });
  }

  // ── somewhere else ────────────────────────────────────────────────────
  // terminus' directory picker, then terminus' copy — rsync, keeping both when
  // a name is taken ("name (1).jpg"), never writing over anything.
  function sendTo(ps, move) {
    if (ps.length === 0) return;
    const fm = win.fileManager;
    if (!fm) { win.say("no file manager to ask"); return; }
    const ok = fm.choose(true, win.dir, (paths) => {
      if (paths.length === 0) return;
      const dest = String(paths[0]);
      if (dest === win.dir) { win.say("they are already here"); return; }
      win.say((move ? "moving " : "copying ") + win.some(ps) + "…", 60000);
      win.run(Terminus.shArgv(Terminus.transferCommand(ps, dest, move, Terminus.CLASH.keep)), (code) => {
        win.say(code !== 0 ? "could not " + (move ? "move " : "copy ") + win.some(ps)
                : win.some(ps) + (move ? " moved to " : " copied to ") + dest.replace(Paths.home(), "~"));
        if (move && code === 0) win.dropRows(ps);
      });
    });
    if (!ok) win.say("the file picker is busy with another request");
  }

  // ── turning the files themselves ──────────────────────────────────────
  // terminus' rotate, onto the files — what the gallery offers, for a row of
  // sideways photos. On a picture being edited here it would be lost under
  // the edit, so that one is left to the edit's own turn.
  function rotateFiles(ps, deg) {
    const ok = ps.filter((p) => V.writable(p) && !Terminus.isVideo(Terminus.basename(p)) && !(p === win.path && win.edited));
    if (ok.length === 0) { win.say("these cannot be turned in place"); return; }
    win.keepCopies(ok, () => win.run(["sh", "-c", ok.map((p) => Terminus.rotateCommand(p, deg)).join(" && ")], (code) => {
      if (code !== 0) { win.say("could not turn " + win.some(ok)); return; }
      const next = Object.assign({}, win.thumbs);
      for (const p of ok) delete next[p];
      win.thumbs = next;
      for (const p of ok) win.wantThumb(p);
      if (ok.indexOf(win.path) >= 0) win.reloadTick++;
      win.say("turned " + win.some(ok) + "  \u00b7  u turns " + (ok.length === 1 ? "it" : "them") + " back");
    }));
  }
  function convertFiles(ps, ext) {
    if (ps.length === 0) return;
    win.run(Terminus.shArgv(Terminus.convertCommand(ps, ext)), (code) => {
      win.say(code === 0 ? win.some(ps) + " converted to " + ext + " beside " + (ps.length === 1 ? "it" : "them")
              : "could not convert " + win.some(ps));
      win.refresh();
    });
  }

  // ── the map ───────────────────────────────────────────────────────────
  // The pictures shown that say where they were taken, as pins (MapView.qml,
  // loaded by url while the window is in its map mode). Esc goes back to
  // the mode it came from.
  property string mapFrom: ""
  property var mapFocus: null
  readonly property var mapPoints: {
    const out = [];
    for (const r of win.rows) {
      const m = win.meta[r.path];
      if (m && m.lat !== null && m.lat !== undefined) out.push({ lat: m.lat, lon: m.lon, path: r.path });
    }
    return out;
  }
  function openMap(at) {
    if (win.rows.length === 0 || !win.mgr) return;
    const go = () => {
      if (win.mapPoints.length === 0 && !at) { win.say("none of these say where they were taken"); return; }
      if (win.mode !== "map") win.mapFrom = win.mode;
      win.mapFocus = at || null;
      win.mode = "map";
    };
    if (!win.exiftool) {
      if (at) go(); else win.say("the map reads where they were taken with exiftool — pacman -S perl-image-exiftool", 8000);
      return;
    }
    const missing = win.allRows.some((r) => { const m = win.meta[r.path]; return !m || m.sig !== win.mgr.sigOf(r); });
    if (missing) { win.say("reading where they were taken…", 60000); win.needMeta(() => { win.say(""); go(); }); }
    else go();
  }

  // ── the clipboard ─────────────────────────────────────────────────────
  // ctrl+v: whatever it holds, looked at. Files copied anywhere open as a
  // picked set; a picture with no file (a screenshot, a browser's copy) is
  // written to the runtime directory and opened from there, for Save New
  // to keep — nothing lands in a directory of yours unasked.
  function pasteLook() {
    const stem = Paths.runtimeDir() + "/picasso-view/clipboard-" + Date.now();
    win.capture(["sh", "-c", V.clipboardLookCommand(stem), "sh", stem], (text) => {
      const got = V.parseClipboardLook(text);
      const pics = got.paths.filter((p) => Terminus.isImage(Terminus.basename(p)));
      if (pics.length === 0) { win.say("no picture on the clipboard"); return; }
      win.load(pics, "view");
      if (got.kind === "image") win.say("from the clipboard — ctrl+shift+s keeps it", 6000);
    });
  }
  // The gallery's Paste: into the directory shown, as terminus pastes — files
  // copied in beside each other, a picture written as "Pasted image.png".
  function pasteHere() {
    if (win.dir === "" || win.picked.length > 0) return;
    const d = win.dir;
    win.capture(["sh", "-c", Terminus.clipboardPasteCommand(d)], (text) => {
      const got = V.parseClipboardLook(text);
      if (got.kind === "wrote") { win.want = Terminus.joinPath(d, got.paths[0]); win.say("pasted"); win.refresh(); return; }
      if (got.kind !== "uris") { win.say("nothing on the clipboard to paste"); return; }
      win.run(Terminus.shArgv(Terminus.transferCommand(got.paths, d, false, Terminus.CLASH.keep)), (code) => {
        win.say(code === 0 ? "pasted " + win.some(got.paths) : "could not paste");
        win.refresh();
      });
    });
  }

  // ── without what the camera wrote ─────────────────────────────────────
  // The time, the camera and — the one that matters — where it was taken,
  // dropped from a copy that is going to somebody else.
  function copyClean() {
    if (win.path === "") return;
    win.run(["sh", "-c", 'magick -- "$1[0]" -auto-orient -strip png:- | wl-copy --type image/png', "sh", win.path],
      (code) => win.say(code === 0 ? "copied, without its metadata" : "could not copy it"));
  }
  function saveClean(ps) {
    if (ps.length === 0) return;
    const cmds = ps.map((p) => {
      const name = V.writable(p) ? V.editedName(p, "clean") : V.editedName(p, "clean").replace(/\.[^.]+$/, ".png");
      return Terminus.convertIntoCommand(p, Terminus.dirname(p), name, true);
    });
    let left = cmds.length, bad = 0;
    for (const c of cmds) win.run(Terminus.shArgv(c), (code) => {
      if (code !== 0) bad++;
      if (--left > 0) return;
      win.say(bad > 0 ? "could not write every copy" : (ps.length === 1 ? "a clean copy beside it" : ps.length + " clean copies beside them"));
      win.refresh();
    });
  }

  // ── made from it, beside it ───────────────────────────────────────────
  // A new file next to the picture, never over it — enhanced (ImageMagick),
  // the subject cut out (rembg), or four times the size (Real-ESRGAN) — and
  // then shown beside the original, to judge. The one not wanted goes to the
  // trash like any other.
  function makeBeside(kind) {
    if (win.path === "" || !win.stillOnly()) return;
    const src = win.path, tools = win.mgr ? win.mgr.tools : {};
    const up = tools["realesrgan-ncnn-vulkan"] ? "realesrgan-ncnn-vulkan" : (tools["upscayl-bin"] ? "upscayl-bin" : "");
    const k = {
      enhance: { tag: "enhanced", cmd: V.enhanceCommand(), keep: V.writable(src), said: "enhancing…" },
      cutout:  { tag: "cutout", cmd: V.cutoutCommand(), keep: false, said: "cutting out the subject — the first time fetches its model…" },
      upscale: { tag: "x4", cmd: V.upscaleCommand(up), keep: false, said: "upscaling — a minute, for a big picture…" }
    }[kind];
    if (!k) return;
    let name = V.editedName(src, k.tag);
    if (!k.keep) name = name.replace(/\.[^.]+$/, ".png");
    name = Terminus.freeNameKeeping(win.allRows, name);
    const dest = Terminus.joinPath(Terminus.dirname(src), name);
    win.say(k.said, 600000);
    win.run(["sh", "-c", k.cmd, "sh", src, dest], (code) => {
      if (code !== 0) { win.say("could not make it  \u00b7  " + kind + " failed"); return; }
      win.say(name + " beside it  \u00b7  shown on the right", 6000);
      if (win.picked.length > 0) win.picked = win.picked.concat([dest]);
      win.compareAfter = dest;
      win.want = src;
      win.startMode = "view";
      win.list();
    });
  }

  // ── for sending ───────────────────────────────────────────────────────
  // terminus' export: small, stripped, a format for the web — beside each
  // one ("-web"), or into a directory terminus' picker is asked for.
  function exportFor(ps, preset, ask) {
    ps = ps.filter((p) => !Terminus.isVideo(Terminus.basename(p)));
    if (ps.length === 0) return;
    const go = (dest) => {
      win.say("exporting " + win.some(ps) + "…", 600000);
      win.run(Terminus.shArgv(Terminus.exportCommand(ps, dest, preset.ext, preset.edge, preset.q, dest === "" ? "web" : "")), (code) => {
        win.say(code === 0 ? win.some(ps) + " exported" + (dest === "" ? " beside " + (ps.length === 1 ? "it" : "them")
                                                       : " to " + dest.replace(Paths.home(), "~"))
                           : "could not export every one");
        win.refresh();
      });
    };
    if (!ask) { go(""); return; }
    const fm = win.fileManager;
    if (!fm) { win.say("no file manager to ask"); return; }
    if (!fm.choose(true, win.dir, (paths) => { if (paths.length > 0) go(String(paths[0])); }))
      win.say("the file picker is busy with another request");
  }

  // ── a contact sheet ───────────────────────────────────────────────────
  // The pictures on one page, a grid with their names, written where the
  // save dialog says.
  function contactSheet(ps) {
    const pics = ps.filter((p) => !Terminus.isVideo(Terminus.basename(p)));
    if (pics.length === 0) return;
    const fm = win.fileManager;
    if (!fm) { win.say("no file manager to ask"); return; }
    const base = (win.picked.length > 0 ? "Picked" : (Terminus.basename(win.dir) || "Pictures")) + " contact sheet.jpg";
    const ok = fm.choose(false, win.dir, (paths) => {
      if (paths.length === 0) return;
      let out = String(paths[0]);
      if (!/\.(png|jpe?g|webp|pdf)$/i.test(out)) out += ".jpg";
      win.say("laying out " + pics.length + " pictures…", 600000);
      win.run(["sh", "-c", V.contactSheetCommand(V.contactCols(pics.length), 360, true), "sh", out].concat(pics), (code) => {
        win.say(code === 0 ? "contact sheet saved  \u00b7  " + out.replace(Paths.home(), "~") : "could not make the contact sheet");
        win.refresh();
      });
    }, Terminus.freeNameKeeping(win.allRows, base));
    if (!ok) win.say("the file picker is busy with another request");
  }

  // ── places ────────────────────────────────────────────────────────────
  // Where to go from here: the pictures directories, terminus' bookmarks (its
  // own file, read as it is now), and the directories last looked at.
  FileView {
    id: bookmarkFile
    path: Quickshell.statePath("terminus-bookmarks")
    blockLoading: true
    printErrors: false
  }
  function placeRows() {
    bookmarkFile.reload();
    const marks = String(bookmarkFile.text() || "").split("\n").map((l) => l.trim()).filter((l) => l !== "");
    const tilde = (d) => d.replace(Paths.home(), "~");
    const row = (d, icon) => ({ text: Terminus.basename(d) || "/", icon: icon, act: "go", dir: d, hint: tilde(Terminus.dirname(d)),
                                mark: d === win.dir });
    const sep = { isSeparator: true };
    const own = [Picasso.picturesDir, Picasso.shotDir, Picasso.dir].filter((d, i, a) => d !== "" && a.indexOf(d) === i);
    let out = own.map((d) => row(d, "\uf03e"));
    if (marks.length > 0) out = out.concat([sep, { text: "Bookmarks", enabled: false }]).concat(marks.map((d) => row(d, "\uf02e")));
    const rec = (win.mgr ? win.mgr.recent : []).filter((d) => own.indexOf(d) < 0 && marks.indexOf(d) < 0);
    if (rec.length > 0) out = out.concat([sep, { text: "Lately", enabled: false }]).concat(rec.map((d) => row(d, "\uf1da")));
    return out;
  }

  // ── reading the text in it ────────────────────────────────────────────
  // tesseract, on the selection when there is one (the same grab a save
  // makes) or on the whole picture; the text to the clipboard.
  function readText() {
    if (!win.loaded || !win.stillOnly()) return;
    const done = (code) => win.say(code === 0 ? "the text is on the clipboard"
      : code === 127 ? "reading text needs tesseract — pacman -S tesseract tesseract-data-eng"
      : code === 3 ? "no text found" : "could not read it", code === 127 ? 9000 : 3000);
    const ocr = (png) => win.run(["sh", "-c", V.ocrCommand(png), "sh", png], done);
    win.say("reading…", 30000);
    if (win.crop && win.fallback === "") {
      win.grabEdit((tmp) => { if (tmp === "") win.say("could not render the selection"); else ocr(tmp); });
      return;
    }
    const tmp = Paths.runtimeDir() + "/picasso-view-ocr-" + Date.now() + ".png";
    const src = win.fallback !== "" ? win.fallback : win.path + "[0]";
    win.run(["sh", "-c", 'magick -- "$2" "$1"', "sh", tmp, src], (code) => {
      if (code !== 0) { win.say("could not read it"); return; }
      ocr(tmp);
    });
  }

  // ── dragged out, as files ─────────────────────────────────────────────
  // The marked pictures when the one picked up is among them. Under the
  // pointer, the suite's drag card (terminus/DragCard.qml): one picture
  // rides as its thumbnail and name, several as a count, as in terminus.
  // The card is grabbed before the drag starts — the drag reads its picture
  // as it starts.
  function dragOut(item, p) {
    const ps = win.targets(p);
    item.Drag.mimeData = { "text/uri-list": ps.map((q) => Strings.fileUrl(q)).join("\r\n") + "\r\n" };
    const th = ps.length === 1 ? (win.thumbs[p] || "") : "";
    dragCard.thumb = th !== "" ? Strings.fileUrl(th) : "";
    dragCard.glyph = Terminus.isVideo(Terminus.basename(p)) ? "\uf03d" : "\uf03e";
    dragCard.ink = Zenon.cyan;
    dragCard.label = win.some(ps);
    dragCard.count = ps.length;
    item.Drag.hotSpot = Qt.point(16, dragCard.height / 2);
    dragCard.picture((url) => {
      item.Drag.imageSource = url;
      item.Drag.active = true;
    });
  }
  // ── fullscreen ────────────────────────────────────────────────────────
  // The picture alone: the compositor's fullscreen, and nothing of the
  // window's own around it — no bar, no strip, no panel, black behind. The
  // bars come back as they were on the way out.
  property bool full: false
  property bool chromeBefore: true
  // The bar and the strip are still there, off the edges: they slide in
  // while the pointer is at the top or bottom edge, and over them.
  readonly property real peekZone: 24
  readonly property bool peekTop: win.full && win.mode === "view"
    && (barHover.hovered || edgeHover.hovered && edgeHover.point.position.y < win.peekZone)
  readonly property bool peekBottom: win.full && strip.can
    && (stripHover.hovered || navTabs.itemAt(2) !== null && navTabs.itemAt(2).hot
        || edgeHover.hovered && edgeHover.point.position.y > canvas.height - win.peekZone)
  function fullscreen() { if (win.mode === "view") win.full = !win.full; }
  onFullChanged: {
    Hyprland.dispatch("hl.dsp.window.fullscreen()");
    if (win.full) {
      win.chromeBefore = win.chrome;
      win.chrome = false;
      win.panelShown = false;
      win.infoShown = false;
    } else win.chrome = win.chromeBefore;
  }

  // ── background ────────────────────────────────────────────────────────
  // Through the picker's own card. A crop cannot travel as a look, so a
  // cropped edit is rendered to a scratch png and the card opens on that —
  // written into the background directory only if the card is APPLIED (see
  // PicassoPopup.focusAdopt); closed, the render is thrown away and nothing
  // was saved anywhere.
  function toBackground() {
    if (win.path === "" || !win.loaded || !win.stillOnly()) return;
    if (win.crop) {
      if (win.fallback !== "") { win.say("this is a preview copy — the original cannot be edited here"); return; }
      win.grabEdit((tmp) => {
        if (tmp === "") { win.say("could not render the selection"); return; }
        Picasso.setAsWallpaper(tmp, {}, {
          dir: Picasso.dir,
          name: V.editedName(win.path, "background").replace(/\.[^.]+$/, ".png")
        });
      });
      return;
    }
    Picasso.setAsWallpaper(win.path, Art.lookDiff(win.look));
  }

  // ── saving the edit ───────────────────────────────────────────────────
  // The edit is baked by grabbing a Scene at the picture's own size (see the
  // bake loader at the bottom), written as png, then converted to the target
  // by ImageMagick — which keeps a jpeg a jpeg at a quality worth keeping,
  // where Qt's own writer would drop it to 75.
  property var bakeThen: null
  property string bakeDest: ""
  // set instead of a destination: the grab itself is wanted — a png in the
  // runtime directory, handed over and left to the caller (the clipboard)
  property var bakeRaw: null

  function grabEdit(then) {
    if (win.fallback !== "" || bakeLoader.active) return;
    win.bakeRaw = then;
    bakeLoader.active = true;
  }

  function bake(dest, then) {
    if (win.fallback !== "") { win.say("this is a preview copy — the original cannot be edited here"); return; }
    if (bakeLoader.active) return;
    win.bakeDest = dest;
    win.bakeThen = then;
    win.say("saving…");
    bakeLoader.active = true;
  }
  function baked(tmp) {
    if (win.bakeRaw) {
      const raw = win.bakeRaw;
      win.bakeRaw = null;
      bakeLoader.active = false;
      raw(tmp);
      return;
    }
    const dest = win.bakeDest, then = win.bakeThen;
    bakeLoader.active = false;
    if (tmp === "") { win.say("could not render the edit"); if (then) then(false); return; }
    win.run(["sh", "-c", 'magick "$1" -quality 92 "$2" && rm -f "$1"', "sh", tmp, dest], (code) => {
      if (code !== 0) { win.say("could not save to " + dest); if (then) then(false); return; }
      win.say("saved · " + dest.replace(Paths.home(), "~"));
      win.afterSave(dest);
      if (then) then(true);
    });
  }

  function save() {
    if (!win.edited || !win.stillOnly()) return;
    const dest = V.writable(win.path) ? win.path
      : Terminus.dirname(win.path) + "/" + V.editedName(win.path).replace(/\.[^.]+$/, ".png");
    const go = () => win.bake(dest, (ok) => { if (ok) { win.resetEdit(); if (dest === win.path) win.say("saved  \u00b7  u puts the original back", 6000); } });
    if (dest === win.path) win.keepCopies([dest], go); else go();
  }
  function saveNew() {
    if ((!win.edited && !win.scratch) || !win.stillOnly()) return;
    const fm = win.fileManager;
    if (!fm) { win.say("no file manager to ask"); return; }
    const ok = fm.choose(false, win.dir, (paths) => {
      if (paths.length === 0) return;
      let f = String(paths[0]);
      if (!/\.(png|jpe?g|webp|bmp|tiff?)$/i.test(f)) f += ".png";
      win.bake(f, (done) => { if (done) win.resetEdit(); });
    }, win.scratch ? "Pasted image.png" : V.editedName(win.path));
    if (!ok) win.say("the file picker is busy with another request");
  }

  // A file was written — by a save or by the annotator. Its thumbnail is
  // stale; the picture on screen is stale; and a new file is a new row.
  function afterSave(file) {
    const next = Object.assign({}, win.thumbs);
    delete next[file];
    win.thumbs = next;
    win.reloadTick++;
    if (win.picked.length > 0 && win.picked.indexOf(file) < 0) win.picked = win.picked.concat([file]);
    win.want = file;
    win.startMode = win.mode;
    win.list();
  }

  // ── the slideshow ─────────────────────────────────────────────────────
  Timer {
    interval: win.slideSecs * 1000
    repeat: true
    // a video is not timed: it plays to its end, then the show moves on
    running: win.playing && win.mode === "view" && !win.edited && !win.isVid
    onTriggered: win.step(1)
  }
  onPlayingChanged: if (win.playing) win.say("slideshow, every " + win.slideSecs + " s"
                                            + (win.shuffle ? ", shuffled" : "") + "  \u00b7  [ ] slower, faster")
  function pace(d) {
    const at = V.SLIDE_SECS.indexOf(win.slideSecs);
    const to = V.SLIDE_SECS[Math.max(0, Math.min(V.SLIDE_SECS.length - 1, (at < 0 ? 1 : at) + d))];
    if (win.mgr) win.mgr.setSlides(to, win.shuffle);
    win.say("slideshow, every " + to + " s");
  }
  function setShuffle(on) {
    if (win.mgr) win.mgr.setSlides(win.slideSecs, on);
    win.say(on ? "slideshow shuffled" : "slideshow in order");
  }

  // ── comparing ─────────────────────────────────────────────────────────
  // A second picture beside this one, at the same part of it and the same
  // size: zoom or pan either and both follow. Itself only a picture — the
  // edit, the crop and the keys stay with the left one.
  property bool compare: false
  property string cmpPath: ""
  readonly property int cmpIndex: win.compare ? V.indexOfPath(win.rows, win.cmpPath) : -1
  function startCompare(other) {
    if (win.compare && !other) { win.compare = false; return; }
    if (win.rows.length < 2) { win.say("nothing to compare it with"); return; }
    const m = win.markedPaths().filter((p) => V.indexOfPath(win.rows, p) >= 0);
    if (other) win.cmpPath = other;
    else if (m.length === 2) {
      if (m[0] !== win.path) win.go(V.indexOfPath(win.rows, m[0]));
      win.cmpPath = m[1];
    } else win.cmpPath = win.rows[win.index + 1 < win.rows.length ? win.index + 1 : win.index - 1].path;
    if (win.cmpPath === win.path) { win.say("that is the same picture"); return; }
    win.compare = true;
    win.mode = "view";
    win.say("comparing  \u00b7  shift+\u2190 \u2192 the right one, tab swaps, v ends it", 5000);
  }
  function stepCompare(d) {
    const n = win.rows.length;
    let i = win.cmpIndex;
    for (let k = 0; k < n; ++k) {
      i = Math.max(0, Math.min(n - 1, i + d));
      if (i !== win.index) break;
    }
    if (i >= 0 && i !== win.index) win.cmpPath = win.rows[i].path;
  }
  function swapCompare() {
    const b = win.cmpPath;
    if (b === "") return;
    const a = win.path;
    win.leave(() => { win.go(V.indexOfPath(win.rows, b), true); win.cmpPath = a; });
  }
  onCompareChanged: Qt.callLater(() => win.refit(true))

  DragCard { id: dragCard }

  // ── the keys ──────────────────────────────────────────────────────────
  Item {
    id: keys
    anchors.fill: parent
    focus: true
    Keys.onReleased: (e) => {
      if (!e.isAutoRepeat && win.panRelease(e.key)) e.accepted = true;
      if (e.key === Qt.Key_Backslash && !e.isAutoRepeat) { win.peekOriginal = false; e.accepted = true; }
      if (e.key === Qt.Key_Control && !e.isAutoRepeat) { loupeWait.stop(); stage.loupeOn = false; }
    }
    Keys.onPressed: (e) => {
      if (menu.open) {
        if (e.key === Qt.Key_Escape) { menu.open = false; e.accepted = true; }
        return;
      }
      if (win.mode === "annotate" || confirm.open) return;
      if (propsBox.open) {
        e.accepted = true;
        if (e.key === Qt.Key_Escape) { if (propsCard.tab === 1) propsCard.tab = 0; else propsBox.open = false; }
        else propsCard.handleKey(e.key);
        return;
      }
      const ctrl = e.modifiers & Qt.ControlModifier, shift = e.modifiers & Qt.ShiftModifier;
      const alt = e.modifiers & Qt.AltModifier;
      const k = e.key;
      const gallery = win.mode === "gallery";
      // ctrl alone, held: the loupe; with anything else, it is a shortcut
      if (k === Qt.Key_Control) { if (!e.isAutoRepeat) loupeWait.restart(); e.accepted = true; return; }
      loupeWait.stop();
      stage.loupeOn = false;
      if (win.mode === "map") {
        e.accepted = true;
        const m = mapLoader.item;
        if (k === Qt.Key_Escape || k === Qt.Key_M || k === Qt.Key_Q) win.mode = win.mapFrom !== "" ? win.mapFrom : "gallery";
        else if (!m) return;
        else if (k === Qt.Key_Plus || k === Qt.Key_Equal) m.zoomBy(1);
        else if (k === Qt.Key_Minus) m.zoomBy(-1);
        else if (k === Qt.Key_0) m.fit();
        else if (k === Qt.Key_Left || k === Qt.Key_H) m.panBy(160, 0);
        else if (k === Qt.Key_Right || k === Qt.Key_L) m.panBy(-160, 0);
        else if (k === Qt.Key_Up || k === Qt.Key_K) m.panBy(0, 160);
        else if (k === Qt.Key_Down || k === Qt.Key_J) m.panBy(0, -160);
        else if (k === Qt.Key_G) win.mode = "gallery";
        else e.accepted = false;
        return;
      }
      // the picture spoken about: the one shown, or the gallery's cursor's
      // (nothing, when that is on a directory)
      const cur = gallery ? win.cursorPath() : win.path;
      e.accepted = true;
      if (ctrl && k === Qt.Key_C) {
        if (shift) win.copyPath();
        else if (gallery) win.copyFiles(win.targets(cur));
        else win.copyImage();
        return;
      }
      if (ctrl && k === Qt.Key_V) { win.pasteLook(); return; }
      if (ctrl && k === Qt.Key_A) { win.markAll(); return; }
      if (ctrl && k === Qt.Key_F) { win.openFilter(); return; }
      if (ctrl && k === Qt.Key_Z) { win.undo(); return; }
      if (ctrl && k === Qt.Key_S) { shift ? win.saveNew() : win.save(); return; }
      // ctrl + - 0: the zoom, as terminus has them — the tiles' in the
      // gallery, the picture's on a picture
      if (ctrl && (k === Qt.Key_Plus || k === Qt.Key_Equal || k === Qt.Key_Minus || k === Qt.Key_0)) {
        const dz = k === Qt.Key_Minus ? -1 : k === Qt.Key_0 ? 0 : 1;
        if (gallery) dz === 0 ? win.gzoomSet(1) : win.gzoomBy(dz * 0.1);
        else if (win.mode === "view") win.zoomStep(dz);
        return;
      }
      if (ctrl) { e.accepted = false; return; }

      if (k === Qt.Key_Escape) {
        if (win.editingColor !== "") win.editingColor = "";
        // a selection dragged out on the picture is let go of; a crop set
        // up in the edit panel stays, staged, for the panel's Save
        else if (win.cropping) { if (!win.cropStaged) win.crop = null; win.cropping = false; }
        else if (win.full) win.full = false;
        else if (win.compare) win.compare = false;
        else if (win.markCount > 0) win.marks = ({});
        else if (win.dupes) win.leaveDupes();
        else if (win.filterText !== "") win.setFilter("");
        else if (win.infoShown) win.infoShown = false;
        else if (win.panelShown) win.panelShown = false;
        // a picture goes back to the gallery it was opened from — its directory,
        // or the picked pictures. And there it stops: Escape never closes the
        // window (the user asked) — q, or the window's own close, does.
        else if (!gallery && !win.solo && win.galleryItems.length > 0) win.mode = "gallery";
        return;
      }
      if (k === Qt.Key_Q) { win.close(); return; }
      // terminus' key for the properties card
      if (alt && (k === Qt.Key_Return || k === Qt.Key_Enter)) {
        if (gallery) {
          const it = win.galleryItems[win.gidx];
          win.showProps(it && it.isDir ? [it.path] : (cur !== "" ? win.targets(cur) : [win.dir]));
        } else if (win.path !== "") win.showProps([win.path]);
        return;
      }

      // the same in both
      if (k === Qt.Key_Slash) win.openFilter();
      else if (k === Qt.Key_U) win.undo();
      // as terminus has them: d to the trash, D for good (after asking)
      else if (k === Qt.Key_D) {
        const ps = gallery ? win.targets(cur) : (cur !== "" ? [cur] : []);
        if (shift) win.deleteForever(ps); else win.trash(ps);
      }
      else if (k === Qt.Key_Apostrophe) win.showMenu(placesTool.mapToItem(null, 0, placesTool.height + 4), "places", "");
      else if (k === Qt.Key_Asterisk) win.toggleStar(cur);
      else if (k === Qt.Key_T) win.editTags(cur);
      else if (k === Qt.Key_F2) win.bulkRename(win.targets(cur));
      else if (k === Qt.Key_X) win.toggleMark(cur);
      else if (k === Qt.Key_V) win.startCompare();
      // the gallery's Delete is the marked pictures' when there are some;
      // the picture's is the picture's
      // shift: for good, after asking
      else if (k === Qt.Key_Delete && shift) win.deleteForever(gallery ? win.targets(cur) : (cur !== "" ? [cur] : []));
      else if (k === Qt.Key_Delete) win.trash(gallery ? win.targets(cur) : (cur !== "" ? [cur] : []));
      else if (gallery) {
        const cols = win.gcols;
        if (k === Qt.Key_Left || k === Qt.Key_H) win.gallerySeek(-1);
        else if (k === Qt.Key_Right || k === Qt.Key_L) win.gallerySeek(1);
        else if (k === Qt.Key_Up || k === Qt.Key_K) win.gallerySeek(-cols);
        else if (k === Qt.Key_Down || k === Qt.Key_J) win.gallerySeek(cols);
        else if (k === Qt.Key_M) win.openMap();
        else if (k === Qt.Key_Plus || k === Qt.Key_Equal) win.gzoomBy(0.1);
        else if (k === Qt.Key_Minus) win.gzoomBy(-0.1);
        else if (k === Qt.Key_0) win.gzoomSet(1);
        else if (k === Qt.Key_Home) win.gallerySel(0);
        else if (k === Qt.Key_End) win.gallerySel(win.galleryItems.length - 1);
        else if (k === Qt.Key_Return || k === Qt.Key_Enter) win.galleryOpen(win.gidx);
        else if (k === Qt.Key_Backspace) win.goUp();
        else if (k === Qt.Key_G && win.rows.length > 0) win.mode = "view";
        else if (k === Qt.Key_S && win.rows.length > 0) { win.playing = true; win.mode = "view"; }
        // marked, and on to the next, for going down a directory picking
        else if (k === Qt.Key_Space) { if (cur !== "") win.toggleMark(cur); win.gallerySeek(1); }
        else e.accepted = false;
      }
      else if (win.compare && shift && (k === Qt.Key_Left || k === Qt.Key_Right)) win.stepCompare(k === Qt.Key_Left ? -1 : 1);
      // kept here either way: let go of, Tab walks the focus into the filter
      else if (k === Qt.Key_Tab) { if (win.compare) win.swapCompare(); }
      else if (k === Qt.Key_Backslash) { if (!e.isAutoRepeat && win.edited) win.peekOriginal = true; }
      // zoomed in, ← → h l move about the picture, as ↑ ↓ k j do; space
      // and page up/down still go to the next and the last
      // (only when it is wider than the stage — with nowhere to go sideways
      // they still step)
      else if (!win.fitted && win.tw * win.vz > stage.width + 1 && (k === Qt.Key_Left || k === Qt.Key_H)) win.panKey(k, 1, 0, e.isAutoRepeat);
      else if (!win.fitted && win.tw * win.vz > stage.width + 1 && (k === Qt.Key_Right || k === Qt.Key_L)) win.panKey(k, -1, 0, e.isAutoRepeat);
      // backspace is back to the gallery, as the bar's back arrow is
      else if (k === Qt.Key_Backspace) { if (!win.solo && win.galleryItems.length > 0) win.mode = "gallery"; }
      else if (k === Qt.Key_Left || k === Qt.Key_H || k === Qt.Key_PageUp) win.step(-1);
      else if (k === Qt.Key_Right || k === Qt.Key_L || k === Qt.Key_PageDown || k === Qt.Key_Space) win.step(1);
      else if (k === Qt.Key_Home) win.go(0);
      else if (k === Qt.Key_End) win.go(win.rows.length - 1);
      // alt+j puts the strip away, down out of sight; alt+k brings it back
      else if (alt && k === Qt.Key_J) { if (win.mgr) win.mgr.setStrip(false); }
      else if (alt && k === Qt.Key_K) { if (win.mgr) win.mgr.setStrip(true); }
      else if (k === Qt.Key_Up || k === Qt.Key_K) win.panKey(k, 0, 1, e.isAutoRepeat);
      else if (k === Qt.Key_Down || k === Qt.Key_J) win.panKey(k, 0, -1, e.isAutoRepeat);
      else if (k === Qt.Key_Plus || k === Qt.Key_Equal) win.zoomStep(1);
      else if (k === Qt.Key_Minus) win.zoomStep(-1);
      else if (k === Qt.Key_0) win.zoomStep(0);
      else if (k === Qt.Key_1) win.zoomTo(1, undefined, undefined, Zenon.normal);
      // the picture at its own size — and again, back to the fit
      else if ((k === Qt.Key_Return || k === Qt.Key_Enter) && !win.isVid) {
        if (!win.fitted && Math.abs(win.vz - 1) < 0.001) { win.fitted = true; win.refit(true); win.sayZoom(); }
        else win.zoomTo(1, undefined, undefined, Zenon.normal);
      }
      else if (k === Qt.Key_2) win.zoomTo(2, undefined, undefined, Zenon.normal);
      else if (k === Qt.Key_Z) win.zoomLock = !win.zoomLock;
      else if (k === Qt.Key_G) win.mode = "gallery";
      else if (k === Qt.Key_E) { if (win.stillOnly()) win.panelShown = !win.panelShown; }
      else if (k === Qt.Key_C) { if (shift) win.trimBorders(); else win.cropTool(); }
      else if (k === Qt.Key_R) { win.panelShown = true; win.turn(shift ? -90 : 90); }
      else if (k === Qt.Key_M) {
        if (win.isVid) { win.muted = !win.muted; win.say(win.muted ? "muted" : "sound on"); }
        else { win.panelShown = true; win.setLook("mirror", !win.look.mirror); }
      }
      else if (k === Qt.Key_A) win.annotate();
      else if (k === Qt.Key_W && shift) stage.monitorsShown = !stage.monitorsShown;
      else if (k === Qt.Key_W) win.toBackground();
      else if (k === Qt.Key_S) win.playing = !win.playing;
      else if (k === Qt.Key_BracketLeft) win.pace(1);
      else if (k === Qt.Key_BracketRight) win.pace(-1);
      else if (k === Qt.Key_P) win.gifPause();
      else if (k === Qt.Key_Comma) win.gifStep(-1);
      else if (k === Qt.Key_Period) win.gifStep(1);
      else if (k === Qt.Key_Y) win.copyColour();
      else if (k === Qt.Key_I) { if (win.mode === "view") win.infoShown = !win.infoShown; }
      else if (k === Qt.Key_B) win.chrome = !win.chrome;
      else if (k === Qt.Key_F) win.fullscreen();
      else if (k === Qt.Key_O) win.reveal();
      else e.accepted = false;
    }
  }

  // the gallery's cursor, when it is on a picture
  function cursorPath() {
    const it = win.galleryItems[win.gidx];
    return it && !it.isDir && !it.isFill ? it.path : "";
  }
  function openFilter() {
    win.filterOpen = true;
    filterField.text = win.filterText;
    Qt.callLater(() => { filterField.forceActiveFocus(); filterField.selectAll(); });
  }

  // ── an animation, held still ──────────────────────────────────────────
  function gifPause() {
    if (win.isVid) { if (win.vid) win.vid.toggle(); return; }
    if (!win.animated || !win.img || !(win.img.frameCount > 1)) return;
    win.gifPaused = !win.gifPaused;
  }
  function gifStep(d) {
    if (win.isVid) { if (win.vid) win.vid.seekBy(d * 5000); return; }
    const a = win.img;
    if (!win.animated || !a || !(a.frameCount > 1)) return;
    win.gifPaused = true;
    a.currentFrame = (a.currentFrame + d + a.frameCount) % a.frameCount;
  }

  // ── the pixel under the pointer ───────────────────────────────────────
  // Zoomed in past 400% — where a picture's pixels are drawn sharp, one
  // colour each — the one under the pointer is read off the picture itself
  // (see the probe on the stage) and shown beside it; y copies it.
  property var pixel: null
  readonly property bool pixelClose: win.loaded && win.vz >= 4 && !win.vector && !win.animated && !win.isVid
    && win.straighten === 0
    && win.fallback === "" && !win.cropping && !win.peekOriginal
  function copyColour() {
    if (!win.pixel) return;
    Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | wl-copy", "sh", win.pixel.hex]);
    win.say(win.pixel.hex + " copied");
  }

  function annotate() {
    if (win.path === "" || win.fallback !== "" || !win.stillOnly()) return;
    if (win.edited) { win.say("save or reset the edit first — marks go on the saved picture"); return; }
    win.playing = false;
    win.mode = "annotate";
  }
  onModeChanged: {
    const was = win.lastMode;
    win.lastMode = win.mode;
    if (was === "gallery" && win.mode === "view") win.flyIn();
    else if (was === "view" && win.mode === "gallery") win.flyOut();
    if (win.mode !== "view" && win.full) win.full = false;
    if (win.mode !== "annotate") Qt.callLater(() => keys.forceActiveFocus());
    if (win.mode === "view") Qt.callLater(() => win.refit(false));
    if (win.mode === "gallery") {
      // back from a picture, the cursor is on it — unless it was left on a directory
      const on = win.galleryItems[win.gidx];
      if (win.index >= 0 && (!on || !on.isDir)) { const at = win.itemOfPath(win.path); if (at >= 0) win.gidx = at; }
      Qt.callLater(() => grid.positionViewAtIndex(win.gidx, GridView.Contain));
    }
  }

  // ── pieces ────────────────────────────────────────────────────────────
  // A glyph button in the bar, named in a tooltip under it — see
  // morpheus/WindowTip, one for the whole window.
  component Tool: Rectangle {
    id: tool
    property string glyph: ""
    property string name: ""
    property string key: ""
    property bool on: false
    property bool live: true
    signal hit()
    // a right click — the slideshow's pace and shuffle
    signal alt()
    width: 34; height: 34; radius: Zenon.windowRadius
    opacity: tool.live ? 1 : 0.35
    color: tool.on ? Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.20)
      : (toolMa.containsMouse ? Zenon.wash(0.06) : "transparent")
    border.width: tool.on ? 1 : 0
    border.color: Zenon.cyan
    Text {
      anchors.centerIn: parent
      text: tool.glyph
      color: tool.on ? Zenon.cyan : Zenon.white
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(16)
    }
    MouseArea {
      id: toolMa
      anchors.fill: parent
      hoverEnabled: true
      enabled: tool.live
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: (m) => m.button === Qt.RightButton ? tool.alt() : tool.hit()
      onContainsMouseChanged: containsMouse ? tips.show(tool, tool.name, tool.key) : tips.hide(tool)
    }
  }

  component Sep: Rectangle { width: 1; height: 26; color: Zenon.border; anchors.verticalCenter: parent ? parent.verticalCenter : undefined }

  // ── the bar ───────────────────────────────────────────────────────────
  Rectangle {
    id: bar
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    // fullscreen, it waits above the top edge (win.peekTop)
    anchors.topMargin: win.full && !win.peekTop ? -bar.height : 0
    Behavior on anchors.topMargin { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }
    height: win.chrome || win.full ? 52 : 0
    // not under the annotator's own bar: both are translucent, and this
    // one's title and tools read straight through the other's
    visible: (win.chrome || win.full) && win.mode !== "annotate"
    color: Zenon.headBg
    z: 5
    HoverHandler { id: barHover }
    // The hairline, opened over a sheet spliced out of the bar (properties),
    // so the bar and the card read as one piece.
    readonly property real cutX: propsSheet.cardInk > 0.01 ? propsSheet.drawnX : bar.width
    readonly property real cutW: propsSheet.cardInk > 0.01 ? propsSheet.drawnW : 0
    Rectangle { anchors.bottom: parent.bottom; width: bar.cutX; height: 1; color: Zenon.border }
    Rectangle { anchors.bottom: parent.bottom; x: bar.cutX + bar.cutW; width: Math.max(0, bar.width - x); height: 1; color: Zenon.border }

    // the picture under it, frosted: under the bar's ground, which tints it
    // (see `canvas`)
    Frost {
      anchors.fill: parent
      z: -1
      source: stage
      active: win.picShows && win.picTop < bar.height
    }

    // back to the gallery this picture is from — its directory, or the picked
    // pictures it was opened among
    Tool {
      id: backBtn
      anchors.left: parent.left
      anchors.leftMargin: 12
      anchors.verticalCenter: parent.verticalCenter
      // in the gallery: the directory before, or the one above (the gallery
      // keeps no ".." cell of its own any more)
      visible: win.mode === "view" ? !win.solo && win.galleryItems.length > 0
        : win.mode === "gallery" && win.canBack
      glyph: "\uf060"
      readonly property string backTo: win.history.length > 0 ? win.history[win.history.length - 1] : win.upDir
      name: win.mode === "gallery" ? "Back to " + (Terminus.basename(backTo) || "/")
        : win.picked.length > 0 ? "Back to the picked pictures"
        : "Back to " + (Terminus.basename(win.dir) || "/")
      key: win.mode === "gallery" ? "mouse 4" : "g"
      onHit: win.navBack()
    }

    // what it is
    Column {
      anchors.left: backBtn.visible ? backBtn.right : parent.left
      anchors.leftMargin: backBtn.visible ? 10 : 16
      anchors.right: sortRow.visible ? sortRow.left : tools.left
      anchors.rightMargin: 16
      anchors.verticalCenter: parent.verticalCenter
      spacing: 1
      Text {
        width: parent.width
        // in the gallery, the bar is about the directory; otherwise the picture
        text: win.mode === "map" ? "Where they were taken"
          : win.mode === "gallery"
          ? (win.picked.length > 0 ? "Picked pictures" : (Terminus.basename(win.dir) || "/"))
          : (win.row ? win.row.name : (win.rows.length === 0 ? "" : "…"))
        color: Zenon.white
        font.family: Zenon.face
        font.weight: 600
        font.pixelSize: Zenon.px(14)
        elide: Text.ElideMiddle
      }
      Item {
        width: parent.width
        height: 16
        Text {
          anchors.fill: parent
          // while the search is typed in, what it understands
          text: filterField.activeFocus && win.note === ""
            ? "words, #tag, \u2605, is:video is:picture is:marked is:directory  \u00b7  enter keeps it, esc clears it"
            : win.note !== "" ? win.note
            : win.mode === "map" ? win.mapPoints.length + " of " + win.rows.length + " say where  \u00b7  a pin opens its picture  \u00b7  esc goes back"
            : (win.mode === "gallery" ? win.where : win.facts)
          color: win.note !== "" ? Zenon.sand : Zenon.muted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(12)
          elide: Text.ElideRight
        }
      }
    }

    // the order, in the bar rather than over the grid — the same in the
    // gallery and on a picture, since the strip is the gallery in a row.
    // Stood down in a window too narrow for it beside the tools.
    Row {
      id: sortRow
      anchors.right: tools.left
      anchors.rightMargin: 16
      anchors.verticalCenter: parent.verticalCenter
      visible: bar.width >= 1080
      spacing: 4
      Head { anchors.verticalCenter: parent.verticalCenter; text: "Order"; rightPadding: 8 }
      Repeater {
        model: [{ k: "name", t: "Name" }, { k: "time", t: "Newest" }, { k: "size", t: "Largest" }]
        delegate: Seg {
          required property var modelData
          anchors.verticalCenter: parent.verticalCenter
          width: 76
          height: 28
          label: modelData.t
          live: win.picked.length === 0
          chosen: win.sortKey === modelData.k
          onHit: win.sortBy(modelData.k)
        }
      }
    }

    Row {
      id: tools
      anchors.right: parent.right
      anchors.rightMargin: 12
      anchors.verticalCenter: parent.verticalCenter
      spacing: 2

      // How zoomed: terminus' meter (ZoomMeter.qml). The gallery's tiles on
      // terminus' own scale; a picture's zoom along its stops, which run on
      // a log scale (5% to 3200%) so 100% sits near the middle.
      Item {
        id: zoomBox
        anchors.verticalCenter: parent.verticalCenter
        visible: win.mode === "gallery" || (win.mode === "view" && win.loaded)
        width: zoomMeter.implicitWidth + 20
        height: 34
        readonly property real lo: 0.05
        readonly property real hi: 32
        ZoomMeter {
          id: zoomMeter
          anchors.centerIn: parent
          value: win.mode === "gallery"
            ? (win.gzoom - win.gzoomMin) / (win.gzoomMax - win.gzoomMin)
            : Math.log(Math.max(zoomBox.lo, win.vz) / zoomBox.lo) / Math.log(zoomBox.hi / zoomBox.lo)
          onSeek: (f) => {
            if (win.mode === "gallery") win.gzoomSet(win.gzoomMin + f * (win.gzoomMax - win.gzoomMin));
            else win.zoomTo(zoomBox.lo * Math.pow(zoomBox.hi / zoomBox.lo, f), undefined, undefined, 0);
          }
          onStep: (d) => win.mode === "gallery" ? win.gzoomBy(d * 0.1) : win.zoomStep(d)
          onReset: win.mode === "gallery" ? win.gzoomSet(1) : win.zoomStep(0)
        }
        HoverHandler {
          onHoveredChanged: hovered
            ? tips.show(zoomBox, "Zoom  \u00b7  " + (win.mode === "gallery" ? Math.round(win.gzoom * 100) : Math.round(win.shownZoom)) + "%", "+ - 0")
            : tips.hide(zoomBox)
        }
      }
      Sep { visible: zoomBox.visible }
      // ── the search ──────────────────────────────────────────────
      // A magnifier among the tools, in the gallery and on a picture, that
      // opens leftwards into the field when you search (`/`, ctrl+f, a
      // click) and stays open while a filter holds something — so the
      // window says why pictures are missing. Words narrow the pictures
      // and the directories and light up in their names; #tag, ★ and is:
      // narrow by what they are; how many are left is said inside it.
      Rectangle {
        id: searchPill
        readonly property bool busy: filterField.activeFocus || win.filterOpen || win.filterText !== ""
        anchors.verticalCenter: parent.verticalCenter
        visible: win.mode === "gallery" || win.mode === "view"
        width: searchPill.busy ? 300 : 34
        Behavior on width { NumberAnimation { duration: Zenon.normal; easing.type: Easing.OutCubic } }
        height: 34
        radius: Zenon.windowRadius
        clip: true
        color: searchPill.busy ? Zenon.wash(0.07) : (pillHover.hovered ? Zenon.wash(0.06) : Zenon.wash(0))
        Behavior on color { ColorAnimation { duration: Zenon.fast } }
        border.width: searchPill.busy ? 1 : 0
        border.color: filterField.activeFocus ? Zenon.cyan : Zenon.border
        Behavior on border.color { ColorAnimation { duration: Zenon.fast } }
        HoverHandler {
          id: pillHover
          cursorShape: searchPill.busy ? Qt.IBeamCursor : Qt.ArrowCursor
          onHoveredChanged: hovered && !searchPill.busy
            ? tips.show(searchPill, "Search and filter  \u00b7  words, #tag, \u2605, is:video", "/")
            : tips.hide(searchPill)
        }
        TapHandler { onTapped: { tips.hide(searchPill); win.openFilter(); } }

        // centred in the button, then at the field's left edge
        Text {
          id: pillGlyph
          x: searchPill.busy ? 12 : (34 - width) / 2
          Behavior on x { NumberAnimation { duration: Zenon.normal; easing.type: Easing.OutCubic } }
          anchors.verticalCenter: parent.verticalCenter
          text: "\uf002"
          color: searchPill.busy ? Zenon.cyan : Zenon.white
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(searchPill.busy ? 13 : 16)
        }
        TextInput {
          id: filterField
          anchors.left: pillGlyph.right
          anchors.leftMargin: 9
          anchors.right: pillCount.left
          anchors.rightMargin: 8
          anchors.verticalCenter: parent.verticalCenter
          visible: searchPill.busy
          color: Zenon.white
          selectionColor: Zenon.cyan
          selectedTextColor: Zenon.onAccent
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(13)
          clip: true
          onTextEdited: win.setFilter(filterField.text)
          Keys.onEscapePressed: (e) => {
            e.accepted = true;
            win.setFilter("");
            filterField.text = "";
            win.filterOpen = false;
            keys.forceActiveFocus();
          }
          Keys.onReturnPressed: (e) => { e.accepted = true; win.filterOpen = false; keys.forceActiveFocus(); }
          Keys.onEnterPressed: (e) => { e.accepted = true; win.filterOpen = false; keys.forceActiveFocus(); }
          onActiveFocusChanged: if (!activeFocus) win.filterOpen = false
          cursorDelegate: Caret { field: filterField }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: filterField.text === "" && win.filterText === ""
            text: "Search"
            color: Zenon.muted
            font: filterField.font
          }
        }
        // the field follows the filter set from elsewhere (the menu's ★, esc)
        Connections {
          target: win
          function onFilterTextChanged() { if (filterField.text !== win.filterText) filterField.text = win.filterText; }
        }
        // how many are left
        Text {
          id: pillCount
          visible: searchPill.busy
          anchors.right: pillClear.visible ? pillClear.left : parent.right
          anchors.rightMargin: pillClear.visible ? 6 : 12
          anchors.verticalCenter: parent.verticalCenter
          text: win.filterText === "" ? ""
            : win.rows.length + " of " + win.allRows.length
              + (win.shownDirectories.length > 0 ? "  +" + win.shownDirectories.length : "")
          color: win.filterText !== "" && win.rows.length === 0 && win.shownDirectories.length === 0 ? Zenon.red : Zenon.muted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(12)
        }
        Text {
          id: pillClear
          anchors.right: parent.right
          anchors.rightMargin: 10
          anchors.verticalCenter: parent.verticalCenter
          visible: searchPill.busy && win.filterText !== ""
          text: "\uf00d"
          color: clearHover.hovered ? Zenon.white : Zenon.muted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(12)
          HoverHandler { id: clearHover; cursorShape: Qt.PointingHandCursor }
          TapHandler { onTapped: { win.setFilter(""); keys.forceActiveFocus(); } }
        }
      }
      Tool { id: placesTool; glyph: "\uf07c"; name: "Places"; key: "'"
             onHit: win.showMenu(placesTool.mapToItem(null, 0, placesTool.height + 4), "places", "") }
      Tool { glyph: win.mode === "gallery" ? "" : ""; name: win.mode === "gallery" ? "Picture" : "Gallery"; key: "g"
             on: win.mode === "gallery"; live: win.mode !== "gallery" || win.rows.length > 0
             onHit: win.mode = win.mode === "gallery" ? "view" : "gallery" }
      Tool { id: slideTool; glyph: win.playing ? "" : ""
             name: (win.playing ? "Stop the slideshow" : "Slideshow") + "  \u00b7  right click: pace, shuffle"; key: "s"
             on: win.playing; live: win.rows.length > 1; onHit: win.playing = !win.playing
             onAlt: win.showMenu(slideTool.mapToItem(null, 0, slideTool.height + 4), "slides", "") }
      Sep {}
      Tool { glyph: ""; name: "Edit"; key: "e"; on: win.panelShown && win.mode === "view"
             live: win.mode === "view" && !win.isVid; onHit: win.panelShown = !win.panelShown }
      Tool { glyph: ""; name: "Crop"; key: "c"; on: win.cropping
             live: win.mode === "view" && win.loaded; onHit: win.cropping ? (win.cropping = false) : win.cropTool() }
      Tool { glyph: ""; name: "Annotate"; key: "a"; live: win.loaded && win.fallback === ""
             onHit: win.annotate() }
      Tool { glyph: ""; name: "Set as background"; key: "w"; live: win.loaded
             onHit: win.toBackground() }
      Sep {}
      Tool { glyph: "\uf065"; name: "Fullscreen"; key: "f"; live: win.mode === "view" && win.loaded
             onHit: win.fullscreen() }
      Tool { glyph: ""; name: "Info"; key: "i"; on: win.infoShown && win.mode === "view"
             live: win.mode === "view"; onHit: win.infoShown = !win.infoShown }
      Tool { glyph: ""; name: "Copy the picture"; key: "ctrl+c"; live: win.path !== ""; onHit: win.copyImage() }
      Tool { glyph: ""; name: "Show in terminus"; key: "o"; live: win.dir !== ""; onHit: win.reveal() }
      // the same paths the keys trash: the gallery's marked pictures or its
      // cursor's, otherwise the one shown (a bare trash() did nothing)
      Tool { glyph: ""; name: "Move to the trash"; key: "del"
             live: win.mode === "gallery" ? win.targets(win.cursorPath()).length > 0 : win.path !== ""
             onHit: win.trash(win.mode === "gallery" ? win.targets(win.cursorPath()) : [win.path]) }
    }
  }

  // "~/Pictures/Wallpapers · 7 directories · 31 pictures"
  readonly property string where: {
    const out = [];
    if (win.picked.length === 0 && win.dir !== "") out.push(win.dir.replace(Paths.home(), "~"));
    const nf = win.directories.filter((f) => !f.isUp).length;
    if (nf > 0) out.push(nf + (nf === 1 ? " directory" : " directories"));
    out.push(win.rows.length + (win.rows.length === 1 ? " picture" : " pictures"));
    if (win.markCount > 0) out.push(win.markCount + " marked  \u00b7  right click for what to do with them");
    return out.join("  \u00b7  ");
  }

  // "3 / 42 · 4032×3024 · 3.1 MiB · 2d ago · 45%"
  readonly property string facts: {
    if (!win.row) return "";
    const out = [(win.index + 1) + " / " + win.rows.length];
    if (win.nw > 0) out.push(Math.round(win.nw) + "×" + Math.round(win.nh));
    out.push(Terminus.formatSize(win.row.size));
    out.push(Terminus.formatTime(win.row.mtime));
    if (win.mode === "view" && win.loaded) out.push(Math.round(win.shownZoom) + "%" + (win.zoomLock ? " locked" : ""));
    if (win.isVid && win.vid) out.push(V.clock(win.vid.position) + " / " + V.clock(win.vid.duration) + (win.muted ? "  muted" : ""));
    const a = win.animated ? win.img : null;
    if (a && a.frameCount > 1)
      out.push("frame " + (a.currentFrame + 1) + " / " + a.frameCount + (win.gifPaused ? ", stopped" : ""));
    if (win.edited) out.push(win.peekOriginal ? "showing the original" : "edited");
    if (win.compare && win.cmpIndex >= 0) out.push("beside " + (win.cmpIndex + 1));
    if (win.markCount > 0) out.push(win.markCount + " marked");
    if (win.starred(win.path)) out.unshift("\u2605");
    return out.join("  ·  ");
  }

  // ── the stage ─────────────────────────────────────────────────────────
  // ── THE PICTURE RUNS ON UNDER THE CHROME ──────────────────────────────
  // The stage is still the room between the bar, the strip and the panel —
  // the fit, the pan limits and every overlay go by it — but it no longer
  // clips: a picture zoomed or panned past it carries on under the bar, the
  // strip and the edit panel, which frost over it (morpheus/Frost, in each).
  // This frame is the window's edge instead, and the clip is here. In a
  // comparison it stops at the second half, which has a picture of its own.
  Item {
    id: canvas
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: win.compare ? twin.left : parent.right
    anchors.bottom: parent.bottom
    clip: true
    visible: win.mode === "view"
    // the edges the fullscreen bar and strip slide in from (win.peekTop)
    HoverHandler { id: edgeHover; enabled: win.full }

  Item {
    id: stage
    // the old anchors, as geometry: the frame is the parent now, and the
    // bar, the strip and the panel are not its siblings
    x: 0
    // fullscreen, the bar and the strip slide in over the picture
    y: win.full ? 0 : bar.height
    width: canvas.width - (win.compare ? 0 : panel.width)
    height: canvas.height - (win.full ? 0 : bar.height + strip.height)
    onWidthChanged: win.refit(false)
    onHeightChanged: win.refit(false)

    // ── what lies under the picture ─────────────────────────────────────
    // Fitted, it lifts off the window on a soft shadow; zoomed, it IS the
    // window, and the shadow goes.
    RectangularShadow {
      x: pic.x; y: pic.y + 6
      width: pic.width; height: pic.height
      radius: win.picRadius
      blur: 32
      color: "#a6000000"
      transform: Translate { x: win.slideX }
      opacity: win.fitted && win.chrome ? pic.opacity : 0
      visible: opacity > 0.01
      Behavior on opacity { NumberAnimation { duration: Zenon.normal; easing.type: Easing.OutCubic } }
    }

    // The tile's thumbnail, blurred, where the picture will be, while the
    // picture itself decodes — so a large photo comes up soft and sharpens,
    // rather than out of nothing.
    Item {
      id: standIn
      readonly property string url: win.mode === "view" && !win.isVid ? win.thumbUrl(win.path) : ""
      readonly property var r: standImg.status === Image.Ready
        ? win.guessRect(standImg.implicitWidth / standImg.implicitHeight) : null
      x: r ? r.x : 0; y: r ? r.y : 0
      width: r ? r.w : 0; height: r ? r.h : 0
      opacity: r && !win.loaded && !win.flyingIn ? 1 : 0
      visible: opacity > 0.01
      // in at once (a flyer is fading over it), out over the picture
      Behavior on opacity { enabled: standIn.opacity >= 1; NumberAnimation { duration: win.stepMs; easing.type: Easing.OutCubic } }
      Image {
        id: standImg
        anchors.fill: parent
        visible: false
        source: standIn.url
        asynchronous: true
        cache: true
      }
      MultiEffect {
        anchors.fill: parent
        source: standImg
        blurEnabled: true
        blur: 0.7
        blurMax: 32
        brightness: -0.04
      }
    }

    // the picture stepped away from, sliding off as the next slides in
    Image {
      id: ghostImg
      x: win.ghost ? win.ghost.x - win.enterK * win.ghost.d * stage.width : 0
      y: win.ghost ? win.ghost.y : 0
      width: win.ghost ? win.ghost.w : 0
      height: win.ghost ? win.ghost.h : 0
      visible: !!win.ghost
      source: win.ghost ? win.ghost.url : ""
      fillMode: Image.Stretch
      autoTransform: true
      // Synchronous ONLY because it is a cache hit — and it is one only if
      // it asks exactly as the stage's still did, since the size is part of
      // the cache's key (see the read-ahead). Without this line it asked
      // for no size at all, missed, and decoded the whole picture again on
      // the GUI thread: every step of a 4–5K picture froze the shell for
      // 170–250 ms (lag.log, 2026-10-09; ~5 ms once it matched).
      sourceSize.width: win.vector ? Math.max(stage.width, stage.height) * 2 : 0
      asynchronous: false
      cache: true
      mipmap: true
    }

    // The picture, drawn at the size it is shown rather than scaled from its
    // own: the Scene's effect layer is then only ever as big as the stage.
    Item {
      id: pic
      x: win.vx
      y: win.vy
      width: win.tw * win.vz
      height: win.th * win.vz
      Behavior on x { enabled: win.glide > 0; NumberAnimation { duration: win.glide; easing.type: Zenon.ease } }
      Behavior on y { enabled: win.glide > 0; NumberAnimation { duration: win.glide; easing.type: Zenon.ease } }
      Behavior on width { enabled: win.glide > 0; NumberAnimation { duration: win.glide; easing.type: Zenon.ease } }
      Behavior on height { enabled: win.glide > 0; NumberAnimation { duration: win.glide; easing.type: Zenon.ease } }
      // In only, as terminus' tiles and Thumb do: nothing while it decodes,
      // then the fade — and no ghost of the last picture on the way out.
      // The fade is enterK's, which a step also slides in by (slideX).
      // A step shows the next picture at full strength the moment it is
      // decoded — only its short slide is animated — so stepping never waits
      // on a fade; a picture arrived at any other way fades in.
      opacity: win.loaded && !win.flyingIn ? (win.enterDir !== 0 ? 1 : win.enterK) : 0
      transform: Translate { x: win.slideX }

      // Rounded while fitted. A mask is a layer as big as the picture, so
      // only while that is no bigger than the stage — never zoomed in.
      layer.enabled: win.picRadius > 0 && win.fitted && win.loaded
      layer.smooth: true
      layer.effect: MultiEffect {
        maskEnabled: true
        maskSource: picMask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
      }

      // see-through parts on a checkerboard, as every editor shows them
      Image {
        anchors.fill: parent
        visible: win.mayAlpha && win.loaded && !win.isVid
        fillMode: Image.Tile
        smooth: false
        source: "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='16' height='16'>"
          + "<rect width='16' height='16' fill='%2326262b'/><rect width='8' height='8' fill='%23323238'/>"
          + "<rect x='8' y='8' width='8' height='8' fill='%23323238'/></svg>"
      }

      Scene {
        id: scene
        anchors.fill: parent
        // \ held: the turn and the mirror stay, so nothing jumps
        look: win.peekOriginal ? Art.lookOf({ rotate: win.look.rotate, mirror: win.look.mirror }) : win.look
        ground: false
        unit: V.unitFor(pic.width, pic.height)
        accent: win.look.tint === "accent" ? Picasso.accentFor(win.path) : ""

        Loader {
          id: imgLoader
          anchors.fill: parent
          active: win.stageUrl !== "" && !win.isVid
          sourceComponent: win.animated && win.fallback === "" ? animComp : stillComp
          // straightened: turned inside the frame, grown to fill it — the
          // frame mirrors after, so a mirrored one turns the other way here
          rotation: win.straighten * (win.look.mirror ? -1 : 1)
          scale: V.straightenScale(width, height, win.straighten)
        }
      }
      // a video, outside the Scene — no look is worn by one
      Loader {
        id: vidLoader
        anchors.fill: parent
        active: win.isVid && win.path !== ""
        sourceComponent: vidComp
      }
    }
    Item {
      id: picMask
      width: pic.width
      height: pic.height
      visible: false
      // Only while the picture's own layer reads it (fitted). Always on, it
      // was a layer as big as the picture as shown — 64512×37632 at 3200%,
      // past the GPU's 32768 — asked for again on every frame zoomed in.
      layer.enabled: win.picRadius > 0 && win.fitted && win.loaded
      Rectangle { anchors.fill: parent; radius: win.picRadius; color: "#000000" }
    }

    // the zoom asked for, said large over the picture for a moment
    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: parent.top
      anchors.topMargin: 18
      z: 6
      width: zoomSaidText.implicitWidth + 28
      height: 34
      radius: 17
      color: Zenon.hud(0.8)
      border.width: 1
      border.color: Zenon.border
      opacity: win.zoomSaid ? 1 : 0
      visible: opacity > 0.01
      Behavior on opacity { NumberAnimation { duration: win.zoomSaid ? Zenon.fast : 380; easing.type: Easing.OutCubic } }
      Text {
        id: zoomSaidText
        anchors.centerIn: parent
        text: (win.fitted ? "fit  ·  " : "") + Math.round(win.shownZoom) + "%"
        color: Zenon.white
        font.family: Zenon.face
        font.weight: 600
        font.pixelSize: Zenon.px(16)
      }
    }

    // Qt's player, and its output's own size — the frame as encoded, which
    // the zoom and the fit go by as they go by a picture's.
    Component {
      id: vidComp
      Item {
        id: vbox
        readonly property real vw: vout.sourceRect.width
        readonly property real vh: vout.sourceRect.height
        readonly property int position: mp.position
        readonly property int duration: mp.duration
        readonly property bool going: mp.playbackState === MediaPlayer.PlayingState
        function toggle() { if (vbox.going) mp.pause(); else mp.play(); }
        function seekBy(ms) { mp.position = Math.max(0, Math.min(mp.duration, mp.position + ms)); }
        function seekTo(f) { mp.position = Math.max(0, Math.min(1, f)) * mp.duration; }
        MediaPlayer {
          id: mp
          source: Strings.fileUrl(win.path)
          videoOutput: vout
          audioOutput: AudioOutput { muted: win.muted }
          onMediaStatusChanged: if (mp.mediaStatus === MediaPlayer.EndOfMedia && win.playing) win.step(1)
          onErrorOccurred: (err, msg) => win.say("this video cannot be played  \u00b7  " + msg)
          Component.onCompleted: mp.play()
        }
        VideoOutput { id: vout; anchors.fill: parent; fillMode: VideoOutput.Stretch }
      }
    }

    Component {
      id: stillComp
      Image {
        source: win.stageUrl
        fillMode: Image.Stretch
        autoTransform: true
        asynchronous: true
        // in the cache, where the read-ahead put it — see holdPaths
        cache: true
        // Past 300% each of the picture's pixels is a square, sharp-edged,
        // as a pixel is: blended into its neighbours it is only blur, and a
        // screenshot zoomed into to read a detail is unreadable.
        smooth: win.vz < 3
        // A 6000px photo shown at 1400 shimmers without these: the drop is
        // too far for plain linear filtering to average.
        mipmap: true
        // 0 is "as the file says"; a vector has no size of its own worth
        // trusting, so it is drawn big enough to zoom into
        sourceSize.width: win.vector ? Math.max(stage.width, stage.height) * 2 : 0
        onStatusChanged: if (status === Image.Error) win.renderFallback()
      }
    }
    Component {
      id: animComp
      AnimatedImage {
        source: win.stageUrl
        fillMode: Image.Stretch
        autoTransform: true
        cache: false
        smooth: win.vz < 3
        playing: true
        paused: win.gifPaused
        onStatusChanged: if (status === Image.Error) win.renderFallback()
      }
    }

    // The wheel zooms, towards the pointer; a drag pans once there is
    // somewhere to pan to. A double click on the fitted picture zooms in
    // there, and one on the zoomed picture fits it again. The crop is the
    // toolbar's (c); shift+drag still draws a box at any zoom, the
    // selection the right-click menu's rows act on. Right click is the menu.
    MouseArea {
      id: stageMa
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
      cursorShape: pressed && !win.fitted && !selecting ? Qt.ClosedHandCursor
        : (!win.fitted ? Qt.OpenHandCursor : Qt.ArrowCursor)
      property real lx: 0
      property real ly: 0
      property real px: 0
      property real py: 0
      property bool selecting: false
      property bool panning: false
      property bool moved: false
      property real ax: 0
      property real ay: 0
      onWheel: (w) => {
        const d = w.angleDelta.y !== 0 ? w.angleDelta.y : w.angleDelta.x;
        if (d === 0) return;
        if (stage.loupeOn) { stage.loupeK = Math.max(1.5, Math.min(24, stage.loupeK * Math.pow(1.0015, d))); return; }
        win.zoomTo(win.vz * Math.pow(1.0015, d), w.x, w.y, 90);
      }
      onPressed: (m) => {
        keys.forceActiveFocus();
        selecting = false; panning = false; moved = false;
        if (m.button === Qt.RightButton) { win.openMenu(mapToItem(null, m.x, m.y), false); return; }
        lx = m.x; ly = m.y; px = m.x; py = m.y;
        const inPic = m.x >= pic.x && m.y >= pic.y && m.x < pic.x + pic.width && m.y < pic.y + pic.height;
        if (win.loaded && inPic && m.button === Qt.LeftButton && !win.isVid && (m.modifiers & Qt.ShiftModifier)) {
          selecting = true;
          ax = (m.x - pic.x) / win.vz; ay = (m.y - pic.y) / win.vz;
        } else panning = true;
      }
      onPositionChanged: (m) => {
        if (!pressed) return;
        if (Math.abs(m.x - px) >= 5 || Math.abs(m.y - py) >= 5) moved = true;
        if (selecting) {
          const cx = (m.x - pic.x) / win.vz, cy = (m.y - pic.y) / win.vz;
          // a click is not a selection: it has to be dragged a little first
          if (!win.cropping && !moved) return;
          const r = Cap.rectOf(ax, ay, cx, cy, win.tw, win.th);
          if (r.w < 4 || r.h < 4) return;
          if (!win.cropping) { win.cropRatio = "free"; win.cropStaged = false; win.cropping = true; }
          win.crop = r;
          return;
        }
        if (panning) { win.panBy(m.x - lx, m.y - ly); lx = m.x; ly = m.y; }
      }
      // A box dragged out opens the edit panel, where its crop, convert and
      // save are — on the release, not as the drag begins: the panel takes
      // width from the stage, and the picture refitting under a drag still
      // in progress moved the box away from the pointer.
      onReleased: (m) => {
        if (selecting && win.cropping && win.crop) win.panelShown = true;
        selecting = false; panning = false;
      }
      onDoubleClicked: (m) => {
        if (m.button !== Qt.LeftButton || !win.loaded || win.isVid || (m.modifiers & Qt.ShiftModifier)) return;
        if (win.fitted) {
          if (stage.overPic(Qt.point(m.x, m.y))) win.zoomTo(Math.max(1, win.fitZ() * 2), m.x, m.y, Zenon.normal);
        } else { win.fitted = true; win.refit(true); win.sayZoom(); }
      }
    }

    property bool navHovered: false
    function overPic(at) {
      return at.x >= pic.x && at.y >= pic.y && at.x < pic.x + pic.width && at.y < pic.y + pic.height;
    }

    // ── a level, while straightening ───────────────────────────────────
    Item {
      x: pic.x; y: pic.y; width: pic.width; height: pic.height
      visible: win.straightening && win.loaded
      Repeater {
        model: 7
        Rectangle { required property int index; x: parent.width * (index + 1) / 8; width: 1; height: parent.height
                    color: Qt.rgba(1, 1, 1, 0.35) }
      }
      Repeater {
        model: 7
        Rectangle { required property int index; y: parent.height * (index + 1) / 8; height: 1; width: parent.width
                    color: Qt.rgba(1, 1, 1, 0.35) }
      }
    }

    // ── the monitors' view of it ────────────────────────────────────────
    // What each monitor would show as a background, filled and centred: the
    // background's own crop, outlined. Sand when the picture is smaller than
    // the monitor and would be blown up.
    property bool monitorsShown: false
    Item {
      x: pic.x; y: pic.y; width: pic.width; height: pic.height
      visible: stage.monitorsShown && win.loaded && !win.isVid
      Repeater {
        model: stage.monitorsShown ? V.monitorCuts(win.tw, win.th, win.screenList) : []
        delegate: Rectangle {
          required property var modelData
          required property int index
          readonly property real k: win.tw > 0 ? pic.width / win.tw : 0
          x: modelData.x * k; y: modelData.y * k
          width: modelData.w * k; height: modelData.h * k
          color: "transparent"
          border.width: 2
          border.color: modelData.short ? Zenon.sand : [Zenon.cyan, Zenon.magenta, Zenon.green, Zenon.blue][index % 4]
          Rectangle {
            x: 6; y: 6 + index * 26
            width: monName.implicitWidth + 14
            height: 22
            radius: 4
            color: Zenon.hud(0.8)
            Text {
              id: monName
              anchors.centerIn: parent
              text: modelData.name + (modelData.short ? "  \u00b7  smaller than the screen" : "")
              color: parent.parent.border.color
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(12)
            }
          }
        }
      }
    }

    // ── the loupe ───────────────────────────────────────────────────────
    // ctrl held over the picture. Its own file (Loupe.qml), loaded by url
    // while it is up.
    property bool loupeOn: false
    property real loupeK: 4
    readonly property real loupeMag: V.clampZoom(Math.max(1, win.vz * stage.loupeK))
    Loader {
      id: loupeLoader
      z: 6
      readonly property point at: hoverWatch.point.position
      readonly property bool over: stage.loupeOn && hoverWatch.hovered && win.loaded
        && at.x >= pic.x && at.y >= pic.y && at.x < pic.x + pic.width && at.y < pic.y + pic.height
      source: loupeLoader.over ? "Loupe.qml" : ""
      x: at.x - width / 2
      y: at.y - height / 2
      onLoaded: {
        const it = loupeLoader.item;
        it.source = Qt.binding(() => win.stageUrl);
        it.nw = Qt.binding(() => win.nw);
        it.nh = Qt.binding(() => win.nh);
        it.tw = Qt.binding(() => win.tw);
        it.th = Qt.binding(() => win.th);
        it.rotate = Qt.binding(() => win.look.rotate);
        it.mirror = Qt.binding(() => win.look.mirror);
        it.mag = Qt.binding(() => stage.loupeMag);
        it.px = Qt.binding(() => (loupeLoader.at.x - pic.x) * win.tw / Math.max(1, pic.width));
        it.py = Qt.binding(() => (loupeLoader.at.y - pic.y) * win.th / Math.max(1, pic.height));
      }
    }
    Timer {
      id: loupeWait
      interval: 160
      onTriggered: if (win.mode === "view" && win.loaded && !win.isVid && !win.cropping) stage.loupeOn = true
    }

    // ── the crop, over the picture ──────────────────────────────────────
    Item {
      id: cropLayer
      x: pic.x; y: pic.y; width: pic.width; height: pic.height
      visible: win.cropping && win.loaded && !win.peekOriginal
      readonly property real k: win.vz
      readonly property var r: win.crop || { x: 0, y: 0, w: win.tw, h: win.th }

      // what is cut away, darkened
      Rectangle { x: 0; y: 0; width: parent.width; height: cropLayer.r.y * cropLayer.k; color: "#99000000" }
      Rectangle { x: 0; y: (cropLayer.r.y + cropLayer.r.h) * cropLayer.k; width: parent.width
                  height: parent.height - y; color: "#99000000" }
      Rectangle { x: 0; y: cropLayer.r.y * cropLayer.k; width: cropLayer.r.x * cropLayer.k
                  height: cropLayer.r.h * cropLayer.k; color: "#99000000" }
      Rectangle { x: (cropLayer.r.x + cropLayer.r.w) * cropLayer.k; y: cropLayer.r.y * cropLayer.k
                  width: parent.width - x; height: cropLayer.r.h * cropLayer.k; color: "#99000000" }

      // a fresh box, dragged out anywhere
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.CrossCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        property real ax: 0
        property real ay: 0
        property bool drawing: false
        onPressed: (m) => {
          keys.forceActiveFocus();
          drawing = m.button === Qt.LeftButton;
          if (!drawing) { win.openMenu(mapToItem(null, m.x, m.y), false); return; }
          ax = m.x / cropLayer.k; ay = m.y / cropLayer.k;
        }
        onPositionChanged: (m) => {
          if (!drawing) return;
          const cx = m.x / cropLayer.k, cy = m.y / cropLayer.k;
          let r = Cap.rectOf(ax, ay, cx, cy, win.tw, win.th);
          const ratio = win.ratioValue(win.cropRatio);
          if (ratio > 0) r = V.fitAspect(r, (cx < ax ? "l" : "r") + (cy < ay ? "t" : "b"), ratio, win.tw, win.th);
          if (r.w >= 4 && r.h >= 4) win.crop = r;
        }
      }

      Rectangle {
        id: cropBox
        x: cropLayer.r.x * cropLayer.k
        y: cropLayer.r.y * cropLayer.k
        width: cropLayer.r.w * cropLayer.k
        height: cropLayer.r.h * cropLayer.k
        color: "transparent"
        border.width: 1
        border.color: Zenon.cyan

        // thirds, for placing things
        Repeater {
          model: 2
          Rectangle { required property int index; x: cropBox.width * (index + 1) / 3; width: 1
                      height: cropBox.height; color: Qt.rgba(1, 1, 1, 0.25) }
        }
        Repeater {
          model: 2
          Rectangle { required property int index; y: cropBox.height * (index + 1) / 3; height: 1
                      width: cropBox.width; color: Qt.rgba(1, 1, 1, 0.25) }
        }

        // the box itself moves; its corners and sides resize it
        Repeater {
          model: ["move", "tl", "t", "tr", "l", "r", "bl", "b", "br"]
          delegate: MouseArea {
            id: grip
            required property string modelData
            readonly property bool body: grip.modelData === "move"
            readonly property real gx: grip.modelData.indexOf("l") >= 0 ? 0
              : grip.modelData.indexOf("r") >= 0 ? cropBox.width : cropBox.width / 2
            readonly property real gy: grip.modelData.indexOf("t") >= 0 ? 0
              : grip.modelData.indexOf("b") >= 0 ? cropBox.height : cropBox.height / 2
            x: grip.body ? 0 : grip.gx - 9
            y: grip.body ? 0 : grip.gy - 9
            width: grip.body ? cropBox.width : 18
            height: grip.body ? cropBox.height : 18
            z: grip.body ? 0 : 1
            cursorShape: grip.body ? Qt.SizeAllCursor
              : (grip.modelData === "tl" || grip.modelData === "br") ? Qt.SizeFDiagCursor
              : (grip.modelData === "tr" || grip.modelData === "bl") ? Qt.SizeBDiagCursor
              : (grip.modelData === "l" || grip.modelData === "r") ? Qt.SizeHorCursor : Qt.SizeVerCursor
            property var r0: null
            property point p0
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onPressed: (m) => {
              keys.forceActiveFocus();
              if (m.button === Qt.RightButton) {
                grip.r0 = null;
                win.openMenu(grip.mapToItem(null, m.x, m.y), true);
                return;
              }
              grip.r0 = cropLayer.r;
              grip.p0 = grip.mapToItem(cropLayer, m.x, m.y);
            }
            onPositionChanged: (m) => {
              if (!grip.r0) return;
              const p = grip.mapToItem(cropLayer, m.x, m.y);
              const dx = (p.x - grip.p0.x) / cropLayer.k, dy = (p.y - grip.p0.y) / cropLayer.k;
              if (grip.body) { win.crop = Cap.moveRect(grip.r0, dx, dy, win.tw, win.th); return; }
              let r = Cap.resizeRect(grip.r0, grip.modelData, dx, dy, win.tw, win.th);
              const ratio = win.ratioValue(win.cropRatio);
              if (ratio > 0) r = V.fitAspect(r, grip.modelData, ratio, win.tw, win.th);
              if (r.w >= 4 && r.h >= 4) win.crop = r;
            }
            onReleased: grip.r0 = null
            Rectangle {
              visible: !grip.body
              anchors.centerIn: parent
              width: 10; height: 10; radius: 2
              color: Zenon.cyan
              border.width: 1
              border.color: "#000000"
            }
          }
        }
      }

      // the size it will be saved at
      Rectangle {
        x: cropBox.x + 6
        y: Math.max(6, cropBox.y - height - 6)
        width: cropSize.implicitWidth + 12
        height: 22
        radius: 4
        color: Zenon.hud(0.8)
        Text {
          id: cropSize
          anchors.centerIn: parent
          text: Math.round(cropLayer.r.w) + " × " + Math.round(cropLayer.r.h)
          color: Zenon.white
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(12)
        }
      }
    }

    // prev and next are the edge tabs, below with the strip's (navTabs)
    HoverHandler { id: hoverWatch }

    // two fingers on a touchpad, or a screen: the zoom, about between them
    PinchHandler {
      target: null
      property real base: 1
      onActiveChanged: if (active) base = win.vz
      onActiveScaleChanged: if (active) win.zoomTo(base * activeScale, centroid.position.x, centroid.position.y, 0)
    }

    // ── the pixels, close up ────────────────────────────────────────────
    // Past 1200% a hairline between them, so they can be counted.
    Canvas {
      id: pixelGrid
      anchors.fill: parent
      visible: win.loaded && win.vz >= 12 && !win.cropping && !win.vector
      readonly property string geom: [pic.x, pic.y, pic.width, pic.height, width, height].join(",")
      onGeomChanged: if (visible) requestPaint()
      onVisibleChanged: requestPaint()
      onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        if (!visible || !(win.tw > 0)) return;
        const z = pic.width / win.tw;
        const x0 = Math.max(0, pic.x), x1 = Math.min(width, pic.x + pic.width);
        const y0 = Math.max(0, pic.y), y1 = Math.min(height, pic.y + pic.height);
        ctx.strokeStyle = "rgba(0, 0, 0, 0.28)";
        ctx.lineWidth = 1;
        ctx.beginPath();
        for (let x = pic.x + Math.ceil((x0 - pic.x) / z) * z; x <= x1; x += z) {
          ctx.moveTo(Math.round(x) + 0.5, y0);
          ctx.lineTo(Math.round(x) + 0.5, y1);
        }
        for (let y = pic.y + Math.ceil((y0 - pic.y) / z) * z; y <= y1; y += z) {
          ctx.moveTo(x0, Math.round(y) + 0.5);
          ctx.lineTo(x1, Math.round(y) + 0.5);
        }
        ctx.stroke();
      }
    }

    // Which of the picture's own pixels the pointer is on: back through the
    // zoom, then back through the edit's turn and mirror (viewer.js unturn).
    readonly property var pixelAt: {
      if (!win.pixelClose || !hoverWatch.hovered) return null;
      const pos = hoverWatch.point.position;
      const z = pic.width / win.tw;
      const tx = Math.floor((pos.x - pic.x) / z), ty = Math.floor((pos.y - pic.y) / z);
      if (tx < 0 || ty < 0 || tx >= win.tw || ty >= win.th) return null;
      return V.unturn(tx, ty, win.nw, win.nh, win.look.rotate, win.look.mirror);
    }
    onPixelAtChanged: if (stage.pixelAt) probe.requestPaint(); else win.pixel = null

    // The read: one pixel of the Image — upright already, autoTransform —
    // drawn into a canvas one pixel big and read back out of it.
    Canvas {
      id: probe
      width: 1
      height: 1
      // not 0: an item that is not drawn is not painted either
      opacity: 0.01
      renderStrategy: Canvas.Immediate
      onPaint: {
        const at = stage.pixelAt;
        if (!at || !win.img) return;
        const ctx = getContext("2d");
        ctx.clearRect(0, 0, 1, 1);
        ctx.drawImage(win.img, at.x, at.y, 1, 1, 0, 0, 1, 1);
        const d = ctx.getImageData(0, 0, 1, 1).data;
        win.pixel = { x: at.x, y: at.y, hex: V.pixelHex(d[0], d[1], d[2]) };
      }
    }
    Rectangle {
      visible: stage.pixelAt !== null && win.pixel !== null
      x: Math.min(stage.width - width - 8, hoverWatch.point.position.x + 18)
      y: Math.min(stage.height - height - 8, hoverWatch.point.position.y + 18)
      width: chipRow.implicitWidth + 16
      height: 28
      radius: 6
      color: Zenon.hud(0.867)
      border.width: 1
      border.color: Zenon.border
      Row {
        id: chipRow
        anchors.centerIn: parent
        spacing: 8
        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: 14; height: 14; radius: 3
          color: win.pixel ? win.pixel.hex : "transparent"
          border.width: 1
          border.color: Zenon.wash(0.45)
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: win.pixel ? win.pixel.hex + "   " + win.pixel.x + ", " + win.pixel.y : ""
          color: Zenon.white
          font.family: Zenon.faceMono
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(12)
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "y copies"
          color: Zenon.muted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(11)
        }
      }
    }

    // ── a video's controls ──────────────────────────────────────────────
    Rectangle {
      id: vbar
      visible: win.isVid && win.vid !== null
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: 14
      width: Math.min(parent.width - 40, 640)
      height: 40
      radius: 8
      color: Zenon.hud(0.8)
      border.width: 1
      border.color: Zenon.border
      opacity: hoverWatch.hovered || !(win.vid && win.vid.going) ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: Zenon.fast } }
      Text {
        id: vplay
        anchors.left: parent.left
        anchors.leftMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        text: win.vid && win.vid.going ? "\uf04c" : "\uf04b"
        color: vplayMa.containsMouse ? Zenon.cyan : Zenon.white
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(15)
        MouseArea { id: vplayMa; anchors.fill: parent; anchors.margins: -8; hoverEnabled: true
                    onClicked: { keys.forceActiveFocus(); win.gifPause(); } }
      }
      Text {
        id: vtime
        anchors.left: vplay.right
        anchors.leftMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        text: win.vid ? V.clock(win.vid.position) + " / " + V.clock(win.vid.duration) : ""
        color: Zenon.muted
        font.family: Zenon.faceMono
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(12)
      }
      Text {
        id: vmute
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        text: win.muted ? "\uf6a9" : "\uf028"
        color: vmuteMa.containsMouse ? Zenon.cyan : Zenon.white
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(15)
        MouseArea { id: vmuteMa; anchors.fill: parent; anchors.margins: -8; hoverEnabled: true
                    onClicked: { keys.forceActiveFocus(); win.muted = !win.muted; } }
      }
      Item {
        anchors.left: vtime.right
        anchors.leftMargin: 14
        anchors.right: vmute.left
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        height: 18
        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 4; radius: 2
                    color: Qt.rgba(1, 1, 1, 0.12) }
        Rectangle { anchors.verticalCenter: parent.verticalCenter; height: 4; radius: 2; color: Zenon.cyan
                    width: win.vid && win.vid.duration > 0 ? parent.width * win.vid.position / win.vid.duration : 0 }
        MouseArea {
          anchors.fill: parent
          onPressed: (m) => { keys.forceActiveFocus(); if (win.vid) win.vid.seekTo(m.x / width); }
          onPositionChanged: (m) => { if (pressed && win.vid) win.vid.seekTo(m.x / width); }
        }
      }
    }

    // the left half's name, while it is half of a comparison
    Rectangle {
      visible: win.compare && win.row !== null
      anchors.left: parent.left
      anchors.bottom: parent.bottom
      anchors.margins: 10
      width: Math.min(parent.width - 20, aName.implicitWidth + 16)
      height: 24
      radius: 5
      color: Zenon.hud(0.8)
      Text {
        id: aName
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        verticalAlignment: Text.AlignVCenter
        text: win.row ? win.row.name : ""
        color: Zenon.cyan
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(12)
        elide: Text.ElideMiddle
      }
    }
  }
  }

  // ── WHERE THE PICTURE REACHES UNDER THE CHROME ────────────────────────
  // In the frame's coordinates (the window's, near enough): each frost is
  // on only while some of the picture is under it, so a fitted picture
  // costs the bars nothing.
  readonly property real picTop: stage.y + pic.y
  readonly property real picBottom: stage.y + pic.y + pic.height
  readonly property real picRight: stage.x + pic.x + pic.width
  readonly property bool picShows: win.mode === "view" && win.loaded && pic.width > 0

  // ── the other half of a comparison ────────────────────────────────────
  // The second picture, in the same place as the first: the same part of it
  // in the middle and drawn as wide — read off `pic` as it is DRAWN, so it
  // glides along with every zoom. Wheel and drag here move the first, and
  // this follows; it has no edit, no crop and no keys of its own.
  Item {
    id: twin
    anchors.top: bar.bottom
    anchors.right: panel.left
    anchors.bottom: strip.top
    width: win.compare && win.mode === "view" ? Math.floor((win.width - panel.width) / 2) : 0
    visible: width > 0
    clip: true
    readonly property var crow: win.cmpIndex >= 0 ? win.rows[win.cmpIndex] : null
    readonly property real bw: twinImg.status === Image.Ready ? twinImg.implicitWidth : 0
    readonly property real bh: twinImg.status === Image.Ready ? twinImg.implicitHeight : 0
    readonly property var view: {
      if (!(twin.bw > 0) || !(win.tw > 0) || !(pic.width > 0) || twin.width <= 0) return { z: 1, x: 0, y: 0 };
      if (win.fitted) {
        const m = win.margin;
        const v = V.fitView(twin.bw, twin.bh, twin.width - 2 * m, twin.height - 2 * m, 1);
        return { z: v.z, x: v.x + m, y: v.y + m };
      }
      const z = pic.width / win.tw;
      const c = V.centreOf({ z: z, x: pic.x, y: pic.y }, win.tw, win.th, stage.width, stage.height);
      return V.viewAt(z * win.tw / twin.bw, c.fx, c.fy, twin.bw, twin.bh, twin.width, twin.height);
    }
    Image {
      id: twinImg
      x: twin.view.x
      y: twin.view.y
      width: twin.bw * twin.view.z
      height: twin.bh * twin.view.z
      source: twin.crow ? win.urlOf(twin.crow.path) : ""
      fillMode: Image.Stretch
      autoTransform: true
      asynchronous: true
      cache: true
      mipmap: true
      smooth: twin.view.z < 3
      sourceSize.width: 0
      opacity: status === Image.Ready ? 1 : 0
    }
    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.MiddleButton
      cursorShape: win.fitted ? Qt.ArrowCursor : (pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor)
      property real lx: 0
      property real ly: 0
      onWheel: (w) => {
        const d = w.angleDelta.y !== 0 ? w.angleDelta.y : w.angleDelta.x;
        if (d !== 0) win.zoomTo(win.vz * Math.pow(1.0015, d), w.x, w.y, 90);
      }
      onPressed: (m) => { keys.forceActiveFocus(); lx = m.x; ly = m.y; }
      onPositionChanged: (m) => { win.panBy(m.x - lx, m.y - ly); lx = m.x; ly = m.y; }
      onDoubleClicked: (m) => {
        if (win.fitted) win.zoomTo(Math.max(1, win.fitZ() * 2), m.x, m.y, Zenon.normal);
        else { win.fitted = true; win.refit(true); }
      }
    }
    Rectangle { anchors.left: parent.left; width: 1; height: parent.height; color: Zenon.border }
    Rectangle {
      visible: twin.crow !== null
      anchors.left: parent.left
      anchors.bottom: parent.bottom
      anchors.margins: 10
      width: Math.min(parent.width - 20, bName.implicitWidth + 16)
      height: 24
      radius: 5
      color: Zenon.hud(0.8)
      Text {
        id: bName
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        verticalAlignment: Text.AlignVCenter
        text: twin.crow ? twin.crow.name + "   \u00b7   shift+\u2190 \u2192   tab swaps" : ""
        color: Zenon.sand
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(12)
        elide: Text.ElideMiddle
      }
    }
  }

  Loader {
    id: mapLoader
    anchors.top: bar.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    active: win.mode === "map"
    source: active ? "MapView.qml" : ""
    onLoaded: {
      const m = mapLoader.item;
      m.points = Qt.binding(() => win.mapPoints);
      m.thumbs = Qt.binding(() => win.thumbs);
      m.opened.connect((p) => {
        const ri = win.rowIndex[p];
        if (ri === undefined) return;
        win.go(ri);
        win.mode = "view";
      });
      m.wantThumb.connect((p) => win.wantThumb(p));
      Qt.callLater(() => { if (mapLoader.item) mapLoader.item.start(win.mapFocus); });
    }
  }

  // ── the gallery ───────────────────────────────────────────────────────
  // Terminus' grid, as the directory would look there: cells that divide the
  // width exactly at about 190px, each picture whole and rounded at its own
  // shape (not cropped to a square), its name under it in two lines at
  // most, and terminus' own cursor — SelectCell — sliding between them.
  // Directories are their glyph in terminus' directory ink. The rail is terminus'.
  Item {
    id: galleryPane
    anchors.top: bar.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    visible: win.mode === "gallery" || galleryOut.running

    // pictures scrolled off the top carry on under the bar, frosted — see
    // morpheus/ScrollEdge. Up in the bar's space, and under it: the bar is
    // z 5 over this pane, so its headBg tints them.
    ScrollEdge {
      view: grid
      x: grid.x
      y: -height
      width: grid.width
      height: bar.height
      visible: win.chrome
    }

    // the gallery's last screenfuls, held decoded — terminus' own keeper
    ThumbKeeper { id: thumbKeeper }
    GridView {
      id: grid
      // a screen's worth of tiles made ahead each way, so a scroll finds
      // them already built (and, through the keeper, already decoded)
      cacheBuffer: Math.max(0, grid.height)
      // ctrl+wheel zooms the tiles, as in terminus' grid
      ElasticScroll {
        view: grid
        step: grid.cellHeight
        intercept: (w) => {
          if (!(w.modifiers & Qt.ControlModifier)) return false;
          win.gzoomBy(w.angleDelta.y > 0 ? 0.1 : -0.1);
          return true;
        }
      }
      anchors.fill: parent
      anchors.leftMargin: 6
      anchors.rightMargin: scrub.visible ? scrub.width + 6 : 6
      clip: true
      model: win.galleryItems
      // a target width, as terminus has it: the cells divide the pane
      // exactly, with no ragged strip down the right
      cellWidth: Math.floor(grid.width / win.gcols)
      cellHeight: Math.round(168 * win.gzoom)
      currentIndex: win.gidx
      boundsBehavior: Flickable.StopAtBounds
      onCurrentIndexChanged: if (win.mode === "gallery") grid.positionViewAtIndex(win.gidx, GridView.Contain)

      delegate: Item {
        id: cell
        required property var modelData
        required property int index
        width: grid.cellWidth
        height: grid.cellHeight
        readonly property bool directory: !!cell.modelData.isDir
        // an empty cell, ending a line before a section
        readonly property bool fill: !!cell.modelData.isFill
        readonly property bool here: cell.index === win.gidx
        readonly property bool marked: !cell.directory && !cell.fill && !!win.marks[cell.modelData.path]
        readonly property var tagged: cell.directory || cell.fill ? [] : (win.tags[cell.modelData.path] || [])
        readonly property var chip: win.layout.chips[cell.index] || null
        readonly property int ri: cell.directory || cell.fill ? -1 : (win.rowIndex[cell.modelData.path] ?? -1)
        readonly property var burst: cell.ri >= 0 ? (win.burstAt[cell.ri] || null) : null
        readonly property bool best: !!win.dupes && !cell.fill && !!win.dupes.keep[cell.modelData.path]
        enabled: !cell.fill
        z: cell.chip ? 2 : 0
        // the picture, for a flight into it or out of it (flyIn/flyOut)
        readonly property alias thumbItem: pic
        Component.onCompleted: {
          if (!cell.directory && !cell.fill) win.wantThumb(cell.modelData.path);
          // a fresh directory comes up a tile after a tile, top to bottom —
          // terminus' TileRise, which its grid does on arriving too
          if (win.staggering) { rise.hide(); rise.start(grid, cell.index); }
          else if (win.reflowing && !cell.fill) cell.glideIn();
        }
        TileRise { id: rise }

        // the tile a menu is open about — terminus' HeldRing, as its grid
        // wears it (marked: the clicked one, which the menu is anchored to)
        HeldRing {
          anchors.fill: parent
          anchors.margins: 4
          z: 5
          radius: 6
          on: menu.open && !cell.fill && menu.subject === cell.modelData.path
            && (menu.kind === "cell" || menu.kind === "directory" || menu.kind === "marked")
        }

        // from where this path's tile was before the reorder — see tilePos
        // (terminus/Glide, as terminus' views glide)
        Glide { id: glide; limit: grid.height }
        function glideIn() {
          const was = win.tilePos[cell.modelData.path];
          if (!was) { cell.opacity = 0; glideFade.start(); return; }
          const c = win.gcols;
          glide.from(was.x - (cell.index % c) * grid.cellWidth,
                     was.y - Math.floor(cell.index / c) * grid.cellHeight);
        }
        NumberAnimation { id: glideFade; target: cell; property: "opacity"; to: 1; duration: 260; easing.type: Easing.OutCubic }


        // out of the window, as a file — see win.dragOut
        Drag.active: false
        Drag.dragType: Drag.Automatic
        Drag.supportedActions: Qt.CopyAction
        Drag.onDragFinished: (action) => { cell.Drag.active = false; }
        DragHandler {
          target: null
          // from the picture itself; off it, a drag is the box (see gband)
          enabled: active || (!cell.directory && !cell.fill && win.hoverThumb === cell.index)
          onActiveChanged: if (active) win.dragOut(cell, cell.modelData.path)
        }

        Item {
          id: thumbBox
          anchors.top: parent.top
          anchors.topMargin: 12
          anchors.horizontalCenter: parent.horizontalCenter
          width: parent.width - 24
          height: parent.height - 68
          // marked, the picture steps back a little inside its ring
          scale: cell.marked ? 0.9 : 1
          Behavior on scale { NumberAnimation { duration: win.stepMs; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }

          // a directory with pictures in it is drawn as them, as terminus'
          // grid draws one — see terminus/FolderCover.qml
          FolderCover {
            id: dirCover
            anchors.fill: parent
            live: cell.directory && !cell.modelData.isUp
            path: cell.directory && !cell.modelData.isUp ? cell.modelData.path : ""
            stamp: cell.modelData.mtime || 0
            glyph: dirGlyph.text
            ink: dirGlyph.color
          }
          // otherwise its glyph — terminus' own, from the shell's glyph map
          // (Downloads, Pictures, .git… each have theirs), in its ink
          Text {
            id: dirGlyph
            anchors.centerIn: parent
            visible: cell.directory && !dirCover.shown
            text: cell.directory ? Terminus.glyphOf(cell.modelData, Icons) : ""
            color: cell.directory ? Terminus.inkOf(cell.modelData) : Zenon.cyan
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Math.round(64 * win.gzoom)
          }
          Thumb {
            id: pic
            HoverHandler {
              onHoveredChanged: {
                if (hovered) win.hoverThumb = cell.index;
                else if (win.hoverThumb === cell.index) win.hoverThumb = -1;
              }
            }
            visible: !cell.directory && !cell.fill && pic.measured
            // a picture flying back in lands here; until it does, it is the flyer
            opacity: win.flyTarget !== "" && win.flyTarget === cell.modelData.path ? 0 : 1
            anchors.centerIn: parent
            width: Math.max(1, Math.min(thumbBox.width, thumbBox.height * pic.ratio))
            height: Math.max(1, Math.min(thumbBox.height, thumbBox.width / pic.ratio))
            radius: Zenon.windowRadius
            color: "transparent"
            measure: !cell.directory && !cell.fill
            path: cell.directory || cell.fill ? "" : cell.modelData.path
            thumb: win.thumbs[cell.modelData.path] ?? ""
            wait: !(cell.modelData.path in win.thumbs)
            spinner: false
            // decoded as terminus' tiles are, and kept (see Thumb.pooled)
            pooled: true
            keeper: thumbKeeper
          }
          Text {
            visible: !cell.directory && pic.visible && Terminus.isVideo(cell.modelData.name || "")
            anchors.centerIn: pic
            text: "\uf144"
            color: Zenon.white
            style: Text.Outline
            styleColor: "#99000000"
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(30)
          }
          // marked: terminus' MarkRing — a ring a little out from the picture,
          // which has stepped back inside it (thumbBox.scale), and a tick
          MarkRing { anchors.fill: pic; on: cell.marked && pic.visible }
          // the open flare — see win.flare; terminus' tile wears the same
          Rectangle {
            id: cellFlare
            property real glow: 0
            anchors.fill: cell.directory ? parent : pic
            anchors.margins: cell.directory ? 4 : -3
            radius: Zenon.windowRadius + 2
            visible: cellFlare.glow > 0.003
            opacity: cellFlare.glow
            color: Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.18)
            border.width: 3
            border.color: Zenon.cyan
            Connections {
              target: win
              function onFlarePulseChanged() {
                if (!cell.fill && cell.modelData.path === win.flarePath) cellFlareAnim.restart();
              }
            }
            SequentialAnimation {
              id: cellFlareAnim
              NumberAnimation { target: cellFlare; property: "glow"; to: 1; duration: 140;
                                easing.type: Easing.OutCubic }
              NumberAnimation { target: cellFlare; property: "glow"; to: 0; duration: 620;
                                easing.type: Easing.InOutSine }
            }
          }
          // the star, and the tags that come with a colour, along its foot
          Row {
            x: pic.x + 6
            y: pic.y + pic.height - height - 6
            spacing: 4
            visible: cell.tagged.length > 0 && pic.visible
            Text {
              anchors.verticalCenter: parent.verticalCenter
              visible: cell.tagged.indexOf(V.FAVOURITE) >= 0
              text: "\uf005"
              color: Zenon.sand
              style: Text.Outline
              styleColor: "#99000000"
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(14)
            }
            Repeater {
              model: cell.tagged.filter((t) => Tags.presetInk(t) !== "")
              delegate: Rectangle {
                required property var modelData
                anchors.verticalCenter: parent.verticalCenter
                width: 10
                height: 10
                radius: 5
                color: Zenon[Tags.presetInk(modelData)]
                border.width: 1
                border.color: "#99000000"
              }
            }
          }
        }
        // terminus' TileName: ElideMiddle does nothing on a wrapped label, so a
        // long name was cut off with no ellipsis and no extension
        TileName {
          anchors.top: thumbBox.bottom
          anchors.topMargin: 8
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.margins: 8
          horizontalAlignment: Text.AlignHCenter
          visible: !cell.fill
          name: cell.modelData.isUp ? "Up to " + (Terminus.basename(cell.modelData.path) || "/") : (cell.modelData.name || "")
          // what the filter's words matched, lit
          mark: win.filterWords
          color: cell.directory ? Zenon.cyan : Zenon.white
          font.family: Zenon.face
          font.weight: cell.here ? Font.Bold : Font.Medium
          font.pixelSize: Zenon.px(14)
        }
        // a folded burst: how many are under it — Enter or a click on this opens it
        Rectangle {
          visible: !!cell.burst && !cell.burst.open && pic.visible
          x: thumbBox.x + pic.x + pic.width - width - 6
          y: thumbBox.y + pic.y + pic.height - height - 6
          z: 2
          width: burstRow.implicitWidth + 12
          height: 22
          radius: 11
          color: Zenon.hud(0.867)
          border.width: 1
          border.color: Zenon.sand
          Row {
            id: burstRow
            anchors.centerIn: parent
            spacing: 5
            Text { text: "\uf24d"; color: Zenon.sand; font.family: Zenon.face; font.pixelSize: Zenon.px(11) }
            Text { text: cell.burst ? cell.burst.n : ""; color: Zenon.sand; font.family: Zenon.face; font.weight: 600; font.pixelSize: Zenon.px(12) }
          }
          MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor
                      onClicked: { keys.forceActiveFocus(); win.foldBurst(cell.burst.key, false); } }
        }
        // the one of an alike group worth keeping
        Rectangle {
          visible: cell.best && pic.visible
          x: thumbBox.x + pic.x + pic.width - width - 6
          y: thumbBox.y + pic.y + pic.height - height - 6
          z: 2
          width: bestText.implicitWidth + 14
          height: 20
          radius: 10
          color: Zenon.green
          Text { id: bestText; anchors.centerIn: parent; text: "best"; color: Zenon.black
                 font.family: Zenon.face; font.weight: 600; font.pixelSize: Zenon.px(11) }
        }
        // A section begins here: a rule across the grid's line, and its name.
        Rectangle {
          visible: !!cell.chip && cell.chip.text !== ""
          x: 6
          y: 11
          z: 3
          width: grid.width - 12
          height: 1
          color: Zenon.border
        }
        Rectangle {
          visible: !!cell.chip && cell.chip.text !== ""
          x: 10
          y: 1
          z: 4
          width: chipRow.implicitWidth + 18
          height: 22
          radius: 11
          color: Zenon.headBg
          border.width: 1
          border.color: cell.chip && cell.chip.kind === "dupe" ? Zenon.sand : Zenon.border
          Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: 8
            Text {
              text: cell.chip ? cell.chip.text : ""
              color: cell.chip && cell.chip.kind === "dupe" ? Zenon.sand : Zenon.white
              font.family: Zenon.face
              font.weight: 600
              font.pixelSize: Zenon.px(12)
            }
            Text {
              visible: text !== ""
              text: cell.chip ? (cell.chip.sub || "") : ""
              color: Zenon.muted
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(12)
            }
            Text {
              visible: !!cell.chip && !!cell.chip.burst
              text: "fold \uf068"
              color: foldMa.containsMouse ? Zenon.cyan : Zenon.muted
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(12)
              MouseArea { id: foldMa; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true
                          onClicked: { keys.forceActiveFocus(); win.foldBurst(cell.chip.burst, true); } }
            }
          }
        }
        MouseArea {
          id: cellMa
          anchors.fill: parent
          // ctrl marks one, shift marks the run from the cursor
          onClicked: (m) => {
            keys.forceActiveFocus();
            if (!cell.directory && (m.modifiers & Qt.ControlModifier)) win.toggleMark(cell.modelData.path);
            else if (!cell.directory && (m.modifiers & Qt.ShiftModifier)) win.markRange(win.gidx, cell.index);
            win.gallerySel(cell.index);
          }
          onDoubleClicked: win.galleryOpen(cell.index)
        }
      }
    }

    SelectCell { view: grid; index: win.gidx; on: win.mode === "gallery" }

    // a soft shade falling from the bar onto the grid once it is scrolled
    // (terminus/TopShade, as terminus' views have it)
    TopShade { view: grid; on: win.chrome; x: grid.x; width: grid.width }

    // ── the section scrolled into, held at the top ──────────────────────
    // Its own chip has gone up under the bar; this one stays, until the
    // next section's chip comes up and pushes it off.
    Item {
      id: pinned
      x: grid.x
      width: grid.width
      height: 24
      z: 3
      readonly property var starts: Object.keys(win.layout.chips).map(Number)
        .filter((i) => win.layout.chips[i] && win.layout.chips[i].text !== "")
        .sort((a, b) => a - b)
      readonly property real scrolled: grid.contentY - grid.originY
      readonly property real ch: grid.cellHeight
      function rowY(i) { return Math.floor(i / win.gcols) * pinned.ch; }
      readonly property int cur: {
        let c = -1;
        for (const i of pinned.starts) { if (pinned.rowY(i) < pinned.scrolled - 0.5) c = i; else break; }
        return c;
      }
      readonly property int after: {
        for (const i of pinned.starts) if (i > pinned.cur) return i;
        return -1;
      }
      readonly property var chip: pinned.cur >= 0 ? win.layout.chips[pinned.cur] : null
      y: pinned.after >= 0 ? Math.min(1, pinned.rowY(pinned.after) - pinned.scrolled + 1 - 28) : 1
      visible: !!pinned.chip && win.mode === "gallery"
      RectangularShadow {
        anchors.fill: pinChip
        radius: pinChip.radius
        blur: 12
        color: "#80000000"
      }
      Rectangle {
        id: pinChip
        x: 10
        width: pinRow.implicitWidth + 18
        height: 22
        radius: 11
        color: Zenon.headBg
        border.width: 1
        border.color: pinned.chip && pinned.chip.kind === "dupe" ? Zenon.sand : Zenon.border
        Row {
          id: pinRow
          anchors.centerIn: parent
          spacing: 8
          Text {
            text: pinned.chip ? pinned.chip.text : ""
            color: pinned.chip && pinned.chip.kind === "dupe" ? Zenon.sand : Zenon.white
            font.family: Zenon.face
            font.weight: 600
            font.pixelSize: Zenon.px(12)
          }
          Text {
            visible: text !== ""
            text: pinned.chip ? (pinned.chip.sub || "") : ""
            color: Zenon.muted
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(12)
          }
        }
        // a click goes back up to where the section begins
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: { keys.forceActiveFocus(); grid.positionViewAtIndex(pinned.cur, GridView.Beginning); }
        }
      }
    }

    // ── the drag box ────────────────────────────────────────────────────
    // As terminus' (its `band`): a DragHandler over the grid, which only
    // takes the gesture once the pointer has moved — so a click is still a
    // click — and only from somewhere that is not a thumbnail, since
    // dragging one is taking the file out. What it covers is worked out from
    // the grid's geometry, not asked of the tiles: one scrolled out of view
    // has no tile, but it has a cell. It ADDS to what was marked, and drawn
    // near the top or the bottom, the grid scrolls under it.
    DragHandler {
      id: gband
      target: null
      acceptedButtons: Qt.LeftButton
      enabled: gband.active || (win.mode === "gallery" && win.hoverThumb < 0 && !menu.open && !confirm.open
                                && !scrubHov.hovered && !railHov.hovered)
      grabPermissions: PointerHandler.CanTakeOverFromAnything
      // in the grid's content, so it stays put while the grid scrolls
      property real cy0: 0
      readonly property real px: centroid.position.x
      readonly property real py: centroid.position.y
      readonly property real x1: Math.max(grid.x, Math.min(centroid.pressPosition.x, gband.px))
      readonly property real x2: Math.min(grid.x + grid.width, Math.max(centroid.pressPosition.x, gband.px))
      readonly property real y1: Math.min(gband.cy0 - grid.contentY, gband.py)
      readonly property real y2: Math.max(gband.cy0 - grid.contentY, gband.py)
      property var base: ({})
      property rect held: Qt.rect(0, 0, 0, 0)
      onActiveChanged: {
        if (!active) return;
        keys.forceActiveFocus();
        gband.base = Object.assign({}, win.marks);
        gband.cy0 = centroid.pressPosition.y + grid.contentY;
        gband.held = Qt.rect(gband.x1, gband.py, 0, 0);
      }
      onCentroidChanged: if (gband.active) gband.apply()
      function apply() {
        const w = gband.x2 - gband.x1, h = gband.y2 - gband.y1;
        if (w > 2 && h > 2) gband.held = Qt.rect(gband.x1, gband.y1, w, h);
        const cols = win.gcols, cw = grid.cellWidth, ch = grid.cellHeight;
        const top = grid.contentY - grid.originY;
        const r1 = Math.floor((gband.y1 + top) / ch), r2 = Math.floor((gband.y2 + top) / ch);
        const c1 = Math.floor((gband.x1 - grid.x) / cw), c2 = Math.floor((gband.x2 - grid.x) / cw);
        const next = Object.assign({}, gband.base);
        for (let r = Math.max(0, r1); r <= r2; ++r)
          for (let c = Math.max(0, c1); c <= Math.min(cols - 1, c2); ++c) {
            const it = win.galleryItems[r * cols + c];
            if (it && !it.isDir && !it.isFill) next[it.path] = true;
          }
        win.marks = next;
      }
    }
    // the grid scrolled while the box is held near an edge
    Timer {
      interval: 16
      repeat: true
      running: gband.active && (gband.py < 40 || gband.py > galleryPane.height - 40)
      onTriggered: {
        const d = gband.py < 40 ? -(40 - gband.py) / 2 : (gband.py - galleryPane.height + 40) / 2;
        const max = Math.max(grid.originY, grid.originY + grid.contentHeight - grid.height);
        grid.contentY = Math.max(grid.originY, Math.min(max, grid.contentY + d));
        gband.apply();
      }
    }
    Rectangle {
      visible: opacity > 0.01 && gband.held.width > 2 && gband.held.height > 2
      opacity: gband.active ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
      x: gband.held.x
      y: gband.held.y
      width: gband.held.width
      height: gband.held.height
      radius: Zenon.windowRadius
      color: Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.12)
      border.width: 1
      border.color: Zenon.border
      z: 5
    }

    // ── the scrubber ────────────────────────────────────────────────────
    // In the date order, the sections down the side: a click goes there, and
    // the one the cursor is in is lit.
    Item {
      id: scrub
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.topMargin: 8
      anchors.bottomMargin: 8
      width: 84
      visible: win.mode === "gallery" && win.dateMarks.length >= 3
      HoverHandler { id: scrubHov }
      readonly property int here: {
        let at = -1;
        for (let i = 0; i < win.dateMarks.length; ++i) if (win.dateMarks[i].gi <= win.gidx) at = i;
        return at;
      }
      Rectangle { anchors.left: parent.left; width: 1; height: parent.height; color: Zenon.border }
      ListView {
        id: scrubList
        anchors.fill: parent
        anchors.leftMargin: 6
        clip: true
        model: win.dateMarks
        currentIndex: scrub.here
        highlightFollowsCurrentItem: false
        onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)
        boundsBehavior: Flickable.StopAtBounds
        delegate: Text {
          required property var modelData
          required property int index
          width: scrubList.width
          height: 22
          verticalAlignment: Text.AlignVCenter
          text: modelData.short
          color: index === scrub.here ? Zenon.cyan : (scrubMa.containsMouse ? Zenon.white : Zenon.muted)
          font.family: Zenon.face
          font.weight: index === scrub.here ? 600 : 400
          font.pixelSize: Zenon.px(12)
          elide: Text.ElideRight
          MouseArea {
            id: scrubMa
            anchors.fill: parent
            hoverEnabled: true
            onClicked: {
              keys.forceActiveFocus();
              win.gallerySel(modelData.gi);
              grid.positionViewAtIndex(modelData.gi, GridView.Beginning);
            }
            onContainsMouseChanged: containsMouse ? tips.show(parent, modelData.text) : tips.hide(parent)
          }
        }
      }
    }

    // Right click, anywhere over the grid: the tile's menu — or the marked
    // pictures', the directory's, or (between tiles) the gallery's own.
    MouseArea {
      anchors.fill: grid
      acceptedButtons: Qt.RightButton
      onPressed: (m) => {
        keys.forceActiveFocus();
        win.galleryMenu(grid.indexAt(m.x + grid.contentX, m.y + grid.contentY), mapToItem(null, m.x, m.y));
      }
    }

    ScrollRail {
      target: grid
      on: win.mode === "gallery"
      HoverHandler { id: railHov }
      anchors.right: grid.right
      anchors.rightMargin: 2
      anchors.top: grid.top
      anchors.topMargin: 2
      anchors.bottom: grid.bottom
      anchors.bottomMargin: 2
    }
  }

  // ── the flight, between a tile and the stage ──────────────────────────
  // See flyIn/flyOut. Over the stage and the gallery, under the bar.
  Item {
    id: flyLayer
    anchors.fill: parent
    z: 3.5
    property bool back: false
    function launch(url, back, from, to, r0, r1) {
      flyAnim.stop();
      flyFade.stop();
      flyLayer.back = back;
      flyer.opacity = 1;
      flyImg.source = url;
      flyX.from = from.x; flyX.to = to.x;
      flyY.from = from.y; flyY.to = to.y;
      flyW.from = from.width; flyW.to = to.width;
      flyH.from = from.height; flyH.to = to.height;
      flyR.from = r0; flyR.to = r1;
      flyer.visible = true;
      flyAnim.restart();
    }
    ClippingRectangle {
      id: flyer
      visible: false
      color: "transparent"
      Image {
        id: flyImg
        anchors.fill: parent
        fillMode: Image.Stretch
        autoTransform: true
        // Asked as the stage's still asks, for the same reason as ghostImg:
        // flying back to the gallery hands this the stage's own url, and a
        // different size is a cache miss, decoded whole on the GUI thread.
        // A thumbnail asked at 0 is decoded at its own small size.
        sourceSize.width: win.vector && String(flyImg.source) === String(win.stageUrl)
          ? Math.max(stage.width, stage.height) * 2 : 0
        asynchronous: false
        cache: true
        mipmap: true
      }
    }
    ParallelAnimation {
      id: flyAnim
      NumberAnimation { id: flyX; target: flyer; property: "x"; duration: win.flyMs; easing.type: Easing.OutCubic }
      NumberAnimation { id: flyY; target: flyer; property: "y"; duration: win.flyMs; easing.type: Easing.OutCubic }
      NumberAnimation { id: flyW; target: flyer; property: "width"; duration: win.flyMs; easing.type: Easing.OutCubic }
      NumberAnimation { id: flyH; target: flyer; property: "height"; duration: win.flyMs; easing.type: Easing.OutCubic }
      NumberAnimation { id: flyR; target: flyer; property: "radius"; duration: win.flyMs; easing.type: Easing.OutCubic }
      onFinished: {
        win.landed(flyLayer.back);
        // into its tile it simply becomes the tile; onto the stage it hands
        // over to the picture (or its stand-in) under a short fade
        if (flyLayer.back) { flyer.visible = false; flyImg.source = ""; }
        else flyFade.restart();
      }
    }
    NumberAnimation {
      id: flyFade
      target: flyer; property: "opacity"; to: 0
      duration: win.stepMs; easing.type: Easing.OutCubic
      onFinished: { flyer.visible = false; flyImg.source = ""; }
    }
  }
  // the gallery goes down under a picture flying out of it, rather than
  // leaving the window dark for a frame
  NumberAnimation {
    id: galleryOut
    target: galleryPane; property: "opacity"; from: 1; to: 0
    duration: win.flyMs; easing.type: Easing.OutCubic
    onFinished: galleryPane.opacity = 1
  }
  // the gallery comes up under a picture flying back into it
  NumberAnimation {
    id: galleryFade
    target: galleryPane; property: "opacity"; from: 0; to: 1
    duration: win.flyMs; easing.type: Easing.OutCubic
  }

  // ── the strip ─────────────────────────────────────────────────────────
  // The directory under the picture. Its own wheel: over the strip, the wheel
  // scrolls it, and the picture is left where it is.
  Rectangle {
    id: strip
    anchors.left: parent.left
    anchors.right: panel.left
    anchors.bottom: parent.bottom
    // the room it could have; put away, it slides down out of the way
    readonly property bool can: (win.chrome || win.full) && win.mode === "view" && win.rows.length > 1
    height: strip.can && win.stripShown ? 96 : 0
    Behavior on height { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }
    // fullscreen, it waits below the bottom edge (win.peekBottom)
    anchors.bottomMargin: win.full && !win.peekBottom ? -strip.height - 1 : 0
    Behavior on anchors.bottomMargin { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }
    HoverHandler { id: stripHover }
    visible: height > 0
    color: Zenon.headBg
    Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: Zenon.border }

    // the picture under it, frosted (see `canvas`)
    Frost {
      anchors.fill: parent
      z: -1
      source: stage
      active: win.picShows && win.picBottom > strip.y
    }

    ListView {
      id: stripList
      anchors.fill: parent
      anchors.topMargin: 11
      anchors.bottomMargin: 6
      orientation: ListView.Horizontal
      spacing: 6
      clip: true
      model: win.rows
      currentIndex: win.index
      // the current picture kept in the middle as you go
      highlightRangeMode: ListView.ApplyRange
      preferredHighlightBegin: width / 2 - 50
      preferredHighlightEnd: width / 2 + 50
      highlightMoveDuration: Zenon.normal
      boundsBehavior: Flickable.StopAtBounds
      leftMargin: 10
      rightMargin: 10
      // tiles a little way out of view are kept, so stepping through the
      // directory does not rebuild — and re-decode — each one it scrolls to
      cacheBuffer: 1600

      delegate: Item {
        id: tile
        required property var modelData
        required property int index
        readonly property bool current: tile.index === win.index
        width: 100
        // room under it, inside the list's clip, for the current one's pip
        height: stripList.height - 7
        Component.onCompleted: win.wantThumb(tile.modelData.path)

        // the current one lifted off the strip on a shadow, with a pip
        // under it — the others already stand back at 0.6
        RectangularShadow {
          visible: tile.current
          anchors.fill: parent
          anchors.topMargin: 3
          radius: 5
          blur: 14
          spread: 1
          color: "#cc000000"
        }
        Rectangle {
          visible: tile.current
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.top: parent.bottom
          anchors.topMargin: 3
          width: 16
          z: 2
          height: 3
          radius: 1.5
          color: Zenon.cyan
        }
        // No fades here, in or out: going through pictures moves the
        // current tile and scrolls new ones in on every step, and each of
        // them dissolving was motion that said nothing.
        Thumb {
          anchors.fill: parent
          anchors.margins: tile.current ? 0 : 4
          path: tile.modelData.path
          thumb: win.thumbs[tile.modelData.path] ?? ""
          wait: !(tile.modelData.path in win.thumbs)
          spinner: false
          fade: false
          opacity: tile.current || tileMa.containsMouse ? 1 : 0.6
        }
        Rectangle {
          anchors.fill: parent
          radius: 5
          color: "transparent"
          border.width: 2
          border.color: Zenon.cyan
          visible: tile.current
        }
        // the other half of a comparison
        Rectangle {
          anchors.fill: parent
          radius: 5
          color: "transparent"
          border.width: 2
          border.color: Zenon.sand
          visible: win.compare && tile.modelData.path === win.cmpPath
        }
        Rectangle {
          visible: !!win.marks[tile.modelData.path]
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: 6
          width: 15
          height: 15
          radius: 8
          color: Zenon.cyan
          Text { anchors.centerIn: parent; text: "\uf00c"; color: Zenon.black; font.family: Zenon.face; font.pixelSize: Zenon.px(8) }
        }
        Text {
          visible: Terminus.isVideo(tile.modelData.name)
          anchors.centerIn: parent
          text: "\uf144"
          color: Zenon.white
          style: Text.Outline
          styleColor: "#99000000"
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(22)
        }
        Text {
          visible: win.starred(tile.modelData.path)
          anchors.left: parent.left
          anchors.bottom: parent.bottom
          anchors.margins: 6
          text: "\uf005"
          color: Zenon.sand
          style: Text.Outline
          styleColor: "#99000000"
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(12)
        }
        // up out of the strip, as a file: only an upward pull — sideways
        // is the strip scrolling
        Drag.active: false
        Drag.dragType: Drag.Automatic
        Drag.supportedActions: Qt.CopyAction
        Drag.onDragFinished: (action) => { tile.Drag.active = false; }
        DragHandler {
          target: null
          xAxis.enabled: false
          onActiveChanged: if (active) win.dragOut(tile, tile.modelData.path)
        }
        MouseArea {
          id: tileMa
          anchors.fill: parent
          hoverEnabled: true
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          onClicked: (m) => {
            keys.forceActiveFocus();
            const p = tile.modelData.path;
            if (m.button === Qt.RightButton) {
              win.showMenu(mapToItem(null, m.x, m.y), win.markCount > 1 && win.marks[p] ? "marked" : "tile", p);
              return;
            }
            if (m.modifiers & Qt.ControlModifier) { win.toggleMark(p); return; }
            win.go(tile.index);
          }
          onContainsMouseChanged: containsMouse ? tips.show(tile, tile.modelData.name) : tips.hide(tile)
        }
      }
    }
    // the rail, in the strip's bottom margin
    ScrollRail {
      target: stripList
      horizontal: true
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.leftMargin: 2
      anchors.rightMargin: 2
    }
    // The shell's one scroll (morpheus Elastic), turned on its side: a notch
    // is about a third of the strip, more when the wheel is spun; a
    // touchpad is followed and coasts; the ends give.
    ElasticScroll {
      anchors.fill: stripList
      view: stripList
      horizontal: true
      step: Math.max(212, Math.round(stripList.width / 3))
    }
  }

  // ── the edge tabs ───────────────────────────────────────────────────
  // One look for the three ways about: prev and next on the stage's sides,
  // and the strip's handle on its top edge (or the window's foot, the strip
  // put away). Each is a tab grown out of the edge it sits on — flush there,
  // rounded on the side that faces in — and leans out a little under the
  // pointer. Prev and next come up while the pointer is on the picture.
  Repeater {
    id: navTabs
    model: [
      { edge: "left",   d: -1 },
      { edge: "right",  d: 1 },
      { edge: "bottom", d: 0 }
    ]
    delegate: Rectangle {
      id: navTab
      required property var modelData
      readonly property string edge: navTab.modelData.edge
      readonly property bool side: navTab.edge !== "bottom"
      readonly property bool hot: navMa.containsMouse
      readonly property real depth: navTab.hot ? 22 : 17
      readonly property bool live: navTab.side
        ? win.index + navTab.modelData.d >= 0 && win.index + navTab.modelData.d < win.rows.length
        : true
      readonly property bool shown: navTab.side
        ? win.mode === "view" && navTab.live && (hoverWatch.hovered || navTab.hot) && !win.cropping
        : strip.can && !win.cropping && (!win.full || win.peekBottom)
      // Prev and next come up as the pointer nears their side, not anywhere
      // over the picture: full within 80px of the edge, gone past 240.
      readonly property real near: {
        if (!navTab.side || navTab.hot) return 1;
        const px = hoverWatch.point.position.x;
        const dist = navTab.edge === "left" ? px : stage.width - px;
        return Math.max(0, Math.min(1, 1 - (dist - 80) / 160));
      }
      readonly property string glyph: navTab.edge === "left" ? "\uf104"
        : navTab.edge === "right" ? "\uf105"
        : (win.stripShown ? "\uf107" : "\uf106")
      z: 4
      width: navTab.side ? navTab.depth : 52
      height: navTab.side ? 52 : navTab.depth
      x: navTab.edge === "left" ? stage.x
        : navTab.edge === "right" ? stage.x + stage.width - width
        : strip.x + (strip.width - width) / 2
      // the strip's tab over its top line by one, so the two read as one
      y: navTab.side ? stage.y + (stage.height - height) / 2 : strip.y - height + 1
      Behavior on width { enabled: navTab.side; NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }
      Behavior on height { enabled: !navTab.side; NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }
      // rounded only on the free side
      topLeftRadius: navTab.edge === "left" ? 0 : 7
      bottomLeftRadius: navTab.edge === "right" ? 7 : 0
      topRightRadius: navTab.edge === "right" ? 0 : 7
      bottomRightRadius: navTab.edge === "left" ? 7 : 0
      // solid: the strip's colour, laid over black rather than over what
      // is behind it
      readonly property color base: Qt.tint(Qt.tint(Zenon.ground, Zenon.layerBg), Zenon.headBg)
      color: navMa.pressed ? Qt.tint(navTab.base, Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.28))
        : navTab.hot ? Qt.tint(navTab.base, Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.16))
        : navTab.base
      border.width: 1
      border.color: Zenon.border
      opacity: navTab.shown ? navTab.near : 0
      visible: opacity > 0.01
      Behavior on opacity { NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }
      // a click leans it the way it goes, and it springs back
      transform: Translate { id: navNudge }
      SequentialAnimation {
        id: navNudgeAnim
        NumberAnimation { target: navNudge; property: navTab.side ? "x" : "y"
                          to: navTab.side ? navTab.modelData.d * 6 : (win.stripShown ? 4 : -4)
                          duration: Math.round(70 * Oracle.motionScale); easing.type: Easing.OutCubic }
        NumberAnimation { target: navNudge; property: navTab.side ? "x" : "y"; to: 0
                          duration: Math.round(260 * Oracle.motionScale); easing.type: Easing.OutBack; easing.overshoot: 2 }
      }
      // no line along the edge it grows out of
      Rectangle {
        color: navTab.color
        x: navTab.edge === "left" ? 0 : navTab.edge === "right" ? parent.width - 1 : 1
        y: navTab.side ? 1 : parent.height - 1
        width: navTab.side ? 1 : parent.width - 2
        height: navTab.side ? parent.height - 2 : 1
      }
      Text {
        anchors.centerIn: parent
        // nudged off the flush edge, into the middle of what shows
        anchors.horizontalCenterOffset: navTab.edge === "left" ? -1 : navTab.edge === "right" ? 1 : 0
        anchors.verticalCenterOffset: navTab.side ? 0 : 1
        text: navTab.glyph
        color: navTab.hot ? Zenon.cyan : Zenon.muted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(navTab.side ? 16 : 14)
      }
      MouseArea {
        id: navMa
        anchors.fill: parent
        anchors.margins: -4
        hoverEnabled: true
        onContainsMouseChanged: {
          if (navTab.side) stage.navHovered = containsMouse;
          if (!containsMouse) { tips.hide(navTab); return; }
          if (navTab.edge === "left") tips.show(navTab, "Previous", "\u2190");
          else if (navTab.edge === "right") tips.show(navTab, "Next", "\u2192");
          else tips.show(navTab, win.stripShown ? "Put the strip away" : "Show the strip",
                         win.stripShown ? "alt+j" : "alt+k");
        }
        onClicked: {
          keys.forceActiveFocus();
          navNudgeAnim.restart();
          if (navTab.side) win.step(navTab.modelData.d);
          else win.toggleStrip();
        }
      }
    }
  }

  // ── the edit panel ────────────────────────────────────────────────────
  Rectangle {
    id: panel
    anchors.top: bar.bottom
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    // wide enough for LookEditor's tint swatches on one row: 318 of them,
    // plus the 20 of margin either side and room for the ring
    readonly property real full: 370
    width: win.panelShown && win.mode === "view" && !win.isVid ? panel.full : 0
    // it slides in and out; the picture refits beside it as it goes
    Behavior on width { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }
    visible: width > 0
    clip: true
    color: Zenon.headBg
    Rectangle { anchors.left: parent.left; width: 1; height: parent.height; color: Zenon.border; z: 2 }

    // the picture under it, frosted (see `canvas`): the panel lies over the
    // picture rather than beside it once it is zoomed past the room
    Frost {
      anchors.fill: parent
      z: -1
      source: stage
      active: win.picShows && !win.compare && win.picRight > panel.x
    }

    // Its insides at their full width all the while, held to the panel's
    // left edge: they slide in with it rather than squeeze to fit.
    Item {
      id: panelBody
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: panel.full

      Flickable {
        id: panelFlick
        ElasticScroll { view: panelFlick }
        anchors.fill: parent
        anchors.margins: 20
        anchors.bottomMargin: 72
        contentHeight: win.editingColor === "" ? panelCol.implicitHeight : tintCol.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: panelCol
          width: panelFlick.width
          spacing: 8
          visible: win.editingColor === ""

          Head { text: "Turn" }
          Row {
            spacing: 4
            Seg { width: 96; label: "  Left"; onHit: win.turn(-90) }
            Seg { width: 96; label: "  Right"; onHit: win.turn(90) }
            Seg { width: 96; label: "  Mirror"; chosen: win.look.mirror
                  onHit: win.setLook("mirror", !win.look.mirror) }
          }

          Item { width: 1; height: 8 }
          Item {
            width: parent.width
            height: cropHead.height
            Head { id: cropHead; text: "Crop" }
            Text {
              anchors.right: parent.right
              visible: win.crop !== null
              text: "Clear"
              color: clearMa.containsMouse ? Zenon.cyan : Zenon.soft
              font.family: Zenon.face
              font.weight: 600
              font.pixelSize: Zenon.px(13)
              MouseArea { id: clearMa; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true
                          onClicked: { win.crop = null; win.cropping = false; } }
            }
          }
          Flow {
            width: parent.width
            spacing: 4
            Repeater {
              model: win.cropRatios
              delegate: Seg {
                required property var modelData
                width: modelData.k.indexOf("mon:") === 0 ? 144 : 70
                height: 30
                label: modelData.t
                chosen: win.cropping && win.cropRatio === modelData.k
                current: !win.cropping && win.crop !== null && win.cropRatio === modelData.k
                onHit: win.startCrop(modelData.k)
              }
            }
          }
          Seg {
            width: parent.width
            height: 30
            label: "\uf065  Trim black borders"
            onHit: win.trimBorders()
          }
          Slide {
            width: parent.width
            label: "Straighten"
            from: -15
            to: 15
            rest: 0
            value: win.straighten
            valueText: (win.straighten > 0 ? "+" : "") + win.straighten.toFixed(1) + "\u00b0"
            onMoved: (v) => {
              win.straighten = Math.round(v * 10) / 10;
              win.straightening = true;
              straightenSeen.restart();
            }
          }
          Text {
            width: parent.width
            visible: win.cropping
            text: "drag the box or its edges, or draw a new one · esc when done"
            color: Zenon.soft
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(12)
            wrapMode: Text.WordWrap
          }

          // terminus' conversion and its targets — see convertTo
          Item { width: 1; height: 8 }
          Head { text: "Convert" }
          Row {
            spacing: 4
            Repeater {
              model: Terminus.convertTargets()
              delegate: Seg {
                required property var modelData
                width: 106
                height: 42
                onHit: win.convertTo(modelData.ext)
                Column {
                  anchors.centerIn: parent
                  spacing: 1
                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: modelData.ext.toUpperCase()
                    color: Zenon.white
                    font.family: Zenon.face
                    font.weight: 600
                    font.pixelSize: Zenon.px(13)
                  }
                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: modelData.hint
                    color: Zenon.soft
                    font.family: Zenon.face
                    font.weight: Zenon.weight
                    font.pixelSize: Zenon.px(11)
                  }
                }
              }
            }
          }
          Text {
            width: parent.width
            text: win.edited ? "a new file beside it, with the edit" + (win.crop ? " and the crop" : "")
                             : "a new file beside it — the original stays"
            color: Zenon.soft
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(12)
            wrapMode: Text.WordWrap
          }

          Item { width: 1; height: 8 }
          Head { text: "Look" }
          LookEditor {
            width: parent.width
            look: win.look
            path: win.path
            showBackdrop: false
            customTint: win.customTint
            tips: tips
            onTouched: (key, value) => win.setLook(key, value)
            onResetLook: win.stageLook = ({})
            onEditColor: (which) => win.editingColor = which
          }
        }

        // the custom tint, chosen
        Column {
          id: tintCol
          width: panelFlick.width
          spacing: 12
          visible: win.editingColor !== ""
          Item {
            width: parent.width
            height: tintHead.height
            Head { id: tintHead; text: "Tint colour" }
            Text {
              anchors.right: parent.right
              text: "Done"
              color: doneMa.containsMouse ? Zenon.cyan : Zenon.white
              font.family: Zenon.face
              font.weight: 600
              font.pixelSize: Zenon.px(14)
              MouseArea { id: doneMa; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true
                          onClicked: win.editingColor = "" }
            }
          }
          ColorPicker {
            width: parent.width
            height: 250
            textSize: 14
            hex: win.look.tint !== "" && win.look.tint !== "accent" ? win.look.tint : win.customTint
            onEdited: (h) => { win.customTint = h; win.setLook("tint", h); }
            onAccepted: win.editingColor = ""
            onCancelled: win.editingColor = ""
          }
        }
      }

      Row {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 18
        spacing: 8
        DialogButton { label: "Reset"; ink: Zenon.muted; ready: win.edited; onClicked: win.resetEdit() }
        DialogButton { label: "Save New"; ink: Zenon.white; ready: win.edited || win.scratch; onClicked: win.saveNew() }
        DialogButton { label: "Save"; ink: Zenon.cyan; primary: true; ready: win.edited; onClicked: win.save() }
      }

      // a short window leaves the panel taller than it: the rail, in the
      // right margin
      ScrollRail {
        target: panelFlick
        anchors.right: parent.right
        anchors.rightMargin: 4
        anchors.top: panelFlick.top
        anchors.bottom: panelFlick.bottom
      }
    }
  }

  function ratioValue(k) {
    for (const c of win.cropRatios) if (c.k === k) {
      if (c.r === -1) return win.th > 0 ? win.tw / win.th : 0;
      if (c.r === -2) {
        const s = win.screen;
        return s && s.height > 0 ? s.width / s.height : 16 / 9;
      }
      return c.r;
    }
    return 0;
  }
  function startCrop(k) {
    if (!win.loaded) return;
    win.cropRatio = k;
    win.cropStaged = true;
    const ratio = win.ratioValue(k);
    // a ratio chosen re-shapes the box around its middle; free keeps the
    // box there is, or starts from most of the picture
    if (ratio > 0) win.crop = V.centredCrop(win.tw, win.th, ratio);
    else if (!win.crop) win.crop = { x: Math.round(win.tw * 0.05), y: Math.round(win.th * 0.05),
                                     w: Math.round(win.tw * 0.9), h: Math.round(win.th * 0.9) };
    win.cropping = true;
    win.fitted = true;
    win.refit(true);
  }

  // ── info ──────────────────────────────────────────────────────────────
  // FROSTED, as terminus' menus are: a surface of its own (a popup), which
  // hyprland blurs — an item inside the window can only be drawn over the
  // picture, never blur it. Placed against `infoSpot`, top right of the
  // stage; the surface is exactly the card.
  Item {
    id: infoSpot
    anchors.top: bar.bottom
    anchors.topMargin: 12
    anchors.right: win.compare ? twin.right : panel.left
    anchors.rightMargin: 12
    width: 380
    height: 1
    // a popup's rect is read when it is placed: moved, it is placed again
    onXChanged: if (infoPop.visible) infoPop.anchor.updateAnchor()
  }
  PopupWindow {
    id: infoPop
    // under a question, never over it: the sheet is in the window, this is not
    visible: win.infoShown && win.mode === "view" && win.row !== null && !confirm.open && !bulkCard.open
    color: "transparent"
    implicitWidth: info.width
    implicitHeight: info.height
    anchor {
      window: win
      rect.x: infoSpot.x
      rect.y: infoSpot.y
      rect.width: 1
      rect.height: 1
      adjustment: PopupAdjustment.None
    }
    Rectangle {
      id: info
      width: 380
      height: infoCol.implicitHeight + 32
      radius: Zenon.dialogRadius
      color: Zenon.frostBg
      border.width: 1
      border.color: Zenon.border

      Column {
        id: infoCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 16
        spacing: 7
        Repeater {
          model: {
            if (!win.row) return [];
            const out = [
              { k: "Name", v: win.row.name },
              { k: "Directory", v: win.dir.replace(Paths.home(), "~") },
              { k: "Size", v: win.nw > 0 ? Math.round(win.nw) + " × " + Math.round(win.nh) : "" },
              { k: "File", v: Terminus.formatSize(win.row.size) + "  ·  " + Terminus.extOf(win.row.name).toUpperCase() },
              { k: "Modified", v: new Date(win.row.mtime * 1000).toLocaleString(Qt.locale(), "yyyy-MM-dd HH:mm") }
            ];
            if (win.isVid && win.vid) out.push({ k: "Length", v: V.clock(win.vid.duration) });
            const tg = win.tags[win.path] || [];
            if (tg.length > 0) out.push({ k: "Tags", v: tg.map((t) => t === V.FAVOURITE ? "\u2605" : t).join(", ") });
            const more = win.exif.slice();
            // where it was taken: a link to the map — and a word that a copy
            // sent on would say so too
            if (win.gps) more.push({ k: "Location", v: win.gps.lat + ", " + win.gps.lon, url: V.mapUrl(win.gps) },
                                   { k: "", v: "on the map, among the others", mapAt: true },
                                   { k: "", v: "a copy sent on says where — the menu's Copy has one without", note: true });
            return out.concat(more);
          }
          delegate: Row {
            required property var modelData
            spacing: 12
            Text {
              width: 104
              text: modelData.k
              color: Zenon.muted
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(14)
            }
            Text {
              width: infoCol.width - 116
              text: modelData.v
              color: modelData.url || modelData.mapAt ? (linkMa.containsMouse ? Zenon.cyan : Zenon.blue)
                : (modelData.note ? Zenon.muted : Zenon.white)
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(modelData.note ? 12 : 14)
              font.underline: (!!modelData.url || !!modelData.mapAt) && linkMa.containsMouse
              wrapMode: modelData.note ? Text.WordWrap : Text.WrapAnywhere
              MouseArea {
                id: linkMa
                anchors.fill: parent
                enabled: !!modelData.url || !!modelData.mapAt
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: modelData.mapAt ? win.openMap(win.gps) : Qt.openUrlExternally(modelData.url)
              }
            }
          }
        }
        // red, green and blue, and the light (the line over them)
        Canvas {
          id: histCanvas
          width: infoCol.width
          height: win.hist && win.hist.pixels > 0 ? 64 : 0
          visible: height > 0
          onWidthChanged: requestPaint()
          onHeightChanged: requestPaint()
          Connections { target: win; function onHistChanged() { histCanvas.requestPaint(); } }
          Connections { target: Zenon; function onThemeChanged() { histCanvas.requestPaint(); } }
          onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const h = win.hist;
            if (!h || !(h.max > 0)) return;
            const n = h.r.length, bw = width / n;
            // square-rooted: a picture is mostly a few tones, and on a straight
            // scale everything else is a line along the floor
            const yOf = (v) => height - height * Math.sqrt(v / h.max);
            const shape = (arr) => {
              ctx.beginPath();
              ctx.moveTo(0, height);
              for (let i = 0; i < n; ++i) { ctx.lineTo(i * bw, yOf(arr[i])); ctx.lineTo((i + 1) * bw, yOf(arr[i])); }
              ctx.lineTo(width, height);
              ctx.closePath();
            };
            const ink = (c, a) => "rgba(" + Math.round(c.r * 255) + ", " + Math.round(c.g * 255) + ", "
              + Math.round(c.b * 255) + ", " + a + ")";
            ctx.globalCompositeOperation = "lighter";
            for (const c of [["r", Zenon.red], ["g", Zenon.green], ["b", Zenon.blue]]) {
              ctx.fillStyle = ink(c[1], 0.45);
              shape(h[c[0]]);
              ctx.fill();
            }
            ctx.globalCompositeOperation = "source-over";
            ctx.strokeStyle = ink(Zenon.white, 0.7);
            ctx.lineWidth = 1;
            shape(h.l);
            ctx.stroke();
          }
        }
        // its own colours, the most used first — a click copies one
        Row {
          visible: win.palette.length > 0
          spacing: 6
          Repeater {
            model: win.palette
            delegate: Rectangle {
              id: sw
              required property var modelData
              width: Math.floor((infoCol.width - 6 * 7) / 8)
              height: 26
              radius: 5
              color: sw.modelData.hex
              border.width: 1
              border.color: swMa.containsMouse ? Zenon.white : Zenon.wash(0.25)
              MouseArea {
                id: swMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | wl-copy", "sh", sw.modelData.hex]);
                  win.say(sw.modelData.hex + " copied");
                }
              }
            }
          }
        }
      }
    }
  }

  // ── annotation ────────────────────────────────────────────────────────
  Loader {
    id: annLoader
    anchors.fill: parent
    z: 8
    active: win.mode === "annotate" && win.path !== ""
    sourceComponent: Annotator {
      path: win.path
      fileManager: win.fileManager
      // marks saved over the picture itself: the original kept first, for u
      guard: (file, write) => win.keepCopies([file], write)
      // On its own — the screenshot's toast — Back is into the viewer too:
      // the window stops being a lone annotation and opens the picture's
      // directory at it (or at the copy the marks were saved to).
      onFinished: {
        if (!win.solo) { win.mode = "view"; return; }
        const at = win.soloFile !== "" ? win.soloFile : win.path;
        win.solo = false;
        win.soloFile = "";
        win.load([at], "view");
      }
      // Saved over itself, the marks carry on; saved as a new file, that file
      // is where the marks now live, and it is shown instead. On its own the
      // window has nothing else to show, and stays with its marks.
      onSaved: (file) => {
        if (win.solo) { win.soloFile = file; return; }
        if (file !== win.path) win.mode = "view";
        win.afterSave(file);
      }
      Rectangle { anchors.fill: parent; z: -1; color: Zenon.layerBg }
    }
    onLoaded: item.takeFocus()
  }

  // every button's name, under it
  WindowTip { id: tips; window: win }

  // ── the right-click menu ──────────────────────────────────────────────
  // morpheus' CardPopup — the card every menu here is, hung off a point in
  // this window — as plato's file tree uses it. Inside a selection it is
  // about the selection; anywhere else, about the picture.
  function openMenu(at, onSelection) {
    if (win.path === "") return;
    win.showMenu(at, onSelection && win.crop !== null ? "selection" : "picture", win.path);
  }
  function showMenu(at, kind, p) {
    menu.kind = kind;
    menu.subject = p;
    // held while the card is up — it moves with the pointer otherwise
    menu.pixel = win.pixel;
    menu.at = at;
    menu.open = true;
  }
  // A gallery tile's menu: a directory's, the marked pictures' (when it is one
  // of several marked), or the picture's own; between tiles, the gallery's.
  function galleryMenu(i, at) {
    const it = i >= 0 ? win.galleryItems[i] : null;
    if (!it || it.isFill) { win.showMenu(at, "gallery", ""); return; }
    if (it.isDir) { win.showMenu(at, "directory", it.path); return; }
    if (win.markCount > 1 && win.marks[it.path]) { win.showMenu(at, "marked", it.path); return; }
    // The cursor stays where it was (user, 2026-10-09): the tile is held —
    // HeldRing — and the verbs act on its path (menu.pick).
    menu.heldAt = i;
    win.showMenu(at, "cell", it.path);
  }

  function zoomToCrop() {
    const c = win.crop;
    if (!c) return;
    const m = 2 * win.margin;
    const z = V.clampZoom(V.fitScale(c.w, c.h, stage.width - m, stage.height - m, 32));
    win.fitted = false;
    win.setView(V.clampView({ z: z, x: stage.width / 2 - (c.x + c.w / 2) * z,
                              y: stage.height / 2 - (c.y + c.h / 2) * z },
                            win.tw, win.th, stage.width, stage.height), Zenon.normal);
  }

  function copySelection() {
    win.grabEdit((tmp) => {
      if (tmp === "") { win.say("could not copy the selection"); return; }
      win.run(["sh", "-c", 'wl-copy --type image/png < "$1"; rm -f "$1"', "sh", tmp]);
      win.say("selection copied to the clipboard");
    });
  }

  // ── converting ────────────────────────────────────────────────────
  // terminus' conversion, and terminus' targets. The picture as it is on
  // disk goes through its convertCommand — a new file beside it, never over
  // it. An edit or a selection is rendered first (the same grab a save
  // makes) and that render converted into the directory under a free name, so
  // what is converted is what is on screen.
  function convertTo(ext) {
    if (win.path === "" || !win.stillOnly()) return;
    const withEdit = win.crop !== null || win.straighten !== 0 || Object.keys(Art.lookDiff(win.look)).length > 0;
    if (!withEdit) {
      win.run(Terminus.shArgv(Terminus.convertCommand([win.path], ext)), (code) => {
        win.say(code === 0 ? "converted to " + ext + " beside it" : "could not convert it");
        if (code === 0) { win.want = win.path; win.startMode = win.mode; win.list(); }
      });
      return;
    }
    win.grabEdit((tmp) => {
      if (tmp === "") { win.say("could not render the edit"); return; }
      const name = V.editedName(win.path, win.crop ? "crop" : "edited").replace(/\.[^.]+$/, "." + ext);
      win.run(Terminus.shArgv(Terminus.convertIntoCommand(tmp, win.dir, name)), (code) => {
        win.run(["rm", "-f", tmp]);
        if (code !== 0) { win.say("could not convert it"); return; }
        win.say((win.crop ? "selection" : "edit") + " saved as " + ext + " beside it");
        win.resetEdit();
        win.want = win.path; win.startMode = win.mode; win.list();
      });
    });
  }

  function cropTool() {
    if (!win.stillOnly()) return;
    win.panelShown = true;
    win.startCrop(win.crop ? win.cropRatio : "free");
  }

  // The black strips round it — a letterbox, a scan's edge — found by
  // ImageMagick (viewer.js trimCommand) and set up as a free crop, in the
  // crop tool, to be nudged and saved like any other; nothing is written.
  function trimBorders() {
    if (!win.stillOnly() || !win.loaded) return;
    const file = win.fallback !== "" ? win.fallback : win.path;
    const at = win.path, w = win.tw, h = win.th;
    win.capture(["sh", "-c", V.trimCommand(win.look.rotate, win.look.mirror) + " 2>/dev/null", "sh", file], (out) => {
      if (win.path !== at) return;
      const r = V.parseTrim(out, w, h);
      if (!r) { win.say("could not find the picture's edges"); return; }
      if (r.none) { win.say("no black borders to trim"); return; }
      win.panelShown = true;
      win.cropRatio = "free";
      win.cropStaged = true;
      win.crop = r;
      win.cropping = true;
      win.fitted = true;
      win.refit(true);
      win.say("black borders trimmed  \u00b7  " + r.w + " \u00d7 " + r.h + "  \u00b7  ctrl+s saves");
    });
  }

  // The rows of each card. A branch carries its rows as `children`, and
  // CardPopup opens them beside it on hover — see its BRANCHES.
  function menuRows(kind, p) {
    const sep = { isSeparator: true };
    const ps = kind === "marked" || kind === "convertFiles" ? win.targets(p) : (p ? [p] : []);
    const branch = (text, icon, sub) => ({ text: text, icon: icon, children: win.menuRows(sub, p) });
    const editIn = Oracle.imageEditor === "" ? [] : [
      // oracle's Default Apps image editor, for what picasso's own edit
      // does not reach — layers, painting, a raw file's development
      { text: "Edit in " + Oracle.imageEditorName, icon: "\uf1de", act: "editIn" }];
    const tagRows = [
      { text: ps.length > 0 && ps.every((q) => win.starred(q)) ? "Unstar" : "Star", icon: "\uf005", act: "star", hint: "*" },
      { text: ps.length > 1 ? "Add tags…" : "Tags…", icon: "\uf02b", act: "tags", hint: "t", asks: true }];
    // a function, not a list: its Save as branch builds rows that build this
    const fileRows = () => [
      { text: "Copy to…", icon: "\uf0c5", act: "copyTo", asks: true },
      { text: "Move to…", icon: "\uf064", act: "moveTo", asks: true },
      { text: "Turn right", icon: "\uf01e", act: "rotR", hint: "in the file" },
      { text: "Turn left", icon: "\uf0e2", act: "rotL", hint: "in the file" },
      branch("Save as", "\uf0ec", "convertFiles")];
    const pick = menu.pixel;
    const tools = win.mgr ? win.mgr.tools : {};
    const exportRows = () => V.EXPORTS.map((x, i) => ({ text: x.t, icon: "\uf1d8", act: "export", preset: i }))
      .concat([{ isSeparator: true }, { text: "Into a directory…  \u00b7  2048 px WebP", icon: "\uf07c", act: "exportTo", asks: true }]);

    switch (kind) {
    case "selection":
      return [
        { text: "Copy selection", icon: "\uf0c5", act: "copySel" },
        { text: "Copy the text in it", icon: "\uf031", act: "ocr" },
        { text: "Save selection as…", icon: "\uf0c7", act: "saveNew" },
        { text: "Crop and save", icon: "\uf125", act: "save" },
        { text: "Set selection as background", icon: "\uf108", act: "background" },
        sep
      ].concat(Terminus.convertTargets().map((t) =>
        ({ text: "Save selection as " + t.ext.toUpperCase() + "  \u00b7  " + t.hint,
           icon: "\uf0ec", act: "conv", ext: t.ext }))).concat([
        sep,
        { text: "Zoom to selection", icon: "\uf00e", act: "zoomSel" },
        { text: "Clear selection", icon: "\uf00d", act: "clearSel" }
      ]);

    case "picture":
      return [
        { text: "Copy picture", icon: "\uf0c5", act: "copy", hint: "ctrl+c" },
        branch("Copy", "\uf0c1", "copy"),
        sep,
        { text: "Annotate", icon: "\uf040", act: "annotate", hint: "a", enabled: win.fallback === "" },
        { text: "Edit", icon: "\uf1de", act: "edit", hint: "e" }
      ].concat(editIn).concat([
        { text: "Crop…", icon: "\uf125", act: "crop", hint: "c" },
        { text: "Trim black borders", icon: "\uf065", act: "trim", hint: "C" },
        { text: "Turn right", icon: "\uf01e", act: "turn", hint: "r" },
        { text: "Set as background", icon: "\uf108", act: "background", hint: "w" },
        sep
      ]).concat(tagRows).concat([
        { text: "Rename…", icon: "\uf246", act: "rename", hint: "F2", asks: true },
        { text: win.marks[p] ? "Unmark" : "Mark", icon: "\uf00c", act: "mark", hint: "x" },
        sep,
        branch("View", "\uf06e", "view"),
        branch("Save as", "\uf0ec", "convert"),
        branch("Make from it", "\uf0d0", "improve"),
        branch("Export for the web", "\uf1d8", "export"),
        sep,
        { text: "Show in terminus", icon: "\uf07c", act: "reveal", hint: "o" },
        { text: "Properties", icon: "\uf05a", act: "props", hint: "alt+enter" },
        { text: "Move to trash", icon: "\uf1f8", act: "trash", hint: "d" },
        { text: "Delete permanently…", icon: "\uf00d", act: "deleteP", hint: "D", asks: true }
      ]);

    case "improve":
      return [
        { text: "Enhanced copy", icon: "\uf0d0", act: "make", kind: "enhance", hint: "levels, tone, sharpness" }
      ].concat(tools.rembg ? [{ text: "Cut out the subject", icon: "\uf0c4", act: "make", kind: "cutout", hint: "rembg" }]
                           : [{ text: "Cut out the subject", icon: "\uf0c4", enabled: false, hint: "needs rembg" }])
       .concat(tools["realesrgan-ncnn-vulkan"] || tools["upscayl-bin"]
         ? [{ text: "Four times the size", icon: "\uf065", act: "make", kind: "upscale", hint: "Real-ESRGAN" }]
         : [{ text: "Four times the size", icon: "\uf065", enabled: false, hint: "needs realesrgan-ncnn-vulkan" }]);

    case "export":
      return exportRows();

    case "places":
      return win.placeRows();

    case "copy":
      return ([
        { text: "Copy path", icon: "\uf0c1", act: "copyPath", hint: "ctrl+shift+c" },
        { text: "Copy as a file", icon: "\uf15b", act: "copyFiles" },
        { text: "Copy without metadata", icon: "\uf070", act: "copyClean" },
        { text: "Copy the text in it", icon: "\uf031", act: "ocr" }
      ]).concat(pick ? [
        { text: "Copy colour " + pick.hex, icon: "\uf1fb", act: "colour", hint: "y" },
        { text: "Tint the picture " + pick.hex, icon: "\uf1fb", act: "tintPick" }
      ] : []);

    case "view":
      return ([
        { text: win.compare ? "Stop comparing" : "Compare with the next", icon: "\uf0db", act: "compare", hint: "v" },
        { text: "Lock the zoom", icon: "\uf023", act: "zoomLock", hint: "z", mark: win.zoomLock },
        { text: win.playing ? "Stop the slideshow" : "Slideshow", icon: "\uf04b", act: "play", hint: "s" },
        { text: "Slideshow slower", icon: "\uf017", act: "slower", hint: "[   now " + win.slideSecs + " s" },
        { text: "Slideshow faster", icon: "\uf017", act: "faster", hint: "]" },
        { text: "Shuffle the slideshow", icon: "\uf074", act: "shuffle", mark: win.shuffle },
        { text: "Fullscreen", icon: "\uf065", act: "full", hint: "f" },
        { text: "The strip", icon: "\uf00a", act: "strip", hint: "alt+j  alt+k", mark: win.stripShown },
        { text: "Monitor outlines", icon: "\uf108", act: "monitors", hint: "W", mark: stage.monitorsShown },
        { text: "Map of the directory", icon: "\uf279", act: "map", enabled: win.rows.length > 0 },
        { text: "Info", icon: "\uf129", act: "info", hint: "i", mark: win.infoShown }
      ]);

    case "convert":
      return (Terminus.convertTargets().map((t) =>
        ({ text: "Convert to " + t.ext.toUpperCase() + "  \u00b7  " + t.hint, icon: "\uf0ec", act: "conv", ext: t.ext })))
        .concat([sep, { text: "A copy without metadata", icon: "\uf070", act: "saveClean" }]);

    case "convertFiles":
      return (Terminus.convertTargets().map((t) =>
        ({ text: "Convert to " + t.ext.toUpperCase() + "  \u00b7  " + t.hint, icon: "\uf0ec", act: "convFiles", ext: t.ext })))
        .concat([sep, { text: ps.length > 1 ? "Copies without metadata" : "A copy without metadata",
                        icon: "\uf070", act: "saveClean" }]);

    case "tile":
    case "cell": {
      const bAt = win.burstAt[win.rowIndex[p]];
      return [
        { text: "Open", icon: "\uf06e", act: "open", hint: kind === "cell" ? "enter" : "" }
      ].concat(kind === "cell" && bAt ? [{ text: bAt.open ? "Fold the burst" : "Open the burst  \u00b7  " + bAt.n,
                                           icon: "\uf24d", act: "fold", key: bAt.key, fold: bAt.open }] : []).concat([
        { text: "Compare with the shown picture", icon: "\uf0db", act: "compareWith", enabled: p !== win.path },
        { text: "Annotate", icon: "\uf040", act: "annotateP" },
        { text: "Set as background", icon: "\uf108", act: "bgFile" },
        sep
      ].concat(tagRows).concat([
        { text: "Rename…", icon: "\uf246", act: "rename", hint: "F2", asks: true },
        { text: win.marks[p] ? "Unmark" : "Mark", icon: "\uf00c", act: "mark", hint: "x" },
        sep,
        branch("Copy", "\uf0c5", "copyCell"),
        branch("Export for the web", "\uf1d8", "export")
      ]).concat(fileRows()).concat(editIn).concat([
        sep,
        { text: "Show in terminus", icon: "\uf07c", act: "reveal" },
        { text: "Properties", icon: "\uf05a", act: "props", hint: "alt+enter" },
        { text: "Move to trash", icon: "\uf1f8", act: "trashP", hint: "d" },
        { text: "Delete permanently…", icon: "\uf00d", act: "deleteP", hint: "D", asks: true }
      ]));
    }

    case "copyCell":
      return ([
        { text: "Copy picture", icon: "\uf0c5", act: "copyP" },
        { text: "Copy path", icon: "\uf0c1", act: "copyPathP" },
        { text: "Copy as a file", icon: "\uf15b", act: "copyFiles", hint: "ctrl+c" },
        { text: "Copy without metadata", icon: "\uf070", act: "copyCleanP" }
      ]);

    case "marked":
      return [
        { text: ps.length + " marked pictures", icon: "\uf00c", enabled: false },
        sep,
        { text: "View just these", icon: "\uf06e", act: "viewMarked" },
        { text: "Slideshow of these", icon: "\uf04b", act: "showMarked" }
      ].concat(ps.length === 2 ? [{ text: "Compare the two", icon: "\uf0db", act: "compare", hint: "v" }] : []).concat([
        sep
      ]).concat(tagRows).concat([
        { text: "Copy as files", icon: "\uf15b", act: "copyFiles", hint: "ctrl+c" },
        branch("Export for the web", "\uf1d8", "export"),
        { text: "Contact sheet…", icon: "\uf00a", act: "sheet", asks: true },
        { text: "Rename (" + ps.length + ")", icon: "\uf246", act: "bulkRename", hint: "F2", asks: true }
      ]).concat(fileRows()).concat([
        sep,
        { text: "Unmark all", icon: "\uf00d", act: "unmarkAll", hint: "esc" },
        { text: "Properties", icon: "\uf05a", act: "props", hint: "alt+enter" },
        { text: "Move " + ps.length + " to trash", icon: "\uf1f8", act: "trashP", hint: "d" },
        { text: "Delete " + ps.length + " permanently…", icon: "\uf00d", act: "deleteP", hint: "D", asks: true }
      ]);

    case "directory":
      return [
        { text: "Open", icon: "\uf07c", act: "openDirectory", hint: "enter" },
        { text: "Slideshow of it", icon: "\uf04b", act: "showDirectory" },
        { text: "Show in terminus", icon: "\uf07c", act: "revealDirectory" },
        { text: "Copy path", icon: "\uf0c1", act: "copyPathP" },
        sep,
        { text: "Properties", icon: "\uf05a", act: "props", hint: "alt+enter" }
      ];

    case "gallery": {
      const starOnly = V.splitFilter(win.filterText).tags.indexOf(V.FAVOURITE) >= 0;
      return (win.dupes ? [
        { text: "Mark all but the best of each", icon: "\uf00c", act: "markDupes" },
        { text: "Stop showing alike pictures", icon: "\uf00d", act: "dupes", hint: "esc" },
        sep
      ] : []).concat([
        { text: "Paste into this directory", icon: "\uf0ea", act: "paste", enabled: win.picked.length === 0 && win.dir !== "" },
        { text: "Look at the clipboard", icon: "\uf03e", act: "pasteLook", hint: "ctrl+v" },
        sep,
        { text: "Mark all", icon: "\uf00c", act: "markAll", hint: "ctrl+a", enabled: win.rows.length > 0 }
      ].concat(win.markCount > 0 ? [{ text: "Unmark all", icon: "\uf00d", act: "unmarkAll", hint: "esc" }] : []).concat([
        { text: "Filter…", icon: "\uf0b0", act: "filter", hint: "/" },
        { text: "Only the starred", icon: "\uf005", act: "starredOnly", mark: starOnly },
        branch("Order", "\uf0dc", "order"),
        { text: "Fold bursts", icon: "\uf24d", act: "bursts", mark: !!(win.mgr && win.mgr.groupBursts) },
        { text: win.dupes ? "Stop showing alike pictures" : "Find alike pictures", icon: "\uf24d", act: "dupes",
          enabled: win.dupes !== null || win.allRows.length > 1 },
        { text: "Map of these", icon: "\uf279", act: "map", hint: "M", enabled: win.rows.length > 0 },
        sep,
        { text: "Contact sheet of " + (win.markCount > 0 ? "the marked" : "all") + "…", icon: "\uf00a", act: "sheetAll",
          asks: true, enabled: win.rows.length > 0 },
        { text: "Tags in .xmp sidecars too", icon: "\uf02c", act: "xmp", mark: !!(win.mgr && win.mgr.xmpSidecars),
          enabled: win.exiftool, hint: win.exiftool ? "darktable, digiKam" : "needs exiftool" },
        branch("Places", "\uf07c", "places"),
        sep,
        { text: "Slideshow", icon: "\uf04b", act: "play", hint: "s", enabled: win.rows.length > 1 },
        { text: "Show in terminus", icon: "\uf07c", act: "reveal", enabled: win.dir !== "" },
        { text: "Properties of this directory", icon: "\uf05a", act: "props", enabled: win.dir !== "" && win.picked.length === 0 }
      ]));
    }

    case "custom":
      return menu.custom;

    case "order":
      return ([{ k: "name", t: "Name" }, { k: "time", t: "Newest" }, { k: "size", t: "Largest" },
               { k: "taken", t: "Taken, by date" }]
        .map((o) => ({ text: o.t, act: "sort", key: o.k, mark: win.sortKey === o.k, enabled: win.picked.length === 0 })));

    case "slides":
      return [
        { text: win.playing ? "Stop the slideshow" : "Start the slideshow", icon: win.playing ? "\uf04c" : "\uf04b",
          act: "play", hint: "s", enabled: win.rows.length > 1 },
        sep
      ].concat(V.SLIDE_SECS.map((n) => ({ text: "Every " + n + " seconds", act: "secs", secs: n, mark: win.slideSecs === n })))
        .concat([sep, { text: "Shuffle", icon: "\uf074", act: "shuffle", mark: win.shuffle }]);
    }
    return [];
  }

  // A row of any card, done. `p` is the picture the card was opened on;
  // what happens to files happens to win.targets(p) — the marked ones when
  // `p` is among them.
  function act(row, p) {
    const ps = win.targets(p);
    switch (row.act) {
    case "fn": if (row.fn) row.fn(); break;
    case "props": win.showProps(p !== "" ? ps : [win.dir]); break;
    case "copySel": win.copySelection(); break;
    case "saveNew": win.saveNew(); break;
    case "save": win.save(); break;
    case "background": win.toBackground(); break;
    case "bgFile": Picasso.setAsWallpaper(p, {}); break;
    case "zoomSel": win.zoomToCrop(); break;
    case "clearSel": win.crop = null; win.cropping = false; break;
    case "copy": win.copyImage(); break;
    case "copyP": win.run(["sh", "-c", "wl-copy < \"$1\"", "sh", p]); win.say("copied to the clipboard"); break;
    case "copyPath": win.copyPath(); break;
    case "copyPathP":
      Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | wl-copy", "sh", p]);
      win.say("path copied");
      break;
    case "copyFiles": win.copyFiles(ps); break;
    case "copyClean": win.copyClean(); break;
    case "copyCleanP":
      win.run(["sh", "-c", 'magick -- "$1[0]" -auto-orient -strip png:- | wl-copy --type image/png', "sh", p],
        (code) => win.say(code === 0 ? "copied, without its metadata" : "could not copy it"));
      break;
    case "saveClean": win.saveClean(ps); break;
    case "ocr": win.readText(); break;
    case "colour": if (menu.pixel) { win.pixel = menu.pixel; win.copyColour(); } break;
    case "tintPick":
      if (!menu.pixel) break;
      win.customTint = menu.pixel.hex;
      win.panelShown = true;
      win.setLook("tint", menu.pixel.hex);
      break;
    case "annotate": win.annotate(); break;
    case "annotateP":
      win.go(V.indexOfPath(win.rows, p));
      win.mode = "view";
      Qt.callLater(win.annotate);
      break;
    case "edit": win.panelShown = true; break;
    case "editIn": win.editIn(); break;
    case "crop": win.cropTool(); break;
    case "trim": win.trimBorders(); break;
    case "turn": win.panelShown = true; win.turn(90); break;
    case "star": win.toggleStar(p); break;
    case "tags": win.editTags(p); break;
    case "rename": win.rename(p); break;
    case "mark": win.toggleMark(p); break;
    case "markAll": win.markAll(); break;
    case "unmarkAll": win.marks = ({}); break;
    case "compare": win.startCompare(); break;
    case "compareWith": win.mode = "view"; win.startCompare(p); break;
    case "zoomLock": win.zoomLock = !win.zoomLock; break;
    case "play":
      win.playing = !win.playing;
      if (win.playing && win.mode === "gallery" && win.rows.length > 0) win.mode = "view";
      break;
    case "secs": if (win.mgr) win.mgr.setSlides(row.secs, win.shuffle); win.say("slideshow, every " + row.secs + " s"); break;
    case "shuffle": win.setShuffle(!win.shuffle); break;
    case "slower": win.pace(1); break;
    case "faster": win.pace(-1); break;
    case "full": win.fullscreen(); break;
    case "info": win.infoShown = !win.infoShown; break;
    case "strip": win.toggleStrip(); break;
    case "monitors": stage.monitorsShown = !stage.monitorsShown; break;
    case "conv": win.convertTo(row.ext); break;
    case "convFiles": win.convertFiles(ps, row.ext); break;
    case "rotR": win.rotateFiles(ps, 90); break;
    case "rotL": win.rotateFiles(ps, 270); break;
    case "copyTo": win.sendTo(ps, false); break;
    case "moveTo": win.sendTo(ps, true); break;
    case "open":
      if (win.mode === "gallery") win.galleryOpen(win.gidx);
      else win.go(V.indexOfPath(win.rows, p));
      break;
    case "viewMarked": win.load(ps, "view"); break;
    case "showMarked": win.load(ps, "show"); break;
    case "openDirectory": win.openDirectory(p); break;
    case "showDirectory": win.load([p], "show"); break;
    case "revealDirectory": win.run(["qs", "ipc", "call", "Terminus", "open", p]); break;
    case "reveal": win.reveal(); break;
    case "trash": if (win.path !== "") win.trash([win.path]); break;
    case "trashP": win.trash(ps); break;
    case "deleteP": win.deleteForever(ps); break;
    case "paste": win.pasteHere(); break;
    case "pasteLook": win.pasteLook(); break;
    case "filter": win.openFilter(); break;
    case "starredOnly": {
      const on = V.splitFilter(win.filterText).tags.indexOf(V.FAVOURITE) >= 0;
      win.setFilter(on ? win.filterText.split(/\s+/).filter((w) => V.splitFilter(w).tags.indexOf(V.FAVOURITE) < 0).join(" ")
                       : (win.filterText + " \u2605").trim());
      break;
    }
    case "sort": win.sortBy(row.key); break;
    case "make": win.makeBeside(row.kind); break;
    case "markDupes": win.markAllButBest(); break;
    case "fold": win.foldBurst(row.key, row.fold); break;
    case "export": win.exportFor(p === win.path && win.mode === "view" && win.markCount === 0 ? [p] : ps, V.EXPORTS[row.preset], false); break;
    case "exportTo": win.exportFor(p === win.path && win.mode === "view" && win.markCount === 0 ? [p] : ps,
                                   { edge: 2048, ext: "webp", q: 85 }, true); break;
    case "sheet": win.contactSheet(ps); break;
    case "sheetAll": win.contactSheet(win.markCount > 0 ? win.markedPaths() : win.rows.map((r) => r.path)); break;
    case "go": win.openDirectory(row.dir); break;
    case "xmp": if (win.mgr) { win.mgr.setXmp(!win.mgr.xmpSidecars); win.say(win.mgr.xmpSidecars
      ? "tags and stars are written to an .xmp beside each picture too" : "tags stay on the files only (an .xmp already there is still kept up)"); } break;
    case "bursts": if (win.mgr) win.mgr.setBursts(!win.mgr.groupBursts); break;
    case "dupes": if (win.dupes) win.leaveDupes(); else win.findDupes(); break;
    case "map": win.openMap(); break;
    case "bulkRename": win.bulkRename(ps); break;
    }
  }

  CardPopup {
    id: menu
    window: win
    property string kind: "picture"
    property string subject: ""
    property var pixel: null
    // rows a card hands up as they are (PropsCard's open-with list)
    property var custom: []
    // the gallery tile a "cell" menu is about, while the cursor is elsewhere
    property int heldAt: -1
    fit: true
    model: win.menuRows(menu.kind, menu.subject)
    onChosen: (i) => menu.pick(menu.model[i])
    onSubChosen: (b, i) => menu.pick((menu.model[b].children || [])[i])
    function pick(row) {
      if (!row || row.isSeparator || row.enabled === false) return;
      menu.open = false;
      // A verb about a held tile acts on menu.subject and the cursor stays
      // (user, 2026-10-09) — except Open, which opens the cursor's tile
      // (galleryOpen(gidx)) and leaves the gallery anyway.
      if (row.act === "open" && menu.kind === "cell" && menu.heldAt >= 0
          && (win.galleryItems[menu.heldAt] || {}).path === menu.subject)
        win.gallerySel(menu.heldAt);
      menu.heldAt = -1;
      win.act(row, menu.subject);
    }
  }
  // A card hung off a window takes no grab, so a click anywhere else is the
  // window's — caught here, and spent on putting the menu away.
  MouseArea {
    anchors.fill: parent
    z: 30
    visible: menu.open
    acceptedButtons: Qt.AllButtons
    onPressed: menu.open = false
  }


  // ── properties ────────────────────────────────────────────────────────
  // terminus' card (terminus/PropsCard.qml), on a floating sheet: what the
  // file is, its owner, its exact size, what opens it, its sha256, and its
  // permissions behind their row. `propsHost` is what the card asks of a
  // window, answered with picasso's own listing, thumbnails and tags.
  function showProps(ps) {
    ps = (ps || []).filter((q) => q !== "");
    if (ps.length === 0) return;
    const byPath = {};
    for (const r of win.allRows) byPath[r.path] = r;
    for (const d of win.directories) byPath[d.path] = d;
    const rows = ps.map((q) => byPath[q]).filter((r) => !!r).map((r) => Object.assign({}, r));
    // not in the listing (the directory itself): stat'ed, as terminus does
    if (rows.length !== ps.length) { if (ps.length === 1) propsCard.askPath(ps[0]); return; }
    propsCard.show(Terminus.enrich(rows, Icons));
  }

  Item {
    id: propsHost
    visible: false
    function enrich(rows) { return Terminus.enrich(rows, Icons); }
    function warn(t) { win.say(t); }
    function run(cmd) {
      win.run(typeof cmd === "string" ? ["sh", "-c", cmd] : Terminus.shArgv(cmd), (code) => {
        if (code !== 0) win.say("that did not work");
        propsHost.rescan();
      });
    }
    // the card writes a word here when something is done
    property string status: ""
    onStatusChanged: if (propsHost.status !== "") { win.say(propsHost.status); propsHost.status = ""; }
    function inkFor(r) { return Terminus.inkOf(r); }
    readonly property var tagMarks: win.tags
    function tagInk(name) {
      const k = name === V.FAVOURITE ? "yellow" : Tags.presetInk(name);
      return (k !== "" && Zenon[k]) ? Zenon[k] : Zenon.cyan;
    }
    // the gallery's own thumbnails: a picture shows itself, a video its frame
    function thumbKind(r) { return Terminus.isImage(r.name) ? "i" : Terminus.isVideo(r.name) ? "v" : ""; }
    function thumbHas(r) { return r.path in win.thumbs; }
    function thumbJob(r, kind) { return r.path; }
    function thumbNow(path) { win.wantThumb(path); }
    readonly property var thumbFile: {
      const out = {};
      for (const k in win.thumbs) if (win.thumbs[k] !== "" && win.thumbs[k] !== "-") out[k] = win.thumbs[k];
      return out;
    }
    // what opens it — terminus' scan (Terminus.appsCommand)
    property var openWithApps: []
    property string openWithDefault: ""
    property string openWithMime: ""
    property bool appsScanned: false
    property string appsPath: ""
    function findApps(path) {
      propsHost.openWithApps = [];
      propsHost.openWithDefault = "";
      propsHost.openWithMime = "";
      propsHost.appsScanned = !path;
      if (!path) return;
      propsApps.command = ["sh", "-c", Terminus.appsCommand(path)];
      propsApps.running = true;
    }
    function rescan() { if (propsHost.appsPath !== "") propsHost.findApps(propsHost.appsPath); }
    function setDefaultApp(id) {
      if (!id || propsHost.openWithMime === "") return;
      propsHost.run(Terminus.setDefaultAppCommand(id, propsHost.openWithMime));
      win.say("default set");
    }
    Process {
      id: propsApps
      stdout: StdioCollector {
        waitForEnd: true
        onStreamFinished: {
          propsHost.openWithApps = Terminus.parseApps(text);
          propsHost.openWithMime = Terminus.parseAppsMime(text);
          propsHost.openWithDefault = Terminus.parseAppsDefault(text);
          propsHost.appsScanned = true;
        }
      }
    }
  }

  Item {
    id: propsBox
    anchors.fill: parent
    z: 10
    property bool open: false
    visible: propsBox.open || propsSheet.cardInk > 0.01
    onOpenChanged: if (!propsBox.open) keys.forceActiveFocus()
    // the window behind it darkened, as terminus does (its cardScrim) — from
    // the bar down: the bar is the sheet's titlebar and stays lit
    Rectangle {
      anchors.fill: parent
      anchors.topMargin: bar.height
      color: Zenon.darken(0.55)
      opacity: propsBox.open ? 1 : 0
      visible: opacity > 0.01
      Behavior on opacity {
        NumberAnimation { duration: propsBox.open ? propsSheet.slideIn : propsSheet.slideOut; easing.type: Zenon.ease }
      }
    }
    InputShield { visible: propsBox.open; onClicked: propsBox.open = false }
    Sheet {
      id: propsSheet
      backdrop: win.mode === "view" ? canvas : galleryPane   // frosted over it — see morpheus/Sheet
      // spliced out of the bar: flush to its bottom edge, sliding down out
      // of it, its own title on the card — as terminus' properties sheet
      floating: true
      splice: true
      shown: propsBox.open
      fromTop: bar.height
      title: propsCard.many ? propsCard.rows.length + " items"
        : (propsCard.rows[0] ? propsCard.rows[0].name : "Properties")
      glyph: propsCard.many ? "\uf0c5" : (propsCard.rows[0] ? propsCard.rows[0].glyph || "" : "")
      glyphInk: propsCard.rows[0] && !propsCard.many ? Terminus.inkOf(propsCard.rows[0]) : Zenon.cyan
      cardW: propsCard.wantW
      cardH: propsCard.implicitHeight
      PropsCard {
        id: propsCard
        width: parent.width
        host: propsHost
        onOpened: propsBox.open = true
        onClosed: propsBox.open = false
        onMenuWanted: (item, rows) => {
          // choosing a row makes it the default; the card's strike-out
          // (terminus' cross) has no place on this menu
          menu.custom = rows.map((r) => r.sep ? { isSeparator: true }
            : { text: r.label, hint: r.key || "", act: "fn", fn: r.act });
          win.showMenu(item.mapToItem(null, 0, item.height), "custom", "");
        }
      }
    }
  }

  // ── asking first ──────────────────────────────────────────────────────
  Item {
    id: confirm
    anchors.fill: parent
    z: 11
    property bool open: false
    property string question: ""
    // a line, or [key, line] — see terminus/ConfirmBody
    property var detail: ""
    property var items: []
    property string glyph: ""
    // which answer Return takes: 0 the verb, 1 Cancel
    property int pick: 0
    property string okLabel: "OK"
    property color okInk: Zenon.cyan
    property var then: null
    // a line to type into — a new name, tags — and a word under it
    property bool withField: false
    property string fieldHint: ""
    property int selectTo: -1
    visible: confirmSheet.cardInk > 0.01 || confirm.open
    // `detail`: a line under the question; `items`: what it is about, one a
    // line; `glyph`: its mark, in the answer's ink — see terminus/ConfirmBody
    function ask(q, ok, ink, fn, detail, items, glyph) {
      confirm.withField = false;
      confirm.detail = detail || "";
      confirm.items = items || [];
      confirm.glyph = glyph || "";
      confirm.pick = 0;
      confirm.question = q; confirm.okLabel = ok; confirm.okInk = ink; confirm.then = fn;
      confirm.open = true;
    }
    // then(text) on OK. The text starts as `initial`, selected up to
    // `selectTo` — a rename selects the name and leaves the extension.
    function askText(q, initial, ok, fn, hint, selectTo) {
      confirm.withField = true;
      confirm.detail = "";
      confirm.fieldHint = hint || "";
      askField.text = initial || "";
      confirm.selectTo = selectTo === undefined ? askField.text.length : selectTo;
      confirm.question = q; confirm.okLabel = ok; confirm.okInk = Zenon.cyan; confirm.then = fn;
      confirm.open = true;
    }
    function answer(yes) {
      const fn = confirm.then, text = askField.text;
      confirm.open = false;
      confirm.then = null;
      if (yes && fn) fn(text);
    }
    InputShield { visible: confirm.open; onClicked: confirm.answer(false) }
    Sheet {
      backdrop: win.mode === "view" ? canvas : galleryPane   // frosted over it — see morpheus/Sheet
      id: confirmSheet
      shown: confirm.open
      fromTop: bar.height
      cardW: confirm.withField ? 440 : 480
      cardH: confirm.withField ? (confirm.fieldHint !== "" ? 190 : 166) : confirmBody.implicitHeight
      // a question with no field: terminus' shared body, as terminus asks
      ConfirmBody {
        id: confirmBody
        visible: !confirm.withField
        width: parent.width
        height: parent.height
        question: confirm.question
        glyph: confirm.glyph
        glyphInk: confirm.okInk
        detail: confirm.detail
        items: confirm.items
        choices: [{ label: confirm.okLabel, ink: confirm.okInk }, { label: "Cancel", ink: Zenon.muted }]
        pick: confirm.pick
        onPicked: (i) => confirm.pick = i
        onChose: (i) => confirm.answer(i === 0)
      }
      Text {
        id: confirmQ
        visible: confirm.withField
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 18
        text: confirm.question
        color: Zenon.white
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(16)
        elide: Text.ElideMiddle
      }
      Rectangle {
        visible: confirm.withField
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 18
        anchors.rightMargin: 18
        y: 50
        height: 36
        radius: Zenon.windowRadius
        color: Zenon.wash(0.04)
        border.width: 1
        border.color: askField.activeFocus ? Zenon.cyan : Zenon.border
        TextInput {
          id: askField
          anchors.fill: parent
          anchors.leftMargin: 10
          anchors.rightMargin: 10
          verticalAlignment: TextInput.AlignVCenter
          color: Zenon.white
          selectionColor: Zenon.cyan
          selectedTextColor: Zenon.onAccent
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(15)
          clip: true
          selectByMouse: true
          cursorDelegate: Caret { field: askField }
          Keys.onPressed: (e) => {
            if (e.key === Qt.Key_Escape) { e.accepted = true; confirm.answer(false); }
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { e.accepted = true; confirm.answer(true); }
          }
        }
      }
      Text {
        visible: confirm.withField && confirm.fieldHint !== ""
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 18
        anchors.rightMargin: 18
        y: 94
        text: confirm.fieldHint
        color: Zenon.muted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(12)
        wrapMode: Text.WordWrap
      }
      Row {
        visible: confirm.withField
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 14
        spacing: 8
        DialogButton { label: "Cancel"; ink: Zenon.muted; onClicked: confirm.answer(false) }
        DialogButton { label: confirm.okLabel; ink: confirm.okInk; primary: true; onClicked: confirm.answer(true) }
      }
      Item {
        id: confirmKeys
        Keys.onPressed: (e) => {
          e.accepted = true;
          if (e.key === Qt.Key_Escape) confirm.answer(false);
          else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) confirm.answer(confirm.pick === 0);
          // drawn Cancel then the verb, left to right
          else if (e.key === Qt.Key_Left || e.key === Qt.Key_H || e.key === Qt.Key_Right || e.key === Qt.Key_L
                   || e.key === Qt.Key_Tab) confirm.pick = 1 - confirm.pick;
        }
      }
    }
    onOpenChanged: {
      if (!open) {
        if (win.mode === "annotate" && annLoader.item) annLoader.item.takeFocus(); else keys.forceActiveFocus();
        return;
      }
      if (!confirm.withField) { confirmKeys.forceActiveFocus(); return; }
      askField.forceActiveFocus();
      askField.select(0, confirm.selectTo);
    }
  }

  BulkRename {
    backdrop: win.mode === "view" ? canvas : galleryPane   // frosted over it — see morpheus/Sheet
    id: bulkCard
    z: 12
    host: win
    noun: "picture"
    topInset: bar.height
    onRenamed: (moves) => win.renamedMany(moves)
    onClosed: keys.forceActiveFocus()
  }

  // ── the bake ──────────────────────────────────────────────────────────
  // The edit at the picture's own size: the same Scene, the same look, the
  // same unit per picture, grabbed to a file. Built only for the moment of
  // saving — an effect layer the size of a 24-megapixel photo is not
  // something to keep drawing — and off to the side of the window, where it
  // is rendered for the grab and never seen.
  Loader {
    id: bakeLoader
    active: false
    x: -100000
    sourceComponent: Item {
      id: bk
      readonly property var r: win.crop || { x: 0, y: 0, w: win.tw, h: win.th }
      width: Math.max(1, Math.round(bk.r.w))
      height: Math.max(1, Math.round(bk.r.h))
      clip: true

      Scene {
        x: -bk.r.x
        y: -bk.r.y
        width: win.tw
        height: win.th
        look: win.look
        ground: false
        unit: V.unitFor(win.tw, win.th)
        accent: scene.accent
        Image {
          id: full
          anchors.fill: parent
          rotation: win.straighten * (win.look.mirror ? -1 : 1)
          scale: V.straightenScale(width, height, win.straighten)
          source: Strings.fileUrl(win.path)
          fillMode: Image.Stretch
          autoTransform: true
          asynchronous: true
          cache: false
          onStatusChanged: {
            if (status === Image.Ready) settle.start();
            else if (status === Image.Error) win.baked("");
          }
        }
      }
      // a frame for the effect layer to render into before it is read back
      Timer {
        id: settle
        interval: 150
        onTriggered: {
          const ok = bk.grabToImage((res) => {
            const tmp = Paths.runtimeDir() + "/picasso-view-" + Date.now() + ".png";
            win.baked(res.saveToFile(tmp) ? tmp : "");
          }, Qt.size(bk.width, bk.height));
          if (!ok) win.baked("");
        }
      }
    }
  }

  // mouse 4 and mouse 5, anywhere in the window: back and forward (navBack),
  // as in terminus. Only those two buttons, so every other click falls
  // through to what is under it.
  MouseArea {
    anchors.fill: parent
    z: 1000
    acceptedButtons: Qt.BackButton | Qt.ForwardButton
    onPressed: (m) => {
      if (m.button === Qt.BackButton) win.navBack();
      else if (m.button === Qt.ForwardButton) win.navForward();
    }
  }
}
