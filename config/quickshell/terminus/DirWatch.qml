// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// Terminus' watching the directory … logic, out of TerminusWindow.qml
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
  id: dirWatch
  property var term: null
  readonly property alias otherWatchProc: otherWatchProc
  readonly property alias peekAim: peekAim
  readonly property alias peekWatchProc: peekWatchProc
  readonly property alias watchAim: watchAim
  readonly property alias watchProc: watchProc

  // Until now the listing only changed when TERMINUS changed it: navigate, or
  // finish an action, and it re-read. Anything done by another program — a
  // download landing, a build writing output, a file removed in a terminal —
  // went unnoticed until you left the directory and came back.
  //
  // inotifywait, because there is no alternative in reach: quickshell exposes
  // no QFileSystemWatcher to QML, and FileView's `watchChanges` watches a
  // single named file rather than a directory's contents. inotify is the
  // kernel's own answer and inotify-tools is already installed.
  //
  // -m keeps it running and prints a line per event; -q drops the startup
  // banner so the only output is events. One directory, not recursive: this
  // is about the listing on screen, and -r on a deep tree costs a watch
  // descriptor per directory underneath it.
  Process {
    id: watchProc
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: (line) => { term.noteWatchHit(line); watchSettle.restart(); }
    }
    // ── A DEAD WATCH IS INVISIBLE, WHICH IS WHY IT IS GUARDED ────────
    // inotifywait exits the moment ONE of its paths is gone. Watching
    // only cwd that could not really happen; watching the open branches
    // too, a directory deleted from under an expanded tree takes the watch
    // on the PARENT down with it — and a listing that has quietly
    // stopped updating looks exactly like a listing with nothing to say.
    //
    // So it falls back to cwd alone, which is the one path that must
    // exist for any of this to make sense, and the branches are tried
    // again the next time the set of them changes.
    //
    // ── A RESTART IS NOT A DEATH ────────────────────────────────────
    // And telling them apart is the whole job. Changing the path list
    // means stopping this process and starting another, and the stop
    // raises exactly the same signal a crash does — so every restart
    // read as a failure, set watchBare, and 800ms later re-armed the
    // watch WITHOUT the branches. Expanding a directory called watch(),
    // which killed the watcher, which dropped the branches: the tree
    // was watched for 800 milliseconds and then never again, and a file
    // deleted out of an expanded directory stayed on screen. Only cwd
    // updated, which is precisely the shape of the report.
    //
    // FLAGGED, not counted. It was a count — one credit per stop — and a
    // count assumes one exit per stop, which is wrong: two restarts before
    // the old process has finished dying are two stops of the SAME process
    // and one exit. The spare credit then swallowed the next real death,
    // the watch stayed down, and changes stopped showing until navigating
    // started a new one — the "sometimes it doesn't update". A flag says
    // "the next exit is ours", however many times we asked, so a process
    // that falls over on its own still finds it clear and still falls back. A window — "ignore
    // an exit within 500ms of a restart" — would have swallowed the case
    // this guard exists for, which is inotifywait exiting AT ONCE on a
    // path that has gone.
    onExited: (code) => {
      if (term.watchStopping) { term.watchStopping = false; return; }
      term.watchDied();
    }
  }
  function watchDied() {
    if (!term.shown || term.cwd === "" || term.searchMode !== "") return;
    if (term.watchBare) return;      // already minimal; do not spin
    term.watchBare = true;
    watchRetry.restart();
  }
  Timer {
    id: watchRetry
    interval: 800
    onTriggered: term.watch()
  }
  function noteWatchHit(line) {
    const s = String(line || "");
    if (s === "") return;
    // ── THE DIRECTORY IS NOT "EVERYTHING UP TO THE FIRST SPACE" ────────
    // inotifywait prints "<watched dir>/ EVENT[,EVENT] name" and this cut
    // at the first space. That is right until a watched directory has a space
    // in its NAME: ".../testing again/ CREATE x" was read as a hit on
    // ".../testing", which is not a directory at all, so the branch was
    // never re-read and creating or deleting anything inside it left the
    // rows exactly as they were. Buck's directory is called "testing again",
    // and every test that found this working used names without spaces.
    //
    // Nor is "/ " a safe delimiter: a path component may itself begin with
    // a space, and "/tmp/x/ notes/" contains one before the real boundary.
    //
    // MATCHED, NOT PARSED. inotifywait can only report a directory we
    // handed it, we know that list exactly, and matching a prefix cannot
    // be confused by any character a name is allowed to contain. Longest
    // wins, so a branch beats the cwd it sits under.
    const dirs = term.watching();
    let best = "";
    for (let i = 0; i < dirs.length; ++i) {
      const d = dirs[i];
      if (d.length <= best.length) continue;
      if (s.indexOf(d === "/" ? "/" : d + "/") === 0) best = d;
    }
    if (best === "") return;
    term.watchHits[best] = true;
  }
  // Coalesced. A single `cp` of a large file emits create, then a stream of
  // close_write/attrib events; re-reading the directory for each one would be
  // a find per event. One re-read once the noise stops is the same answer for
  // a fraction of the work.
  Timer {
    id: watchSettle
    interval: 250
    onTriggered: {
      if (term.searchMode !== "") return;
      const hits = term.watchHits;
      term.watchHits = ({});
      // ── ONLY WHAT MOVED ─────────────────────────────────────────────
      // The first pass at this re-listed cwd AND dropped every branch's
      // cached rows on any event anywhere. Every branch then re-read and
      // rebuilt, so a single file appearing in one of them redrew the
      // whole tree — which is the redraw, and it is entirely avoidable:
      // the event says where it happened.
      const branches = [];
      for (const d in hits) if (d !== term.cwd) branches.push(d);
      // ── THE LISTING IS ALWAYS RE-READ ───────────────────────────────
      // Deciding NOT to refresh on the strength of a parsed line means
      // one unparsed line stops the listing updating, with nothing on
      // screen to say so — the worst failure this window has. refresh()
      // compares the bytes it gets back against the ones it has, so a
      // re-read that finds nothing new costs one `find` and touches no
      // delegate. The redraw this whole change was about came from
      // re-reading every BRANCH, not from re-reading the directory.
      term.refresh();
      if (branches.length > 0) term.rereadBranches(branches);
      // A directory on screen may have gained or lost its last item. The
      // view does not change when that happens — the row is the same row
      // — so the chevron would go on saying whatever it said when the
      // listing was built. Debounced, and free when nothing moved.
      term.emptyDelayRef.restart();
    }
  }
  // This used to delete the branch's rows and let primeOpen notice the hole
  // and fill it. Two things came of that, and the second one took a capture
  // to see.
  //
  // The branch VANISHED for the length of a `find` and came back, which is
  // the redraw-on-every-update Buck reported: a file copied into an expanded
  // directory made the whole directory blink.
  //
  // And the list briefly got SHORTER, which is a real event with real
  // consequences: the cursor clamp (see the pane's onViewChanged) saw an
  // index past the end and pulled it back — so a file created inside a
  // branch landed the cursor on its new row, the branch emptied for the
  // re-read a moment later, and the cursor was dragged up to the directory and
  // left there once the rows came back.
  //
  // A forced read replaces the rows when the new ones arrive and not before.
  function rereadBranches(dirs) {
    const pane = term.act;
    if (!pane || !pane.treed || !dirs || dirs.length === 0) return;
    for (const p of dirs) {
      if (!pane.isOpen(p)) continue;
      pane.readKids(p, true);
    }
  }
  Process {
    id: peekWatchProc
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: (line) => peekSettle.restart()
    }
  }
  Timer {
    id: peekAim
    interval: 220
    onTriggered: {
      const r = term.currentRow();
      term.watchPeek(term.viewMode === "columns" && r && r.isDir ? r.path : "");
    }
  }
  // Coalesced exactly as the listing's own watcher is, and for the same
  // reason: one `cp` is a stream of events and one re-read answers all of it.
  Timer {
    id: peekSettle
    interval: 250
    onTriggered: term.repeek()
  }
  function watchPeek(dir) {
    if (dir === term.peekWatched) return;
    term.peekWatched = dir;
    peekWatchProc.running = false;
    if (dir === "" || !term.shown) return;
    peekWatchProc.command = Terminus.watchArgv([dir]);
    peekWatchProc.running = true;
  }
  // Something changed in the directory being previewed, so the peek we hold of it
  // is a photograph of a scene that has moved. BOTH copies go: the parsed one
  // the pane draws from, and the raw one an arrival would be seeded with — a
  // stale seed is a stale listing, which is the worse of the two.
  function repeek() {
    const d = term.peekWatched;
    if (d === "") return;
    term.forgetListing(d);
    const r = term.currentRow();
    // The one case where the pane must be redrawn with the same row in it:
    // the directory it is showing has changed underneath. Saying so is what
    // gets it past the guard in loadPreview.
    if (r && r.path === d) { term.previewShown = ""; term.loadPreview(); }
  }
  function forgetListing(dir) {
    if (term.previewCache[dir] !== undefined) {
      const c = Object.assign({}, term.previewCache);
      delete c[dir];
      term.previewCache = c;
    }
    if (term.listingText[dir] !== undefined) {
      const t = Object.assign({}, term.listingText);
      delete t[dir];
      term.listingText = t;
    }
  }
  function watch() {
    // One credit per stop that will actually produce an exit — see the
    // note on watchProc.onExited.
    if (watchProc.running) term.watchStopping = true;
    watchProc.running = false;
    term.watchArmed = "";
    // nothing to watch while hidden, and nothing to watch while showing search
    // results, which are not a directory
    if (!term.shown || term.cwd === "" || term.searchMode !== "") return;
    // ── AND EVERY BRANCH THE LIST HAS OPEN ────────────────────────────
    // cwd alone was right while the list only ever showed cwd. A tree
    // shows other directories at the same time, and those were watched by
    // nothing: copying a file into an expanded directory, or deleting one out
    // of it, left the branch showing what it held a minute ago while the
    // parent updated perfectly — which is exactly the shape of the report.
    //
    // ONE inotifywait over all of them rather than a process per branch.
    // It takes a list, the handler already coalesces the burst, and
    // openBranches names only the ones actually on screen.
    const dirs = term.watching();
    term.watchArmed = dirs.join("\n");
    watchProc.command = Terminus.watchArgv(dirs);
    watchProc.running = true;
  }
  Timer {
    id: watchAim
    interval: 150
    onTriggered: {
      if (term.shown && term.cwd !== "" && term.searchMode === ""
          && term.watching().join("\n") !== term.watchArmed)
        term.watch();
      if (term.shown && term.dual && term.otherCwd !== ""
          && term.otherWatching().join("\n") !== term.otherWatchArmed)
        term.watchOther();
      term.watchShut();
    }
  }
  function shutWatching() {
    const pane = term.act;
    if (!term.shown || !pane || !pane.treed) return [];
    const out = [];
    const v = pane.view;
    for (let i = 0; i < v.length && out.length < term.shutCap; ++i)
      if (v[i].isDir && !pane.isOpen(v[i].path)) out.push(v[i].path);
    return out;
  }
  // Re-aimed from watchAim with the other two, and asked when showing,
  // hiding, switching half or leaving the list — see shutKey.
  function watchShut() {
    const dirs = term.shutWatching();
    const key = dirs.join("\n");
    if (key === term.shutArmed && (key === "" || shutWatchProc.running)) return;
    term.shutArmed = key;
    shutWatchProc.running = false;
    if (dirs.length === 0) return;
    // ONE UNWATCHABLE PATH KILLS inotifywait OUTRIGHT, and `/` alone has
    // two (/root, /lost+found). So the list is sieved first — gone,
    // unreadable and untraversable directories are dropped — and the shell
    // then execs into inotifywait, so stopping the Process stops the
    // watcher rather than orphaning it behind a pipe.
    shutWatchProc.command = ["sh", "-c",
      'n=$#; while [ "$n" -gt 0 ]; do d=$1; shift; n=$((n-1)); '
      + 'if [ -d "$d" ] && [ -r "$d" ] && [ -x "$d" ]; then set -- "$@" "$d"; fi; done; '
      + '[ "$#" -gt 0 ] || exit 0; '
      + 'exec inotifywait -m -q -e create -e delete -e moved_to -e moved_from -- "$@"',
      "sh"].concat(dirs);
    shutWatchProc.running = true;
  }
  Process {
    id: shutWatchProc
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: (line) => term.shutHit()
    }
    // Died — a directory went between the sieve and the watch, most likely.
    // Forgotten, so the next re-aim starts it again rather than deciding
    // it is already armed. Not when a re-aim has already started the next
    // one: that one IS armed, and the old one's exit is only arriving late.
    onExited: (code) => { if (!shutWatchProc.running) term.shutArmed = ""; }
  }
  // Leading edge, then no more than once per interval: the first event is
  // answered straight away, a stream of them once a second.
  Timer {
    id: shutGate
    interval: 1000
    property bool again: false
    onTriggered: if (shutGate.again) {
      shutGate.again = false;
      term.emptyDelayRef.restart();
      shutGate.start();
    }
  }
  function shutHit() {
    if (shutGate.running) { shutGate.again = true; return; }
    term.emptyDelayRef.restart();
    shutGate.start();
  }
  // watchProc follows the active half and nothing followed the passive one,
  // so with a split open anything that happened over there — a delete made
  // in this very window while both halves showed the same directory, a copy
  // sent across with F5, a download landing — sat unseen until you clicked
  // across. The same watch, aimed at the other half's directory and the
  // branches it has open, with the same coalescing. A lost path just means
  // the next re-arm leaves the branches out; the listing itself re-reads
  // whatever the event was, so a missed parse cannot freeze it.
  Process {
    id: otherWatchProc
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: (line) => { term.noteOtherHit(line); otherSettle.restart(); }
    }
    onExited: (code) => {
      // see watchStopping
      if (term.otherWatchStopping) { term.otherWatchStopping = false; return; }
      if (term.otherWatchBare) return;
      term.otherWatchBare = true;
      term.otherRetryRef.restart();
    }
  }
  function otherWatching() {
    const pane = term.pas;
    if (!pane || pane.cwd === "") return [];
    const out = [pane.cwd];
    if (term.otherWatchBare || !pane.treed) return out;
    const prefix = pane.cwd === "/" ? "/" : pane.cwd + "/";
    for (const p of pane.liveBranches())
      if (p.indexOf(prefix) === 0) out.push(p);
    return out;
  }
  function watchOther() {
    if (otherWatchProc.running) term.otherWatchStopping = true;
    otherWatchProc.running = false;
    term.otherWatchArmed = "";
    if (!term.shown || !term.dual || term.otherCwd === "") return;
    const dirs = term.otherWatching();
    term.otherWatchArmed = dirs.join("\n");
    otherWatchProc.command = Terminus.watchArgv(dirs);
    otherWatchProc.running = true;
  }
  function noteOtherHit(line) {
    const s = String(line || "");
    const dirs = term.otherWatching();
    let best = "";
    for (let i = 0; i < dirs.length; ++i) {
      const d = dirs[i];
      if (d.length <= best.length) continue;
      if (s.indexOf(d === "/" ? "/" : d + "/") === 0) best = d;
    }
    if (best !== "") term.otherHits[best] = true;
  }
  Timer {
    id: otherSettle
    interval: 250
    onTriggered: {
      const hits = term.otherHits;
      term.otherHits = ({});
      const pane = term.pas;
      term.refreshOther();
      if (!pane || !pane.treed) return;
      for (const d in hits)
        if (d !== pane.cwd && pane.isOpen(d)) pane.readKids(d, true);
      term.emptyDelayRef.restart();
    }
  }
  // Exactly what inotifywait is watching, and the list noteWatchHit reads a
  // reported line against. One function so the two cannot drift: a
  // directory missing from here is one whose events are silently dropped.
  function watching() {
    return [term.cwd].concat(term.watchBare ? [] : term.openBranches());
  }
  // The directories the active pane has expanded, under the directory being
  // listed. Stale entries elsewhere in openDirs are not on screen and must
  // not be handed to inotifywait, which fails outright on a path that has
  // since been removed — taking the watch on cwd down with it.
  //
  // FROM THE ROWS, not from openDirs: that is now the manager's record of
  // every directory ever expanded (see mgr.tree), and it is never pruned, so it
  // can name directories that are gone. The branches actually drawn were
  // read from disk this session, so they exist.
  function openBranches() {
    const out = [];
    if (!term.act || !term.act.treed) return out;
    const prefix = term.cwd === "/" ? "/" : term.cwd + "/";
    for (const p of term.act.liveBranches())
      if (p.indexOf(prefix) === 0) out.push(p);
    return out;
  }
  // Re-read every listing on screen, as if the watcher had fired on all of
  // them — see onShownChanged.
  function catchUp() {
    if (term.cwd === "" || term.searchMode !== "") return;
    term.refresh();
    term.refreshOther();
    if (term.act && term.act.treed) term.rereadBranches(term.act.liveBranches());
    term.emptyDelayRef.restart();
  }
  // Back to one tab at home, which is what "do not restore" means when it is
  // asked of a window that is already open rather than of one being built.
  function resetSession() {
    if (term.tabs.length === 1 && term.tabs[0].cwd === Paths.home()
        && term.cwd === Paths.home() && !term.dual) return;
    term.tabs = [{ cwd: Paths.home(), sel: 0, dual: false, otherCwd: "",
                   otherSel: 0, paneSide: 0, view: term.viewMode }];
    term.tab = 0;
    term.dual = false;
    term.pas.cwd = "";
    term.act.marked = {};
    // enter, not goTo: this is where the window IS as far as history goes,
    // not somewhere it navigated to.
    term.enter(Paths.home());
  }
}
