// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// WHAT IS TAKING UP A VOLUME'S ROOM, ASKED — morpheus/py/usage.py for one
// mount: the free room at once, the last walk's kinds from the shared
// cache, and a fresh walk at idle priority when that one is old. Hands
// over what UsageBar and UsageLegend draw, colored from the theme.
//
//     UsageScan { id: use; mount: d.mount; active: sheet.open }
//     UsageBar { segments: use.segments; … }
//     UsageLegend { items: use.legend }
//
// Only while `active`: a sheet shut or a pane gone stops the walk (it
// starts again where it left off — from nothing — next time; the cache
// is only written by a walk that finished).

import QtQuick
import Quickshell
import Quickshell.Io
import "../morpheus"
import "usage.js" as U

Item {
  id: use

  property string mount: ""
  property bool active: true

  property var df: null
  property var cats: null
  property int at: 0
  property bool scanning: false
  property int files: 0
  // statvfs refused the mount (gone, or not ours to read): why
  property string error: ""

  readonly property var segments: U.stretches(use.df, use.cats).map((s) => ({ frac: s.frac, ink: use.inkOf(s.ink) }))
  readonly property var legend: U.legend(use.df, use.cats).map((l) => ({ name: l.name, line: l.line, ink: use.inkOf(l.ink) }))
  readonly property string words: U.scanWords({ scanning: use.scanning, files: use.files, at: use.at })
  readonly property real used: use.df && use.df.total > 0 ? use.df.used / use.df.total : -1

  // a kind's color by Zenon's name for it; "" is the track's (free room)
  function inkOf(name) { return name ? Zenon[name] : Zenon.wash(0.08); }

  function rescan() { use.run(true); }
  function run(fresh) {
    proc.running = false;
    use.df = null;
    use.cats = null;
    use.at = 0;
    use.scanning = false;
    use.files = 0;
    use.error = "";
    if (use.mount === "" || !use.active) return;
    proc.command = ["python3", "-I", Quickshell.shellDir + "/morpheus/py/usage.py", use.mount,
                    "--cache", Quickshell.statePath("usage.json")].concat(fresh ? ["--fresh"] : []);
    proc.running = true;
  }
  onMountChanged: use.run(false)
  onActiveChanged: if (use.active) use.run(false); else proc.running = false
  Component.onCompleted: use.run(false)

  Process {
    id: proc
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: (line) => {
        const e = U.parseLine(line);
        if (!e) return;
        if (e.ev === "df") use.df = e;
        else if (e.ev === "done" && e.ok === false) use.error = e.why || "It could not be read";
        else if (e.ev === "scan") { use.scanning = true; use.files = e.files; }
        else if (e.ev === "cats") { use.cats = e.cats; use.at = e.at; if (!e.cached) use.scanning = false; }
      }
    }
    onExited: use.scanning = false
  }
}
