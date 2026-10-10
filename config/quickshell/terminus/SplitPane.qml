// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// Terminus' the second pane … logic, out of TerminusWindow.qml
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
  id: splitPane
  property var term: null
  readonly property alias thumbRetry: thumbRetry
  readonly property alias warmAim: warmAim

  // With one pane, side 0 is the whole body and side 1 is not drawn. These
  // are functions rather than four more properties because a binding that
  // calls one still depends on everything the call reads.
  function paneX(side) {
    if (!term.dual) return 0;
    return side === 0 ? 0 : term.paneSplit + 1;
  }
  function paneW(side) {
    if (!term.dual) return term.chromeRef.bodyBox.width;
    return side === 0 ? term.leftPaneW : term.rightPaneW;
  }
  // 22px of headings when this half is a list, nothing when it is not. With
  // one pane the strip above the body does this job; with two it has to
  // happen per pane, or the two halves cannot differ.
  function paneHeadH(side) {
    if (!term.dual) return 0;
    const p = side === 0 ? paneL : term.paneRRef;
    return p.viewMode === "list" ? 22 : 0;
  }
  function listOf(side) { return term.chromeRef.listA.side === side ? term.chromeRef.listA : term.chromeRef.listB; }
  function gridOf(side) { return term.chromeRef.gridA.side === side ? term.chromeRef.gridA : term.chromeRef.gridB; }
  // A click in the half the keyboard is not in: land on the row, then come
  // over. Both halves are real panes, so this is the whole of what makes
  // them interchangeable rather than one of them being second class.
  // THE SAME RULE, FOR A CLICK THAT LANDS ON NOTHING.
  //
  // focusPane below is a click on a ROW in the other half: take the row, then
  // come over. Empty space had no equivalent, and the empty-space overlay is
  // one item across the whole body with no idea which half the pointer is in
  // — so clicking the background of the inactive half cleared the ACTIVE
  // pane's marks and opened the paste menu for the ACTIVE pane's directory,
  // from a click made in the other one. Nothing moved, which read as the mouse
  // being unable to choose a pane at all: only rows could, and only by being
  // rows.
  //
  // No `sel` here — clicking empty space is not choosing a row, so the cursor
  // stays where that half left it.
  function comeOverAt(bx) {
    const v = term.viewUnder(bx);
    if (v && v.pane) term.activatePane(v.pane.side);
  }
  function focusPane(pane, i) {
    if (!pane) return;
    pane.sel = i;
    term.activatePane(pane.side);
  }
  // One half's views, back to the top. Called from the wholesale branch of
  // that pane's diff, before the model is cleared.
  function rewindPane(side) {
    term.listOf(side).positionViewAtBeginning();
    term.gridOf(side).positionViewAtBeginning();
    if (side === term.paneSide) {
      term.midCol.view.positionViewAtBeginning();
    }
  }
  Process {
    id: otherProc
    // A directory that has gone since the window was last open — an unmounted
    // disk, a deleted download — falls back to home rather than leaving the
    // pane blank with nothing to say for itself. `find` exits non-zero on a
    // path that is not there, which is the whole test. Guarded against home
    // itself so a failure there cannot loop.
    onExited: (code) => {
      if (term.otherAgain) { Qt.callLater(term.refreshOther); return; }
      if (code === 0 || term.otherCwd === Paths.home()) return;
      term.pas.cwd = Paths.home();
      term.pas.sel = 0;
      term.refreshOther();
    }
    stdout: StdioCollector {
      id: otherOut
      waitForEnd: true
      onStreamFinished: {
        // The same bytes are the same rows. The passive half is re-read on
        // every event in it now (see watchOther), and handing it a fresh
        // `raw` each time rebuilt rows that had not changed.
        // The pane's own record, the one the active half's refresh keeps,
        // so it stays true across a step over and a swap.
        if (term.otherFor !== term.otherCwd) { Qt.callLater(term.refreshOther); return; }
        if (otherOut.text === term.pas.lastListing) return;
        term.pas.lastListing = otherOut.text;
        // ENRICHED HERE, where the other half's listing is parsed. It used
        // to be decorated by the otherRows binding instead — that binding is
        // the pane's own `sorted` now, shared with the active half, and a
        // listing that arrived undecorated drew rows with no glyph and no
        // ink at all.
        term.pas.raw = term.enrich(
          Terminus.parseListing(otherOut.text, term.otherCwd));
        if (term.otherSel >= term.otherRows.length)
          term.pas.sel = Math.max(0, term.otherRows.length - 1);
        // and its pictures: makeThumbs covers both halves, but only the
        // active half's listing ever asked for it
        Qt.callLater(term.makeThumbs);
      }
    }
  }
  Timer {
    id: thumbRetry
    interval: 250
    onTriggered: term.makeThumbs()
  }
  Timer {
    id: warmAim
    // Short, because arrowing along a row of directories and opening one is
    // the case that used to miss: at 260ms a directory you passed through
    // was never warmed, and it was exactly the directory you then opened.
    // The peek it costs is one capped `find`, and the gate below would
    // otherwise pay for it at the worst possible moment.
    interval: 100
    repeat: false
    onTriggered: term.warmPeek()
  }
  // Its own process and its own rows, deliberately NOT the preview's.
  // That machinery has previewFor/previewShown/settlePreview between it
  // and the screen, and a stale answer there is a wrong preview — it has
  // already cost us one bug this session. A warm that misses costs a
  // decode nobody uses.
  Process {
    id: warmProc
    stdout: StdioCollector {
      id: warmOut
      waitForEnd: true
      onStreamFinished: term.warmLanded()
    }
  }
  // `force` asks for a named directory regardless of where the cursor is
  // — the open gate below uses it, because by then the answer is needed
  // rather than merely likely.
  function warmPeek(force) {
    let p = "";
    if (force) p = String(force);
    else {
      if (!term.shown || term.viewMode !== "grid") return;
      const r = term.currentRow();
      if (!r || !r.isDir) return;
      p = r.path;
    }
    if (p === term.warmDir) return;
    term.warmDir = p;
    warmProc.running = false;
    warmProc.command = ["sh", "-c", Terminus.peekCommand(p)];
    warmProc.running = true;
  }
  // Every warm image has either finished or has nothing to finish. An
  // Error counts as settled: a thumbnail the pool has lost is not a
  // reason to sit here, it is a reason to go and show the glyph.
  function warmSettled() {
    // THE REPEATER MUST HAVE CAUGHT UP FIRST. Assigning warmRows and the
    // items existing are not the same instant, and a poll that lands in
    // between walks nothing and calls it settled — which released the
    // gate before a single image had been asked for.
    if (term.warmRepRef.count !== term.warmRows.length) return false;
    for (let i = 0; i < term.warmRepRef.count; ++i) {
      const it = term.warmRepRef.itemAt(i);
      if (!it) return false;
      if (String(it.source) === "") continue;
      if (it.status !== Image.Ready && it.status !== Image.Error) return false;
    }
    return true;
  }
  function holdTick() {
    if (term.warmShown === term.holdFor && term.warmSettled()) term.holdGo();
  }
  function holdGo() {
    term.holdPollRef.stop();
    term.holdStopRef.stop();
    if (!term.openHeld) return;
    term.openHeld = false;
    term.openCleared = term.holdFor;
    term.holdFor = "";
    term.activate();
  }
  function warmLanded() {
    const dir = term.warmDir;
    if (dir === "") return;
    const rows = term.rowsFromListing(warmOut.text, dir);
    const out = [];
    for (let i = 0; i < rows.length && out.length < term.warmCap; ++i) {
      const r = rows[i];
      if (r.isDir) continue;
      if (!Terminus.isImage(r.name) && !Terminus.isVideo(r.name)
          && !Terminus.isAudio(r.name)) continue;
      out.push(r);
    }
    // The pool first — free when the index already knows these — and then
    // the decode, which is what the Repeater below is for.
    // ── AND THE LISTING ITSELF, WHICH WAS BEING THROWN AWAY ───────
    // The peek just read this directory. Opening it then ran `find` over
    // the same directory a second time and waited 92ms for the answer —
    // measured as 72% of the whole keypress-to-drawn path, against 36ms
    // for every thumbnail on screen.
    //
    // enter() already knows how to start from remembered bytes: it draws
    // them in the same frame and lets the refresh behind it agree, which
    // it does, because the seed is exactly what the refresh returns. All
    // that was missing is that nobody told it about this read.
    //
    // rememberListing refuses anything over 64KB, and the peek only
    // truncates at 200KB — so any text it accepts is a COMPLETE listing,
    // never a cut one. The size guard is the truncation guard.
    term.rememberListing(dir, warmOut.text);
    term.primeThumbs(out);
    term.warmRows = out;
    // Only now are the rows on screen ABOUT this directory. warmDir is set
    // the moment a peek is asked for, which is too early for the gate to
    // trust — it would read the previous directory's images as this one's.
    term.warmShown = dir;
  }
  function refreshOther() {
    if (!term.dual || term.otherCwd === "") return;
    if (otherProc.running) { term.otherAgain = true; return; }
    term.otherAgain = false;
    term.otherFor = term.otherCwd;
    otherProc.command = ["sh", "-c", Terminus.listCommand(term.otherCwd)];
    otherProc.running = true;
  }
  function toggleDual() {
    if (term.picking) return;   // see loadViewPrefs: a dialog has one pane
    if (term.dual) {
      term.dual = false;
      term.fitSplit(false);
      term.viewSaveRef.restart();
      return;
    }
    // Opens where you are standing, like a new tab does and for the same
    // reason: you split the window because you want a second view of what is
    // already in front of you.
    if (term.otherCwd === "") {
      term.pas.cwd = term.cwd;
      // A first split is a second look at the same directory, read the same way.
      term.pas.sortKey = term.act.sortKey;
      term.pas.sortDesc = term.act.sortDesc;
    }
    term.fitSplit(true);
    term.dual = true;
    term.demoteColumns();
    term.refreshOther();
    term.viewSaveRef.restart();
  }
  // Whether any tab OTHER than the one on screen is split. The one on screen
  // lives in the window rather than in its record — see closeTabAt.
  function otherTabSplit() {
    for (let i = 0; i < term.tabs.length; ++i)
      if (i !== term.tab && term.tabs[i] && term.tabs[i].dual === true) return true;
    return false;
  }
  function fitSplit(on) {
    if (term.otherTabSplit()) { term.fitPending = false; return; }
    // Asked before `dual` changes, while bodyBox is still one pane wide.
    if (on) {
      if (term.splitGrew > 0) { term.fitPending = false; return; }
      term.splitWant = term.width + Math.round(term.chromeRef.bodyBox.width);
    } else if (term.splitGrew > 0) term.splitWant = term.width - term.splitGrew;
    else { term.fitPending = false; return; }
    term.fitFor = on;
    term.fitPending = true;
    fitProc.running = false;
    fitProc.running = true;
  }
  // A tab closed: if it held the last split, the room goes back with it.
  function fitAfterTabs() {
    if (term.dual || term.otherTabSplit() || term.splitGrew <= 0) return;
    term.splitWant = term.width - term.splitGrew;
    term.fitFor = false;
    term.fitPending = true;
    fitProc.running = false;
    fitProc.running = true;
  }
  Process {
    id: fitProc
    command: ["sh", "-c", "hyprctl -j activewindow; echo '@@mons'; hyprctl -j monitors"]
    stdout: StdioCollector {
      id: fitOut
      onStreamFinished: {
        if (!term.fitPending) return;
        // asked for a state we have since toggled out of — see fitFor
        if (term.fitFor !== (term.dual || term.otherTabSplit())) { term.fitPending = false; return; }
        const grow = term.fitFor;
        const parts = fitOut.text.split("@@mons");
        let win = null, mons = null;
        try { win = JSON.parse(parts[0]); mons = JSON.parse(parts[1]); } catch (e) { return; }
        // The window the key was pressed in is the focused one; anything
        // else answering here is not ours to resize.
        if (!win || win.class !== "org.quickshell" || win.title !== term.title) return;
        term.fitPending = false;
        const room = Terminus.splitRoom(win, mons, term.splitWant, 16, 560, "right");
        if (room) Terminus.splitRoomDispatches(win.address, room).forEach((d) => Hyprland.dispatch(d));
        term.splitGrew = grow && room ? room.dw : 0;
        term.viewSaveRef.restart();
      }
    }
  }
  // FOCUS THE OTHER SIDE, WHICH IS NOW ONE ASSIGNMENT. What `o`, Tab and a
  // click over there all do.
  //
  // It used to be twenty lines: the two listings changed hands, the side they
  // were drawn on flipped the other way so the screen held still, and the
  // view and the zoom of each half had to be saved, restored and written back
  // whole with the per-directory handlers muted throughout — because the
  // state was crossing the divider and everything that belonged to the HALF
  // rather than to the state had to be held back from crossing with it.
  //
  // Nothing crosses now. Each half owns its directory, its cursor, its view,
  // its zoom and its model, permanently; `paneSide` says only which of the
  // two the keyboard is in. So the whole of stepping across is moving that
  // flag — no listing changes hands, no model is rebuilt, and not one
  // delegate in either pane is destroyed.
  function stepOver() {
    if (!term.dual) return;
    term.activatePane(term.paneSide === 0 ? 1 : 0);
  }
  // Every pointer path used to call stepOver, which is a TOGGLE, and a click
  // is not one event: a row, the catcher over the passive half and the
  // empty-space overlay can each hear the same press. Two of them toggling
  // is a click that crosses over and straight back, which is the split view
  // "fighting" you — you pressed a directory's triangle in the right half and
  // the left half took the keyboard. Naming the side makes any number of
  // callers agree: the second one finds it already done.
  //
  // AND NOTHING IS WIPED ON THE WAY. Crossing used to clear the pane you left
  // — its filter and its ticks — so a selection made on one side was gone the
  // moment you looked at the other, the way it never is in Finder. Each half
  // keeps both; the ticks are only drawn in the active half (see `ticked`)
  // and come back when you do.
  function activatePane(side) {
    if (!term.dual || side === term.paneSide) return;
    // MUTED ACROSS THE FLIP, and this is not optional. `cwd` is a window onto
    // the active pane, so moving the flag changes it — and onCwdChanged
    // applies the DIRECTORY's remembered view. Without the guard, stepping
    // across overwrote the half you arrived in with whatever the half you
    // left had last recorded against that path, and the change to viewMode
    // recorded it right back: the two panes traded views, every press, for as
    // long as you kept pressing.
    term.applyDepth++;
    term.paneSide = side;
    term.applyDepth--;
    // The field shows the half you are now in — that half's own filter,
    // which it kept while you were away.
    term.chromeRef.filterField.text = term.act.query;
    // Whatever the half you have arrived in is showing, it is a grid or a
    // list: columns is a three-column layout and there is not room for two of
    // them. A stored "columns" — from a session before the split was opened —
    // would otherwise draw nothing at all.
    if (term.act.viewMode === "columns") term.act.viewMode = "list";
    term.saveTab();
    term.makeThumbs();
    // Each watcher follows a HALF, and the halves just traded roles. Same
    // directory on both sides means cwd did not change, so onCwdChanged is
    // not coming to do this.
    term.watch();
    term.watchOther();
  }
  // THE TWO DIRECTORIES CHANGE SIDES and the focus stays where it is. The
  // only thing left in this window that moves a listing across the divider,
  // and the only thing that should: `o` is a request to swap them.
  function swapSides() {
    if (!term.dual) return;
    term.exchangePanes();
  }
  // The whole second pane, in one function. Everything a pane owns goes with
  // it, because the point of the gesture is that the two halves trade places
  // entirely — not that two directories are moved between two sets of
  // settings that stay put.
  function exchangePanes() {
    if (!term.dual) return;
    // The remembered view belongs to NAVIGATION, not to a swap: arriving in a
    // directory last looked at as a grid must not flip the pane it lands in.
    term.applyDepth++;
    const a = term.paneLRef;
    const b = term.paneRRef;
    term.quietArrive = true;
    const cwd = a.cwd, sel = a.sel, raw = a.raw, vm = a.viewMode;
    const zoom = a.zoom, q = a.query, mk = a.marked, ll = a.lastListing;
    a.cwd = b.cwd; a.sel = b.sel; a.raw = b.raw; a.viewMode = b.viewMode;
    a.zoom = b.zoom; a.query = b.query; a.marked = b.marked;
    a.lastListing = b.lastListing;
    b.cwd = cwd; b.sel = sel; b.raw = raw; b.viewMode = vm;
    b.zoom = zoom; b.query = q; b.marked = mk; b.lastListing = ll;
    // The order goes with the listing it was chosen for.
    const sk = a.sortKey, sd = a.sortDesc;
    a.sortKey = b.sortKey; a.sortDesc = b.sortDesc;
    b.sortKey = sk; b.sortDesc = sd;
    term.sortKey = term.act.sortKey;
    term.sortDesc = term.act.sortDesc;
    term.chromeRef.filterField.text = term.act.query;
    term.saveTab();
    // inotify follows the cwd (onCwdChanged), so anything that changes over
    // here while you were over there still arrives on its own.
    term.makeThumbs();
    term.quietArrive = false;
    term.applyDepth--;
  }
  // F5 and F6, the two keys every dual-pane file manager has had since the
  // eighties. They are the yank buffer and a paste, with the destination
  // pointed at the other side rather than at where you are standing.
  function sendToOther(op) {
    if (!term.dual || term.otherCwd === "") {
      term.warn("no second pane");
      return;
    }
    if (term.otherCwd === term.cwd) {
      term.warn("both panes are here");
      return;
    }
    const rows = term.acting();
    if (rows.length === 0) return;
    term.setPending({ op: op, paths: rows.map((r) => r.path),
                      names: rows.map((r) => r.name) });
    term.pasteDest = term.otherCwd;
    term.pastePending();
  }
}
