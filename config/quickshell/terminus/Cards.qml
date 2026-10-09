// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// Terminus' while a card has the screen … logic, out of TerminusWindow.qml
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
  id: cards
  property var term: null

  function noteSheet(key, ink, x, w) {
    const m = Object.assign({}, term.sheetInks);
    if (ink > 0.001) m[key] = { ink: ink, x: x, w: w }; else delete m[key];
    term.sheetInks = m;
    let best = null;
    for (const k in m) if (!best || m[k].ink > best.ink) best = m[k];
    term.sheetInk = best ? best.ink : 0;
    if (best) { term.spliceX = best.x; term.spliceW = best.w; }
  }
  function latchBar() {
    term.barSend = term.sendToRef.open;
    term.barTitle = term.sendToRef.open ? "" : term.sheetTitle;
    term.barGlyph = term.sendToRef.open ? "" : term.sheetGlyph;
    term.barTitleInk = term.sheetTitleInk;
    term.barGlyphInk = term.sheetGlyphInk;
  }
  // `arm` is false when the trail moved rather than the pointer — see
  // crumbDrop.rehover.
  function crumbHover(path, arm) {
    // the same step again changes nothing — unless the pointer has now
    // moved over a step the trail put there, which arms its hold
    if (path === term.crumbDropPath && (arm !== true || crumbSpring.running)) return;
    term.crumbDropPath = path;
    const ok = arm === true && path !== "" && path !== term.cwd
      && !term.dragPaths.some((p) => path === p || path.indexOf(p + "/") === 0);
    if (ok) crumbSpring.restart(); else crumbSpring.stop();
  }
  Timer {
    id: crumbSpring
    interval: term.springMs
    onTriggered: {
      const dir = term.crumbDropPath;
      if (dir === "" || dir === term.cwd) return;
      term.goTo(dir);
      // the trail is about to be rebuilt under the pointer; the next move
      // over it says which step is there now
      term.crumbDropPath = "";
    }
  }
  function markRange(a, b) {
    const lo = Math.min(a, b), hi = Math.max(a, b);
    const next = Object.assign({}, term.marked);
    const v = term.view;
    for (let i = lo; i <= hi; ++i)
      if (v[i]) next[v[i].path] = true;
    term.act.marked = next;
  }
  function markAt(i) {
    const r = term.view[i];
    if (!r) return;
    const next = Object.assign({}, term.marked);
    if (next[r.path]) delete next[r.path];
    else next[r.path] = true;
    term.act.marked = next;
  }
  function clickRow(i, right, shift, ctrl) {
    term.saveAimed = true;
    if (shift) {
      const from = term.anchorIndex();
      term.markRange(from, i);
      term.holdAnchor = true;
      term.act.sel = i;
      term.holdAnchor = false;
    }
    else if (ctrl) {
      const cur = term.currentRow();
      const r = term.view[i];
      if (term.markedCount === 0 && cur && r && cur.path === term.clickedPath
          && cur.path !== r.path) {
        const next = Object.assign({}, term.act.marked);
        next[cur.path] = true;
        next[r.path] = true;
        term.act.marked = next;
      } else {
        term.markAt(i);
      }
      term.act.sel = i;
      term.setAnchor(i);   // sel may not have changed, so onSelChanged may not fire
    }
    else {
      if (!right) term.act.marked = {};
      term.act.sel = i;
      term.setAnchor(i);
      const r = term.view[i];
      term.clickedPath = r ? String(r.path) : "";
    }
    term.contentRef.forceActiveFocus();
  }
  function toggleVisual() {
    if (term.visualOn) { term.endVisual(); return; }
    if (term.view.length === 0) return;
    term.visualBase = Object.assign({}, term.marked);
    term.visualAt = term.sel;
    term.extendVisual();
  }
  function endVisual() { term.visualAt = -1; term.visualBase = ({}); }
  // A RUN IN A LIST, A RECTANGLE IN A GRID.
  //
  // The range between two indices is the right answer in a list, where the
  // rows ARE the order. In a grid it is a snake: anchor on the third tile,
  // move down one row, and everything from there to the far edge and back
  // round comes with you, because index 3 to index 12 is twelve consecutive
  // tiles wrapping across the rows. Nobody dragging a mouse across a grid of
  // icons means that.
  //
  // So the grid takes the two corners and marks what lies BETWEEN them — the
  // same region a rubber band would cover, in whichever direction you moved,
  // and only the tiles inside it rather than the whole rows they sit on.
  function extendVisual() {
    if (!term.visualOn) return;
    const v = term.view;
    const next = Object.assign({}, term.visualBase);

    if (term.viewMode === "grid") {
      const cols = Math.max(1, term.gridCols());
      const ar = Math.floor(term.visualAt / cols), ac = term.visualAt % cols;
      const br = Math.floor(term.sel / cols),      bc = term.sel % cols;
      const r0 = Math.min(ar, br), r1 = Math.max(ar, br);
      const c0 = Math.min(ac, bc), c1 = Math.max(ac, bc);
      for (let r = r0; r <= r1; ++r) {
        for (let c = c0; c <= c1; ++c) {
          const i = r * cols + c;
          if (v[i]) next[v[i].path] = true;
        }
      }
    } else {
      const lo = Math.min(term.visualAt, term.sel);
      const hi = Math.max(term.visualAt, term.sel);
      for (let i = lo; i <= hi; ++i) if (v[i]) next[v[i].path] = true;
    }
    term.act.marked = next;
  }
  function toggleMark() {
    const r = term.currentRow();
    if (!r) return;
    const next = Object.assign({}, term.marked);
    if (next[r.path]) delete next[r.path];
    else next[r.path] = true;
    term.act.marked = next;
  }
  // How many tiles fit across, which is what up and down have to step by.
  // Asked of the view rather than recomputed from targetCell: the cell width
  // is rounded to divide the pane exactly, so dividing the pane by the TARGET
  // gives a different number at some widths.
  function gridCols() {
    return Math.max(1, Math.floor(term.actGrid.width
                    / Math.max(1, term.actGrid.cellWidth)));
  }
  function moveSel(delta) {
    const n = term.view.length;
    if (n === 0) return;
    term.saveAimed = true;
    // WRAPS, but only off the end it is already standing on.
    //
    // Down at the bottom is the top again and up at the top is the bottom —
    // which is what a list of thirty items with the one you want at the other
    // end wants. A page or a half page from the MIDDLE still lands on the end
    // rather than jumping past it to the far side: "down sixteen" from row
    // four means row twenty or the bottom, never the top.
    let i = term.sel + delta;
    if (i < 0) i = term.sel === 0 ? n - 1 : 0;
    else if (i > n - 1) i = term.sel === n - 1 ? 0 : n - 1;
    term.act.sel = i;
    Qt.callLater(term.positionSel);
  }
}
