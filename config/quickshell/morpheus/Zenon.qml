// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
// ZENON palette — single source of truth, mirrors ~/.config/nvim/lua/zenon.lua
//
// THE SHELL'S ZENON: zenon/ZenonBase.qml — every token, color and helper,
// and the reasons for each — fed what only the shell has: Oracle's settings
// and the worn theme file.

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../oracle"
import "zenon"

ZenonBase {
  cfg: Oracle

  // YOURS FIRST: a theme in ~/.config/zenworks/themes (saved from Follow
  // Background, or put there by hand) is worn over the shipped one of the
  // same name beside the shell. Both are read side by side — switching one
  // FileView over from a missing file dropped the second read (2026-10-25).
  readonly property string themeStem: Zenon.themeName === "zenon" || Zenon.themeName === "follow" ? "" : Zenon.themeName
  property var themeOwn: null
  property var themeShipped: null
  function wearTheme() { Zenon.fileTheme = Zenon.themeOwn || Zenon.themeShipped || ({}); }
  function parseTheme(text, where) {
    try {
      const t = JSON.parse(text);
      return t && typeof t === "object" ? t : null;
    } catch (e) {
      console.warn("zenon: theme " + Zenon.themeName + " (" + where + ") is not valid JSON, wearing Zenon");
      return null;
    }
  }
  readonly property FileView ownFile: FileView {
    // no file for Zenon, nor for Follow Background, which is made, not read
    path: Zenon.themeStem === "" ? "" : Oracle.themesDir + "/" + Zenon.themeStem + ".json"
    // editing the theme you are wearing repaints the shell as you save
    watchChanges: true
    // read before the first frame: a few hundred bytes, and loaded in the
    // background the session's first frame was Zenon and then flicked over
    blockLoading: true
    printErrors: false
    onFileChanged: reload()
    onPathChanged: { Zenon.themeOwn = null; if (path === "") Zenon.wearTheme(); }
    onLoaded: { Zenon.themeOwn = Zenon.parseTheme(text(), "yours"); Zenon.wearTheme(); }
    onLoadFailed: { Zenon.themeOwn = null; Zenon.wearTheme(); }
  }
  readonly property FileView shippedFile: FileView {
    path: Zenon.themeStem === "" ? "" : Quickshell.shellDir + "/themes/" + Zenon.themeStem + ".json"
    watchChanges: true
    blockLoading: true
    printErrors: false
    onFileChanged: reload()
    onPathChanged: { Zenon.themeShipped = null; if (path === "") Zenon.wearTheme(); }
    onLoaded: { Zenon.themeShipped = Zenon.parseTheme(text(), "shipped"); Zenon.wearTheme(); }
    onLoadFailed: { Zenon.themeShipped = null; Zenon.wearTheme(); }
  }
}
