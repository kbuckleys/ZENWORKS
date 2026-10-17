// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE THEME AND THE FONTS, CARRIED OUT OF THE SHELL. Oracle is the one
// place a font is set: hyprland gets lua/font.lua (below), and kitty, GTK,
// gsettings and fontconfig's generic families scripts/fontsync.sh.
//
// THE THEME. kitty and hyprland paint with their
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
  // oracle's Font for hyprland's own text — always written, unlike the
  // theme: base.lua's literals are only a first-boot font (themesync.js)
  readonly property string fontText: Sync.renderHyprFont(Zenon.face, Zenon.weight, Zenon.px(14))
  // everything else's, as fontsync.sh's arguments (themesync.js)
  readonly property var fontArgs: [
    Sync.pangoFont(Zenon.face, Zenon.weight, Number(Zenon.cfg.fontSize) || 16),
    Sync.pangoFont(Zenon.faceCode, Zenon.codeWeight, Number(Zenon.cfg.monoSize) || 16),
    Zenon.faceCode, String(Zenon.codeWeight), String(Sync.pt(Number(Zenon.cfg.monoSize) || 16)),
    Sync.renderFontconfig(Zenon.face, Zenon.faceCode)]
  onFontArgsChanged: fontSettle.restart()
  Timer {
    id: fontSettle
    interval: 400
    onTriggered: Quickshell.execDetached(
      [Quickshell.shellDir + "/scripts/fontsync.sh"].concat(sync.fontArgs))
  }

  onKittyTextChanged: settle.restart()
  onHyprTextChanged: settle.restart()
  onFontTextChanged: settle.restart()
  Component.onCompleted: { settle.restart(); fontSettle.restart(); }

  // a theme file being saved is several writes; the apps hear about the last
  Timer {
    id: settle
    interval: 400
    onTriggered: {
      if (sync.put(kittyFile, sync.kittyText)) tell.kitty = true;
      if (sync.put(hyprFile, sync.hyprText)) tell.hypr = true;
      if (sync.put(fontFile, sync.fontText, true)) tell.hypr = true;
      if (tell.kitty || tell.hypr) tell.restart();
    }
  }

  // AFTER THE WRITE HAS LANDED. setText writes in the background, and the
  // first version signaled straight after it: hyprland reloaded, read the
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

  // write `want` if the file says something else; true when it was written.
  // A theme file is never created for Zenon; `always` creates it regardless.
  function put(file, want, always) {
    // what we last wrote, when we wrote it: FileView's own write is not
    // read back (no `loaded`), so text() may still be the old file
    const have = file.last !== "" ? file.last : file.exists ? String(file.text()) : "";
    if (have === want) return false;
    if (!file.exists && !sync.colors && !always) return false;
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

  FileView {
    id: fontFile
    property bool exists: true
    property string last: ""
    path: sync.configDir + "/hypr/lua/font.lua"
    blockLoading: true
    printErrors: false
    onLoadFailed: exists = false
  }
}
