// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// Terminus' which way it is laid out … logic, out of TerminusWindow.qml
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
  id: opening
  property var term: null
  readonly property alias pickerSave: pickerSave
  readonly property alias viewSave: viewSave

  // Whatever was on columns when the second pane opened lands on list: a
  // three-column layout in half a window is six columns of listing at a
  // quarter width each. Guarded like every other view written by terminus
  // rather than by you, so it is not recorded as the directory's preference.
  function demoteColumns() {
    if (!term.dual) return;
    term.applyDepth++;
    if (term.paneLRef.viewMode === "columns") term.paneLRef.viewMode = "list";
    if (term.paneRRef.viewMode === "columns") term.paneRRef.viewMode = "list";
    term.applyDepth--;
  }
  function cycleView() {
    const i = term.viewRing.indexOf(term.viewMode);
    term.act.viewMode = term.viewRing[(i + 1) % term.viewRing.length];
    Qt.callLater(term.positionSel);
  }
  // Straight to a named view, for the settings panel's three buttons. `v`
  // cycles, and cycling is the wrong gesture when the thing you want is
  // written on screen in front of you. A view that is not in the ring is
  // REFUSED rather than set and quietly undone — while the window is split,
  // columns is not one of the three, and demoteColumns says why.
  function setView(v) {
    if (term.viewRing.indexOf(v) < 0) return;
    term.act.viewMode = v;
    Qt.callLater(term.positionSel);
  }
  // The view you were last in, not the one the file happens to declare above.
  // Columns is the right DEFAULT — it is what you want while navigating — but
  // it is a poor thing to be dropped back into every single time when you live
  // in thumbnails, and re-pressing `v` twice on every launch is not a setting.
  //
  // The view PREFERENCES travel together because they are one answer to "how
  // do I like looking at files": which layout, how big, sorted how, and
  // whether the dotfiles are in. Where you were is deliberately not in here —
  // a file manager that reopens in last week's directory is a surprise, not a
  // convenience.
  FileView {
    id: viewFile
    path: Quickshell.statePath("terminus-view.json")
    blockLoading: true
    printErrors: false
  }
  Timer {
    id: pickerSave
    interval: 400
    onTriggered: term.savePickerView()
  }
  // MERGED, never rebuilt. The writer below composes the whole file out of
  // this window's own properties, which is safe for a window that owns all
  // of them and ruinous for a dialog that owns exactly one — it would
  // write a picker's idea of every setting over yours. So this one reads
  // what is there, changes its single key, and puts it back.
  function savePickerView() {
    if (!term.isPicker) return;
    viewFile.reload();
    viewFile.waitForJob();
    let s = null;
    try { s = JSON.parse(String(viewFile.text() || "{}")); } catch (e) { s = null; }
    const out = (s && typeof s === "object" && !Array.isArray(s)) ? s : ({});
    out.pickerView = term.act.viewMode;
    term.pickerView = out.pickerView;
    out.pickerSidebar = term.sidebar;
    out.pickerSidebarWidth = term.sidebarWidth;
    out.pickerSideGrew = term.sideGrew;
    if (term.pickerW > 0 && term.pickerH > 0) {
      out.pickerW = term.pickerW;
      out.pickerH = term.pickerH;
    }
    viewFile.setText(JSON.stringify(out));
  }
  // Debounced, because zoom arrives as a burst of ctrl-+ and writing the file
  // on every step would be a dozen writes for one gesture.
  Timer {
    id: viewSave
    interval: 400
    onTriggered: {
      // A PICKER is not a preference. pick() forces columns so the dialog is
      // always laid out the way a dialog should be, and letting that overwrite
      // the view you actually chose would mean every save dialog reset it.
      if (term.picking || term.isPicker) return;
      // The OPEN TABS travel with the view preferences, because they are the
      // same question: how was this window set up when I left it. Only window 0
      // restores them — a spare window you opened with N is a scratch view, and
      // a picker is not a window you own at all.
      //
      // ── BUT A SCRATCH WINDOW MUST NOT ERASE THE SESSION ──────────────
      // `undefined` here was not "leave it alone", it was "delete it":
      // JSON.stringify omits an undefined value entirely, and every window
      // writes this one shared file. So opening a second window — from the
      // menu, from Icarus, from `Terminus spawn` — rewrote the file without
      // a `tabs` key and window 0's directories were gone. That is the whole
      // of "terminus does not remember where I was": it remembered fine
      // until the moment a second window saved anything at all.
      //
      // Re-read rather than remembered, through the same reload/waitForJob
      // funnel editBookmarks uses and for the same reason — window 0 has
      // very likely written since this window loaded, and carrying a copy
      // from startup would put its OLD directories back.
      let keptTabs = undefined;
      let keptTab = undefined;
      // ── AND A PICKER'S VIEW IS NOT THIS WINDOW'S TO STATE EITHER ────
      // Only a dialog ever writes it, so this window's copy is from
      // whenever it loaded — and writing that back put `columns` over a
      // picker's `list` the moment any ordinary window saved anything at
      // all. Exactly the shape of the `tabs` bug above, which is why the
      // re-read now covers both and happens for window 0 too: window 0
      // owns its tabs, but it does not own this.
      let keptPickerView = term.pickerView;
      viewFile.reload();
      viewFile.waitForJob();
      let cur = null;
      try { cur = JSON.parse(String(viewFile.text() || "{}")); } catch (e) { cur = null; }
      if (cur && typeof cur.pickerView === "string")
        keptPickerView = cur.pickerView;
      term.pickerView = keptPickerView;
      // The dialog's size is the dialog's, for the same reason.
      const keptPickerW = cur && typeof cur.pickerW === "number" ? cur.pickerW : undefined;
      const keptPickerH = cur && typeof cur.pickerH === "number" ? cur.pickerH : undefined;
      // and so is its sidebar
      const keptPickerSide = cur && typeof cur.pickerSidebar === "boolean" ? cur.pickerSidebar : undefined;
      const keptPickerSideW = cur && typeof cur.pickerSidebarWidth === "number" ? cur.pickerSidebarWidth : undefined;
      const keptPickerSideGrew = cur && typeof cur.pickerSideGrew === "number" ? cur.pickerSideGrew : undefined;
      // ── AND NEITHER MAY IT WRITE WHAT WAS OPEN ─────────────────────
      // The same rule as the tabs, and the same bug: every window wrote
      // ITS OWN open branches, second pane and pane side over window 0's.
      // A spare window saving anything at all put back the tree it had
      // when it was made — which is "it always forgets the last directory I
      // expanded": you expanded it in window 0, and a spare's save a moment
      // later wrote the older tree over it. Only window 0 speaks for these;
      // any other window carries forward what is on disk.
      let keptOpen = [term.paneLRef.dirOpenList(), term.paneRRef.dirOpenList()];
      let keptDual = term.dual, keptOther = term.otherCwd, keptSide = term.paneSide;
      if (term.winId === 0) {
        keptTabs = term.tabsForDisk();
        keptTab = term.tab;
      } else if (cur) {
        keptTabs = cur.tabs;
        keptTab = cur.tab;
        keptOpen = cur.paneOpen;
        keptDual = cur.dual;
        keptOther = cur.otherCwd;
        keptSide = cur.paneSide;
      }
      viewFile.setText(JSON.stringify({
        tabs: keptTabs,
        tab: keptTab,
        view: term.viewMode,
        pickerView: keptPickerView,
        zoom: term.zoom,
        sidebar: term.sidebar,
        sidebarWidth: term.sidebarWidth,
        thumbsOn: term.thumbsOn,
        dirsFirst: term.dirsFirst,
        naturalSort: term.naturalSort,
        alwaysTabs: term.alwaysTabs,
        colHeadsOn: term.colHeadsOn,
        confirmTrash: term.confirmTrash,
        cursorSlide: term.cursorSlide,
        termCmd: term.termCmd,
        previewOn: term.previewOn,
        dirViewCap: term.dirViewCap,
        thumbZoom: term.thumbZoom,
        sortKey: term.sortKey,
        sortDesc: term.sortDesc,
        usage: term.usage,
        git: term.git,
        showHidden: term.showHidden,
        winW: term.winW,
        winH: term.winH,
        splitGrew: term.splitGrew,
        sideGrew: term.sideGrew,
        pickerSidebar: keptPickerSide,
        pickerSidebarWidth: keptPickerSideW,
        pickerSideGrew: keptPickerSideGrew,
        pickerW: keptPickerW,
        pickerH: keptPickerH,
        recentsView: term.recentsView,
        recentsShown: term.recentsShown,
        grouped: term.grouped,
        perDirView: term.perDirView,
        lastSaveDir: term.mgr ? term.mgr.lastSaveDir : "",
        sessionReplay: term.sessionReplay,
        dual: keptDual,
        otherCwd: keptOther,
        paneSide: keptSide,
        paneViews: [term.paneLRef.viewMode, term.paneRRef.viewMode],
        // Which branches were open, per side — see pane.openList. A tree
        // you built to look at something is part of "where I was", so it
        // travels with the tabs rather than with the look of the window,
        // and it is restored only when session replay is on.
        paneOpen: keptOpen,
        paneZooms: [term.paneLRef.zoom, term.paneRRef.zoom],
        paneFrac: term.paneFrac,
        dirViews: term.dirViews
      }) + "\n");
    }
  }
  function loadViewPrefs() {
    const raw = String(viewFile.text() || "").trim();
    if (raw === "") return;
    let s = null;
    // A half-written or hand-edited file must not take the window down with
    // it: bad preferences are worth less than a working file manager.
    try { s = JSON.parse(raw); } catch (e) { return; }
    if (!s) return;
    if (term.viewRing.indexOf(s.view) >= 0) term.act.viewMode = s.view;
    if (term.viewRing.indexOf(s.pickerView) >= 0) term.pickerView = s.pickerView;
    const z = Number(s.zoom);
    if (!isNaN(z) && z > 0) term.zoom = term.zoomClamp(z);
    const tz = Number(s.thumbZoom);
    if (!isNaN(tz) && tz > 0) term.act.zoom = term.zoomClamp(tz);
    if (typeof s.sidebar === "boolean") term.sidebar = s.sidebar;
    const sw = Number(s.sidebarWidth);
    if (!isNaN(sw) && sw > 0)
      term.sidebarWidth = Math.max(term.sidebarMin, Math.min(term.sidebarMax, sw));
    term.usage = s.usage === true;
    // The flag alone, with no scan: loadViewPrefs runs before the first
    // refresh (see Component.onCompleted) and refresh is what asks git. Calling
    // toggleGit here would scan a directory the window has not listed yet.
    term.git = s.git === true;
    // "usage" is the mode's own sort key and means nothing without the mode.
    // Restoring one without the other would leave the window in an order with
    // no bars and no explanation for it.
    if (typeof s.sortKey === "string" && s.sortKey !== ""
        && (s.sortKey !== "usage" || term.usage))
      term.sortKey = s.sortKey;
    if (typeof s.sortDesc === "boolean") term.sortDesc = s.sortDesc;
    if (typeof s.showHidden === "boolean") term.showHidden = s.showHidden;
    if (typeof s.grouped === "boolean") term.grouped = s.grouped;
    if (typeof s.recentsView === "string" && s.recentsView !== ""
        && term.viewRing.indexOf(s.recentsView) >= 0)
      term.recentsView = s.recentsView;
    if (typeof s.recentsShown === "boolean") term.recentsShown = s.recentsShown;
    if (typeof s.perDirView === "boolean") term.perDirView = s.perDirView;
    if (typeof s.thumbsOn === "boolean") term.thumbsOn = s.thumbsOn;
    if (typeof s.dirsFirst === "boolean") term.dirsFirst = s.dirsFirst;
    if (typeof s.naturalSort === "boolean") term.naturalSort = s.naturalSort;
    if (typeof s.alwaysTabs === "boolean") term.alwaysTabs = s.alwaysTabs;
    if (typeof s.colHeadsOn === "boolean") term.colHeadsOn = s.colHeadsOn;
    if (typeof s.confirmTrash === "boolean") term.confirmTrash = s.confirmTrash;
    if (typeof s.cursorSlide === "boolean") term.cursorSlide = s.cursorSlide;
    if (typeof s.termCmd === "string") term.termCmd = s.termCmd;
    if (typeof s.previewOn === "boolean") term.previewOn = s.previewOn;
    if (typeof s.dirViewCap === "number" && s.dirViewCap > 0)
      term.dirViewCap = Math.round(s.dirViewCap);
    if (typeof s.lastSaveDir === "string" && term.mgr
        && term.mgr.lastSaveDir === "") term.mgr.lastSaveDir = s.lastSaveDir;
    if (typeof s.sessionReplay === "boolean") term.sessionReplay = s.sessionReplay;
    // ── AND THE SIZE, WRITTEN BEFORE THERE IS A SURFACE TO RESIZE ──────
    // This runs from Component.onCompleted, where `visible` has just been
    // put back to `shown` — which is false — so the window has not been
    // mapped yet and the implicit size is still the size it will be born
    // at. Assigning here replaces a constant binding with a constant, which
    // costs nothing; assigning it later would be a resize in front of you.
    //
    // Clamped at minimumSize, because a stored 40x40 is a window a
    // compositor may decline to show at all, and a preferences file is a
    // thing a person can edit by hand.
    const wantW = Number(s.winW);
    const wantH = Number(s.winH);
    if (!isNaN(wantW) && wantW >= 560 && !isNaN(wantH) && wantH >= 320) {
      term.winW = Math.round(wantW);
      term.winH = Math.round(wantH);
      term.implicitWidth = term.winW;
      term.implicitHeight = term.winH;
    }
    // A dialog is born at the size the last dialog was left at, if one
    // ever was — written here for the same no-surface-yet reason.
    // How much of that size a split added — see fitSplit.
    const sg = Number(s.splitGrew);
    if (!isNaN(sg) && sg > 0) term.splitGrew = Math.round(sg);
    const sdg = Number(s.sideGrew);
    if (!isNaN(sdg) && sdg > 0) term.sideGrew = Math.round(sdg);
    // A dialog's sidebar is its own once it has been touched in one; until
    // then it opens the way the window's does. The window's sideGrew is
    // never the dialog's — that room was taken from a different window.
    if (term.isPicker) {
      if (typeof s.pickerSidebar === "boolean") term.sidebar = s.pickerSidebar;
      const psw = Number(s.pickerSidebarWidth);
      if (!isNaN(psw) && psw > 0)
        term.sidebarWidth = Math.max(term.sidebarMin, Math.min(term.sidebarMax, psw));
      const psg = Number(s.pickerSideGrew);
      term.sideGrew = !isNaN(psg) && psg > 0 && term.sidebar ? Math.round(psg) : 0;
    }
    const pw = Number(s.pickerW);
    const ph = Number(s.pickerH);
    if (term.isPicker && !isNaN(pw) && pw >= 560 && !isNaN(ph) && ph >= 320) {
      term.pickerW = Math.round(pw);
      term.pickerH = Math.round(ph);
      term.implicitWidth = term.pickerW;
      term.implicitHeight = term.pickerH;
    }
    // The second pane comes back the way it was left, and its directory with
    // it — but only if that directory still exists, for the same reason the
    // tabs are checked: a pane opening on a removed download is a pane opening
    // on an error.
    if (typeof s.otherCwd === "string") term.pas.cwd = s.otherCwd;
    if (s.paneSide === 1) term.paneSide = 1;
    // ── AND ONLY THE ONES STILL THERE ────────────────────────────────
    // Set straight away, so the tree is right on the first paint for the
    // overwhelming majority of entries that do exist, and then sieved by
    // the answer below. Waiting for a process before showing any branch at
    // all would make every restored session open flat and then jump.
    // The open branches are NOT restored from here any more — the manager
    // holds one record for every window, always restored. See mgr.tree.
    if (s.paneViews && s.paneViews.length === 2) {
      term.paneLRef.viewMode = s.paneViews[0];
      term.paneRRef.viewMode = s.paneViews[1];
    }
    if (s.paneZooms && s.paneZooms.length === 2) {
      if (s.paneZooms[0] > 0) term.paneLRef.zoom = s.paneZooms[0];
      if (s.paneZooms[1] > 0) term.paneRRef.zoom = s.paneZooms[1];
    }
    term.demoteColumns();
    const pf = Number(s.paneFrac);
    if (!isNaN(pf) && pf > 0)
      term.paneFrac = Math.max(term.paneMinFrac, Math.min(term.paneMaxFrac, pf));
    if (s.dirViews && typeof s.dirViews === "object") {
      term.dirViews = s.dirViews;
      term.dirViewOrder = Object.keys(s.dirViews);
    }
    // A PICKER IS NOT A FILE MANAGER. It is a dialog with one job — say which
    // file — and a second pane is a place to put things, which is the one
    // thing it must never be. winId is -1 for the portal's own window and is
    // set before this runs, so the preference is simply not read for it.
    if (term.winId >= 0 && s.dual === true && term.otherCwd !== "") {
      term.dual = true;
      term.refreshOther();
    }
    term.restoreTabs(s);
  }
  // Reopening where you left off, but only the tabs whose directories are still
  // there — a tab pointing at a removed download or an unmounted disk would be
  // a window that opens on an error. Checked by the caller, which is why this
  // hands the surviving list to a process rather than trusting the file.
  function restoreTabs(st) {
    if (term.winId !== 0) return;
    if (!term.sessionReplay) return;
    if (!st.tabs || st.tabs.length === 0) return;
    const want = [];
    for (let i = 0; i < st.tabs.length; ++i) {
      const t = st.tabs[i];
      if (t && typeof t.cwd === "string" && t.cwd !== "") want.push(t);
    }
    if (want.length === 0) return;
    term.pendingTabs = want;
    term.pendingTabIndex = (typeof st.tab === "number") ? st.tab : 0;
    // the directories as arguments, not spliced into the script — see shArgv
    tabCheckProc.command = ["sh", "-c",
      "for d; do [ -d \"$d\" ] && printf '%s\\036' \"$d\"; done", "terminus"]
      .concat(want.map((t) => t.cwd));
    tabCheckProc.running = true;
  }
  function revealWhenReady() {
    term.holdReveal = true;
    term.revealWaited = 0;
    revealPoll.restart();
  }
  Timer {
    id: revealPoll
    interval: 25
    repeat: true
    onTriggered: {
      term.revealWaited += revealPoll.interval;
      const ready = !term.listProcRef.running && term.act.raw.length > 0
        && !term.act.kidsBusy;
      if (!ready && term.revealWaited < 450) return;
      revealPoll.stop();
      if (!term.holdReveal) return;
      term.holdReveal = false;
      term.shown = true;
      term.takeFocus();
    }
  }
  // Asked of every window by the manager when the desktop is clicked — see
  // dismissMenus there.
  function dismissMenus() { if (term.menuPopRef.menu.open) term.menuPopRef.menu.close(); }
  function takeBoot() {
    if (term.bootPath === "") return false;
    const p = term.bootPath;
    term.bootPath = "";
    term.enter(p);
    return true;
  }
  Process {
    id: tabCheckProc
    stdout: StdioCollector {
      id: tabCheckOut
      waitForEnd: true
      onStreamFinished: {
        const alive = {};
        for (const d of String(tabCheckOut.text || "").split("\u001e")) {
          if (d !== "") alive[d] = true;
        }
        const kept = term.pendingTabs.filter((t) => alive[t.cwd]);
        term.pendingTabs = [];
        if (kept.length === 0) { term.takeBoot(); return; }
        term.tabs = kept;
        term.tab = Math.max(0, Math.min(kept.length - 1, term.pendingTabIndex));
        const t = kept[term.tab];
        term.act.sel = t.sel || 0;
        // The restored tab, unless this window was built to go somewhere —
        // then the tabs are kept as they are and the destination wins, which
        // is what asking for one means.
        if (term.takeBoot()) return;
        // enter() rather than goTo(): this is where the window already is as
        // far as history is concerned, not somewhere it navigated to.
        term.enter(t.cwd);
      }
    }
  }
  // a dialog's sidebar into its own slot, a window's into the shared prefs
  function saveSide() {
    if (term.isPicker) pickerSave.restart();
    else viewSave.restart();
  }
}
