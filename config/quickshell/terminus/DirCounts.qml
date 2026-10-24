// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// HOW MANY THINGS A DIRECTORY HOLDS, for the grid's second line under a
// name (user, 2026-10-10: size under a file, a count under a directory).
// Nothing else in the window knew: a listing is one level deep, and du is
// for bytes, in the usage mode only.
//
// Asked only for the directories a GRID is showing, one process for all of
// them, and asked again for a directory only when its mtime has moved —
// adding or removing an entry is exactly what moves a directory's mtime,
// and the listing that carries it is already being kept fresh.

import QtQuick
import Quickshell.Io

Item {
  id: counts
  property var term: null

  // path -> { all, shown, m }: everything in it, the part that is not
  // hidden, and the mtime it was counted at. `shown` is what the grid says
  // while hidden files are off, so the number matches what opening it shows.
  property var known: ({})

  // the grid's directories, as "path\tmtime" lines — a string, so a listing
  // rebuilt with the same directories does not count them again
  readonly property string want: {
    if (!counts.term) return "";
    const out = [];
    const ps = [counts.term.paneLRef, counts.term.dual ? counts.term.paneRRef : null];
    for (const p of ps) {
      if (!p || p.viewMode !== "grid") continue;
      const v = p.view || [];
      for (let i = 0; i < v.length && out.length < 4000; ++i)
        if (v[i] && v[i].isDir) out.push(v[i].path + "\t" + (v[i].mtime || 0));
    }
    return out.join("\n");
  }
  onWantChanged: aim.restart()
  Timer { id: aim; interval: 120; onTriggered: counts.run() }

  property bool again: false
  function run() {
    if (proc.running) { counts.again = true; return; }
    if (counts.want === "") return;
    const ask = [];
    for (const line of counts.want.split("\n")) {
      const tab = line.lastIndexOf("\t");
      const p = line.slice(0, tab), m = Number(line.slice(tab + 1));
      const k = counts.known[p];
      if (!k || k.m !== m) { ask.push(p); proc.mtimes[p] = m; }
    }
    if (ask.length === 0) return;
    // a name per line, so a name with a newline in it miscounts by one —
    // a count, not an inventory
    proc.command = ["sh", "-c",
      'for d do\n'
      + '  if [ -r "$d" ] && [ -x "$d" ]; then\n'
      + '    n=$(find "$d" -mindepth 1 -maxdepth 1 -printf "%f\\n" 2>/dev/null'
      + ' | awk \'{ t++; if (substr($0, 1, 1) != ".") v++ } END { print t + 0, v + 0 }\')\n'
      + '  else n="- -"; fi\n'
      + '  printf "%s\\037%s\\036" "$d" "$n"\n'
      + 'done', "sh"].concat(ask);
    proc.running = true;
  }
  Process {
    id: proc
    property var mtimes: ({})
    onExited: if (counts.again) { counts.again = false; Qt.callLater(counts.run); }
    stdout: StdioCollector {
      id: out
      waitForEnd: true
      onStreamFinished: {
        const next = Object.assign({}, counts.known);
        for (const rec of String(out.text).split("\x1e")) {
          if (rec === "") continue;
          const f = rec.split("\x1f");
          if (f.length < 2) continue;
          const n = f[1].split(" ");
          next[f[0]] = n[0] === "-" ? { all: -1, shown: -1, m: proc.mtimes[f[0]] }
            : { all: Number(n[0]) || 0, shown: Number(n[1]) || 0, m: proc.mtimes[f[0]] };
        }
        proc.mtimes = ({});
        counts.known = next;
      }
    }
  }

  // "12 items", "1 item", "empty"; "" until it has been counted, or when
  // it cannot be read
  function countText(e) {
    if (!e) return "";
    const k = counts.known[e.path];
    if (!k || k.all < 0) return "";
    const n = counts.term.showHidden ? k.all : k.shown;
    return n === 0 ? "empty" : n === 1 ? "1 item" : n + " items";
  }
}
