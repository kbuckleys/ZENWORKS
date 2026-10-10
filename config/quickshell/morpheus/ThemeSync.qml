// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE THEME, CARRIED OUT OF THE SHELL. kitty and hyprland paint with their
// own config, so when the theme changes they are each written a file
// (themesync.js) and told to read it: kitty reloads its config on SIGUSR1,
// hyprland on `hyprctl reload`.
//
// ONLY WHEN THE FILE WOULD CHANGE. Every start of the shell lands here with
// the theme it was wearing, and a reload of hyprland on every login — or on
// every live reload of this file — would be a flicker for nothing. So the
// file on disk is read first and written only if it says something else.
// And Zenon never creates one: no file is Zenon already.
//
// Loaded by shell.qml through a Loader, not as a qmldir type: a new type in
// morpheus/qmldir is not seen by a live reload.

import QtQuick
import Quickshell
import Quickshell.Io
import "themesync.js" as Sync

Item {
  id: sync

  readonly property string configDir:
    Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")

  // the palette as plain hex, or null when Zenon is worn
  readonly property var colors: {
    if (Zenon.themeName === "zenon" || !Zenon.theme.colors) return null;
    const out = { name: Zenon.theme.name || Zenon.themeName };
    for (const s of ["ground", "surface", "ink", "muted", "soft", "keyInk", "dim", "red",
                     "green", "yellow", "blue", "magenta", "cyan", "pink", "sand",
                     "border", "onAccent"])
      out[s] = Zenon.hex(Zenon[s]);
    return out;
  }
  readonly property string kittyText: Sync.renderKitty(sync.colors, Zenon.light)
  readonly property string hyprText: Sync.renderHyprTheme(sync.colors)

  onKittyTextChanged: settle.restart()
  onHyprTextChanged: settle.restart()
  Component.onCompleted: settle.restart()

  // a theme file being saved is several writes; the apps hear about the last
  Timer {
    id: settle
    interval: 400
    onTriggered: {
      if (sync.put(kittyFile, sync.kittyText)) tell.kitty = true;
      if (sync.put(hyprFile, sync.hyprText)) tell.hypr = true;
      if (tell.kitty || tell.hypr) tell.restart();
    }
  }

  // AFTER THE WRITE HAS LANDED. setText writes in the background, and the
  // first version signalled straight after it: hyprland reloaded, read the
  // theme.lua that was not there yet, and kept Zenon's borders (2026-10-08).
  // Oracle waits the same way before its own `hyprctl reload`.
  Timer {
    id: tell
    interval: 250
    property bool kitty: false
    property bool hypr: false
    onTriggered: {
      if (tell.kitty) Quickshell.execDetached(["pkill", "-USR1", "-x", "kitty"]);
      if (tell.hypr) Quickshell.execDetached(["hyprctl", "reload"]);
      tell.kitty = false;
      tell.hypr = false;
    }
  }

  // write `want` if the file says something else; true when it was written
  function put(file, want) {
    // what we last wrote, when we wrote it: FileView's own write is not
    // read back (no `loaded`), so text() may still be the old file
    const have = file.last !== "" ? file.last : file.exists ? String(file.text()) : "";
    if (have === want) return false;
    if (!file.exists && !sync.colors) return false;
    file.setText(want);
    file.last = want;
    file.exists = true;
    return true;
  }

  FileView {
    id: kittyFile
    property bool exists: true
    property string last: ""
    path: sync.configDir + "/kitty/theme.conf"
    blockLoading: true
    printErrors: false
    onLoadFailed: exists = false
  }

  FileView {
    id: hyprFile
    property bool exists: true
    property string last: ""
    path: sync.configDir + "/hypr/lua/theme.lua"
    blockLoading: true
    printErrors: false
    onLoadFailed: exists = false
  }
}
