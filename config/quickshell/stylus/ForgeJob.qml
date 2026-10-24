// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ONE LONG forge.py RUN THAT OUTLIVES THE WINDOW — a write, a surface
// scan, a backup: started with what it is about, followed line by line
// (S.advance), stopped with SIGTERM, and ended with forge's own done event
// — or, when it died saying nothing, its last stderr line as the why.
//
//     ForgeJob { id: writing; core: mgr.core; dying: "The writer stopped"
//                onEnded: (job) => … }
//     writing.start(["write", src, …], { drives: … })   // false when busy
//     writing.job      { …what it is about, phase, frac, rate, phaseMs, result }
//
// The manager holds one of these per kind, so the three can run at once.

import QtQuick
import Quickshell.Io
import "stylus.js" as S

QtObject {
  id: fj

  property string core: ""
  // the why when it exits without a done line
  property string dying: "It stopped"
  property var job: null
  readonly property bool running: proc.running
  signal ended(var job)

  function start(args, about) {
    if (proc.running) return false;
    fj.job = Object.assign({ phase: "", frac: 0, rate: 0, phaseMs: 0, at: Date.now(), result: null }, about || {});
    proc.tail = "";
    proc.command = ["python3", "-I", fj.core].concat(args);
    proc.running = true;
    return true;
  }
  function stop() { if (proc.running) proc.signal(15); }
  // the result put away
  function clear() { if (!proc.running) fj.job = null; }

  property Process runner: Process {
    id: proc
    property string tail: ""
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: (line) => { const e = S.parseEvent(line); if (e && fj.job) fj.job = S.advance(fj.job, e, Date.now()); }
    }
    stderr: SplitParser { splitMarker: "\n"; onRead: (line) => proc.tail = line }
    onExited: (code) => {
      if (fj.job && !fj.job.result)
        fj.job = S.advance(fj.job, { ev: "done", ok: false, code: "io", why: proc.tail || fj.dying }, Date.now());
      fj.ended(fj.job);
    }
  }
}
