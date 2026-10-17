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

  function write(path, content) {
    root.queue.push({ path: path, content: content });
    root.drain();
  }

  function drain() {
    if (root.queue.length === 0 || proc.running) return;
    const job = root.queue.shift();
    proc.command = ["sh", "-c",
      "cat > \"$1.tmp.$$\" && mv -f \"$1.tmp.$$\" \"$1\" || rm -f \"$1.tmp.$$\"",
      root.tag, job.path];
    proc.stdinEnabled = true;
    proc.running = true;
    proc.write(job.content);
    proc.stdinEnabled = false;
  }

  Process {
    id: proc
    onExited: root.drain()
  }
}
