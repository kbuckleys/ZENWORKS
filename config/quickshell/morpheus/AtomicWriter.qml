// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ATOMICWRITER — a file rewritten whole, one at a time, never half-written.
//
// What a history or a cache is saved through. Writes queue and go one after
// another, each:
//
//   Through stdin, not argv. A cache rewritten as one `printf '%s' <all of
//   it>` argument fails with E2BIG once it passes 128 KiB (a single argv
//   string's limit), and nothing is written. Closing stdin ends `cat`.
//
//   Beside the file and renamed over it: `cat >` truncates first, so a
//   crash mid-write lost the whole cache or history.
//
// This was written out in cynosure, lexi and metis, identical but for the
// name the shell ran under.

import QtQuick
import Quickshell
import Quickshell.Io

Scope {
  id: root

  // the name the `sh` runs under, so a stuck write says whose it is
  property string tag: "write"

  property var queue: []
  property var current: null

  // `done(ok)`, if given, once the file is in place (or the write failed)
  function write(path, content, done) {
    root.queue.push({ path: path, content: content, done: done || null });
    root.drain();
  }

  function drain() {
    // busy from the moment a job is taken, not from when the process says
    // it runs: while the shell starts, `running` set true reads false for a
    // while, and a second write took the first one's place (audit, 10-27)
    if (root.queue.length === 0 || root.current !== null || proc.running) return;
    const job = root.queue.shift();
    root.current = job;
    // the failure branch EXITS 1: `|| rm -f` alone ended on rm's own 0, and
    // a write into a missing directory or onto a full disk said ok (10-23).
    // The directory is made first, as FileView's setText does: a fresh
    // ~/.config/zenworks has none of its folders yet (2026-10-25)
    proc.command = ["sh", "-c",
      "mkdir -p \"$(dirname \"$1\")\" && cat > \"$1.tmp.$$\" && mv -f \"$1.tmp.$$\" \"$1\" || { rm -f \"$1.tmp.$$\"; exit 1; }",
      root.tag, job.path];
    proc.stdinEnabled = true;
    proc.running = true;
  }

  Process {
    id: proc
    // the content written once cat is really there (audit, 2026-10-27):
    // a write made in the same breath as `running` was lost while the shell
    // was still starting — cat then waited on stdin for good, and so did
    // every write queued behind it
    onStarted: {
      const job = root.current;
      proc.write(job ? job.content : "");
      proc.stdinEnabled = false;
    }
    onExited: (code) => {
      const job = root.current;
      root.current = null;
      if (job && job.done) job.done(code === 0);
      root.drain();
    }
  }
}
