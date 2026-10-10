// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// CERES' WINDOW, KEPT — built off the startup path, shown on request.
//
// terminus' arrangement, for terminus' reasons (see TerminusManager): the
// window's type is compiled ASYNCHRONOUSLY once the shell is up rather than
// named at file scope, where compiling it would hold the bar back; and one
// window is built HIDDEN as soon as the type is ready, because a window
// standing by costs nothing until it is on screen and the first open should
// not be the one that pays for building it.
//
// ON THE MONITOR YOU ARE ON. A quickshell window cannot be moved to another
// screen once it exists — quickshell segfaults in setScreen — so a hidden
// window sitting on the wrong monitor is thrown away and a new one is built
// where you are looking. It is cheap: the type is already compiled.

import QtQuick
import Quickshell
import "."
import Quickshell.Hyprland
import Quickshell.Io
import "../morpheus/lagnotes.js" as LagNotes
import "../oracle"

Scope {
  id: mgr

  property var win: null
  property var comp: null
  property var pending: null   // the view asked for before the type was ready

  readonly property bool shown: mgr.alive() && mgr.win.visible && mgr.win.backingWindowVisible

  // ── A DEAD POINTER IS NOT A WINDOW ────────────────────────────────────
  // The window can go away by routes this manager never hears about — the
  // compositor closing it, its screen being unplugged, an output that went
  // dark for the idle timer and came back as a new screen. A destroyed QObject
  // held in a `var` does not become null: reading anything off it throws. So
  // `mgr.win.visible` threw inside open(), open() stopped there, and ceres
  // would not open again until the shell was restarted. Terminus hit exactly
  // this once; see TerminusManager.picker.
  //
  // Reading one property is the only way to ask "are you still there".
  function alive() {
    if (!mgr.win) return false;
    try {
      return mgr.win.mgr === mgr;
    } catch (e) {
      return false;
    }
  }

  Timer {
    interval: 2500
    running: true
    onTriggered: mgr.compile()
  }

  function compile() {
    if (mgr.comp) return;
    mgr.comp = Qt.createComponent("CeresWindow.qml", Component.Asynchronous);
    if (mgr.comp.status === Component.Loading) mgr.comp.statusChanged.connect(mgr.settled);
    else mgr.settled();
  }

  function settled() {
    if (!mgr.comp || mgr.comp.status === Component.Loading) return;
    if (mgr.comp.status === Component.Error) {
      console.error("ceres: " + mgr.comp.errorString());
      // Let the next open try again. Held, one failed compile — a file
      // caught half-written by a reload — was every open for the rest of
      // the session quietly waiting on a component that would never be ready.
      mgr.comp = null;
      return;
    }
    if (mgr.pending !== null) { const v = mgr.pending; mgr.pending = null; mgr.open(v); }
    else if (!mgr.win) mgr.prebuild();
  }

  function focusedScreen() {
    const m = Hyprland.focusedMonitor;
    if (m) for (const s of Quickshell.screens) if (s.name === m.name) return s;
    // none in focus: the main monitor (oracle's Display setting)
    return Oracle.pickScreen("");
  }

  // ── ITS SIZE, REMEMBERED ─────────────────────────────────────────────
  // The last size the window was left at, handed to each window built.
  // Hyprland's rule for ceres floats it and nothing more: a rule `size`
  // would override this on every map.
  FileView {
    id: sizeFile
    path: Quickshell.statePath("ceres-window.json")
    blockLoading: true
    printErrors: false
  }
  function savedSize() {
    try {
      const o = JSON.parse(sizeFile.text());
      if (o.w >= 760 && o.h >= 440) return o;
    } catch (e) {}
    return null;
  }
  function noteSize(w, h) {
    if (w < 760 || h < 440) return;
    sizeFile.setText(JSON.stringify({ w: Math.round(w), h: Math.round(h) }));
  }

  function build() {
    const scr = mgr.focusedScreen();
    const props = { mgr: mgr };
    if (scr) props.screen = scr;
    const sz = mgr.savedSize();
    if (sz) { props.implicitWidth = sz.w; props.implicitHeight = sz.h; }
    const t0 = Date.now();
    mgr.win = mgr.comp.createObject(mgr, props);
    LagNotes.mark("ceres window", t0);
    Ceres.windowShown = Qt.binding(() => mgr.shown);
  }

  // ── THE STANDING WINDOW, BUILT IN THE BACKGROUND ───────────────────
  // As terminus' window 0 (see TerminusManager.prebuild): incubated, so
  // the ~120 ms build is spread over frames instead of landing in one a
  // couple of seconds after every start and every reload. An open before
  // it is done finishes it on the spot.
  property var incubator: null
  function prebuild() {
    if (mgr.incubator || mgr.win || !mgr.comp || mgr.comp.status !== Component.Ready) return;
    const scr = mgr.focusedScreen();
    const props = { mgr: mgr };
    if (scr) props.screen = scr;
    const sz = mgr.savedSize();
    if (sz) { props.implicitWidth = sz.w; props.implicitHeight = sz.h; }
    const inc = mgr.comp.incubateObject(mgr, props, Qt.Asynchronous);
    if (!inc) return;
    mgr.incubator = inc;
    if (inc.status !== Component.Loading) mgr.adopt(inc);
    else inc.onStatusChanged = () => mgr.adopt(inc);
  }
  function adopt(inc) {
    if (mgr.incubator !== inc || inc.status === Component.Loading) return;
    mgr.incubator = null;
    if (inc.status !== Component.Ready || !inc.object) return;
    mgr.win = inc.object;
    Ceres.windowShown = Qt.binding(() => mgr.shown);
  }
  function settle() {
    const inc = mgr.incubator;
    if (!inc) return;
    if (inc.status === Component.Loading) inc.forceCompletion();
    mgr.adopt(inc);
  }

  function open(view) {
    mgr.settle();
    if (!mgr.comp || mgr.comp.status !== Component.Ready) {
      mgr.pending = view || "";
      mgr.compile();
      return;
    }
    const scr = mgr.focusedScreen();
    if (!mgr.alive()) mgr.win = null;
    // on the wrong monitor, or on none — a screen that went away leaves the
    // window holding nothing to be drawn on
    if (mgr.win && !mgr.win.visible && (!mgr.win.screen || (scr && mgr.win.screen !== scr))) {
      mgr.win.destroy();
      mgr.win = null;
    }
    if (!mgr.win) mgr.build();
    // SAYS SHOWN, IS NOT: the compositor closed it and `visible` never heard
    // (see onClosed in the window, which is the real fix — this is the
    // backstop). Put down first, so being shown is a change again.
    if (mgr.win.visible && !mgr.win.backingWindowVisible) mgr.win.visible = false;
    const was = mgr.win.visible;
    mgr.win.present(view || "");
    // Already open is not the same as in front of you: it may be on another
    // workspace entirely. Brought here, and given the keyboard.
    if (was) mgr.raise();
  }

  // To it, wherever it is. In the Lua dispatcher's own words — this config
  // runs hyprland on Lua, and the old "focuswindow title:…" string is
  // refused there, which is why this never did anything before.
  function raise() {
    Hyprland.dispatch('hl.dsp.focus({ window = "title:^(ceres)$" })');
  }

  // The window ceres is in has the keyboard: the one case where a toggle
  // means "put it away". Open but somewhere else, a toggle brings it here —
  // it used to close it, so the press that should have shown it hid it.
  readonly property bool focused: {
    const t = Hyprland.activeToplevel;
    return mgr.shown && !!t && t.title === "ceres";
  }

  // Closes only when the window is showing the view asked for; asked for
  // the other view, it switches to it instead of going away.
  function toggle(view) {
    mgr.settle();
    if (mgr.focused && mgr.win.tab === view) mgr.win.dismiss();
    else mgr.open(view);
  }

  Connections {
    target: Ceres
    function onWindowRequested(view) { mgr.open(view); }
    function onWindowToggleRequested(view) { mgr.toggle(view); }
  }
}
