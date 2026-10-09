// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// TERMINUS — the file manager. God of boundaries, and of the stones that mark
// them: a directory is a boundary, a path is a line drawn between two of them,
// and the divider down the middle of a split view is the stone itself.
//
// It was called janus while it had one pane and two faces to look at it with.
// It has two panes now, so the boundary is the point.
//
// A FloatingWindow, NOT a PanelWindow. Every other surface in this shell is
// layer-shell: it floats above the desktop, hyprland cannot tile it, and it
// owns the keyboard through a focus grab until it closes. That is right for a
// launcher you use for four seconds and wrong for a window you work in — so
// this one is an ordinary xdg-toplevel. Hyprland tiles it, floats it, moves it
// between workspaces and applies window rules to it exactly as it would to a
// terminal, because from the compositor's side there is nothing to tell them
// apart. It carries a title so a rule can find it:
//
//     windowrulev2 = float, title:^(terminus)$
//
// Consequences of not being a layer, all deliberate: no morph into the pill,
// no HyprlandFocusGrab, no edgeLift, and no entry in shell.qml's height
// switch. It opens, it sits where the compositor puts it, and it closes.

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

FloatingWindow {
  id: root

  // A DIALOG IS NOT THE FILE MANAGER, and the window rules say so:
  //
  //     windowrulev2 = float, title:^(terminus)$          1000x1000
  //     windowrulev2 = float, title:^(terminus-picker)$   1000x450
  //
  // Both windows answered to "terminus", so the picker took the file manager's
  // rule and came up square. It has its own name whenever a portal request is
  // what put it on screen — which is set before `shown`, so the title is
  // already right when the surface is mapped and the rule is applied.
  title: root.picking ? "terminus-picker" : "terminus"
  // The manager that made this window, so a window can ask for another one
  // without knowing how they are kept.
  property var mgr: null
  property int winId: 0

  // The manager reaches in through these rather than through ids. An id is
  // private to the document that declares it — `w.content` from outside is
  // undefined, and reading `.activeFocus` off undefined is what made every
  // ipc call that touched focus return nothing at all.
  function takeFocus() { content.forceActiveFocus(); }
  // Ask for the keyboard and keep asking. The right entry point for anything
  // that has just made this window visible: a bare forceActiveFocus() on that
  // frame is dropped, because the surface has not been mapped yet.
  function claimFocus() { portal.focusClaim.restart(); }

  // The context menu, reached through the root object.
  //
  // An INLINE COMPONENT cannot see the ids of the document that declares it —
  // only the root object, which is why everything in here goes through `root`.
  // EntryRow called `menu.openAt` directly, so right-clicking a row in list or
  // columns view threw ReferenceError and no menu ever came up; the grid's own
  // tiles are written at document scope, so the same gesture worked there and
  // the two halves disagreed for no visible reason.
  //
  // The bookmark sidebar had the identical bug against `bookmarkFile`, which
  // is what made removed bookmarks come back. One wrapper per id that a
  // delegate needs, and the trap is closed.
  function openMenuAt(item, mouse) { menuPop.menu.openAt(item, mouse); }

  // ── the menu key ──────────────────────────────────────────────────────
  // The keyboard's own way of asking what the right button asks, about the row
  // the CURSOR is on — which is already the row the menu acts on. `menu.target`
  // is `root.currentRow()`, never a hit test against the pointer; right-click
  // only looks like it is about the row under the mouse because clickRow()
  // moves the cursor there first. So this needs no target plumbing at all,
  // only somewhere to put the card.
  //
  // The row has to be REALISED before the view will hand back its delegate, so
  // the cursor is scrolled into view first and the placing waits a tick — the
  // same shape as positionSel's other callers.
  function openMenuAtCursor() {
    // the keyboard's menu is about the cursor, never a row still held
    root.heldRow = null;
    // An empty directory has no row to ask about, so ask about the directory
    // instead: the row branch of the menu returns nothing without a target,
    // and an empty card is worse than the one that has something in it.
    if (root.view.length === 0 || !root.currentRow()) {
      menuPop.menu.openHere(content, { x: content.width / 2, y: content.height / 3 });
      return;
    }
    root.positionSel();
    Qt.callLater(root._placeMenuAtCursor);
  }

  function _placeMenuAtCursor() {
    const v = root.viewMode === "grid" ? root.actGrid
            : root.viewMode === "columns" ? root.midCol.view : root.actList;
    const it = v ? v.itemAtIndex(root.sel) : null;
    // From the row's bottom-left, so the card drops out of the row the way a
    // menu drops out of the thing it belongs to. A row near the bottom needs
    // no special handling here: the card is on a popup surface now, and the
    // compositor flips it above the pointer when there is no room below.
    if (it) menuPop.menu.openAt(it, { x: 0, y: it.height });
    // A row the view still has not built — it can refuse even after
    // positionSel if the listing changed underneath. The menu is about the
    // cursor either way, so it opens against the view rather than not at all.
    else if (v) menuPop.menu.openAt(v, { x: 0, y: 0 });
  }
  function setSaveName(n) { chrome.saveField.text = n; root.saveAimed = false; }

  // Zenon.layerBg's colour at Zenon.layerBg's alpha, until the settings panel
  // says otherwise — see winAlpha.
  //
  // NOT PAINTED BY THE WINDOW ANY MORE (2026-10-09): the surface is clear and
  // `content` lays the ground everywhere but the tab strip, whose tabs paint
  // their own — so an inactive tab can be thinner glass than the rest of the
  // window, which no amount of painting OVER one ground could do.
  color: root.ground(0)
  function ground(a) { return Qt.rgba(Zenon.layerBg.r, Zenon.layerBg.g, Zenon.layerBg.b, a); }
  // an inactive tab's glass, against the window's own
  // (0.4 went to a dark slab over a dark background, the label lost in it).
  // A dark theme tints it navy as well — see Zenon.tabAway/tabAwayInk.
  readonly property real tabAwayAlpha: Zenon.tabAway(root.winAlpha)
  minimumSize: Qt.size(560, 320)
  // An explicit size, because nothing else supplies one. Every item inside is
  // anchored to its parent, so no implicit size propagates up from the content
  // and the surface is created 0x0 — which a compositor is free to simply not
  // show. Tiled, hyprland overrides both of these immediately; floating, they
  // are the size it opens at.
  implicitWidth: 1100
  implicitHeight: 680

  // ── THE SIZE YOU LEFT IT AT ───────────────────────────────────────────
  // The two above are the size a window is BORN at, and they were the size
  // it was born at every single time: resize the window, close it, open it
  // again and you are back to 1100x680. Every other thing about how this
  // window is set up is remembered — which view, how zoomed, how wide the
  // sidebar — and its actual dimensions were the one that was not.
  //
  // STORAGE, NOT A BINDING. `implicitWidth: root.winW` with `winW` following
  // `width` is a circle: the window's size feeds the size it asks to be.
  // Even where that settles it rewrites the value every step, which is the
  // shape the thumbnail zoom got caught in. So these are written by hand, in
  // one direction each — noteSize reads the window, loadViewPrefs writes the
  // implicit size once, before the surface exists.
  //
  // Seeded with the defaults above rather than with 0, so a window that is
  // never resized writes back the size it has instead of writing a zero that
  // the loader would have to reject.
  property int winW: 1100
  property int winH: 680
  // The dialog's own, in a slot of its own for the reason pickerView has
  // one: a save dialog is a place with its own habits, and resizing it must
  // not resize your file manager. 0 means never set — a first dialog is
  // born at the file manager's size, as it always was.
  property int pickerW: 0
  property int pickerH: 0

  onWidthChanged: { root.noteSize(); root.noteSideWidth(); }
  onHeightChanged: root.noteSize()

  function noteSize() {
    // A PICKER IS A DIALOG and its size is the portal's business, not a
    // preference — the same exclusion viewSave makes for everything else.
    // Nothing to learn from a window that is not on screen: an unmapped
    // surface reports whatever it was last given, including 0.
    if (!root.visible || root.width < 200 || root.height < 200) return;
    // A PICKER remembers too, but into its own slot and through its own
    // merged write — viewSave declines to write anything for a dialog.
    if (root.isPicker) {
      if (root.width === root.pickerW && root.height === root.pickerH) return;
      root.pickerW = root.width;
      root.pickerH = root.height;
      opening.pickerSave.restart();
      return;
    }
    if (root.picking) return;
    if (root.width === root.winW && root.height === root.winH) return;
    root.winW = root.width;
    root.winH = root.height;
    // Through the same debounce the rest of the preferences use, which is
    // what keeps a drag-resize to one write rather than one per frame.
    opening.viewSave.restart();
  }

  // `shown` and `visible` are kept in step BOTH WAYS, and neither is a binding.
  //
  // Two bugs live here, and the second one hid behind the first.
  //
  // Writing `visible` directly did not stick: `visible: false` on the window is
  // a constant binding, and an imperative write races whatever re-evaluates it,
  // so toggle() answered "closed" having just set it true.
  //
  // Binding it the other way — `visible: root.shown` — fixed opening but broke
  // reopening. When the COMPOSITOR closes the window it writes `visible` itself,
  // and an imperative write to a bound property destroys the binding. `shown`
  // was then stuck true against a window that was gone, so the next `shown =
  // true` changed nothing at all and no surface was ever created. That is why
  // the portal accepted a request, reported picking=true, and showed nothing.
  //
  // Handlers in both directions, with no binding to break: setting `shown`
  // shows the window, and the window being closed by anything else puts `shown`
  // back. Neither can loop, because QML does not re-emit a change that did not
  // change anything.
  property bool shown: false
  onVisibleChanged: {
    if (root.shown !== root.visible) root.shown = root.visible;
    if (root.visible) portal.focusClaim.restart();
  }

  // ── where we are ────────────────────────────────────────────────────────
  // THE ACTIVE PANE, READ THROUGH. Every one of these used to be storage and
  // is now a window onto whichever half the keyboard is in, so the four
  // hundred places in this file that ask "where are we" go on asking exactly
  // as they did — and a Tab changes the answer without moving a byte.
  //
  // Read-only on purpose: `root.cwd = x` would silently break the binding and
  // leave the pane holding something else. The writes all go to root.act.
  readonly property string cwd: root.act.cwd
  readonly property var rows: root.act.raw
  readonly property string query: root.act.query
  property bool showHidden: true
  property string sortKey: "name"

  // ── ARRANGING: HEADINGS OVER THE SORT YOU ALREADY HAVE ───────────────
  // Finder offers "Arrange by" as a second axis beside the sort, and it is
  // not one — see groupLabel in terminus.js. This is a single toggle: put
  // headings on the bands the CURRENT sort falls into. Sorted by date you
  // get Today / Yesterday / Previous 7 days; by kind, Images / Documents;
  // by tag, the tag names. Change the sort and the headings follow.
  //
  // List view only. A GridView lays out fixed cells and has no notion of a
  // row to hang a heading off, and the columns view is three narrow lists
  // where a heading costs more width than it is worth.
  property bool grouped: false
  readonly property int groupHeadH: Math.round(22 * root.zoom)

  // How far one level of the list's tree is indented, and the room a
  // disclosure triangle takes. Scaled with the zoom like every other
  // measurement in a row.
  //
  // THE STEP IS NOT THE MARKER'S WIDTH. They were both 14, which read as
  // barely an indent at all once the guide lines went in — a level looked
  // like a nudge rather than a rank. The two are separate measurements and
  // only the step wants doubling: the marker is still a 14px glyph.
  //
  // Everything in the guides is expressed against these, so nothing else
  // moves. A column's line sits at k * treeStep + treeArrowW / 2, which is
  // the middle of where a marker at that depth would be, and the arm is
  // whatever is left of the step — so widening the step lengthens the arms
  // and leaves the corners, the markers and the icons where they belong.
  readonly property int treeStep: Math.round(28 * root.zoom)
  readonly property int treeArrowW: Math.round(14 * root.zoom)

  // ONE MOMENT FOR THE WHOLE LISTING. The date bands are worked out against
  // this rather than against Date.now() per row: a listing read across
  // midnight would otherwise file two rows a second apart under different
  // headings, and the heading would appear halfway down a run of files that
  // all arrived together.
  property real nowSec: Math.floor(Date.now() / 1000)
  property bool sortDesc: false
  readonly property int sel: root.act.sel

  // Whether the menu on screen is the one the hamburger opened, so the
  // button can light up while its own card is up and not while a row's is.
  property bool burgerOn: false

  // path -> true. A map rather than a list so a row can ask about itself in
  // constant time while the list is being drawn.
  readonly property var marked: root.act.marked
  // what y or d put down, waiting for a p somewhere else
  // What y or d put down, waiting for a p somewhere else — and "somewhere
  // else" now includes ANOTHER WINDOW. The buffer belongs to the manager, so
  // copying in one terminus and pasting in another is the same gesture it always
  // was. A binding rather than a copy, so both windows' status lines and menus
  // notice the moment either of them yanks. Written through setPending.
  readonly property var pending: root.mgr ? root.mgr.clipboard : null

  // The rows a pending CUT will take away, as a set.
  //
  // A copy leaves everything where it is, so it says nothing about the rows it
  // came from; a cut is a promise to remove them, and until it is paid the
  // listing was showing them exactly as solid as the files that are staying.
  // EntryRow has carried an unused `dim` for exactly this since it was
  // written.
  readonly property var cutSet: {
    const m = ({});
    const p = root.pending;
    if (p && p.op === "move")
      for (let i = 0; i < p.paths.length; ++i) m[p.paths[i]] = true;
    return m;
  }
  // ── A CUT PASTED SOMEWHERE ELSE ───────────────────────────────────────
  // Nautilus moves a Terminus cut itself, and nothing tells Terminus: the
  // rows went, but the cut stayed pending, and a `p` here would have tried to
  // move files that are no longer anywhere it knew. So when a fresh listing
  // of the directory the cut came from holds none of its items, the cut has
  // been taken — dropped, and the clipboard's copy of it marked spent (see
  // spentClip). Only when ALL of them are gone: one missing item is a file
  // deleted, not a paste.
  function cutTaken(dir, rows) {
    const p = root.pending;
    if (!p || p.op !== "move" || !root.mgr) return;
    const here = p.paths.filter((x) => Terminus.dirname(x) === dir);
    if (here.length === 0) return;
    const present = {};
    for (let i = 0; i < rows.length; ++i) present[rows[i].path] = true;
    if (here.some((x) => present[x])) return;
    root.mgr.spentClip = p.paths.slice();
    // not setPending: that spends the marks, and nothing was done here
    root.mgr.clipboard = null;
  }

  // ── AN ACTION SPENDS THE SELECTION ────────────────────────────────────
  // Marks are a sentence being built — these three, then a verb — and the
  // verb finishes the sentence. Left ticked afterwards they were silently
  // inherited by the NEXT verb: three files deleted, then some unrelated
  // key, and it happened to the same three. enter() has always cleared them
  // on the way out of a directory for exactly this reason; nothing did it
  // on the way through an action.
  //
  // AT THE CHOKEPOINTS, NOT AT EACH VERB. A dozen functions read acting(),
  // and a handful of them already remembered to clear afterwards — which is
  // the shape of a rule that is going to be forgotten by the next verb
  // somebody writes. Everything that actually DOES something goes through
  // run(), startJob() or setPending(), so those three cover the lot,
  // including verbs that do not exist yet.
  //
  // The visual range goes with it: it is a selection being dragged out, and
  // it means nothing once the thing it was for has happened.
  //
  // Written only when there is something to write. This is called on every
  // command the window runs, and assigning an empty object over an empty
  // object still fires every binding watching the marked set.
  function spendMarks() {
    if (root.visualOn) root.endVisual();
    if (!root.act) return;
    for (const k in root.act.marked) { root.act.marked = ({}); return; }
  }

  function setPending(v) {
    // Cut and copy are actions too — the marks have been spent on the
    // clipboard, and the paste that follows acts on what is in it.
    root.spendMarks();
    if (root.mgr) root.mgr.clipboard = v;
  }
  property string status: ""
  // ── and whether it is bad news ────────────────────────────────────────
  // The status line was drawn in red whatever it said, so "path copied",
  // "background set" and "3 to copy" arrived in the colour of a failure and
  // taught you to stop reading it. Red now means something went wrong or was
  // refused; everything else is an ordinary note.
  //
  // Cleared on EVERY status change and set again by warn() straight after —
  // which works because the change signal runs synchronously inside the
  // assignment, so warn's own flag lands last. That way a plain
  // `root.status = …` cannot inherit the red of whatever failed before it.
  property bool statusBad: false

  // ── and it goes away on its own ───────────────────────────────────────
  // "path copied" and "bookmark removed" are worth saying once; they are not
  // worth sitting in the bar until something else happens to overwrite them,
  // which is how a note becomes furniture you stop reading.
  //
  // EXCEPT WHEN IT ENDS IN AN ELLIPSIS. This window already uses that to mean
  // "still happening" — "searching…", "measuring 12 directories…" — and a
  // progress note that vanished while the work carried on would be a lie in
  // the other direction. Those stay until the thing they describe finishes
  // and replaces them.
  Timer {
    id: statusClear
    interval: 3000
    onTriggered: root.status = ""
  }

  onStatusChanged: {
    root.statusBad = false;
    // the chip keeps the words while it fades out; see its own note
    if (root.status !== "") chrome.statusChip.shown = root.status;
    root.armStatusClear();
  }

  // ── LONG ENOUGH TO READ IT ────────────────────────────────────────────
  // Three seconds is a "copied" — not an error with a reason in it. The
  // time grows with the length, a failure gets twice as long, and nothing
  // goes while the pointer is on it (see statusChip's hover): the full text
  // is open in its card then, and taking it away mid-sentence is rude.
  function armStatusClear() {
    const t = root.status;
    if (t === "" || t.endsWith("\u2026")) { statusClear.stop(); return; }
    statusClear.interval = Math.min(12000, (root.statusBad ? 6000 : 3000) + t.length * 35);
    if (!chrome.statusChipMa.containsMouse) statusClear.restart();
  }

  function warn(t) { root.status = t; root.statusBad = true; root.armStatusClear(); }

  // Only while there is something on screen to be about. On the way out the
  // flag is reset and this deliberately does not follow it, so the chip fades
  // in the colour it arrived in — see the chip's own note.
  onStatusBadChanged: if (root.status !== "") chrome.statusChip.shownBad = root.statusBad;

  // ── watching the directory ──────────────────────────────────────────────
  // the functions of this section live in terminus/DirWatch.qml; these
  // forward to it, so every caller is unchanged
  DirWatch { id: dirWatch; term: root }

  property bool watchBare: false
  // Deliberate stops whose exit has not been seen yet — see onExited.
  property bool watchStopping: false

  function watchDied() { return dirWatch.watchDied(); }


  // ── WHICH DIRECTORY CHANGED ───────────────────────────────────────────
  // inotifywait prints "<watched dir>/ EVENT[,EVENT] name", and until the
  // tree there was only ever one watched directory so the line carried
  // nothing worth reading. Now it names the one that moved, and that is
  // the difference between re-reading a branch and re-reading everything.
  //
  // A plain object mutated in place: nothing binds to it, it is drained by
  // the timer below, and making it a fresh object per event would be a
  // property write per inotify line.
  property var watchHits: ({})

  function noteWatchHit(line) { return dirWatch.noteWatchHit(line); }


  // Forget what these branches hold so they are read again. Only the ones
  // named, and only if they are still open.
  // ── RE-READ IN PLACE, DO NOT EMPTY AND REFILL ──────────────────────────
  function rereadBranches(dirs) { return dirWatch.rereadBranches(dirs); }

  // ── THE PREVIEWED DIRECTORY, WATCHED THE SAME WAY ─────────────────────
  // The right-hand column is a directory as much as the middle one is, and it
  // was the only listing on screen with nothing watching it: a file written
  // into it by something else stayed invisible until you walked in and out
  // again. One watcher, re-aimed at whatever is being previewed.
  //
  // AIMED ON A DELAY, not on every cursor move. Re-aiming is a process spawn
  // and a kill, and holding Down through a directory of directories would do one per
  // row for answers nobody reads. The row you actually stop on is the only one
  // worth watching — the same argument the preview's own debounce makes.
  property string peekWatched: ""




  function watchPeek(dir) { return dirWatch.watchPeek(dir); }

  function repeek() { return dirWatch.repeek(); }

  function forgetListing(dir) { return dirWatch.forgetListing(dir); }

  function watch() { return dirWatch.watch(); }

  // ── THE WATCH FOLLOWS THE ROWS, NOT JUST THE GESTURES ─────────────────
  // watching() is read off the rows on screen, and watch() was only asked
  // at the moments something was DONE — arriving, showing, a triangle
  // clicked. Arriving is exactly when the rows are not there yet: a
  // directory whose directories were left expanded comes back with its
  // branches read in a moment AFTER cwd changes, so the watch was armed on
  // cwd alone and stayed that way. Every delete inside an expanded directory
  // then went unseen — the job's own refresh re-reads cwd and never the
  // branches, which are the watcher's to catch — until a triangle was
  // clicked or you left and came back. Which is "random" only in the sense
  // that it depended on whether you had re-entered the directory since
  // last expanding something in it.
  //
  // So whenever the rows change, what SHOULD be watched is compared with
  // what WAS armed, and the watch is re-aimed when they differ. Debounced:
  // a directory with several remembered branches fills in one read at a
  // time, and each re-aim is a kill and a spawn.
  property string watchArmed: ""
  property string otherWatchArmed: ""


  // ── AND THE DIRECTORIES THAT ARE SHUT ─────────────────────────────────────
  // watchProc covers cwd and the open branches, which is everything whose
  // ROWS are on screen. One thing on screen is about a directory's inside
  // without showing it: the chevron, which says whether a shut directory
  // holds anything. A file landing in an empty shut directory is an event for
  // that directory and none at all for its parent, so nothing noticed, and
  // the directory stayed chevron-less until something made terminus look.
  //
  // So every shut directory row in the list gets a watch of its own, in a
  // SEPARATE inotifywait from watchProc:
  //   - only arrivals and departures, the only events that can change
  //     whether a directory is empty — not the close_write and attrib churn
  //   - an event never re-reads a listing; it asks probeEmpty again, and
  //     at most once a second (shutGate), because a shut .cache or a
  //     download in progress will fire all day
  //   - its failure costs nothing but chevrons, which is exactly how it
  //     was before it existed
  //
  // Only in the list, the one view with chevrons, only for the active
  // half, which is the one probeEmpty asks about, and capped: a results
  // page can name directories from anywhere.
  readonly property int shutCap: 2000
  property string shutArmed: ""

  function shutWatching() { return dirWatch.shutWatching(); }

  function watchShut() { return dirWatch.watchShut(); }

  // Whatever changes WHICH directories there are to watch without the rows
  // changing — rows changing already goes through watchAim.
  readonly property string shutKey: (root.shown && root.act && root.act.treed)
    ? String(root.paneSide) : ""
  onShutKeyChanged: dirWatch.watchAim.restart()



  function shutHit() { return dirWatch.shutHit(); }

  // ── THE OTHER HALF IS WATCHED TOO ─────────────────────────────────────
  property bool otherWatchStopping: false
  property bool otherWatchBare: false
  property var otherHits: ({})

  Timer { id: otherRetry; interval: 800; onTriggered: root.watchOther() }

  function otherWatching() { return dirWatch.otherWatching(); }

  function watchOther() { return dirWatch.watchOther(); }

  function noteOtherHit(line) { return dirWatch.noteOtherHit(line); }


  onOtherCwdChanged: { root.otherWatchBare = false; root.watchOther(); }

  function watching() { return dirWatch.watching(); }

  function openBranches() { return dirWatch.openBranches(); }

  onCwdChanged: {
    // Where the shell was last looking, whichever window it was in — see
    // TerminusManager.lastCwd. A dialog's wandering is not a place you were.
    if (root.mgr && root.shown && root.winId >= 0) root.mgr.noteCwd(root.cwd);
    // The anchor is a row INDEX, and the rows are about to be different ones.
    root.endVisual();
    // and a save aimed at a row here is not aimed at anything there
    root.saveAimed = false;
    // AND SO IS THE PREVIEW — USUALLY. Its peek is about a row in the
    // directory we have just left, and that row is not in this listing, so it
    // is wrong the instant cwd changes rather than merely stale. Cleared here
    // rather than left to the new listing, which is a whole process away:
    // that gap is exactly how long another directory's contents used to sit in
    // the right-hand column.
    //
    // NOT WHEN IT IS ALREADY ABOUT A ROW IN THIS LISTING. Walking UP lands on
    // the directory we came out of, so the preview should show precisely what
    // it is showing — millerStep has already handed that column those rows,
    // off the listing it had in hand. Blanking here threw them away and the
    // same thirty-two rows were built again a tick later: the third column
    // rebuilding on the way back, which rotation alone could never fix
    // because the rotation was never the thing destroying them.
    const shown = root.previewShown;
    if (shown === "" || Terminus.dirname(shown) !== root.cwd) {
      root.settlePreview("none", [], "");
      root.previewInfo = null;
      listing.infoDelay.stop();
    }
    // before anything else: how this directory was left is part of arriving
    // in it, and applying it after the listing has drawn is a visible flip
    root.applyDirView();
    // A new directory is a new set of branches: the fallback to cwd alone
    // was about the old set, and left set it kept every later directory's
    // expanded directories unwatched until the window was hidden and shown.
    root.watchBare = false;
    root.watch();
    slide.archSweep.restart();
    // one handler per signal: remembering the open tabs lives here too
    opening.viewSave.restart();
  }
  onSearchModeChanged: root.watch()
  // ── COMING BACK IS A REASON TO LOOK AGAIN ─────────────────────────
  // The watch is the main way a change shows, and it is not the only one
  // that has to work: a watch that died quietly (watchBare gives up on a
  // second death), a tab that sat in the background with nothing watching
  // it, or an event inotify does not report (a write still open) all left a
  // listing standing that was no longer true — and you only find out when
  // you look, which is exactly when the window gets the keyboard back. One
  // listing per pane, and the byte-identical guard makes an unchanged one
  // cost nothing on screen. A dead watch is re-armed while it is at it.
  // Through the attached Window: a FloatingWindow has no `active` of its own.
  readonly property bool keyed: content.Window.active
  onKeyedChanged: {
    if (!root.keyed || !root.shown || root.searchMode !== "") return;
    if (!dirWatch.watchProc.running) { root.watchBare = false; root.watch(); }
    if (root.dual && !dirWatch.otherWatchProc.running) { root.otherWatchBare = false; root.watchOther(); }
    root.refresh();
    root.refreshOther();
  }
  onShownChanged: {
    root.visible = root.shown;
    // A HIDDEN DIALOG IS AN UNANSWERED ONE. However this window came to be
    // hidden — the compositor, a stray keybind, anything that does not go
    // through portalAnswer — something is still waiting on it, and a request
    // that is never answered is a dialog that can never be opened again.
    if (!root.shown && root.picking) { root.portalCancel(); return; }
    // a closed spare is the manager's to keep or let go — see keepOneSpare
    if (!root.shown && root.mgr) {
      if (root.winId >= 0) root.mgr.noteCwd(root.cwd);
      root.mgr.noteHidden(root);
    }
    // A fallback taken last time the window was up is not a reason to watch
    // less this time — see watchDied.
    if (root.shown) { root.watchBare = false; root.otherWatchBare = false; }
    root.watch();
    root.watchOther();
    root.watchShut();
    // ── WHAT HAPPENED WHILE NOBODY WAS WATCHING ─────────────────────────
    // The watcher stops when the window hides, and that is exactly when
    // other programs write: you are in the browser when the download lands,
    // not in here. Coming back re-armed the watch and re-read nothing, so
    // every listing on screen was a photograph from the moment you left —
    // a file saved into an expanded directory was missing until the directory was
    // shut and opened again, and an empty directory that had since filled up
    // still had no chevron.
    //
    // So showing is treated as one big watch event. Cheap when nothing
    // moved: refresh() compares the bytes it gets back against the ones it
    // has, and a forced branch read replaces rows only when they arrive.
    if (root.shown) root.catchUp();
    // The peek watcher goes with it, and it has to be FORGOTTEN rather than
    // merely stopped: watchPeek does nothing when asked for the directory it
    // already holds, so a hidden window that kept the name would never re-aim
    // when it came back — the preview would be live until you closed it once
    // and dead ever after.
    root.peekWatched = "";
    dirWatch.peekWatchProc.running = false;
    if (root.shown) dirWatch.peekAim.restart();
    // "RESTORE SESSION" IS ABOUT WHAT YOU GET WHEN YOU OPEN IT.
    //
    // Gating only the restore-from-disk made the switch look broken, and
    // fairly: closing the window is how you close terminus, and the shell
    // still running underneath is an implementation detail nobody outside
    // this file should have to know about. Turned off, it kept every tab
    // across a hide and a show and only came up clean at the next login.
    //
    // So the clean slate happens on the way IN as well. Window 0 only —
    // the spare windows opened with N never restored anything to begin with.
    if (root.shown && !root.sessionReplay && root.winId === 0)
      root.resetSession();
  }

  function catchUp() { return dirWatch.catchUp(); }

  function resetSession() { return dirWatch.resetSession(); }

  // ── how each directory likes to be looked at ────────────────────────────
  // the functions of this section live in terminus/ViewPrefs.qml; these
  // forward to it, so every caller is unchanged
  ViewPrefs { id: viewPrefs; term: root }
  // A pictures directory wants the grid and a source tree wants the list, and
  // having to say so every time you walk between them is the sort of small
  // repeated cost a file manager should absorb. So the view and the zoom are
  // remembered PER DIRECTORY: change either while standing somewhere, and
  // coming back puts it the way you left it.
  //
  // A directory nobody has expressed an opinion about simply keeps whatever
  // the last one used, which is the old behaviour — so this only ever adds a
  // memory, never a surprise.
  //
  // Capped, and oldest-first, because this rides along in the preferences file
  // and a map that only ever grows would be an unbounded write on every save.
  property var dirViews: ({})
  property var dirViewOrder: []
  // How many directories keep their remembered view. Not readonly any more:
  // three hundred was a number nobody could see, let alone choose, sitting
  // next to a button offering to forget all of them.
  property int dirViewCap: 300

  // ...and whether to do it at all.
  //
  // It is the kind of helpfulness that is either exactly right or quietly
  // maddening: a directory of photographs opening as thumbnails is the point,
  // and a view that changes as you walk a tree when you wanted one view
  // everywhere is the same feature being wrong. The map is kept either way —
  // turning it off stops it being written and stops it being applied, so
  // turning it back on returns the memory rather than starting again.
  property bool perDirView: true

  // ── THUMBNAILS IN THE GRID ─────────────────────────────────────────────
  // The grid decoded every picture it could see, always. That is what the
  // grid is FOR on a directory of photographs, and it is what makes it unusable
  // on a network mount or four thousand raws — so it is a switch. Off, a tile
  // is its glyph, which is what a tile with nothing decoded yet already is.
  // ── DIRECTORIES AT THE TOP, OR NOT ─────────────────────────────────────────
  // The listing pinned every directory above every file, in every view but
  // disk usage. It is a reasonable default and it is not everybody's: sorted
  // by date, a directory touched last year sitting above this morning's download
  // is the sort refusing to answer the question asked of it.
  property bool dirsFirst: true

  // See Terminus.sortEntries: "file2" before "file10", which a plain string
  // compare gets backwards.
  property bool naturalSort: true

  property bool thumbsOn: true

  // ── AND THE PREVIEW PANE ───────────────────────────────────────────────
  // The third column's media half: the picture, the film's frame, the PDF,
  // the archive's tree. Off, the column still lists a directory you point
  // at — that is navigation, not preview — but nothing is decoded, stat'd or
  // read for a FILE you are merely passing over, which is most of them.
  property bool previewOn: true

  // Guards the round trip, and it is a DEPTH rather than a flag.
  //
  // applyDirView writes viewMode and the zooms, whose own handlers call
  // rememberView — which would write the very entry being read. A bool was
  // enough for that and wrong for everything since: exchangePanes sets it,
  // then changes cwd, whose handler calls applyDirView, which set it again and
  // then cleared it — releasing a guard its caller was still standing behind,
  // and applying the destination directory's view in the middle of a pane
  // swap. That is what made stepping between two panes with two different
  // views rearrange both of them.
  //
  // Counted, so an inner guard cannot end an outer one. Nothing terminus writes
  // to itself is recorded as a preference while this is above zero.
  property int applyDepth: 0
  readonly property bool applyingDirView: root.applyDepth > 0

  function rememberView() { return viewPrefs.rememberView(); }

  function trimDirViews() { return viewPrefs.trimDirViews(); }

  function forgetDirViews() { return viewPrefs.forgetDirViews(); }

  function applyDirView() { return viewPrefs.applyDirView(); }

  // ── the second pane ─────────────────────────────────────────────────────
  // the functions of this section live in terminus/SplitPane.qml; these
  // forward to it, so every caller is unchanged
  SplitPane { id: splitPane; term: root }
  // Optional, and off by default: terminus is a one-pane file manager that can
  // become a two-pane one, not the other way round.
  //
  // The trick is that there is still only ONE pane's worth of live state. The
  // active side is the window — cwd, rows, sel, marks, filter, history, the
  // lot, exactly as before — and the other side is a listing and a cursor and
  // nothing else. `o` SWAPS them, which is the same move switchTab makes
  // between tabs, so both sides get the full window in turn and neither needs
  // a second copy of every property in this file.
  //
  // What that buys: no branch in any existing key, verb or view. What it
  // costs: the inactive side cannot be filtered or marked until you step into
  // it, which is what stepping into it is for.
  property bool dual: false
  // THE OTHER HALF, READ THROUGH — the mirror of the block above. It owns
  // its listing the same way the active one does, so this is a window onto
  // it rather than a second copy kept in step by hand.
  readonly property string otherCwd: root.pas.cwd
  readonly property int otherSel: root.pas.sel
  readonly property var otherRaw: root.pas.raw
  readonly property var otherRows: root.pas.view

  // The two halves, as objects. Both exist whether or not the window is
  // split: with one pane the right-hand one is simply not drawn, which is
  // cheaper than creating and destroying a pane every time `dual` is
  // toggled and means the second side remembers where it was.
  // The left one starts where the window starts, in columns — the view a
  // file manager should open in, because it is the one you navigate in. The
  // right one starts empty, and an empty cwd is what "there is no second
  // pane yet" has always meant here: see toggleDual, which fills it with
  // wherever you are standing the first time you ask for a split.
  Pane { term: root; id: paneL; side: 0; cwd: Paths.home(); viewMode: "columns" }
  Pane { term: root; id: paneR; side: 1; viewMode: "list" }

  // WHICH ONE THE KEYBOARD IS IN, and which one it is not. Every verb in
  // this window acts on `act`; the other side is read, never written, except
  // by the two functions that deliberately reach across it.
  // GUARDED ON `dual`, and that guard is not decoration. With one pane
  // there is no other side to be in, but paneSide is remembered across a
  // session — so a window saved while the keyboard was on the right, then
  // reopened unsplit, would make paneR the active pane and draw paneL's
  // empty half. It cost an evening: the listing arrived, the model filled,
  // and the view on screen was bound to the other one.
  readonly property Pane act: (root.dual && root.paneSide === 1) ? paneR : paneL
  readonly property Pane pas: (root.dual && root.paneSide === 1) ? paneL : paneR

  // ── WHERE EACH HALF IS, as the views ask it ───────────────────────────
  function paneX(side) { return splitPane.paneX(side); }
  function paneW(side) { return splitPane.paneW(side); }
  function paneHeadH(side) { return splitPane.paneHeadH(side); }

  // The two views of whichever half the keyboard is in. Everything that used
  // to name `list` or `grid` outright means this.
  // ASKED, NOT ASSUMED. listA is not always the left half: `o` swaps the two
  // directories between the sides, and a pane carries the side it is drawn on
  // rather than being defined by it — see paneSide.
  //
  // Hardcoding the map cost the whole of list and grid their mouse. With the
  // active pane on side 1 and only one pane open, this handed back listB —
  // empty and not even drawn — so rowUnder asked an invisible view where the
  // pointer was, always heard -1, and `overEmpty` stayed true. The empty-space
  // MouseArea sits ABOVE the views, so it then swallowed every left click and
  // answered every right click with the paste-here menu for the row the cursor
  // was already on. Column view was unaffected, which is why it survived
  // unnoticed: rowUnder measures that one against the middle column directly.
  //
  // Written as expressions rather than through listOf(): a binding does not
  // re-evaluate on a FUNCTION call, so it would never notice a swap.
  // THE LIST WHOSE PANE IS THE ACTIVE PANE. Not "the list for paneSide":
  // `act` is `(dual && paneSide === 1) ? paneR : paneL`, so with one pane open
  // it is ALWAYS paneL however stale paneSide happens to be — and paneSide
  // does go stale, because closing the second half leaves it at 1 while the
  // only pane drawn is side 0. Following the number rather than the pane was
  // the whole bug: rowUnder asked an empty, undrawn view where the pointer
  // was, heard -1 forever, and the empty-space MouseArea that sits ABOVE the
  // views then ate every click in list and grid.
  readonly property var actList: chrome.listA.pane === root.act ? chrome.listA : chrome.listB
  readonly property var actGrid: chrome.gridA.pane === root.act ? chrome.gridA : chrome.gridB
  function listOf(side) { return splitPane.listOf(side); }
  function gridOf(side) { return splitPane.gridOf(side); }

  function comeOverAt(bx) { return splitPane.comeOverAt(bx); }

  function focusPane(pane, i) { return splitPane.focusPane(pane, i); }

  function rewindPane(side) { return splitPane.rewindPane(side); }

  // WHICH HALF the active pane occupies: 0 left, 1 right.
  //
  // Without this, `o` swapped the two directories between the sides and the
  // active pane was always the left one — so pressing it made the contents
  // jump across the window, and a border marking "the live side" would have
  // been a border that never moved. With it, the exchange and the flip happen
  // together: the state moves one way, the side it is drawn on moves the
  // other, and the visible result is that the contents stay exactly where they
  // are while the focus crosses over. Which is what Tab is expected to do.
  property int paneSide: 0
  // AN INVARIANT, NOT A TIDY-UP. With one pane, side 0 is the only half drawn
  // — PaneList and PaneGrid are both `dual || side === 0` — so a paneSide of 1
  // while unsplit names a half that does not exist.
  //
  // It happens: toggleDual puts the window back to one pane and leaves this
  // wherever the keyboard was. `act` guards against it (`dual && paneSide === 1`)
  // and so does everything reached through `act`, but anything reading the
  // number directly is looking at a lie. It already cost list and grid their
  // mouse once, through actList — which picked the list for paneSide rather
  // than the list belonging to the active pane, and so answered with an empty,
  // undrawn view.
  //
  // Enforced where the state changes rather than at each of the four places
  // that unsplit. loadTab writes `dual` before `paneSide`, so a tab that was
  // saved split still restores its side.
  onDualChanged: {
    if (!root.dual) root.paneSide = 0;
    root.watchOther();
  }

  // WHAT EACH SIDE IS SHOWING is the pane's own business now. paneViews and
  // paneZooms were two arrays indexed by side, kept in step by hand at every
  // exchange because the state crossed the divider and the view had to be
  // held back from crossing with it. Nothing crosses any more.
  //
  // TOTAL, on purpose: grid or list and nothing else. A stored value can be
  // "columns" — from a session before there were two panes, or a tab saved
  // while there was only one — and a third answer here renders neither view,
  // which is a pane that goes blank the moment you step out of it.
  readonly property string otherViewMode:
    root.pas.viewMode === "grid" ? "grid" : "list"

  // Where the divider sits, as a FRACTION of the body rather than a pixel
  // count, so resizing the window keeps the proportion you chose instead of
  // pinning one pane to a width and giving every new pixel to the other.
  property real paneFrac: 0.5
  // Eased when the divider is SENT somewhere — a keyed step, the double-click
  // back to even — and never while it is under the pointer. A behaviour left
  // running through a drag puts the split a frame behind the mouse, which
  // reads as the window resisting you rather than as smoothness. Exactly the
  // rule the sidebar's own Behavior follows; see `side`.
  Behavior on paneFrac {
    enabled: !chrome.splitGrip.pressed
    NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease }
  }
  readonly property real paneMinFrac: 0.15
  readonly property real paneMaxFrac: 0.85

  // The divider's x, and the two halves either side of it.
  readonly property real paneSplit: Math.floor(chrome.bodyBox.width * root.paneFrac)
  readonly property real leftPaneW: root.paneSplit
  readonly property real rightPaneW: Math.max(0, chrome.bodyBox.width - root.paneSplit - 1)

  // The half the keyboard is in, for the things that still follow it around
  // rather than belonging to a side: the miller frame, the drop target, the
  // rubber band. Both are paneX/paneW asked about the active side.
  readonly property real activePaneW: root.paneW(root.act.side)
  readonly property real activePaneX: root.paneX(root.act.side)



  // ── THE DIRECTORY YOU ARE ABOUT TO OPEN ───────────────────
  // Everything above makes the cold path cheaper. This is the admission
  // that the cold path is the wrong thing to optimise: Finder is not
  // quick at decoding, its cache is warm before you look, because the
  // system generated those thumbnails long ago and keeps them decoded.
  //
  // We cannot keep them decoded — Qt's cache for pixmaps no Image is
  // using is small and, checked on 6.11, has no tunable. What we can do
  // is decode them a moment BEFORE they are needed, while the cursor is
  // resting on the directory, and hold a reference so they survive until
  // the real tiles take over.
  //
  // MEASURED FIRST, because the whole thing rests on one assumption: a
  // second Image with the same source AND the same sourceSize is served
  // from cache and reports Ready on the spot, while a different
  // sourceSize is not. That is why the tile's decode size is pinned to
  // the pool's own — see thumb.pooled. A warm at the wrong size is not
  // a smaller win, it is no win and double the work.
  property string warmDir: ""
  property string warmShown: ""
  property var warmRows: []
  // A screenful and no more. Warming a directory you merely passed over
  // should cost a peek and a handful of decodes, not the directory.
  readonly property int warmCap: 24



  function warmPeek(force) { return splitPane.warmPeek(force); }

  // ── DO NOT OPEN INTO A GRID THAT IS NOT READY ────────────────
  // Every other change made the wait shorter. This one removes it from
  // view, which is a different thing and the only one that reaches zero:
  // a tile cannot show a placeholder during a swap that has not happened.
  //
  // MEASURED, because it decides where the wait actually is. From the
  // keypress: 92ms before the rows exist — that is find, parse, sort,
  // enrich — and every thumbnail resolved within 36ms after that, warm.
  // So the glyphs are not slow decoding. They are a view that changes
  // before its contents are ready, and no decoder is fast enough to fix
  // that, because the gap is between the swap and the paint.
  //
  // So the swap waits. The outgoing directory stays on screen — nothing
  // has changed yet at this point, which is exactly why the gate lives
  // in activate() and not in the listing handler — and the new one
  // appears whole.
  //
  // IT CAN ONLY EVER DELAY. holdStop fires at 150ms whatever happens and
  // opens regardless, so a directory whose thumbnails have to be built
  // from scratch costs a beat and then behaves as it always did. There is
  // no path here that can leave the window waiting on something.
  property bool openHeld: false
  property string holdFor: ""
  // The one open that has already been through the gate, so releasing it
  // cannot re-enter it.
  property string openCleared: ""

  Timer { id: holdPoll; interval: 16; repeat: true; onTriggered: root.holdTick() }
  Timer { id: holdStop; interval: 150; repeat: false; onTriggered: root.holdGo() }

  function warmSettled() { return splitPane.warmSettled(); }

  function holdTick() { return splitPane.holdTick(); }

  function holdGo() { return splitPane.holdGo(); }

  function warmLanded() { return splitPane.warmLanded(); }

  // Queued behind one in flight exactly as the active listing is — see
  // startListing.
  property bool otherAgain: false
  property string otherFor: ""

  function refreshOther() { return splitPane.refreshOther(); }

  function toggleDual() { return splitPane.toggleDual(); }

  // ── A FLOATING WINDOW MAKES ROOM FOR ITS SPLIT ─────────────────────────
  // Splitting a floating window widens it by one pane — each side keeps the
  // width the single pane had, as far as the monitor allows — and
  // unsplitting gives exactly that back, from the right edge — kept on the
  // monitor, never recentred (see Terminus.splitRoom). Tiled, fullscreen
  // or maximized, the layout owns the size and nothing happens: Terminus.splitRoom says so.
  //
  // Hyprland does the resize, because a mapped Quickshell window ignores a
  // new implicitWidth. `splitGrew` is what was added, and it is remembered
  // with the window's size: close a split window and it reopens wide, so an
  // unsplit after that must still know how much was ours to give back.
  //
  // ── ONE SPLIT'S WORTH OF ROOM, HOWEVER MANY SPLITS ────────────────────
  // The split is per TAB and the window is shared by all of them, so the
  // room is the window's, not a tab's: it is taken when the FIRST split
  // anywhere opens and handed back when the LAST one closes. Asked per
  // toggle, splitting a second tab widened the window again, and unsplitting
  // it gave back room the first tab was still standing in.
  //
  // And a window already carrying the room (splitGrew > 0) never takes it
  // twice — reopened wide from a session, say.
  //
  // ── THE ANSWER IS FOR THE QUESTION THAT WAS ASKED ─────────────────────
  // The resize waits on hyprctl, and `\ \` is quicker than that. The unsplit
  // found nothing to give back (splitGrew was only set when the answer
  // landed), then the split's answer landed anyway, widened a window that
  // was no longer split, and recorded nothing — so the room was never given
  // back, and every quick toggle ratcheted the window wider until it hit the
  // edges. So each request says what it was for (`fitFor`), an answer for a
  // state we have since left is dropped, and one request resizes at most
  // once (`fitPending`), however many times its process reports.
  property int splitGrew: 0
  property int splitWant: 0
  property bool fitFor: false
  property bool fitPending: false

  function otherTabSplit() { return splitPane.otherTabSplit(); }

  function fitSplit(on) { return splitPane.fitSplit(on); }

  function fitAfterTabs() { return splitPane.fitAfterTabs(); }


  function stepOver() { return splitPane.stepOver(); }

  // ── "THIS SIDE", NEVER "THE OTHER SIDE" ─────────────────────────────────
  function activatePane(side) { return splitPane.activatePane(side); }

  function swapSides() { return splitPane.swapSides(); }

  function exchangePanes() { return splitPane.exchangePanes(); }

  function sendToOther(op) { return splitPane.sendToOther(op); }

  // Where a paste LANDS. Normally where you are standing; the other pane's
  // directory for the one gesture that deliberately acts somewhere else. It is
  // cleared the moment the job is handed over, so nothing can inherit it.
  property string pasteDest: ""
  readonly property string destDir:
    root.pasteDest !== "" ? root.pasteDest : root.cwd

  // ── the sidebar ─────────────────────────────────────────────────────────
  // the functions of this section live in terminus/SideMarks.qml; these
  // forward to it, so every caller is unchanged
  SideMarks { id: sideMarks; term: root }
  // Bookmarks and disks, in a column you can put away. It replaces the strip
  // of bookmark chips that used to sit across the top: chips were fine for
  // four and useless for twenty, and there was nowhere to put a disk.
  property bool sidebar: false
  // How wide it is when open. Dragged by the divider, kept between sessions
  // with the other view preferences, and clamped so it can be neither a sliver
  // nor most of the window.
  property real sidebarWidth: 200
  // A shade under the list, and the number is small because it COMPOSITES.
  //
  // The sidebar is painted over the window's own ground, which is layerBg —
  // 80% black over the blurred desktop. An alpha of 0.90 here does not mean
  // "90% black on screen", it means 0.90 laid over 0.80, which comes out at
  // 0.98: near enough solid, and the reason the sidebar read as a hole cut in
  // the window. 0.25 over 0.80 lands at 0.85 — a shade under the listing,
  // which is all that was wanted, and the blur still carries through.
  // NOW THE BODY ITSELF (user, 2026-10-09): the sidebar, the path bar and
  // the column heads wear no shade of their own — hairlines alone divide
  // them. Ground at nought rather than "transparent", so the mix to solid
  // behind a sheet goes through the theme's ground and not through grey.
  readonly property color sidebarBg: Zenon.alpha(Zenon.ground, 0)

  readonly property real sidebarMin: 130
  readonly property real sidebarMax: 420

  // ── THE SIDEBAR MAKES ROOM FOR ITSELF ─────────────────────────────────
  // Plato's tree, copied: the sidebar is shown or hidden AT ONCE and slides
  // (see `side`), and at the same moment a floating window asks Hyprland for
  // the room — wider by the sidebar on the way out, narrower by exactly what
  // was added on the way back, from the left edge so the listing holds still
  // (pushed inward only if the monitor's edge is in the way). Tiled or fullscreen, the
  // layout owns the size and nothing happens. Each request says what it was
  // for (`sideFor`) and resizes at most once (`sidePending`), so a quick
  // open-close cannot land the open's answer after the close.
  property int sideGrew: 0
  property int sideWant: 0
  property bool sideFor: false
  property bool sidePending: false

  function toggleSidebar() { return sideMarks.toggleSidebar(); }

  function setSidebar(on) { return sideMarks.setSidebar(on); }

  // A PICKER DOES ALL OF THIS TOO. It used to be left out, so the sidebar in
  // a dialog was squeezed out of the listing instead of making room, and its
  // open/closed and width were forgotten — while it inherited the main
  // window's sideGrew and could "give back" room it never took. Now it
  // behaves exactly like the window, and keeps its own copy of the three
  // (pickerSidebar, pickerSidebarWidth, pickerSideGrew) through the merged
  // write in savePickerView, the way it keeps its own view and size.
  // ONE ANIMATION, NOT TWO (plato's tree had it first). The sidebar slid on
  // its own clock while Hyprland animated the resize and move on
  // another, and the listing shook left and right between them. While the
  // window is resized for the sidebar, the rest keeps its width (sideKeepW:
  // the window less the sidebar, at the toggle) and the sidebar is exactly
  // what the window has gained or not yet given back. -1: not following;
  // released once the window lands, or after a ceiling.
  property real sideKeepW: -1
  property bool sideFollowing: false
  property int sideTarget: 0
  function releaseSideFollow() { return sideMarks.releaseSideFollow(); }
  // tiled, maximized or fullscreen: the layout owns the size, no resize
  // will come, and the sidebar just slides (terminus/LayoutProbe.qml)
  LayoutProbe { id: sideLayout; title: root.title }
  Timer { id: sideCeiling; interval: 1500; onTriggered: root.releaseSideFollow() }
  function noteSideWidth() { return sideMarks.noteSideWidth(); }

  function sideRoom(shown) { return sideMarks.sideRoom(shown); }


  property var disks: []

  // ── ONE MARK IN THE SIDEBAR, AND THE MOST SPECIFIC ONE ────────────────
  function under(path, mount) { return sideMarks.under(path, mount); }

  readonly property string sideDisk: {
    if (root.searchMode !== "") return "";
    for (let i = 0; i < root.bookmarks.length; ++i)
      if (root.bookmarks[i] === root.cwd) return "";
    let best = "";
    for (let j = 0; j < root.disks.length; ++j) {
      const m = String(root.disks[j].mount || "");
      if (!root.under(root.cwd, m)) continue;
      if (m.length > best.length) best = m;
    }
    return best;
  }
  property string diskKey: ""
  // path -> { avail, fsSize, fsUsed }, refreshed on every poll — see diskProc
  property var diskUse: ({})
  function diskLive(d) { return sideMarks.diskLive(d); }
  // false until the first poll has landed, so the machine's own disks are not
  // mistaken for something you just plugged in
  property bool diskSeen: false


  // Polled rather than watched. udisks has a D-Bus signal for this and
  // quickshell can listen to D-Bus — but the polling costs one lsblk every
  // four seconds and needs no service to be running, and a file manager that
  // notices a USB stick three seconds late has still noticed it.
  // Every two seconds while the window is up — a gauge that lags a copy
  // by four reads as broken — and at once when a job finishes, which is
  // when free space actually moves (see onJobsEnded).
  Timer {
    interval: 2000
    running: root.visible
    repeat: true
    triggeredOnStart: true
    onTriggered: root.pollDisks()
  }

  function pollDisks() { return sideMarks.pollDisks(); }

  // ONE AT A TIME, IN ORDER. "Mount all" asks for several at once, and one
  // Process given a second command while it runs drops the first — so they
  // queue, and each starts when the one before it has answered.
  property var mountQueue: []

  function drainMounts() { return sideMarks.drainMounts(); }


  function leaveMount(mp) { return sideMarks.leaveMount(mp); }
  function leaveMountEverywhere(mp) { return sideMarks.leaveMountEverywhere(mp); }

  function mountDisk(d) { return sideMarks.mountDisk(d); }

  function ejectDisk(d) { return sideMarks.ejectDisk(d); }

  function ownsDiskPrompt() { return sideMarks.ownsDiskPrompt(); }

  // ── A DISK'S OWN MENU ─────────────────────────────────────────────────
  function confirmErase(heading, detail, items, onYes) { return sideMarks.confirmErase(heading, detail, items, onYes); }

  function diskMenu(item, x, y, d) { return sideMarks.diskMenu(item, x, y, d); }

  // ── how big a directory really is ──────────────────────────────────────────
  // the functions of this section (git, usage, directory sizes) live in
  // terminus/Measure.qml; these
  // forward to it, so every caller is unchanged
  Measure { id: measure; term: root }
  // The listing shows a dash for a directory, because a directory's own size
  // is the size of its record and never the number anybody means. `z` asks for
  // the real one, and the answer replaces the dash for as long as the window
  // is open.
  //
  // On demand, and it has to be: `du` over a home directory is a walk of every
  // inode under it, which is seconds of disk for a column nobody had asked
  // about. Measured directories are remembered by path, so the answer survives
  // walking away and coming back.
  property var dirSizes: ({})


  // ── git status ──────────────────────────────────────────────────────────
  //
  // A gutter beside the name, one character wide, saying what git thinks of
  // each row. Everything it needs was already here and tested — the command,
  // the porcelain parser, the roll-up that folds a repository's whole answer
  // down to the rows on screen — and none of it had ever been called; the mode
  // is what connects them.
  //
  // OFF BY DEFAULT and asked for explicitly, the same as disk usage, because
  // it costs a process per directory and most directories are not in a
  // repository at all.
  property bool git: false
  // path -> state, already rolled up: a directory carries the worst state of
  // everything beneath it, so the mark on a directory means "something in here".
  property var gitMarks: ({})
  // What repository, and which branch of it. Empty when the directory is not
  // in one, which is also how the bar knows to say nothing.
  property string gitRoot: ""
  property string gitBranch: ""


  property string gitAsked: ""

  function scanGit() { return measure.scanGit(); }

  function toggleGit() { return measure.toggleGit(); }

  function gitInk(state) { return measure.gitInk(state); }

  // ── disk usage ──────────────────────────────────────────────────────────
  //
  // ncdu's question, asked without leaving the directory you are in: what in
  // here is actually taking up the room. Everything it needs already existed —
  // `du` and its parser, the recursive sizes cache, the sort — so the mode is
  // mostly a matter of measuring every directory instead of the selected one
  // and drawing the answer as a length rather than only as a number.
  property bool usage: false
  // What the mode overrides, so leaving it puts things back rather than
  // leaving you in an order and a view you did not choose.
  property string usagePrevSort: ""
  property bool usagePrevDesc: false
  property string usagePrevView: ""

  function usageOf(r) { return measure.usageOf(r); }

  // The biggest thing on screen, which is what every bar is drawn against.
  readonly property real usageMax: {
    if (!root.usage) return 0;
    // The array in a LOCAL. `root.view` is a QML property, and reading it in
    // the loop condition and again in the body is two property lookups per
    // row — on a four-thousand-entry directory, eight thousand of them every
    // time a measurement lands.
    const v = root.view;
    let m = 0;
    for (let i = 0; i < v.length; ++i) {
      const b = root.usageOf(v[i]);
      if (b > m) m = b;
    }
    return m;
  }

  // AND THE SAME QUESTION ASKED OF THE OTHER HALF.
  //
  // Both panes drew their bars against usageMax, which is computed from the
  // ACTIVE listing — so walking through one half rescaled every bar in the
  // other and moved the sand-coloured "biggest here" mark onto a row that is
  // not the biggest there. A bar is a proportion, and a proportion is only
  // meaningful against the things beside it: each half is measured against
  // what is IN that half.
  //
  // The measurements themselves stay shared — dirSizes is keyed by path and a
  // directory is the same size whichever pane is looking at it. It is only the
  // yardstick that is per-pane.
  readonly property real otherUsageMax: {
    if (!root.usage || !root.dual) return 0;
    const v = root.otherRows;
    let m = 0;
    for (let i = 0; i < v.length; ++i) {
      const b = root.usageOf(v[i]);
      if (b > m) m = b;
    }
    return m;
  }

  function toggleUsage() { return measure.toggleUsage(); }

  // Every directory here, not just the selected one — the mode is a picture of
  // the whole directory and a picture with holes in it is worse than none.
  // Already-measured directories are skipped: dirSizes outlives the listing, so
  // coming back to a directory you have already looked at costs nothing.
  // Paths du has already been asked about, so one it cannot answer for — a
  // directory that is not readable — is asked once and then left alone.
  // Without this the retry below would ask about it forever.
  property var duTried: ({})


  function measureAll() { return measure.measureAll(); }

  // ── THE SELECTION'S DIRECTORIES, MEASURED FOR ITS TOTAL ────────────────────
  // Marking a directory asks what it adds up to, so it is measured — quietly, a
  // moment after the marks settle, and only the marked directories du has not
  // already answered for. Each is asked once (selTried), so a directory du cannot
  // read does not send this round in circles; it simply stays "measuring".
  property bool duQuiet: false
  property var selTried: ({})

  onMarkedCountChanged: if (root.markedCount > 0) measure.selMeasure.restart()

  function measureMarked() { return measure.measureMarked(); }

  function measureDirs() { return measure.measureDirs(); }

  // ── thumbnails ──────────────────────────────────────────────────────────
  // the functions of this section live in terminus/Thumbnails.qml; these
  // forward to it, so every caller is unchanged
  Thumbnails { id: thumbnails; term: root }
  // Generated for the whole directory at once when the grid is what is on
  // screen, and only then: a directory you are looking at as a list does not need
  // 256px PNGs of everything in it. `thumbTick` is what tells the tiles to
  // look again once the batch has finished.
  // path -> true once a batch has actually produced its thumbnail. A tile
  // points at the original until its entry appears here.
  //
  // Without this the tiles guessed, and every guess that lost printed
  // "Cannot open: …/thumbs/xxxx.png" into the log — one line per image per
  // visit, for a file that was about to exist. Asking the batch what it made
  // is the difference between a fallback and a warning.
  // path -> the thumbnail that exists for it, as the generator REPORTED it.
  //
  // Terminus used to work the filename out itself and assume the batch had made
  // it. Two things were wrong with that: a file that yields no picture — a
  // track with no cover — was marked ready and pointed an Image at a path
  // nothing had written, and the name could only ever be computed by terminus, so
  // Picasso could not find a thumbnail terminus had already made of the same
  // background. The pool is shared now and the shell names the files; this is
  // what came back. See morpheus/thumbs.js.
  property var thumbFile: ({})
  property var thumbJobs: []

  // ── AND THE SAME ANSWERS, ACROSS RESTARTS ──────────────────
  // thumbFile is this window's memory and dies with it. The pictures do
  // not — 133MB of them sit in the pool — so every restart re-derived
  // names that had not changed, by running md5sum over the directory
  // again. This is that derivation, kept: source -> "size|mtime|key".
  //
  // Checked in JS against the row's own stat, which the listing already
  // paid for. A file that changed has a different size or mtime, so its
  // entry simply does not match and the shell is asked properly — the
  // index can be wrong without ever being believed.
  property var thumbIndex: ({})
  // Generous: an entry is about sixty bytes and Buck's pool is 730
  // pictures. The cap is here so a decade of browsing cannot turn a cache
  // index into something that costs real time to parse.
  readonly property int thumbIndexCap: 40000


  function loadThumbIndex() { return thumbnails.loadThumbIndex(); }

  function indexHit(r) { return thumbnails.indexHit(r); }

  // ── A NAME IS NOT A FILE ──────────────────────────────────────────
  function thumbHas(r) { return thumbnails.thumbHas(r); }
  function keepThumb(url) { return thumbnails.keepThumb(url); }

  function thumbJob(r, kind) { return thumbnails.thumbJob(r, kind); }

  // ── A PROMISE THE POOL NO LONGER KEEPS ───────────────────
  // Thumbs.sweep deletes anything nothing has touched in a month, and a
  // person may empty the directory outright. The index would then point at
  // files that are gone, and a tile that used to show a picture would show
  // its glyph forever — the one failure a remembered name can cause that
  // deriving it every time cannot.
  //
  // So the Image says when it could not load, the claim is dropped, and
  // the file is asked for again. The same shape as noteBlind: the record
  // is allowed to be wrong because being wrong is survivable.
  //
  // AND THE BAD FILE GOES. A pool file that exists but will not decode — cut
  // short by a full disk or a killed generator — was reused as it was, since
  // the generator keeps anything non-empty: the Image failed again, asked
  // again, and got the same file back, a spawn loop for as long as the row
  // was on screen. So the file is removed before the retry, the retry waits
  // a beat for that to land, and a path that misses a second time is left
  // on its glyph for the rest of the session rather than asked forever.
  property var thumbMissed: ({})
  function thumbMiss(r) { return thumbnails.thumbMiss(r); }


  function saveThumbIndex() { return thumbnails.saveThumbIndex(); }

  // ── PICTURES QT CANNOT OPEN ─────────────────────────────────────────────
  // A quarter of what this window calls an image is a format Qt has a
  // decoder for; the rest — raws, HEIF, jxl, psd — are handed to the same
  // ImageMagick that already renders the grid's thumbnails, and the render
  // is shown in place of the file. See Terminus.qtBlind.
  //
  // THAT LIST IS A SEED, NOT THE TRUTH. Qt sniffs content as well as names
  // and its plugins differ per machine, so the list cannot be right by
  // construction — and does not have to be. An Image that fails writes its
  // extension down here, and every later file of that kind takes the
  // rendered path from the start. One wasted decode per format, once.
  property var blindExt: ({})

  function noteBlind(name) { return thumbnails.noteBlind(name); }

  function needsRender(r) { return thumbnails.needsRender(r); }

  function thumbKind(r) { return thumbnails.thumbKind(r); }

  // ── AND THE BETTER COPY, FOR QUICK LOOK ONLY ────────────────────────────
  // The preview pane follows the cursor and takes the cheap 480; quick look
  // is asked for, one file at a time, and gets 1600. Its own map and its own
  // process, so a big render cannot make the pane's batch wait.
  property var bigFile: ({})
  // Insertion order, so the map can be bounded. Without it this grew by one
  // entry for every image, video and track the window ever showed and never
  // gave one back — the same shape of leak the navigation history had, and the
  // odd one out among this window's caches, which are all capped (see
  // cachePreview and dirViewCap).
  //
  // Evicting is cheap and safe: the entry only says "a thumbnail for this path
  // exists", the file it names is still on disk, and the generator skips work
  // for a thumbnail that is already there. Losing an entry costs one stat, not
  // one decode.
  property var thumbOrder: []
  // Far more than a directory of photographs, so ordinary browsing never
  // evicts and the cap is only felt by a session that has walked past tens of
  // thousands of files.
  readonly property int thumbCap: 4000


  // Made but not yet handed to the grid — see thumbProc's stdout.
  property var thumbPending: ({})
  Timer { id: thumbFlush; interval: 80; onTriggered: root.takeThumbs() }

  function takeThumbs() { return thumbnails.takeThumbs(); }

  // ── HOW MANY PATHS FIT IN ONE COMMAND ────────────────────────────────
  // The whole job list is interpolated into a single `sh -c` argument, and
  // Linux caps one argument at MAX_ARG_STRLEN — 128KB. A backgrounds directory
  // went over it: the command came to 178KB and the kernel refused to exec
  // it, which Qt reports as "Process failed to start, likely because the
  // binary could not be found". Nothing was missing; the argument was too
  // long. Every thumbnail in that directory silently failed and the grid
  // sat on its glyphs.
  //
  // This is the same trap statArgv carries a note about, met from the other
  // side — there the fix was to stop using a shell string at all, and here
  // the shell is doing real work, so the list is cut into pieces instead.
  // 150 paths is comfortably inside the cap even for very long ones, and it
  // has a second benefit: the thumbnails appear in waves rather than all at
  // the end of one long run.
  readonly property int thumbBatch: 150
  property var thumbQueue: []

  function thumbNow(job) { return thumbnails.thumbNow(job); }

  function runThumbBatch() { return thumbnails.runThumbBatch(); }


  // Asked for when quick look opens on something Qt cannot read. The pane's
  // small copy is already on screen by then, so this only ever replaces a
  // soft picture with a sharp one.
  // path -> the size|mtime its big copy was rendered from, for the same
  // reason thumbHas exists: bigFile is keyed by path and outlives the file.
  property var bigStamp: ({})

  function wantBig(r) { return thumbnails.wantBig(r); }

  function makeThumbs() { return thumbnails.makeThumbs(); }

  function primeThumbs(want) { return thumbnails.primeThumbs(want); }

  // ── searching ───────────────────────────────────────────────────────────
  // the functions of this section live in terminus/Searching.qml; these
  // forward to it, so every caller is unchanged
  Searching { id: searching; term: root }
  // "" while browsing, "find" or "grep" while showing results. Results replace
  // the listing rather than opening a pane: they ARE what you are looking at,
  // and every verb should act on them exactly as it acts on a directory.
  property string searchMode: ""
  property string searchQuery: ""

  // ── THE REALM CHANGES WHEN THE ROWS DO, NOT BEFORE ────────────────────
  // Opening a collection used to change four things the moment you asked
  // for it: the view mode, searchMode (which brings the WHERE column in
  // and takes width off NAME), the sidebar's lit row, and the listing —
  // and the listing last, when the search answered. So a 150ms search
  // showed a reflow, then a blank, then the rows: three visible events
  // for one act, which is the flash.
  //
  // Holding the rows alone only removed the blank and left the reflow
  // happening on the OLD rows, which read worse. So all of it waits here
  // and lands in one frame, with the previous listing untouched until
  // then. The status line says `searching…` throughout, which is the one
  // honest thing to show while a question is outstanding.
  property var pendingRealm: null

  function applyPendingRealm() { return searching.applyPendingRealm(); }


  function runStat(paths, asked) { return searching.runStat(paths, asked); }


  function search(mode, query) { return searching.search(mode, query); }

  function searchKey() { return searching.searchKey(); }
  function runSearch() { return searching.runSearch(); }

  // ── collections ───────────────────────────────────────────────────
  // the functions of this section live in terminus/Collections.qml; these
  // forward to it, so every caller is unchanged
  Collections { id: collections; term: root }
  // A saved QUESTION — see collections.js. What lives here is the list of
  // and the machinery to run one; the compiler is over there.
  property var collections: []


  // What the file said last time we looked. Compared BEFORE anything is
  // assigned, because assigning `collections` rebuilds every sidebar row
  // under it — and the rows are where the cursor lives.
  property string collRaw: ""

  function loadCollections() { return collections.loadCollections(); }

  function editCollections(mutate) { return collections.editCollections(mutate); }

  // Written straight onto the record rather than into a side table: a
  // collection is already a thing with a name and rules saved on disk, and
  // how it is read belongs with them.
  // ── THE VIEW, AND ONLY THE VIEW ───────────────────────────────────────
  function rememberCollectionView() { return collections.rememberCollectionView(); }

  function rememberTagView() { return collections.rememberTagView(); }

  // ── A TAG PAGE IS ITS OWN PLACE ───────────────────────────────────────
  function applyTagView(name) { return collections.applyTagView(name); }

  // ── AND SO IS A COLLECTION ────────────────────────────────────────────
  function applyCollectionView(f) { return collections.applyCollectionView(f); }

  // ── RECENTS, WHICH IS BUILT IN RATHER THAN MADE ──────────────────────
  // Finder ships one saved search and this is it: what you have touched
  // lately, which is the answer to a surprisingly large share of "where did
  // I put that". Every part already exists — it is one date rule over home,
  // run by the same fd pipeline every other collection uses.
  //
  // NOT WRITTEN INTO THE COLLECTIONS FILE. Seeding a record into Buck's own
  // data would make it something he can half-delete and something a future
  // seeding bug can duplicate; synthesised here it simply always exists and
  // always says the same thing. The cost is that its view cannot ride on
  // the record like a real collection's does — see recentsView, which keeps
  // it in the view preferences instead, where view preferences live anyway.
  readonly property string recentsId: "builtin:recents"
  property string recentsView: Coll.DEFAULT_VIEW

  readonly property var recentsCollection: ({
    id: root.recentsId,
    name: "Recents",
    ink: "blue",
    root: "~",
    view: root.recentsView,
    builtin: true,
    // Skips the application-state churn a home directory is mostly made of
    // — see NOISE in collections.js for what and why.
    tidy: true,
    // Directories too, not only files — see the note on anyKind in
    // collections.js. A directory's mtime moves when anything is added to
    // or removed from it, so this reads as "directories worked in lately",
    // which is the half of "what have I touched" that was missing.
    anyKind: true,
    // The hundred most recently touched, not every hit in the window — see
    // `newest` in collections.js. Recents is a glance, and a week of a busy
    // home directory is several hundred rows nobody scrolls through.
    newest: 100,
    rules: [{ kind: "date", op: "within", value: "7d" }]
  })

  // The sidebar's list and the palette's: the built-in first, then yours.
  readonly property var allCollections:
    [root.recentsCollection].concat(root.collections)
  // The sidebar's, which Recents can be taken out of — see its row's cross.
  property bool recentsShown: true
  readonly property var sideCollections: root.recentsShown
    ? root.allCollections : root.collections

  // ── A SEARCH THAT HAS NOT BEEN SAVED ─────────────────────────────────
  // A refined search is a collection in every way but one: nobody named it.
  // It runs through the same pipeline and lands on the same results page,
  // and lives here rather than in the collections file until — if ever —
  // "save as collection" gives it a name. See collEdit.runSearch.
  property var scratchColl: null
  // What the search sheet last ran, so `s` over its results reopens on it.
  property var lastSearch: null
  readonly property bool scratchOpen: root.searchMode === "collection"
    && !!root.scratchColl && root.collOpenId === root.scratchColl.id

  function searchScratch(f, q) { return collections.searchScratch(f, q); }

  function collById(id) { return collections.collById(id); }

  function saveCollection(folder) { return collections.saveCollection(folder); }

  function dropCollection(id) { return collections.dropCollection(id); }

  // ── running one ───────────────────────────────────────────────────────

  function finishCollection(paths) { return collections.finishCollection(paths); }

  // ── var, NOT int, AND THAT IS NOT A STYLE CHOICE ──────────────────────
  // A collection's id comes from Date.now(), which is thirteen digits.
  // QML's `int` is 32-bit, so 1789823955681 was silently truncated to
  // -1177406751 on the way into this property — and collById then matched
  // nothing at all.
  //
  // Everything downstream failed quietly because of it: the view a
  // collection was set to was never saved (rememberCollectionView looks
  // the collection up by this id and gave up), and the sidebar row never
  // lit, because `collOpenId === modelData.id` compared a truncated number
  // with a whole one. Both looked like separate bugs in the view code.
  property var collOpenId: -1

  // ── OPENING ONE IS A JOURNEY; ARRIVING BACK AT ONE IS NOT ───────────
  function goToCollection(id) { return collections.goToCollection(id); }

  function openCollection(id) { return collections.openCollection(id); }

  // ── A COLLECTION IS A QUESTION, AND AN ACTION CHANGES THE ANSWER ──────
  // refresh() re-lists cwd and returns immediately on a results page — "results
  // are not a directory" — which was true when nothing on one could be acted
  // on. It is not true now: a collection is a tree, things are created,
  // renamed and deleted in it, and none of that showed. The row for a file
  // you had just deleted sat there until you left the page and came back,
  // which is exactly the complaint the directory listing used to draw.
  //
  // RE-ASKED, NOT PATCHED. Re-running the query is the only answer that is
  // right for all of it: a delete removes a row, a rename replaces one, and
  // a create ADDS one that no amount of re-statting the paths we already
  // have could discover. Measured at 10ms for Recents over this home
  // directory, which is cheaper than reasoning about which rows to mend.
  //
  // NOT openCollection, which is the gesture rather than the query: that one
  // records where to return to on Escape, announces itself in the status
  // line and puts the cursor on the first row. A refresh must do none of
  // those — see the landing in statProc.
  // Where the cursor was when a collection was re-asked, as a fallback for
  // when the row it was on has gone. -1 means "not a refresh".
  property int reAt: -1


  // ── EVERY RESULTS PAGE, RE-ASKED AFTER AN ACTION ────────────────────
  function reSearch() { return collections.reSearch(); }

  function reCollect() { return collections.reCollect(); }

  function cancelCollection() { return collections.cancelCollection(); }

  // ── A TAG, BROWSED ────────────────────────────────────────────────────
  function openTag(name) { return collections.openTag(name); }

  // Which tag is being browsed, for the sidebar to light its own row with.
  readonly property string openTagName:
    root.searchMode === "tag" ? root.searchQuery : ""

  property string searchBackCwd: ""
  property string searchBackSel: ""
  // ── AND HOW THE PANE WAS ARRANGED BEFORE THE RESULTS ─────────────────
  // A collection and a tag each carry their own view now, and applying one
  // changes the PANE — which is the same pane the directory underneath was
  // being read in. Leaving the results left the pane in the collection's
  // arrangement, so a directory you had in columns came back as a grid, and
  // the next thing that wrote a directory record wrote that down.
  //
  // So the arrangement is put back with the cwd and the cursor, which are
  // the other two things a results page borrows and has to return.
  property var searchBackView: null

  function clearSearch() { return collections.clearSearch(); }

  // ── tabs ────────────────────────────────────────────────────────────────
  // the functions of this section live in terminus/Tabs.qml; these
  // forward to it, so every caller is unchanged
  Tabs { id: tabs; term: root }
  // `cwd` and `sel` stay the live values rather than being read out of the tab
  // array, because every binding in this window already reads them. A switch
  // saves the pair into the tab being left and loads the pair from the tab
  // being entered — so tabs cost one array and two assignments, and nothing
  // downstream has to know they exist.
  property var tabs: [{ cwd: Paths.home(), sel: 0, dual: false, otherCwd: "",
                       otherSel: 0, paneSide: 0, view: "columns" }]
  property int tab: 0

  // Whether the tabs come back at all. Some people want the file manager to
  // open where they left it and some want it to open clean every time, and
  // neither is wrong — so it is a switch rather than a decision made here.
  //
  // Only the RESTORE is gated — the tabs go on being recorded either way, so
  // switching this back on takes effect from the session you are in rather
  // than needing one more restart before it has anything to remember. It does
  // mean the session saved before you turned it off is written over by the
  // next one, which is the right way round: what comes back should be where
  // you actually were last, not where you were the last time you happened to
  // have the setting on.
  property bool sessionReplay: true

  function tabState() { return tabs.tabState(); }

  function loadTab(t) { return tabs.loadTab(t); }

  // ── COMING BACK IS NOT ARRIVING ─────────────────────────────────────────
  // True while a tab is being put back or the halves are being exchanged.
  // The grid's entrance — the screenful held back, then rising tile by tile
  // (PaneGrid.held, TileRise) — is for walking INTO a directory; stepping back
  // into a tab you were just looking at replayed it on every switch, as if
  // the pictures had never been seen. Its rows are handed back already
  // listed, so they simply stand there.
  property bool quietArrive: false

  function tabList() { return tabs.tabList(); }

  function tabsForDisk() { return tabs.tabsForDisk(); }

  function saveTab() { return tabs.saveTab(); }

  onTabsChanged: opening.viewSave.restart()
  onTabChanged: opening.viewSave.restart()

  // ── rearranging them ────────────────────────────────────────────────────
  function moveTab(from, to) { return tabs.moveTab(from, to); }

  function switchTab(i) { return tabs.switchTab(i); }

  function newTab(path) { return tabs.newTab(path); }

  function openInNewTab(path) { return tabs.openInNewTab(path); }

  function openRealmInNewTab(open) { return tabs.openRealmInNewTab(open); }

  function closeTabAt(i) { return tabs.closeTabAt(i); }

  function closeTab() { return tabs.closeTab(); }

  // ── zoom ────────────────────────────────────────────────────────────────
  // the functions of this section live in terminus/Zoom.qml; these
  // forward to it, so every caller is unchanged
  Zoom { id: zoom; term: root }
  // One number, applied to the sizes that carry information — row height, the
  // glyph, the name, and the grid's cell. Not a scale transform on the whole
  // window: that would blur the text and enlarge the chrome, and the chrome is
  // not what you are trying to see more of.
  // TWO zooms, because they are two different questions.
  //
  // `zoom` scales the rows and the type in list and columns view — how much
  // text fits. `thumbZoom` scales the tiles in the grid — how big the pictures
  // are. One shared number meant sizing your thumbnails up to look at a photo
  // also blew up every row in the other two views, and each had to be undone
  // separately on the way back.
  //
  // Which one a zoom gesture moves is decided by the view you are in, so
  // ctrl+= means "more of what I am looking at" wherever you are.
  // Eased, so a burst of ctrl-+ is one continuous change of scale rather than
  // a stack of steps. Everything sized off zoom — row height, glyphs, names,
  // the grid's cells — moves together because they all read this one number,
  // which is the whole reason it is one number.
  property real zoom: 1.0
  // ── EASED WHEN YOU ZOOM, INSTANT WHEN YOU ARRIVE ────────────
  // Zoom is remembered per directory, so stepping into one restores its
  // number — and the ease turned that restore into a quarter-second of
  // the whole view resizing itself, from the last directory's zoom to
  // this one's. It reads as the listing settling down rather than as a
  // listing arriving, and it happens on every single navigation between
  // two directories that disagree about zoom.
  //
  // applyDepth already means exactly the right thing: terminus is
  // putting the view back the way it was, rather than you changing it.
  // It is held across the arrival restore, the back restore and the tab
  // restore, which is every case where the number is remembered rather
  // than chosen. Nothing terminus writes to itself is recorded as a
  // preference while it is up; nothing terminus writes to itself should
  // be animated either.
  Behavior on zoom {
    enabled: root.applyDepth === 0
    NumberAnimation { duration: Zenon.normal; easing.type: Easing.OutCubic }
  }
  // Eased on the PANE, not here: this is a window onto whichever half is
  // active, and an animation on a binding that changes target when the
  // keyboard moves would slide the number across on every Tab.
  readonly property real thumbZoom: root.act.zoom
  readonly property real zoomMin: 0.7
  readonly property real zoomMax: 2.4
  // Where the grid starts and where ctrl+0 puts it back: the smallest tile.
  readonly property real thumbZoomDefault: root.zoomMin

  // The zoom that the view on screen is actually using.
  readonly property real activeZoom: root.viewMode === "grid" ? root.thumbZoom : root.zoom

  // The system's own double click interval, which is a setting a person
  // may well have changed — and the fallback is Qt's default rather than a
  // number of my own. See the note on rowMouse.
  readonly property int doubleMs: {
    const v = Application.styleHints ? Application.styleHints.mouseDoubleClickInterval : 0;
    return (typeof v === "number" && v > 0) ? v : 400;
  }

  function zoomClamp(v) { return zoom.zoomClamp(v); }

  function zoomBy(step) { return zoom.zoomBy(step); }

  function zoomReset() { return zoom.zoomReset(); }

  function setZoom(v) { return zoom.setZoom(v); }

  // ── bookmarks ───────────────────────────────────────────────────────────
  // the functions of this section live in terminus/Bookmarks.qml; these
  // forward to it, so every caller is unchanged
  Bookmarks { id: bookmarks; term: root }
  // Kept in the shell's own state directory, not next to the config: it is
  // something you accumulate by using terminus, not something you write by hand.
  property var bookmarks: []


  function readBookmarks() { return bookmarks.readBookmarks(); }

  function loadBookmarks() { return bookmarks.loadBookmarks(); }

  function setBookmarks(list) { return bookmarks.setBookmarks(list); }

  function isBookmarked(path) { return bookmarks.isBookmarked(path); }

  function editBookmarks(mutate) { return bookmarks.editBookmarks(mutate); }

  function toggleBookmarkFor(path) { return bookmarks.toggleBookmarkFor(path); }

  // ── BOOKMARKING BY DRAG ─────────────────────────────────────────────
  function localPaths(urls) { return bookmarks.localPaths(urls); }

  function bookmarkDropped(urls) { return bookmarks.bookmarkDropped(urls); }


  // Which bookmark is being carried and where it would land, held on the
  // window because the row being dragged and the row drawing the drop line are
  // two different rows and neither can see the other.
  // The sidebar row the listing is currently standing in, published by the
  // ── THE CURSOR TRAVELS ONLY WHEN IT CHANGES ROWS ────────────────────
  // Its y comes from mapToItem, which moves for two quite different
  // reasons: the cursor moving to another row, and the sidebar's own
  // layout shifting under it. Easing was applied to both, and the second
  // one is not travel — it is the rows jumping while the bar walks to
  // where one of them used to be.
  //
  // They jump often. The column's top spacer is max(0, 10 - colHeads),
  // so the whole sidebar moves ten pixels whenever the listing's heading
  // strip appears or disappears with the view mode — and a bookmark that
  // opens a directory remembered in another view does exactly that. The
  // bar was then chasing a moving target: measured off Buck's capture it
  // ended up twenty-one pixels below the row it was going to, further
  // than the two rows are apart, with the active row's own cyan bar
  // already in place. Two rows marked, in two different ways.
  //
  // Armed by the row that CLAIMS the cursor, before the assignment, so
  // the binding is already allowed to ease by the time it re-evaluates.
  // Everything else snaps, which is what a layout shift should do.
  property bool sideSlide: false
  function armSideSlide() { return bookmarks.armSideSlide(); }

  // row itself — see SideRow. Held here because the bar that marks it is a
  // sibling of the Column the rows are in and cannot see inside it.
  property var sideAt: null
  // The sidebar row whose menu is open — outlined, not made the cursor, so
  // a right-clicked disk is plain to see without the bar leaving where you
  // are. Set by diskMenu, cleared by the menu itself as it closes.
  property var sideMenuAt: null
  // THE ROW A RIGHT CLICK ASKED ABOUT, in the listing. A right click is an
  // alt mode (user, 2026-10-09): the cursor stays where it was, the row is
  // outlined (HeldRing), and the menu is about it. Only a verb CHOSEN from
  // the menu brings the cursor over, since the verbs act on the cursor —
  // see RowMenu.run. Cleared as the menu closes.
  property var heldRow: null
  // The held row as the VERBS see it, only for the length of one chosen
  // verb (RowMenu.run): currentRow() and acting() answer with it, so the
  // verb acts there and the cursor never moves (user, 2026-10-09). A field
  // on a plain object, not a property, so setting and clearing it notifies
  // nothing — the preview and the bar never hear of it.
  readonly property var heldBox: ({ row: null })

  property int markDragFrom: -1
  property int markDragTo: -1
  // how tall the carried row is: the gap the others open for it
  property real markDragH: 0
  // the row just dropped, and how far from its new home it was let go —
  // the rebuilt row picks this up and glides the rest of the way in
  property var markSettle: null

  function moveBookmark(from, to, quiet) { return bookmarks.moveBookmark(from, to, quiet); }

  function removeBookmark(path) { return bookmarks.removeBookmark(path); }

  function toggleBookmark() { return bookmarks.toggleBookmark(); }

  function bookmarkVerb() { return bookmarks.bookmarkVerb(); }

  function toggleBookmarkHere() { return bookmarks.toggleBookmarkHere(); }

  // ── tags ────────────────────────────────────────────────────────────────
  // the functions of this section live in terminus/Tagging.qml; these
  // forward to it, so every caller is unchanged
  Tagging { id: tagging; term: root }
  // The truth is on the FILE — `user.xdg.tags`, see tags.js for why. What
  // lives here is a cache of it, because the truth is expensive to ask:
  // sweeping $HOME for tagged files takes 1.57s over 432,933 of them.
  // Once in the background is fine, behind every click on a sidebar tag is
  // not, so the answer is kept.
  //
  // Two halves, and only one of them is derived. `index` is a cache and can
  // always be rebuilt from disk. `defs` cannot: it is the colour and the
  // ORDER a tag was given, which exist nowhere on the filesystem, and a tag
  // that has been made but not yet put on anything exists only here.
  property var tagDefs: []          // [{ name, ink }]
  property var tagMarks: ({})       // path -> [name], the delegates' lookup

  // WHETHER ANYTHING AT ALL IS TAGGED. Gates the tag ordering in the sort
  // ring: on a machine that has never used tags, "sort by tag" is a button
  // that cannot change the order of anything. Cheap because tagMarks is
  // swapped wholesale rather than mutated, so this re-evaluates once per
  // index rebuild, not once per tagged file.
  readonly property bool anyTagged: {
    for (const k in root.tagMarks) return true;
    return false;
  }


  function tagState() { return tagging.tagState(); }

  property var tagViews: ({})

  // What became of each preset that is no longer itself — see tagState.
  property var tagGone: ({})

  property string tagRaw: ""

  function loadTags() { return tagging.loadTags(); }

  function editTags(mutate) { return tagging.editTags(mutate); }

  // ── IS THIS ONE OF THE SEVEN, WHATEVER IT IS CALLED NOW ─────────────
  function presetSlot(name) { return tagging.presetSlot(name); }

  function tagInk(name) { return tagging.tagInk(name); }

  function tagsFor(path) { return tagging.tagsFor(path); }

  // Drops index entries for paths that were asked about and did not come
  // back. Only ever called with a list we have just stat'd, so "missing"
  // means missing rather than "not looked at".
  //
  // A collection's paths come from fd and are real by construction, so the
  // only ones this can remove are tag entries whose file has gone.
  // ── A TAG IS KEYED BY PATH, AND A PATH CAN STOP EXISTING ────────────
  function forgetTags(paths) { return tagging.forgetTags(paths); }

  function moveTags(pairs) { return tagging.moveTags(pairs); }

  function pruneTagIndex(asked, rows) { return tagging.pruneTagIndex(asked, rows); }

  // What the sidebar lists: every tag that is on at least one file, by name,
  // with how many carry it. Sorted rather than kept in definition order —
  // the sidebar is somewhere you look a tag UP, and the list is as long as
  // the number of tags in use rather than a handful you arranged by hand.
  readonly property var sideTags: {
    const counts = Tags.tally(root.tagMarks);
    const names = Object.keys(counts).sort();
    const out = [];
    for (let i = 0; i < names.length; ++i)
      out.push({ name: names[i], count: counts[names[i]],
                 ink: root.tagInk(names[i]) });
    return out;
  }

  function openTagPicker() { return tagging.openTagPicker(); }
  function openProperties(page) { return tagging.openProperties(page); }
  function openCollectionEditor(id) { return tagging.openCollectionEditor(id); }

  // ── writing a tag to the disk ─────────────────────────────────────────

  function applyTagPairs(pairs, homing) { return tagging.applyTagPairs(pairs, homing); }

  function drainTagWrites() { return tagging.drainTagWrites(); }

  function toggleTagFor(paths, name) { return tagging.toggleTagFor(paths, name); }

  function toggleTagHere(name) { return tagging.toggleTagHere(name); }

  function defineTag(name, ink) { return tagging.defineTag(name, ink); }

  function renameTag(from, to) { return tagging.renameTag(from, to); }

  // ── OFF EVERY FILE, FROM THE SIDEBAR'S CROSS ──────────────────────────
  function clearTag(name) { return tagging.clearTag(name); }

  function dropTag(name) { return tagging.dropTag(name); }

  // ── rebuilding the cache from the disk ────────────────────────────────

  function rebuildTagIndex(where) { return tagging.rebuildTagIndex(where); }

  // ── taking the keyboard ─────────────────────────────────────────────────
  // the functions of this section live in terminus/Portal.qml; these
  // forward to it, so every caller is unchanged
  Portal { id: portal; term: root }

  // ── portal mode ─────────────────────────────────────────────────────────
  // What xdg-desktop-portal-termfilechooser asks for when an application says
  // "open a file". The portal runs a wrapper script, the wrapper hands the
  // request here over ipc and then waits, and terminus answers by writing the
  // chosen paths — one per line — into the file the portal named.
  //
  // Three shapes of request, and they are genuinely different tasks:
  //   open   pick one or more existing things
  //   dir    pick a directory, which means the one you are IN counts
  //   save   type a name for something that does not exist yet
  //
  // A `done` marker is written beside the output file whether the pick was
  // confirmed or cancelled. Without it the wrapper cannot tell "still
  // choosing" from "chose nothing", and a cancel would hang the application
  // that asked until the wrapper's patience ran out.
  property var portal: null   // { multiple, directory, save, out }
  readonly property bool picking: root.portal !== null

  // ── A DIALOG FOR ITS WHOLE LIFE, not just while a request is open ───────
  //
  // `picking` answers "is there a request in front of me", and it goes false
  // the instant one is answered — while the window itself lives on for a
  // moment afterwards. Every guard written against it therefore has a hole on
  // the way out, and the preference write is debounced by 400ms, which is
  // exactly long enough to fall through it: a sort chosen inside a save dialog
  // was written to the shared preferences after the dialog had stopped
  // picking, and the next thing the main window loaded was the dialog's idea
  // of how to sort.
  //
  // winId is -1 from the moment a picker is constructed and never changes, so
  // this is true for as long as the object exists.
  readonly property bool isPicker: root.winId === -1

  function persistPrefs() { return portal.persistPrefs(); }

  // ── THE FILE YOU HAVE NOT SAVED YET ─────────────────────────────────────
  //
  // Firefox and friends write the file BEFORE they ask where to put it: by the
  // time the dialog is up, the suggested name already exists at the suggested
  // path, with real bytes in it. So a save dialog opened on a directory showed
  // the thing you were in the middle of naming as an item already sitting
  // there — 461 bytes, "modified just now" — and offered to overwrite it.
  //
  // Nothing in this window or in the portal wrapper creates that file; both
  // were checked, and a picker opened by hand against an empty directory
  // leaves it empty. It is the asking application's, and it is not ours to
  // delete. It is ours not to LIST: the dialog is about a file that does not
  // exist yet, and saying otherwise is the dialog contradicting itself.
  //
  // Matched on the full path the request named, not on the name in the field,
  // so renaming in the field does not un-hide it and an unrelated file that
  // happens to share the name elsewhere is untouched.
  readonly property string portalGhost:
    (root.portal && root.portal.save && root.portal.suggested)
      ? root.portal.suggested : ""

  // ── WHERE A SAVE LANDS ────────────────────────────────────────────────
  // It was always cwd, so in the list, where directories open in place rather
  // than being walked into, the only way to save into one was to right-click
  // it and open it as a directory. For an EMPTY directory there was nothing
  // else to do at all: it has no chevron, so it cannot be expanded to put
  // the cursor inside it.
  //
  // The directory under the cursor is the place, open or not, which is exactly
  // the question cursorDir already answers for making a new file. A file
  // under the cursor means the directory it sits in. Outside the tree (columns,
  // grid) cursorDir is cwd, so those views save where they always did.
  //
  // ONLY ONCE YOU HAVE AIMED IT. A listing lands with the cursor on its
  // first row, and when that row is a directory, "type a name and press
  // Return" would have saved into it rather than where the dialog opened.
  // So the cursor counts from the first click or move you make, and stops
  // counting again whenever the directory changes under it.
  property bool saveAimed: false
  readonly property string saveDir: {
    if (!root.portal || !root.portal.save || !root.saveAimed) return root.cwd;
    // read so the binding follows the cursor and the rows under it
    void root.act.sel; void root.act.view;
    return root.cursorDir();
  }

  // Something by that name is already where the save would land. The
  // portal used to guard this by appending "_" to the name it suggested,
  // and pick() now strips that (see there), so the dialog has to be the
  // one to say so: the button reads "Replace" rather than overwriting
  // quietly.
  readonly property bool saveClash: {
    if (!root.portal || !root.portal.save) return false;
    const n = chrome.saveField.text;
    if (n === "") return false;
    const target = Terminus.joinPath(root.saveDir, n);
    // the application's own placeholder is not a file you would be replacing
    if (target === root.portalGhost) return false;
    const rows = root.saveRows();
    for (let i = 0; i < rows.length; ++i)
      if (rows[i].path === target) return true;
    return false;
  }

  // What is already where the save would land, less the application's own
  // placeholder (see portalGhost), which is not a name anybody is using.
  function saveRows() {
    const rows = root.saveDir === root.cwd
      ? root.rows : (root.act.kids["k:" + root.saveDir] || []);
    return rows.filter((r) => r.path !== root.portalGhost);
  }

  // The clash's way out, short of replacing: the field's name with the first
  // free " (n)" before its extension — the shape Keep both writes on a paste.
  // The small button inside the name field while saveClash holds.
  function saveNumbered() {
    const f = chrome.saveField;
    f.text = Terminus.freeNameKeeping(root.saveRows(), f.text);
    f.forceActiveFocus();
    f.cursorPosition = f.text.length;
  }

  readonly property string portalTitle: {
    if (!root.portal) return "";
    if (root.portal.save) return "Save as";
    if (root.portal.directory) return "Choose a directory";
    return root.portal.multiple ? "Choose files" : "Choose a file";
  }

  // What confirming would hand back, so the button can say how many and refuse
  // when there is nothing to give.
  readonly property var portalChoice: {
    if (!root.portal) return [];
    if (root.portal.save) {
      const n = chrome.saveField.text;
      return Terminus.nameError(n) === "" ? [Terminus.joinPath(root.saveDir, n)] : [];
    }
    if (root.portal.directory) {
      // a marked directory if you marked one, otherwise the one you are
      // standing in — which is what "choose this directory" means
      const dirs = root.markedRows().filter((r) => r.isDir);
      if (dirs.length > 0) return dirs.map((r) => r.path);
      const c = root.currentRow();
      if (c && c.isDir) return [c.path];
      return [root.cwd];
    }
    const files = root.acting().filter((r) => !r.isDir);
    if (files.length === 0) return [];
    return root.portal.multiple ? files.map((r) => r.path) : [files[0].path];
  }


  function portalAnswer(paths) { return portal.portalAnswer(paths); }

  function portalConfirm() { return portal.portalConfirm(); }

  function portalCancel() { return portal.portalCancel(); }

  // ── which way it is laid out ────────────────────────────────────────────
  // the functions of this section live in terminus/Opening.qml; these
  // forward to it, so every caller is unchanged
  Opening { id: opening; term: root }
  //   list    one row per entry, with size and date. What you want when the
  //           question is "how big" or "when did I touch this".
  //   columns yazi's miller layout — parent, here, and a preview of whatever
  //           is under the cursor. What you want while NAVIGATING, because
  //           you can see where you came from and where you are about to go
  //           without moving.
  //   grid    thumbnails. What you want in a directory of pictures, where the
  //           filename is the least useful thing about the file.
  readonly property string viewMode: root.act.viewMode
  // MILLER COLUMNS IS A THREE-COLUMN LAYOUT, and two of them side by side is
  // six columns of listing in half a window each. So while the second pane is
  // open the ring is list and grid — the two views that are a single column
  // and therefore mean the same thing at half width. Closing the pane brings
  // columns back.
  readonly property var viewRing: root.dual
    ? ["list", "grid"] : ["columns", "list", "grid"]

  // ── A DIALOG REMEMBERS ITS OWN VIEW, NOT YOURS ────────────────────────
  // pick() used to force columns on every request, and the picker was
  // excluded from writing preferences — so a view chosen in a dialog was
  // gone the moment it closed.
  //
  // The exclusion is right and stays: a save dialog must not be able to
  // rewrite how your file manager looks. What was missing is that a
  // dialog is a place too, and it can have a preference of its own. So
  // it gets a second slot in the same file, written only by pickers and
  // read only by pick().
  property string pickerView: "columns"

  // syncPaneView STOOD HERE and copied the active half's view and zoom into
  // the arrays indexed by side, on every change, so that stepping away and
  // back returned to it. The pane holds them itself now; there is nothing to
  // copy and nothing that can fall out of step.

  function demoteColumns() { return opening.demoteColumns(); }

  function cycleView() { return opening.cycleView(); }

  function setView(v) { return opening.setView(v); }

  // ── how solid the window is ─────────────────────────────────────────────
  //
  // ORACLE'S PANEL OPACITY, as every other window in the shell (user,
  // 2026-10-09: terminus was the one place that ignored it). It had its own
  // Opacity slider, saved per window at 80%, which is gone; the alpha is
  // Zenon.layerBg's, which is Oracle.panelOpacity through Zenon.glass.
  readonly property real winAlpha: Zenon.layerBg.a

  // ── what it opens as ────────────────────────────────────────────────────


  function savePickerView() { return opening.savePickerView(); }


  function loadViewPrefs() { return opening.loadViewPrefs(); }

  function restoreTabs(st) { return opening.restoreTabs(st); }

  property var pendingTabs: []
  property int pendingTabIndex: 0

  // ── WHERE THIS WINDOW WAS ASKED TO OPEN ───────────────────────────────
  // Set by the manager when a window is built FOR a destination, which is
  // now the ordinary case: nothing is created at startup any more, so
  // `Terminus open ~/Pictures` builds the window and tells it where to go.
  //
  // It has to be a property rather than a goTo from outside, because the
  // session restore below finishes ASYNCHRONOUSLY — it shells out to check
  // which stored directories still exist — and lands a second or so after
  // the window was made. Navigating from the manager therefore worked and
  // was then undone, which looked exactly like the request being ignored.
  property string bootPath: ""

  // ── A NEW WINDOW ARRIVES FINISHED ───────────────────────────────────────
  // It used to be shown the moment it was made, and then everyone watched it
  // load: a flat listing, the expanded directories filling in a beat later and
  // shoving every row below them down, and "measuring 48 directories" filling
  // the size column after that. Nothing was slow — it was all visible.
  //
  // So a window the manager makes, or a hidden spare it re-aims, is held
  // back until its listing is in and no branch is still being read, and only
  // then shown — with a ceiling, so a slow disk costs a short wait and never
  // a window that does not come. The sizes come from the manager's pool of
  // what the other windows have already measured (see noteSizes there), so
  // the size column is not re-measured either.
  property bool holdReveal: false
  property int revealWaited: 0
  function revealWhenReady() { return opening.revealWhenReady(); }

  function dismissMenus() { return opening.dismissMenus(); }

  function takeBoot() { return opening.takeBoot(); }


  // rememberView restarts the save itself — see how each directory likes to
  // be looked at, above
  onZoomChanged: root.rememberView()
  onThumbZoomChanged: root.rememberView()
  onSidebarChanged: {
    root.saveSide();
    // the foot's trash size, fresh as the sidebar comes out
    if (root.sidebar) fileOps.trashSizeLater.restart();
  }
  onSidebarWidthChanged: root.saveSide()
  function saveSide() { return opening.saveSide(); }
  // Both write the directory's record, the same way a view change does. The
  // applyDirView guard inside rememberView is what stops this echoing back
  // while a record is being applied.
  onSortKeyChanged: {
    if (root.act.sortKey !== root.sortKey) root.act.sortKey = root.sortKey;
    root.rememberView(); opening.viewSave.restart();
  }
  onSortDescChanged: {
    if (root.act.sortDesc !== root.sortDesc) root.act.sortDesc = root.sortDesc;
    root.rememberView(); opening.viewSave.restart();
  }
  // The other direction: the keyboard crossed over, so the window's order is
  // now the half it arrived in. Muted — taking up a pane's own sort is not
  // telling that directory how it likes to be read.
  onActChanged: {
    root.applyDepth++;
    root.sortKey = root.act.sortKey;
    root.sortDesc = root.act.sortDesc;
    root.applyDepth--;
  }
  onShowHiddenChanged: opening.viewSave.restart()

  // Every view scrolls its own way, and only one of them is on screen — but
  // telling all three is cheaper than asking which, and means switching view
  // never lands you somewhere other than where the cursor was.
  // ── holding your place while the listing is rebuilt ─────────────────────
  // the functions of this section live in terminus/Preview.qml; these
  // forward to it, so every caller is unchanged
  Preview { id: preview; term: root }
  function keepScroll() { return preview.keepScroll(); }

  // ── A CHEVRON MOVES NOTHING BUT THE ROWS UNDER IT ───────────────────────
  // Opening or shutting a branch changes the rows below it, which the view
  // reads as a wholesale change and rewinds for; the cursor is then landed
  // back on its row with positionSel — which SCROLLS to it. From the
  // keyboard that is right: the cursor is where you are looking. From a
  // chevron it is not — you clicked a triangle somewhere else on screen, and
  // the list jumped away from it to wherever the highlighted row was.
  //
  // So a chevron saves the scroll first, and the landing puts it back
  // instead of chasing the cursor. The cursor still moves with its row.
  property var scrollHold: null
  function settleScroll() { return preview.settleScroll(); }

  function restoreScroll(keep) { return preview.restoreScroll(keep); }

  function putScroll(v, y) { return preview.putScroll(v, y); }

  function toggleGrouped() { return preview.toggleGrouped(); }

  // ── SCROLL ELASTICS ───────────────────────────────────────────────────
  // The band and the smooth wheel notch are morpheus/Elastic.qml now —
  // one rule for every scrollable surface in the shell rather than a copy
  // of the numbers per module. Everything that used to be written out
  // here, including why Flickable cannot do this on its own, moved there
  // with its comments.
  //
  // The listing's wheel is an ElasticScroll like every other list's, given
  // `pick` (three views sit under one pointer, wheelTarget chooses) and
  // `intercept` (ctrl+wheel zooms) — see the body's wheel overlay.

  // Whether the horizontal keys belong to the tree rather than to history.
  // One question, asked in the key handler and by the hint bar, so the two
  // can never disagree about what h does.
  // ── WHICH PAGES A TREE CAN EXIST IN ───────────────────────────────────
  // A directory listing, always. And a COLLECTION, which is new: its rows
  // are paths from all over, so they cannot be INDENTED by how deep they
  // happen to live — that was Recents putting lua files three levels in
  // under nothing, and the reason the whole tree was switched off here —
  // but a directory in the results is still a directory, and opening it in place
  // to see what is in it is the same gesture it is anywhere else. Depth
  // comes from the walk now rather than from the path, which is what makes
  // the difference; see the pane's `flat`.
  //
  // NOT find or grep. Those pages are a question you asked, and splicing
  // a directory's whole contents into a list of matches answers a
  // different one.
  // ── WHICH SET OF OPEN BRANCHES IS SHOWING ───────────────────────────
  // A collection is its own list, so the directories opened in it are its own
  // too. They were ONE map per pane, shared by every realm that pane had
  // ever shown: collapsing Documents in home collapsed it in Recents and
  // the other way about, because both were asking the same map about the
  // same path.
  //
  // Keyed by realm, and a collection's key is its id — two collections do
  // not share either. find, grep and a tag page all answer "d": none of
  // them draws a tree (see treeRealm), so they have nothing to keep and
  // must not disturb what the directory listing has.
  // ── WHERE YOU ARE, AS SOMETHING HISTORY CAN HOLD ────────────────────
  // The trail stored paths, and a collection is not one — so opening one
  // put nothing in history and leaving it dropped it entirely. Back went
  // to whatever you were doing before, as though the collection had never
  // been a place. It is a place: it has a name, a row in the sidebar and
  // its own remembered view.
  //
  // A directory is its path and a collection is "c:" and its id, which is
  // a number for one you made and a string for the built-in — both survive
  // the round trip, see travelTo. find, grep and tag pages answer with the
  // cwd they are covering, so they are not recorded separately; they are
  // typed once and gone, and Escape is their way out.
  readonly property string here:
    root.searchMode === "collection" ? ("c:" + root.collOpenId) : root.cwd

  // ── AND A TAG PAGE IS A LIST YOU MADE, TOO ──────────────────────────
  // It was grouped with find and grep — "a question you asked" — and so a
  // tagged directory was the one directory in terminus you could not open in
  // place: no chevron, and a double click walked you into it. But a tag is
  // closer to a collection than to a search: you put those things there,
  // and reading what is inside one is the point. So it draws a tree, and
  // keeps its own open branches under its name — "t:" + the tag — so
  // expanding a directory on the blue page does not expand it everywhere.
  readonly property string realmKey:
    root.searchMode === "collection" ? ("c:" + root.collOpenId)
    : (root.searchMode === "tag" ? ("t:" + root.openTagName) : "d")

  readonly property bool treeRealm:
    root.searchMode === "" || root.searchMode === "collection"
    || root.searchMode === "tag"

  readonly property bool treeKeys:
    root.viewMode === "list" && root.treeRealm

  // ── ONE KEY, FOUR OUTCOMES ────────────────────────────────────────────
  function treeStepKey(deeper) { return preview.treeStepKey(deeper); }

  function collapseAll() { return preview.collapseAll(); }

  // ── A VIEW CAN BE SCROLLED PAST THE END OF A LISTING IT NO LONGER
  //    HAS ─────────────────────────────────────────────────────────
  // Page down through a directory of 481 and step back out into one of 30
  // and the view keeps the contentY it had: measured at 10380 against a
  // contentHeight of 670. The TILES still draw — the view lays those out
  // from the model — so nothing looks wrong, but SelectCell positions
  // itself by -contentY, which puts the cursor ten thousand pixels above
  // the viewport. The cursor is not lost, it is off-screen, and no
  // keypress brings it back because every new index is drawn just as far
  // away.
  //
  // Nothing else was going to catch it. syncView's rewind is deliberately
  // SKIPPED when a row is spoken for — which is exactly what going back
  // does, since wantSel holds the directory you came out of — and
  // positionViewAtIndex with Contain does nothing when it reckons the
  // index is already visible.
  // ── CONTENT DOES NOT NECESSARILY START AT ZERO ───────────────
  function snapInBounds(v) { return preview.snapInBounds(v); }

  function positionSel() { return preview.positionSel(); }

  function rowsFromListing(text, dir) { return preview.rowsFromListing(text, dir); }


  // ── the parent, for the left column ─────────────────────────────────────
  property var parentRows: []
  // The bytes the left column was built from, so an answer that says nothing
  // new leaves it alone. Same guard, same reason, as the listing's own.
  property var parentListing: null

  function seedParent() { return preview.seedParent(); }


  function startParent() { return preview.startParent(); }

  // where the directory we are IN sits in its own parent, so the left column
  // can mark it the way the middle column marks the cursor
  readonly property int parentIndex: {
    // At an archive's top the row to mark in the parent is the archive.
    const at = Terminus.mountOf(root.cwd, root.archMounts);
    const me = (at && at.mnt === root.cwd) ? at.archive : root.cwd;
    for (let i = 0; i < root.parentRows.length; ++i)
      if (root.parentRows[i].path === me) return i;
    return -1;
  }

  // ── the preview, for the right column ───────────────────────────────────
  // What the preview has already produced, keyed by path. Walking back up a
  // list re-selects rows you were just on, and re-running bat and re-laying
  // out its markup to show you the same thing again is the delay you feel.
  // Capped, because a preview of a big file is a big string.
  // ── ARRIVING SOMEWHERE YOU HAVE ALREADY SEEN ────────────────────────────
  // Raw `find` output by directory. Miller's whole shape is that the column on
  // the right is ALREADY the directory you are about to step into — the peek
  // that drew it is the same command, with the same flags, that listing it
  // would run. Stepping in threw that away and waited for a process to tell it
  // again, which is most of the lag on every `l` and every click.
  //
  // Kept as TEXT rather than as parsed rows, so the seed is byte-identical to
  // what the refresh behind it will return: lastListing is set from the same
  // string, so the confirming listing recognises itself and returns without
  // touching the model at all. Arriving costs a parse instead of a process.
  //
  // Small and short: sixteen directories, nothing over 64KB. This is a way of
  // not waiting, not a cache of the filesystem.
  property var listingText: ({})
  property var listingOrder: []

  function rememberListing(dir, text) { return preview.rememberListing(dir, text); }

  property var previewCache: ({})
  property var previewOrder: []
  // A text preview is rendered in the theme of its moment (render.lua's
  // colours, baked into the markup), so a new theme empties the cache and
  // renders the row under the cursor again.
  Connections {
    target: Zenon
    // settled, not every step of a crossfade: each would run render.lua
    function onThemeEpochChanged() {
      root.previewCache = ({});
      root.previewOrder = [];
      root.previewShown = "";
      root.previewFor = "";
      root.refreshPreview();
    }
  }

  function cachePreview(path, entry) { return preview.cachePreview(path, entry); }

  // ── THE SETTINGS PANEL'S CURSOR ────────────────────────────────────────
  // The panel used to say of itself that it "has no keyboard of its own — it
  // is a panel of switches you point at", and that is true right up until the
  // moment your hands are already on the keys. Tab walks it now.
  //
  // THE ROWS ENROL THEMSELVES rather than being listed here: they are written
  // inline in two columns and there are twenty-two of them, and a hand-kept
  // index beside that is a second list to forget to update.
  //
  // AND THEN THEY ARE SORTED BY WHERE THEY ARE. Enrolment order is completion
  // order, and Component.onCompleted is emitted children-before-parents with
  // no promise about siblings — so the registry came out backwards and Tab
  // started at the bottom of the right-hand column. Position is the only thing
  // that agrees with what the eye is going to do: down the left column, then
  // down the right.
  property var prefRows: []
  property int prefCursor: -1

  function prefEnrol(item) { return preview.prefEnrol(item); }

  function prefOrder() { return preview.prefOrder(); }

  function prefAt() { return preview.prefAt(); }

  function prefStep(d) { return preview.prefStep(d); }

  // ── THE KEYMAP ─────────────────────────────────────────────────────────
  // This was the F1 page's own table and it is the only copy of it now. The
  // page is gone: it and the palette were the same list twice — one you read
  // and closed and then pressed the key, one you typed into and ran — and the
  // palette was already drawing the key beside every verb. So the keymap IS
  // the palette, and there is one thing to open instead of two.
  //
  // STILL GROUPED, because ninety keys in a flat list is a wall. The palette
  // shows these headings when nothing is typed and drops them when something
  // is: grouped to read, ranked to search.
  //
  // Nothing here carries a verb, and most of it CANNOT. j and k are the
  // cursor, escape means four different things depending on what is up, and
  // the mouse gestures are not keys at all. The ones that can are matched to
  // the verb table by KEY, below, so the runnable half stays runnable and
  // nothing is listed twice.
  readonly property var keyGroups: [
    // No back/forward row: they are verbs, so the palette lists them itself
    // rather than this writing the same pair down a second time.
    ["move", [["j / k  ↓ ↑", "down / up"],
              ["←  backspace", "parent"], ["→", "enter a directory"],
              // What h / l and the horizontal arrows do depends on the
              // view, so the hint has to as well — see root.treeKeys.
              [root.treeKeys ? "h / l  ← / →" : "h / l",
               root.treeKeys ? "collapse / expand" : "back / forward"],
              ["↵", "open"], ["space", "quick look"],
              ["g g", "top"], ["G", "bottom"],
              ["ctrl u / d", "half page"], ["ctrl b / f", "page"],
              [root.mouseKey(4) + " / " + root.mouseKey(5),
               "back / forward"]]],
    ["select", [["shift space", "toggle and move on"],
                ["v", "visual select"],
                ["ctrl a", "select all"],
                ["ctrl r", "invert selection"],
                ["esc", "leave visual, then clear"]]],
    ["act", [["y y", "copy"], ["y t", "copy to"],
             ["x x", "cut"], ["x t", "move to"], ["p", "paste"],
             ["d", "trash"], ["D", "delete for good"],
             ["a", "create (end in / for a directory)"], ["r", "rename"],
             ["c m", "permissions"], [";  ctrl s", "shell here"],
             ["u", "undo trash / move / rename"],
             ["z", "measure directory size"],
             ["c a", "archive selection"],
             ["c x", "extract archive"]]],
    ["look", [["f  /", "filter"], ["s", "search names"],
              ["S", "search contents"], [".", "hidden"],
              [", n / s / m / k", "sort name / size / time / kind"],
              [", !", "reverse"],
              ["V", "view: columns · list · grid"], ["+ / -", "zoom"],
              ["ctrl 0", "reset zoom"]]],
    ["go", [["g r", "the directory a row actually lives in"],
            ["g space", "go to\u2026 (tab completes)"],
            // The sheet's own footer says this, and F1 did not — the one
            // place the chord was not written down. `false` because it
            // claims no verb: the palette's shift+return is the listing's,
            // which hands a FILE to open-with. See the note in the builder.
            ["shift return", "go to\u2026 landing in a new tab", false],
            ["g h", "home"], ["g c", "config"], ["g d", "downloads"],
            ["g D", "documents"], ["g p", "pictures"], ["g v", "videos"],
            ["g t", "trash"], ["g m", "media"], ["g /", "root"]]],
    ["copy", [["c c", "full path"], ["c d", "directory"],
              ["c f", "filename"], ["c n", "name without extension"]]],
    ["tabs", [["t", "new"], ["w", "close"], ["1 - 9", "switch"],
              ["shift return", "open a directory in a new tab", false],
              [root.mouseKey(3), "open a directory in a new tab"],
              ["[  ]", "previous / next"]]],
    ["panes", [["\\", "second pane on / off"],
               ["tab  o", "step into the other side"],
               ["alt \u2190 \u2192", "resize the split"],
               ["|", "sidebar on / off"],
               ["alt shift \u2190 \u2192", "resize the sidebar"],
               ["f5", "copy to the other side"],
               ["f6", "move to the other side"],
               [root.mouseKey(1), "step into the other side"]]],
    ["marks", [["b a", "bookmark this directory"],
               ["b b", "bookmark the item under the cursor"]]],
    ["tags", [["c t", "tag the selection"],
              ["\u21b5", "put the tag on / take it off"],
              ["type", "filter, or name a new tag"],
              ["alt r", "rename the highlighted tag, in the row"],
              ["del", "remove a tag everywhere"],
              ["menu", "the seven colours, on the row's own menu"]]],
    ["collections", [["c s", "new collection"],
                     ["click", "open one from the sidebar"],
                     ["right click", "edit one from the sidebar"],
                     ["middle click", "remove one from the sidebar"],
                     ["esc", "leave it and go back"]]],
    ["dialogs", [["esc", "close"], ["return", "accept"],
                 ["\u2190 \u2192 \u2191 \u2193", "move (permissions)"],
                 ["space", "toggle a bit"],
                 ["s", "checksum (properties)"]]],
    ["menu", [["menu key", "actions for the row"],
              [root.mouseKey(2), "actions for the row"],
              ["\u2014", "archive · open with"],
              ["\u2014", "bulk rename · links · restore"],
              ["\u2014", "sort, as a submenu"]]],
    ["window", [["q", "close"],
                ["esc", "clear filter / selection"],
                [root.mouseKey(4) + " / " + root.mouseKey(5),
                 "back / forward"]]],
    // THE LIST DESCRIBING ITSELF, which is not as odd as it looks: it is the
    // keymap, and the keys that drive it are keys. They were the one set that
    // was only ever printed along its own footer, where a hint strip is read
    // once and then stops being looked at.
    //
    // F1 is not among them any more. It opened a separate keymap page, that
    // page is this list, and a second key to the same door is a key to
    // remember for nothing.
    ["palette", [["F1 / ~ / ctrl p", "open this list"],
                 ["\u2014", "type to filter"],
                 ["\u2191 \u2193", "move"],
                 ["\u21b5", "run the highlighted verb"],
                 ["esc", "close"]]]
  ]

  // ── EVERY VERB, BY NAME ────────────────────────────────────────────────
  // The two-key sequences come from `content.sequences`, which already pairs
  // a label with the function it calls, so those cannot drift from what the
  // keys actually do. The single-key verbs are a switch rather than a table
  // and are named here — the one list in this file that has to be kept in
  // step by hand, and the smaller half of the job.
  //
  // A label that is a FUNCTION is called: `b b` says "bookmark" or "remove
  // bookmark" depending on the row, and a palette that said one of those when
  // it meant the other would be worse than not listing it.
  //
  // THE KEYMAP DECIDES THE ORDER AND THE VERB TABLE DECIDES WHAT RUNS. Read
  // the groups in order, hand each row the verb that shares its key, and put
  // whatever verb the keymap never mentioned in a group of its own at the end
  // — so a thing that can be done is never unreachable just because the page
  // it was written for did not list it.
  readonly property var commands: {
    const verbs = [];
    const seqs = content.sequences;
    for (const prefix in seqs) {
      const rows = seqs[prefix];
      for (let i = 0; i < rows.length; i++) {
        const r = rows[i];
        const label = (typeof r[1] === "function") ? r[1]() : r[1];
        const key = prefix + " " + (r[0] === " " ? "space" : r[0]);
        verbs.push({ label: label, key: key, act: r[2], used: false });
      }
    }
    const one = [
      ["open",              "\u21b5", () => root.activate()],
      ["open with",         "\udb81\ude36 \u21b5", () => root.beginOpenWith(
                                              root.currentRow()
                                                ? root.currentRow().path : "")],
      ["quick look",        "space",   () => root.quickLook()],
      // BOTH KEYS ON THE VERB, not a verb keyed `h` and a keymap row saying
      // `h / l  ← →` beside it. They were the same two things listed twice —
      // once as something you could run and once as something to read — and
      // the palette drew them as two rows a few lines apart.
      ["back",              "h",       () => root.back()],
      ["forward",           "l",       () => root.forward()],
      ["up a directory",    "h",       () => root.goUp()],
      ["rename",            "r",       () => root.beginRename()],
      ["bulk rename",       "r",       () => root.beginBulkRename()],
      ["duplicate",         "y d",     () => root.duplicate()],
      ["make symlink",      "y l",     () => root.linkHere()],
      ["rotate left",       "[",       () => root.rotateLook(-90)],
      ["rotate right",      "]",       () => root.rotateLook(90)],
      ["extract audio",     "e",       () => root.extractAudio()],
      ["sort by tag",       ", t",     () => root.setSort("tag")],
      ["group headings",    ", h",     () => root.toggleGrouped()],
      ["expand in place",   "l",       () => {
        const r = root.currentRow();
        if (r && r.isDir) root.act.setOpen(r.path, true);
      }],
      ["collapse all",      "",        () => root.collapseAll()],
      ["paste",             "p",       () => root.paste()],
      ["new file or directory", "a",      () => root.beginCreate()],
      ["new directory with selection", "c g", () => root.gatherIntoFolder()],
      ["trash",             "d",       () => root.trash()],
      ["delete for good",   "D",       () => root.deleteForever()],
      ["undo",              "u",       () => root.undo()],
      ["select all",        "ctrl a",  () => root.selectAll()],
      ["invert selection",  "ctrl r",  () => root.invertSelection()],
      ["search names",      "s",       () => root.beginSearch("find")],
      ["search contents",   "S",       () => root.beginSearch("grep")],
      // alt return, which is the key it has always answered to and the only
      // verb here listed with no key at all — the palette drew it with an
      // empty chip while the keymap wrote the key down separately, so neither
      // half said the whole thing.
      ["properties",        "alt \u21b5",  () => props.ask()],
      ["permissions",       "c m",     () => root.openProperties(1)],
      ["disks",             "M",       () => disks.ask()],
      ["tags",              "c t",     () => tagPick.ask()],
      ["new collection",  "c s",     () => collEdit.ask(-1)],
      // Editing one is only offered while you are looking at it, which is
      // also the only time you know which one you mean.
      ["edit collection", "",        () => {
        if (root.collOpenId >= 0) collEdit.ask(root.collOpenId);
        else root.warn("open a collection first");
      }],
      ["go to containing directory", "g r", () => root.reveal()],
      ["reindex tags",      "",        () => root.rebuildTagIndex()],
      ["new tab",           "t",       () => root.newTab()],
      ["close tab",         "ctrl c",  () => root.closeTab()],
      ["split view",        "\\",      () => root.toggleDual()],
      ["step to other pane", "o",      () => root.stepOver()],
      ["sidebar",           "|",       () => root.toggleSidebar()],
      ["cycle view",        "V",       () => root.cycleView()],
      ["hidden files",      ".",       () => root.showHidden = !root.showHidden],
      ["disk usage",        ", u",     () => root.toggleUsage()],
      ["git status",        ", g",     () => root.toggleGit()],
      ["open a shell here", "ctrl s",  () => root.openShell()],
      ["settings",          "",        () => prefs.open = true]
    ];
    for (let i = 0; i < one.length; i++)
      verbs.push({ label: one[i][0], key: one[i][1], act: one[i][2],
                   used: false });

    // FIRST VERB PER KEY, and only for a key that is one. Two verbs can share
    // a key — `r` is rename on one row and bulk rename on several — and three
    // have no key at all, so a plain map keyed by key would have silently
    // dropped the second of each pair. The keymap row takes the first; the
    // rest come back below, unclaimed and still listed.
    const byKey = ({});
    for (let i = 0; i < verbs.length; i++) {
      const k = verbs[i].key;
      if (k !== "" && byKey[k] === undefined) byKey[k] = verbs[i];
    }

    const out = [];
    const gs = root.keyGroups;
    for (let g = 0; g < gs.length; g++) {
      const name = gs[g][0];
      const rows = gs[g][1];
      // ── WHAT A ROW CLAIMS, AND WHAT IT ONLY SHOWS ─────────────────
      // A row is paired to a verb by KEY, which is convenient and is held
      // together by two strings agreeing. Two things went wrong with that and
      // both are answered here.
      //
      // FIRST, keys mean different things in different places. `dialogs` and
      // `menu` describe keys that work INSIDE something else — a card that is
      // up, or the row menu — so `s`, which is "checksum" under the properties
      // card, claimed the listing's SEARCH CONTENTS verb: the row came up
      // yellow and return on it would have started a filename search. The same
      // trap sat on `esc`, `return` and `space`. Those two groups claim
      // nothing.
      //
      // SECOND, a row that writes its key the way a READER wants it — `h  ←`,
      // `g / G` — no longer matches the verb's own key and silently stops
      // claiming. So a row may NAME the verb it claims as a third element, and
      // then the two are tied by something written down rather than by two
      // strings happening to agree.
      const modal = name === "dialogs" || name === "menu";
      for (let i = 0; i < rows.length; i++) {
        // THIRD, a row may say it claims NOTHING, with `false` in that slot.
        // One key can mean two things depending on what is under the cursor:
        // shift+return opens a DIRECTORY in a new tab and hands a FILE to the
        // open-with sheet. The verb is the file half. This row is the
        // directory half, and matching on the key alone let it swallow the
        // verb — which took the verb out of the palette's runnable half and
        // left "open with" listed with no key beside it.
        const claim = rows[i].length > 2 ? rows[i][2] : rows[i][0];
        const v = (claim === false || (modal && rows[i].length <= 2))
          ? undefined : byKey[claim];
        if (v !== undefined) v.used = true;
        // THE KEYMAP'S WORDING IS WHAT IS SHOWN, THE VERB'S IS STILL FOUND.
        // The two tables name the same thing differently on purpose: the
        // keymap is read under a heading, so `\\` is "second pane on / off"
        // under panes, while the verb has to stand alone and is called "split
        // view". Taking the keymap's label alone lost the other name — typing
        // "split" found the row that RESIZES one and not the one that opens
        // it. So the verb's name rides along as something to match against.
        out.push({ section: name, label: rows[i][1], key: rows[i][0],
                   alias: v !== undefined ? v.label : "",
                   act: v !== undefined ? v.act : null });
      }
    }
    for (let i = 0; i < verbs.length; i++)
      if (!verbs[i].used)
        out.push({ section: "more", label: verbs[i].label,
                   key: verbs[i].key, alias: "", act: verbs[i].act });

    // ── THE ONES THAT DO SOMETHING FIRST ──────────────────────────────
    // Two kinds of row live in this list and they are different in kind: a
    // verb you can press return on, and a key the window already answers to.
    // Read in group order they were shuffled together, so the half you can
    // act on was something you found by scanning for the colour.
    //
    // A STABLE PARTITION, not a sort: inside each half the groups keep their
    // order, so the keymap still reads as move, then select, then act — it is
    // the same page with the verbs lifted to the top of it.
    // ── AND THE COLLECTIONS, BY NAME ─────────────────────────────────
    // A collection is a verb you made: "open the PNGs" is exactly the sort
    // of thing this list is for, and reaching them only through the
    // sidebar meant the one window that has no sidebar open could not get
    // at them at all. Named rather than keyed — there is no key to give
    // out, and the palette is how a thing without one is reached.
    for (let i = 0; i < root.allCollections.length; i++) {
      const c = root.allCollections[i];
      if (!c || !c.name) continue;
      out.push({ section: "collections", label: c.name, key: "",
                 alias: Coll.describe(c),
                 act: (function (id) {
                   return function () { root.goToCollection(id); };
                 })(c.id) });
    }

    const runs = [];
    const refs = [];
    for (let i = 0; i < out.length; i++)
      (out[i].act ? runs : refs).push(out[i]);
    return runs.concat(refs);
  }

  // ── LOOKING PROPERLY, WITHOUT OPENING ANYTHING ─────────────────────────
  // The preview column is a column: a photograph in it is a stamp, and the
  // only way to actually SEE a file was to open the application that owns it
  // and then close it again. This is the same preview the pane already
  // computes — previewKind, previewText, the cached frame — drawn at the size
  // of the window instead of the size of a column.
  //
  // It reads that state rather than starting any of its own: whatever the
  // cursor is on has already been worked out by the time you ask.
  property bool looking: false

  function quickLook() { return preview.quickLook(); }

  // ── WHAT THE ROW NEEDS, MADE ON DEMAND ───────────────────────────────
  function lookFetch() { return preview.lookFetch(); }

  property string previewKind: "none"   // none | dir | image | video | audio | font | pdf | text | archive | binary
  // Where a rendered PDF page lands. One name, reused: only one preview is on
  // screen at a time, so keeping every page ever looked at would be a cache
  // nobody reads. `previewStamp` busts Qt's image cache, which would otherwise
  // show the previous PDF at the same path.
  // Beside the thumbnails, not loose in the cache root: everything terminus
  // renders is one directory, so clearing it is one rm.
  readonly property string pdfStem: Terminus.terminusCacheDir() + "/preview"
  // WHOSE PAGE IS CURRENTLY AT pdfStem. One file is reused for every PDF, so
  // the path alone cannot say whether what is sitting there belongs to the row
  // being asked about — quick look would happily show the last document opened
  // in the preview pane. Written wherever a render is started.
  property string pdfFor: ""
  property int previewStamp: 0
  property var previewRows: []
  // AN ARCHIVE'S TREE IS NOT A LISTING'S ROWS, and they used to share this
  // property. A tree entry has a glyph, an ink and a depth; it has no `path`,
  // so nothing that expects an entry can read one — and everything that reads
  // the preview had to ask `previewKind` first and remember to. The file
  // already carries the scar: an invisible ListView "quietly instantiated a
  // column of rows against the wrong shape of data".
  //
  // Two properties, so the question cannot be forgotten. Each is emptied when
  // the other is filled — see settlePreview, which is the one place both are
  // written.
  property var previewTree: []

  property string previewText: ""
  // ── TEXT PREVIEWS ARE SET IN PLATO'S FACE ───────────────────────────
  // The column preview and quick look show a file's text as plato would:
  // its typeface and weight (plato/core/Settings, kept in plato.json in
  // this shell's state — plato itself is loaded only while open). Its
  // defaults when plato has never saved one: SF Mono, SemiBold.
  property string codeFamily: "SF Mono"
  property int codeWeight: Font.DemiBold
  // cached previews carry the face in their markup: a new one reads afresh
  onCodeFamilyChanged: root.previewCache = ({})
  FileView {
    path: Quickshell.statePath("plato.json")
    watchChanges: true
    blockLoading: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      let j = {};
      try { j = JSON.parse(text()) || {}; } catch (e) {}
      root.codeFamily = j.fontFamily || "SF Mono";
      root.codeWeight = ({ regular: Font.Normal, medium: Font.Medium, semibold: Font.DemiBold,
                           bold: Font.Bold })[j.fontWeight || "semibold"] || Font.DemiBold;
    }
  }


  // The cache is tried SYNCHRONOUSLY, before the debounce. A row you have
  // already looked at needs no process and no parse, so making it wait 55ms
  // behind a timer that exists to avoid spawning things was the one delay with
  // nothing behind it — walking back up a list is now instant.
  onSelChanged: {
    // timed for lag.log: a cursor move to the frame that shows it
    listing.drawnAfter("terminus cursor drawn");
    // The shift-range starts wherever the cursor was last put — see anchorPath.
    if (!root.holdAnchor) root.setAnchor(root.act.sel);
    // Before the early return below: the range follows the cursor in every
    // view, not only the one that draws a preview.
    if (root.visualOn) root.extendVisual();
    // Before the columns-only return: the grid is where this matters, and
    // the grid never reaches refreshPreview.
    splitPane.warmAim.restart();
    if (root.viewMode !== "columns") return;
    root.refreshPreview();
  }

  // WHAT THE PANE SHOULD BE SHOWING NOW, cache first.
  //
  // Pulled out of onSelChanged because the cursor moving is not the only thing
  // that changes what is under it. Walking INTO a directory usually leaves
  // `sel` exactly where it was — 0 to 0 — so nothing fired, and the pane went
  // on showing the previous directory's peek until something else happened to
  // restart the timer. That is the list that flashes in the right-hand column
  // on the way in: not a flicker of the new preview, but the old one still
  // being drawn.
  // ── NOT WHILE THE COLUMNS ARE MOVING ──────────────────────────────────
  // XAnimator survives GUI-thread work: it keeps its own time on the render
  // thread. What it cannot survive is a scene-graph SYNC, and filling the
  // preview pane builds a column's worth of delegates — which is one.
  //
  // Stepping into a directory asks at once for a peek of whatever row is
  // selected in the new one, and that answer lands a hundred-odd milliseconds
  // later: right at the tail of the slide. One dropped frame, at the same
  // point every time, which is why it reads as a rhythm rather than as jank.
  //
  // THE WHOLE PIPELINE PAUSES, not just its answers. Holding only the settle
  // was the first try and it cost more than it bought: the clearing and the
  // re-fetching still ran mid-slide, so a peek cancelled by one call and
  // re-armed by another could land after the held one was replayed, and the
  // preview of the first row in a directory you had just opened became a coin
  // toss. Nothing is asked for while the columns move, and exactly one
  // request goes out when they stop — which is also the moment the answer
  // could first have been seen.
  property bool previewWanted: false

  Connections {
    target: millerAnim
    // callLater because millerStep stops the animator and starts it again in
    // the same breath: stepping twice quickly would otherwise resume in the
    // gap between the two and land the sync inside the next slide, which is
    // the bump this exists to remove.
    function onRunningChanged() {
      if (!millerAnim.running) Qt.callLater(root.resumePreview);
    }
  }

  // UNCONDITIONAL, and that is the point. Resuming only when something had
  // asked during the slide left the gap this was reported as: the paths that
  // ask BEFORE stepping, and the step that leaves `sel` at 0 so nothing fires
  // at all, both ended a slide with no request outstanding and no preview.
  // Every slide now ends with exactly one refresh; refreshPreview returns
  // immediately when the pane is already showing the right row, so asking
  // when the answer is already in costs nothing.


  function resumePreview() { return preview.resumePreview(); }

  function refreshPreview() { return preview.refreshPreview(); }
  onViewModeChanged: {
    if (root.viewMode === "columns") { preview.previewDelay.restart(); listing.infoDelay.restart(); }
    else { root.previewInfo = null; root.watchPeek(""); }
    root.rememberView();
    root.makeThumbs();
    splitPane.warmAim.restart();
    // one handler per signal, so remembering the view lives here too
    opening.viewSave.restart();
    // viewSave declines to write anything for a dialog, on purpose. This
    // is the one thing about a dialog worth keeping — see pickerView.
    if (root.isPicker) opening.pickerSave.restart();
  }

  // WHICH ROW THE RUNNING PEEK IS ABOUT. "" when nothing is in flight.
  //
  // previewProc is one process reused for every peek, and its output used to
  // be applied to whatever the cursor happened to be sitting on when it
  // finished. Walk down a column faster than a peek returns and the answer for
  // the row you left lands on the row you are on — a directory's listing drawn
  // as if it were this directory's, or as the text of a file. Worse, it was
  // then CACHED under the wrong path, so the ghost outlived the moment: the
  // row went on showing another directory's contents until the cache was dropped.
  // That is the "random dir" the preview sometimes shows, and it is the same
  // fault in the picker, which draws the same pane.
  property string previewFor: ""

  // WHILE THE ROWS ON SCREEN ARE THE ONES BEING LEFT.
  //
  // enter() moves the cursor to the top before it replaces the listing,
  // because the two cannot be written in one statement — and between those
  // two lines `sel` is 0 against the OLD directory's rows. Everything that
  // watches the cursor fired there: the preview settled on row 0 of the place
  // you were leaving, drew its contents in the last column, and was corrected
  // seventy milliseconds later when the real rows arrived. Measured at 1ms
  // in and 77ms out of that wrong listing, every single step.
  //
  // That is the list that flashes. It is not a stale frame and not a missing
  // one: it is a correct preview of the wrong row.
  property bool arriving: false

  // WHICH ROW THE PANE IS ALREADY SHOWING. "" when it is showing nothing.
  //
  // ONE navigation calls into the preview four or five times: the cwd
  // changing, the cursor landing on row 0, the rows themselves arriving, the
  // 30ms debounce behind all three, and the peek watcher aiming at the new
  // row. Each of those called refreshPreview or loadPreview, and each call
  // that did not hit the cache emptied the pane and refilled it a moment
  // later — so opening a directory wrote the preview column four times:
  // blank, right, blank, blank, right. Measured with a counter on every
  // assignment; the two blanks in the middle are the flash.
  //
  // Nothing about the row has changed between those calls, so nothing should
  // be redrawn. This is what they check.
  property string previewShown: ""


  function loadPreview() { return preview.loadPreview(); }

  function beginPeek(path, command) { return preview.beginPeek(path, command); }

  function settlePreview(kind, rows, text, path) { return preview.settlePreview(kind, rows, text, path); }



  // ── what the picture IS ──────────────────────────────────────────────────
  // the functions of this section live in terminus/Listing.qml; these
  // forward to it, so every caller is unchanged
  Listing { id: listing; term: root }
  // The preview pane used to show a picture and nothing else, which answers
  // "which file is this" and none of the questions you actually open a directory
  // of media to ask — how big, how long, what codec.
  //
  // Two probes, one panel: `magick identify` for a still and `ffprobe` for a
  // video. Both were already installed for the thumbnails, so neither adds a
  // dependency, and both are quick enough to run per row PROVIDED they are not
  // run per row — hence the debounce and the cache below.
  property var previewInfo: null
  // Which path the answer on its way belongs to, and which probe was asked.
  // A reply arriving after the cursor has moved on is dropped rather than
  // shown against the wrong file: ffprobe on a large mkv can outlive several
  // keystrokes.
  property string previewInfoFor: ""
  property string previewInfoKind: ""
  property var infoCache: ({})
  property var infoOrder: []

  function cacheInfo(path, info) { return listing.cacheInfo(path, info); }

  // The kind is settled asynchronously — the pane reads the file before it
  // knows it is text — so a probe skipped because previewKind was still
  // "none" has to be asked for again once it is not.
  onPreviewKindChanged: if (root.previewKind === "text" && !root.previewInfo)
    listing.infoDelay.restart()



  function loadPreviewInfo() { return listing.loadPreviewInfo(); }

  function renderPdf(path) { return listing.renderPdf(path); }


  // Two steps, so a keystroke does not re-sort.
  //
  // `sorted` changes when the directory, the sort or the hidden toggle changes
  // — rarely. `view` is that list filtered by what you have typed, and a
  // filter cannot change the order of what survives it. One expression did
  // both, so every character re-sorted the whole directory.
  // SEARCH RESULTS ARE NOT SORTED, and that is the whole of the second half of
  // the search fix.
  //
  // fzf ranks its answers best-first, and this then threw that away and put
  // them back in alphabetical order — so the most relevant hit was wherever
  // its name happened to fall in the alphabet. Between matching whole paths
  // and re-sorting the result, "find" was returning good answers and
  // presenting them as noise.
  //
  // A search result is an ANSWER, not a directory; the hidden-file toggle
  // still applies, because that is about what you want to see rather than
  // about order.
  // Both derived per pane now — see the Pane component, which holds the
  // arrangement, the model and the index for its own half. These two are
  // what the rest of the window means by "the listing": the active one.
  readonly property var sorted: root.act.sorted
  readonly property var view: root.act.view

  // ── the listing, as something the views can be TOLD ABOUT ───────────────
  function rowFor(path) { return listing.rowFor(path); }

  function markedRows() { return listing.markedRows(); }

  function acting() { return listing.acting(); }

  function currentRow() { return listing.currentRow(); }

  function inkFor(e) { return listing.inkFor(e); }

  function nameInkFor(e) { return listing.nameInkFor(e); }

  function nameInkOf(e) { return listing.nameInkOf(e); }

  // Text previews in plato's colours, when plato is part of this shell — see
  // previewCommand in terminus.js. Markdown comes out rendered, as plato
  // draws it (headings, tables, boxes; plato's markdown settings apply).
  readonly property string platoRender: Quickshell.shellDir + "/plato/nvim/render.lua"

  function inkOf(e) { return listing.inkOf(e); }

  // ── THE GLYPH, WITH THE KIND BEHIND IT ────────────────────────────────
  function glyphOf(r) { return listing.glyphOf(r); }

  function enrich(rows) { return listing.enrich(rows); }

  // ── the metadata cells, worked out ON FIRST SIGHT ───────────────────────
  function kindOf(e) { return listing.kindOf(e); }

  function whenOf(e) { return listing.whenOf(e); }

  function sizeTextOf(e) { return listing.sizeTextOf(e); }

  Component.onCompleted: {
    // A FloatingWindow is visible by default, and `shown` starts false, so a
    // freshly created window came up ON SCREEN with nothing having asked for
    // it — the manager makes one at load so SUPER+E always has something to
    // reveal, and that one flashed up on every quickshell start. Nothing
    // synced the two: onShownChanged only fires on a CHANGE, and false never
    // changed. So sync it once here, at construction, before spawn() or pick()
    // has had the chance to set `shown`.
    root.visible = root.shown;
    // Whatever the other windows have already measured — see revealWhenReady.
    if (root.mgr) root.dirSizes = Object.assign({}, root.mgr.sharedSizes);
    // Mounts a previous run left behind — see Terminus.sweepArchivesCommand.
    // Window 0 only: it is the first thing built, so nothing of THIS run
    // can be mounted yet.
    if (root.winId === 0) root.run(Terminus.sweepArchivesCommand(root.archBase));
    root.loadBookmarks();
    // before the first listing: the sort and the hidden-file setting decide
    // what that listing turns into, so reading them afterwards would show one
    // arrangement and then rearrange it in front of you
    root.loadViewPrefs();
    // Both panes start from the one record of what is expanded — mgr.tree.
    if (root.mgr) { paneL.openDirs = root.mgr.tree; paneR.openDirs = root.mgr.tree; }
    // Nothing to wait for when there is no session to replay: the
    // destination applies now rather than after a restore that will not
    // happen. When there IS one, restoreTabs has already been set going by
    // loadViewPrefs and its completion calls takeBoot instead.
    if (!root.sessionReplay || root.winId !== 0) root.takeBoot();
    // ── THE FIRST DIRECTORY GETS ITS OWN VIEW TOO ───────────────────────
    // A directory's remembered view is applied when cwd CHANGES — and the
    // window is born with cwd already at home, so for home it never changed.
    // loadViewPrefs had just put back the view of wherever you were LAST,
    // and home wore it: leave a picture directory in grid, restart, and your
    // home listing came up as a grid of directory icons. Asked once here, for
    // whatever directory the window is actually starting in.
    root.applyDirView();
    root.refresh(true);
  }

  // ── reading the directory ───────────────────────────────────────────────

  // ── A LISTING ASKED FOR WHILE ONE IS OUT IS QUEUED, NOT DROPPED ──────
  // `running = true` on a Process that is already running does nothing — it
  // does not restart it, and it does not pick up the new command. So a
  // refresh that landed while the previous `find` was still out simply
  // vanished: a job finishes and re-reads, inotify fires for the same change
  // a moment later, and if that `find` had started before the last write hit
  // the disk the screen kept its answer until you left and came back. It
  // depended on timing alone, which is why it could not be made to happen.
  //
  // So a request made mid-flight is remembered and run as soon as the one in
  // flight exits, and a listing read for a directory we are no longer in is
  // thrown away rather than drawn under the new cwd.
  property bool listAgain: false
  property string listFor: ""

  function startListing() { return listing.startListing(); }

  function refresh(full) { return listing.refresh(full); }

  // ── the slide ───────────────────────────────────────────────────────────
  // the functions of this section live in terminus/SlideMotion.qml (not
  // Slide: picasso, which this window imports, has a Slide of its own);
  // these forward to it, so every caller is unchanged
  SlideMotion { id: slide; term: root }
  // The columns are dropped to one side by a step and carried home.
  //
  // AN ANIMATOR, NOT A NUMBERANIMATION, and that is the whole of why this
  // used to look like it was running at a third of the frame rate. A
  // NumberAnimation is ticked on the GUI thread — the same thread that, at
  // the exact moment of a step, is parsing a listing, rebuilding a model,
  // enriching a few hundred rows and starting a preview. Every frame that
  // work overran was a frame the slide did not get, so a 260ms travel
  // arrived in four or five visible jumps.
  //
  // XAnimator runs on the RENDER thread. It keeps its own time and moves the
  // item whether or not QML is busy, so the same gesture is smooth through
  // the very work that used to interrupt it. The cost is that `miller.x` is
  // no longer a binding — nothing else writes or reads it, which is what
  // makes that safe.
  //
  // Zenon.travelEase, not Zenon.ease: this is a thing crossing a pane and it
  // is watched the whole way, where the shell's quintic is a curve for things
  // arriving. See the note on the token — quintic here read as a lurch and
  // then a drift, which is what "not tight" was.
  XAnimator {
    id: millerAnim
    target: chrome.miller
    to: 0
    // Through Zenon, so the shell's one motion setting reaches it — this was
    // the last animation in terminus still carrying its own number, which
    // meant turning the whole desktop's motion down left the columns sliding
    // at their old speed.
    //
    duration: Zenon.normal
    easing.type: Zenon.travelEase
  }

  // ── AND IT FADES IN AS IT COMES ──────────────────────────────────────
  // The eye tracks a hard-edged boundary moving across a pane very precisely
  // — precisely enough to read a single late frame as a bump — and cannot do
  // the same to one that is changing opacity. So the arrival is made less
  // trackable exactly where it is least reliable: the first frames, where
  // three models have just been swapped and the scene graph is rebuilding.
  //
  // OpacityAnimator, like the slide, so it runs on the RENDER thread and the
  // two cannot drift apart under GUI-thread work. A fade driven from QML
  // would be the one thing in this transition that could stutter.
  //
  // A CROSS-FADE NOW, NOT A REVEAL. It used to start from nothing, because it
  // was hiding three columns' worth of delegates being rebuilt on every step.
  // They are not rebuilt any more — walking up, two of the three columns keep
  // the rows they already had — so fading all the way out was covering work
  // that no longer happens, and a view that blinks to black and back is doing
  // more to the eye than the movement itself.
  //
  // From millerDim instead: enough to soften the one column that genuinely
  // does change, not enough to read as the view disappearing. Over the FULL
  // length of the slide, so the opacity and the travel finish together —
  // arriving at 0.9 and climbing is invisible, where a fade that ended early
  // left the last stretch of movement at full contrast and drew the eye
  // straight back to it.
  readonly property real millerDim: 0.35

  OpacityAnimator {
    id: millerFade
    target: chrome.miller
    to: 1
    duration: Zenon.normal
    easing.type: Zenon.travelEase
  }

  // The preview pane's own arrival.
  //
  // This had two speeds once — a longer one for arriving in a directory, a
  // short one for walking the cursor down it. The long one was covering a pop
  // that came from the column being EMPTIED mid-navigation, and that stopped
  // happening when syncPreviewRows learnt to leave a hidden column alone. A
  // fade tuned to hide a bug should not outlive the bug.
  //
  // Render thread, so a directory heavy enough to be worth easing in is not
  // the thing that makes its own easing stutter.
  OpacityAnimator {
    id: previewFade
    target: chrome.previewPane
    to: 1
    duration: Zenon.fast
    easing.type: Zenon.travelEase
  }

  // WHICH WAY THE TREE MOVED, from the two paths alone: into a child and the
  // columns travel left, out to a parent and they travel right. A jump to
  // somewhere unrelated — a bookmark, a search result, a tab — is not a step
  // and gets no slide: there is no direction to show, and animating one would
  // claim a relationship between the two places that does not exist.
  readonly property real millerTravel: 0.25

  // ── WHICH COLUMN STANDS WHERE ─────────────────────────────────────────
  // millerOrder[slot] names the INSTANCE in that slot. A step rotates this
  // rather than each column re-deriving its content: walking down, the
  // preview becomes the middle and the middle becomes the parent, and only
  // the far column is handed something it has never held. Two of the three
  // then sync against rows they already have, which is a diff that finds
  // nothing to do — where before all three rebuilt.
  //
  // The rotation must happen BEFORE the row sources move, or the column about
  // to leave the middle would first sync itself to the new directory and
  // rebuild for nothing. millerStep runs at the top of enter(), ahead of the
  // cwd and the seed, which is why it lives there.
  property var millerOrder: [0, 1, 2]

  function millerRotate(down) { return slide.millerRotate(down); }

  // The rows each SLOT shows. Bound by slot rather than by instance, so a
  // column picks up whatever its new slot is about the moment it rotates.
  readonly property var millerRowsParent: root.viewMode === "columns"
    ? (root.parentRows || []) : []
  readonly property var millerRowsCurrent: root.viewMode === "columns"
    ? (root.act.view || []) : []
  readonly property var millerRowsPreview:
    (root.viewMode === "columns" && root.previewKind === "dir")
      ? (root.previewRows || []) : []

  // The instance standing in a given slot, for the code that needs to measure
  // the middle column or scroll the parent. Expressions, not a function: a
  // binding does not re-evaluate on a call, so it would never see a rotation.
  readonly property var parCol: root.millerOrder[0] === 0 ? chrome.colA
    : (root.millerOrder[0] === 1 ? chrome.colB : chrome.colC)
  readonly property var midCol: root.millerOrder[1] === 0 ? chrome.colA
    : (root.millerOrder[1] === 1 ? chrome.colB : chrome.colC)

  // True from the moment a step is taken until the slide it starts has
  // finished. The travel is queued a tick late now (see millerStep), so
  // millerAnim.running is briefly false during a step it is about to run —
  // and everything that defers work "while the columns move" has to keep
  // deferring across that gap or it will fire in it.
  property bool stepping: false

  function startTravel(down) { return slide.startTravel(down); }

  function millerStep(from, to) { return slide.millerStep(from, to); }

  function landWanted() { return slide.landWanted(); }

  function goTo(path) { return slide.goTo(path); }

  // ── WHERE IT ACTUALLY LIVES ─────────────────────────────────────────────
  function reveal() { return slide.reveal(); }

  // ── THE HISTORY, WRITTEN HERE AND NOWHERE ELSE ─────────────────────────
  function markTrailSel() { return slide.markTrailSel(); }

  function pushTrail(path) { return slide.pushTrail(path); }

  readonly property bool canBack: root.act.trailAt > 0
  readonly property bool canForward:
    root.act.trailAt >= 0 && root.act.trailAt < root.act.trail.length - 1

  function travelTo(ref) { return slide.travelTo(ref); }

  function back() { return slide.back(); }

  function forward() { return slide.forward(); }

  function aimAt(dir) { return slide.aimAt(dir); }

  function enter(path) { return slide.enter(path); }

  // The path to put the cursor on once the next listing arrives. A directory
  // is not in the list yet when you ask to leave it, so the wish is recorded
  // and the listing honours it.
  property string wantSel: ""

  // The raw output the current rows were built from, for the comparison above.
  //
  // `var` holding null rather than an empty string, and that is not a style
  // choice. "" was the sentinel for "nothing loaded yet" — but "" is also
  // exactly what `find` prints for an EMPTY DIRECTORY, so walking into one
  // compared "" against "", decided nothing had changed, and left the previous
  // directory's rows on screen under the new breadcrumb. null can never be a
  // listing, so it can never collide with one.
  readonly property var lastListing: root.act.lastListing

  function goUp() { return slide.goUp(); }

  // Bumped every time something is OPENED — Return, or a double click. A
  // counter rather than a signal because a delegate can bind to a property and
  // cannot connect to a signal it has no reference to — see the note over
  // openMenuAt for the same trap.
  //
  // This is the only thing the row sweep and the tile flare hang off, and it
  // took two goes to get there. The sweep was fired by the CURSOR MOVING, on
  // the theory that a highlight arriving fully formed is hard to follow at
  // speed. But moving the cursor is not an event worth animating: it happens
  // on every j and k, on every click, and on the pointer drifting across the
  // list — and a light washing over a row you were only passing through reads
  // as the list flashing at the pointer. Opening something is the event. The
  // grid's tiles had always been drawn this way; the list rows now agree.
  property int openPulse: 0
  // and one for a row that has just been created, so it can announce itself
  property int madePulse: 0

  // ── AND ONE FOR COMING BACK FROM A WORKSPACE THAT WAS NOT THIS ONE ──
  //
  // The cursor bars travel on XAnimator/YAnimator, which run on the RENDER
  // thread — and the render thread stops when the compositor stops asking this
  // window for frames, which is exactly what switching away to another
  // workspace does. A travel in flight at that moment is cut off where it
  // stood. Coming back does not finish it: the binding behind the bar never
  // changed value, so nothing re-writes it, and the bar sits BETWEEN two rows
  // until the cursor is moved again. Measured off a 60fps capture of column
  // view — rows are 28px, and the bar came back at y=55 against a row at 62 and
  // stayed there for the remaining 170 frames.
  //
  // Qt is never told any of this happened: neither `visible`,
  // `backingWindowVisible` nor `Window.active` moves across a workspace
  // switch — probed, all three. Hyprland is the only one who knows, and the
  // rest of this shell already asks it.
  property int thawPulse: 0
  Connections {
    target: Hyprland
    function onFocusedWorkspaceChanged() { root.thawPulse++; }
  }

  function activate() { return slide.activate(); }

  // ── OPENING A FILE, AND ASKING WHEN NOTHING WILL ────────────────────────
  // Not through root.run: that is the action queue, and every action's exit
  // re-reads the directory — an open changes nothing in it. A process of its
  // own per open, because two quick opens must not wait on each other, and
  // this one has to be HEARD: when gio says nothing is registered for the
  // file's type the open-with card comes up for that file, where it used to
  // fail into /dev/null and leave you double-clicking a file that did
  // nothing. See Terminus.openOrAskCommand.
  Component {
    id: openerProc
    Process {
      property string path: ""
      onExited: (code) => {
        if (code === Terminus.NO_HANDLER) root.beginOpenWith(path, true, true);
        else if (code !== 0) root.status = "could not open " + Terminus.basename(path);
        destroy();
      }
    }
  }

  function openFile(path) { return slide.openFile(path); }

  function followLink(path) { return slide.followLink(path); }


  // ── ARCHIVES, AS DIRECTORIES ────────────────────────────────────────────
  // Mounted read-only by ratarmount and walked into — see the note over
  // Terminus.mountOf for why nothing past this point knows the difference,
  // and for the three questions (what to show, where up goes, the crumbs)
  // that are asked through archMounts instead of about the raw path.
  property var archMounts: ({})       // mount point -> archive path
  readonly property string archBase:
    (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/terminus/archives"

  function shownPath(dir) { return slide.shownPath(dir); }
  function parentOf(dir) { return slide.parentOf(dir); }

  function enterArchive(r) { return slide.enterArchive(r); }


  // ── AND PUT AWAY WHEN NOTHING IS IN THEM ─────────────────────────────

  // ── running things ──────────────────────────────────────────────────────
  // the functions of this section live in terminus/Selecting.qml; these
  // forward to it, so every caller is unchanged
  // Selecting, not Selection: plato's editor has a Selection of its own and
  // imports terminus — a terminus Selection shadowed it and broke plato
  Selecting { id: selection; term: root }
  // One process with a queue, so two verbs fired in quick succession cannot
  // interleave their output or race each other onto the same directory. Every
  // one of them re-reads the directory when it lands, because all of them
  // change what is in it.
  property var queue: []


  function run(cmd) { return selection.run(cmd); }

  function drain() { return selection.drain(); }

  // ── selection ───────────────────────────────────────────────────────────
  // Where a shift-range starts: the row the cursor was last put on by
  // anything OTHER than a shift-click — a plain click, a ctrl-click, the
  // arrow keys, a landing. Shift-click alone leaves it where it is, so
  // shift-clicking twice extends from the same place both times rather than
  // walking the anchor along behind you.
  //
  // A PATH, NOT AN INDEX, and not moved by plain clicks alone. It was an
  // index only a plain click set, so a range started from wherever you last
  // clicked rather than from the row you had arrowed or ctrl-clicked onto —
  // from row 0 in a directory you had not clicked in yet, and from a
  // different row altogether once a branch opened above it and pushed every
  // index down. The row the range began on was simply not in it. Read back
  // through anchorIndex(), which falls back to the cursor when the row is not
  // in this listing.
  property string anchorPath: ""
  // raised while a shift-click moves the cursor, so onSelChanged leaves the
  // anchor behind — see clickRow
  property bool holdAnchor: false

  function setAnchor(i) { return selection.setAnchor(i); }

  function anchorIndex() { return selection.anchorIndex(); }

  // True while the pointer is over a row or a tile. The drag box asks this
  // rather than guessing from coordinates: "was the cursor actually on top of
  // the item" is exactly the question, and the items themselves know.
  property bool hoverRow: false
  // Set by the body's HoverHandler from the view's own hit test. Starts true so
  // a click that arrives before any hover still reaches the empty-space
  // handler rather than falling into a gap.
  property bool overEmpty: true
  // Whether the pointer is somewhere a rubber band would mean anything. See
  // band.zoneL/zoneR — written by the hover handler that watches the body.
  property bool overBandZone: true
  // The narrowest a listing can be and still hold three columns. Below it the
  // size and date are dropped rather than squeezed into each other.
  readonly property real metaMinWidth: 420

  // The ink the CURRENT path segment is written in. Named because the hint
  // bars use it too: a bind's description and the directory you are standing in
  // are both "the thing this window is about right now", and they were two
  // hard-coded greys that happened to differ.
  readonly property color crumbInk: Zenon.keyInk

  // ── the mouse, as a glyph ─────────────────────────────────────────────
  // "middle click" is three syllables of hint sitting next to a two-word
  // entry, and the F1 list had "right click", "click" and "mouse 4 / 5" all
  // saying the same noun a different way.
  //
  // There is no per-button mouse glyph in the font, so the button is the
  // NUMBER beside it — the notation the keymap was already using for
  // "mouse 4 / 5", and the numbering this machine actually uses: evdev orders
  // them BTN_LEFT, BTN_RIGHT, BTN_MIDDLE (272, 273, 274), which is what
  // hyprland binds against. So 1 left, 2 RIGHT, 3 MIDDLE — not X11's order,
  // where 2 and 3 are the other way round.
  readonly property string mouseGlyph: "\uEFBA"
  function mouseKey(button) { return selection.mouseKey(button); }

  // ── the list's columns ──────────────────────────────────────────────────
  //
  // ONE set of fractions, read by the headings and by the rows, so a cell is
  // always under the heading that names it. Fractions of the INNER width: a
  // Row's padding comes out of its children's space, so subtracting the 24px
  // first is what makes the arithmetic exact at any width.
  //
  // Search gets a set of its own. A result is a PATH, not a name — where it
  // was found is half the answer and the reason the search was run — so the
  // column appears with the results and goes away with them. NAME gives up the
  // room for it: the numbers were already the narrowest things on the row.
  // ── TWO COLUMNS TAKE WHAT THEY NEED; THE REST STILL SHARE ───────────
  // KIND and MODIFIED hold content with a known longest form. Measured at
  // 14px in this face: "broken link" is 94px and "2026-07-05" is 86, and
  // neither grows past that however wide the window is. A fraction of the
  // row cannot be right for either at more than one size — MODIFIED's 0.24
  // was 96px at the narrowest listing that shows metadata at all, and over
  // 400 in a maximised window, three quarters of it empty.
  //
  // SIZE IS NOT ONE OF THEM, and that is deliberate rather than an
  // oversight. The number is short but the column also carries the usage
  // bar drawn behind it, and a bar is a picture of a proportion — it wants
  // as much room as the window can spare, the same as it always had.
  //
  // So size keeps its own fraction of the full width exactly as before,
  // the two fixed columns take their pixels, and everything freed goes to
  // NAME: the one column whose content has no upper bound and the one
  // actually being read.
  //
  // With the zoom, like every other measurement on a row.
  readonly property int colKindW: Math.round(100 * root.zoom)
  // 112, not 94. The times used to be right-aligned and flush with the
  // window, so the column only had to be as wide as the longest one —
  // "2026-07-05" at 13px is about 78 of the 94. Left-aligned, that same 94
  // puts the far end of a full date within a couple of pixels of the edge
  // of the window, and the extra width is what becomes the air after it.
  readonly property int colTimeW: Math.round(112 * root.zoom)

  function colWidths(inner, f) { return selection.colWidths(inner, f); }

  readonly property var colPlain:
    ({ name: 0.44, where: 0.0, kind: 0.14, size: 0.18, time: 0.24 })
  readonly property var colFound:
    ({ name: 0.30, where: 0.24, kind: 0.10, size: 0.16, time: 0.20 })
  // AND THE SAME ANSWER FOR A NARROW PANE. The miller layout's middle column
  // is a third of a pane wide, so it has always been drawn with no metadata at
  // all — which is right for a directory, where the name is the whole of what
  // distinguishes a row, and wrong for RESULTS, where it is not. A search in
  // columns view showed two files of the same name as two identical rows and
  // no way to tell which was which; that is the exact failure the WHERE column
  // was written for, and it was the one view that could not draw it.
  //
  // The numbers give up their room rather than the name: a size and a date are
  // what you can still get from the preview pane beside it, and where the file
  // actually is, is not.
  // Half and half. The first split gave WHERE the larger share on the grounds
  // that it is the disambiguating column — and turned "terminus.js" into
  // "ter….js", which disambiguates nothing because you can no longer read what
  // it is. A name has a length a file type puts a floor under; WHERE elides
  // from the FRONT and stays useful at any width, so it is the one that can
  // afford to give room back.
  readonly property var colFoundNarrow:
    ({ name: 0.52, where: 0.48, kind: 0.0, size: 0.0, time: 0.0 })
  // True while a scrollbar has the pointer. The rubber band stands down for
  // it — see ScrollRail's own note.
  property bool railDragging: false
  // True while the pointer is ON a scrollbar. The rail lies OVER the rows, so
  // a press there is also a press on a row — and a row's DragHandler is
  // allowed to take a grab away from the MouseArea that already accepted it,
  // which is why the first stroke down the bar also picked the file up and
  // started carrying it. preventStealing holds off the Flickable but says
  // nothing to a handler. Arming on HOVER rather than on the drag closes the
  // window entirely: by the time a drag is recognised the grab is long gone.
  property bool railHover: false

  // How far one notch of the wheel moves the list. Rows are root.rowH tall, so
  // this is "about four rows" at the default zoom — enough that a long directory
  // does not need a dozen strokes, short enough to stop where you meant to.
  readonly property real wheelStep: Math.round(root.rowH * 4)


  function wheelTarget(bx, by) { return selection.wheelTarget(bx, by); }

  function rowUnder(bx, by) { return selection.rowUnder(bx, by); }

  function viewUnder(bx) { return selection.viewUnder(bx); }
  // true for the whole of a row being dragged out, so the overlays that watch
  // hoverRow do not wake up when the pointer leaves the row it picked up
  property bool draggingRow: false

  // ── while a card has the screen ─────────────────────────────────────────
  // the functions of this section live in terminus/Cards.qml; these
  // forward to it, so every caller is unchanged
  Cards { id: cards; term: root }
  //
  // Three layers keep a dialog modal and this is the third. InputShield stops
  // the POINTER, dialogKeys stops the KEYBOARD, and neither stops a
  // DragHandler: a pointer handler is allowed to take a grab away from an item
  // that has already accepted the press, and rowDrag/tileDrag are declared
  // with permissive enough grabs to do exactly that. So a press on a row
  // behind an open dialog still started a drag, complete with the card
  // following the cursor over the top of the panel.
  //
  // Handlers cannot be shielded, only switched off — so they read this.
  // ── HOW SOFT THE WINDOW GOES BEHIND A CARD ─────────────────────────────
  // The keymap already did this and it was the right idea in the wrong number
  // of places: a card standing on a flat wash of black has no depth behind it,
  // and dimming hides the thing you are deciding about instead of setting it
  // back. So every card that takes the window over softens it, and by its OWN
  // fade — the strongest one wins, so two cards overlapping never double the
  // blur or flicker as one of them leaves.
  //
  // sendTo is deliberately NOT here. A picker is about the listing behind it;
  // blurring that would hide the thing the choice is being made against, which
  // is the same reason it has no scrim.
  // ── THE WINDOW BEHIND A CARD IS DARKENED, NOT BLURRED ─────────────────
  // The body used to go soft under a card while this took a little of the
  // contrast out on top. The cards float in the middle of the window now,
  // and the window behind is simply set back: the whole of it, chrome
  // included, darkened under the card's overlay. Strong enough to do the
  // job on its own, since there is no blur left to share it.
  readonly property color cardScrim: Zenon.darken(0.55)

  // ── WHAT THE OPEN SHEET IS ABOUT, SAID ON THE BAR ──────────────────────
  // Every one of these cards opened with a coloured caption band across its
  // own top — the same idea the send picker had before its header moved to
  // the chrome. A sheet hangs FROM the bar, so the bar is where it says what
  // it is: the band comes off the card, the breadcrumb steps aside, and the
  // sheet is left as the thing it actually is rather than a titled box.
  //
  // THE THING, NOT THE WORD, everywhere it can be. "Properties" tells you
  // what you already know; the filename is the one fact the card is about.
  readonly property string sheetTitle: {
    // THE QUESTION, which is the whole of what the card is about — it was
    // the card's first line, and the bar is where a sheet's name goes now.
    if (confirm.open) return confirm.heading;
    if (props.open)
      return props.many ? props.rows.length + " items"
        : (props.rows[0] ? props.rows[0].name : "Properties");
    if (bulk.open)
      return bulk.names.length === 1 ? "Rename 1 item"
        : "Rename " + bulk.names.length + " items";
    // THE FILE, not its type. The card led with the mime — "Open text/plain
    // with" — on the reasoning that the choice outlives this one file, and
    // what that actually put on the bar was a string with a slash in it where
    // a filename was expected.
    if (appPick.open)
      return appPick.paths.length > 1 ? "(multiple files)"
        : Terminus.basename(appPick.path);
    // The one sheet that is about the WINDOW rather than about a file, so it
    // is the one whose title is a word.
    if (prefs.open) return "Settings";
    if (cmdPalette.open) return "Commands";
    if (marks.open) return "Bookmarks";
    if (disks.open) return "Disks";
    if (plug.open) return plug.rows.length > 1 ? plug.rows.length + " new disks" : "New disk";
    if (diskInfo.open) return diskInfo.cur ? diskInfo.title : "Disk";
    if (diskTool.open)
      return (diskTool.mode === "format" ? "Format " : "Check ")
        + (diskToolBody.title !== "" ? diskToolBody.title : "disk");
    // Named for what it is ABOUT, not for the verb: the card is open over a
    // selection and how many is the thing you want confirmed before you tag
    // them. The footer says it too, and the bar is where the eye already is.
    if (tagPick.open)
      return tagPick.targets.length === 1
        ? "Tag 1 item" : "Tag " + tagPick.targets.length + " items";
    if (collEdit.open)
      return collEdit.searching
        ? (collEdit.naming ? (collEdit.hangs ? "Save Search as Collection" : "New Collection")
           : (collEdit.searchKind === "grep" ? "Search Contents" : "Search"))
        : (collEdit.making ? "New Collection" : "Collection");
    return "";
  }

  // A glyph ahead of the title, for the sheets that want one. Empty is the
  // answer for most of them: a card about a file says so by naming it, and
  // a picture beside the name would be saying it twice.
  //
  // Properties and permissions are the exception, and only for a single item.
  // The name in the bar is the whole of what those two cards are about, and
  // the glyph is how the row beside it was already being read — so the header
  // shows the file the way the listing showed it. Several at once have no one
  // glyph, and the title says "6 items" rather than a name.
  readonly property string sheetGlyph: {
    if (confirm.open)
      return confirm.choices.length > 0 ? confirm.verbGlyph(confirm.choices[0].label) : "";
    // The question's own mark — see confirm.verbGlyph, which keys it off the
    // same word verbInk keys the colour off.
    // The file's own glyph when there is one file. The generic mark is for
    // the case that has no file to show — several of them at once.
    if (appPick.open)
      return appPick.icon !== "" ? appPick.icon : "\uEC65";
    if (props.open && !props.many && props.rows[0])
      return props.rows[0].glyph !== undefined ? props.rows[0].glyph : "";
    // A VERB, not a file. Rename is always about several — one name is the
    // in-place edit — so there is no row's glyph to show and this says what
    // the card does instead.
    if (bulk.open) return "\uEC61";
    // The mark itself, the one the listing and the sidebar put beside a
    // bookmarked row — so the sheet is labelled with the thing it holds.
    if (marks.open) return "\uF02E";
    // nf-fa-tag, the same mark the sidebar will list them under
    if (tagPick.open) return "\uF02B";
    if (collEdit.open)
      return collEdit.searching && !collEdit.naming ? "\uF002" : "\uEC78";
    // the same disk mark the sidebar and the rows use
    // the disk's own mark, as its row in the sidebar wears it
    if (diskInfo.open)
      return diskInfo.cur && (diskInfo.cur.removable || diskInfo.cur.hotplug)
        ? "\uF0A0" : "\uF1C0";
    if (disks.open) return "\uF1C0";
    if (plug.open) return "\uF0A0";
    if (diskTool.open) return diskTool.mode === "format" ? "\uF1C0" : "\uF0AD";
    return "";
  }

  // PUNCTUATION IS NOT THE SUBJECT. Where the glyph is the row's own it wears
  // the row's ink with the name — but rename's is a verb standing in for a
  // row that does not exist, so it takes crumbInk, the ink the step you are
  // standing on uses. The send header's verb and arrow are inked the same way
  // and for the same reason.
  readonly property color sheetGlyphInk:
    confirm.open ? (confirm.choices.length > 0 ? confirm.choices[0].ink : Zenon.sand)
    : bulk.open ? root.crumbInk
    // The tag under the cursor, on the mark only — see sheetTitleInk.
    : (tagPick.open && tagPick.chosen() !== "") ? root.tagInk(tagPick.chosen())
    : root.sheetTitleInk



  // ── THE HEADER IS INKED LIKE THE ROW IT IS ABOUT ───────────────────────
  // Glyph and name together, the way a row is inked everywhere else in this
  // window: a directory cyan, an archive yellow, a broken link red. The bar
  // was titling everything cyan, which made a card about a tarball look like
  // a card about a directory.
  //
  // Only where there IS one row. Several at once have no colour of their own
  // — the title says "6 items", which is not a file and is not inked like one.
  //
  // The confirm card is the exception it always was: its band wore the
  // PRIMARY choice's colour so the card read as dangerous exactly when what
  // it offered was, and that survives the move to the bar.
  readonly property color sheetTitleInk: {
    // The question in white with its mark in the verb's colour, as the
    // card wrote it: the mark carries the danger, the words are the words.
    if (confirm.open) return Zenon.white;
    if (diskTool.open) return diskTool.mode === "format" ? Zenon.red : Zenon.cyan;
    if (appPick.open && appPick.icon !== "") return appPick.iconInk;
    if (props.open && !props.many && props.rows[0])
      return root.nameInkFor(props.rows[0]);
    // SAND, which is what a bookmark is inked everywhere else in this window:
    // the ribbon on a listing row, the one in the sidebar, the one in the go
    // sheet. Cyan is the ink of a place you are going; this card is about the
    // marks themselves, so it wears their colour.
    if (marks.open) return Zenon.sand;
    // The colour of the tag the cursor is on goes on the MARK, so the bar's
    // tag IS the tag being chosen — and the words stay white, the way the
    // confirmation writes its question: "Tag 1 item" is not a tag, and in
    // red it read as a warning.
    if (tagPick.open) return Zenon.white;
    return Zenon.cyan;
  }

  // ── NOTHING HANGS FROM THE BAR ANY MORE ─────────────────────────────────
  // The sheets float (see Sheet.floating), so the bar keeps its hairline
  // whole, its own colour and its crumbs: a sheet no longer touches it and
  // carries its title on its own card. The splice the bar's edge used to
  // open for a sheet, and the tally of which sheet was "on" it, went with it.

  // ONE ANSWER TO "IS A SHEET UP", and everything the bar does about it reads
  // this. The strip goes black, the breadcrumb stands down and the sheet's own
  // title fades in — three effects of one fact, which were three expressions
  // naming the picker and the dialogs separately until they disagreed.
  //
  // ── AND NOW THEY SPLICE AGAIN (2026-10-05) ─────────────────────────────
  // Frosted glass made the old look worth having back: every sheet hangs
  // from the bar (Sheet.splice), and the bar goes black while one is down,
  // its hairline open over the card, so the two read as one piece. Each
  // sheet reports its ink and where its card is drawn; the strongest wins.
  // The bar carries the card's title again (see barTitle), and the crumbs
  // stand down for it (chromeInk).
  property real sheetInk: 0
  property real spliceX: 0
  property real spliceW: 0
  property var sheetInks: ({})
  function noteSheet(key, ink, x, w) { return cards.noteSheet(key, ink, x, w); }

  // ── THE BAND A SHEET HANGS FROM ────────────────────────────────────────
  // Every strip of chrome above an open sheet goes the sheet's own colour, so
  // the header and the card read as one piece with a seam in it rather than
  // as a black card under a grey bar. Tinted rather than switched, off the
  // sheet's arrival, so it darkens at exactly the rate the sheet does — and
  // at full strength the tint is opaque black, which is what Zenon.black is
  // and therefore what the card is.
  //
  // One expression, because there is more than one strip: the path bar always,
  // the tab strip whenever there are two tabs, and they must not disagree.
  //
  // THE SIDEBAR'S GROUND, now that the two sit side by side across the top
  // of the window: a bar in headBg beside a sidebar in sidebarBg was two
  // greys meeting at the seam. sidebarBg is black at a quarter, so going
  // solid behind a sheet is that same black rising to full.
  // ── THE BAR IS THE SHEET'S TITLEBAR (2026-10-05) ────────────────────
  // Every sheet hangs from the path bar again with no header of its own,
  // and the bar BECOMES its header: the toggles, the crumbs, the filter and
  // the counts all stand down (crumbBar.chromeInk) and the sheet's name
  // stands in their place, centred over the card — so with the sidebar out
  // or in, the title sits over what it names.
  //
  // LATCHED, as Sheet latches its own: sheetTitle empties the moment the
  // sheet is told to go, and the title has to stay through the fade out.
  // Taken afresh whenever something opens — so a sheet with no name (the
  // confirmation, whose question is its card) does not wear the last one's —
  // and whenever a name arrives while one is up.
  property string barTitle: ""
  property string barGlyph: ""
  property color barTitleInk: Zenon.cyan
  property color barGlyphInk: Zenon.cyan
  // the send picker's sentence instead of a title
  property bool barSend: false
  function latchBar() { return cards.latchBar(); }
  onModalChanged: if (root.modal) root.latchBar()
  onSheetTitleChanged: if (root.sheetTitle !== "") root.latchBar()
  onSheetGlyphChanged: if (root.sheetTitle !== "") root.latchBar()
  onSheetTitleInkChanged: if (root.sheetTitle !== "") root.latchBar()
  // ITS OWN HANDLER. Latching only on the title's change read the glyph's
  // ink before that binding had caught up, so the mark kept the colour of
  // the tag the cursor had just LEFT — or cyan, from when the sheet opened.
  onSheetGlyphInkChanged: if (root.sheetTitle !== "") root.latchBar()
  Connections {
    target: sendTo
    function onOpenChanged() { if (sendTo.open) root.latchBar(); }
  }

  readonly property color chromeBg: Zenon.mix(root.sidebarBg, Zenon.ground, root.sheetInk)
  // ── THE TAB STRIP KEEPS PLATO'S GREY ────────────────────────────────
  // The strip wore chromeBg with the bar, and the tabs say which is which by
  // shading the inactive ones back over it — over black at a quarter that
  // shade is black on black, and every tab looked the same. So the strip is
  // headBg, as plato's is (plato/editor/TabBar.qml): the active tab is that
  // grey showing through, the others darker. Solid black behind a sheet,
  // the same way chromeBg goes.
  readonly property color tabBg: Zenon.mix(Zenon.tabHere, Zenon.ground, root.sheetInk)


  readonly property bool modal: root.looking || cmdPalette.open || marks.open
    || disks.open || plug.open || diskInfo.open || tagPick.open || collEdit.open
    || props.open || confirm.open || diskTool.open
    || sendTo.open
    || bulk.open || prefs.open
    || appPick.open

  // Built when the path changes, not when a crumb is drawn. The delegate asked
  // crumbs() for its own length, so rendering n crumbs cost n+1 walks of the
  // path on every repaint.
  // Through archMounts, so inside an archive the crumbs spell the archive's
  // path rather than a hashed one in /run — see Terminus.archiveCrumbs.
  // ── A DRAG OVER THE BREADCRUMBS ─────────────────────────────────────
  // The step under a drag, or "". Held for springMs it is gone to — but not
  // the step you are already in, and never one the drag is carrying (the
  // same rule springCheck keeps for directory rows). Safe mid-drag for the
  // reason opening a directory on hold is: the drag lives on dragProxy.
  property string crumbDropPath: ""

  function crumbHover(path, arm) { return cards.crumbHover(path, arm); }


  // ── THE WAY BACK DOWN ───────────────────────────────────────────────
  // The deepest directory on the line you are walking. Going up — a crumb,
  // `h`, a drag held on a step — leaves it where it was, and the steps
  // between here and there stay on the trail, dimmed, to be clicked,
  // dropped on or held on to go back down. Going anywhere OFF that line
  // (a sibling, a bookmark) starts a new one. The way Nautilus does it.
  // Kept per pane and carried with the tab — see Pane.crumbDeep.
  readonly property string crumbDeep: root.act.crumbDeep

  readonly property var crumbList: {
    const here = Terminus.archiveCrumbs(root.cwd, Paths.home(), root.archMounts);
    const deep = root.crumbDeep;
    if (deep === "" || deep === root.cwd || here.length === 0) return here;
    const all = Terminus.archiveCrumbs(deep, Paths.home(), root.archMounts);
    // the two trails have to agree up to here, or the tail is not a way
    // down from HERE — an archive mount can make them disagree
    if (all.length <= here.length
        || String(all[here.length - 1].path) !== String(here[here.length - 1].path))
      return here;
    return here.concat(all.slice(here.length).map((c) =>
      ({ label: c.label, path: c.path, ghost: true })));
  }

  // How many are ticked, without building the list of them. The status line
  // wants a number, and markedRows scans the whole view to produce an array —
  // which it was doing on every pointer move of a drag-select.
  // Counted against the VIEW, not against the raw map.
  //
  // A filter narrows what every verb acts on — markedRows() has always walked
  // the view — so a header reading "12 selected" while `d` would trash three
  // of them was the window misreporting its own state. Marks made before the
  // filter was typed are KEPT rather than dropped: they stop being counted
  // while they are out of sight and come back the moment it clears.
  readonly property int markedCount: {
    const v = root.view;
    const m = root.marked;
    let n = 0;
    for (let i = 0; i < v.length; ++i) if (m[v[i].path]) n++;
    return n;
  }

  function markRange(a, b) { return cards.markRange(a, b); }

  function markAt(i) { return cards.markAt(i); }

  // The three clicks every list in every file manager has:
  //   plain  — go here, and drop whatever was selected
  //   ctrl   — add or remove this one, keep the rest
  //   shift  — everything from the anchor to here
  //
  // Right-click is deliberately none of them: you right-click a selection to
  // act on it, so clearing it first would make the menu act on one file.
  //
  // A PLAIN CLICK SELECTS WITHOUT TICKING — the row is only "selected"
  // because acting() falls back to the cursor while nothing is marked. So the
  // first ctrl-click after it has to tick that row too, or the selection you
  // were adding to quietly becomes just the new row and the first one has to
  // be clicked again. Only a row a plain click landed on, remembered by path:
  // the cursor sitting on row 0 after entering a directory was never chosen.
  property string clickedPath: ""

  function clickRow(i, right, shift, ctrl) { return cards.clickRow(i, right, shift, ctrl); }

  // ── visual mode ───────────────────────────────────────────────────────
  // yazi's `v`. An anchor is dropped where the cursor stands and everything
  // between it and the cursor is selected as the cursor moves; `v` again stops
  // extending and leaves the selection exactly as it is, and Escape does the
  // same before it gets as far as clearing anything.
  //
  // WHAT WAS ALREADY MARKED IS KEPT SEPARATELY, in `visualBase`, and the range
  // is laid over a copy of it on every move. That is the difference between a
  // selection you can extend and one that only ever grows: walking back down
  // the range releases the rows the range no longer covers, without releasing
  // the ones that were marked before visual mode started.
  //
  // The anchor is its own property rather than the `anchor` shift-click uses,
  // because the two are live at the same time and mean different things — one
  // is where the last plain click landed, this one is where `v` was pressed.
  property int visualAt: -1
  property var visualBase: ({})
  readonly property bool visualOn: root.visualAt >= 0

  function toggleVisual() { return cards.toggleVisual(); }

  function endVisual() { return cards.endVisual(); }

  function extendVisual() { return cards.extendVisual(); }

  function toggleMark() { return cards.toggleMark(); }

  function gridCols() { return cards.gridCols(); }

  function moveSel(delta) { return cards.moveSel(delta); }


  // ── the verbs ───────────────────────────────────────────────────────────
  // the functions of this section live in terminus/Clipboard.qml; these
  // forward to it, so every caller is unchanged
  Clipboard { id: clipboard; term: root }
  function yank(op) { return clipboard.yank(op); }

  Process { id: clipCopyProc }

  // ── what the SYSTEM clipboard is holding ────────────────────────────────

  function pasteFrom(kind, paths, op) { return clipboard.pasteFrom(kind, paths, op); }


  // ── DECIDED ONCE, AT THE GESTURE ──────────────────────────────────────
  // destDir is read again after the conflict scan comes back, and a scan is
  // a process: leave it reading the cursor live and moving the cursor while
  // it ran would check one directory for clashes and write into another.
  // Latched into pasteDest, which every other deliberate destination already
  // uses and which commitPaste clears.

  function paste() { return clipboard.paste(); }

  function pastePending() { return clipboard.pastePending(); }
  // this paste's share of the pending list, when some of it stayed put
  property var pasteOnly: null
  // What the scan found already in the destination — see commitPaste for
  // why the undo record needs to know.
  property var pasteClash: []

  // ── transfers in flight, all of them at once ────────────────────────────
  //
  // They used to QUEUE: one Process, one `job`, and anything started while it
  // ran went into a list and waited. That was the safe reading of "two rsyncs
  // writing the same destination race over the same names", and it cost you
  // the obvious thing — a copy off a slow disk and an extract on a fast one
  // have nothing to do with each other, and making the second wait for the
  // first is the file manager inventing a dependency that does not exist.
  //
  // So: one Process PER JOB, created when the job starts and destroyed when it
  // exits. Nothing is serialised.
  //
  // THE RACE IS REAL AND IT IS NARROW. Two jobs landing in the same directory
  // can each be told a name is free, because the conflict scan that answered
  // ran before the other job had written it. That needs both to be aimed at
  // one directory AND to carry a colliding basename; short of that they touch
  // nothing in common. It is worth knowing about and it is not worth making
  // every unrelated pair of transfers take turns.
  //
  // ── why a ListModel and not a list ────────────────────────────────────
  // A `property var` holding an array has to be REPLACED to be seen changing,
  // and a Repeater over a replaced array rebuilds every delegate. rsync
  // reports progress several times a second, so the drawer would have thrown
  // its rows away and built new ones at that rate: the width animation on
  // each bar would never once get to run, and a row highlighted under the
  // pointer would drop its highlight on the next line of output.
  //
  // A ListModel is edited in PLACE. set() touches the roles it is given and
  // the delegate that is already on screen simply re-reads them.
  // ── THE JOBS THEMSELVES LIVE IN MORPHEUS ─────────────────────────────
  // See morpheus/Jobs.qml. They used to be this window's — its ListModel,
  // its Processes — so retiring a spare window took its running copies down
  // with it, and with every window closed there was nothing to show what was
  // still going. This window builds the command and hands it over; the
  // drawer reads Jobs, and so does the bar.
  //
  // Whether the pointer is on the drawer's glyph, and whether it is on the
  // card. Two items, one question — the drawer stays open while the pointer
  // is over EITHER.
  property bool jobsOverGlyph: false
  property bool jobsOverCard: false

  // A job ended, in this window or any other: whatever this window is
  // showing may be where it wrote.
  Connections {
    target: Jobs
    function onEnded(id, op, code, cancelled, dest) {
      // A cancel is a nonzero exit too, and you are the thing that went wrong.
      if (code !== 0 && !cancelled && root.shown)
        root.warn(op === "archive" ? "archive failed"
                     : op === "extract" ? "extract failed" : "transfer failed");
      // `status` is sticky, so "3 to copy" would outlive the copy otherwise
      if (code === 0 && root.status !== "") root.status = "";
      if (!root.shown) return;
      root.refresh();
      // refresh() re-reads cwd alone, so a copy into an open branch never
      // showed, and a directory that was empty kept no chevron.
      root.rereadBranches(root.openBranches());
      creating.emptyDelay.restart();
      if (root.searchMode !== "") collections.collSettle.restart();
      // the second pane is very often the destination
      root.refreshOther();
      // and free space just moved
      root.pollDisks();
    }
    function onSaid(text) { if (root.shown) root.warn(text); }
  }

  function startJob(op, paths, dest, clash) { return clipboard.startJob(op, paths, dest, clash); }

  function clearEndedJobs() { return clipboard.clearEndedJobs(); }

  // ── ANOTHER ONE OF THESE, HERE ─────────────────────────────────────────
  // `y y` then `p` already does it in two gestures. This is the one gesture,
  // and it is not a new mechanism: a duplicate IS a copy into the directory
  // you are already standing in, with the clash resolved rather than asked
  // about — because the clash is the whole point. terminus_free turns
  // "report.pdf" into "report (1).pdf" the same way "Keep both" does, at the
  // moment of writing rather than from a listing that may be stale.
  //
  // Straight to commitPaste, skipping paste()'s question: there is nothing to
  // ask. Every item collides, by construction.
  // ── WHERE A ROW ACTUALLY LIVES ────────────────────────────────────────
  function homeOf(rows) { return clipboard.homeOf(rows); }

  function duplicate() { return clipboard.duplicate(); }

  function commitPaste(clash) { return clipboard.commitPaste(clash); }

  // ── ASKING ABOUT THE TRASH ─────────────────────────────────────────────
  // Only this one is optional. Trash is recoverable — the undo record below
  // is what recovers it — so being asked every time is a keystroke spent on a
  // decision that can be unmade. deleteForever() has no such switch and never
  // will: that is the difference between the two verbs.
  property bool confirmTrash: true

  // ── WHETHER THE CURSOR SLIDES ──────────────────────────────────────────
  // Every list in this window marks its cursor with one bar that travels
  // between rows rather than a fill that blinks from one to the next. It is
  // 110ms and it is the difference between a cursor that moves and a cursor
  // that teleports — but it is also a thing that moves on screen every time
  // you press j, and that is not to everyone's taste on a list you drive at
  // speed. Off, the bar still marks the row; it simply arrives there.
  //
  // NOT a motion-scale setting: Zenon already has one of those and turning the
  // whole desktop's motion down to nothing is a different request from wanting
  // this one thing to stop sliding.
  property bool cursorSlide: true

  // The strip comes and goes with the second tab, so the body jumps by its
  // height the moment one is opened and again when it is closed. On, it is
  // simply always there.
  property bool alwaysTabs: false

  // The sort strip over a single-pane list. Twenty-two pixels, and sorting is
  // reachable from this panel and from the `,` keys either way.
  property bool colHeadsOn: true

  function trash() { return clipboard.trash(); }
  function askTrash(rows) { return clipboard.askTrash(rows); }

  function doTrash(rows) { return clipboard.doTrash(rows); }

  // ── renaming ────────────────────────────────────────────────────────────
  // the functions of this section live in terminus/RenameDrag.qml; these
  // forward to it, so every caller is unchanged
  RenameDrag { id: renameDrag; term: root }
  // In place, on the row itself. `renaming` is a window-level flag rather than
  // per-row state because only one row can be the cursor, and the cursor is
  // the only row this is ever about — so the delegate that happens to be
  // current picks it up and everything else ignores it, including the rows in
  // the other pane and in the columns beside it.
  // what the components in their own files (Pane, PaneList, MillerColumn,
  // PrefText…) reach of the window's items, by name — they take `term`, the
  // window, and read these through it
  readonly property alias paneEmptyDelay: creating.emptyDelay
  readonly property alias paneMakeGuard: creating.makeGuard
  readonly property alias paneUsageDelay: measure.usageDelay
  readonly property alias paneWatchAim: dirWatch.watchAim
  readonly property alias listScrollHold: preview.scrollHoldExpiry
  readonly property alias millerAnimation: millerAnim
  readonly property alias prefsContent: content
  readonly property alias prefsDialogKeys: dialogKeys
  readonly property alias prefsSheet: prefs
  readonly property alias crumbBarRef: chrome.crumbBar
  readonly property alias sideRef: side
  readonly property alias tabStripRef: chrome.tabStrip
  readonly property alias chromeRef: chrome
  readonly property alias contentRef: content
  readonly property alias dropLayerRef: dropLayer
  readonly property alias plugRef: plug
  readonly property alias viewSaveRef: opening.viewSave
  readonly property alias confirmRef: confirm
  readonly property alias lookLayerRef: lookLayer
  readonly property alias propsRef: props
  readonly property alias sideGripRef: chrome.sideGrip
  readonly property alias springGraceRef: renameDrag.springGrace
  readonly property alias labelFmRef: labelFm
  readonly property alias jobsDrawerRef: jobsDrawer
  readonly property alias millerAnimRef: millerAnim
  readonly property alias statusClearRef: statusClear
  readonly property alias cmdPaletteRef: cmdPalette
  readonly property alias collEditRef: collEdit
  readonly property alias diskInfoRef: diskInfo
  readonly property alias marksRef: marks
  readonly property alias menuPopRef: menuPop
  readonly property alias paneLRef: paneL
  readonly property alias paneRRef: paneR
  readonly property alias prefsRef: prefs
  readonly property alias sendToRef: sendTo
  readonly property alias tagPickRef: tagPick
  readonly property alias emptyDelayRef: creating.emptyDelay
  readonly property alias otherRetryRef: otherRetry
  readonly property alias holdPollRef: holdPoll
  readonly property alias holdStopRef: holdStop
  readonly property alias warmRepRef: warmRep
  readonly property alias diskToolRef: diskTool
  readonly property alias sideCeilingRef: sideCeiling
  readonly property alias sideLayoutRef: sideLayout
  readonly property alias splitPaneRef: splitPane
  readonly property alias thumbFlushRef: thumbFlush
  readonly property alias listProcRef: listing.listProc
  readonly property alias listingRef: listing
  readonly property alias dirWatchRef: dirWatch
  readonly property alias infoDelayRef: listing.infoDelay
  readonly property alias openingRef: opening
  readonly property alias previewFadeRef: previewFade
  readonly property alias previewRef: preview
  readonly property alias makeGuardRef: creating.makeGuard
  readonly property alias millerFadeRef: millerFade
  readonly property alias openerProcRef: openerProc
  readonly property alias collectionsRef: collections
  readonly property alias trashSizeProcRef: fileOps.trashSizeProc
  readonly property alias clipCopyProcRef: clipCopyProc
  readonly property alias dragCardRef: dragCard
  readonly property alias dragProxyRef: dragProxy
  readonly property alias dropAskRef: dropAsk
  readonly property alias appPickRef: appPick
  readonly property alias bulkRef: bulk
  readonly property alias thumbnailsRef: thumbnails
  property bool renaming: false

  // WHICH ROW IS BEING NAMED, by path.
  //
  // The field used to be tied to `current` — the row the cursor is on — and a
  // rename is not about the cursor, it is about a row. Any flicker in `sel`
  // while a listing settled took `current` away for a frame, the Loader
  // holding the field deactivated, the field was destroyed, and destruction
  // reads as "focus lost" — which commits and closes. That is the whole of
  // "inline creation sometimes works": the box opened and was torn down again
  // before you could type into it, leaving the file under its generic name.
  //
  // A path does not flicker. Every view checks its own row against it, so the
  // list, the miller middle column and the grid all open the same box on the
  // same row without any of them knowing about the others.
  property string renamePath: ""

  function beginRename() { return renameDrag.beginRename(); }

  // `cancelled` is Escape rather than Return, and for something that was
  // created a moment ago that means "I did not want this after all" — so it
  // goes away again. Anything older is left exactly as it was.
  // ── WHETHER THE FRESH THING IS EMPTY ────────────────────────────────
  // Cancelling the name of something just created UNDOES the creation, and
  // for a directory that is a recursive delete. That is exactly right for
  // `a`, which makes an empty directory and nothing else — and catastrophic
  // for the gather verb, whose directory arrives with the selection already
  // inside it. Escape there deleted the files it had just tidied away,
  // with no trash and no undo. Measured, on two fixtures, before this
  // flag existed.
  property bool freshHolds: false

  function endRename(cancelled) { return renameDrag.endRename(cancelled); }

  // ── A RESERVED NAME IS GIVEN BACK ───────────────────────────────────
  function unreserve(path) { return renameDrag.unreserve(path); }

  function commitRename(entry, name) { return renameDrag.commitRename(entry, name); }

  function applyRename(from, want, wasFresh, fresh, over) { return renameDrag.applyRename(from, want, wasFresh, fresh, over); }

  function copyPath() { return renameDrag.copyPath(); }

  function setWallpaper(screenName) { return renameDrag.setWallpaper(screenName); }

  // The row menu's Install on font files: the marked ones, or the one under
  // the cursor, through alexandria's install (its queue, its fc-cache and
  // oracle's rescan) — the same install as its own window's button.
  function installFonts() {
    const book = root.mgr ? root.mgr.fontBook : null;
    const files = root.acting().filter((r) => !r.isDir && Terminus.isFont(r.name)).map((r) => r.path);
    if (!book || files.length === 0) { root.warn("not a font"); return; }
    const what = files.length === 1 ? Terminus.basename(files[0]) : files.length + " fonts";
    root.status = "installing " + what + "\u2026";
    book.install(files, (ok) => {
      if (ok) root.status = "installed " + what;
      else root.warn("could not install " + what);
    }, files.length === 1 ? "Installing\u2026" : "Installing " + files.length + " fonts\u2026");
    root.act.marked = {};
  }

  function applyBand(x1, y1, x2, y2, base) { return renameDrag.applyBand(x1, y1, x2, y2, base); }

  function bandIndexAt(view, y) { return renameDrag.bandIndexAt(view, y); }

  // ── dragging in and out ─────────────────────────────────────────────────
  function dragPicture(entry, then) { return renameDrag.dragPicture(entry, then); }

  // The paths the drag in flight is carrying, so opening on hold can refuse
  // to go into one of them — see springCheck. Empty when nothing is dragged.
  property var dragPaths: []

  function beginDrag(entry, hx, hy) { return renameDrag.beginDrag(entry, hx, hy); }

  function dragRows(entry) { return renameDrag.dragRows(entry); }

  function dragUris(entry) { return renameDrag.dragUris(entry); }

  // What arrives from elsewhere. A copy unless the source asked for a move,
  // which is what dragging between two directories of the same disk means.
  // A drop ASKS whether it is a copy or a move.
  //
  // The action the drag carries is a guess — it comes from which modifier
  // happened to be held, and between two windows of the same application it is
  // whatever the compositor decided to propose. Copying when you meant to move
  // leaves a duplicate you have to find; moving when you meant to copy takes
  // the original away. Neither is worth inferring, so the drop says what it is
  // about to do and lets you pick. The conflict check still runs afterwards.
  // The directory currently under a drag, or "" for the space between rows.
  property string dropDir: ""
  // which half a drag is over — the half the pane-wide cue lights
  property int dropSide: 0

  function dropDirAt(x, y) { return renameDrag.dropDirAt(x, y); }

  // ── WHILE A DRAG IS HELD OVER THE LISTING ─────────────────────────────
  // Two helps, and they are kept OUT of the drag itself. Everything that
  // starts, carries and finishes a drag is the rows' and dropUris' business,
  // and none of it is touched here: dropHint calls in on enter, move, leave
  // and drop, and this block only reads where the pointer is and moves the
  // views. Take this block and those four calls out and drag and drop is
  // exactly what it was.
  //
  //   EDGE SCROLL  held within dragEdge of a view's top or bottom, the view
  //                scrolls that way — faster nearer the edge, and it keeps
  //                going while the pointer is still. The wheel cannot do it:
  //                while a drag is in flight the compositor holds the pointer.
  //
  //   OPEN ON HOLD a drag held over a directory for springMs goes into it, in
  //                whichever pane it is over — including the one the drag
  //                came from, which is safe because the drag lives on
  //                dragProxy and not on a row the re-listing destroys. Never
  //                into something being dragged: that is a drop dropUris
  //                refuses anyway. In the LIST a hold only opens the
  //                directory's branch, never goes in; the branches a drag
  //                opened are shut when it leaves or lands.
  readonly property int dragEdge: 56
  readonly property int springMs: 1000

  property var assistView: null
  property real assistSpeed: 0
  property point assistAt: Qt.point(0, 0)
  property string springDir: ""
  property int springSide: 0
  // true when dropDir was read off a FILE inside an open branch rather than
  // off a directory row — a place to drop, but not something to open on hold:
  // it is already open, and the next hold would walk into it.
  property bool dropViaFile: false
  // The branches this drag opened on hold, as { pane, dir }, so they can be
  // shut again once it is over — see springShut.
  property var springOpened: []

  function assistSideAt(x) { return renameDrag.assistSideAt(x); }

  function assistViewAt(x, y) { return renameDrag.assistViewAt(x, y); }

  function dragAssistMove(x, y) { return renameDrag.dragAssistMove(x, y); }

  // ── HOW FAST, AT THE VERY EDGE ────────────────────────────────────────
  function assistTopSpeed(v) { return renameDrag.assistTopSpeed(v); }

  function dragAssistStop(hold) { return renameDrag.dragAssistStop(hold); }


  function springCheck() { return renameDrag.springCheck(); }


  // Shuts what the drag opened, the way Finder does, and nothing else: a
  // branch that was open before the drag stays open. From the DROP AREA's
  // end of things, not the drag's — a drag from another window or
  // application ends over there, and this window only sees it leave or
  // land.
  //
  // A DROP HOLDS THEM OPEN instead (springHeld): while the copy-or-move
  // question is up, and for springGrace after Copy or Move is chosen, so
  // what landed is seen landing before the branch folds away. A separate
  // list from springOpened, so a new drag started meanwhile keeps its own
  // branches and the grace running out does not shut them under it.
  property var springHeld: []


  function springShut(list) { return renameDrag.springShut(list); }

  function dropRowAt(v, rows, x, y, pane) { return renameDrag.dropRowAt(v, rows, x, y, pane); }

  function fetchInto(urls, dest) { return renameDrag.fetchInto(urls, dest); }

  function urlsFrom(d) { return renameDrag.urlsFrom(d); }

  function dropUris(urls, action, dest, atItem, atX, atY, extra) { return renameDrag.dropUris(urls, action, dest, atItem, atX, atY, extra); }

  // ── undo ────────────────────────────────────────────────────────────────
  // the functions of this section live in terminus/FileOps.qml; these
  // forward to it, so every caller is unchanged
  FileOps { id: fileOps; term: root }
  // The three things that move a file out from under you, and nothing else.
  //
  // A COPY is not on the list: undoing one means deleting the copies, and a
  // stack that deletes files is a worse hazard than the mistake it fixes.
  // Trash, move and rename all have an exact inverse, which is the test for
  // belonging here.
  property var undoStack: []

  // ── AND IT IS OFFERED, NOT ONLY KEPT ──────────────────────────────────
  // Undo was a key (u) and a menu entry, which is to say it was something you
  // had to already know about at the moment you needed it most. For a few
  // seconds after anything undoable, the bar offers it — the undoChip beside
  // the status — and then gets out of the way. The stack is unchanged; this
  // is only the door to it.
  property bool undoOffer: false

  function pushUndo(entry) { return fileOps.pushUndo(entry); }

  readonly property string undoLabel: {
    const n = root.undoStack.length;
    if (n === 0) return "";
    const e = root.undoStack[n - 1];
    if (e.kind === "trash") return "Undo trash";
    if (e.kind === "move") return "Undo move";
    return "Undo rename";
  }

  function undo() { return fileOps.undo(); }

  // ── the trash, in both directions ───────────────────────────────────────
  readonly property bool inTrash: Terminus.isTrashDir(root.cwd)

  // How much the trash holds, asked when you are standing in it.
  property string trashSize: ""


  onInTrashChanged: {
    if (root.inTrash && !fileOps.trashSizeProc.running) fileOps.trashSizeProc.running = true;
  }

  // ── AND WHAT IT HOLDS, FOR THE SIDEBAR'S FOOT ─────────────────────────
  // The trash is always one row away at the bottom of the sidebar, with how
  // many things are in it and how much they weigh. The count is a live
  // listing of Trash/files (FolderListModel watches the directory, so a trash
  // from anywhere shows), and the size is asked again whenever the count
  // moves — after a pause, so a trash of forty files is one `du`, not forty.
  FolderListModel {
    id: trashList
    folder: "file://" + Terminus.trashFilesDir()
    showDirs: true
    showHidden: true
    showDotAndDotDot: false
    showOnlyReadable: false
    sortField: FolderListModel.Unsorted
  }
  readonly property int trashCount: trashList.count
  onTrashCountChanged: fileOps.trashSizeLater.restart()
  function trashDropped(urls) { return fileOps.trashDropped(urls); }

  function emptyTrash() { return fileOps.emptyTrash(); }

  function restoreSelected() { return fileOps.restoreSelected(); }

  // ── archives ────────────────────────────────────────────────────────────
  function extractSelected() { return fileOps.extractSelected(); }

  // yazi's `c a`. The name carries the format: ".tar.zst", ".zip", ".7z" —
  // bsdtar reads the extension and picks the writer, so there is no format
  // menu to get out of step with what the tools can actually produce.
  // The format is CHOSEN, not typed. It was a single "Compress…" that guessed
  // .tar.zst and left you to retype the extension for anything else — which
  // meant knowing which spellings bsdtar accepts. The name is still yours to
  // edit; only the extension comes from the menu.
  readonly property var archiveFormats: [
    [".tar.zst", "tar · zstd — fast, small"],
    [".tar.gz",  "tar · gzip — most portable"],
    [".tar.xz",  "tar · xz — smallest, slowest"],
    [".zip",     "zip — for other systems"],
    [".7z",      "7z — 7-Zip"]
  ]

  // What is being archived and what it will be called, held while the answer
  // to "is that name taken" comes back. Null at every other moment.
  property var archivePending: null

  function beginArchive(ext) { return fileOps.beginArchive(ext); }


  function commitArchive(name) { return fileOps.commitArchive(name); }

  // ── links ───────────────────────────────────────────────────────────────
  function linkHere() { return fileOps.linkHere(); }

  // ── QUICK ACTIONS ────────────────────────────────────────────────────
  // Done from the viewer, on the file you are looking at. See the commands
  // in terminus.js for what each one does and why rotation is the only one
  // that writes over the original.
  //
  // `imgStamp` is a cache-buster. Qt keys its image cache on the URL, and a
  // rotation leaves the URL alone — so without this the picture on screen
  // after a rotate is the one from before it, and stays that way until the
  // overlay is closed and reopened.
  property int imgStamp: 0

  function rotateLook(degrees) { return fileOps.rotateLook(degrees); }


  function convertLook(ext) { return fileOps.convertLook(ext); }

  function extractAudio() { return fileOps.extractAudio(); }

  function pasteLink(symbolic) { return fileOps.pasteLink(symbolic); }

  // ── bulk rename ─────────────────────────────────────────────────────────
  function beginBulkRename() { return fileOps.beginBulkRename(); }
  // The one open dropdown of the cards still built here — the collection
  // editor's; BulkDrop asks its host for it.
  property var bulkOpenDrop: null

  // ── open with ───────────────────────────────────────────────────────────
  // Filled in when the menu opens, because it costs a process and almost every
  // right-click is not about this.
  property var openWithApps: []
  // Whether the scan has ANSWERED, which is a different question from whether
  // it found anything — an empty list means "nothing handles this" only after
  // the process has been and gone, and the menu decides between a submenu and
  // a card on the strength of that distinction.
  property bool appsScanned: false
  // The file's type, which the same scan now leads with. Kept because the
  // answer to "nothing opens this" is to register something against the TYPE,
  // and by then the file that raised the question is beside the point.
  property string openWithMime: ""
  // WHICH of them actually opens it. The registered list answers "what could
  // open this"; a default is a different claim and the properties card shows
  // it as one — buck's jpegs were defaulting to an Avahi SSH browser, which
  // the old list could show as one row among three but never as the answer.
  property string openWithDefault: ""


  // A path whose scan was asked for while another was still out.
  property string appsAgain: ""

  function findApps(path) { return fileOps.findApps(path); }

  function openWith(id, path) { return fileOps.openWith(id, path); }

  // ── CHANGING WHAT OPENS A TYPE ──────────────────────────────────────────
  // Both of these edit the association database rather than this file, so both
  // ask the scan again afterwards: the card is showing the old answer the
  // moment the command lands, and there is nothing else to tell it otherwise.
  //
  // `rescanApps` re-reads for the row the card is about, which is the row the
  // question was asked of — not the cursor, which may have moved on.
  property string appsPath: ""
  function rescanApps() { return fileOps.rescanApps(); }
  function setDefaultApp(id) { return fileOps.setDefaultApp(id); }
  function removeApp(id) { return fileOps.removeApp(id); }

  // ── and choosing one by hand ────────────────────────────────────────────
  function beginOpenWith(path, launch, alone) { return fileOps.beginOpenWith(path, launch, alone); }

  function selectAll() { return fileOps.selectAll(); }

  function invertSelection() { return fileOps.invertSelection(); }

  function setSort(key) { return fileOps.setSort(key); }

  function copyText(text, note) { return fileOps.copyText(text, note); }

  // Empty means xdg-terminal-exec, which is what it always did — see
  // Terminus.shellCommand for the two shapes a value can take.
  property string termCmd: ""

  function openShell() { return fileOps.openShell(); }

  // yazi's `a`. One prompt for both, because the only difference is whether
  // the name ends in a slash — which is how yazi says it too.
  // ── creating ────────────────────────────────────────────────────────────
  // the functions of this section live in terminus/Creating.qml; these
  // forward to it, so every caller is unchanged
  Creating { id: creating; term: root }
  // MAKE IT, THEN NAME IT — which is the order every file manager that feels
  // direct does it in, and the order a phantom row asking for a name up front
  // was pretending to.
  //
  // The item is created immediately under a free default name, the listing
  // brings it back, the cursor lands on it and the row goes straight into the
  // same inline edit `r` uses. So there is one naming interaction in this
  // window, not two, and the thing being named is on screen while you name it.
  //
  // Return with the name untouched keeps the default. Escape UNDOES the
  // creation rather than leaving a "new file" behind, which is what makes it
  // safe to press `a` to see what happens.
  property string freshPath: ""

  // ── WHICH DIRECTORIES ARE EMPTY ──────────────────────────────────────
  // path -> true for a directory known to hold nothing. Absence means
  // "not asked yet", NOT "empty": a chevron is shown while the answer is
  // outstanding and taken away when the answer is no, so the common case
  // — a directory with things in it — never flickers.
  property var dirEmpty: ({})



  function probeEmpty() { return creating.probeEmpty(); }

  // Paths this window has asked to exist but has not yet seen in a
  // listing, each against the moment it was asked for. Mutated in place:
  // nothing binds to it, and it is read once per create. Entries are
  // dropped by rowsIn as soon as the rows that would have collided are the
  // real ones.
  //
  // ── AND THEY EXPIRE ───────────────────────────────────────────────
  // Presence in a listing was the only thing that ever released a name,
  // and plenty of creates never produce one: cancelled with Escape,
  // renamed into something else on the spot, or removed by something
  // outside this window. Each of those left its name reserved for the
  // rest of the session, so a directory worked in for a few minutes started
  // offering "new file 9" — which is what the capture of it shows.
  //
  // A reservation only has to outlive the gap between asking for a name
  // and the row arriving under it, which is one command and one listing.
  // Anything older than that is answering a question nobody asked.
  property var justMade: ({})
  readonly property int madeTTL: 5000

  // The directory the last create was aimed at, re-read once the command
  // has actually run — see startCreate.
  property string madeIn: ""

  // ── THE DIRECTORY THE CURSOR IS POINTING AT ─────────────────────────
  function cursorDir() { return creating.cursorDir(); }

  function rowsIn(dir) { return creating.rowsIn(dir); }

  function beginCreate() { return creating.beginCreate(); }
  function beginMkdir() { return creating.beginMkdir(); }

  function startCreate(kind) { return creating.startCreate(kind); }

  // A create waiting for the directory it is aimed at to be read.
  // { kind, dir, cwd }, or null. Never survives its own landing: the kid
  // collector clears it before calling through.
  //
  // ── AND IT MUST NOT SURVIVE ANYTHING ELSE ─────────────────────────
  // A deferred create is a promise about a moment, and the moment can
  // pass: walk away, collapse the branch, or delete the directory and make
  // another with the same name, and the read it was waiting for still
  // arrives. It then made a file nobody had asked for, in a directory
  // nobody was looking at — a directory created fresh sprouted a "new
  // file 2" on its own, from an attempt made against the directory of the
  // same name several minutes earlier.
  //
  // So it carries the cwd it was made in, the landing checks that the
  // branch is still open under it, and a timer throws it away if the
  // read never comes at all. A create that cannot be delivered where it
  // was asked for is not delivered anywhere.
  property var pendingMake: null


  // The half of startCreate that needs to know what the directory holds.
  // ── RESERVING A NAME, APART FROM MAKING THE THING ───────────────────
  function reserveName(stem, where) { return creating.reserveName(stem, where); }

  function makeIn(kind, where) { return creating.makeIn(kind, where); }

  // ── FINDER'S NEW DIRECTORY WITH SELECTION ──────────────────────────────────
  function gatherIntoFolder() { return creating.gatherIntoFolder(); }

  function deleteForever() { return creating.deleteForever(); }

  function beginSearch(mode) { return creating.beginSearch(mode); }



  // ── chrome ──────────────────────────────────────────────────────────────
  // 24, not 28. Two pixels off every row, twice (the second, user
  // 2026-10-08) — the list and the miller columns both measure themselves
  // from this, so a screenful gains rows and the vertical rhythm tightens
  // without the text itself moving.
  readonly property int rowH: Math.round(24 * root.zoom)

  // WHEN THE CURSOR IS AN OUTLINE RATHER THAN A BAR, asked by the SelectBar
  // over each list. EntryRow decides this per row as `cursorOnly`; the bar is
  // outside the delegates and has to ask the same question of the pane.
  function cursorOutline(p) {
    if (!p) return true;
    return !p.active || root.markedCount > 0;
  }

  // ── on partial rows at the edges of a listing, and on elastic ───────────
  // Neither is here, both were, and this is why — so the next attempt starts
  // from what was measured rather than from what looks obvious.
  //
  // A pane is whatever height the window is; a row is a fixed rowH. The last
  // row is therefore usually cut, and the tidy-looking fix is to make the rows
  // divide the pane exactly. They cannot: Qt lays delegates out on whole
  // pixels, so a fractional row height is rounded on the way to the screen and
  // the view's own bookkeeping drifts with it. Measured — a directory of 2299
  // rows asked to be 28.606 tall reported a contentHeight of 2330 rows' worth,
  // an average of 29.0, and an originY that wandered by half a row, which ate
  // rows off the top of the listing. Padding the pane down to a whole number
  // of rows instead only trades the clipped row for a strip of dead space.
  //
  // Elastic hit the same wall from the other side: any give displaces the
  // rows, and displacing rows in a viewport that is not an exact number of
  // them tall is that clipping again. It is also unreachable by the obvious
  // route — a WheelHandler declared inside a Flickable never fires at all,
  // because Flickable's default property parents non-Item children to
  // contentItem as a plain QObject — and Qt's own overshoot never runs here
  // either, since the overlay below takes the wheel before the flick engine
  // sees it.
  //
  // Both worked, in the sense of doing what they said. Both cost more in
  // machinery and edge cases than a clipped row at the bottom of a list is
  // worth.

  // Tight. One line of type, so 40 was leaving a band of air under the text
  // once the separator at the bottom was counted as part of the bar.
  readonly property int headH: 34

  // ── THE WARM ITSELF ─────────────────────────────────
  // Nothing is drawn here. Each Image exists to make Qt decode a file
  // and to HOLD A REFERENCE to the result, which is the part that
  // matters: an unreferenced pixmap is subject to a small cache and is
  // usually gone by the time you need it.
  //
  // They live until the next warm replaces them, which spans the
  // navigation — so the real tiles come up against a decode that is
  // still referenced rather than one that was just dropped.
  Item {
    id: warmers
    visible: false
    width: 0
    height: 0
    Repeater {
      id: warmRep
      model: root.warmRows
      delegate: Image {
        required property var modelData
        visible: false
        asynchronous: true
        cache: true
        // ── THE SAME fillMode AS THE TILE, AND IT IS NOT COSMETIC ────
        // Qt keys a decoded pixmap on url + requested size + provider
        // options, and the provider options carry preserveAspectRatioFit,
        // which comes straight off fillMode. A warmer left at the default
        // Stretch decodes the same file at the same size into a DIFFERENT
        // cache entry — so every warm was real work that no tile could
        // ever find. Measured: the tile still took 141ms to go Ready with
        // a fully warmed image sitting in the cache beside it.
        fillMode: Image.PreserveAspectFit
        // The pool file only. There is no point warming an original:
        // that path is for tiles zoomed past the cache, and it decodes
        // at the tile's size, which we do not know for a directory we
        // have not opened.
        source: root.thumbFile[modelData.path]
          ? "file://" + root.thumbFile[modelData.path] : ""
        // EXACTLY what the tile will ask for — see thumb.pooled.
        sourceSize.width: Thumbs.size()
        sourceSize.height: Thumbs.size()
      }
    }
  }

  Item {
    id: content
    anchors.fill: parent
    focus: true

    // Keys land here, not on the filter field: the field only takes them while
    // it has focus, and it only has focus while you are filtering. That is what
    // buys the bare-letter verbs — y, d, p, n — that a permanently focused
    // field would have swallowed. Zeus had to put its sort on Alt+S for exactly
    // that reason; this window does not have to.
    // Mouse 4 goes UP a directory — the same thing backspace does. Up is where
    // you almost always mean to go, and it is predictable: back depends on the
    // path you took to get here, which you cannot see.
    //
    // There is no mouse 5. There WAS, walking a forward history, and it could
    // never do anything: forward is only ever filled by going back, going back
    // was what mouse 4 gave up to go up instead, so the stack was empty for the
    // life of the window while every navigation still pushed a path onto its
    // twin. The button is gone and so are both stacks.
    //
    // On the whole surface rather than a row: which directory you are in is
    // about the window, not about whatever the pointer happens to be over, and
    // over an empty listing there is no row to be over.
    MouseArea {
      anchors.fill: parent
      // ── THE SIDE BUTTONS ARE THE TRAIL, NOT THE TREE ─────────────────
      // Back used to go UP a directory, which is the other axis entirely: up
      // is the parent, back is where you were. With a history to walk they do
      // what the same two buttons do in every browser, and `h` is still there
      // for the parent.
      acceptedButtons: Qt.BackButton | Qt.ForwardButton
      onPressed: (m) => {
        if (m.button === Qt.BackButton) root.back();
        else if (m.button === Qt.ForwardButton) root.forward();
      }
    }

    // ── the keymap ────────────────────────────────────────────────────
    // Yazi's, because that is the muscle memory this replaces. Including its
    // SEQUENCES: g d, c m, b a and so on are two keystrokes, so a pending
    // prefix has to be held between them, and any key that is not a valid
    // continuation cancels it rather than doing something else.
    property string pending: ""

    // The sequences, once. The bar along the bottom renders these and the key
    // handler dispatches them, so a destination cannot be listed without
    // working or work without being listed — they were two lists before, which
    // is two chances to disagree.
    readonly property var sequences: ({
      g: [
        ["g", "top",       () => { root.act.sel = 0; root.positionSel(); }],
        ["h", "home",      () => root.goTo(Paths.home())],
        ["c", "config",    () => root.goTo(Paths.configDir())],
        ["d", "downloads", () => root.goTo(UserDirs.downloads)],
        ["D", "documents", () => root.goTo(UserDirs.documents)],
        ["p", "pictures",  () => root.goTo(UserDirs.pictures)],
        ["v", "videos",    () => root.goTo(UserDirs.videos)],
        ["t", "trash",     () => root.goTo(Terminus.trashFilesDir())],
        ["b", "bookmarks", () => marks.ask()],
        ["r", "containing dir", () => root.reveal()],
        ["m", "media",     () => root.goTo("/run/media")],
        ["/", "root",      () => root.goTo("/")],
        // THE SAME SHEET THAT SENDS, ASKED TO GO INSTEAD. Picking a place
        // out of a tree you can filter is the same act whether something is
        // travelling with you or not, and it was already built — so this is
        // the picker with its destination handed to goTo rather than to
        // paste, not a second picker that happens to look like it.
        [" ", "go to", () => sendTo.ask("go")]
      ],
      c: [
        ["c", "copy path",     () => { const r = root.currentRow();
                                       if (r) root.copyText(r.path, "path copied"); }],
        ["d", "copy dirname",  () => { const r = root.currentRow();
                                       if (r) root.copyText(Terminus.dirname(r.path), "dirname copied"); }],
        ["f", "copy filename", () => { const r = root.currentRow();
                                       if (r) root.copyText(r.name, "filename copied"); }],
        ["n", "copy name",     () => { const r = root.currentRow();
                                       if (r) root.copyText(Terminus.stem(r.name), "name copied"); }],
        ["m", "permissions",   () => root.openProperties(1)],
        ["t", "tags",          () => tagPick.ask()],
        ["s", "collection",  () => collEdit.ask(-1)],
        ["a", "archive",       () => root.beginArchive("")],
        // The other half of `c a`, beside it: an archive is unpacked next to
        // itself, the same as the menu's Extract here.
        ["x", "extract",       () => root.extractSelected()],
        ["g", "directory with these", () => root.gatherIntoFolder()]
      ],
      b: [
        ["a", "bookmark here",   () => root.toggleBookmark()],
        // ONE key that goes both ways, on whatever the cursor is on. `b d`
        // used to sit beside `b a` as "remove bookmark" and called exactly the
        // same function — two entries in the hint bar for one toggle, neither
        // of which could act on the row you were looking at. This one does:
        // a directory under the cursor is what you are pointing at, and the
        // glyph beside its name says which way the toggle will go.
        // A FUNCTION rather than a string, because this label is not fixed —
        // see bookmarkVerb. The hint bar calls it if it is callable, so any
        // other entry that wants to describe itself by the state it is in can
        // do the same without a second mechanism.
        ["b", () => root.bookmarkVerb(), () => root.toggleBookmarkHere()]
      ],
      // TAKING AND SENDING ARE THE SAME VERB. `y` is "copy this" and `x` is
      // "move this"; what follows says WHERE — doubled means the clipboard,
      // `t` (to) means pick a destination and send it there without going. Both
      // prefixes are shaped the same way, so knowing one is knowing the
      // other.
      y: [
        ["y", "copy",    () => root.yank("copy")],
        ["t", "copy to", () => sendTo.ask("copy")],
        // Under the copy prefix because that is what it is: a copy whose
        // destination is where you already are.
        ["d", "duplicate", () => root.duplicate()],
        // Also under copy, and next to duplicate for the same reason: both
        // put a second thing here that stands for the first.
        ["l", "symlink here", () => root.linkHere()]
      ],
      x: [
        ["x", "cut",     () => root.yank("move")],
        ["t", "move to", () => sendTo.ask("move")]
      ],
      ",": [
        ["u", "disk usage",  () => root.toggleUsage()],
        ["g", "git status",  () => root.toggleGit()],
        ["n", "by name",     () => root.setSort("name")],
        ["s", "by size",     () => root.setSort("size")],
        ["m", "by modified", () => root.setSort("time")],
        ["k", "by kind",     () => root.setSort("kind")],
        ["t", "by tag",      () => root.setSort("tag")],
        ["h", "headings",    () => root.toggleGrouped()],
        ["!", "reverse",     () => root.sortDesc = !root.sortDesc]
      ]
    })

    // No timer. It used to give up after 1200ms, which meant a menu you were
    // still reading closed itself; it now stays until you choose or press
    // escape, and a key that is not one of the choices is ignored rather than
    // taken as a reason to dismiss.
    function seq(prefix) { content.pending = prefix; }
    function done() { content.pending = ""; }

    Keys.onPressed: (event) => {
      // ── while a dialog is up ──────────────────────────────────────
      // It takes the keyboard and the listing behind it gets nothing: acting
      // on a file while a question about that file is still on screen is the
      // one thing this must not do.
      //
      // confirm holds focus in controls of its own and never reaches here —
      // this is the keyboard for the ones that had none at all, and Escape
      // for them.
      // Dialogs are handled by dialogKeys, which takes the keyboard for as
      // long as one is up — see its own note. Nothing here may act while a
      // question is on screen.
      if (confirm.open || props.open
          || appPick.open || sendTo.open) return;

      // ── AND WHILE A NAME IS BEING TYPED IN THE LISTING ────────────
      // An inline rename holds the keyboard in a TextInput ON a row, and a
      // TextInput passes on any key it did not use. Right at the END of the
      // text is exactly that: the caret cannot go further, so the key came up
      // here, moved the cursor to the next row, destroyed the delegate being
      // edited and took the rename down with it — reaching for a file
      // extension aborted the edit.
      //
      // Swallowed rather than returned, so nothing behind acts on it either.
      // Return and Escape never arrive: the field consumes both, to commit and
      // to cancel.
      if (root.renaming) { event.accepted = true; return; }

      if (menuPop.menu.open) {
        // EVERY key belongs to the menu while it is up — the listing behind
        // it must not act on anything — but they no longer all mean "nothing".
        // The card is navigable from the keyboard now, which is the other half
        // of being able to open it from the keyboard.
        event.accepted = true;
        // the key that opened it closes it
        if (event.key === Qt.Key_Menu) { menuPop.menu.close(); return; }
        // Escape backs out ONE LEVEL, the way it does everywhere else in this
        // window: out of the submenu first, and only then out of the menu.
        if (event.key === Qt.Key_Escape) {
          if (menuPop.menu.subSel >= 0) { menuPop.menu.subSel = -1; menuPop.menu.subAt = -1; }
          else menuPop.menu.close();
          return;
        }
        // j/k as well as the arrows, because the listing behind it moves that
        // way and a menu that did not would be the one place it does not.
        if (event.key === Qt.Key_Down || event.text === "j") { menuPop.menu.move(1); return; }
        if (event.key === Qt.Key_Up || event.text === "k") { menuPop.menu.move(-1); return; }
        // right steps INTO the children, left comes back out — the same shape
        // as h/l walking the tree in the listing
        if (event.key === Qt.Key_Right || event.text === "l") {
          if (menuPop.menu.subSel < 0) {
            const it = menuPop.menu.items[menuPop.menu.at];
            if (it && it.sub) {
              menuPop.menu.subAt = menuPop.menu.at;
              menuPop.menu.subSel = menuPop.menu.step(it.sub, -1, 1);
            }
          }
          return;
        }
        if (event.key === Qt.Key_Left || event.text === "h") {
          if (menuPop.menu.subSel >= 0) { menuPop.menu.subSel = -1; menuPop.menu.subAt = -1; }
          return;
        }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          if (menuPop.menu.subSel >= 0) menuPop.menu.activateSub();
          else menuPop.menu.activateAt();
          return;
        }
        return;
      }

      // A portal request outranks everything: an application is blocked on the
      // answer, so return hands it over and escape tells it no.
      //
      // EXCEPT OVER A DIRECTORY YOU HAVE NOT CHOSEN YET. Return used to answer
      // the request no matter what the cursor was on, which made a save dialog
      // impossible to navigate with the keyboard: the one key that means "go
      // in" meant "write it here" instead, so the only way to reach the directory
      // you wanted was to answer in the wrong one and move the file afterwards.
      //
      // A DIRECTORY request is the exception to the exception — there, a
      // directory under the cursor IS the answer, so Return gives it.
      if (root.picking) {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          event.accepted = true;
          const pr = root.currentRow();
          if (pr && pr.isDir && !root.portal.directory) root.enter(pr.path);
          else root.portalConfirm();
          return;
        }
        if (event.key === Qt.Key_Escape) {
          event.accepted = true; root.portalCancel(); return;
        }
      }

      // F1 AS THE ONE KEY NOBODY HAS TO BE TOLD. ctrl P is the palette's key
      // and ~ is the one this window has always used, and both of them are
      // things you have to already know. F1 is the key a person presses when
      // they have no idea what the keys are, which is exactly the state this
      // list exists for — so it opens it too, and earns its place by being
      // guessable rather than by being fast.
      if (event.key === Qt.Key_F1) {
        event.accepted = true; cmdPalette.ask(); return;
      }

      // ── a pending prefix owns the next key ──────────────────────────
      if (content.pending !== "") {
        event.accepted = true;
        if (event.key === Qt.Key_Escape) { content.done(); return; }
        // A bare modifier is a key event of its own with no text, and holding
        // shift to reach an upper-case destination sends one before the letter
        // arrives. Treating that as "not a choice, so dismiss" is what made
        // `g` then shift-D impossible: the menu was gone before the D landed.
        if (event.text === "") return;
        const list = content.sequences[content.pending] || [];
        for (const entry of list) {
          if (entry[0] === event.text) {
            content.done();
            entry[2]();
            return;
          }
        }
        // not one of the choices: leave the menu up rather than closing on a
        // stray keystroke
        return;
      }

      // ── escape, in the order things unwind ──────────────────────────
      // Escape unwinds what you are in the middle of, and stops there. It does
      // NOT close the window: a file manager you are browsing should not
      // vanish because you dismissed a filter twice. `q` quits, the way it
      // does in yazi, and a PICKER still cancels on escape — an application is
      // blocked on that answer, so escape means "no" and is handled above.
      if (event.key === Qt.Key_Escape) {
        event.accepted = true;
        if (root.searchMode !== "") root.clearSearch();
        else if (root.query !== "") { chrome.filterField.text = ""; root.act.query = ""; }
        else if (root.visualOn) root.endVisual();
        else if (Object.keys(root.marked).length > 0) root.act.marked = {};
        return;
      }

      // ── the two dividers, from the keyboard ─────────────────────────
      // Alt walks the split, alt+shift walks the sidebar's edge — one hand
      // shape for both lines, and the ARROW POINTS THE WAY THE LINE TRAVELS
      // rather than at whichever pane grows. Which pane grows depends on which
      // side of the divider you are asking about; the divider itself only ever
      // goes left or right, so that is what the key says.
      //
      // BEFORE the movement block below, which takes a bare Left and Right and
      // never looks at the modifiers — so with alt held they meant "up a
      // directory" and "open the file", neither of which is a thing to do by
      // accident while reaching for a resize.
      //
      // Both consume the key even when there is nothing to resize. A binding
      // that quietly turns into a different verb whenever the sidebar happens
      // to be closed is worse than one that does nothing.
      if ((event.modifiers & Qt.AltModifier)
          && (event.key === Qt.Key_Left || event.key === Qt.Key_Right)) {
        event.accepted = true;
        const grow = event.key === Qt.Key_Right ? 1 : -1;
        if (event.modifiers & Qt.ShiftModifier) {
          // PIXELS, because that is what the sidebar is measured in — it is a
          // column of fixed things rather than a share of the window, which is
          // the whole reason sidebarWidth is not a fraction. Clamped to the
          // same bounds the grip drags between, and onSidebarWidthChanged
          // writes it to disk without being asked.
          if (root.sidebar)
            root.sidebarWidth = Math.max(root.sidebarMin,
              Math.min(root.sidebarMax, root.sidebarWidth + grow * 20));
        } else if (root.dual) {
          // A FRACTION, because the split is one — see paneFrac. Stepping in
          // pixels would drift the proportion every time the window resized,
          // which is the thing paneFrac exists to prevent. 2% lands where you
          // meant without making the trip across the pane a drum roll.
          root.paneFrac = Math.max(root.paneMinFrac,
            Math.min(root.paneMaxFrac, root.paneFrac + grow * 0.02));
          opening.viewSave.restart();
        }
        return;
      }

      // ── movement ────────────────────────────────────────────────────
      // The GRID IS TWO-DIMENSIONAL, and it has to be asked first.
      //
      // This block used to sit below the plain up/down handlers, which meant
      // it could never run for them: they matched, moved by one tile, and
      // returned. So the grid navigated in a straight line through a layout
      // that is laid out in rows — down moved you one tile sideways instead of
      // one row down. Left and right reached here only because nothing above
      // claimed them.
      //
      // The letters are not in this block at all: h and l are back and
      // forward in every layout now, so there is no case where they need a
      // second meaning, and only the arrows have two axes to worry about.
      if (root.viewMode === "grid") {
        if (event.key === Qt.Key_Left) {
          event.accepted = true; root.moveSel(-1); return;
        }
        if (event.key === Qt.Key_Right) {
          event.accepted = true; root.moveSel(1); return;
        }
        if (event.key === Qt.Key_Up || event.key === Qt.Key_K) {
          event.accepted = true; root.moveSel(-root.gridCols()); return;
        }
        if (event.key === Qt.Key_Down || event.key === Qt.Key_J) {
          event.accepted = true; root.moveSel(root.gridCols()); return;
        }
      }
      if (event.key === Qt.Key_Up || event.key === Qt.Key_K) {
        event.accepted = true; root.moveSel(-1); return;
      }
      if (event.key === Qt.Key_Down || event.key === Qt.Key_J) {
        event.accepted = true; root.moveSel(1); return;
      }
      // ── THE LETTERS ARE THE TRAIL, THE ARROWS ARE THE TREE ──────────
      // These were yazi's pair for a long time — h up, H back, one the tree
      // and the other the trail.
      //
      // WHAT SHIFT IS FOR. g and G are top and bottom: two ends of ONE axis,
      // and the case is which end. h and H were not that — going up a
      // directory and going back through the trail are two different verbs
      // that happen to start with the same letter, so the capital promised a
      // relationship that is not there and read as "up, but more". Back and
      // forward are their own pair and take their own lowercase keys.
      //
      // BY TEXT, not by key: Key_H is the same code with shift or without, so
      // matching on the key would take H and L as well. Nothing claims the
      // capitals any more.
      //
      // Parent and enter keep the arrows, which is where they were always
      // written down beside the letters anyway — see the keymap's move group.
      // ── THE LETTERS ARE THE TRAIL, THE ARROWS ARE THE TREE ──────────
      // BY TEXT, not by key: Key_H is the same code with shift or without, so
      // matching on the key would take H and L as well.
      //
      // AND THE ARROWS ARE NOT IN IT. They were briefly, on the reasoning that
      // one axis should mean one thing whichever key you reach for — and that
      // is the wrong axis. Left and right are where you ARE, a step out of a
      // directory and a step into the one under the cursor; back and forward are
      // where you have BEEN. Hovering .claude and pressing right has to open
      // .claude, not jump to wherever you were before.
      // ── IN THE LIST, ALL FOUR WORK THE TREE ───────────────────────
      // h / l and the horizontal arrows, with no modifier. A list that is
      // a tree has one horizontal axis and it is the tree's — offering
      // history on the same keys would be two verbs on one gesture, which
      // is the thing g/G was chosen over.
      //
      // Finder's exact pair, and its second step is the part that makes
      // them worth the keys: right on an OPEN directory walks into it rather
      // than doing nothing, and left on a row inside a branch closes the
      // branch it is in. So the two keys alone get you all the way down a
      // tree and all the way back out.
      //
      // Only here. Columns view is already a tree you walk with these, and
      // a results page has no tree at all — both keep back and forward.
      if (root.treeKeys
          && (event.key === Qt.Key_Right || event.key === Qt.Key_Left
              || event.text === "h" || event.text === "l")) {
        event.accepted = true;
        root.treeStepKey(event.key === Qt.Key_Right || event.text === "l");
        return;
      }
      if (event.text === "h") { event.accepted = true; root.back(); return; }
      if (event.text === "l") { event.accepted = true; root.forward(); return; }
      if (event.key === Qt.Key_Left) {
        event.accepted = true; root.goUp(); return;
      }
      // Alt+Return opens the properties of what is selected. It has to be
      // tested BEFORE the plain Return below, which takes any Return at all
      // and opens the file — modifiers and all.
      if ((event.modifiers & Qt.AltModifier)
          && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
        event.accepted = true; props.ask(); return;
      }
      // SHIFT+RETURN IS THE OTHER WAY TO OPEN IT. Before the plain Return
      // below, which takes any Return at all and opens the row in place,
      // modifiers and all.
      //
      // ON A DIRECTORY, in a tab of its own — the keyboard's version of the
      // middle click that already does it. ON A FILE, the open-with sheet:
      // plain Return hands it to whatever owns that kind of file, and the
      // shifted one is where you say which. It used to open the same way
      // Return does, which made the modifier mean nothing over half the rows
      // in the window.
      if ((event.modifiers & Qt.ShiftModifier)
          && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
        event.accepted = true;
        const r = root.currentRow();
        if (r && r.isDir) root.openInNewTab(r.path);
        else if (r) root.beginOpenWith(r.path);
        return;
      }
      // RETURN OPENS. Whatever is under the cursor, file or directory — it is
      // the key that means "do the thing", and over a file the thing is to
      // open it in whatever owns that kind of file.
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        event.accepted = true; root.activate(); return;
      }
      // RIGHT WALKS THE TREE, and only that. It is the other half of left,
      // which goes up; a key whose whole meaning is "go deeper" should not
      // also be able to launch a PDF in a reader. Over a file it does nothing
      // rather than something surprising, and Return is a key away.
      //
      // In grid the arrow has already moved the cursor sideways above — this
      // is the list and the columns, where there is no second axis for it.
      // In the list this never runs — see treeKeys above, which takes Right
      // first. This is the columns view, where right IS the way deeper.
      if (event.key === Qt.Key_Right) {
        event.accepted = true;
        const rr = root.currentRow();
        if (rr && rr.isDir) root.activate();
        return;
      }
      if (event.key === Qt.Key_G) {
        event.accepted = true;
        if (event.modifiers & Qt.ShiftModifier) {
          root.act.sel = Math.max(0, root.view.length - 1);
          root.positionSel();
        } else content.seq("g");
        return;
      }
      if (event.modifiers & Qt.ControlModifier) {
        // Tab cycling and closing, where a browser puts them. Backtab is what
        // Qt reports for ctrl+shift+tab — shift turns the key itself into a
        // different one rather than only appearing in the modifiers.
        if (event.key === Qt.Key_Tab) {
          event.accepted = true;
          root.switchTab((root.tab + 1) % root.tabs.length);
          return;
        }
        if (event.key === Qt.Key_Backtab) {
          event.accepted = true;
          root.switchTab((root.tab - 1 + root.tabs.length) % root.tabs.length);
          return;
        }
        if (event.key === Qt.Key_P) { event.accepted = true; cmdPalette.ask(); return; }
        if (event.key === Qt.Key_C) { event.accepted = true; root.closeTab(); return; }
        if (event.key === Qt.Key_U) { event.accepted = true; root.moveSel(-8); return; }
        if (event.key === Qt.Key_D) { event.accepted = true; root.moveSel(8); return; }
        if (event.key === Qt.Key_B) { event.accepted = true; root.moveSel(-16); return; }
        if (event.key === Qt.Key_F) { event.accepted = true; root.moveSel(16); return; }
        if (event.key === Qt.Key_A) { event.accepted = true; root.selectAll(); return; }
        if (event.key === Qt.Key_R) { event.accepted = true; root.invertSelection(); return; }
        if (event.key === Qt.Key_S) { event.accepted = true; root.openShell(); return; }
        if (event.key === Qt.Key_0) { event.accepted = true; root.zoomReset(); return; }
        // ctrl +/- as well as the bare keys: in the grid these are thumbnail
        // size, and ctrl is where every application puts that
        if (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal) {
          event.accepted = true; root.zoomBy(0.1); return;
        }
        if (event.key === Qt.Key_Minus) {
          event.accepted = true; root.zoomBy(-0.1); return;
        }
      }
      if (event.key === Qt.Key_PageUp)   { event.accepted = true; root.moveSel(-16); return; }
      if (event.key === Qt.Key_PageDown) { event.accepted = true; root.moveSel(16); return; }
      // The Menu (Application) key. No text of its own, so it belongs up here
      // with the named keys rather than in the switch below.
      if (event.key === Qt.Key_Menu)     { event.accepted = true; root.openMenuAtCursor(); return; }
      if (event.key === Qt.Key_Home)     { event.accepted = true; root.act.sel = 0; root.positionSel(); return; }
      if (event.key === Qt.Key_End) {
        event.accepted = true;
        root.act.sel = Math.max(0, root.view.length - 1);
        root.positionSel();
        return;
      }
      if (event.key === Qt.Key_Backspace) { event.accepted = true; root.goUp(); return; }
      // Tab crosses to the other pane, and only when there is one — with a
      // single pane it is left alone rather than bound to something else.
      // TAB REACHES THE NAME FIELD in a save dialog. The keyboard starts in
      // the listing now, because WHERE is the question you are there to
      // answer — but the name still has to be reachable without the mouse,
      // and Tab is the key that moves between the halves of a form. A picker
      // has one pane, so the step-over below is inert in it anyway.
      if (event.key === Qt.Key_Tab && root.picking
          && root.portal.save) {
        event.accepted = true;
        chrome.saveField.forceActiveFocus();
        // the name, not its type: typing replaces "report", keeps ".pdf"
        // (as rename does — Terminus.stem)
        const stem = Terminus.stem(chrome.saveField.text);
        chrome.saveField.select(0, stem.length > 0 ? stem.length : chrome.saveField.text.length);
        return;
      }
      if (event.key === Qt.Key_Tab && root.dual) {
        event.accepted = true; root.stepOver(); return;
      }
      // F5 and F6, where every dual-pane file manager has kept them since the
      // eighties. Inert with one pane rather than bound to something else,
      // because a key that means "to the other side" should not quietly mean
      // something different when there is no other side.
      if (event.key === Qt.Key_F5) { event.accepted = true; root.sendToOther("copy"); return; }
      if (event.key === Qt.Key_F6) { event.accepted = true; root.sendToOther("move"); return; }

      // ── zoom, on the keys everything else uses ──────────────────────
      if (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal) {
        event.accepted = true; root.zoomBy(0.1); return;
      }
      if (event.key === Qt.Key_Minus) {
        event.accepted = true; root.zoomBy(-0.1); return;
      }

      // ── tabs ────────────────────────────────────────────────────────
      if ((event.modifiers & Qt.AltModifier)
          && event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
        event.accepted = true; root.switchTab(event.key - Qt.Key_1); return;
      }
      if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9 && event.text !== "") {
        event.accepted = true; root.switchTab(event.key - Qt.Key_1); return;
      }
      if (event.key === Qt.Key_BracketLeft) {
        event.accepted = true;
        root.switchTab((root.tab - 1 + root.tabs.length) % root.tabs.length);
        return;
      }
      if (event.key === Qt.Key_BracketRight) {
        event.accepted = true;
        root.switchTab((root.tab + 1) % root.tabs.length);
        return;
      }

      if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier)) return;

      // ── everything else, by character so shift is a different key ───
      switch (event.text) {
      // SPACE LOOKS, SHIFT+SPACE SELECTS.
      //
      // Shift does not change what space TYPES, so these cannot be two cases
      // the way `g` and `G` are — the modifier has to be read here. The
      // control and alt guard above lets shift through for exactly this.
      case " ":
        event.accepted = true;
        if (event.modifiers & Qt.ShiftModifier) {
          root.toggleMark(); root.moveSel(1);
        } else {
          root.quickLook();
        }
        break;
      case "y":  event.accepted = true; content.seq("y"); break;
      case "x":  event.accepted = true; content.seq("x"); break;
      case "p":  event.accepted = true; root.paste(); break;
      case "d":  event.accepted = true; root.trash(); break;
      case "D":  event.accepted = true; root.deleteForever(); break;
      case "M":  event.accepted = true; disks.ask(); break;
      case "a":  event.accepted = true; root.beginCreate(); break;
      // ONE KEY, and it does what the selection says. `r` on a row opens that
      // row's name; `r` on nine rows opens the card that renames nine. Having
      // it mean "rename the row under the cursor" while nine were ticked was
      // the one verb in this window that ignored the selection every other
      // verb acts on.
      case "r":
        event.accepted = true;
        if (root.acting().length > 1) root.beginBulkRename();
        else root.beginRename();
        break;
      case ".":  event.accepted = true; root.showHidden = !root.showHidden; break;
      case ";":  event.accepted = true; root.openShell(); break;
      case "f":  event.accepted = true; chrome.filterField.forceActiveFocus(); break;
      case "/":  event.accepted = true; chrome.filterField.forceActiveFocus(); break;
      case "s":  event.accepted = true; root.beginSearch(""); break;
      case "S":  event.accepted = true; root.beginSearch("grep"); break;
      case "t":  event.accepted = true; root.newTab(); break;
      case "w":  event.accepted = true; root.closeTab(); break;
      case "v":  event.accepted = true; root.toggleVisual(); break;
      case "V":  event.accepted = true; root.cycleView(); break;
      case "u":  event.accepted = true; root.undo(); break;
      case "z":  event.accepted = true; root.measureDirs(); break;
      // The row menu and the palette both offer this with `e` beside it,
      // and until now that key only existed inside quick look — so the
      // hint was a promise the listing did not keep.
      case "e":  event.accepted = true; root.extractAudio(); break;
      case "\\": event.accepted = true; root.toggleDual(); break;
      // The SAME KEY WITH SHIFT, because it is the same gesture about the
      // other vertical division of the window: `\` splits the body in two,
      // `|` puts the places column back beside it. onSidebarChanged writes
      // the new state to disk without being asked.
      case "|":  event.accepted = true; root.toggleSidebar(); break;

      case "o":  event.accepted = true; root.stepOver(); break;
      case "q":
        event.accepted = true;
        // A DIALOG ANSWERS RATHER THAN CLOSING. Something is blocked waiting
        // on this window, so walking away from it has to say "no" — and it
        // took the branch below instead, which asks retire() to drop a window
        // that was never in `wins`. That did nothing at all: the dialog stayed
        // open with its request still pending, and the manager went on
        // believing it had a live picker.
        if (root.picking) { root.portalCancel(); break; }
        // the first window hides; a spare one goes away, because a pile of
        // hidden windows nobody can reach is a leak with a keybind
        if (root.winId === 0 || !root.mgr) root.shown = false;
        else root.mgr.retire(root.winId);
        break;
      case "N":
        event.accepted = true;
        if (root.mgr) root.mgr.spawn(root.cwd);
        break;
      case "~":  event.accepted = true; cmdPalette.ask(); break;
      case "g":  event.accepted = true; content.seq("g"); break;
      case "c":  event.accepted = true; content.seq("c"); break;
      case "b":  event.accepted = true; content.seq("b"); break;
      case ",":  event.accepted = true; content.seq(","); break;
      }
    }

    // ── THE GROUND, less the tab strip (see the window's colour) ──────
    Rectangle {
      z: -1
      width: side.width
      height: parent.height
      color: root.ground(root.winAlpha)
    }
    Rectangle {
      z: -1
      x: side.width
      y: chrome.tabStrip.height
      width: parent.width - side.width
      height: parent.height - y
      color: root.ground(root.winAlpha)
    }

    // side, in its own file — see terminus/Sidebar.qml
    Sidebar { id: side; term: root }

    // ── ROWS GO UNDER THE CHROME ─────────────────────────────────────
    // A list or grid's rows scrolled off its top carry on under the bars
    // above it, frosted and fading — see morpheus/ScrollEdge. Declared
    // before the chrome so every strip's translucent ground tints them; each
    // runs from the top of the window down to its view's top edge. Not the
    // miller columns: three views side by side under one bar.
    // The miller columns' too, one each: they fill the frame top to bottom,
    // so each runs down to the frame's top, and slides with its column.
    // Clipped to the listing's side of the window, as millerBox clips them:
    // a column sliding between slots must not take its frost over the
    // sidebar.
    Item {
      x: side.width
      width: parent.width - side.width
      height: parent.height
      clip: true
      visible: chrome.millerBox.visible
      Repeater {
        id: millerEdges
        model: [chrome.colA, chrome.colB, chrome.colC]
        delegate: ScrollEdge {
          required property var modelData
          view: modelData.list
          visible: modelData.list.visible
          opacity: modelData.opacity
          scrim: 0   // laid once, full width — see topScrim
          x: chrome.bodyRow.x + chrome.bodyBox.x + chrome.millerBox.x + chrome.miller.x + modelData.x
          y: 0
          width: modelData.width
          height: chrome.bodyRow.y + chrome.bodyBox.y + chrome.millerBox.y + chrome.miller.y + modelData.y
        }
      }
    }

    Repeater {
      id: listEdges
      model: [chrome.listA, chrome.listB, chrome.gridA, chrome.gridB]
      delegate: ScrollEdge {
        required property var modelData
        view: modelData
        visible: modelData.on
        scrim: 0   // laid once, full width — see topScrim
        x: side.width + chrome.bodyRow.x + chrome.bodyBox.x + modelData.x
        // from the window's top, under the tab strip too: the tabs frost
        // what scrolls up as the bars do (user, 2026-10-09, having first
        // had it cut back to the bar — the tabs are their own glass now)
        y: 0
        width: modelData.width
        height: chrome.bodyRow.y + chrome.bodyBox.y + modelData.y
      }
    }

    // ── AND UNDER THE PICKER'S FOOTER ───────────────────────────────
    // The same thing turned over (ScrollEdge.below): while a portal request
    // is open, rows not yet reached show frosted through the footer, the
    // way the rows gone by show through the bars above. Every view runs
    // down to the body's bottom, which is the footer's top, so each edge is
    // simply the footer's own strip over that view's columns.
    Repeater {
      id: footEdges
      model: [chrome.listA, chrome.listB, chrome.gridA, chrome.gridB]
      delegate: ScrollEdge {
        required property var modelData
        view: modelData
        below: true
        visible: modelData.on && root.picking
        scrim: 0   // see footScrim
        x: side.width + chrome.bodyRow.x + chrome.bodyBox.x + modelData.x
        y: chrome.portalBar.y
        width: modelData.width
        height: chrome.portalBar.height
      }
    }
    Item {
      x: side.width
      y: chrome.portalBar.y
      width: parent.width - side.width
      height: chrome.portalBar.height
      clip: true
      visible: chrome.millerBox.visible && root.picking
      Repeater {
        id: footMillerEdges
        model: [chrome.colA, chrome.colB, chrome.colC]
        delegate: ScrollEdge {
          required property var modelData
          view: modelData.list
          below: true
          visible: modelData.list.visible
          scrim: 0   // see footScrim
          opacity: modelData.opacity
          x: chrome.bodyRow.x + chrome.bodyBox.x + chrome.millerBox.x + chrome.miller.x + modelData.x
          y: 0
          width: modelData.width
          height: chrome.portalBar.height
        }
      }
    }

    // ── ONE SCRIM ACROSS THE CHROME, not one per view ───────────────
    // ScrollEdge lays ground over its own strip while rows are under it, so
    // a bar's words stay legible over the ghosts. Per view, that was a box
    // the width of one column; while the bars had a shade of their own it
    // hid, and once they wore the body (2026-10-09) it showed as a pale
    // block across both tabs (user's capture). So the edges lay none, and
    // this lays it the full width of the listing side, top bars and tabs.
    function edgesOn(rep) {
      for (let i = 0; i < rep.count; ++i) {
        const e = rep.itemAt(i);
        if (e && e.on) return true;
      }
      return false;
    }
    Rectangle {
      id: topScrim
      x: side.width
      width: parent.width - side.width
      height: chrome.bodyRow.y + chrome.bodyBox.y
        + (chrome.millerBox.visible ? chrome.millerBox.y + chrome.miller.y : 0)
      color: Zenon.ground
      opacity: (content.edgesOn(listEdges) || (chrome.millerBox.visible && content.edgesOn(millerEdges)))
        ? 0.35 : 0
      visible: opacity > 0.001
      Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    }
    Rectangle {
      id: footScrim
      x: side.width
      y: chrome.portalBar.y
      width: parent.width - side.width
      height: chrome.portalBar.height
      color: Zenon.ground
      // thicker than the top's: the footer's words (the name being saved,
      // the buttons) sat over bright thumbnails and read faint through 35%
      // (user's picker.png, 2026-10-09) — still frost, just more of a pane
      opacity: root.picking && (content.edgesOn(footEdges)
        || (chrome.millerBox.visible && content.edgesOn(footMillerEdges))) ? 0.62 : 0
      visible: opacity > 0.001
      Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    }

    // chrome, in its own file — see terminus/Chrome.qml
    Chrome { id: chrome; term: root }

    // ── THE HEADING STRIP, PAINTED OVER THE BODY RATHER THAN IN IT ────────
    // With the window split, colHeads collapses to nothing and each half draws
    // its own heading bar INSIDE the body — and the body is the layer that goes
    // soft behind a sheet. A black ground painted in there is blurred together
    // with the rows underneath and comes out a grey band: a lighter strip
    // between a black bar and a black card, which is the whole of what "the
    // header is not opaque" looks like from the outside. Measured at (4,5,5)
    // with the ground in the pane and (0,0,0) with it here.
    //
    // A SIBLING OF THE CHROME, not a child of it: the Column would lay it out
    // as another strip and push the body down by its height. It is positioned
    // against the same three heights the Column stacks, so it lands exactly on
    // the heading bars it is covering and moves with them.
    //
    // ONE PER HALF rather than one across the window, because only a half that
    // is showing a LIST has a heading bar — a single strip would have laid a
    // black band across the top row of a grid beside it.
    Repeater {
      model: 2

      delegate: Rectangle {
        required property int index

        // The sidebar's width, because paneX is measured from the body's left
        // edge and the body begins where the sidebar ends.
        x: side.width + root.paneX(index)
        width: root.paneW(index)
        y: chrome.tabStrip.height + chrome.crumbBar.height + chrome.colHeads.height
        height: root.paneHeadH(index)
        color: Zenon.black
        opacity: root.sheetInk
        visible: height > 0 && opacity > 0.01
      }
    }


    // ── properties ────────────────────────────────────────────────────
    // What the listing cannot fit: the whole path, the owner, the exact byte
    // count, and for a selection the total. `stat` is asked once for the set,
    // the same way the search results are — one process, not one per file.
    Rectangle {
      id: props
      anchors.fill: parent
      z: 13
      visible: opacity > 0.01
      opacity: props.open ? 1 : 0
      // THE SCRIM STOPS AT THE BAR: the bar is this sheet's titlebar,
      // and a scrim laid over it dimmed the title — as the send picker's is.
      color: "transparent"
      Rectangle {
        anchors.fill: parent
        anchors.topMargin: chrome.tabStrip.height + chrome.crumbBar.height
        color: root.cardScrim
      }
      // and the sidebar beside the bar, which is not the titlebar: the
      // scrim stops at the bar, not at the sidebar's first heading
      Rectangle {
        width: side.width
        height: chrome.tabStrip.height + chrome.crumbBar.height
        color: root.cardScrim
      }
      Behavior on opacity { NumberAnimation { duration: props.open ? propsSheet.slideIn : propsSheet.slideOut; easing.type: Zenon.ease } }

      property bool open: false

      // The card itself is PropsCard.qml, shared with picasso. Its state is
      // reached here under the names the rest of this window has always used.
      property alias rows: card.rows
      property alias tab: card.tab
      property alias permCursor: card.permCursor
      property alias permMode: card.permMode
      readonly property alias many: card.many
      readonly property alias hasPerms: card.hasPerms
      property alias walked: card.walked
      property alias owner: card.owner
      property alias imageInfo: card.imageInfo
      property alias files: card.files
      property alias dirs: card.dirs
      property alias checksum: card.checksum
      function ask() { card.ask(); }
      function askPath(path) { card.askPath(path); }
      function show(sel) { card.show(sel); }
      function togglePermBit() { card.togglePermBit(); }
      function applyPerms() { card.applyPerms(); }
      function computeChecksum() { card.computeChecksum(); }
      function handleKey(k) { return card.handleKey(k); }

      InputShield {
        keepTop: chrome.tabStrip.height + chrome.crumbBar.height
        onClicked: { props.open = false; content.forceActiveFocus(); }
      }


      Sheet {
        backdrop: chrome   // frosted over it — see morpheus/Sheet
        splice: true
        onCardInkChanged: root.noteSheet("s0", cardInk, drawnX, drawnW)
        onDrawnXChanged: root.noteSheet("s0", cardInk, drawnX, drawnW)
        onDrawnWChanged: root.noteSheet("s0", cardInk, drawnX, drawnW)
        id: propsSheet
        leftInset: side.width
        floating: false   // hangs from the bar, which carries its title — see barTitle
        title: root.sheetTitle
        glyph: root.sheetGlyph
        titleInk: root.sheetTitleInk
        glyphInk: root.sheetGlyphInk
        shown: props.open
        fromTop: chrome.tabStrip.height + chrome.crumbBar.height
        cardW: card.wantW
        cardH: card.implicitHeight

        PropsCard {
          id: card
          width: parent.width
          host: root
          onOpened: props.open = true
          onClosed: { props.open = false; content.forceActiveFocus(); }
          onMenuWanted: (item, rows) => menuPop.menu.openCustom(item, { x: 0, y: item.height }, rows, false)
        }
      }
    }

    // ── what the prefix key is waiting for ────────────────────────────
    // Yazi shows the continuations of a half-typed sequence along the bottom,
    // which is the difference between a sequence you remember and one you
    // have to look up. Same list, same place. It appears with the prefix and
    // goes the moment the next key lands or the timeout gives up.
    Rectangle {
      id: which
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: content.pending === "" ? 0 : whichFlow.implicitHeight + 20
      // one line, so the bar is a fixed depth whichever prefix is pending
      visible: height > 0
      clip: true
      z: 7
      // THE SHELL'S HINT-BAR GROUND, which every popup with a row of keys
      // along its bottom wears. This strip had its own answer — 86% black with
      // headBg over it — and 86% is not opaque: at a `g` pressed over a file
      // of Lua the code behind it read straight through the hints, which is
      // the exact thing the alpha was there to stop.
      color: Zenon.hintBg
      Behavior on height { NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }

      Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        // the divider every other strip in this window is separated by
        color: Zenon.border
      }

      readonly property var entries:
        content.pending === "" ? [] : (content.sequences[content.pending] || [])

      // ── laid out by hand, so it can WRAP AND STILL BE CENTRED ────────
      //
      // This was a single Row that clipped at both ends when the set was wider
      // than the window — the reasoning being that a Flow can wrap but cannot
      // centre the lines it wraps, so a narrow window would trade a clipped
      // strip for a ragged block. Both halves of that are true, and clipping
      // is still the worse of the two: a hint you cannot see is not a hint.
      //
      // So the break points are worked out here rather than left to a Flow,
      // and each line is its own centred Row. FontMetrics measures the same
      // two fonts the delegates draw with, so the widths it adds up are the
      // widths that get drawn — the chip's padding is the one constant that
      // has to agree with KeyCap (morpheus), and it is written down in both places.
      readonly property real chipPad: Math.round(13 * 1.15)
      readonly property real gap: 22
      readonly property real entryGap: 8

      FontMetrics {
        id: chipFm
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(13)
      }
      FontMetrics {
        id: labelFm
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(15)
      }

      function entryText(e) {
        return (typeof e[1] === "function") ? e[1]() : e[1];
      }
      function keyText(e) { return e[0] === " " ? "space" : e[0]; }

      function entryWidth(e) {
        return chipFm.advanceWidth(which.keyText(e)) + which.chipPad
          + which.entryGap + labelFm.advanceWidth(which.entryText(e));
      }

      // The entries grouped into the lines they will be drawn on. Greedy, which
      // is what you want here: the order is the order the keys are listed in,
      // so a line break must never reorder them to pack better.
      readonly property var lines: {
        const avail = which.width - 32;
        const out = [];
        let cur = [];
        let w = 0;
        for (const e of which.entries) {
          const ew = which.entryWidth(e);
          if (cur.length > 0 && w + which.gap + ew > avail) {
            out.push(cur);
            cur = [];
            w = 0;
          }
          w += (cur.length > 0 ? which.gap : 0) + ew;
          cur.push(e);
        }
        if (cur.length > 0) out.push(cur);
        return out;
      }

      Column {
        id: whichFlow
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 10
        spacing: 6

        Repeater {
          model: which.lines

          delegate: Row {
            required property var modelData
            anchors.horizontalCenter: parent.horizontalCenter
            // wider apart than the two halves of one entry, so a line reads as
            // separate hints rather than one long sentence
            spacing: which.gap

            Repeater {
              model: parent.modelData

              delegate: Row {
                required property var modelData
                spacing: which.entryGap

                KeyCap {
                  anchors.verticalCenter: parent.verticalCenter
                  fontSize: 13
                  // The KEY as something you can read, which is not always the
                  // key itself: the entry that opens the path bar is bound to a
                  // space, and a space drawn in the key column is a gap with a
                  // label floating after it. The binding stays a space — this
                  // is the name of it, not the match.
                  label: which.keyText(modelData)
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  // Static for nearly every entry, and worked out on the spot
                  // for the ones whose meaning depends on what the cursor is on.
                  text: which.entryText(modelData)
                  // same ink and the same weight as the path bar's current
                  // segment, because they are the same kind of statement
                  color: root.crumbInk
                  font.family: Zenon.face
                  font.weight: Font.Medium
                  font.pixelSize: Zenon.px(15)
                }
              }
            }
          }
        }
      }
    }

    // ── clicking away from a pending chord cancels it ─────────────────
    // The hint bar waits for the second key and only Escape ever called it
    // off, so a `g` pressed by mistake sat there holding the keyboard — and
    // the thing you actually do when you have changed your mind is click
    // somewhere, which did nothing to it and then fed it the next keystroke.
    //
    // The click is SWALLOWED rather than passed on, the way dismissing a menu
    // is: the gesture that cancels something should not also do the next
    // thing. Above the bar as well as the rows, so clicking the hints
    // themselves cancels too — they are a reminder, not a set of buttons.
    MouseArea {
      anchors.fill: parent
      z: 8
      enabled: content.pending !== ""
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      onPressed: (m) => { m.accepted = true; content.done(); }
    }

    // ── the keymap, on F1 ─────────────────────────────────────────────
    // The hint strip is gone. A permanent one row of keys could only ever show
    // a fraction of them and cost a strip of the window for the privilege;
    // yazi puts the whole list behind a key, and so does this. ESCAPE closes
    // it, and nothing else does — it is a page you read while you work out
    // which key you wanted, so it has to survive you pressing keys.



    // ── the drawer's list ─────────────────────────────────────────────
    // Hangs off the glyph in the breadcrumb bar and shows every job at once,
    // live. No focus is taken and no shield is laid down: it is a glance, not
    // a dialog, and the listing behind it stays as usable as it was.
    Item {
      id: jobsDrawer
      anchors.fill: parent
      z: 14
      visible: opacity > 0.01
      opacity: jobsDrawer.open ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }

      property bool open: false
      // where the card's TOP RIGHT corner goes, in this item's coordinates —
      // the same arithmetic the prefs panel does from the hamburger
      property real px: 0
      property real py: 0

      function openFrom(item) {
        const p = item.mapToItem(jobsDrawer, item.width, item.height);
        jobsDrawer.px = p.x;
        jobsDrawer.py = p.y + 6;
        jobsDrawer.open = true;
      }

      // ONE DECISION, ASKED FROM BOTH SIDES. The glyph and the card each
      // report whether the pointer is on them; this is the only thing that
      // acts on the answer, so the two cannot disagree about whether the
      // drawer should still be up.
      function settle() {
        if (root.jobsOverGlyph || root.jobsOverCard) {
          jobsLinger.stop();
          jobsDrawer.open = true;
          return;
        }
        jobsLinger.restart();
      }

      // The gap between the glyph and the card is a few pixels of bar, and
      // for those few pixels the pointer is over neither. Closing on the
      // frame that happens would make the drawer impossible to reach.
      Timer {
        id: jobsLinger
        interval: 220
        onTriggered: {
          if (root.jobsOverGlyph || root.jobsOverCard) return;
          jobsDrawer.open = false;
          // You opened it and moved away, so you have read whatever went
          // wrong: the red goes with the pointer rather than sitting there
          // until a timer decides you are done.
          root.clearEndedJobs();
        }
      }

      // the same shadow the menu and the prefs panel carry
      MenuShadow {
        panel: jobsCard
        cornerRadius: 8
        transformOrigin: Item.TopRight
        scale: jobsCard.scale
      }

      // The card itself is morpheus' — the jobs are the shell's now, not
      // this window's, and the bar draws the same card. See Jobs.qml.
      JobsCard {
        id: jobsCard
        x: Math.round(Math.max(4,
             Math.min(jobsDrawer.px - jobsCard.width, jobsDrawer.width - jobsCard.width - 4)))
        y: Math.round(Math.max(4,
             Math.min(jobsDrawer.py, jobsDrawer.height - jobsCard.height - 4)))
        shown: jobsDrawer.opacity
        onHoveredChanged: {
          root.jobsOverCard = jobsCard.hovered;
          jobsDrawer.settle();
        }
      }
    }

    // ── the dialogs' keyboard ─────────────────────────────────────────
    // ONE ITEM THAT ACTUALLY HAS FOCUS.
    //
    // The confirm card used to carry `focus: confirm.open` on an item of its
    // own, which makes that item focused within ITS scope and nothing more —
    // `content` holds the window's active focus, so the card's Return never
    // arrived. The card appeared, showed you two buttons and would not take an
    // answer from the keyboard: "delete doesn't work".
    //
    // Putting the dispatch in content's own handler is not enough either,
    // because that only works while content is the thing with focus. So this
    // ASKS for the keyboard when a dialog opens, keeps asking until it has it
    // the way the window's focusClaim does, and hands it back on the way out.
    //
    // The collection editor is excluded: it holds TextInputs that take focus
    // for themselves and need the letters — SEVERAL of them, plus a tab ring
    // walking between them, and this claim was pulling focus back out from
    // under whichever one the ring had just handed it to.
    // ── WHERE EVERY DROPDOWN'S LIST IS DRAWN ──────────────────────────
    // At WINDOW scope, not inside the sheet that owns the dropdown, and
    // that is the whole point of it.
    //
    // A sheet is as tall as its own content. A new collection has one rule,
    // so its card is about 165px — and a list of seven options is 210. It
    // did not matter whether the list hung down or flipped up or clamped
    // itself politely: there was never room inside that card, and there
    // never will be for a card that has just been opened. Measured against
    // the WINDOW there is always room.
    //
    // Empty until a list moves in, and an Item with no MouseArea of its own
    // takes no events while it is.
    Item {
      id: dropLayer
      anchors.fill: parent
      // Over the sheets, which sit at 13–15. Under nothing that matters:
      // menus and quick look are separate surfaces entirely.
      z: 30

      // Clicking anywhere else puts the open list away, which is what a
      // menu does. Declared FIRST, so the lists that arrive here at runtime
      // sit above it and keep their rows.
      MouseArea {
        anchors.fill: parent
        enabled: root.bulkOpenDrop !== null
        onClicked: root.bulkOpenDrop = null
      }
    }

    // dialogKeys, in its own file — see terminus/DialogKeys.qml
    DialogKeys { id: dialogKeys; term: root }

    // ── what a drag out of this window IS ─────────────────────────────
    // One item for every drag a row or tile starts, rather than an attached
    // Drag group on each delegate. A delegate dies whenever its listing is
    // rebuilt, and opening a directory on hold (springTimer) rebuilds the
    // listing the drag came from — which took the drag, and the only thing
    // that ever cleared draggingRow, down with it. So opening on hold used to
    // be refused in the source pane. This lives as long as the window does,
    // and the rows only say WHEN (their DragHandlers, via root.beginDrag).
    //
    // Artemis' shape otherwise, which drags into other applications
    // successfully: `Drag.source` and `Drag.keys` both set, or startDrag()
    // returns false with no warning and nothing anywhere accepts the drag.
    //
    // CopyAction only, like artemis. A move offered over the wayland data-device
    // means the source has to delete the file when the target says it took it,
    // and nothing here implements that half — so offering it would be a
    // promise terminus cannot keep. Moving between terminus windows is `x` then `p`.
    Item {
      id: dragProxy
      x: -4000
      width: 1
      height: 1
      property string uris: ""
      Drag.active: false
      Drag.source: dragProxy
      Drag.keys: ["text/uri-list"]
      Drag.mimeData: ({ "text/uri-list": dragProxy.uris })
      Drag.supportedActions: Qt.CopyAction
      Drag.dragType: Drag.Automatic
      Drag.onDragFinished: (dropAction) => {
        dragProxy.Drag.active = false;
        root.draggingRow = false;
        root.dragPaths = [];
      }
    }

    // ── what the pointer carries while dragging ───────────────────────
    // The suite's drag card — see DragCard.qml, and dragPicture.
    DragCard { id: dragCard }

    // prefs, in its own file — see terminus/PrefsSheet.qml
    PrefsSheet { id: prefs; term: root }

    // ── the right-click menu ──────────────────────────────────────────
    // What you can do to the thing under the pointer. Everything here has a
    // key as well; this is the half of the interface for the hand that is
    // already on the mouse.
    // ── CLICKS THAT LAND NOWHERE NEAR THE CARD ───────────────────────────
    // The menu's own catcher went with it onto its surface, and that surface
    // is only as big as the card plus the room its shadow needs. A click
    // further out than that lands on this window instead, where nothing was
    // listening any more — so the menu sat there until it was answered. This
    // is the other half of the same catcher.
    MouseArea {
      anchors.fill: parent
      z: 8
      visible: menuPop.menu.open
      enabled: menuPop.menu.open
      acceptedButtons: Qt.AllButtons
      onClicked: menuPop.menu.close()
    }

    // ── AND CLICKS THAT LAND OUTSIDE TERMINUS ALTOGETHER ────────────────
    // The catcher above only hears this window. A click on the desktop or
    // on another program went to that program, and the card — a popup of
    // its own — stayed floating over whatever you had moved on to.
    //
    // NOT A FOCUS GRAB. That was the first answer and it broke the
    // submenus: a submenu is a surface of its own that only exists once it
    // opens, so the first click on it landed outside the grab, the grab
    // cleared, and the whole menu shut — "Open with" could be seen and not
    // used. Asked instead of Qt, which already knows: the menu goes when
    // none of the three windows it lives across is the active one. Checked
    // a beat after focus moves, because moving between them passes through
    // a frame where neither side has it yet.
    readonly property bool menuFocusHere: content.Window.active
      || menuPop.menuCard.Window.active || (menuPop.subPop.visible && menuPop.subCard.Window.active)
    onMenuFocusHereChanged: if (menuPop.menu.open) menuAway.restart()
    Timer {
      id: menuAway
      interval: 120
      onTriggered: if (menuPop.menu.open && !content.menuFocusHere) menuPop.menu.close()
    }

    // menuPop, in its own file — see terminus/RowMenu.qml
    RowMenu { id: menuPop; term: root }


    // ── bulk rename ───────────────────────────────────────────────────
    // The card is BulkRename.qml, shared with picasso's viewer: it edits the
    // names, and hands back the moves for this window to run as a job.
    BulkRename {
      backdrop: chrome   // frosted over it — see morpheus/Sheet
      id: bulk
      z: 15
      host: root
      hangs: true
      onCardInkChanged: root.noteSheet("bulk", cardInk, drawnX, drawnW)
      onDrawnXChanged: root.noteSheet("bulk", cardInk, drawnX, drawnW)
      onDrawnWChanged: root.noteSheet("bulk", cardInk, drawnX, drawnW)
      topInset: chrome.tabStrip.height + chrome.crumbBar.height
      leftInset: side.width
      scrim: root.cardScrim
      wheelStep: root.wheelStep
      title: root.sheetTitle
      glyph: root.sheetGlyph
      titleInk: root.sheetTitleInk
      glyphInk: root.sheetGlyphInk
      onRenamed: (moves) => {
        if (moves.length === 0) { root.status = "no names changed"; return; }
        root.run(Terminus.bulkRenameApply(moves));
        root.status = "renamed " + moves.length;
      }
      onClosed: content.forceActiveFocus()
    }


    // ── the confirmation ──────────────────────────────────────────────
    // Everything that overwrites or deletes comes through here. Same shape as
    // zeus' kill card, and for the same reason: the thing you are about to act
    // on stays on screen behind the question, dimmed, so you can still read
    // what you picked while you answer for it.
    Rectangle {
      id: confirm
      anchors.fill: parent
      z: 10
      visible: opacity > 0.01
      opacity: confirm.open ? 1 : 0
      // THE SCRIM STOPS AT THE BAR: the bar is this sheet's titlebar,
      // and a scrim laid over it dimmed the title — as the send picker's is.
      color: "transparent"
      Rectangle {
        anchors.fill: parent
        anchors.topMargin: chrome.tabStrip.height + chrome.crumbBar.height
        color: root.cardScrim
      }
      // and the sidebar beside the bar, which is not the titlebar: the
      // scrim stops at the bar, not at the sidebar's first heading
      Rectangle {
        width: side.width
        height: chrome.tabStrip.height + chrome.crumbBar.height
        color: root.cardScrim
      }
      Behavior on opacity { NumberAnimation { duration: confirm.open ? confirmSheet.slideIn : confirmSheet.slideOut; easing.type: Zenon.ease } }

      property bool open: false
      property string heading: ""
      // a line, or [key, line] — see ConfirmBody
      property var detail: ""
      // what it is about, one a line — see ConfirmBody
      property var items: []
      // Which choice the keyboard is on. Starts at 0 — the verb, listed first
      // — so Return still means what it always meant.
      property int pick: 0
      // Every button on the card, Cancel included: { label, ink, act }. A LIST
      // rather than a fixed yes/no pair, because a paste onto a name that is
      // already taken has three real answers and cramming a third one into a
      // second dialog would have been two cards that drift apart.
      property var choices: []

      // Red is reserved for what cannot be undone. Trash is recoverable, so it
      // is a warning colour and not an alarm.
      function verbInk(verb) {
        if (verb === "Delete" || verb === "Format") return Zenon.red;
        if (verb === "Trash") return Zenon.yellow;
        return Zenon.sand;
      }

      // AND ITS MARK, off the same word, so the two cannot come to disagree
      // about which question is being asked. A bin for the one that can be
      // undone and a cross for the one that cannot — the same split verbInk
      // already draws in yellow and red, and it inks this too. Every other
      // question gets none: a picture makes none of them clearer.
      function verbGlyph(verb) {
        if (verb === "Delete" || verb === "Format") return "\uF00D";
        if (verb === "Trash") return "\uF014";
        return "";
      }

      // The two-button case, which is most of them, in the shape every existing
      // caller already uses.
      function ask(heading, detail, verb, onYes, items) {
        confirm.askMany(heading, detail,
          [{ label: verb, ink: confirm.verbInk(verb), act: onYes }], items);
      }

      // Cancel is appended here rather than passed in: every one of these can
      // be backed out of, and a caller that forgot to offer the way out would
      // be a dialog with no way out.
      function askMany(heading, detail, choices, items) {
        confirm.items = items || [];
        const all = choices.slice();
        all.push({ label: "Cancel", ink: Zenon.muted, act: null });
        confirm.pick = 0;
        confirm.heading = heading;
        confirm.detail = detail;
        confirm.choices = all;
        // focus is not claimed here: the item that reads these keys is
        // dialogKeys, which watches `open` on all three dialogs and takes
        // focus itself, with a retry — a delegate that the scene has not
        // finished placing silently drops forceActiveFocus().
        confirm.open = true;
      }

      function choose(i) {
        const c = confirm.choices[i];
        confirm.open = false;
        confirm.choices = [];
        content.forceActiveFocus();
        if (c && c.act) c.act();
      }

      // Enter takes the FIRST choice — the primary one, listed first for that
      // reason — and escape takes none of them.
      function accept() { confirm.choose(0); }

      function dismiss() {
        confirm.open = false;
        confirm.choices = [];
        content.forceActiveFocus();
      }

      InputShield { keepTop: chrome.tabStrip.height + chrome.crumbBar.height; onClicked: confirm.dismiss() }


      // The panel shadow every card on this desktop casts — icarus'
      // shadow, and now this window's too. A card is a card: one of
      // them wearing a shadow of its own was two answers to the same
      // question.
      // PICASSO'S CARD, NOW SHARED (ConfirmBody): the question in the card
      // with its mark, a muted line, the items one a line, the answers at the
      // bottom right — the way out on the left, the verb at the far right.
      // Attached under the bars as picasso's is, so the bar keeps its
      // breadcrumb rather than repeating the question.
      Sheet {
        backdrop: chrome   // frosted over it — see morpheus/Sheet
        splice: true
        onCardInkChanged: root.noteSheet("s2", cardInk, drawnX, drawnW)
        onDrawnXChanged: root.noteSheet("s2", cardInk, drawnX, drawnW)
        onDrawnWChanged: root.noteSheet("s2", cardInk, drawnX, drawnW)
        id: confirmSheet
        leftInset: side.width
        shown: confirm.open
        fromTop: chrome.tabStrip.height + chrome.crumbBar.height
        // wider once there are more than two answers, so "Keep both" is not
        // squeezed into a column narrower than its own label
        // ONE ROW NOW (see ConfirmBody.headless): the question is on the
        // bar, so the card is the line and the answers side by side — as
        // wide as that row wants, never narrower than it was.
        cardW: Math.max(confirm.choices.length > 2 ? 600 : 480, confirmBody.implicitWidth)
        cardH: confirmBody.implicitHeight

        ConfirmBody {
          id: confirmBody
          headless: true
          width: parent.width
          height: parent.height
          question: confirm.heading
          glyph: confirm.choices.length > 0 ? confirm.verbGlyph(confirm.choices[0].label) : ""
          glyphInk: confirm.choices.length > 0 ? confirm.choices[0].ink : Zenon.white
          detail: confirm.detail
          items: confirm.items
          choices: confirm.choices
          pick: confirm.pick
          onPicked: (i) => confirm.pick = i
          // one definition of what choosing means — Return goes through
          // choose(pick) and so does a click
          onChose: (i) => confirm.choose(i)
        }
      }
    }

    // cmdPalette, in its own file — see terminus/CommandPalette.qml
    CommandPalette { id: cmdPalette; term: root }


    // ── THE BOOKMARKS, ON g b ─────────────────────────────────────────────
    // They are in the sidebar and they are among the go sheet's roots, and
    // neither is the same thing as asking for them: the sidebar is a panel you
    // keep open or you do not, and the go sheet answers "where to?" with every
    // root it has. This answers "which bookmark?" and nothing else.
    //
    // The palette's shape, because it is the palette's problem — a short list
    // ── A DISK WAS PLUGGED IN ─────────────────────────────────────────────
    // Asked the moment one appears unmounted: mount it, or leave it be. It is
    // not one disk at a time. Plugging in three sticks, or one drive with
    // three partitions, is one question with three answers — so while the
    // card is up, anything else that arrives joins it rather than queueing a
    // second card behind the first.
    //
    // One disk: Mount mounts it and goes there, which is what plugging a
    // disk in and saying yes means. More than one: each row has a Mount of
    // its own, and the button at the foot becomes Mount all. The card stays
    // up after a Mount all, so you can see where each one landed and go to
    // whichever you wanted.
    //
    // The rows read root.disks, so a disk pulled out again leaves the card,
    // and one mounted by anything else says so. With none left it closes.
    Rectangle {
      id: plug
      anchors.fill: parent
      z: 13
      visible: opacity > 0.01
      opacity: plug.open ? 1 : 0
      // THE SCRIM STOPS AT THE BAR: the bar is this sheet's titlebar,
      // and a scrim laid over it dimmed the title — as the send picker's is.
      color: "transparent"
      Rectangle {
        anchors.fill: parent
        anchors.topMargin: chrome.tabStrip.height + chrome.crumbBar.height
        color: root.cardScrim
      }
      // and the sidebar beside the bar, which is not the titlebar: the
      // scrim stops at the bar, not at the sidebar's first heading
      Rectangle {
        width: side.width
        height: chrome.tabStrip.height + chrome.crumbBar.height
        color: root.cardScrim
      }
      Behavior on opacity {
        NumberAnimation {
          duration: plug.open ? plugSheet.slideIn : plugSheet.slideOut
          easing.type: Zenon.ease
        }
      }

      property bool open: false
      property int sel: 0
      // device paths asked about this time, in the order they arrived
      property var paths: []
      // the one disk to go to once it is mounted — the single-disk Mount
      property string goAfter: ""

      readonly property var rows: {
        const out = [];
        for (const p of plug.paths)
          for (const d of root.disks) if (d.path === p) { out.push(d); break; }
        return out;
      }
      readonly property bool many: plug.rows.length > 1
      readonly property int waiting: plug.rows.filter(d => d.mount === "").length

      function add(list) {
        const ps = plug.open ? plug.paths.slice() : [];
        for (const d of list) if (ps.indexOf(d.path) < 0) ps.push(d.path);
        plug.paths = ps;
        if (!plug.open) { plug.sel = 0; plug.goAfter = ""; }
        plug.open = true;
      }

      // After every poll: go to the disk that was waiting to be mounted, and
      // close once every disk it asked about has been pulled out again.
      function settle() {
        if (!plug.open) return;
        if (plug.goAfter !== "") {
          for (const d of root.disks) {
            if (d.path !== plug.goAfter || d.mount === "") continue;
            plug.goAfter = "";
            plug.dismiss();
            root.goTo(d.mount);
            return;
          }
        }
        if (plug.rows.length === 0) plug.dismiss();
        else if (plug.sel >= plug.rows.length) plug.sel = plug.rows.length - 1;
      }

      function dismiss() {
        plug.open = false;
        content.forceActiveFocus();
      }

      function step(d) {
        const n = plug.rows.length;
        if (n > 0) plug.sel = (plug.sel + d + n) % n;
      }

      function mountOne(i) {
        const d = plug.rows[i];
        if (!d) return;
        if (d.mount !== "") { plug.dismiss(); root.goTo(d.mount); return; }
        root.mountDisk(d);
      }

      function inspect(i) {
        const d = plug.rows[i];
        if (d) diskInfo.ask(d);
      }

      // The foot's button, and Return.
      function primary() {
        if (!plug.many) {
          const d = plug.rows[0];
          if (!d) return;
          if (d.mount !== "") { plug.dismiss(); root.goTo(d.mount); return; }
          plug.goAfter = d.path;
          root.mountDisk(d);
          return;
        }
        if (plug.waiting === 0) { plug.dismiss(); return; }
        for (const d of plug.rows) if (d.mount === "") root.mountDisk(d);
      }

      InputShield { keepTop: chrome.tabStrip.height + chrome.crumbBar.height; onClicked: plug.dismiss() }

      Sheet {
        backdrop: chrome   // frosted over it — see morpheus/Sheet
        splice: true
        onCardInkChanged: root.noteSheet("s4", cardInk, drawnX, drawnW)
        onDrawnXChanged: root.noteSheet("s4", cardInk, drawnX, drawnW)
        onDrawnWChanged: root.noteSheet("s4", cardInk, drawnX, drawnW)
        id: plugSheet
        leftInset: side.width
        floating: false   // hangs from the bar, which carries its title — see barTitle
        title: root.sheetTitle
        glyph: root.sheetGlyph
        titleInk: root.sheetTitleInk
        glyphInk: root.sheetGlyphInk
        shown: plug.open
        fromTop: chrome.tabStrip.height + chrome.crumbBar.height
        cardW: 640
        cardH: plugBody.wantH

        PlugBody {
          id: plugBody
          anchors.fill: parent
          rows: plug.rows
          sel: plug.sel
          goAfter: plug.goAfter
          wheelStep: root.wheelStep
          onSelected: (i) => plug.sel = i
          onMountOne: (i) => plug.mountOne(i)
          onInspect: (i) => plug.inspect(i)
          onPrimary: plug.primary()
          onDismissed: plug.dismiss()
        }
      }
    }

    // diskInfo, in its own file — see terminus/DiskInfoSheet.qml
    DiskInfoSheet { id: diskInfo; term: root }

    // ── CHECK, REPAIR OR FORMAT A DISK ─────────────────────────────────
    // From a disk's menu. The card is terminus/DiskTool.qml; this is the
    // sheet it hangs in, under the confirmation sheet (z 9 against its 10)
    // because formatting asks there before it erases anything.
    Rectangle {
      id: diskTool
      anchors.fill: parent
      z: 9
      visible: opacity > 0.01
      opacity: diskTool.open ? 1 : 0
      color: "transparent"
      Rectangle {
        anchors.fill: parent
        anchors.topMargin: chrome.tabStrip.height + chrome.crumbBar.height
        color: root.cardScrim
      }
      Rectangle {
        width: side.width
        height: chrome.tabStrip.height + chrome.crumbBar.height
        color: root.cardScrim
      }
      Behavior on opacity {
        NumberAnimation {
          duration: diskTool.open ? diskToolSheet.slideIn : diskToolSheet.slideOut
          easing.type: Zenon.ease
        }
      }

      property bool open: false
      property string path: ""
      property string mode: "repair"
      // The installed tools, asked once per opening — see Terminus.fsToolsCommand.
      property var have: ({})
      // The disk as it was asked about, held: a format or a repair unmounts
      // it, and a card that followed the live record would rewrite itself
      // under the run that is changing it.
      property var held: null

      function ask(d, mode) {
        diskTool.path = d.path;
        diskTool.held = d;
        diskTool.mode = mode;
        diskTool.open = true;
        toolScan.running = true;
        diskToolBody.reset();
        diskToolClaim.restart();
      }
      function dismiss() {
        if (diskToolBody.running) return;
        diskTool.open = false;
        content.forceActiveFocus();
      }

      Process {
        id: toolScan
        command: ["sh", "-c", Terminus.fsToolsCommand()]
        stdout: StdioCollector {
          waitForEnd: true
          onStreamFinished: {
            diskTool.have = Terminus.parseFsTools(text);
            diskToolBody.reset();
          }
        }
      }

      Timer {
        id: diskToolClaim
        interval: 40
        repeat: true
        property int tries: 0
        onRunningChanged: if (running) tries = 0
        onTriggered: {
          if (!diskTool.open || diskToolBody.activeFocus || tries++ > 12) { stop(); return; }
          diskToolBody.forceActiveFocus();
        }
      }

      InputShield { keepTop: chrome.tabStrip.height + chrome.crumbBar.height; onClicked: diskTool.dismiss() }

      Sheet {
        backdrop: chrome
        splice: true
        onCardInkChanged: root.noteSheet("disktool", cardInk, drawnX, drawnW)
        onDrawnXChanged: root.noteSheet("disktool", cardInk, drawnX, drawnW)
        onDrawnWChanged: root.noteSheet("disktool", cardInk, drawnX, drawnW)
        id: diskToolSheet
        leftInset: side.width
        floating: false
        title: root.sheetTitle
        glyph: root.sheetGlyph
        titleInk: root.sheetTitleInk
        glyphInk: root.sheetGlyphInk
        shown: diskTool.open
        fromTop: chrome.tabStrip.height + chrome.crumbBar.height
        cardW: diskTool.mode === "format" ? 680 : 600
        cardH: diskToolBody.implicitHeight

        DiskTool {
          id: diskToolBody
          width: parent.width
          height: parent.height
          host: root
          disk: diskTool.held
          mode: diskTool.mode
          have: diskTool.have
          onClosed: diskTool.dismiss()
        }
      }
    }

    // disks, in its own file — see terminus/DisksSheet.qml
    DisksSheet { id: disks; term: root }

    // collEdit, in its own file — see terminus/CollEditSheet.qml
    CollEditSheet { id: collEdit; term: root }

    // tagPick, in its own file — see terminus/TagPickSheet.qml
    TagPickSheet { id: tagPick; term: root }

    // marks, in its own file — see terminus/MarksSheet.qml
    MarksSheet { id: marks; term: root }

    // ── QUICK LOOK ────────────────────────────────────────────────────────
    // The preview the pane already worked out, at the size of the window. It
    // starts nothing and asks for nothing: previewKind, previewText and the
    // cached frame are all standing answers about the row under the cursor by
    // the time this opens.

    // sendTo, in its own file — see terminus/SendToSheet.qml
    SendToSheet { id: sendTo; term: root }



    // ── choosing an application by hand ───────────────────────────────
    // Reached from the menu's "Open with…" — the shape that row takes when
    // NOTHING already handles the file's type. Everything installed is in
    // here, because the whole reason this card is open is that the short list
    // was empty.
    //
    // What you choose is registered against the TYPE on its way to opening
    // the file, so this is a card you visit once per kind of file rather than
    // once per file. See adoptAppCommand.
    Rectangle {
      id: appPick
      anchors.fill: parent
      z: 16
      visible: opacity > 0.01
      opacity: appPick.open ? 1 : 0
      // THE SCRIM STOPS AT THE BAR: the bar is this sheet's titlebar,
      // and a scrim laid over it dimmed the title — as the send picker's is.
      color: "transparent"
      Rectangle {
        anchors.fill: parent
        anchors.topMargin: chrome.tabStrip.height + chrome.crumbBar.height
        color: root.cardScrim
      }
      // and the sidebar beside the bar, which is not the titlebar: the
      // scrim stops at the bar, not at the sidebar's first heading
      Rectangle {
        width: side.width
        height: chrome.tabStrip.height + chrome.crumbBar.height
        color: root.cardScrim
      }
      Behavior on opacity { NumberAnimation { duration: appPick.open ? appSheet.slideIn : appSheet.slideOut; easing.type: Zenon.ease } }

      // THE CARD IS AppPicker.qml — shared with artemis, which raises the same
      // one over itself for a file nothing opens. What stays here is what is
      // terminus' own: the scrim, the sheet it hangs in, the row's glyph for
      // the title, and what choosing actually runs.
      property alias open: appPicker.open
      property alias paths: appPicker.paths
      property alias path: appPicker.path
      // As permissions does: what the row looked like in the listing, kept
      // beside the paths. Only for one file — several at once have no single
      // glyph, and the title says so.
      property string icon: ""
      property color iconInk: Zenon.white

      function ask(paths, openFiles) {
        const list = (paths && paths.length !== undefined)
          ? paths : [String(paths || "")];
        const lead = list.length === 1 ? root.rowFor(list[0]) : null;
        appPick.icon = lead && lead.glyph !== undefined ? lead.glyph : "";
        appPick.iconInk = lead ? root.inkFor(lead) : Zenon.white;
        appPicker.ask(list, openFiles);
      }

      function dismiss() { appPicker.dismiss(); }

      // Run it, and remember it. The status line says which of the two
      // happened: a file whose type could not be named is opened and nothing
      // is learned from it, and claiming otherwise would be a lie about what
      // the next right-click will show.
      function run(app, mime, paths, openFiles) {
        const n = paths.length;
        // Only registered, from the properties card — see beginOpenWith.
        if (!openFiles) {
          root.run(Terminus.setDefaultAppCommand(app.id, mime));
          root.status = mime + " now opens with " + app.name;
          fileOps.rescanTick.restart();
          return;
        }
        // The type is adopted ONCE, on the row the menu opened on, and the
        // rest are launched. Registering per file would be the same statement
        // made three times.
        root.run(Terminus.adoptAppCommand(app.id, mime, paths[0]));
        for (let i = 1; i < n; ++i)
          root.run(Terminus.openWithCommand(app.id, paths[i]));
        root.status = mime !== ""
          ? mime + " now opens with " + app.name
          : (n > 1 ? n + " opened with " + app.name
                   : "opened with " + app.name);
        // the scan behind the menu is stale the moment that lands — and
        // it is ASKED AGAIN, not just marked stale. Marking it was all this
        // did, so the card said "…" for as long as it stayed open.
        root.openWithApps = [];
        root.appsScanned = false;
        fileOps.rescanTick.restart();
      }

      InputShield { keepTop: chrome.tabStrip.height + chrome.crumbBar.height; onClicked: appPick.dismiss() }

      // The panel shadow every card on this desktop casts — icarus'
      // shadow, and now this window's too. A card is a card: one of
      // them wearing a shadow of its own was two answers to the same
      // question.
      Sheet {
        backdrop: chrome   // frosted over it — see morpheus/Sheet
        splice: true
        onCardInkChanged: root.noteSheet("s10", cardInk, drawnX, drawnW)
        onDrawnXChanged: root.noteSheet("s10", cardInk, drawnX, drawnW)
        onDrawnWChanged: root.noteSheet("s10", cardInk, drawnX, drawnW)
        id: appSheet
        leftInset: side.width
        floating: false   // hangs from the bar, which carries its title — see barTitle
        title: root.sheetTitle
        glyph: root.sheetGlyph
        titleInk: root.sheetTitleInk
        glyphInk: root.sheetGlyphInk
        shown: appPick.open
        fromTop: chrome.tabStrip.height + chrome.crumbBar.height
        cardW: 560
        // As tall as it needs and no taller: a filter over four hundred
        // entries usually leaves three, and a card that stayed full height
        // around them would be mostly empty box.
        cardH: appPicker.implicitHeight

        AppPicker {
          id: appPicker
          width: parent.width
          host: root
          wheelStep: root.wheelStep
          handlers: root.openWithApps
          defaultId: root.openWithDefault
          mime: root.openWithMime
          onChosen: (app, mime, paths, openFiles) => appPick.run(app, mime, paths, openFiles)
          onRemoveRequested: (id) => root.removeApp(id)
          onNotice: (text) => { root.status = text; }
          onDismissed: content.forceActiveFocus()
        }
      }
    }
  }







  // ── a scrollbar you can actually grab ───────────────────────────────────
  // The rest of the shell wears a 3px position REPORT — right for a popup
  // where the wheel is the only thing that scrolls. A directory of thumbnails is
  // a different problem: it can be hundreds of tiles deep, and dragging to the
  // middle of it beats forty flicks of the wheel.
  //
  // Takes its target as a PROPERTY rather than reaching for an id, because an
  // inline component cannot see the ids of the document that declares it.
  //
  // It hides itself when everything already fits, so attaching one to a view
  // costs nothing in the common case of a short directory.

  // The row flash (RowFlash.qml, FlashOver.qml) lived here; it has its own
  // files now, because the open-with card (AppPicker.qml) is shared with
  // artemis and takes it along.

  // ── THE SELECTION, AS ONE BAR THAT MOVES ────────────────────────────────
  // A fill on each delegate cannot travel: the row you leave and the row you
  // arrive at are two different rectangles, so the mark blinks off one and on
  // to the other. The view's own `highlight` is no good either — these views
  // call positionViewAtIndex on every index change, and repositioning the view
  // snaps the highlight to its new row. Measured: with the duration set to
  // five SECONDS the highlight still arrived within one frame.
  //
  // So it is a bar of ours, on its own layer under the list and clipped to it
  // so it cannot ride out over a footer when the list is scrolled. A SIBLING
  // of the view, because a child of it is a child of contentItem, and the view
  // manages the geometry of what it holds.
  //
  // THE ROW IS ANIMATED AND THE SCROLL IS NOT. One expression for both eases
  // the list's own scrolling as well, so the bar lags behind the rows it is
  // marking; the slot is where the cursor is and travels, contentY is where
  // the list has got to and is followed exactly.
  // The grid's cursor is SelectCell.qml, the list's SelectBar.qml.













  // ── why there is no elastic here ────────────────────────────────────────
  // There was, three times over, and it cannot coexist with the rule above.
  //
  // The rows divide the pane exactly so that nothing is ever half drawn. Any
  // give displaces them, and displacing them reveals a strip at one edge and
  // cuts a row off at the other — so every elastic bounce clips precisely what
  // the fitting exists to prevent, and a gentler bounce only clips less. The
  // last attempt got around it by making the displacement fall off with
  // distance so the far edge never moved, which works and reads as the list
  // stretching; it was still a lot of machinery running on every row to buy an
  // effect that has to fight the layout to exist.
  //
  // One or the other. Not clipping won. If elastic is ever wanted back, this
  // is the trade being reopened, not a bug being fixed.
  //
  // Two things it is worth not rediscovering: a WheelHandler declared inside a
  // Flickable never fires at all — Flickable's default property parents
  // non-Item children to contentItem as a plain QObject, so the handler is
  // registered on nothing (the overlay below says the same) — and Qt's own
  // overshoot is unreachable from here anyway, because the wheel is taken by
  // that overlay and never reaches the flick engine.





  // The status chip's message in full, while the pointer is on a chip that
  // had to cut it — see statusChip.cap.
  StatusNote {
    parent: root.contentItem
    z: 60
    anchorItem: chrome.statusChip
    text: chrome.statusChip.shown
    bad: chrome.statusChip.shownBad
    open: chrome.statusChipMa.containsMouse && chrome.statusChip.cut && root.status !== ""
  }

  // dropAsk, in its own file — see terminus/DropAsk.qml
  DropAsk { id: dropAsk; term: root }

  // Quick look, in its own file — see terminus/QuickLook.qml
  QuickLook {
    id: lookLayer
    root: root
    card: card
    facts: chrome.facts
    previewBody: chrome.previewBody
  }


}
