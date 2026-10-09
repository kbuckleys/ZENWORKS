// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// One row of a directory, drawn the same way in all three places it appears.
//
// The list view wants size and date beside the name; the miller columns are
// a third of the width and want the name alone; the preview pane wants the
// name and no interaction at all. Those are the same row with two switches
// on it, not three delegates — and three delegates is how the glyph, the
// colour rules and the tick end up drifting apart.
// ── one tile of a thumbnail view ────────────────────────────────────────
// Lifted out of the grid's delegate so the SECOND PANE can be a grid too.
// Both panes draw the same tile; what differs is which state it is bound to
// and, for the inactive one, that its cursor is an outline rather than a
// fill — see EntryRow.passive, which is the same rule for rows.
// ── A PANE, AS A THING THAT OWNS ITS OWN LISTING ───────────────────────
// This window used to have one directory and a spare. The active side held
// `cwd`, `rows`, `sel` and the view mode; the other side held `otherCwd`
// and `otherRaw` and could do nothing until you stepped into it — and
// stepping into it EXCHANGED the two, so the state crossed the divider one
// way while the side it was drawn on crossed the other. On screen nothing
// moved, which was the point; underneath, every delegate in both halves was
// destroyed and rebuilt, because the item drawing a directory before the
// step was not the item drawing it after.
//
// The cost was thumbnails. The set of pictures on screen is identical
// either side of a Tab, but for an instant one pane's worth is referenced
// by nothing, and Qt frees unreferenced pixmaps the moment its cache is
// over budget — so they decode again. Around eleven of forty-eight, per
// press, at default zoom.
//
// So a pane owns its half of the window and everything in it, permanently,
// and `paneSide` decides only which of the two the keyboard is in. Tab
// moves a flag. Nothing is handed over, nothing is rebuilt, and the
// question "which item draws this directory" has one answer for as long as
// the directory is on screen.
//
// Its own file since 2026-10-08, out of TerminusWindow.qml, where it was an
// inline component. `term` is the terminus window; every place that makes
// one passes it (`term: root`).

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

QtObject {
  // the terminus window — passed in by whoever makes one. NOT `root`:
  // inside a delegate a property of that name shadowed the window's id
  // and bound to itself (2026-10-08)
  property var term: null
  id: pane

  // 0 left, 1 right. Fixed for the life of the object — a pane IS a half of
  // the window, which is the whole reason this type exists.
  property int side: 0
  readonly property bool active: term.act === pane

  property string cwd: ""
  // Raw, as the listing came back. The sort and the hidden-file setting are
  // applied below rather than baked in, so changing either rearranges both
  // panes at once instead of only the one you are standing in.
  property var raw: []

  // ── WHERE THIS PANE HAS BEEN ────────────────────────────────────────
  // On the pane, not on the window: two panes navigate independently, and
  // "back" in one is not a question about the other. Carried in and out of
  // tab state with everything else a pane is, so stepping between tabs does
  // not hand one tab's history to another.
  //
  // `trailAt` is where in it you are standing. Everything after that index
  // is the forward direction — and a fresh navigation throws it away, which
  // is what every browser does and what makes the pair of keys make sense.
  property var trail: []
  property int trailAt: -1
  // Where the cursor was in each directory this pane has left. goUp already
  // does this for one step — it arms wantSel with the directory you came out
  // of — and walking the trail is the same promise over any distance: the
  // row you were on when you left is the row you come back to.
  property var trailSel: ({})
  // The way back down — see root.crumbDeep. Here for the same reason the
  // trail is: on the window, a tab standing at ~ wore the dimmed path of
  // the tab beside it, because ~ is above everything and so it never let go.
  property string crumbDeep: ""

  property int sel: 0
  property string viewMode: "list"
  // THIS HALF'S ORDER. It was the window's: both halves sorted by
  // root.sortKey, so walking the left half into a directory that remembers
  // "newest first" re-sorted the right half too, and a click on the right
  // half's heading re-sorted the left. root.sortKey is now a window onto
  // the ACTIVE pane's pair — see onActChanged — so every verb that sorts
  // still writes the one it always wrote.
  property string sortKey: "name"
  property bool sortDesc: false
  // "usage" without the usage column is no order at all; a half that was
  // sorted that way while it was off-screen falls back to name.
  readonly property string sortBy:
    (pane.sortKey === "usage" && !term.usage) ? "name" : pane.sortKey
  // The grid opens at its smallest tiles — the most of a directory at once —
  // and zoomReset goes back here too. See root.thumbZoomDefault.
  property real zoom: term.thumbZoomDefault
  // Instant on a restore, eased when you ask — see root.zoom, which
  // carries the same guard. This is the one the grid reads, so this is
  // the one where the reflow was visible: tiles walking down from
  // three columns to six over seven frames.
  Behavior on zoom {
    enabled: term.applyDepth === 0
    NumberAnimation { duration: Zenon.normal; easing.type: Easing.OutCubic }
  }
  property string query: ""

  // ── A REORDER GLIDES ──────────────────────────────────────────────
  // A filter typed or a new order: each row or tile eases from where it
  // was to where it is now (terminus/Glide.qml — drawing only, the view's
  // own transitions stay out, see PaneList). `reflowing` is up for the
  // length of the change; `prevAt` is where each path stood, taken from
  // the model at the top of syncView, before it is touched — so a delegate
  // rebound or moved by the sync reads its old place.
  property bool reflowing: false
  property var prevAt: ({})
  // Not while terminus is putting a view back (applyDepth — arriving,
  // going back, a tab restored): that is not you reordering anything.
  function reflow() {
    if (term.applyDepth > 0) return;
    pane.reflowing = true;
    pane.reflowOff.restart();
  }
  property Timer reflowOff: Timer { interval: 450; onTriggered: pane.reflowing = false }
  // the old place of a path, or -1
  function wasAt(path) {
    const i = pane.prevAt["k:" + String(path)];
    return i === undefined ? -1 : i;
  }
  // A filter loosened (cleared, or a letter taken off): the rows it had
  // are all still there and the rest come back around them, so most of
  // the listing is new paths and yet it is a reorder — see syncView.
  // Picasso's gallery does the same: what stood glides, the rest fades in.
  property bool widening: false
  property string queryWas: ""
  onQueryChanged: {
    pane.widening = pane.queryWas !== "" && pane.query.length < pane.queryWas.length;
    pane.queryWas = pane.query;
    pane.reflow();
  }
  onSortKeyChanged: pane.reflow()
  onSortDescChanged: pane.reflow()

  // path -> true. A map rather than a list so a row can ask about itself in
  // constant time while the list is being drawn.
  property var marked: ({})
  // null, never "", is the "nothing loaded yet" sentinel: an empty
  // directory prints nothing, so "" is a perfectly real listing.
  property var lastListing: null
  // Bytes are only the same listing in the same directory: two directories
  // holding the same names print the same text.
  // The ghost trail follows you down and stays when you come back up.
  onCwdChanged: {
    // another directory is an arrival, never a reorder to glide
    pane.reflowing = false;
    pane.reflowOff.stop();
    pane.lastListing = null;
    const c = pane.cwd, d = pane.crumbDeep;
    const above = d !== "" && d !== c
      && d.indexOf(c === "/" ? "/" : c + "/") === 0;
    if (!above) pane.crumbDeep = c;
  }

  // ── the listing, arranged ────────────────────────────────────────────
  // Deliberately free of anything that changes when the keyboard moves. A
  // dependency on `active` here would re-derive both panes' arrays on every
  // Tab — the diff below would absorb it without touching a delegate, but
  // it is a full pass over the directory for a keystroke that changed
  // nothing, and on four thousand rows that is felt.
  readonly property var sorted: {
    const kept = Terminus.filterEntries(pane.raw, "", term.showHidden,
                                        term.portalGhost);
    if (term.searchMode !== "") return kept;
    if (term.usage) {
      const m = term.dirSizes;
      for (let i = 0; i < kept.length; ++i) {
        const r = kept[i];
        r.du = r.isDir ? m[r.path] : r.size;
      }
    }
    return Terminus.sortEntries(kept, pane.sortBy, pane.sortDesc,
                                term.dirsFirst, term.naturalSort,
                                term.tagMarks);
  }

  // ── THE LIST THAT DOUBLES AS A TREE ──────────────────────────────
  // Finder's list view, where a directory has a triangle and opening one
  // splices its contents in underneath, indented, without going anywhere.
  //
  // FLATTENED INTO THE SAME ARRAY, and that is the whole design. The
  // cursor, the marks, the band sweep, drag, rename and every verb in
  // this window index a flat list of rows; a real nested model would
  // have meant teaching all of them about parents. A tree that flattens
  // to the same shape teaches them nothing.
  //
  // `openDirs` is kept across navigation on purpose: walking out of a
  // directory and back in should find it as you left it, the way Finder
  // does. Stale entries for directories you are no longer looking at
  // cost a key each and are never walked.
  property var openDirs: ({})
  // path -> the rows a directory contains, as parsed. RAW, not sorted:
  // the sort is applied in the flatten below so that changing the order
  // rearranges the branches too rather than leaving them as they were
  // when they were opened.
  property var kids: ({})
  // The raw text each branch was last parsed from — see kidOut. Mutated in
  // place: nothing binds to it.
  property var kidText: ({})

  // Whether this pane's listing is one a tree can exist in — see the
  // note on `tree`. Asked in three places and it must be the same
  // question in all of them.
  readonly property bool treed:
    pane.viewMode === "list" && term.treeRealm

  function isOpen(path) { return pane.openDirs["k:" + String(path)] === true; }

  // ── REMEMBERING WHICH BRANCHES ARE OPEN ──────────────────────────
  // Written out as a plain list of paths, and read back into the map.
  // CAPPED, because openDirs is deliberately never pruned — walking out
  // of a directory and back in should find it as you left it — so over
  // enough sessions it would otherwise become a record of every branch
  // ever opened. JS keeps string keys in insertion order and setOpen
  // always appends, so the tail is the most recently opened.
  readonly property int openCap: 200

  function openList() {
    const out = [];
    for (const k in pane.openDirs) out.push(k.slice(2));
    return out.slice(-pane.openCap);
  }

  // The open branches of every realm this pane has shown. Only the one
  // on screen lives in openDirs; the rest wait here — see root.realmKey.
  property var openSets: ({})
  property string realmWas: "d"

  // A named property, not a bare child: Pane is a QtObject and has no
  // default property to put one in — the same shape Elastic uses for its
  // timers.
  readonly property Connections _realm: Connections {
    target: term
    function onRealmKeyChanged() {
      // Put the outgoing realm's away before the incoming one's is laid
      // out, so a pane that has never shown this realm starts closed
      // rather than inheriting whatever was last on screen.
      const store = Object.assign({}, pane.openSets);
      store[pane.realmWas] = pane.openList();
      pane.openSets = store;
      pane.realmWas = term.realmKey;
      if (term.realmKey === "d" && term.mgr) pane.openDirs = term.mgr.tree;
      else pane.setOpenList(store[term.realmKey] || []);
      // Rows may already be up — onRawChanged has been and gone — so the
      // branches this set names need asking for now.
      pane.primeOpen();
    }
  }

  // What the SESSION remembers, which is the directory listing's tree and
  // not whichever collection happened to be open when it was written.
  function dirOpenList() {
    return term.realmKey === "d" ? pane.openList()
                                 : (pane.openSets["d"] || []);
  }

  // ── ONE RECORD — see mgr.tree ────────────────────────────────────
  // In the directory realm the open branches are the manager's, shared by
  // every pane of every window and saved on every change. Writes go there;
  // this pane follows it back. Collections and tag pages keep their own.
  function writeOpen(next) {
    if (term.realmKey === "d" && term.mgr) term.mgr.setTree(next);
    else pane.openDirs = next;
  }
  readonly property Connections _tree: Connections {
    target: term.mgr
    function onTreeChanged() {
      if (term.realmKey !== "d" || pane.openDirs === term.mgr.tree) return;
      pane.openDirs = term.mgr.tree;
      Qt.callLater(pane.primeOpen);
    }
  }

  function setOpenList(list) {
    if (!Array.isArray(list)) return;
    const m = ({});
    for (const p of list.slice(-pane.openCap))
      if (typeof p === "string" && p !== "") m["k:" + p] = true;
    pane.openDirs = m;
    // ── AND READ, NOT JUST MARKED ────────────────────────────────
    // Setting the list only marks the branches open. If the listing
    // is already in — which, on a restore, it usually is — nothing
    // reads what they hold, and the tree drew them
    // shut until something else happened to re-list the directory:
    // "I have to re-open the window for it to remember". Read now.
    Qt.callLater(pane.primeOpen);
  }

  // ── AND FETCHING WHAT THEY CONTAIN ───────────────────────────────
  // setOpen reads a directory when YOU open it. A branch restored from
  // disk was never opened, so nothing has asked for its children — the
  // flatten would find an open directory with no rows under it and quietly
  // draw it closed.
  //
  // Walks the RAW rows rather than the flattened ones: the flatten is
  // what this is trying to fill in, so it cannot be the thing consulted.
  // Cheap and idempotent — readKids declines a directory that is
  // already read or already queued — so it is safe to call again every
  // time a branch lands, which is how the deeper ones get reached.
  function primeOpen() {
    if (!pane.treed) return;
    const walk = (rows, d) => {
      for (let i = 0; i < rows.length; ++i) {
        const r = rows[i];
        if (!r.isDir || !pane.isOpen(r.path)) continue;
        const k = pane.kids["k:" + r.path];
        if (!k) { pane.readKids(r.path); continue; }
        if (d < 8) walk(k, d + 1);
      }
    };
    walk(pane.raw, 0);
  }

  onRawChanged: pane.primeOpen()
  // ── AND WHEN THE TREE APPEARS ────────────────────────────────────
  // primeOpen does nothing outside the list, so rows that arrived while
  // this pane was a grid never had their open branches read. Switching to
  // the list then drew every one of them shut — still marked open, with
  // nothing loaded — and the first double click on one CLOSED it (it was
  // open), the second opened it, and the read that followed filled in all
  // the others at once. Primed the moment the tree is there to fill.
  onTreedChanged: if (pane.treed) pane.primeOpen()

  // ── OPENING AND CLOSING A BRANCH ─────────────────────────────────
  function setOpen(path, want) {
    if (!path) return;
    const key = "k:" + String(path);
    const was = pane.openDirs[key] === true;
    if (was === want) return;

    const next = Object.assign({}, pane.openDirs);
    if (want) next[key] = true; else delete next[key];

    // CLOSING TAKES THE CURSOR WITH IT. The rows about to leave include
    // the one you are standing on more often than not — you opened the
    // branch, walked into it and are now shutting it — and a cursor left
    // pointing at an index those rows used to occupy lands on whatever
    // slid up into it. It goes to the directory being closed, which is the
    // row you were working with.
    let land = -1;
    if (!want && pane.active) {
      const cur = pane.view[pane.sel];
      const p = String(path);
      if (cur && cur.path !== p
          && String(cur.path).indexOf(p + "/") === 0) {
        for (let i = 0; i < pane.view.length; ++i)
          if (pane.view[i].path === p) { land = i; break; }
      }
    }

    // ── HOLD THE SCROLL ─────────────────────────────────────────
    // Splicing rows into the middle moves nearly every index below the
    // branch, so syncView's diff reads it as a wholesale change — and a
    // wholesale change rewinds the view to the top before rebuilding.
    // Expanding a directory halfway down a listing would have thrown you
    // back to the first row every time.
    //
    // wantSel is exactly the escape hatch that branch already has for
    // this: armed, it skips the rewind and lands on the named row
    // instead. Pointed at the row the cursor is ALREADY on, so nothing
    // moves — clicking a triangle must not also select that row.
    if (pane.active) {
      const keep = pane.view[land >= 0 ? land : pane.sel];
      if (keep) term.wantSel = keep.path;
    }

    pane.writeOpen(next);
    // The watch list is the open branches plus cwd — see root.watch.
    // Also the moment to try the branches again after a fallback.
    if (pane.active) { term.watchBare = false; term.watch(); }
    else { term.otherWatchBare = false; term.watchOther(); }
    // ── AND IT IS READ AGAIN, NOT REMEMBERED ─────────────────
    // A closed branch is not in the watch list, so anything that
    // happened inside it while it was shut went unseen: reopening drew
    // the rows it held when you closed it. This only read a branch with
    // NO rows cached, which after the first open is never true.
    //
    // Forced rather than dropped-and-refilled, for the reason
    // rereadBranches gives: the rows it has stay up until the new ones
    // arrive, so opening a branch you have seen before does not blink.
    if (want) pane.readKids(path, true);
    if (land >= 0) { pane.sel = land; term.settleScroll(); }
    // ── THE ROW MOVED; THE CURSOR DID NOT ───────────────────────
    // Closing a branch takes its rows out from UNDER a cursor that is
    // below it, so every index past the branch shifts up by the size
    // of the branch — and the cursor kept the old one. With a small
    // branch that silently puts it on a different file; with a big
    // one the stale index falls off the end of the listing, no row is
    // current, and the cursor is simply not drawn anywhere. That is
    // the invisible cursor, and Recents is where it showed because a
    // collection's branches are large.
    //
    // NOTHING ELSE WAS GOING TO DO IT. wantSel is armed above for
    // exactly this, but the only thing that consumes it on a branch
    // is the handler for CHILDREN ARRIVING — and a collapse reads
    // nothing, runs no process and raises no such signal. Opening is
    // covered by that handler; closing had no one.
    //
    // Which is also why the triangle broke it and a double click did
    // not: onOpened puts the cursor on the row it is about to toggle
    // first, so the cursor is never below the branch. onToggled
    // deliberately does not — clicking a triangle must not select the
    // row — and that is the whole of the difference.
    else if (!want && pane.active && term.wantSel !== "") {
      // The rows are final here: a collapse is synchronous, so a path
      // that cannot be found now will not turn up in a later listing
      // and the aim must not be left armed for one to take.
      if (term.landWanted()) term.settleScroll();
      else {
        term.wantSel = "";
        pane.sel = Math.max(0, Math.min(pane.sel, pane.view.length - 1));
        term.settleScroll();
      }
    }
  }

  // ── AN OPEN DIRECTORY WITH NO CHEVRON IS NOT SHUT BY OPENING IT ─────
  // Opening an empty directory still records it as open; it simply draws
  // nothing. If something outside then fills it, the row is still marked
  // empty, so it has no chevron and looks shut, but it is open. The first
  // double click therefore CLOSED it, which re-probed it and brought the
  // chevron back, and only the second one opened it. Two double clicks
  // for one directory is the whole of Buck's report.
  //
  // Nothing is on screen to close, so there is nothing to toggle: read it
  // again, and let the probe decide the chevron once the rows are in.
  function toggleOpen(path) {
    const open = pane.isOpen(path);
    if (open && term.dirEmpty[String(path)] === true) {
      pane.readKids(path, true);
      if (pane.active) term.paneEmptyDelay.restart();
      return;
    }
    pane.setOpen(path, !open);
  }

  // Read on demand, one at a time. A queue rather than a process each,
  // because opening a run of branches with the keyboard is easy to do
  // faster than a directory can be read.
  property var kidQueue: []
  // Paths that must be read again even though rows for them are already
  // held — see rereadBranches. Mutated in place; drained by pumpKids.
  property var kidForce: ({})

  function readKids(path, force) {
    const want = String(path);
    if (force === true) pane.kidForce["k:" + want] = true;
    // primeOpen calls this for every open branch each time one lands, so
    // without this a deep tree queues the same directory once per level.
    if (pane.kidQueue.indexOf(want) >= 0) return;
    // A FORCED read still queues behind one already in flight: that read
    // was started before whatever changed, so its answer is the old one
    // and dropping the new request would keep it.
    if (kidProc.at === want && force !== true) return;
    const q = pane.kidQueue.slice();
    q.push(want);
    pane.kidQueue = q;
    pane.pumpKids();
  }

  function pumpKids() {
    // `at` still set means a read has exited but its rows are not placed
    // yet — starting the next one now would hand these rows to that name.
    if (kidProc.running || kidProc.at !== "" || pane.kidQueue.length === 0) return;
    const q = pane.kidQueue.slice();
    const next = q.shift();
    pane.kidQueue = q;
    // Already answered while it sat in the queue, or closed again before
    // its turn came — either way there is nothing to read.
    const forced = pane.kidForce["k:" + next] === true;
    if (forced) delete pane.kidForce["k:" + next];
    if ((!forced && pane.kids["k:" + next]) || !pane.isOpen(next)) {
      pane.pumpKids();
      return;
    }
    kidProc.at = next;
    kidProc.command = ["sh", "-c", Terminus.listCommand(next)];
    kidProc.running = true;
  }

  // whether a branch read is queued or running — see root.revealWhenReady
  readonly property bool kidsBusy: kidProc.running || pane.kidQueue.length > 0

  // A read that exited and never ended its stream would leave `at` armed
  // and the queue waiting for ever; this lets it go.
  property Timer kidStall: Timer {
    interval: 250
    onTriggered: if (!kidProc.running && kidProc.at !== "") {
      kidProc.at = "";
      pane.pumpKids();
    }
  }

  property Process kidProc: Process {
    id: kidProc
    property string at: ""
    // ── THE QUEUE IS PUMPED FROM HERE, NOT FROM THE COLLECTOR ───
    // onStreamFinished fires while the process is still being reaped,
    // so `running` is STILL TRUE there — and pumpKids' first line is
    // `if (kidProc.running) return`. Pumping from the collector
    // therefore did nothing at all: the first branch in the queue
    // loaded and every one behind it sat there for ever.
    //
    // That is why a restored tree showed one branch open with its rows
    // and the rest open with nothing under them — a chevron turned
    // down over an empty gap, which is exactly what it looks like.
    //
    // Exiting is the moment the process is actually finished with.
    // Clearing `at` here also covers a process that fails to start and
    // never produces a stream to finish.
    // ── AND `at` IS NOT CLEARED HERE ──────────────────────────────
    // It was, and exit and end-of-stream arrive in either order: when
    // exit came first it wiped the name of the directory being read,
    // the stream then finished with no idea whose rows it held, and they
    // were thrown away. That was the second half of "the branch below is
    // open with nothing in it" — the read happened and was discarded.
    // The stream handler clears it once the rows are placed; a process
    // that never starts still ends its stream, so nothing is left armed.
    onExited: (code) => {
      pane.pumpKids();
      kidStall.restart();
    }
    stdout: StdioCollector {
      id: kidOut
      waitForEnd: true
      onStreamFinished: {
        const dir = kidProc.at;
        kidProc.at = "";
        if (dir !== "") {
          // Raw, unsorted — the flatten sorts, so a branch follows the
          // order the listing is in rather than the order it was opened
          // in. Replaced wholesale so `tree` sees a new object.
          // THE SAME BYTES ARE THE SAME ROWS, as for the listing itself:
          // a job re-reads every open branch when it lands (see actProc),
          // and handing back an unchanged branch as a new object would
          // re-flatten the whole tree for nothing.
          const same = pane.kids["k:" + dir] !== undefined
            && pane.kidText["k:" + dir] === kidOut.text;
          pane.kidText["k:" + dir] = kidOut.text;
          if (!same) {
            const m = Object.assign({}, pane.kids);
            const fresh = Terminus.parseListing(kidOut.text, dir);
            m["k:" + dir] = fresh;
            pane.kids = m;
            // Anything this branch used to hold and no longer does takes
            // its own remembered branch with it — see dropGone. One call:
            // forgetVanished covers kids as well as openDirs and dirEmpty,
            // so pruning `m` first was the same walk done twice.
            pane.forgetVanished(dir, fresh);
          }
          // What just landed may itself hold branches that were open
          // when the session ended — see primeOpen.
          pane.primeOpen();
          // ── AND THE QUEUE IS PICKED UP AGAIN, A TURN LATER ────────
          // Exit and end-of-stream arrive in EITHER order. When exit came
          // first it pumped an empty queue; then this handler queued the
          // next level (primeOpen, just above) while `running` was still
          // true, pumpKids declined it, and nothing came back for it —
          // so a restored tree loaded one level and left the branch
          // below open with nothing in it: two double clicks to see it.
          // By the next turn the process is gone either way.
          Qt.callLater(pane.pumpKids);
          // ── AND IT MAY HOLD THE ROW SOMEBODY IS WAITING FOR ───────
          // landWanted is called when the LISTING lands, which is the
          // only place rows used to come from. A file made inside a
          // branch arrives here instead, so without this the cursor
          // never moved onto it and `a` never opened its name for
          // editing — the second half of making a file simply did not
          // happen, and wantSel stayed armed afterwards.
          // ── A CREATE THAT WAS WAITING FOR THIS ───────────────────
          // startCreate defers when the directory it is aimed at has
          // never been read: the name it picks has to avoid the names
          // already there. This is that read arriving. Cleared before
          // the call, so a create that somehow fails cannot re-fire on
          // the next listing of the same directory.
          const pm = term.pendingMake;
          if (pm && pm.dir === dir) {
            term.pendingMake = null;
            term.paneMakeGuard.stop();
            // Only where it was asked for, and only while that place
            // is still on screen — see pendingMake.
            if (pm.cwd === term.cwd && pane.active && pane.isOpen(dir))
              term.makeIn(pm.kind, dir);
          }
          if (pane.active && term.wantSel !== "" && term.landWanted())
            Qt.callLater(term.settleScroll);
          // a chevron's saved view comes back even when there was no
          // cursor to land — see root.scrollHold
          else if (term.scrollHold) Qt.callLater(term.settleScroll);
        }
        // NOT pumped here — see onExited. `running` is still true on
        // this signal, so the pump would decline and the queue stop.
      }
    }
  }

  // ── A PATH IS NOT UNIQUE OVER TIME ───────────────────────────────
  // kids, openDirs and dirEmpty are all keyed by path, and nothing ever
  // took an entry out because the thing it was about had gone. Delete a
  // directory and make another with the same name and everything remembered
  // about the first one applies itself to the second: a directory created
  // empty came up already expanded, with the subtree the deleted one had
  // spliced underneath it — rows for files that do not exist, with a dash
  // where their size should be. Buck's capture shows exactly that.
  //
  // A listing is a complete statement of what a directory holds right
  // now, so it is also the moment to forget what it does not. Keyed off
  // the top segment under `dir`, which takes a vanished child and
  // everything remembered beneath it in one pass.
  //
  // SAFE AGAINST THE HIDDEN-FILE TOGGLE: `raw` and the kid listings are
  // both `find` with no name filter, so a dotted directory is in the rows
  // whether or not the view is currently showing it. Pruning against a
  // FILTERED list would forget every open branch starting with a dot.
  function dropGone(map, dir, rows) {
    if (!rows || !map) return false;
    const here = ({});
    for (let i = 0; i < rows.length; ++i) here[rows[i].path] = true;
    const base = (dir === "/" ? "" : dir) + "/";
    let went = false;
    for (const k in map) {
      const p = k.slice(2);
      if (p.indexOf(base) !== 0) continue;
      const rest = p.slice(base.length);
      const cut = rest.indexOf("/");
      if (here[base + (cut < 0 ? rest : rest.slice(0, cut))]) continue;
      delete map[k];
      went = true;
    }
    return went;
  }

  // The same sweep over every path-keyed cache, for a listing that has
  // just landed. Each map is only reassigned when something actually
  // went, so an ordinary refresh costs one walk and no binding churn.
  function forgetVanished(dir, rows) {
    if (!pane.treed || !rows) return;
    // ── ONLY A LISTING THAT IS OF THIS DIRECTORY MAY PRUNE IT ────────
    // A listing that landed after the window had moved — the session
    // restore finishing under a navigation, say — was pruned against the
    // wrong directory, and everything it did not mention was "gone":
    // that is how three expanded directories under Projects vanished from
    // the saved tree between one start and the next. Rows carry their
    // real paths (find's %p), so a listing that is not of `dir` is
    // recognisable, and it is not allowed to delete anything.
    const base = dir === "/" ? "/" : dir + "/";
    for (let i = 0; i < rows.length; ++i) {
      const p = String(rows[i].path || "");
      if (p.indexOf(base) !== 0 || p.slice(base.length).indexOf("/") >= 0) return;
    }
    const nk = Object.assign({}, pane.kids);
    if (pane.dropGone(nk, dir, rows)) pane.kids = nk;
    // The open branches are NOT pruned: they are the manager's record,
    // and a directory that has gone simply never matches a row. Pruning
    // them against listings is how expands were being lost.
    // Keyed by bare path rather than "k:", and mutated in place — the
    // delegate reads it through a pulse, not a binding.
    const ne = ({});
    for (const q in term.dirEmpty) ne["k:" + q] = term.dirEmpty[q];
    if (pane.dropGone(ne, dir, rows)) {
      const back = ({});
      for (const k in ne) back[k.slice(2)] = ne[k];
      term.dirEmpty = back;
    }
  }

  // ── THE BRANCHES ACTUALLY ON SCREEN ──────────────────────────────
  // Not openDirs, which deliberately keeps every directory ever opened so
  // that walking back into one finds it as you left it — handing that
  // whole set to a re-read would spawn a find per directory you have
  // touched all session. The flattened rows are the ones being drawn,
  // and they are the only ones whose staleness anybody can see.
  function liveBranches() {
    const out = [];
    if (!pane.treed) return out;
    const v = pane.tree;
    for (let i = 0; i < v.length; ++i)
      if (v[i].isDir && pane.isOpen(v[i].path)) out.push(v[i].path);
    return out;
  }

  // ── THE FLATTEN, ROWS AND GUIDES IN ONE WALK ─────────────────────
  // The rows and the tree guides come out together because the guide is
  // a fact only the walk knows: "at each level above this row, is that
  // branch still going?" is answerable while standing at the row and
  // nowhere else. Working it out afterwards would mean sorting every
  // open branch a second time.
  //
  // `anc` is a bitmask, bit j set when the row on the way here at DEPTH j
  // has a sibling still to come. For a row at depth d that is everything
  // needed to draw it: a full-height vertical in column k for every set
  // bit k+1 below d-1, and at column d-1 the elbow — always drawn down to
  // the row's middle, carried on to the bottom only when bit d says
  // another sibling follows.
  //
  // Stored path-keyed rather than written onto the row, for the reason
  // depthOf gives: a row object is shared with the caches and with the
  // other pane, and one listing's layout must not leak into another's.
  readonly property var flat: {
    const base = pane.sorted;
    // A branch only means anything in the list. Columns view is already a
    // tree by construction, a grid has nothing to indent, and find and
    // grep are questions rather than directories — see root.treeRealm.
    if (!pane.treed) return { rows: base, guide: null, depth: null };
    let any = false;
    for (const k in pane.openDirs) { any = true; break; }
    if (!any) return { rows: base, guide: null, depth: null };

    const out = [];
    const lvl = [];
    const g = ({});
    // ── DEPTH COMES FROM HERE, NOT FROM THE PATH ─────────────────
    // depthOf used to count separators between the row and cwd, which is
    // the right answer only when every row IS in cwd. A collection's
    // rows come from all over, so that reading indented every result by
    // how deep it happened to live on disk. The walk knows the real
    // answer — how many branches it opened to get here — and it is the
    // same number in a directory listing, so there is one rule now
    // rather than two.
    const dp = ({});
    // Paths reached by opening a branch, as opposed to being in the
    // listing to begin with. Only a collection can have both.
    const under = ({});

    const walk = (rows, d, anc) => {
      const n = rows.length;
      for (let i = 0; i < n; ++i) {
        const r = rows[i];
        const mine = (i === n - 1) ? anc : (anc | (1 << d));
        out.push(r);
        lvl.push(d);
        // Top-level rows have no column to the left of them to be joined
        // to, so a flat listing is drawn exactly as it was.
        if (d > 0) {
          g["k:" + r.path] = mine;
          dp["k:" + r.path] = d;
          under["k:" + r.path] = true;
        }
        if (d >= 8) continue;          // a guard, not a feature
        if (!r.isDir || !pane.isOpen(r.path)) continue;
        const raw = pane.kids["k:" + r.path];
        if (!raw) continue;            // still being read
        const kept = Terminus.filterEntries(raw, "", term.showHidden,
                                            term.portalGhost);
        walk(term.enrich(Terminus.sortEntries(
               kept, pane.sortBy, pane.sortDesc, term.dirsFirst,
               term.naturalSort, term.tagMarks)), d + 1, mine);
      }
    };
    walk(base, 0, 0);

    // ── A PATH CAN BE IN THE LIST TWICE ──────────────────────────
    // Only in a collection, and it is not a corner case: Recents can
    // easily hold both ~/.config and ~/.config/quickshell. Open the
    // first and the second is drawn under it AND still sitting at the
    // top level, the same file in two places, each with its own idea of
    // how deep it is.
    //
    // The nested one wins, because it is the one carrying context. A
    // directory listing cannot produce this — its rows are all siblings
    // in cwd and everything spliced in is strictly deeper — so the pass
    // is skipped there rather than run to find nothing.
    if (term.searchMode === "")
      return { rows: out, guide: g, depth: dp };
    const once = [];
    for (let i = 0; i < out.length; ++i)
      if (!(lvl[i] === 0 && under["k:" + out[i].path] === true))
        once.push(out[i]);
    return { rows: once, guide: g, depth: dp };
  }

  readonly property var tree: pane.flat.rows

  // -1 for a row with nothing to draw, which is every row in a flat
  // listing and every top-level row in a tree.
  function guideOf(path) {
    const g = pane.flat.guide;
    if (!g) return -1;
    const m = g["k:" + String(path)];
    return m === undefined ? -1 : m;
  }

  // HOW DEEP A ROW SITS. Read off the flatten, which counted the
  // branches it opened to get there, rather than measured off the path.
  //
  // It used to count separators between the row and cwd. That is the
  // right answer only when every row IS in cwd, and it is why a tree was
  // switched off in a collection entirely: those rows come from all over,
  // so Recents indented every result by how deep it happened to live on
  // disk — lua files under .config/hypr/lua sat three levels in, under
  // nothing. The walk's own count is right on both kinds of page.
  //
  // A SIDE TABLE, not a field on the row. The objection to stamping it
  // has not changed: a row object is shared with the caches and with the
  // other pane, and one listing's layout must not leak into another's.
  // Absent means top level, which is also the answer for every row when
  // nothing is expanded.
  function depthOf(path) {
    if (!pane.treed) return 0;
    const m = pane.flat.depth;
    if (!m) return 0;
    const d = m["k:" + String(path)];
    return d === undefined ? 0 : d;
  }

  readonly property var view: Terminus.filterQuery(pane.tree, pane.query)


  // The model the views are TOLD ABOUT rather than handed. One role, the
  // path: identity only. Everything a row draws with is looked up from
  // `viewIndex` by that path, so a file whose size or mtime changed
  // re-evaluates one binding in its delegate instead of being destroyed and
  // built again.
  readonly property ListModel vm: ListModel {}

  // path -> row, rebuilt with the listing. NOT a binding: a binding is
  // evaluated when it is first read, and the model is synced before
  // anything reads this — so a delegate created for a path that had only
  // just been appended would look it up as the map was BEFORE the listing
  // changed, and get nothing.
  property var viewIndex: ({})


  function rowFor(path) {
    return pane.viewIndex["k:" + String(path)] || null;
  }

  // ── THE HEADING THIS ROW CARRIES, OR "" ──────────────────────────
  // A row draws the heading for its band only when the row ABOVE it is in
  // a different band, which is what makes one heading appear per run
  // rather than one per row.
  //
  // Asked of the delegate rather than pushed into the model on purpose:
  // the model here is identity only — one `path` role, everything else
  // looked up — and a `group` role would have to be diffed and kept in
  // step by syncView for a string that is derived from data syncView
  // already has. This reads pane.view, so it re-evaluates when the
  // listing does, and only for the delegates that actually exist.
  // ── WHERE A ROW ACTUALLY SITS ────────────────────────────────────
  // The cursor bar is placed by arithmetic rather than by asking the
  // view — see SelectBar, which has good reasons — and that arithmetic
  // was `index * rowH`. True while every cell is exactly a row tall,
  // and no longer true once a cell can carry a heading: with headings
  // on, the bar drifted a heading's height further from the row it was
  // marking for every band above it.
  //
  // The fast path is the old expression, so nothing changes when the
  // headings are off, which is nearly always.
  function rowTop(i) {
    const h = term.rowH;
    if (!term.grouped || !pane.treed) return i * h;
    const v = pane.view;
    const top = Math.min(i, v.length);
    let y = 0;
    for (let k = 0; k < top; ++k)
      y += h + (pane.groupHeadAt(k) !== "" ? term.groupHeadH : 0);
    // Below its own heading, not above it.
    return y + (pane.groupHeadAt(i) !== "" ? term.groupHeadH : 0);
  }

  function groupHeadAt(i) {
    if (!term.grouped) return "";
    const v = pane.view;
    if (i < 0 || i >= v.length) return "";
    const here = Terminus.groupLabel(v[i], pane.sortBy,
                                     term.tagMarks, term.nowSec);
    if (here === "" || i === 0) return here;
    const above = Terminus.groupLabel(v[i - 1], pane.sortBy,
                                      term.tagMarks, term.nowSec);
    return above === here ? "" : here;
  }

  onViewChanged: {
    // ── THE CURSOR CANNOT OUTLIVE THE ROW IT IS ON ────────────────
    // sel is an INDEX. The listing handler clamped it for the one case
    // it knew about — a directory re-read that came back shorter — and
    // nothing else did, although a tree has several other ways to lose
    // rows: a branch re-read after a delete, a directory collapsed, a
    // filter typed, and a file made inside a branch then cancelled.
    //
    // Left past the end the cursor draws as a highlight bar over empty
    // space with no name in it, on a row that cannot be opened, renamed
    // or moved off with anything but an arrow key. The blank band under
    // `test` in Buck's capture is exactly this: rows=1, sel=1.
    //
    // FIRST in this handler, so everything below it — the group bands,
    // the index, the diff, the preview — is working from a cursor that
    // is actually on a row.
    if (pane.sel >= pane.view.length)
      pane.sel = Math.max(0, pane.view.length - 1);
    // The date bands are relative to now, and "now" should be the moment
    // the listing was read — see root.nowSec.
    term.nowSec = Math.floor(Date.now() / 1000);
    const m = ({});
    const v = pane.view;
    for (let i = 0; i < v.length; ++i) m["k:" + v[i].path] = v[i];
    pane.viewIndex = m;
    pane.syncView();
    // Which directories have anything in them is a question about the
    // rows on screen, so it is asked again when they change — debounced,
    // because expanding a branch changes them twice in quick succession.
    if (pane.active) term.paneEmptyDelay.restart();
    // and so is which of them are being watched — see watchAim
    term.paneWatchAim.restart();
    // And which of them still need measuring — see usageDelay.
    if (pane.active && term.usage) term.paneUsageDelay.restart();
    // The rows under the cursor are new ones, so what the preview is OF has
    // changed even when the cursor itself has not moved.
    if (pane.active && pane.viewMode === "columns") term.refreshPreview();
  }

  // The diff. Removals first so the forward walk never has to step over a
  // row that is on its way out, then one pass placing what is left.
  function syncView() {
    const next = pane.view;
    const m = pane.vm;

    // A WHOLESALE CHANGE IS CHEAPER TO REBUILD than to walk into place, and
    // there are two of them: arriving in a different directory, and
    // re-sorting the one you are in. Both move nearly every row, and the
    // walk below is quadratic when nearly every row has moved.
    // Nothing to nothing. The passive pane hits this on every navigation
    // in the other half — its model is empty and its listing is empty —
    // and the branch below would rewind two views and walk a clear for it.
    if (m.count === 0 && next.length === 0) return;

    // where everything stood, for the glide — only for a reorder, and
    // only of the SAME rows: a sync that is mostly new paths is a listing
    // arriving (another directory, a tree's branches loading in after
    // going back), and gliding those replayed the arrival as motion.
    if (pane.reflowing) {
      const at = ({});
      for (let i = 0; i < m.count; ++i) at["k:" + m.get(i).path] = i;
      let kept = 0;
      for (let i = 0; i < next.length; ++i) if (at["k:" + next[i].path] !== undefined) ++kept;
      // loosening a filter keeps every row it had, however many come back
      const reorder = kept >= next.length * 0.5
        || (pane.widening && m.count > 0 && kept >= m.count * 0.5);
      if (next.length === 0 || !reorder) {
        pane.reflowing = false;
        pane.reflowOff.stop();
      } else pane.prevAt = at;
    }

    const n = Math.min(next.length, m.count);
    let same = 0;
    for (let i = 0; i < n; ++i)
      if (m.get(i).path === next[i].path) ++same;

    // ── THE WHOLESALE TEST IS THE ORIGINAL ONE ──────────────────────
    // A pass here tried to spot an insertion — matching from both ends
    // and sending anything contiguous down the incremental walk — so
    // that the view would emit real inserts for its add transitions to
    // animate. The transitions are gone (see the delegate), and with
    // them the only reason to prefer that path.
    //
    // It is not a neutral preference either: the walk does real removes
    // and inserts, which churns the reuse pool, and a collection
    // filling in chunk by chunk looked exactly like an insertion. The
    // set() path below rebinds delegates that are already standing
    // there and never hands one back.
    if (m.count === 0 || same < n * 0.5) {
      // BEFORE the rows change, never after — see rewindPane.
      //
      // AND NOT AT ALL WHEN A ROW IS ALREADY SPOKEN FOR. Rewinding puts the
      // view at the top; positionSel then moves it to the row that was
      // asked for. Two scroll positions in two frames, and walking back UP
      // a tree hits it every time — the cursor is headed for the directory
      // you just came out of, which is usually below the fold, so the
      // column snapped to the top and then jumped down it. That is most of
      // what "it redraws a list it had already drawn" looks like: not the
      // rows being rebuilt, the view being scrolled twice.
      //
      // `wantSel` is read rather than landWanted() called: that one is not
      // a predicate — it consumes the request and moves the cursor.
      let spokenFor = false;
      if (pane.active && term.wantSel !== "") {
        for (let i = 0; i < next.length; ++i)
          if (next[i].path === term.wantSel) { spokenFor = true; break; }
      }
      // ── ALWAYS, AND THAT IS THE FIX ─────────────────────────────
      // Skipping this when a row is spoken for is what stranded the
      // view. MEASURED: scrolling on its own never moves originY —
      // twenty page-downs through 481 rows, not one change — but
      // REMOVING rows from under a scrolled view does, and it does not
      // move back. The origin then belongs to rows that are gone, the
      // next directory inherits it, and the grid draws an empty region
      // of itself.
      //
      // Spoken for is precisely the case that skipped it: going back
      // out of a directory arms wantSel with the directory you came from.
      // So the one path that strands the origin was the one path with
      // nothing to correct it.
      //
      // The cost the old guard was avoiding is a scroll to the top and
      // then a jump to the cursor. That is a frame, and it is only
      // visible when the target is below the fold; a grid that
      // intermittently shows nothing at all is not a trade worth
      // keeping for it.
      term.rewindPane(pane.side);
      // AND THE CURSOR RE-SEATS RATHER THAN TRAVELS. The rewind puts
      // the view at the top and the cursor is then placed on a row
      // that may be well down it — eased, that is the box sliding
      // across the whole grid, which is worse than the jump it is
      // smoothing. Measured at four frames of travel from the first
      // row to the thirtieth. thawPulse is the existing way to say
      // "you are not moving, you are being put somewhere"; SelectBar
      // and SelectCell both answer it.
      term.thawPulse++;
      // REPLACED IN PLACE, not cleared and refilled.
      //
      // `clear()` destroys every delegate and leaves the view empty for a
      // frame; the rows then arrive one append at a time, each its own
      // model change. Walking back UP a tree is where that shows, because
      // the directory landing in this column was on screen a moment ago in
      // the one beside it: the column blanks and redraws a list you were
      // already looking at.
      //
      // `set` rebinds the delegate that is already standing there. Same
      // count of rows either way, and none of them stop existing — which
      // also means reuseItems never has to hand anything back.
      const keep = Math.min(m.count, next.length);
      for (let i = 0; i < keep; ++i) m.set(i, { path: next[i].path });
      for (let i = keep; i < next.length; ++i) m.append({ path: next[i].path });
      if (m.count > next.length) m.remove(next.length, m.count - next.length);
      return;
    }

    const want = ({});
    for (let i = 0; i < next.length; ++i) want["k:" + next[i].path] = true;
    for (let i = m.count - 1; i >= 0; --i)
      if (want["k:" + m.get(i).path] !== true) m.remove(i);

    for (let i = 0; i < next.length; ++i) {
      const p = next[i].path;
      if (i < m.count && m.get(i).path === p) continue;
      let at = -1;
      for (let j = i + 1; j < m.count; ++j)
        if (m.get(j).path === p) { at = j; break; }
      if (at >= 0) m.move(at, i, 1);
      else m.insert(i, { path: p });
    }
    while (m.count > next.length) m.remove(m.count - 1);
  }
}
