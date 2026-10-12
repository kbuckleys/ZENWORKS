// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
// ZENON palette — single source of truth, mirrors ~/.config/nvim/lua/zenon.lua
//
// THE SHELL'S ZENON: zenon/ZenonBase.qml — every token, colour and helper,
// and the reasons for each — fed what only the shell has: Oracle's settings
// and the worn theme file. Iris wears the same base in its own process, fed
// the shell's snapshot of these inputs (ThemeSync), so nothing is computed
// twice and the two cannot drift.

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../oracle"
import "zenon"

ZenonBase {
  cfg: Oracle

  readonly property FileView themeFile: FileView {
    // no file for Zenon, nor for Follow Background, which is made, not read
    path: Zenon.themeName === "zenon" || Zenon.themeName === "follow" ? ""
      : Quickshell.shellDir + "/themes/" + Zenon.themeName + ".json"
    // editing the theme you are wearing repaints the shell as you save
    watchChanges: true
    // read before the first frame: a few hundred bytes, and loaded in the
    // background the session's first frame was Zenon and then flicked over
    blockLoading: true
    printErrors: false
    onFileChanged: reload()
    onPathChanged: if (path === "") Zenon.fileTheme = ({})
    onLoaded: {
      try {
        const t = JSON.parse(text());
        Zenon.fileTheme = t && typeof t === "object" ? t : ({});
      } catch (e) {
        console.warn("zenon: theme " + Zenon.themeName + " is not valid JSON, wearing Zenon");
        Zenon.fileTheme = ({});
      }
    }
    onLoadFailed: Zenon.fileTheme = ({})
  }
}
