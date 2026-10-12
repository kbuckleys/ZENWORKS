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
//   its downloads        in the shell's Jobs drawer, beside terminus' copies:
//                        iris reports each over one standing line (below),
//                        and the drawer's cancel goes back the same way
//   its logins           calypso's Quick Access, opened searching for the
//                        site (`quick`, handed in by shell.qml): you pick,
//                        calypso types it into the field iris has focused.
//                        No secret ever passes through iris or this line.
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
  // calypso's Quick Access, and calypso itself (a suggested password is
  // made and kept there), handed in by shell.qml
  property var quick: null
  property var vault: null
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

  // ── THE LINE TO IRIS ───────────────────────────────────────────────
  // One socket iris keeps open while it runs (iris/core/shelllink.py), JSON
  // a line at a time, rather than a `qs ipc call` per progress tick:
  //
  //   iris → here   {job: "start", key, name, dest}
  //                 {job: "progress", key, pct, rate, eta}
  //                 {job: "end", key, state: "done" | "failed" | "stopped"}
  //                 {fill: site}             a login form: Quick Access
  //                 {suggest: {site, url, username, twice}}   a sign-up:
  //                                          calypso makes, keeps, types
  //   here → iris   {cancel: key}            the drawer's stop
  property var link: null
  // iris' key for a download ↔ the Jobs row it is
  property var rows: ({})
  property var keys: ({})

  SocketServer {
    active: true
    path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/quickshell/iris-shell.sock"
    handler: Socket {
      id: sock
      parser: SplitParser { onRead: (line) => mgr.hear(sock, line) }
      onConnectedChanged: if (!connected && mgr.link === sock) mgr.link = null
    }
  }

  function hear(sock, line) {
    mgr.link = sock;
    let m = null;
    try { m = JSON.parse(line); } catch (e) { return; }
    if (m && typeof m.fill === "string") { if (mgr.quick) mgr.quick.openFor(m.fill); return; }
    if (m && m.suggest) {
      const s = m.suggest;
      if (mgr.vault) mgr.vault.suggest(String(s.site || ""), String(s.url || ""), String(s.username || ""), !!s.twice);
      return;
    }
    if (!m || m.key === undefined) return;
    if (m.job === "start") {
      const id = Jobs.adopt("download", [String(m.name || "download")], String(m.dest || ""));
      mgr.rows[m.key] = id;
      mgr.keys[id] = m.key;
    } else if (m.job === "progress") {
      const id = mgr.rows[m.key];
      if (id) Jobs.update(id, { pct: Math.max(0, Math.min(100, m.pct | 0)), rate: String(m.rate || ""), eta: String(m.eta || "") });
    } else if (m.job === "end") {
      const id = mgr.rows[m.key];
      if (!id) return;
      if (m.state === "stopped") Jobs.update(id, { cancelled: true });
      Jobs.exited(id, m.state === "done" ? 0 : 1);
      delete mgr.rows[m.key];
      delete mgr.keys[id];
    }
  }

  Connections {
    target: Jobs
    function onCancelAsked(id) {
      const k = mgr.keys[id];
      if (k === undefined || !mgr.link) return;
      mgr.link.write(JSON.stringify({ cancel: k }) + "\n");
      mgr.link.flush();
    }
  }
}
