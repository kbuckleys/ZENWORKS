// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ARGUS' EDITOR — what is always in the shell, which is almost nothing: an
// ipc handler, its .desktop entry, the settings every cut shares. The window
// (ArgusWindow) is compiled on first use and let go of when it closes, the
// filmstrip it shows cached per file in ~/.cache/quickshell/argus-strip.
// The recording itself is argus.lua's, in hyprland; this is what happens
// to a recording afterwards: cut it, and keep it as MP4, GIF or WebM.
//
//   `qs ipc call Argus edit <path>`   that video, in the editor
//   `qs ipc call Argus last`          the newest recording, in the editor
//   argus/bin/argus [file]            the same, from a terminal or argus.desktop
//   howler's "Recording Stopped" card  its scissors

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../morpheus"
import "../morpheus/lagnotes.js" as LagNotes
import "../morpheus/hypr.js" as Hypr
import "argus.js" as A

Scope {
  id: mgr

  // terminus, handed in by shell.qml, for Save as… (its picker)
  property var fileManager: null

  // ── WHAT EVERY CUT SHARES, KEPT ────────────────────────────────────
  property var settings: A.defaults()
  function set(key, value) {
    const s = Object.assign({}, mgr.settings);
    s[key] = value;
    mgr.settings = A.parseSettings(JSON.stringify(s));
    saveTimer.restart();
  }
  FileView {
    id: settingsFile
    path: Quickshell.statePath("argus.json")
    blockLoading: true
    printErrors: false
  }
  Timer { id: saveTimer; interval: 400; onTriggered: settingsFile.setText(A.serializeSettings(mgr.settings)) }

  // ── ITS .desktop ENTRY ─────────────────────────────────────────────
  // Offered for video in "Open with" (terminus' menu), never made the
  // default: a player is what a video opens in, an editor is chosen.
  Process {
    running: true
    command: ["sh", "-c", Desktop.installCommand("argus", {
      Type: "Application",
      Name: "Argus",
      GenericName: "Video Trimmer",
      Comment: "Cut a recording and keep it as MP4, GIF or WebM, in ZENWORKS",
      Icon: "video-x-generic",
      Categories: ["AudioVideo", "Video", "AudioVideoEditing"],
      Keywords: ["video", "trim", "cut", "gif", "webm", "mp4", "recording", "screen", "clip", "export"],
      Exec: Desktop.execLine(Quickshell.shellDir + "/argus/bin/argus", "%f"),
      Terminal: "false",
      StartupNotify: "false",
      MimeType: ["video/mp4", "video/webm", "video/x-matroska", "video/quicktime", "video/x-msvideo", "image/gif"],
    })]
  }

  // ── THE WINDOW ─────────────────────────────────────────────────────
  // One, reused: a second video opened replaces the first. Floating by its
  // title (hypr/lua/rules.lua: "argus").
  property var win: null
  LazyComponent {
    id: lazy
    source: Qt.resolvedUrl("ArgusWindow.qml")
    tag: "argus"
  }
  function withWindow(fn) {
    lazy.withReady(() => {
      let fresh = false;
      if (!mgr.win) {
        const t0 = Date.now();
        mgr.win = lazy.comp.createObject(mgr, { mgr: mgr });
        LagNotes.mark("argus window", t0);
        if (!mgr.win) return;
        fresh = true;
      }
      const was = !fresh && mgr.win.visible;
      fn(mgr.win);
      mgr.win.visible = true;
      if (was) Hyprland.dispatch(Hypr.focusTitle("argus"));
    });
  }
  function retire(w) {
    if (mgr.win === w) mgr.win = null;
    if (!mgr.win && lazy.waiting.length === 0) lazy.comp = null;
  }

  function edit(path) {
    const p = String(path || "").trim();
    if (p === "") { mgr.last(); return; }
    mgr.withWindow((w) => w.load(p));
  }
  // the newest recording in the captures directory argus.lua writes to
  Process {
    id: lastProc
    command: ["sh", "-c", "v=$(xdg-user-dir VIDEOS 2>/dev/null); { [ -n \"$v\" ] && [ \"$v\" != \"$HOME\" ]; } || v=\"$HOME/Videos\"; "
      + "ls -t \"$v/Captures\"/*.mp4 \"$v/Captures\"/*.mkv \"$v/Captures\"/*.webm 2>/dev/null | head -n1"]
    stdout: StdioCollector {
      id: lastOut
      waitForEnd: true
      onStreamFinished: {
        const p = lastOut.text.trim();
        // no recordings yet: the window still opens, empty, with Open…
        mgr.withWindow((w) => { if (p !== "") w.load(p); });
      }
    }
  }
  function last() { lastProc.running = true; }

  IpcHandler {
    target: "Argus"
    function edit(path: string): string { mgr.edit(path); return "ok"; }
    function last(): string { mgr.last(); return "ok"; }
  }

  Component.onCompleted: mgr.settings = A.parseSettings(settingsFile.text())
}
