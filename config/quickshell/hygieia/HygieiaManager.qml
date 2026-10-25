// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// HYGIEIA — Tidy (user's pick from the 10-22 ideas round): what is taking
// room that could be given back. The package cache's old versions, packages
// nothing needs, the journal past what is kept, the caches, big or old
// downloads, and copies of the same file — and the trash they all go to.
//
// THIS IS THE PART THAT IS ALWAYS IN THE SHELL: the ipc handler and the
// .desktop entry. Everything else is asked of core/tidy.py while the window
// is open, and nothing runs while it is shut.
//
// THE TRASH FIRST. Files go to the trash (gio); deleting for good, or
// emptying the trash, is there for a disk too full for the trash to help
// (user, 2026-10-22), and the window asks twice before either. Only inside
// the home (tidy.py refuses anything else). The package cache, the orphans
// and the journal are root's: Ceres' password card runs those, one job.
//
//   `qs ipc call Hygieia open`

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../morpheus"
import "../morpheus/lagnotes.js" as LagNotes
import "../morpheus/hypr.js" as Hypr
import "../ceres"
import "hygieia.js" as H

Scope {
  id: mgr

  readonly property string core: Quickshell.shellDir + "/hygieia/core/tidy.py"

  // ── ASKING core/tidy.py ────────────────────────────────────────────
  // one-off processes, made per ask and destroyed when answered; fn(text)
  Component { id: procComp; Process {} }
  Component { id: collComp; StdioCollector { waitForEnd: true } }
  function ask(args, fn) {
    const p = procComp.createObject(mgr);
    const out = collComp.createObject(p);
    p.stdout = out;
    out.streamFinished.connect(() => { fn(out.text); p.destroy(); });
    p.command = ["python3", "-I", mgr.core].concat(args);
    p.running = true;
  }

  // ── WHAT IS KNOWN ──────────────────────────────────────────────────
  property var overview: H.parseOverview("")
  property bool scanning: false
  function scan() {
    if (mgr.scanning) return;
    mgr.scanning = true;
    mgr.ask(["overview"], (t) => { mgr.overview = H.parseOverview(t); mgr.scanning = false; });
  }
  property var dupes: []
  property bool dupesAsked: false
  property bool dupesScanning: false
  function scanDupes() {
    if (mgr.dupesScanning) return;
    mgr.dupesScanning = true;
    mgr.ask(["dupes"], (t) => { mgr.dupes = H.parseDupes(t); mgr.dupesAsked = true; mgr.dupesScanning = false; });
  }

  // ── DOING ──────────────────────────────────────────────────────────
  signal said(string words, bool bad)
  property string busy: ""
  // files and directories to the trash; then asked again
  function trash(paths, words) { mgr.files("trash", paths, words, "moved to the trash"); }
  // gone for good (the window asks twice): for a disk too full for the
  // trash to help
  function erase(paths, words) { mgr.files("delete", paths, words, "deleted"); }
  function emptyTrash() { mgr.files("empty", [], "The trash", "emptied"); }
  function files(verb, paths, words, done) {
    if (mgr.busy !== "" || (verb !== "empty" && !paths.length)) return;
    mgr.busy = verb;
    mgr.ask([verb].concat(paths), (t) => {
      mgr.busy = "";
      let j = null;
      try { j = JSON.parse(t); } catch (e) {}
      const moved = j && j.moved ? j.moved.length : 0, failed = j && j.failed ? j.failed : [];
      if (failed.length) mgr.said(moved + " " + done + "; " + failed.length + " could not be: " + failed[0].why, true);
      else mgr.said(words + " " + done, false);
      mgr.scan();
      if (mgr.dupesAsked) mgr.scanDupes();
    });
  }
  // root's: through Ceres' password card. `pkgs` it installs first (the
  // package cache's paccache is pacman-contrib's)
  function asRoot(kind, pkgs, why, steps) {
    if (mgr.busy !== "") return;
    mgr.busy = kind;
    const ok = Ceres.install(pkgs, why, (done) => {
      mgr.busy = "";
      mgr.said(done ? "Done" : "Not done", !done);
      mgr.scan();
    }, steps);
    if (!ok) { mgr.busy = ""; mgr.said("Ceres is busy — try again once it is done", true); }
  }
  function openTrash() {
    if (mgr.overview.trash.dir !== "") Quickshell.execDetached(["qs", "ipc", "call", "Terminus", "open", mgr.overview.trash.dir]);
  }
  function reveal(path) { Quickshell.execDetached(["qs", "ipc", "call", "Terminus", "reveal", path]); }

  // ── ITS .desktop ENTRY ─────────────────────────────────────────────
  readonly property var launcher: Desktop.launcher("hygieia", {
    Type: "Application",
    Name: "Tidy",
    GenericName: "Disk Cleanup",
    Comment: "Give back room: old packages, caches, the journal, big downloads, duplicate files",
    Icon: "user-trash",
    Categories: ["System", "Utility"],
    Keywords: ["hygieia", "clean", "cleanup", "tidy", "space", "disk", "cache", "duplicates", "duplicate", "orphans", "paccache", "journal", "free"],
    Exec: Desktop.execLine(Quickshell.shellDir + "/hygieia/bin/hygieia", ""),
    Terminal: "false",
    StartupNotify: "false",
  })

  // ── THE WINDOW ─────────────────────────────────────────────────────
  // Floating by its title (hypr/lua/rules.lua: "hygieia").
  property var win: null
  LazyComponent {
    id: lazy
    source: Qt.resolvedUrl("HygieiaWindow.qml")
    tag: "hygieia"
  }
  function open() {
    lazy.withReady(() => {
      let fresh = false;
      if (!mgr.win) {
        const t0 = Date.now();
        mgr.win = lazy.comp.createObject(mgr, { mgr: mgr });
        LagNotes.mark("hygieia window", t0);
        if (!mgr.win) return;
        fresh = true;
      }
      const was = !fresh && mgr.win.visible;
      mgr.win.visible = true;
      if (was) Hyprland.dispatch(Hypr.focusTitle("hygieia"));
    });
  }
  function retire(w) {
    if (mgr.win === w) mgr.win = null;
    if (!mgr.win && lazy.waiting.length === 0) lazy.comp = null;
  }

  IpcHandler {
    target: "Hygieia"
    function open(): string { mgr.open(); return "ok"; }
  }
}
