// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE THEME AND THE FONTS, CARRIED OUT OF THE SHELL. Oracle is the one
// place a font is set: hyprland gets lua/font.lua (below), and kitty, GTK,
// gsettings and fontconfig's generic families scripts/fontsync.sh. Oracle's
// Corner rounding reaches hyprland's windows through base.lua's own line.
//
// THE THEME. kitty, hyprland, GTK and Qt paint with their
// own config, so when the theme changes they are each written a file
// (themesync.js) and told to read it: kitty reloads its config on SIGUSR1,
// hyprland on `hyprctl reload`. GTK reads gtk-4.0/colors.css and
// gtk-3.0/colors.css (each gtk.css @imports its own) as an app starts, and
// scripts/gtkscheme.sh sets dark or light, which libadwaita hears live.
// Qt apps read qt6ct/qt6ct.conf and its color scheme, also as they start.
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
    // an Accent color of its own makes even Zenon a palette to hand on
    if (Zenon.accentOwn === "" && (Zenon.themeName === "zenon" || !Zenon.theme.colors)) return null;
    const out = { name: Zenon.theme.name || Zenon.themeName };
    for (const s of ["ground", "card", "surface", "ink", "muted", "soft", "keyInk", "dim", "red",
                     "green", "yellow", "blue", "magenta", "cyan", "pink", "sand",
                     "border", "onAccent"])
      out[s] = Zenon.hex(Zenon[s]);
    return out;
  }
  readonly property string kittyText: Sync.renderKitty(sync.colors, Zenon.light)
  readonly property string gtk4Text: Sync.renderGtk4(sync.colors, Zenon.light)
  readonly property string gtk3Text: Sync.renderGtk3(sync.colors, Zenon.light)
  // dark or light for every GTK app, Zenon included (gtkscheme.sh)
  readonly property string scheme: Sync.colorScheme(Zenon.light)
  onSchemeChanged: schemeSettle.restart()
  Timer {
    id: schemeSettle
    interval: 400
    onTriggered: Quickshell.execDetached(
      [Quickshell.shellDir + "/scripts/gtkscheme.sh", sync.scheme])
  }
  // hyprland's borders follow the theme Zenon included (user, 2026-10-19):
  // kitty keeps its own zenon.conf for Zenon, but base.lua's literals were
  // another palette's, so hyprland is always handed the colors
  readonly property var hyprColors: {
    const out = { name: Zenon.theme.name || Zenon.themeName };
    for (const s of ["surface", "ink", "red", "blue", "magenta", "cyan", "pink", "sand",
                     "border", "onAccent"])
      out[s] = Zenon.hex(Zenon[s]);
    return out;
  }
  readonly property string hyprText: Sync.renderHyprTheme(sync.hyprColors)
  // Qt's palette (qt6ct), Zenon included: Qt's own is Fusion's grays
  readonly property var qtColors: {
    const out = { name: Zenon.theme.name || Zenon.themeName };
    for (const s of ["ground", "card", "surface", "ink", "muted", "red", "blue", "magenta",
                     "cyan", "border", "onAccent"])
      out[s] = Zenon.hex(Zenon[s]);
    return out;
  }
  readonly property string qtText: Sync.renderQtColors(sync.qtColors, Zenon.light)
  readonly property string qt6ctText: Sync.renderQt6ct(qtFile.path)
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

  // Oracle's Corner rounding for hyprland's windows: base.lua's own
  // `rounding = N` line, rewritten in place (themesync.js) — there is no file
  // of its own for one number base.lua already holds
  readonly property int windowCorner: Zenon.windowRadius
  onWindowCornerChanged: settle.restart()

  onKittyTextChanged: settle.restart()
  onGtk4TextChanged: settle.restart()
  onGtk3TextChanged: settle.restart()
  onHyprTextChanged: settle.restart()
  onFontTextChanged: settle.restart()
  onQtTextChanged: settle.restart()
  Component.onCompleted: { settle.restart(); fontSettle.restart(); schemeSettle.restart(); }

  // a theme file being saved is several writes; the apps hear about the last
  Timer {
    id: settle
    interval: 400
    onTriggered: {
      if (sync.put(kittyFile, sync.kittyText)) tell.kitty = true;
      if (sync.put(hyprFile, sync.hyprText)) tell.hypr = true;
      if (sync.put(fontFile, sync.fontText, true)) tell.hypr = true;
      if (sync.corner()) tell.hypr = true;
      // nothing to tell: a GTK app reads its gtk.css as it starts
      sync.put(gtk4File, sync.gtk4Text);
      sync.put(gtk3File, sync.gtk3Text);
      // nor for Qt: qt6ct reads its files as an app starts
      sync.put(qtFile, sync.qtText, true);
      sync.put(qt6ctFile, sync.qt6ctText, true);
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

  // base.lua with its window corner set to Oracle's; true when it was written.
  // Never created: no base.lua is a hyprland this shell does not configure.
  function corner() {
    if (!baseFile.exists) return false;
    const have = baseFile.last !== "" ? baseFile.last : String(baseFile.text());
    const want = Sync.setHyprRounding(have, sync.windowCorner);
    if (have === want) return false;
    baseFile.setText(want);
    baseFile.last = want;
    return true;
  }

  FileView {
    id: baseFile
    property bool exists: true
    property string last: ""
    path: sync.configDir + "/hypr/lua/base.lua"
    blockLoading: true
    printErrors: false
    // a hand edit to base.lua is read fresh before the next write
    watchChanges: true
    onFileChanged: { last = ""; reload(); }
    onLoadFailed: exists = false
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

  FileView {
    id: gtk4File
    property bool exists: true
    property string last: ""
    path: sync.configDir + "/gtk-4.0/colors.css"
    blockLoading: true
    printErrors: false
    onLoadFailed: exists = false
  }

  FileView {
    id: gtk3File
    property bool exists: true
    property string last: ""
    path: sync.configDir + "/gtk-3.0/colors.css"
    blockLoading: true
    printErrors: false
    onLoadFailed: exists = false
  }

  FileView {
    id: qtFile
    property bool exists: true
    property string last: ""
    path: sync.configDir + "/qt6ct/colors/zenworks.conf"
    blockLoading: true
    printErrors: false
    onLoadFailed: exists = false
  }

  FileView {
    id: qt6ctFile
    property bool exists: true
    property string last: ""
    path: sync.configDir + "/qt6ct/qt6ct.conf"
    blockLoading: true
    printErrors: false
    onLoadFailed: exists = false
  }
}
