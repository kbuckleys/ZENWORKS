// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// SHARE — the suite's one Share menu (2026-10-21): files out to something
// else. Email… (xdg-email, the mail app attaching them — only offered
// while a mail app answers mailto:), New note in Clio. The choices are
// share.js'. Upload for a link (0x0.st) and Copy file were dropped
// 2026-10-22.
//
// A host puts the submenu in its own right-click menu:
//   out.push({ label: "Share", glyph: …, sub: Share.items(() => paths, anyDir, count) })
// `paths` is a function, read when an entry is chosen, so a menu built
// ahead of the click acts on what is chosen then (terminus' held row).

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "share.js" as S

Singleton {
  id: root

  // md-share_variant, for the hosts' menu row
  readonly property string glyph: "󰂗"

  // a mail app answers mailto: — asked at start and again on every menu
  // build, so one installed later shows from the next menu on
  property bool canMail: false
  Process {
    id: mailProbe
    command: ["xdg-mime", "query", "default", "x-scheme-handler/mailto"]
    running: true
    stdout: StdioCollector { onStreamFinished: root.canMail = text.trim() !== "" }
  }

  function items(paths, anyDir, count) {
    // LATER, NOT HERE: items() is called inside the hosts' menu bindings,
    // and reading mailProbe.running there made each probe's end rebuild the
    // whole menu, which started the next probe — a loop that recreated the
    // rows every few ms and took a clicked row's pending act with them
    // (2026-10-22: terminus' file menu answered no clicks). Out of the
    // binding, only a real change of canMail rebuilds.
    Qt.callLater(root.reprobe);
    return S.targets(count, anyDir, root.canMail).map((t) => ({
      label: t.label, glyph: t.glyph, act: () => root.run(t.id, typeof paths === "function" ? paths() : paths)
    }));
  }

  function reprobe() { if (!mailProbe.running) mailProbe.running = true; }

  function run(id, paths) {
    if (!paths || !paths.length) return;
    if (id === "email") Quickshell.execDetached(S.emailArgs(paths));
    else if (id === "clio") Quickshell.execDetached(["qs", "ipc", "call", "Clio", "files", paths.join("\n")]);
  }
}
