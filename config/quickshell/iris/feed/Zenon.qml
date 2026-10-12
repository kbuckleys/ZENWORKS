// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ZENON, AS IRIS WEARS IT. The shell's morpheus/Zenon.qml is the same base fed
// Oracle and the theme file; iris cannot reach either, so it is fed the shell's
// own snapshot of them instead (morpheus/ThemeSync writes it, core/zenonfeed.py
// watches it). core/toolkit.py points every `Zenon` the toolkit asks for here
// (its own directory, so iris' Main.qml never sees two Zenons), and a
// morpheus or terminus file loaded in iris paints exactly as in the shell.

pragma Singleton

import QtQuick
import "../../morpheus/zenon"
import IrisHost

ZenonBase {
  cfg: ZenonFeed.cfg
  fileTheme: ZenonFeed.fileTheme
  followTheme: ZenonFeed.followTheme
  daylight: ZenonFeed.daylight
  wallAccent: ZenonFeed.wallAccent
}
