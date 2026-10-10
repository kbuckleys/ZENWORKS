// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// Terminus' running things … logic, out of TerminusWindow.qml
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
  id: selection
  property var term: null

  Process {
    id: actProc
    // A PROCESS THAT NEVER STARTED says so only by not running. Quickshell
    // emits exited for a process that ran, and for one execve refused
    // (sh missing, E2BIG, ENOMEM) it emits nothing but runningChanged — so
    // the queue waited on an exit that was never coming and every action
    // after it sat there. exited always lands before running drops, so
    // "stopped without having exited" is exactly the failed start.
    property bool sawExit: false
    onRunningChanged: {
      if (actProc.running || actProc.sawExit) return;
      term.warn("could not start that");
      term.drain();
    }
    stderr: StdioCollector {
      id: actErr
      waitForEnd: true
      onStreamFinished: {
        const e = String(actErr.text || "").trim();
        if (e !== "") term.warn(e.split("\n")[0]);
      }
    }
    onExited: (code) => {
      actProc.sawExit = true;
      if (code === 0 && term.status !== "") term.status = "";
      // Whatever was just made inside a branch is on disk now — see
      // root.madeIn. Cleared either way, so a failed create does not
      // leave the next unrelated command re-reading a stale branch.
      if (term.madeIn !== "") {
        const dir = term.madeIn;
        term.madeIn = "";
        if (code === 0 && dir !== term.cwd) term.rereadBranches([dir]);
      }
      // ── AND EVERY OPEN BRANCH, NOT ONLY CWD ─────────────────────────
      // refresh() below re-reads the directory itself. A delete, move or
      // rename INSIDE an expanded directory was left to the watcher to notice,
      // so any time the watcher was not covering that directory — see watchAim
      // for how that happened — what terminus had just done itself never
      // showed. A job is ours; we know it changed something, so we look.
      // Unchanged branches come back byte-identical and cost nothing.
      term.rereadBranches(term.openBranches());
      // emptying or restoring changes what the trash holds
      if (term.inTrash && !term.trashSizeProcRef.running) term.trashSizeProcRef.running = true;
      // A PEEK IS A PHOTOGRAPH and something has just changed the scene. The
      // cache is keyed by path with no notion of when it was taken, so a
      // directory previewed before a paste went on showing what it held before
      // it — for as long as it stayed in the cache. Dropped wholesale rather
      // than picked over: it holds two dozen entries and exists to make
      // walking back up a column instant, not to survive a write.
      term.previewCache = ({});
      term.previewOrder = [];
      if (term.viewMode === "columns") term.refreshPreview();
      term.refresh();
      // refresh() declines on a results page; a collection has its own —
      // see reCollect.
      if (term.searchMode !== "") term.collectionsRef.collSettle.restart();
      term.drain();
    }
  }
  function run(cmd) {
    term.spendMarks();
    term.queue.push(cmd);
    term.drain();
  }
  function drain() {
    if (term.queue.length === 0 || actProc.running) return;
    // a plain script, or a { script, args } from terminus.js that carries its
    // paths as arguments — see shArgv there
    const next = term.queue.shift();
    actProc.command = typeof next === "string" ? ["sh", "-c", next]
      : Terminus.shArgv(next);
    actProc.sawExit = false;
    actProc.running = true;
  }
  function setAnchor(i) {
    const r = term.act.view[i];
    term.anchorPath = r ? String(r.path) : "";
  }
  function anchorIndex() {
    const v = term.act.view;
    if (term.anchorPath !== "")
      for (let i = 0; i < v.length; ++i)
        if (v[i].path === term.anchorPath) return i;
    return term.act.sel;
  }
  function mouseKey(button) { return term.mouseGlyph + " " + button; }
  function colWidths(inner, f) {
    const kind = f.kind > 0 ? term.colKindW : 0;
    const time = f.time > 0 ? term.colTimeW : 0;
    const size = inner * f.size;
    const rest = Math.max(0, inner - kind - time - size);
    const share = f.name + f.where;
    const name = share > 0 ? rest * (f.name / share) : rest;
    return { name: name, where: rest - name,
             kind: kind, size: size, time: time };
  }
  // The view a wheel event belongs to. Only the split case needs thinking
  // about: with one pane there is one view, and with two the pointer decides,
  // because scrolling the pane you are NOT pointing at is never what was
  // meant. Coordinates are the body's, as everywhere else here.
  function wheelTarget(bx, by) {
    const onActive = !term.dual
      || (bx >= term.activePaneX && bx < term.activePaneX + term.activePaneW);
    if (!onActive)
      return term.otherViewMode === "grid" ? term.gridOf(term.pas.side) : term.listOf(term.pas.side);
    // Miller's preview is a pane of its own, and a long file shown in it is a
    // thing you scroll. The wheel used to reach the listing no matter which
    // column the pointer was over, so spinning it on a forty-line preview
    // moved the middle column instead and the preview sat there unread.
    //
    // Only when there is somewhere to scroll TO: a preview that fits would
    // otherwise swallow the wheel and leave the listing beside it stuck.
    // WHICHEVER PREVIEW IS ON SCREEN, not only the text one. The pane shows a
    // file's contents OR an archive's tree, and the wheel was offered to the
    // first and never the second — so spinning it over a long archive listing
    // scrolled the middle column instead and the tree sat there unread.
    if (term.viewMode === "columns"
        && bx - term.activePaneX >= term.chromeRef.previewPane.x) {
      if (term.chromeRef.textScroll.visible
          && term.chromeRef.textScroll.contentHeight > term.chromeRef.textScroll.height)
        return term.chromeRef.textScroll;
      if (term.chromeRef.archiveList.visible
          && term.chromeRef.archiveList.contentHeight > term.chromeRef.archiveList.height)
        return term.chromeRef.archiveList;
    }
    return term.viewMode === "grid" ? term.actGrid
         : (term.viewMode === "columns" ? term.midCol.view : term.actList);
  }
  // Which row is under a point in the body, or -1 for none.
  //
  // Asked of the VIEW, not of hover state. `hoverRow` is a single flag written
  // by every delegate's HoverHandler, so two of them crossing over write it in
  // an order nobody controls, and anything above the views that consumes hover
  // can leave it false while the pointer is plainly on a row. Routing clicks
  // through it made them land on nothing — items would not open. indexAt is
  // the view's own hit test and cannot disagree with what is drawn.
  //
  // Coordinates are the body's; each view converts to its own content space.
  function rowUnder(bx, by) {
    // ASKED OF THE VIEW UNDER THE POINTER — found by its own geometry, not
    // worked out from which pane is active or what mode that pane is in.
    //
    // Two goes at this were wrong in the same way the actList note above
    // describes. It used to return 0 ("over something") for the whole passive
    // half, so the empty-space overlay switched off and the click fell through
    // to the row underneath — right over that half's ROWS, wrong over its
    // empty space, where there is no row to fall through to and the click
    // simply vanished. Answering per side fixed that and broke more: it picked
    // the other half's view by root.viewMode, which is the ACTIVE pane's mode,
    // so with one half in list and the other in grid it questioned a view that
    // is not drawn, heard -1 everywhere, and the overlay ate every click in
    // that half instead.
    //
    // The views know where they are and whether they are on. Asking them is
    // the only form of this that cannot go stale.
    const v = term.viewUnder(bx);
    if (v) return v.indexAt(bx - v.x + v.contentX, by - v.y + v.contentY);

    // Not over a list or a grid. The only other thing holding rows is miller,
    // and miller only ever opens on the active half.
    if (term.viewMode !== "columns") return 0;
    if (term.dual && (bx < term.activePaneX
                      || bx > term.activePaneX + term.activePaneW)) return 0;
    const x = bx - term.activePaneX;
    const y = by - term.chromeRef.bodyBox.topH;
    if (x < term.midCol.x || x > term.midCol.x + term.midCol.width) return 0;
    return term.midCol.view.indexAt(x - term.midCol.x + term.midCol.view.contentX,
                           y + term.midCol.view.contentY);
  }
  // Whichever of the four views the pointer is inside, or null.
  //
  // `on` is the same gate the views draw themselves by — one pane's list and
  // grid are never both on — so this needs to know nothing about sides, modes
  // or which half has the keyboard. Written as a function because it reads
  // geometry that moves; every caller is an event handler, not a binding.
  function viewUnder(bx) {
    const vs = [term.chromeRef.listA, term.chromeRef.listB, term.chromeRef.gridA, term.chromeRef.gridB];
    for (let i = 0; i < vs.length; i++) {
      const v = vs[i];
      if (v.on && bx >= v.x && bx < v.x + v.width) return v;
    }
    return null;
  }
}
