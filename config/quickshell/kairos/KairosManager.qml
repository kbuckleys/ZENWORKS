// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// KAIROS' MANAGER — the part always in the shell besides the counting
// (Kairos.qml): the lock handed to it, the ipc handler, the .desktop entry
// and the window, built when asked for.
//
//   `qs ipc call Kairos open <view>`   day · week

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../morpheus"
import "../morpheus/lagnotes.js" as LagNotes
import "../morpheus/hypr.js" as Hypr

Scope {
  id: mgr

  // Cerberus, from shell.qml: nothing counts while the lock is up
  property var lockscreen: null
  Binding { target: Kairos; property: "locked"; value: !!mgr.lockscreen && mgr.lockscreen.locked }

  // ── ITS .desktop ENTRY ─────────────────────────────────────────────
  Process {
    running: true
    command: ["sh", "-c", Desktop.installCommand("kairos", {
      Type: "Application",
      Name: "Screen Time",
      GenericName: "Screen Time",
      Comment: "How long each app had you, in ZENWORKS",
      Icon: "preferences-system-time",
      Categories: ["Utility"],
      Keywords: ["kairos", "screen", "time", "usage", "apps", "focus", "hours", "today", "week"],
      Exec: Desktop.execLine(Quickshell.shellDir + "/kairos/bin/kairos", ""),
      Terminal: "false",
      StartupNotify: "false",
    })]
  }

  // ── THE WINDOW ─────────────────────────────────────────────────────
  // Floating by its title (hypr/lua/rules.lua: "kairos").
  property var win: null
  LazyComponent {
    id: lazy
    source: Qt.resolvedUrl("KairosWindow.qml")
    tag: "kairos"
  }
  function withWindow(fn) {
    lazy.withReady(() => {
      let fresh = false;
      if (!mgr.win) {
        const t0 = Date.now();
        mgr.win = lazy.comp.createObject(mgr, { mgr: mgr });
        LagNotes.mark("kairos window", t0);
        if (!mgr.win) return;
        fresh = true;
      }
      const was = !fresh && mgr.win.visible;
      fn(mgr.win);
      mgr.win.visible = true;
      if (was) Hyprland.dispatch(Hypr.focusTitle("kairos"));
    });
  }
  function retire(w) {
    if (mgr.win === w) mgr.win = null;
    if (!mgr.win && lazy.waiting.length === 0) lazy.comp = null;
  }

  function open(view) {
    // what is counted reaches the files before the window reads them
    Kairos.tick();
    Kairos.flush();
    mgr.withWindow((w) => w.go(view || ""));
  }

  IpcHandler {
    target: "Kairos"
    function open(view: string): string { mgr.open(view); return "ok"; }
    // what the last `minutes` went to, the way a finished timer says it
    function since(minutes: int): string { return Kairos.summarySince(Date.now() - minutes * 60000); }
  }
}
