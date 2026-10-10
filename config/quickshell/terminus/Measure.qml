// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// Terminus' how big a directory really is … logic, out of TerminusWindow.qml
// (2026-10-08). The state stays on the window (term); the window keeps a
// one-line forwarder for each function here, so callers are unchanged.

import QtQuick
import QtQuick.Shapes
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick.Effects
import QtMultimedia
import Qt.labs.folderlistmodel
import "../morpheus"
import "../picasso"
import "../oracle"
import "terminus.js" as Terminus
import "../morpheus/icons.js" as Icons
import "../morpheus/thumbs.js" as Thumbs
import "tags.js" as Tags
import "collections.js" as Coll

Item {
  id: measure
  property var term: null
  readonly property alias selMeasure: selMeasure
  readonly property alias usageDelay: usageDelay

  Process {
    id: duProc
    stdout: StdioCollector {
      id: duOut
      waitForEnd: true
      onStreamFinished: {
        const got = Terminus.parseDirSizes(duOut.text);
        const next = Object.assign({}, term.dirSizes, got);
        term.dirSizes = next;
        // and handed to the manager, so the NEXT window starts measured —
        // see revealWhenReady
        if (term.mgr) term.mgr.noteSizes(got);
        const n = Object.keys(got).length;
        // In the usage view the bars ARE the report, and a line reading
        // "measured 22" left over from the directory before this one is just
        // a wrong caption under a right picture.
        if (term.duQuiet) {
          // measured for the selection's total, which is the report — see
          // measureMarked. Nothing to say in the status line.
          term.duQuiet = false;
          Qt.callLater(term.measureMarked);
          if (term.usage) Qt.callLater(term.measureAll);
        } else if (term.usage) {
          term.status = "";
          // whatever this batch could not reach, and anything listed since it
          // started — see measureAll's note about being busy
          Qt.callLater(term.measureAll);
          Qt.callLater(term.measureMarked);
        } else {
          // only the nothing-measured case is bad news; the others are counts
          if (n === 0) term.warn("could not measure");
          else term.status = (n === 1 ? "measured" : "measured " + n);
          // marks made while this ran are still waiting for their total
          Qt.callLater(term.measureMarked);
        }
      }
    }
  }
  Process {
    id: gitProc
    stdout: StdioCollector {
      id: gitOut
      waitForEnd: true
      onStreamFinished: {
        // Asked about the directory we were in when the scan started, not the
        // one we are in now: a reply that arrives after you have walked on
        // would otherwise be rolled up against the wrong base and mark rows it
        // knows nothing about.
        const asked = term.gitAsked;
        term.gitAsked = "";
        if (asked !== term.cwd) return;
        const g = Terminus.parseGit(gitOut.text);
        term.gitRoot = g.root;
        term.gitBranch = g.branch;
        term.gitMarks = g.root === "" ? ({})
                                      : Terminus.gitRollup(g.entries, term.cwd);
      }
    }
  }
  function scanGit() {
    if (!term.git) return;
    // One at a time. A directory of directories walked quickly would otherwise
    // start a `git status` per keystroke and the answers would land in an order
    // nobody controls.
    if (gitProc.running) return;
    term.gitAsked = term.cwd;
    gitProc.command = ["sh", "-c", Terminus.gitCommand(term.cwd)];
    gitProc.running = true;
  }
  function toggleGit() {
    term.git = !term.git;
    if (term.git) { term.scanGit(); return; }
    term.gitMarks = ({});
    term.gitRoot = "";
    term.gitBranch = "";
  }
  // What a state is worth looking at in. Red for the two that cost you
  // something, green for what is already safely staged, and the rest below
  // the names they sit beside — a gutter that shouted would be a listing you
  // read the gutter of.
  // one definition, in terminus.js, shared with plato's tree
  function gitInk(state) { return Terminus.gitInk(state); }
  // The measured size of a row: a walked directory, or a file, which is
  // already its own whole answer. Undefined until du has been round.
  function usageOf(r) {
    if (!r) return 0;
    if (!r.isDir) return r.size;
    const v = term.dirSizes[r.path];
    return v === undefined ? 0 : v;
  }
  function toggleUsage() {
    term.usage = !term.usage;
    if (term.usage) {
      term.usagePrevSort = term.sortKey;
      term.usagePrevDesc = term.sortDesc;
      term.usagePrevView = term.viewMode;
      term.sortKey = "usage";
      term.sortDesc = true;
      term.duTried = ({});
      // A FRESH ANSWER, because that is what turning the mode on is asking
      // for. Sizes are cached by path and outlive the listing, which is right
      // for navigating — but a directory measured an hour and several downloads
      // ago would be reported here as though it were current.
      term.dirSizes = ({});
      // The column this mode is about only exists in the list. Toggling it in
      // the grid would reorder tiles that show no sizes, which reads as
      // nothing having happened.
      if (term.viewMode !== "list") term.act.viewMode = "list";
      term.measureAll();
    } else {
      term.sortKey = term.usagePrevSort !== "" ? term.usagePrevSort : "name";
      term.sortDesc = term.usagePrevDesc;
      if (term.usagePrevView !== "" && term.usagePrevView !== term.viewMode)
        term.act.viewMode = term.usagePrevView;
      term.status = "";
    }
  }
  // Opening a branch puts directories on screen without re-listing cwd, so
  // nothing else would come back to measure them. Debounced for the reason
  // the empty-directory probe is: expanding changes the rows twice in quick
  // succession, and du is a walk of the whole subtree.
  Timer {
    id: usageDelay
    interval: 150
    onTriggered: term.measureAll()
  }
  function measureAll() {
    if (!term.usage) return;
    // Busy is not the same as done. This used to just give up, and since the
    // only caller was the listing, nothing ever came back to it: walk into a
    // directory while the previous one is still being measured and its directories
    // kept their dashes for as long as the window stayed open. The retry now
    // lives in duProc's completion, so being busy costs a wait rather than the
    // whole answer.
    if (duProc.running) return;
    const tried = term.duTried;
    const sizes = term.dirSizes;
    // ── EVERY DIRECTORY DRAWN, NOT ONLY THE TOP LEVEL ───────────────
    // This asked about root.rows, which is the listing — so a directory
    // spliced into the tree by opening a branch was never handed to du at
    // all. Its bar stayed an empty track for ever, which the delegate
    // draws to mean "asked, no answer yet" and here meant "never asked":
    // usage had nothing to do with the child rows. `view` is what is on
    // screen, which is also what usageMax is already measured against, so
    // the bars and the yardstick now come from the same set of rows.
    const todo = term.view.filter((r) => r.isDir
      && sizes[r.path] === undefined && tried[r.path] !== true);
    if (todo.length === 0) { term.status = ""; return; }
    const next = Object.assign({}, tried);
    for (const r of todo) next[r.path] = true;
    term.duTried = next;
    term.status = "measuring " + todo.length
      + (todo.length === 1 ? " directory\u2026" : " directories\u2026");
    duProc.command = Terminus.shArgv(
      Terminus.dirSizeCommand(todo.map((r) => r.path)));
    duProc.running = true;
  }
  Timer {
    id: selMeasure
    interval: 350
    onTriggered: term.measureMarked()
  }
  function measureMarked() {
    if (term.markedCount === 0 || duProc.running) return;
    const tried = term.selTried;
    const todo = term.markedRows().filter((r) => r.isDir
      && term.dirSizes[r.path] === undefined && tried[r.path] !== true);
    if (todo.length === 0) return;
    const next = Object.assign({}, tried);
    for (const r of todo) next[r.path] = true;
    term.selTried = next;
    term.duQuiet = true;
    duProc.command = Terminus.shArgv(
      Terminus.dirSizeCommand(todo.map((r) => r.path)));
    duProc.running = true;
  }
  function measureDirs() {
    const dirs = term.acting().filter((r) => r.isDir);
    if (dirs.length === 0) { term.warn("no directory to measure"); return; }
    if (duProc.running) { term.status = "still measuring\u2026"; return; }
    term.status = "measuring " + (dirs.length === 1 ? dirs[0].name
      : dirs.length + " directories") + "\u2026";
    duProc.command = Terminus.shArgv(
      Terminus.dirSizeCommand(dirs.map((r) => r.path)));
    duProc.running = true;
  }
}
