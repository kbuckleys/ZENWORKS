// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// Terminus' tabs … logic, out of TerminusWindow.qml
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
  id: tabs
  property var term: null

  // `tabs` only learns the current tab's cwd when you switch away from it, so
  // the live one is folded in here rather than trusting the stored copy.
  // Everything a tab is, in one object.
  //
  // A tab used to be a directory and a cursor, which was the whole of a pane's
  // state at the time. It is not any more: the second pane, which side the
  // keyboard is on and what each side is looking at all belong to the tab as
  // well, because a tab is meant to be a separate window — split in one and a
  // single pane in the next, neither disturbing the other.
  function tabState() {
    return {
      cwd: term.cwd,
      sel: term.sel,
      // A tab is a place you were, which means it is also the places you were
      // before it. Without this, stepping between tabs would hand one tab's
      // trail to the next and `H` would walk out of a directory this tab has
      // never been in.
      trail: term.act.trail,
      trailAt: term.act.trailAt,
      trailSel: term.act.trailSel,
      crumbDeep: term.act.crumbDeep,
      // The listing itself travels with the tab. Without it every switch threw
      // the model away and ran `find` again, so a tab emptied and refilled for
      // a keystroke that changed nothing about what was in it — the flicker,
      // and the same one the pane exchange had.
      rows: term.rows,
      // WHERE IT WAS SCROLLED TO, which is not the same as which row the
      // cursor was on. A tab remembered `sel` and nothing else, and the view
      // used to keep its offset across the switch by accident — the origin
      // drifted instead of resetting, which is exactly the bug the rewind in
      // syncView fixes. With the rewind honest about resetting, the offset has
      // to be carried deliberately or every switch lands you at the top.
      scroll: term.keepScroll(),
      // and the bytes they were parsed from, so the refresh that follows a
      // switch can recognise an unchanged directory and leave the model alone.
      // Restoring the rows without this only moved the flicker later: the
      // guard compares against the last listing THIS side read, which would
      // have been the other tab's, so every switch counted as a change and
      // rebuilt every delegate anyway.
      listing: term.lastListing,
      dual: term.dual,
      otherCwd: term.otherCwd,
      otherSel: term.otherSel,
      otherRaw: term.otherRaw,
      paneSide: term.paneSide,
      // What each HALF was showing, read off the halves themselves. It used
      // to be two arrays kept in step by hand at every exchange.
      paneViews: [term.paneLRef.viewMode, term.paneRRef.viewMode],
      paneZooms: [term.paneLRef.zoom, term.paneRRef.zoom],
      // AND THE TEXT ZOOM, which is the window's one number rather than a
      // pane's. It was the only part of how a tab is READ that did not
      // travel with it: the pane zooms did, the views did, and this one was
      // left to whatever the last directory happened to set — so a tab you
      // stepped back into wore the other tab's size until you navigated.
      zoom: term.zoom,
      // AND THE ORDER IT IS IN, for exactly the same reason. A tab showing
      // a downloads directory newest-first and another showing a source tree
      // by name are two different readings of two different places, and
      // they were sharing one answer — whichever you had touched last.
      sort: term.sortKey,
      desc: term.sortDesc,
      // And each half's, now that the halves keep their own.
      paneSorts: [[term.paneLRef.sortKey, term.paneLRef.sortDesc], [term.paneRRef.sortKey, term.paneRRef.sortDesc]],
      otherView: term.pas.viewMode,
      view: term.viewMode
    };
  }
  // Put a saved tab back on screen. `otherRaw` travels with it so stepping
  // between tabs does not re-list a directory that was already listed —
  // refreshOther catches anything that changed while it was away.
  function loadTab(t) {
    // ── NOTHING IN HERE IS A PREFERENCE ──────────────────────────────────
    // Loading a tab is terminus rearranging itself, which is exactly what
    // applyDepth exists to say — and it was only being said around the one
    // line that sets the view. The lines above it were not covered, and they
    // are the ones that did the damage: paneViews puts the OLD tab's view on
    // the pane, and the cwd is changed a moment later, so for that moment the
    // window is standing in the new directory wearing the old directory's
    // view. rememberView is unguarded there, and wrote it down.
    //
    // Every new tab therefore recorded its own destination as whatever you
    // happened to be looking at, one step before correcting the view on
    // screen — under a guard, so the correction was never recorded. Opening a
    // tab at home from the grid set home to grid and left it that way, which
    // is the inheritance that survived fixing newTab: the tab was asking the
    // right question and being handed an answer it had just spoiled itself.
    //
    // Raised for the whole function, which is also what makes the comment
    // below true: the tab's own view wins, so the destination's own record
    // must not be applied on the way in either. No early returns, so the
    // release at the end always runs.
    term.applyDepth++;
    term.quietArrive = true;
    if (term.renaming) term.endRename(false);
    // Neither half keeps the last tab's way down: each pane's cwd handler
    // only lets go of it when you step off the line, and a tab at ~ never does.
    term.paneLRef.crumbDeep = "";
    term.paneRRef.crumbDeep = "";
    term.dual = t.dual === true;
    term.pas.cwd = typeof t.otherCwd === "string" ? t.otherCwd : "";
    term.pas.sel = t.otherSel || 0;
    term.pas.raw = t.otherRaw || [];
    term.pas.lastListing = null;
    term.paneSide = t.paneSide === 1 ? 1 : 0;
    if (t.paneViews && t.paneViews.length === 2) {
      term.paneLRef.viewMode = t.paneViews[0];
      term.paneRRef.viewMode = t.paneViews[1];
    }
    if (t.paneZooms && t.paneZooms.length === 2) {
      if (t.paneZooms[0] > 0) term.paneLRef.zoom = t.paneZooms[0];
      if (t.paneZooms[1] > 0) term.paneRRef.zoom = t.paneZooms[1];
    }
    // Inside applyDepth, so it lands rather than eases — arriving in a tab
    // is arriving, not resizing. Same guard the pane zooms above rely on.
    if (typeof t.zoom === "number" && t.zoom > 0) term.zoom = term.zoomClamp(t.zoom);
    // Older tab records predate these two, and a missing answer must not be
    // read as "name ascending" — that would re-sort every tab open when the
    // window was last saved. The same care applyDirView takes.
    if (t.paneSorts && t.paneSorts.length === 2) {
      [term.paneLRef, term.paneRRef].forEach((p, i) => {
        const ps = t.paneSorts[i] || [];
        if (typeof ps[0] === "string" && ps[0] !== "") p.sortKey = ps[0];
        if (typeof ps[1] === "boolean") p.sortDesc = ps[1];
      });
      term.sortKey = term.act.sortKey;
      term.sortDesc = term.act.sortDesc;
    } else {
      if (typeof t.sort === "string" && t.sort !== "") term.sortKey = t.sort;
      if (typeof t.desc === "boolean") term.sortDesc = t.desc;
    }
    term.demoteColumns();
    term.act.trail = (t.trail && t.trail.length !== undefined) ? t.trail : [];
    term.act.trailAt = (typeof t.trailAt === "number") ? t.trailAt : -1;
    term.act.trailSel = t.trailSel ? t.trailSel : ({});
    // before the cwd, so its handler measures against this tab's trail
    term.act.crumbDeep = typeof t.crumbDeep === "string" ? t.crumbDeep : "";
    term.act.cwd = t.cwd;
    term.act.query = "";
    term.chromeRef.filterField.text = "";
    term.act.marked = {};
    term.act.sel = t.sel || 0;
    // Handed back rather than re-read. `lastListing` is cleared with it so the
    // byte-identical guard cannot mistake the next real refresh for a no-op.
    if (t.rows && t.rows.length > 0) {
      term.act.raw = t.rows;
      term.act.lastListing = (t.listing === undefined) ? null : t.listing;
    } else {
      term.act.lastListing = null;
    }
    // The tab's own view, not the destination directory's: arriving in a tab
    // is arriving back where you were, and a tab that rearranged itself on the
    // way in would not be the window you left.
    if (term.viewRing.indexOf(t.view) >= 0) {
      term.applyDepth++;
      term.act.viewMode = t.view;
      term.applyDepth--;
    }
    // AFTER the model has been rebuilt, which is why it is deferred: handing
    // back the rows above runs syncView, and syncView rewinds the views to the
    // top on a wholesale change so their origin cannot drift. That rewind is
    // what keeps the listing from arriving with a band of nothing above it —
    // and it is also what would leave you at the top of every tab you step
    // back into. So the rewind puts the ORIGIN back and this puts YOU back,
    // in that order.
    if (t.scroll) Qt.callLater(term.restoreScroll, t.scroll);
    // The directory is still re-read, but the rows it had are already on
    // screen while that happens, so nothing blinks.
    term.refresh(true);
    term.refreshOther();
    term.quietArrive = false;
    term.applyDepth--;
  }
  function tabList() {
    const out = [];
    for (let i = 0; i < term.tabs.length; ++i)
      out.push(i === term.tab ? term.tabState() : term.tabs[i]);
    return out;
  }
  // WHAT A TAB IS WORTH KEEPING, which is not everything a tab is.
  //
  // A tab carries its listings so switching between them costs no process and
  // no rebuild — and those listings have no business in a preferences file.
  // They are a cache of what is on the disk right now, they are megabytes on a
  // deep directory, and they would be rewritten on every debounced save. What
  // survives a restart is where the tab was pointing and how it was set up;
  // the rows come back from the disk, which is where they came from.
  function tabsForDisk() {
    return term.tabList().map((t) => ({
      cwd: t.cwd, sel: t.sel, view: t.view,
      dual: t.dual, otherCwd: t.otherCwd, otherSel: t.otherSel,
      paneSide: t.paneSide, paneViews: t.paneViews, paneZooms: t.paneZooms,
      // everything tabState keeps about how a tab is READ, which loadTab
      // puts back — left out here, a restored session opened every tab at
      // one zoom and one sort order
      zoom: t.zoom, sort: t.sort, desc: t.desc, otherView: t.otherView
    }));
  }
  function saveTab() {
    const next = term.tabs.slice();
    next[term.tab] = term.tabState();
    term.tabs = next;
  }
  // The record moves; the CURSOR follows the record rather than the position.
  // Dragging the tab you are standing in must leave you standing in it, and
  // dragging one past you must not quietly move you to a different directory —
  // which is what happens if `tab` is left pointing at an index whose occupant
  // has changed underneath it.
  //
  // saveTab first, because the live tab's state (its cwd, its selection, its
  // split) lives in the window until something writes it back, and moving the
  // records around before that would file it under the wrong one.
  function moveTab(from, to) {
    if (from < 0 || to < 0 || from === to) return;
    if (from >= term.tabs.length || to >= term.tabs.length) return;
    term.saveTab();
    const next = term.tabs.slice();
    const rec = next.splice(from, 1)[0];
    next.splice(to, 0, rec);
    // the three cases: you moved the tab you are on, you moved one from
    // before you to after you, or the other way round
    let cur = term.tab;
    if (cur === from) cur = to;
    else if (from < cur && cur <= to) cur -= 1;
    else if (to <= cur && cur < from) cur += 1;
    term.tabs = next;
    // set AFTER the list, and deliberately not through switchTab: nothing has
    // been entered or left, so there is nothing to load — reloading here would
    // throw away the listing and rebuild the identical one.
    term.tab = cur;
  }
  function switchTab(i) {
    if (i === term.tab || i < 0 || i >= term.tabs.length) return;
    term.saveTab();
    term.tab = i;
    term.loadTab(term.tabs[i]);
  }
  // A NEW TAB IS A NEW WINDOW: one pane, at home. It used to inherit the
  // current tab's directory and its split, which made "give me a clean sheet"
  // impossible — you got another copy of where you already were.
  // `t` opens at home; middle click and the menu entry open at a directory.
  // Both are the same tab, so they are the same function with an argument
  // rather than two that drift apart.
  function newTab(path) {
    term.saveTab();
    const t = term.tabState();
    t.cwd = (path && path !== "") ? path : Paths.home();
    t.sel = 0;
    // A NEW TAB HAS NOT BEEN ANYWHERE. The state was copied off the tab you
    // are standing in, and its trail came with it — so `H` in a brand new tab
    // would have walked back through somewhere else's history.
    t.trail = [];
    t.trailAt = -1;
    t.trailSel = ({});
    t.crumbDeep = "";
    // ── A NEW TAB DOES NOT INHERIT THE VIEW ──────────────────────────────
    // The state is copied off the tab you are standing in, and the view came
    // with it: opening a tab from a pictures directory in the grid put home in
    // the grid too, and kept it there. Nothing was wrong with home's own
    // record — loadTab raises applyDepth, which is what stops applyDirView
    // from asking, so the answer was never read rather than being wrong.
    //
    // Asked here instead, where the destination is already known. How a
    // directory wants to be read is a fact about that directory, so a tab opening
    // onto it starts the way that directory was left, and a directory with no
    // record starts in the plainest view the current layout has rather than
    // in whatever the last one happened to be showing.
    //
    // Only while the memory is on: switched off there is no other source of
    // truth, and inheriting is then the only thing left to do.
    if (term.perDirView) {
      const v = term.dirViews[t.cwd];
      t.view = (v && term.viewRing.indexOf(v.view) >= 0)
        ? v.view : term.viewRing[0];
      // ── AND AT THE SIZE IT WAS LEFT AT ─────────────────────────────────
      // The view was asked for here and nothing else was, so a new tab
      // arrived wearing the zoom of the tab it was opened FROM — and since
      // loadTab holds applyDepth up, applyDirView never got to correct it.
      // It corrected itself the next time you navigated, which is exactly
      // the "wrong until I open another dir and come back" this had.
      //
      // Only when the destination has an answer: a directory with no record
      // keeps the zoom you were already reading at, which is what stepping
      // into one does. applyDirView returns early on a missing record for
      // the same reason.
      if (v) {
        const z = Number(v.zoom);
        if (!isNaN(z) && z > 0) t.zoom = term.zoomClamp(z);
        const tz = Number(v.thumbZoom);
        // paneZooms[0] — a new tab is single-pane, so paneL is the one
        // you land in. See root.act.
        if (!isNaN(tz) && tz > 0 && t.paneZooms && t.paneZooms.length === 2)
          t.paneZooms = [term.zoomClamp(tz), t.paneZooms[1]];
        // And the order, now that a tab carries one. Same rule as the
        // zoom: only when the destination has an answer, because a directory
        // with no record keeps the order you were already reading in.
        if (typeof v.sort === "string" && v.sort !== "") t.sort = v.sort;
        if (typeof v.desc === "boolean") t.desc = v.desc;
      }
    }
    // and at the top of it. The state was copied off the tab you are standing
    // in, so without this a new tab opens scrolled to wherever that one was.
    t.scroll = null;
    t.dual = false;
    t.otherCwd = "";
    t.otherSel = 0;
    t.otherRaw = [];
    t.paneSide = 0;
    const next = term.tabs.slice();
    next.push(t);
    term.tabs = next;
    term.tab = next.length - 1;
    term.loadTab(t);
  }
  // A directory in a new tab, leaving this one exactly where it was — which
  // is the whole point of the gesture, so a file (which has no listing to
  // show) is quietly ignored rather than opening a tab onto nothing.
  function openInNewTab(path) {
    if (!path || path === "") return;
    term.newTab(path);
  }
  // A tag page or a collection in a tab of its own: the tab opens where you
  // are standing — which is where Escape will take it back to — and the
  // page is opened in it a beat later, once the tab has finished loading.
  function openRealmInNewTab(open) {
    term.newTab(term.cwd);
    Qt.callLater(open);
  }
  // Close a tab BY INDEX, which is NOT "step into it and then close the one
  // you are in". Middle click did it that second way — switchTab followed by
  // closeTab — and it was wrong twice over. It paid for a full load of a tab
  // that was about to be thrown away; and switchTab rewrites `tabs`, which is
  // the strip Repeater's model, so replacing it destroyed the delegate whose
  // click handler was still running. Everything after that line was
  // unreachable — it threw "root is not defined" rather than running — so the
  // close simply never happened and the gesture read as "select".
  function closeTabAt(i) {
    if (term.tabs.length < 2) return;   // the last tab is just the window
    if (i < 0 || i >= term.tabs.length) return;
    // the strip shrinks this one out and closes the rest up over it
    term.chromeRef.tabStrip.noteClose(i);
    // The tab you are STANDING IN lives in the window rather than in the
    // array, so its record is written back before anything is removed.
    // Without this, closing a background tab rolled the current one back to
    // whatever it looked like the last time you left it.
    const next = term.tabs.slice();
    next[term.tab] = term.tabState();
    next.splice(i, 1);
    if (i === term.tab) {
      // The one you are in: land on its neighbour, which is what `w` means.
      const land = Math.min(i, next.length - 1);
      term.tabs = next;
      term.tab = -1;          // force the load even when the index is the same
      term.tab = land;
      term.loadTab(next[land]);
      term.fitAfterTabs();
      return;
    }
    // ANY OTHER TAB IS ONLY A RECORD. Drop it and stay exactly where you are:
    // nothing about the window changes except which index the current tab
    // sits at, so there is no directory to re-read and nothing to load.
    if (i < term.tab) term.tab = term.tab - 1;
    term.tabs = next;
    term.fitAfterTabs();
  }
  function closeTab() { term.closeTabAt(term.tab); }
}
