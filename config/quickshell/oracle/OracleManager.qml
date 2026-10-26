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
// ON THE MONITOR YOU ARE ON. A hidden window on the wrong monitor is moved
// to the one you are looking at before it is shown — never while it is on
// screen, where quickshell's setScreen hides and reshows it and crashed.
// See open(). The section you were in, and the size you left it at, are kept
// here, for the window the watchdog rebuilds. Its sibling types (ArrangeView)
// come in through the window's own `import "."`.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "../morpheus"
import "../ceres"
import "../morpheus/hypr.js" as Hypr
import "../morpheus/lagnotes.js" as LagNotes

Scope {
  // ── CHECK FOR UPDATES (oracle's About) ──────────────────────────────
  // Zenworks is a package (2026-10-25): it updates through pacman and the
  // AUR like everything else, so the row opens Ceres' Updates, where a new
  // version is listed beside the rest. scripts/update.sh, which laid a
  // fetched copy over ~/.config, is gone with the install script.
  Connections {
    target: Oracle
    function onUpdateAsked() { Ceres.openWindow("updates"); }
  }

  // ── INPUT METHODS (oracle's Input) ─────────────────────────────────
  // fcitx5 and a language's engine, installed the first time a row is
  // turned on; Oracle carries on (or puts the row back) once Ceres ends
  Connections {
    target: Oracle
    function onImInstallAsked(pkgs, why) {
      if (!Ceres.install(pkgs, why, (ok) => Oracle.imInstalled(ok))) Oracle.imInstalled(false);
    }
  }

  // ── THE TERMINAL SETUP (oracle/ZshSetup.qml) ───────────────────────
  // asked once at the first start; Default apps › Terminal setup after
  ZshSetup { id: zshSetup }
  Connections {
    target: Oracle
    function onZshAsked() { zshSetup.apply(); }
  }
  id: mgr

  // handed to the window, for the Font and Location pickers
  property var fileManager: null
  // Alexandria, for the Font row's book button
  property var fontBook: null

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
    const scr = Oracle.focusedScreen();
    const props = { mgr: mgr, fileManager: mgr.fileManager, fontBook: mgr.fontBook };
    if (scr) props.screen = scr;
    if (mgr.section !== "") props.section = mgr.section;
    const sz = mgr.savedSize();
    if (sz) { props.implicitWidth = sz.w; props.implicitHeight = sz.h; }
    const t0 = Date.now();
    mgr.win = mgr.comp.createObject(mgr, props);
    LagNotes.mark("oracle window", t0);
  }

  function open(section) {
    watchdog.arm([section || ""]);
    if (!mgr.comp || mgr.comp.status !== Component.Ready) {
      mgr.pending = [section || ""];
      mgr.compile();
      return;
    }
    const scr = Oracle.focusedScreen();
    if (!mgr.alive()) mgr.win = null;
    if (!mgr.win) mgr.build();
    // says shown, is not: closed by the compositor without `visible` hearing
    if (mgr.win.visible && !mgr.win.backingWindowVisible) mgr.win.visible = false;
    // On the wrong monitor, or on none (a screen that went away): MOVED, not
    // rebuilt — ceres' fix (see CeresManager.open). It used to be destroyed and
    // built again, one of the 110–280 ms "in oracle" stalls in lag.log
    // (2026-10-18). Only while hidden: there quickshell's setScreen is
    // QWindow::setScreen alone, and Wayland's outputs are virtual siblings, so
    // nothing is recreated. Its hide-and-reshow path for a window on screen is
    // the one that crashed.
    if (scr && !mgr.win.visible && mgr.win.screen !== scr) mgr.win.screen = scr;
    const was = mgr.win.visible;
    mgr.win.openPopup(section || "");
    // already open is not the same as in front of you — it may be on
    // another workspace entirely
    if (was) mgr.raise();
  }

  // asked for, never seen: an open not on screen 1.5 s later says what it
  // found and builds a fresh window once (morpheus/OpenWatchdog)
  OpenWatchdog { id: watchdog; owner: mgr; tag: "oracle" }

  function raise() {
    Hyprland.dispatch(Hypr.focusTitle("oracle"));
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
    // open on the FIRST section, wherever it was left — icarus' Settings
    // is a front door, not a return to where you were. Named by position
    // rather than by id, so reordering the sections cannot strand it.
    function first() { mgr.open(Oracle.sections.length ? Oracle.sections[0].id : ""); }
    function close() { mgr.close(); }
  }
}
