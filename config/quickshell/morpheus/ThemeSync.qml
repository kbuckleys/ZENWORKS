// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE THEME AND THE FONTS, CARRIED OUT OF THE SHELL. Oracle is the one
// place a font is set: hyprland gets lua/font.lua (below), and kitty, GTK,
// gsettings and fontconfig's generic families scripts/fontsync.sh. Oracle's
// Corner rounding reaches hyprland's windows through lua/corner.lua.
//
// THE THEME. kitty, hyprland, GTK and Qt paint with their
// own config, so when the theme changes they are each written a file
// (themesync.js) and told to read it: kitty reloads its config on SIGUSR1,
// hyprland on `hyprctl reload`. GTK 4 reads gtk-4.0/colors.css (its
// gtk.css @imports it) as an app starts, and scripts/gtkscheme.sh sets dark
// or light, which libadwaita hears live. GTK 3's gtk-3.0/colors.css rides
// in a theme gtkscheme.sh swaps, so running GTK 3 and Electron apps repaint.
// Qt apps read qt6ct/qt6ct.conf and its color scheme, also as they start.
// hyprtoolkit apps (hyprshutdown) read hypr/hyprtoolkit.conf, and watch it.
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
import "../oracle"
import "themesync.js" as Sync

Item {
  id: sync

  readonly property string configDir: Oracle.configHome
  // hyprland's generated files go with your own (Oracle's hyprLuaDir): the
  // config beside the shell is shipped and may be read-only
  readonly property string hyprLuaDir: Oracle.hyprLuaDir

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
  // kitty's config is yours, beside its theme (see renderKittyConf)
  readonly property string kittyDir: Oracle.zenworksDir + "/kitty"
  readonly property string kittyConfText: Sync.renderKittyConf(Oracle.shippedDir + "/kitty")
  readonly property string gtk4Text: Sync.renderGtk4(sync.colors, Zenon.light)
  readonly property string gtk3Text: Sync.renderGtk3(sync.colors, Zenon.light)
  // dark or light for every GTK app, Zenon included (gtkscheme.sh)
  readonly property string scheme: Sync.colorScheme(Zenon.light)
  // the mode flips at once: color-scheme now, and GTK 3's colors.css
  // without the settle — its slot swaps once the write lands (gtk3File)
  onSchemeChanged: {
    sync.gtkScheme("now");
    if (!sync.put(gtk3File, sync.gtk3Text)) sync.gtkScheme("reload");
  }
  function gtkScheme(how) {
    Quickshell.execDetached([Quickshell.shellDir + "/scripts/gtkscheme.sh", sync.scheme]
      .concat(how ? [how] : []));
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
  // hyprtoolkit's (hyprshutdown's screen), Zenon included, with oracle's
  // Font and Corner rounding: its stock look is no theme of ours
  readonly property var toolkitColors: {
    const out = { name: Zenon.theme.name || Zenon.themeName };
    for (const s of ["ground", "card", "surface", "ink", "blue", "cyan", "magenta"])
      out[s] = Zenon.hex(Zenon[s]);
    return out;
  }
  readonly property string toolkitText: Sync.renderHyprtoolkit(sync.toolkitColors, Zenon.light, {
    face: Zenon.face, mono: Zenon.faceCode,
    px: { text: Zenon.px(16), small: Zenon.px(13), h3: Zenon.px(17), h2: Zenon.px(20), h1: Zenon.px(25) },
    large: Zenon.dialogRadius, small: Zenon.radiusControl })
  // fcitx5's candidate list (themesync.js), only while oracle's Input
  // methods is on: written through sh, as its directory may not be there
  // yet, then a running fcitx5 told to read it again
  readonly property string fcitxText: Oracle.imOn ? Sync.renderFcitxTheme({
    name: Zenon.theme.name || Zenon.themeName, card: Zenon.hex(Zenon.card),
    border: Zenon.hex(Zenon.border), ink: Zenon.hex(Zenon.ink), cyan: Zenon.hex(Zenon.cyan) }) : ""
  readonly property string fcitxPath: (Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share"))
    + "/fcitx5/themes/default/theme.conf"
  property string fcitxLast: ""
  onFcitxTextChanged: settle.restart()
  function putFcitx() {
    if (sync.fcitxText === "" || sync.fcitxText === sync.fcitxLast) return;
    sync.fcitxLast = sync.fcitxText;
    Quickshell.execDetached(["sh", "-c",
      "mkdir -p \"${2%/*}\" && printf %s \"$1\" > \"$2.tmp\" && mv -f \"$2.tmp\" \"$2\" && fcitx5-remote --check -r; exit 0",
      "fcitxtheme", sync.fcitxText, sync.fcitxPath]);
  }
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

  // Oracle's Corner rounding for hyprland's windows: lua/corner.lua
  // (themesync.js), which base.lua reads
  readonly property int windowCorner: Zenon.windowRadius
  readonly property string cornerText: Sync.renderCornerLua(sync.windowCorner)
  onWindowCornerChanged: settle.restart()

  onKittyTextChanged: settle.restart()
  onGtk4TextChanged: settle.restart()
  onGtk3TextChanged: settle.restart()
  onHyprTextChanged: settle.restart()
  onFontTextChanged: settle.restart()
  onQtTextChanged: settle.restart()
  onToolkitTextChanged: settle.restart()
  // a start only checks the slot worn (gtkscheme.sh)
  Component.onCompleted: { settle.restart(); fontSettle.restart(); sync.gtkScheme(""); }

  // a theme file being saved is several writes; the apps hear about the last
  Timer {
    id: settle
    interval: 400
    onTriggered: {
      if (sync.put(kittyConfFile, sync.kittyConfText, true)) tell.kitty = true;
      if (sync.put(kittyFile, sync.kittyText)) tell.kitty = true;
      if (sync.put(hyprFile, sync.hyprText)) tell.hypr = true;
      if (sync.put(fontFile, sync.fontText, true)) tell.hypr = true;
      if (sync.put(cornerFile, sync.cornerText, true)) tell.hypr = true;
      // nothing to tell GTK 4: an app reads its gtk.css as it starts
      sync.put(gtk4File, sync.gtk4Text);
      // GTK 3 rereads colors.css when gtkscheme.sh names a fresh theme slot,
      // once the write has landed (gtk3File's onSaved)
      sync.put(gtk3File, sync.gtk3Text);
      // nor for Qt: qt6ct reads its files as an app starts
      sync.put(qtFile, sync.qtText, true);
      sync.put(qt6ctFile, sync.qt6ctText, true);
      // nor for hyprtoolkit: its apps watch the file themselves
      sync.put(toolkitFile, sync.toolkitText, true);
      sync.putFcitx();
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
    id: cornerFile
    property bool exists: true
    property string last: ""
    path: sync.hyprLuaDir + "/corner.lua"
    blockLoading: true
    printErrors: false
    onLoadFailed: exists = false
  }

  FileView {
    id: kittyConfFile
    property bool exists: true
    property string last: ""
    path: sync.kittyDir + "/kitty.conf"
    blockLoading: true
    printErrors: false
    onLoadFailed: exists = false
  }

  FileView {
    id: kittyFile
    property bool exists: true
    property string last: ""
    path: sync.kittyDir + "/theme.conf"
    blockLoading: true
    printErrors: false
    onLoadFailed: exists = false
  }

  FileView {
    id: hyprFile
    property bool exists: true
    property string last: ""
    path: sync.hyprLuaDir + "/theme.lua"
    blockLoading: true
    printErrors: false
    onLoadFailed: exists = false
  }

  FileView {
    id: fontFile
    property bool exists: true
    property string last: ""
    path: sync.hyprLuaDir + "/font.lua"
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
    // on disk now: wear the other slot so running apps reread it
    onSaved: sync.gtkScheme("reload")
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

  FileView {
    id: toolkitFile
    property bool exists: true
    property string last: ""
    path: sync.configDir + "/hypr/hyprtoolkit.conf"
    blockLoading: true
    printErrors: false
    onLoadFailed: exists = false
  }
}
