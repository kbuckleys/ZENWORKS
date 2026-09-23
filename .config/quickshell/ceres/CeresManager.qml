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

Scope {
  id: mgr

  property var win: null
  property var comp: null
  property var pending: null   // the view asked for before the type was ready

  readonly property bool shown: mgr.win !== null && mgr.win.visible

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
      return;
    }
    if (!mgr.win) mgr.build();
    if (mgr.pending !== null) { const v = mgr.pending; mgr.pending = null; mgr.open(v); }
  }

  function focusedScreen() {
    const m = Hyprland.focusedMonitor;
    if (m) for (const s of Quickshell.screens) if (s.name === m.name) return s;
    return Quickshell.screens.length ? Quickshell.screens[0] : null;
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
    mgr.win = mgr.comp.createObject(mgr, props);
    Ceres.windowShown = Qt.binding(() => mgr.shown);
  }

  function open(view) {
    if (!mgr.comp || mgr.comp.status !== Component.Ready) {
      mgr.pending = view || "";
      mgr.compile();
      return;
    }
    const scr = mgr.focusedScreen();
    if (mgr.win && !mgr.win.visible && scr && mgr.win.screen !== scr) {
      mgr.win.destroy();
      mgr.win = null;
    }
    if (!mgr.win) mgr.build();
    mgr.win.present(view || "");
  }

  // Closes only when the window is showing the view asked for; asked for
  // the other view, it switches to it instead of going away.
  function toggle(view) {
    if (mgr.shown && mgr.win.tab === view) mgr.win.dismiss();
    else mgr.open(view);
  }

  Connections {
    target: Ceres
    function onWindowRequested(view) { mgr.open(view); }
    function onWindowToggleRequested(view) { mgr.toggle(view); }
  }
}
