// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// IRIS, FROM THE SHELL'S SIDE. Iris runs in its own process (iris/bin/iris —
// PySide6, not quickshell); this is the part that lives in the shell, which
// iris depends on:
//
//   its .desktop entry   written on startup when missing, with this
//                        machine's path, as plato's and calypso's are; it
//                        names iris a browser, and claims http/https/html
//                        only where nothing has been chosen — a default
//                        browser picked in oracle's Default apps stays
//   `qs ipc call Iris open [url]`   the browser, at that page
//
// Everything else iris needs of the shell it reads itself: the theme
// (ThemeSync's snapshot) and the suite's toolkit (iris/core/toolkit.py).
//
// iris/shell/ is the one directory of iris that quickshell loads; preflight
// compiles it with the shell's files and the rest of iris in iris' host.

import QtQuick
import Quickshell
import Quickshell.Io
import "../../morpheus"

Scope {
  id: mgr

  readonly property string bin: Quickshell.shellDir + "/iris/bin/iris"
  readonly property var mimes: ["x-scheme-handler/http", "x-scheme-handler/https",
                                "text/html", "application/xhtml+xml"]

  // ── ITS .desktop ENTRY ─────────────────────────────────────────────
  Process {
    running: true
    command: ["sh", "-c", Desktop.installCommand("iris", {
      Type: "Application",
      Name: "Iris",
      GenericName: "Web Browser",
      Comment: "The web, in ZENWORKS",
      Icon: "web-browser",
      Categories: ["Network", "WebBrowser"],
      Keywords: ["web", "browser", "internet", "www", "http", "cloak", "private"],
      Exec: Desktop.execLine(mgr.bin, "%u"),
      Terminal: "false",
      StartupNotify: "false",
      StartupWMClass: "iris",
      MimeType: mgr.mimes,
    }) + "\nfor m in \"$@\"; do\n"
      + "  [ -n \"$(xdg-mime query default \"$m\" 2>/dev/null)\" ] || gio mime \"$m\" iris.desktop >/dev/null 2>&1\n"
      + "done\nexit 0\n", "sh"].concat(mgr.mimes)
  }

  // the browser, at `url` when given
  function open(url) {
    Quickshell.execDetached([mgr.bin].concat(url ? [String(url)] : []));
  }

  IpcHandler {
    target: "Iris"
    function open(url: string): string { mgr.open(url); return "ok"; }
  }
}
