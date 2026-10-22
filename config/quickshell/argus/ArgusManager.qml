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
import "../oracle"
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

  // ── AROUND A RECORDING (2026-10-22) ────────────────────────────────
  // argus.lua asks for Oracle's recording settings, has the countdown
  // shown, and says when it starts and stops; the countdown and the camera
  // bubble are ArgusOverlay's, made the first time either is wanted.
  property var overlay: null
  function withOverlay() {
    if (!mgr.overlay) {
      const c = Qt.createComponent(Qt.resolvedUrl("ArgusOverlay.qml"));
      if (c.status !== Component.Ready) { console.warn("argus:", c.errorString()); return null; }
      mgr.overlay = c.createObject(mgr, {});
    }
    return mgr.overlay;
  }
  property bool recording: false
  onRecordingChanged: {
    if (mgr.recording && Oracle.recCamera) { const o = mgr.withOverlay(); if (o) o.recording = true; }
    else if (mgr.overlay) mgr.overlay.recording = mgr.recording;
    mgr.bigPointer(mgr.recording && Oracle.recBigPointer);
  }
  // the pointer at twice its size while it records: hyprctl setcursor with
  // the session's own theme, and back to its own size after
  readonly property string cursorTheme: Quickshell.env("XCURSOR_THEME") || "default"
  readonly property int cursorSize: Number(Quickshell.env("XCURSOR_SIZE")) || 24
  property bool pointerBig: false
  function bigPointer(on) {
    if (on === mgr.pointerBig) return;
    mgr.pointerBig = on;
    Quickshell.execDetached(["hyprctl", "setcursor", mgr.cursorTheme, String(on ? mgr.cursorSize * 2 : mgr.cursorSize)]);
  }
  // a reload mid-recording: still recording, as far as the overlay goes
  Process {
    running: true
    command: ["pgrep", "-x", "wf-recorder"]
    onExited: (code) => { if (code === 0) mgr.recording = true; }
  }

  IpcHandler {
    target: "Argus"
    function edit(path: string): string { mgr.edit(path); return "ok"; }
    function last(): string { mgr.last(); return "ok"; }
    // for argus.lua: "countdown=3 audio=system pointer=0 camera=0"
    function recPrefs(): string {
      return A.recPrefsLine({ recCountdown: Oracle.recCountdown, recAudio: Oracle.recAudio,
                              recBigPointer: Oracle.recBigPointer, recCamera: Oracle.recCamera });
    }
    function countdown(secs: int): string { const o = mgr.withOverlay(); if (o) o.countdown(secs); return "ok"; }
    function recording(on: bool): string { mgr.recording = on; return "ok"; }
  }

  Component.onCompleted: mgr.settings = A.parseSettings(settingsFile.text())
}
