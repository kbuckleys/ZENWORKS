// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// FOLLOW BACKGROUND: the theme made from a background. While Oracle's theme
// is "follow", the followed monitor's background (Oracle.followMonitor, the
// first by default) is asked for its dominant colours and turned into a
// palette (morpheus/wallpalette.js), which Zenon wears as followTheme. All
// the rest — every component, ThemeSync's kitty and hyprland, plato, the
// previews — is what any theme gets.
//
// THE COLOURS, ONCE PER PICTURE. ImageMagick shrinks the image and counts
// twelve colours; the answer is kept on disk under the file's path, size
// and mtime, so a background seen before costs a cat, and in memory for the
// session.
//
// ONE CHANGE, NEVER DURING THE BACKGROUND'S OWN ANIMATION — see wear.
//
// Loaded by shell.qml through a Loader, not as a qmldir type: a new type in
// picasso/qmldir is not seen by a live reload.

import QtQuick
import Quickshell
import Quickshell.Io
import "../morpheus"
import "../oracle"
import "picasso.js" as Art
import "../morpheus/wallpalette.js" as Pal

Item {
  id: follow

  readonly property bool active: Zenon.themeName === "follow"
  readonly property var screen: Oracle.pickScreen(Oracle.followMonitor)
  readonly property string screenName: follow.screen ? follow.screen.name : ""
  readonly property string wallpaper: follow.screenName !== "" ? Picasso.wallpaperFor(follow.screenName) : ""

  // ── THE SLIDESHOW, IF IT IS NOT TO BE FOLLOWED ────────────────────────
  // With Follow the slideshow off, the picture showing when a slideshow on
  // this monitor began stays the one the theme is made from.
  readonly property bool slideshowHere: {
    const ss = Picasso.slideshow;
    const on = ss ? (ss.screens || []) : [];
    return !!ss && (on.length === 0 || on.indexOf(follow.screenName) >= 0);
  }
  property string frozen: ""
  onSlideshowHereChanged: follow.frozen = follow.slideshowHere ? follow.wallpaper : ""
  readonly property string source: !Oracle.followSlideshow && follow.slideshowHere && follow.frozen !== ""
    ? follow.frozen : follow.wallpaper

  // path -> the histogram's text, for the session
  property var seen: ({})
  property string asked: ""

  readonly property string want: follow.active ? follow.source : ""
  onWantChanged: follow.fetch()
  Component.onCompleted: follow.fetch()

  function fetch() {
    const p = follow.want;
    if (p === "") return;
    const solid = Art.colorOf(p);
    if (solid) { follow.make([{ hex: String(solid).toLowerCase(), n: 1 }]); return; }
    if (follow.seen[p] !== undefined) { follow.make(Pal.parseHistogram(follow.seen[p])); return; }
    follow.asked = p;
    histProc.running = false;
    histProc.command = ["sh", "-c",
      "f=\"$1\"; d=\"$2\"; "
      + "k=$(printf '%s:%s' \"$f\" \"$(stat -c %Y:%s -- \"$f\" 2>/dev/null)\" | md5sum | cut -c1-32); "
      + "c=\"$d/$k.txt\"; [ -s \"$c\" ] && exec cat \"$c\"; mkdir -p \"$d\"; "
      // bounded, and never reading stdin: a picture ImageMagick chokes on
      // is a theme left as it was, not a stuck process
      + "timeout 20 magick \"$f[0]\" -resize 100x100 -colors 12 -depth 8 -format %c histogram:info:- "
      + "> \"$c.tmp\" 2>/dev/null && mv \"$c.tmp\" \"$c\" && exec cat \"$c\"",
      "sh", p, Paths.cacheDir() + "/quickshell/follow"];
    histProc.running = true;
  }

  Process {
    id: histProc
    stdout: StdioCollector {
      id: histOut
      waitForEnd: true
      onStreamFinished: {
        const p = follow.asked;
        const text = histOut.text;
        if (Pal.parseHistogram(text).length > 0) {
          const m = Object.assign({}, follow.seen);
          m[p] = text;
          follow.seen = m;
        }
        // an answer for a picture no longer wanted is kept, not worn
        if (p === follow.want) follow.make(Pal.parseHistogram(text));
      }
    }
  }

  // the palette last made, so a change of tone or colour remakes it
  // without asking ImageMagick again
  property var hist: []
  function make(colors) {
    follow.hist = colors;
    follow.remake();
  }
  function remake() {
    if (!follow.active || !follow.hist.length) return;
    // Sun: light while the sun is up (Zenon.daylight, chronos/SunClock)
    const mode = Oracle.followMode === "sun" ? (Zenon.daylight ? "light" : "dark") : Oracle.followMode;
    const t = Pal.palette(follow.hist, { mode: mode, vivid: Oracle.followVivid });
    if (t) follow.wear(t);
  }
  // a slider dragged is a burst of values; the shell is re-themed once,
  // where it stops
  Connections {
    target: Oracle
    function onFollowModeChanged() { remakeSoon.restart(); }
    function onFollowVividChanged() { remakeSoon.restart(); }
  }
  Connections {
    target: Zenon
    function onDaylightChanged() { if (Oracle.followMode === "sun") remakeSoon.restart(); }
  }
  Timer { id: remakeSoon; interval: 180; onTriggered: follow.remake() }

  // ── WHEN IT IS PUT ON ────────────────────────────────────────────
  // At once, unless a background is mid-animation (Picasso.transitionUntil):
  // then the moment it ends. It used to fade in over eight steps, and every
  // step re-evaluated every colour binding in the shell — ~100 ms on the
  // thread the background's zoom also runs on — so the zoom played in
  // bursts (Buck's capture, 2026-10-08). One change, where nothing moves.
  // A cached palette usually lands before the new picture has even
  // decoded, which is the best moment of all: the old one is standing still.
  property var pending: null
  function wear(t) {
    const wait = Picasso.transitionUntil - Date.now();
    if (wait > 0) {
      follow.pending = t;
      later.interval = Math.ceil(wait) + 60;
      later.restart();
      return;
    }
    later.stop();
    follow.pending = null;
    Zenon.followTheme = t;
  }
  Timer {
    id: later
    onTriggered: if (follow.pending) follow.wear(follow.pending)
  }

  // ── KEEPING ONE ──────────────────────────────────────────────────────
  // Oracle's Save: the palette worn now, written to themes/ under the
  // picture's name — never over a file already there — and the theme list
  // read again so it is in the picker at once.
  Connections {
    target: Oracle
    function onSaveFollowRequested(name) { follow.keep(name); }
  }
  // what oracle's naming sheet starts with: the picture's own name
  readonly property string pictureName: String(follow.source).split("/").pop().replace(/\.[^.]*$/, "")
  Binding { target: Oracle; property: "followSuggest"; value: follow.pictureName }
  // CUSTOM, marked as such: only a theme saved here may be deleted from
  // oracle's Theme list (Delete on its row) — the shipped ones never
  function keep(name) {
    const t = Zenon.followTheme;
    if (!follow.active || !t || !t.colors) return;
    const label = String(name || "").trim() || follow.pictureName || "Background";
    const slug = label.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 40) || "theme";
    const out = { name: label.slice(0, 60), mode: t.mode, custom: true, colors: t.colors };
    keepProc.command = ["sh", "-c",
      "d=\"$1\"; s=\"$2\"; f=\"$d/custom-$s.json\"; n=2; "
      + "while [ -e \"$f\" ]; do f=\"$d/custom-$s-$n.json\"; n=$((n + 1)); done; "
      + "printf '%s\\n' \"$3\" > \"$f\"",
      "sh", Quickshell.shellDir + "/themes", slug, JSON.stringify(out, null, 2)];
    keepProc.running = true;
  }
  Process {
    id: keepProc
    onExited: Oracle.scanThemes()
  }

  // leaving Follow Background: nothing of it lingers for next time
  onActiveChanged: if (!follow.active) { later.stop(); follow.pending = null; Zenon.followTheme = null; follow.hist = []; }
}
