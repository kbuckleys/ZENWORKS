// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ORACLE'S WINDOW, KEPT — ceres' arrangement, for ceres' reasons (see
// CeresManager): the window type is compiled asynchronously once the shell is
// up rather than at file scope, where it would hold the bar back, and one
// window is built hidden as soon as it is ready so the first open does not pay
// for building it.
//
// ON THE MONITOR YOU ARE ON. A quickshell window cannot be moved to another
// screen once it exists — quickshell segfaults in setScreen — so a hidden
// window on the wrong monitor is thrown away and a new one built where you are
// looking. The section you were in, and the size you left it at, are kept here,
// so the new one is the old one on a different screen. Its sibling types
// (ArrangeView) come in through the window's own `import "."`.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Scope {
  id: mgr

  // handed to the window, for the Font and Location pickers
  property var fileManager: null

  property var win: null
  property var comp: null
  property var pending: null   // [section] asked for before the type was ready

  // the section the last window was in, for the next one built
  property string section: ""

  readonly property bool shown: mgr.alive() && mgr.win.visible && mgr.win.backingWindowVisible

  // A destroyed QObject held in a `var` does not become null — reading from
  // it throws. See CeresManager.alive, which learned this first.
  function alive() {
    if (!mgr.win) return false;
    try {
      return mgr.win.mgr === mgr;
    } catch (e) {
      return false;
    }
  }

  Timer {
    interval: 3000
    running: true
    onTriggered: mgr.compile()
  }

  function compile() {
    if (mgr.comp) return;
    mgr.comp = Qt.createComponent("OracleWindow.qml", Component.Asynchronous);
    if (mgr.comp.status === Component.Loading) mgr.comp.statusChanged.connect(mgr.settled);
    else mgr.settled();
  }

  function settled() {
    if (!mgr.comp || mgr.comp.status === Component.Loading) return;
    if (mgr.comp.status === Component.Error) {
      console.error("oracle: " + mgr.comp.errorString());
      // the next open tries again, rather than waiting forever on a
      // component a half-written file broke
      mgr.comp = null;
      return;
    }
    if (!mgr.win) mgr.build();
    if (mgr.pending !== null) { const p = mgr.pending; mgr.pending = null; mgr.open(p[0]); }
  }

  function focusedScreen() {
    const m = Hyprland.focusedMonitor;
    if (m) for (const s of Quickshell.screens) if (s.name === m.name) return s;
    return Quickshell.screens.length ? Quickshell.screens[0] : null;
  }

  // ── ITS SIZE, REMEMBERED ─────────────────────────────────────────────
  // Hyprland's rule for oracle floats it and nothing more: a rule `size`
  // would override this on every map.
  FileView {
    id: sizeFile
    path: Quickshell.statePath("oracle-window.json")
    blockLoading: true
    printErrors: false
  }

  function savedSize() {
    try {
      const o = JSON.parse(sizeFile.text());
      if (o.w >= 640 && o.h >= 420) return o;
    } catch (e) {}
    return null;
  }

  function noteSize(w, h) {
    if (w < 640 || h < 420) return;
    sizeFile.setText(JSON.stringify({ w: Math.round(w), h: Math.round(h) }));
  }

  function build() {
    const scr = mgr.focusedScreen();
    const props = { mgr: mgr, fileManager: mgr.fileManager };
    if (scr) props.screen = scr;
    if (mgr.section !== "") props.section = mgr.section;
    const sz = mgr.savedSize();
    if (sz) { props.implicitWidth = sz.w; props.implicitHeight = sz.h; }
    mgr.win = mgr.comp.createObject(mgr, props);
  }

  function open(section) {
    if (!mgr.comp || mgr.comp.status !== Component.Ready) {
      mgr.pending = [section || ""];
      mgr.compile();
      return;
    }
    const scr = mgr.focusedScreen();
    if (!mgr.alive()) mgr.win = null;
    if (mgr.win && !mgr.win.visible && (!mgr.win.screen || (scr && mgr.win.screen !== scr))) {
      mgr.win.destroy();
      mgr.win = null;
    }
    if (!mgr.win) mgr.build();
    // says shown, is not: closed by the compositor without `visible` hearing
    if (mgr.win.visible && !mgr.win.backingWindowVisible) mgr.win.visible = false;
    const was = mgr.win.visible;
    mgr.win.openPopup(section || "");
    // already open is not the same as in front of you — it may be on
    // another workspace entirely
    if (was) mgr.raise();
  }

  function raise() {
    Hyprland.dispatch('hl.dsp.focus({ window = "title:^(oracle)$" })');
  }

  // The window oracle is in has the keyboard: the one case where a toggle
  // means "put it away". Open but elsewhere, a toggle brings it here.
  readonly property bool focused: {
    const t = Hyprland.activeToplevel;
    return mgr.shown && !!t && t.title === "oracle";
  }

  function toggle() {
    if (mgr.focused) mgr.win.closePopup();
    else mgr.open("");
  }

  function close() {
    if (mgr.alive()) mgr.win.closePopup();
  }

  IpcHandler {
    // "Oracle", like every other layer's own name — the settings STORE answers
    // to "OracleSettings" so that this one can.
    target: "Oracle"
    function toggle() { mgr.toggle(); }
    function open() { mgr.open(""); }
    // open standing in a named section, for a keybind or a menu that goes
    // straight to the monitors or the lock rather than wherever it was left
    function at(section: string) { mgr.open(section); }
    function close() { mgr.close(); }
  }
}
