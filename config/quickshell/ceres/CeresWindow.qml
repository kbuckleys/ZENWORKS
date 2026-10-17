// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// CERES — the Store and the package manager, as a window.
//
// ZENU's views, without a terminal in the way:
//
//   Updates    what is pending, with what each one is, and Update all
//   Packages   the repos and the AUR, searched as you type; esc leaves the
//              field, space or tab marks, ↵ to see exactly what the change
//              will do and cost
//
// and, over either, the three things a change goes through: CONFIRM (targets,
// what comes with them, what goes with them, the download and the disk, and
// why a removal cannot happen if it cannot), REVIEW (an AUR package's
// PKGBUILD as the AUR has it now, diffed against the one last built here),
// and the TRANSACTION (the shared password field and progress view — see
// PasswordField and TxView — so it reads the same here as in the panel).
//
// THE LIST IS NEVER IN HERE. scripts/ceres.sh holds the 135,000 rows and is
// asked for the few hundred that match; see Cer.searchCommand.

import QtQuick
import Quickshell
import Quickshell.Io
import "../morpheus"
import "../terminus" as Term
import "."
import "ceres.js" as Cer
import "store.js" as St

FloatingWindow {
  id: win
  title: "ceres"
  implicitWidth: 1100
  implicitHeight: 720
  // Lower while onboarding, so the window can be exactly as tall as the
  // setup screen — see onboardH.
  minimumSize: Qt.size(760, win.onboarding ? 240 : 440)
  color: Zenon.layerBg
  visible: false

  readonly property string script: Quickshell.shellDir + "/scripts/ceres.sh"
  property var mgr: null
  // the head's glyph buttons say what they are here (user, 2026-10-15)
  readonly property string checkTip: Ceres.checking ? "Checking for updates…"
    : Ceres.lastOk > 0 ? "Check for updates · last checked " + Cer.age(Ceres.now - Ceres.lastOk)
    : "Check for updates"
  WindowTip { id: headTip; window: win }
  onCheckTipChanged: if (headTip.target === refreshChip) headTip.text = win.checkTip

  // The size you left it at, handed back by the manager the next time it
  // builds one — see CeresManager. Written once a resize settles.
  onWidthChanged: sizeSettle.restart()
  onHeightChanged: sizeSettle.restart()
  Timer {
    id: sizeSettle
    interval: 600
    // the onboarding size is not yours, and is not remembered as if it were
    onTriggered: if (win.visible && win.mgr && !win.onboarding) win.mgr.noteSize(win.width, win.height)
  }

  // ── ONBOARDING IS AS TALL AS WHAT IT SAYS ──────────────────────────────
  // The setup screen is a few lines and two cards; in a window left at a
  // browsing size it sat in the top third with the rest empty. While it is
  // up the window fits it, and gives the height back when it goes.
  property real keptH: 0
  readonly property real onboardH: setupView.needH + 48 + foot.height
  onOnboardingChanged: {
    if (win.onboarding) {
      win.keptH = win.height;
      win.implicitHeight = win.onboardH;
    } else if (win.keptH > 0) {
      win.implicitHeight = win.keptH;
      win.keptH = 0;
    }
  }
  onOnboardHChanged: if (win.onboarding) win.implicitHeight = win.onboardH

  // ── where we are ────────────────────────────────────────────────────────
  // THE STORE OPENS FIRST (user, 2026-10-14): Ceres is where apps are
  // found now, and the updates are a tab away — the bar's count still opens
  // straight onto them (present("updates")).
  property string tab: "store"
  // The views, in switch order: [name, label].
  readonly property var tabs: [
    ["store", "Store"],
    ["packages", "Packages"],
    // after Packages (user, 2026-10-14): find, then keep current
    ["updates", Ceres.total > 0 ? "Updates  " + Ceres.total : "Updates"],
    ["history", "History"],
    ["maintenance", win.maint && win.maintCount > 0 ? "Maintenance  " + win.maintCount : "Maintenance"],
    ["settings", configView.changes > 0 ? "Settings  " + configView.changes : "Settings"]
  ]
  // The label column of a list of [label, value, ...] fact rows (the cache's
  // and the mirrors'): as wide as the longest label, never narrower than the
  // 250 the rows used to be fixed at, so short lists keep their alignment.
  FontMetrics { id: mfFact; font.family: Zenon.face; font.pixelSize: Zenon.px(16) }
  function factLabelWidth(facts) {
    let w = 250;
    for (const f of facts || []) w = Math.max(w, Math.ceil(mfFact.advanceWidth(String(f[0]))));
    return w;
  }

  function showTab(t) {
    win.tab = t;
    // Packages is a search, so it opens in the field; the others are lists
    // you came to read and mark, and `/` is there when one needs narrowing.
    // The Store opens with its search idle, as the App Store does — the
    // arrows walk its shelves — and a letter typed goes straight into it.
    win.typing = t === "packages";
    if (t === "packages" && win.found.length === 0) win.search();
    if (t === "store" && !storeView.loaded) storeView.load();
    // the Store's catalog too: a Flatpak since removed is named from it
    if (t === "history") { win.loadHistory(); if (!storeView.loaded) storeView.load(); }
    if (t === "maintenance") {
      win.loadMaint();
      if (win.maintItems[win.msel] && win.maintItems[win.msel].key === "flatpak" && !win.fpRepair) win.checkFlatpakRepair();
    }
    // read once; after that the edits in hand are what the tab shows
    if (t === "settings" && !configView.loaded) configView.load();
    keys.forceActiveFocus();
  }
  function cycleTab(d) {
    const names = win.tabs.map(x => x[0]);
    win.showTab(names[(names.indexOf(win.tab) + d + names.length) % names.length]);
  }
  // Over the tab, when something is being decided. The transaction faces
  // are Ceres' state, not this window's — a run started from the panel is
  // shown here too.
  property string overlay: ""               // "" | "confirm" | "review"
  property bool asking: false
  property bool showSetup: false
  // ── THE PASSWORD, AS A SHEET ────────────────────────────────────────────
  // Not a page of its own: it hangs from the head over whatever asked for it
  // — the confirm screen, the setup screen, the list — so what the password
  // is FOR stays in sight while it is typed. (It was once a face, checked
  // after setup, and the setup screen covered it: Install looked dead.)
  readonly property bool authUp: Ceres.txState === "authfail" || win.asking
  // A QUIET JOB — one that changes no package: a cache trimmed, a sync, a
  // sweep — is started with nothing expected of pacman.log (expected 0). It
  // never takes the page: its progress and then its one-line result, the
  // tool's own, are a sheet over whatever it was started from. It used to
  // switch to the progress page for the second it ran and THEN drop the
  // sheet, which read as the page flashing.
  readonly property bool quietJob: Ceres.txState !== "" && Ceres.txState !== "authfail"
    && Ceres.txExpected === 0
  // never two sheets at once: the password's goes first
  // ── PARU'S UNASKED QUESTION, IN A SHEET (user, 2026-10-14) ────────────
  // A failed run that only wanted an answer — a package to replace, a
  // provider to pick (Ceres.txSettle) — asks it in settleSheet rather than
  // in the failure page or message. Cancel (esc) puts it aside: the plain
  // failure underneath, with its Open in terminal, is what is left.
  property bool settleAside: false
  Connections {
    target: Ceres
    function onTxSettleChanged() { win.settleAside = false; }
  }
  readonly property bool settleUp: txView.settling && Ceres.txState === "failed"
    && !win.settleAside && !win.authUp
  readonly property bool msgUp: win.quietJob && !win.authUp && !win.settleUp
  // the frost under the head and foot — terminus' strip (see the edges)
  readonly property int frostBlur: 64
  readonly property real frostVeil: 0.6
  // how far in the sheets are, for the stage's blur
  readonly property real sheetInk: Math.max(passSheet.cardInk, msgSheet.cardInk,
                                            confirmSheet.cardInk, confSheet.cardInk, fpSheet.cardInk, fpGetSheet.cardInk,
                                            settleSheet.cardInk)
  // ONE SHEET AT A TIME. Go ahead on the confirm asks for the password, and
  // the password's sheet came up BEHIND the confirm's — the prompt was there
  // and could not be seen until the confirm was dismissed. The confirm steps
  // aside while the password is asked for, and comes back if it is canceled.
  readonly property bool confirmUp: win.face === "confirm" && !win.authUp
  // WHAT THE PAGE IS, under whatever sheet is over it. The confirm is a
  // sheet, so the page beneath it is the one it came from — the list, still
  // there, softened.
  readonly property string page: (win.face === "confirm" || win.face === "conf" || win.face === "fpoff"
                                  || win.face === "fpget")
    ? "browse" : win.face
  // pacman.conf's review: a sheet over the Settings tab, like the confirm
  readonly property bool confUp: win.face === "conf" && !win.authUp
  // Settings › Channels' Remove Flatpak…, asked in a sheet that names the
  // apps going with it (user, 2026-10-14)
  readonly property bool fpUp: win.face === "fpoff" && !win.authUp
  function removeFlatpak() {
    win.overlay = "";
    Ceres.removeFlatpak(win.fpDeleteData);
  }

  // WHAT THE APPS KEPT, gone with them unless you say otherwise (user,
  // 2026-10-15: Ceres keeps the system clean): a removal sheet's box,
  // ticked when it opens, with how much it is — ~/.var/app/<id> for one
  // app, ~/.var/app for Flatpak itself.
  property bool fpDeleteData: true
  property string fpDataSize: ""
  function measureData(id) {
    win.fpDeleteData = true;
    win.fpDataSize = "";
    fpDuProc.running = false;
    fpDuProc.command = ["sh", "-c", "du -sh -- \"$HOME/.var/app\"" + (id ? "/" + Cer.q(id) : "") + " 2>/dev/null | cut -f1"];
    Qt.callLater(() => { fpDuProc.running = true; });
  }
  Process {
    id: fpDuProc
    stdout: StdioCollector { id: fpDuOut; onStreamFinished: win.fpDataSize = fpDuOut.text.trim() }
  }

  // ── ONE FLATPAK APP, IN OR OUT (the Store's Get / Remove on Flathub) ───
  // A sheet of its own rather than the confirm sheet, which is pacman's
  // plan: where it goes — for everyone (the password) or just you (none;
  // user, 2026-10-14) — its sizes, and what its sandbox lets it touch.
  property var fpApp: null
  property bool fpRemove: false
  property string fpScope: "system"
  property var fpInfo: null
  property var fpPerms: null
  readonly property bool fpGetUp: win.face === "fpget" && !win.authUp
  function askFlatpak(app, remove) {
    win.fpApp = app;
    win.fpRemove = remove;
    win.fpScope = remove ? (app.scope === "user" ? "user" : "system") : Ceres.flatpakScope;
    win.fpInfo = null;
    win.fpPerms = null;
    win.fpRuntime = null;
    if (remove) win.measureData(app.pkg);
    if (!remove) {
      fpInfoProc.running = false;
      fpMetaProc.running = false;
      fpInfoProc.command = ["flatpak", "remote-info", "--system", "flathub", app.pkg];
      fpMetaProc.command = ["flatpak", "remote-info", "--system", "--show-metadata", "flathub", app.pkg];
      fpInfoProc.running = true;
      fpMetaProc.running = true;
    }
    win.overlay = "fpget";
  }
  function goFlatpak() {
    const a = win.fpApp;
    if (!a || Ceres.txBusy) return;
    win.overlay = "";
    if (win.fpRemove) Ceres.request(Cer.flatpakUninstallSteps(a.pkg, win.fpScope, win.fpDeleteData), "remove " + a.name, 0);
    else {
      Ceres.setFlatpakScope(win.fpScope);
      Ceres.request(Cer.flatpakInstallSteps(a.pkg, win.fpScope), "install " + a.name, 0);
    }
  }
  Process {
    id: fpInfoProc
    stdout: StdioCollector {
      id: fpInfoOut
      onStreamFinished: {
        win.fpInfo = St.remoteInfo(fpInfoOut.text);
        // and the runtime it runs on: here already, or what it costs first
        const rt = win.fpInfo["Runtime"] || "";
        win.fpRuntime = null;
        if (rt === "") return;
        fpRtProc.running = false;
        fpRtProc.command = ["sh", "-c", "rt=" + Cer.q(rt) + "; "
          + "flatpak list --runtime --columns=ref 2>/dev/null | grep -qx \"$rt\" && { echo '@@have'; exit 0; }; "
          + "flatpak remote-info --system flathub \"runtime/$rt\" 2>/dev/null"];
        Qt.callLater(() => { fpRtProc.running = true; });
      }
    }
  }
  // THE RUNTIME FIRST (user, 2026-10-15: "are all flatpak downloads this
  // big?"): an app needs the runtime it is built on — hundreds of MB — and
  // the first app on one brings it down. The sheet says so, and how much,
  // when it is not here yet. null: here already, or not known.
  property var fpRuntime: null
  Process {
    id: fpRtProc
    stdout: StdioCollector {
      id: fpRtOut
      onStreamFinished: {
        if (fpRtOut.text.indexOf("@@have") >= 0) { win.fpRuntime = null; return; }
        const i = St.remoteInfo(fpRtOut.text);
        win.fpRuntime = i["Download Size"] ? { name: (fpRtOut.text.split("\n")[0] || "").split(" - ")[0].trim(),
                                              ref: i["Ref"] || "", download: i["Download Size"],
                                              installed: i["Installed Size"] || "" } : null;
      }
    }
  }
  Process {
    id: fpMetaProc
    stdout: StdioCollector { id: fpMetaOut; onStreamFinished: win.fpPerms = St.permissions(fpMetaOut.text) }
  }
  // THE HEAD STANDS DOWN while there is nothing it could do: through
  // onboarding, and for the whole of a job — tabs and a filter over a
  // progress bar are only noise.
  readonly property bool headHidden: win.onboarding || win.face === "tx"
  function cancelAuth() {
    win.asking = false; field.pw = ""; field.failed = false;
    configView.cancelSave(); win.mirrorsAfter = false;
    Ceres.txClear(); Ceres.forgetNext();
  }
  // ONBOARDING: from the setup screen through its password and its install,
  // there is no tab to switch to and nothing to filter — the head is not
  // shown until paru is here and ceres is ceres.
  readonly property bool onboarding: win.face === "setup"
    || (Ceres.deps.paru && win.face === "tx")
  readonly property string face: {
    const s = Ceres.txState;
    // A finished job STAYS where it ran, log and all — it used to become a
    // sheet of the changes alone, which took the log away the moment it was
    // done. Return or Back leaves it, as it leaves a failed one.
    if (s === "done" && !win.quietJob) return "tx";
    if ((s === "auth" || s === "running" || s === "failed") && !win.quietJob) return "tx";
    if (Ceres.newsGate) return "news";
    // No paru, nothing works: setup is the whole window. Anything less
    // missing waits behind the "Set up" button until asked for.
    if (Ceres.setupNeeded && (Ceres.deps.paru || win.showSetup)) return "setup";
    return win.overlay !== "" ? win.overlay : "browse";
  }

  function present(view) {
    win.visible = true;
    win.showTab(win.tabs.some(x => x[0] === view) ? view : win.tab);
    // asked for with a query (Ceres.searchPackages)
    if (view === "packages" && Ceres.askedQuery !== "") {
      win.sharedQuery = Ceres.askedQuery;
      Ceres.askedQuery = "";
    }
  }

  // ── CLOSED BY THE COMPOSITOR ──────────────────────────────────────────
  // super+q closes the WINDOW, not this object: quickshell reports it as
  // `closed` and leaves `visible` saying true. Every open after that set
  // visible to true — no change — and nothing came back until the shell
  // restarted. Closed from outside is dismissed from inside, the same as
  // escape, which also puts `visible` back where it belongs.
  onClosed: win.dismiss()

  function dismiss() {
    field.pw = "";
    win.asking = false;
    if (!Ceres.txBusy) Ceres.forgetNext();
    if (Ceres.txState === "done" || Ceres.txState === "authfail") Ceres.txClear();
    win.visible = false;
  }

  // ── Packages: the query, the rows, the marks ───────────────────────────
  // ONE QUERY FOR EVERY TAB THAT SEARCHES (user, 2026-10-15): looked for in
  // the Store and not there, it is in Packages the moment you switch — never
  // typed twice. Each tab's own name for it stays, read-only, so every
  // reader reads the one text.
  property string sharedQuery: ""
  readonly property string query: win.sharedQuery
  property bool installedOnly: false
  // what the search returned, in its order — and `rows`, what is drawn and
  // walked: the same, sorted by the column you chose, if you chose one
  property var found: []
  property string sortKey: ""
  property bool sortDesc: false
  readonly property var rows: Cer.sortRows(win.found, win.sortKey, win.sortDesc)
  function sortBy(key) {
    if (win.sortKey === key) win.sortDesc = !win.sortDesc;
    else { win.sortKey = key; win.sortDesc = key === "size"; }
    win.sel = 0;
    pkgList.positionViewAtBeginning();
  }
  property int sel: 0
  // name → row, for everything marked. Installed means it will be removed;
  // not installed means it will be installed — ZENU's rule, and the only
  // one that needs no second key.
  property var marks: ({})
  readonly property int markCount: Object.keys(win.marks).length

  onQueryChanged: searchDelay.restart()
  onInstalledOnlyChanged: win.search()

  Timer { id: searchDelay; interval: 90; onTriggered: win.search() }

  // One search at a time, for the query as it stands. The first search of a
  // session builds the whole list and takes seconds; a keystroke landing
  // meanwhile was a no-op restart, so the list answered an older query and
  // never caught up. A run is drawn only if it is still the question, and a
  // run that was overtaken makes way for one that is.
  function searchKey() { return (win.installedOnly ? "1" : "0") + "\n" + win.query; }
  function search() {
    if (searchProc.running) { searchProc.again = true; return; }
    searchProc.askedKey = win.searchKey();
    searchProc.command = ["sh", "-c", Cer.searchCommand(win.script, win.installedOnly, win.query)];
    searchProc.running = true;
  }

  Process {
    id: searchProc
    property string askedKey: ""
    property bool again: false
    onExited: if (searchProc.again) { searchProc.again = false; Qt.callLater(win.search); }
    stdout: StdioCollector {
      id: searchOut
      onStreamFinished: {
        if (searchProc.askedKey !== win.searchKey()) return;
        win.found = Cer.parseRows(searchOut.text);
        const at = win.seekName === "" ? -1 : win.rows.findIndex(r => r.name === win.seekName);
        win.seekName = "";
        win.sel = Math.max(0, at);
        if (at > 0) pkgList.positionViewAtIndex(at, ListView.Contain);
        else pkgList.positionViewAtBeginning();
        win.peek();
      }
    }
  }

  // ctrl+a: every row on screen marked, or — when they all are already —
  // none of them. What is on screen, not the whole catalog: a search for
  // "gst" and ctrl+a means those, and nothing else.
  function markAll() {
    const all = win.rows.every(r => !!win.marks[r.name]);
    const m = Object.assign({}, win.marks);
    for (const r of win.rows) { if (all) delete m[r.name]; else m[r.name] = r; }
    win.marks = m;
  }
  function markAllUpdates() {
    const rows = win.updateRows.filter(r => !r.head && !r.flatpak);
    const all = rows.every(r => !!win.umarks[r.u.name]);
    const m = {};
    if (!all) for (const r of rows) m[r.u.name] = r;
    win.umarks = m;
  }

  // ── CTRL AND SHIFT CLICKS (user, 2026-10-17) ────────────────────────────
  // ctrl+click marks or unmarks one row, as a right click does; shift+click
  // marks every row from the last one clicked to this one, as a file
  // manager selects. The anchor is the last row clicked either way.
  property int anchor: -1
  property int uanchor: -1
  function markRange(from, to) {
    const a = Math.min(from, to), b = Math.max(from, to);
    const m = Object.assign({}, win.marks);
    for (let i = Math.max(0, a); i <= b && i < win.rows.length; ++i) m[win.rows[i].name] = win.rows[i];
    win.marks = m;
  }
  function markUpdateRange(from, to) {
    const a = Math.min(from, to), b = Math.max(from, to);
    const m = Object.assign({}, win.umarks);
    for (let i = Math.max(0, a); i <= b && i < win.updateRows.length; ++i) {
      const r = win.updateRows[i];
      if (!r.head && !r.flatpak) m[r.u.name] = r;
    }
    win.umarks = m;
  }
  function rowClick(i, mods) {
    if (mods & Qt.ShiftModifier) win.markRange(win.anchor >= 0 ? win.anchor : win.sel, i);
    else if (mods & Qt.ControlModifier) win.toggleMark(win.rows[i]);
    if (!(mods & Qt.ShiftModifier)) win.anchor = i;
    win.sel = i;
    keys.forceActiveFocus();
  }
  function updateClick(i, mods) {
    if (mods & Qt.ShiftModifier) win.markUpdateRange(win.uanchor >= 0 ? win.uanchor : win.usel, i);
    else if (mods & Qt.ControlModifier) win.toggleUmark(win.updateRows[i]);
    if (!(mods & Qt.ShiftModifier)) win.uanchor = i;
    win.usel = i;
    keys.forceActiveFocus();
  }

  function toggleMark(r) {
    if (!r) return;
    const m = Object.assign({}, win.marks);
    if (m[r.name]) delete m[r.name];
    else m[r.name] = r;
    win.marks = m;
  }

  // ── Updates: the pending list, with headings ────────────────────────────
  // Updates has no search (user, 2026-10-17: the shared query, typed in
  // another tab, hid the one update under a count of 1)
  readonly property string uquery: ""
  onUqueryChanged: { win.usel = 1; while (win.updateRows[win.usel] && win.updateRows[win.usel].head) win.usel++; }
  readonly property var updateRows: {
    const out = [];
    const q = win.uquery.toLowerCase();
    const repo = Ceres.repo.filter(u => Cer.matchesAll(u.name, q));
    const aur = Ceres.aur.filter(u => Cer.matchesAll(u.name, q));
    if (repo.length) {
      out.push({ head: true, label: "Official", n: repo.length, aur: false });
      for (const u of repo) out.push({ head: false, u: u, aur: false });
    }
    if (aur.length) {
      out.push({ head: true, label: "AUR", n: aur.length, aur: true });
      for (const u of aur) out.push({ head: false, u: u, aur: true });
    }
    // Flatpak's: updated by Flatpak, never marked into a pacman job
    const flat = Ceres.flat.filter(u => Cer.matchesAll(u.name, q));
    if (flat.length) {
      out.push({ head: true, label: "Flatpak", n: flat.length, aur: false, flatpak: true });
      for (const u of flat) out.push({ head: false, u: u, aur: false, flatpak: true });
    }
    return out;
  }

  // ── THE FILTER, WHICHEVER TAB ───────────────────────────────────────────
  // Every list tab has a filter, and each keeps its own text — the header
  // shows the one for the tab on screen. Maintenance has five rows and
  // nothing to filter.
  //
  // THE FILTER IS A FIELD YOU ARE IN OR OUT OF. It used to be typing
  // anywhere, always — so there was no "in" to step out of, and Esc had to
  // pick between the text and the marks. It picked the marks, and a filter
  // you only meant to change cost everything chosen through it. Now Esc
  // leaves the field first, text kept; out of it space marks, j k move and
  // `/` goes back in; and only then does Esc clear the text, then the marks.
  property bool typing: false
  // the Store's search — see StoreView.query
  readonly property string squery: win.sharedQuery
  readonly property bool filters: win.tab !== "maintenance" && win.tab !== "settings" && win.tab !== "updates"
  readonly property string filterText:
    win.tab === "packages" ? win.query : win.tab === "history" ? win.hquery
    : win.tab === "updates" ? win.uquery : win.tab === "store" ? win.squery : ""
  function setFilter(t) {
    if (win.filters) win.sharedQuery = t;
  }
  // One place typing is understood, for every tab that filters. Returns
  // whether the key was a filter key.
  function filterKey(event) {
    const k = event.key, ctrl = event.modifiers & Qt.ControlModifier;
    if (!win.typing) {
      // terminus' "go to the filter" — and backspace, which can only mean
      // the text, goes back in to take a letter off it
      if (k === Qt.Key_Slash) { win.typing = true; return true; }
      if (k === Qt.Key_Backspace) { win.typing = true; win.setFilter(win.filterText.slice(0, -1)); return true; }
      return false;
    }
    if (ctrl && k === Qt.Key_U) { win.setFilter(""); return true; }
    if (ctrl && k === Qt.Key_W) { win.setFilter(win.filterText.replace(/\S*\s*$/, "")); return true; }
    if (k === Qt.Key_Backspace) { win.setFilter(win.filterText.slice(0, -1)); return true; }
    // already in it; no package name holds a slash, so the habit costs nothing
    if (k === Qt.Key_Slash) return true;
    if (event.text && event.text.length > 0 && !ctrl && !(event.modifiers & Qt.MetaModifier)
        && /^[\x20-\x7e]$/.test(event.text)) {
      // a space starts a new word, never the filter, and never two in a row
      if (event.text === " " && (win.filterText === "" || / $/.test(win.filterText))) return true;
      win.setFilter(win.filterText + event.text);
      return true;
    }
    return false;
  }
  property int usel: 1

  // ── the row under the cursor, described ─────────────────────────────────
  readonly property var current: {
    if (win.tab === "packages") return win.rows[win.sel] || null;
    const r = win.updateRows[win.usel];
    // a Flatpak row is looked up by its id, of Flathub (Cer.infoCommand)
    // (the runtimes row is several things, and has no one record to show)
    if (r && !r.head && r.flatpak && r.u.runtime) return null;
    return r && !r.head ? (r.flatpak ? { name: r.u.id, repo: "flatpak", aur: false }
                                     : { name: r.u.name, repo: "update", aur: r.aur }) : null;
  }
  property var info: null
  property string infoFor: ""

  onCurrentChanged: win.peek()
  onTabChanged: win.peek()

  function peek() { infoDelay.restart(); }
  Timer {
    id: infoDelay
    interval: 140
    onTriggered: {
      const c = win.current;
      if (!c) { win.info = null; win.infoFor = ""; return; }
      const repo = c.repo === "update" ? "update" : (c.aur ? "aur" : "");
      if (win.infoFor === c.name + "|" + repo) return;
      win.infoFor = c.name + "|" + repo;
      win.startInfo();
      // what needs it and what it put on disk: only for what is installed
      win.extras = null;
      win.extrasFor = (c.installed || c.repo === "update") ? c.name : "";
      win.startExtras();
    }
  }
  // Each run carries the row it was asked about, and only that row's answer
  // is shown. A stop and a start in the same breath is not a restart a
  // Process can be relied on to make, and the stopped run's collector could
  // still hand over the previous package's record — so a run still out is
  // left to finish, and the row now current is asked about when it does.
  function startInfo() {
    if (infoProc.running || win.infoFor === "") return;
    const bar = win.infoFor.lastIndexOf("|");
    infoProc.runFor = win.infoFor;
    infoProc.command = ["sh", "-c", Cer.infoCommand(win.script,
      win.infoFor.slice(0, bar), win.infoFor.slice(bar + 1))];
    infoProc.running = true;
  }
  Process {
    id: infoProc
    property string runFor: ""
    onExited: if (infoProc.runFor !== win.infoFor) Qt.callLater(win.startInfo)
    stdout: StdioCollector {
      id: infoOut
      onStreamFinished: if (infoProc.runFor === win.infoFor) win.info = Cer.parseInfo(infoOut.text)
    }
  }
  // ── A PEEK AT A PACKAGE ────────────────────────────────────────────
  // The pointer resting on a row that is not the chosen one: what it is,
  // in terminus' Bubble hanging from the row (as delphi's pull requests
  // peek) — its description, version, where from, how big. Asked with the
  // same `info` the preview uses, once the pointer has stayed a moment.
  //
  // ONE AFTER ANOTHER (user, 2026-10-14): what the bubble shows is
  // `peekShown` — a row, its package and its info together — and it is
  // swapped whole once the next package's info is in, never cleared on
  // the way: the bubble stays up on the last one meanwhile, then moves
  // on, rather than closing, showing the next name with nothing under it
  // and opening again. With a peek up, the next row is asked at once
  // (nearly); it goes only when the pointer has left the rows a moment.
  property Item peekRow: null
  property var peekPkg: null
  property var peekInfo: null
  property var peekShown: null
  onSelChanged: { win.peekInfo = null; win.peekShown = null; }
  Timer { id: peekWait; interval: 450; onTriggered: win.startPeek() }
  Timer { id: peekLeave; interval: 220; onTriggered: if (!win.peekPkg) win.peekShown = null }
  function peekAt(row, pkg) {
    win.peekRow = row;
    win.peekPkg = pkg;
    win.peekInfo = null;
    if (!pkg) { peekWait.stop(); peekLeave.restart(); return; }
    peekLeave.stop();
    peekWait.interval = win.peekShown ? 90 : 450;
    peekWait.restart();
  }
  function startPeek() {
    const p = win.peekPkg;
    if (!p || !win.peekRow) return;
    if (peekProc.running) { peekProc.again = true; return; }
    peekProc.runFor = p.name;
    peekProc.command = ["sh", "-c", Cer.infoCommand(win.script, p.name,
      p.repo === "update" ? "update" : (p.aur ? "aur" : ""))];
    peekProc.running = true;
  }
  Process {
    id: peekProc
    property string runFor: ""
    property bool again: false
    onExited: if (peekProc.again) { peekProc.again = false; win.startPeek(); }
    stdout: StdioCollector {
      id: peekOut
      onStreamFinished: {
        if (!win.peekPkg || peekProc.runFor !== win.peekPkg.name) return;
        win.peekInfo = Cer.parseInfo(peekOut.text);
        win.peekShown = { row: win.peekRow, pkg: win.peekPkg, info: win.peekInfo };
      }
    }
  }
  Term.Bubble {
    id: peekBubble
    window: win
    target: win.peekShown ? win.peekShown.row : null
    shown: !!win.peekShown && !(win.current && win.current.name === win.peekShown.pkg.name)
    readonly property var pkg: win.peekShown ? win.peekShown.pkg : null
    cardWidth: 440
    readonly property var m: win.peekShown ? win.peekShown.info.map : ({})
    Text {
      width: 412
      elide: Text.ElideRight
      textFormat: Text.StyledText
      text: peekBubble.pkg ? "<b>" + Cer.esc(peekBubble.pkg.name) + "</b>  <font color='" + Ceres.ink.muted + "'>"
        + Cer.esc(peekBubble.m["Version"] || peekBubble.pkg.version || "") + "</font>" : ""
      color: Zenon.ink
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(16)
    }
    Text {
      width: 412
      visible: text !== ""
      wrapMode: Text.Wrap
      maximumLineCount: 4
      elide: Text.ElideRight
      text: peekBubble.m["Description"] || ""
      color: Zenon.accentSoft
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(14)
    }
    Text {
      width: 412
      elide: Text.ElideRight
      text: [peekBubble.pkg ? (peekBubble.pkg.repo || "") : "",
             peekBubble.m["Installed Size"] ? "installed " + peekBubble.m["Installed Size"]
               : peekBubble.m["Download Size"] ? "download " + peekBubble.m["Download Size"] : "",
             peekBubble.pkg && peekBubble.pkg.installed ? (peekBubble.pkg.state === "explicit" ? "installed by you" : "installed as a dependency") : "not installed"]
        .filter((x) => x !== "").join("   ·   ")
      color: Zenon.accentMuted
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(13)
    }
    Text {
      width: 412
      visible: text !== "" && text !== "None"
      elide: Text.ElideMiddle
      text: peekBubble.m["URL"] || ""
      color: Zenon.blue
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(13)
    }
  }

  // ── WHAT IS MARKED, NAMED (user, 2026-10-17) ────────────────────────
  // The head's +N / −N, rested on: the packages behind it, in the same
  // inks — green in, red out, yellow for updates (with old → new) — in
  // terminus' Bubble, as the rows' own peek.
  readonly property int markShowMost: 16
  readonly property var markLines: {
    const out = [];
    const ink = (c) => Zenon.hex(c);
    if (win.tab === "updates") {
      for (const n of Object.keys(win.umarks).sort()) {
        const u = win.umarks[n].u;
        out.push("<font color='" + ink(Zenon.yellow) + "'>\uF062</font>  " + Cer.esc(n)
          + (u.from || u.to ? "  <font color='" + Ceres.ink.muted + "'>" + Cer.esc(u.from || "")
            + " \u2192 " + Cer.esc(u.to || "") + "</font>" : ""));
      }
    } else {
      const names = Object.keys(win.marks).sort();
      // what goes in first, then what comes out
      for (const pass of [false, true])
        for (const n of names) {
          const r = win.marks[n];
          if (!!r.installed !== pass) continue;
          out.push(pass ? "<font color='" + ink(Zenon.red) + "'>\u2212</font>  " + Cer.esc(n)
                        : "<font color='" + ink(Zenon.green) + "'>+</font>  " + Cer.esc(n));
        }
    }
    return out;
  }
  Term.Bubble {
    id: markBubble
    window: win
    target: markTally
    shown: markHov.hovered && markTally.visible && win.markLines.length > 0 && win.face === "browse"
    cardWidth: 360
    Text {
      width: 332
      textFormat: Text.StyledText
      wrapMode: Text.Wrap
      lineHeight: 1.15
      text: win.markLines.slice(0, win.markShowMost).join("<br>")
        + (win.markLines.length > win.markShowMost
          ? "<br><font color='" + Ceres.ink.muted + "'>and " + (win.markLines.length - win.markShowMost) + " more</font>" : "")
      color: Zenon.ink
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(15)
    }
  }

  // what needs the package and what it installed — installed packages only
  property var extras: null
  property string extrasFor: ""
  // the preview's file list, opened — folded again for the next package
  property bool filesOpen: false
  onExtrasForChanged: win.filesOpen = false

  // ── TO A PACKAGE BY NAME, from a chip in the preview ────────────────────
  // Packages, searched for exactly that name; the search puts the exact name
  // first, and `seekName` picks it out wherever a chosen sort has put it.
  property string seekName: ""
  function jumpTo(name) {
    win.seekName = name;
    if (win.tab !== "packages") win.showTab("packages");
    win.typing = false;
    // already the question: no search will come back to pick it, so pick it now
    if (win.query === name) {
      const at = win.rows.findIndex(r => r.name === name);
      win.seekName = "";
      if (at >= 0) { win.sel = at; pkgList.positionViewAtIndex(at, ListView.Contain); }
    } else win.sharedQuery = name;
    keys.forceActiveFocus();
  }
  function startExtras() {
    if (extrasProc.running || win.extrasFor === "") return;
    extrasProc.runFor = win.extrasFor;
    extrasProc.command = ["sh", "-c", Cer.extrasCommand(win.extrasFor)];
    extrasProc.running = true;
  }
  Process {
    id: extrasProc
    property string runFor: ""
    onExited: if (extrasProc.runFor !== win.extrasFor) Qt.callLater(win.startExtras)
    stdout: StdioCollector {
      id: extrasOut
      onStreamFinished: if (extrasProc.runFor === win.extrasFor) win.extras = Cer.readExtras(extrasOut.text)
    }
  }

  // ── confirm: what the change will do ────────────────────────────────────
  property var plan: null
  property bool planning: false
  // What the confirm screen is ABOUT, taken when it opens: the marks if
  // there are any, and otherwise the highlighted row on its own. ↵ never
  // marks anything — backing out of a confirm for the row under the cursor
  // leaves nothing marked behind.
  property var targets: ({})
  // "change" — installs and removals from Packages or Maintenance — or
  // "update": some of the pending updates, which is its own thing (see
  // confirmUpdates).
  property string confirmKind: "change"
  readonly property var installNames: win.confirmKind === "undo" ? (win.undo ? win.undo.back.map(b => b.name) : [])
    : win.confirmKind === "update" ? Object.keys(win.targets)
    : Object.keys(win.targets).filter(n => !win.targets[n].installed)
  readonly property var removeNames: win.confirmKind === "undo" ? (win.undo ? win.undo.remove.map(r => r.name) : [])
    : win.confirmKind === "update" ? []
    : Object.keys(win.targets).filter(n => win.targets[n].installed)
  // an undo builds nothing: its copies are already built, or the archive's
  readonly property var aurTargets: win.confirmKind === "undo" ? []
    : win.installNames.filter(n => win.targets[n] && win.targets[n].aur)
  // and what is marked right now, for the foot
  readonly property int markInstalls: Object.keys(win.marks).filter(n => !win.marks[n].installed).length
  readonly property int markRemovals: win.markCount - win.markInstalls

  function confirm() {
    if (win.markCount > 0) win.confirmFor(Object.assign({}, win.marks));
    else if (win.rows[win.sel]) win.confirmOne(win.rows[win.sel]);
  }
  // One package, whatever is marked — a double click, or ↵ with no marks.
  function confirmOne(r) {
    const t = {};
    t[r.name] = r;
    win.confirmFor(t);
  }
  function confirmFor(t) {
    win.confirmKind = "change";
    win.targets = t;
    win.plan = null;
    win.planning = true;
    win.overlay = "confirm";
    win.askPlan(["sh", "-c", Cer.planCommand(
      win.installNames.filter(n => !win.targets[n].aur), win.removeNames)]);
  }
  // THE PLAN ON THE SHEET IS THE PLAN FOR WHAT THE SHEET IS ABOUT. Backing
  // out of A's confirm and opening B's while A's plan was still being worked
  // out re-armed a running Process — a no-op — and A's dependencies, sizes
  // and blocked banner were then shown on B's sheet, and `blocked` decided
  // whether B could go ahead. Each ask is numbered; only the newest one's
  // answer is shown, and it is asked the moment the old run ends.
  property int planSeq: 0
  function askPlan(cmd) {
    win.planSeq++;
    planProc.wantCmd = cmd;
    planProc.wantSeq = win.planSeq;
    win.startPlan();
  }
  function startPlan() {
    if (planProc.running || !planProc.wantCmd) return;
    planProc.seq = planProc.wantSeq;
    planProc.command = planProc.wantCmd;
    planProc.running = true;
  }
  Process {
    id: planProc
    property int seq: -1
    property int wantSeq: -1
    property var wantCmd: null
    onExited: if (planProc.wantSeq !== planProc.seq) Qt.callLater(win.startPlan)
    stdout: StdioCollector {
      id: planOut
      onStreamFinished: {
        if (planProc.seq !== win.planSeq) return;
        win.plan = Cer.readPlan(planOut.text);
        win.planning = false;
      }
    }
  }
  readonly property bool blocked: !!win.plan && (win.plan.removeError !== "" || win.plan.installError !== "")

  // ── some of the updates ─────────────────────────────────────────────────
  // Updating some packages and not others is a PARTIAL UPGRADE, which Arch
  // does not support: a library can move ahead of the programs built against
  // it. It is still offered — it is sometimes exactly what is needed — but it
  // is always confirmed, and the confirm says so. Priced against Ceres' own
  // database, which is where the new versions are.
  property var umarks: ({})
  readonly property int umarkCount: Object.keys(win.umarks).length
  readonly property var pendingNames: Ceres.repo.concat(Ceres.aur).map(u => u.name)
  readonly property bool partial: win.confirmKind === "update"
    && win.installNames.length < win.pendingNames.length

  function toggleUmark(r) {
    if (!r || r.head || r.flatpak) return;
    const m = Object.assign({}, win.umarks);
    if (m[r.u.name]) delete m[r.u.name];
    else m[r.u.name] = r;
    win.umarks = m;
  }

  function confirmUpdates(list) {
    if (list.length === 0) return;
    const t = {};
    for (const r of list)
      t[r.u.name] = { name: r.u.name, version: r.u.to, from: r.u.from, aur: r.aur, installed: true };
    win.confirmKind = "update";
    win.targets = t;
    win.plan = null;
    win.planning = true;
    win.overlay = "confirm";
    win.askPlan(["sh", "-c", Cer.planCommand(
      list.filter(r => !r.aur).map(r => r.u.name), [], Ceres.dbPath)]);
  }
  function confirmUpdate() {
    const marked = Object.keys(win.umarks).map(n => win.umarks[n]);
    if (marked.length) win.confirmUpdates(marked);
    else {
      const r = win.updateRows[win.usel];
      // a Flatpak row is Flatpak's to update, on its own
      if (r && !r.head && r.flatpak) Ceres.updateFlatpak(r.u);
      else if (r && !r.head) win.confirmUpdates([r]);
    }
  }

  // ── undo: a whole transaction taken back ────────────────────────────────
  // ctrl z in History, on any row of a transaction. Planned against what is
  // installed NOW — see Cer.readUndo — so a package a later transaction moved
  // on is skipped and listed, never knocked back over it.
  property var undo: null
  property var undoTx: null

  function undoTransaction(ti) {
    const t = win.history[ti];
    // Flatpak's jobs are not pacman's to take back
    if (!t || t.flatpak || Ceres.txBusy) return;
    win.confirmKind = "undo";
    win.undoTx = t;
    win.undo = null;
    win.targets = ({});
    win.plan = null;
    win.planning = true;
    win.overlay = "confirm";
    undoProc.command = ["sh", "-c", Cer.undoCommand(Paths.cacheDir() + "/paru/clone")];
    undoProc.running = true;
  }
  Process {
    id: undoProc
    stdout: StdioCollector {
      id: undoOut
      onStreamFinished: {
        const p = Cer.readUndo(win.undoTx, undoOut.text);
        if (p.missing.length === 0) { win.planUndo(p); return; }
        undoArchiveProc.pending = p;
        undoArchiveProc.command = ["sh", "-c", Cer.undoArchiveCommand(p.missing)];
        undoArchiveProc.running = true;
      }
    }
  }
  Process {
    id: undoArchiveProc
    property var pending: null
    stdout: StdioCollector {
      id: undoArchiveOut
      onStreamFinished: win.planUndo(Cer.withArchive(undoArchiveProc.pending, undoArchiveOut.text))
    }
  }
  // What is to be removed is asked of pacman first, as any removal is: a
  // package something else now needs cannot go, and the card says so.
  function planUndo(p) {
    win.undo = p;
    if (p.remove.length === 0) { win.planning = false; return; }
    win.askPlan(["sh", "-c", Cer.planCommand([], p.remove.map(r => r.name))]);
  }
  readonly property string undoLabel: win.undoTx
    ? "undo the " + (Cer.describeCommand(win.undoTx.command) || "transaction")
      + " of " + win.dayLabel(win.undoTx.date).toLowerCase() + " " + win.undoTx.time
    : ""

  function go() {
    if (win.planning || win.blocked) return;
    if (win.confirmKind === "undo") {
      if (!win.undo) return;
      const steps = Cer.undoSteps(win.undo);
      if (steps.length === 0) return;
      Ceres.request(steps, win.undoLabel, win.undo.back.length + win.undo.remove.length);
      return;
    }
    if (win.confirmKind === "update") {
      const names = win.installNames;
      // Every name must be a pending update. Anything else means this
      // confirm was set up for something that is not an update, and the
      // one thing it must not do then is fall through to a full upgrade.
      if (names.length === 0 || names.some(n => win.pendingNames.indexOf(n) < 0)) {
        console.warn("ceres: an update confirm holding non-updates was refused: " + names.join(" "));
        return;
      }
      // all of them is not a partial upgrade — it is the full one
      if (!win.partial) { Ceres.request(Cer.upgradeSteps(), "", Ceres.repo.length + Ceres.aur.length); return; }
      Ceres.request([["-Sy", "--needed"].concat(names)],
                    "update " + names.length + " of " + win.pendingNames.length + " \u00b7 partial upgrade",
                    names.length);
      return;
    }
    const steps = Cer.changeSteps(win.installNames, win.removeNames);
    if (steps.length === 0) return;
    const expected = (win.plan ? win.plan.install.length + win.plan.remove.length : 0)
      + win.aurTargets.length;
    Ceres.request(steps, Cer.changeLabel(win.installNames, win.removeNames), expected);
  }

  // ── review: an AUR package's PKGBUILD ───────────────────────────────────
  property int reviewAt: 0
  property var review: null
  function openReview(i) {
    if (win.aurTargets.length === 0) return;
    win.reviewAt = (i + win.aurTargets.length) % win.aurTargets.length;
    win.review = null;
    win.overlay = "review";
    win.fetchReview();
  }
  // THE RECIPE SHOWN IS THE RECIPE FOR THE PACKAGE NAMED ABOVE IT. `paru -Gp`
  // is a network round trip, and ←/→ while it was out was a no-op restart —
  // so the PKGBUILD that arrived was the previous package's, drawn under the
  // new package's header. On the one screen whose whole job is showing you
  // what you are about to build and run, that is the one thing it must never
  // do. Each run carries the package it was for; an answer for any other is
  // dropped, and the one now wanted is fetched when the run ends.
  function fetchReview() {
    const want = win.aurTargets[win.reviewAt];
    if (reviewProc.running) { reviewProc.again = true; return; }
    reviewProc.forName = want;
    reviewProc.command = ["sh", "-c", Cer.reviewCommand(want)];
    reviewProc.running = true;
  }
  Process {
    id: reviewProc
    property var forName: null
    property bool again: false
    onExited: if (reviewProc.again) { reviewProc.again = false; Qt.callLater(win.fetchReview); }
    stdout: StdioCollector {
      id: reviewOut
      onStreamFinished: {
        if (reviewProc.forName !== win.aurTargets[win.reviewAt]) return;
        win.review = Cer.readReview(reviewOut.text);
      }
    }
  }

  // ── History: pacman.log as transactions ────────────────────────────────
  property var history: []
  readonly property string hquery: win.sharedQuery
  property int hsel: 0
  onHqueryChanged: win.hsel = win.firstEvent(win.historyRows)

  function loadHistory() {
    historyProc.command = ["sh", "-c", Cer.historyCommand(600)];
    historyProc.running = true;
  }
  Process {
    id: historyProc
    stdout: StdioCollector {
      id: historyOut
      onStreamFinished: {
        win.history = Cer.readHistory(historyOut.text, Date.now());
        win.hsel = win.firstEvent(win.historyRows);
      }
    }
  }

  // headings and events in one model; typing narrows it to one package
  // A FLATPAK GONE has no name of its own any more (flatpak names only
  // what is installed): the Store's catalog knows it, once it has loaded
  readonly property var fpNames: {
    const m = {};
    for (const a of storeView.apps) {
      if (a.source === "flatpak") m[a.pkg] = a.name;
      for (const o of a.others || []) if (o.source === "flatpak") m[o.pkg] = a.name;
    }
    return m;
  }
  function fpNamed(e) {
    if (!e.flatpak || e.runtime || e.name !== e.id || !win.fpNames[e.id]) return e;
    return Object.assign({}, e, { name: win.fpNames[e.id] });
  }
  readonly property var historyRows: {
    const out = [];
    const q = win.hquery.toLowerCase();
    let lastDay = "";
    for (let ti = 0; ti < win.history.length; ti++) {
      const t = win.history[ti];
      const ev = q.trim() === "" ? t.events : t.events.filter(e => Cer.matchesAll(e.name, q));
      if (ev.length === 0) continue;
      // the runtimes line is not a count of its own: "1 installed", the app
      const tally = Cer.tally(ev.filter(e => !e.runtime)), parts = [];
      for (const v of Cer.VERBS) if (tally[v].length) parts.push(tally[v].length + " " + v);
      // A new day opens a section, terminus' sidebar heading exactly: 13
      // of air and a rule closing the day above (not before the first), 7,
      // the day's name, 7, and the rule under it.
      if (t.date !== lastDay) {
        out.push({ head: true, kind: "day", label: win.dayLabel(t.date), first: lastDay === "" });
        lastDay = t.date;
      }
      out.push({ head: true, kind: "tx", time: t.time, tx: ti,
                 what: Cer.describeCommand(t.command), counts: parts.join(" \u00b7 ") });
      for (const e of ev) out.push({ head: false, e: win.fpNamed(e), tx: ti });
    }
    return out;
  }
  // TODAY, YESTERDAY, then the date — in capitals, as a heading
  function dayLabel(date) {
    const d = new Date(date + "T00:00");
    const today = new Date(); today.setHours(0, 0, 0, 0);
    const days = Math.round((today - d) / 86400000);
    if (days === 0) return "TODAY";
    if (days === 1) return "YESTERDAY";
    return Qt.formatDate(d, days < 300 ? "ddd d MMM" : "ddd d MMM yyyy").toUpperCase();
  }

  function firstEvent(rows) {
    for (let i = 0; i < rows.length; i++) if (!rows[i].head) return i;
    return 0;
  }
  readonly property var hevent: {
    const r = win.historyRows[win.hsel];
    return r && !r.head ? r.e : null;
  }

  // What is in the cache for the selected event's package, and what is
  // installed now — the two things a way back depends on.
  property var cached: []
  property string installedNow: ""
  onHeventChanged: cacheDelay.restart()
  Timer {
    id: cacheDelay
    interval: 120
    onTriggered: {
      const e = win.hevent;
      win.cached = [];
      win.archived = [];
      win.installedNow = "";
      win.lookCache();
    }
  }
  // ONE LOOK AT A TIME, FOR THE ROW YOU ARE ON. Moving through History while
  // a look was out overwrote forName on a running Process — the restart was
  // a no-op — so the old run's output was read as the new package's: an
  // empty list, "nothing of it in the package cache", and no archive lookup
  // ever started for it. An answer for another row is dropped, and the row
  // now under the cursor is looked up when the run ends.
  function lookCache() {
    const e = win.hevent;
    if (!e) return;
    // Flatpak's: no pacman package, no cache, nothing in the archive
    if (e.flatpak) { win.installedNow = ""; win.cached = []; win.archived = []; return; }
    if (cacheProc.running) { cacheProc.again = true; return; }
    cacheProc.forName = e.name;
    cacheProc.command = ["sh", "-c", "pacman -Q -- " + Cer.q(e.name)
      + " 2>/dev/null | cut -d' ' -f2; echo '@@cache'; " + Cer.cachedCommand(e.name)];
    cacheProc.running = true;
  }
  function lookArchive() {
    const e = win.hevent;
    if (!e) return;
    if (archiveProc.running) { archiveProc.again = true; return; }
    archiveProc.forName = e.name;
    archiveProc.command = ["sh", "-c", Cer.archiveCommand(e.name)];
    archiveProc.running = true;
  }
  Process {
    id: cacheProc
    property string forName: ""
    property bool again: false
    onExited: if (cacheProc.again) { cacheProc.again = false; Qt.callLater(win.lookCache); }
    stdout: StdioCollector {
      id: cacheOut
      onStreamFinished: {
        if (!win.hevent || win.hevent.name !== cacheProc.forName) return;
        const parts = cacheOut.text.split("@@cache\n");
        win.installedNow = (parts[0] || "").trim();
        win.cached = Cer.byVersion(Cer.readCached(cacheProc.forName, parts[1] || "")).reverse();
        // and what the Arch archive has beyond it
        win.lookArchive();
      }
    }
  }

  // THE ARCH ARCHIVE: every version ever built, for when the cache has let
  // one go. Newest first, only what the cache does not already hold.
  property var archived: []
  Process {
    id: archiveProc
    property string forName: ""
    property bool again: false
    onExited: if (archiveProc.again) { archiveProc.again = false; Qt.callLater(win.lookArchive); }
    stdout: StdioCollector {
      id: archiveOut
      onStreamFinished: {
        if (!win.hevent || win.hevent.name !== archiveProc.forName) return;
        const have = {};
        for (const c of win.cached) have[c.version] = true;
        win.archived = Cer.readArchive(archiveProc.forName, archiveOut.text)
          .filter(a => !have[a.version]).reverse();
      }
    }
  }

  // ↵ on an event: back to where it came from. An upgrade goes back to the
  // version it replaced; a removal comes back as the version removed — from
  // the cache if it still has it, and otherwise from the archive.
  readonly property var wayBack: {
    const e = win.hevent;
    if (!e || e.flatpak) return null;
    const want = e.verb === "removed" ? e.to : e.from;
    if (!want || want === win.installedNow) return null;
    return win.cached.find(c => c.version === want)
      || win.archived.find(a => a.version === want) || null;
  }

  function installCached(c) {
    if (!c || !win.hevent) return;
    const name = win.hevent.name;
    const verb = win.installedNow === "" ? "reinstall " : "downgrade ";
    if (c.url) {
      // straight from the archive: pacman downloads it and checks the
      // signature as it would any package
      Ceres.request([["@sudo", "pacman", "-U", "--noconfirm", c.url]],
                    verb + name + " to " + c.version + " \u00b7 from the Arch archive", 1);
      return;
    }
    Ceres.request([["-U", c.file]], verb + name + " to " + c.version, 1);
  }

  // one version, from the cache or the archive — what History's way back is
  // chosen from
  component VersionRow: Rectangle {
    id: vrow
    property var v: null
    readonly property bool current: !!vrow.v && vrow.v.version === win.installedNow
    readonly property bool back: !!win.wayBack && !!vrow.v
      && (win.wayBack.file || win.wayBack.url) === (vrow.v.file || vrow.v.url)
    width: 300
    height: 30
    radius: Zenon.windowRadius
    color: "transparent"
    border.width: 1
    border.color: vrow.back ? Zenon.yellow : Zenon.border
    Text {
      anchors.left: parent.left
      anchors.leftMargin: 12
      anchors.verticalCenter: parent.verticalCenter
      text: vrow.v ? vrow.v.version : ""
      color: vrow.current ? Zenon.accentMuted : Zenon.white
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(16)
    }
    Text {
      anchors.right: parent.right
      anchors.rightMargin: 12
      anchors.verticalCenter: parent.verticalCenter
      text: vrow.current ? "installed" : vrow.back ? "\u21b5 go back"
        : (vrow.v && vrow.v.url ? "download" : "install")
      color: vrow.current ? Zenon.accentMuted : vrow.back ? Zenon.yellow : Zenon.accentKey
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(14)
    }
    TapHandler { enabled: !vrow.current; onTapped: win.installCached(vrow.v) }
  }

  // Scrolls a Flickable just enough to show the span [top, top + h) — a
  // sidebar following its selection.
  function keepInView(f, top, h) {
    if (top < f.contentY) f.contentY = Math.max(0, top - 8);
    else if (top + h > f.contentY + f.height)
      f.contentY = Math.min(Math.max(0, f.contentHeight - f.height), top + h + 8 - f.height);
  }

  // ── Maintenance ────────────────────────────────────────────────────────
  property var maint: null
  property int msel: 0
  property int pnsel: 0
  property var pnDiff: []
  // Flatpak's item, when Flatpak is here (user, 2026-10-14)
  readonly property var maintItems: [
    { key: "orphans", title: "Orphaned packages" },
    { key: "pacnew", title: "Configuration files" },
    { key: "cache", title: "Package cache" },
    { key: "clones", title: "AUR build clones" },
    { key: "sync", title: "Package databases" },
    { key: "mirrors", title: "Mirrors" },
    { key: "oldcode", title: "Running old code" },
    { key: "aurhealth", title: "AUR health" }
  ].concat(Ceres.deps.flatpak ? [{ key: "flatpak", title: "Flatpak" }] : [])
  // how many things want doing, for the tab's label
  readonly property int maintCount: !win.maint ? 0
    : (win.maint.orphans.length ? 1 : 0) + (win.maint.pacnew.length ? 1 : 0)
      + (win.maint.stale ? 1 : 0)

  // REPAIR'S DRY RUN, in the background when Flatpak's item is shown — it
  // checksums every installed file, seconds of work, so not on every load.
  // null: not yet known (the button says it is checking).
  property var fpRepair: null
  function checkFlatpakRepair() {
    if (fpRepairProc.running || !Ceres.deps.flatpak) return;
    fpRepairProc.running = true;
  }
  Process {
    id: fpRepairProc
    command: ["sh", "-c", Cer.flatpakRepairCommand()]
    stdout: StdioCollector { id: fpRepairOut; onStreamFinished: win.fpRepair = Cer.readFlatpakRepair(fpRepairOut.text) }
  }
  function loadMaint() {
    maintProc.command = ["sh", "-c", Cer.maintCommand(Paths.cacheDir() + "/paru/clone")];
    maintProc.running = true;
  }
  Process {
    id: maintProc
    stdout: StdioCollector {
      id: maintOut
      onStreamFinished: {
        win.maint = Cer.readMaint(maintOut.text);
        win.pnsel = 0;
        win.loadPacnewDiff();
      }
    }
  }

  function maintSummary(key) {
    const m = win.maint;
    if (!m) return "\u2026";
    switch (key) {
    case "orphans": return m.orphans.length === 0 ? "none"
      : m.orphans.length + (m.orphans.length === 1 ? " package \u00b7 " : " packages \u00b7 ")
        + Cer.bytes(m.orphans.reduce((t, o) => t + o.size, 0));
    case "pacnew": return m.pacnew.length === 0 ? "nothing pending" : m.pacnew.length + " to merge";
    case "cache": return m.cacheCount + " files \u00b7 " + Cer.bytes(m.cacheBytes)
      + (m.stale ? " \u00b7 " + m.stale + (m.stale === 1 ? " stale download" : " stale downloads") : "");
    case "clones": return m.clones.length === 0 ? "none"
      : m.clones.length + " \u00b7 " + Cer.bytes(m.clones.reduce((t, c) => t + c.size, 0));
    case "aurhealth": {
      const h = Ceres.aurHealth;
      if (!h.ok) return "not checked yet";
      if (h.checked === 0) return "no AUR packages";
      return h.problems.length === 0
        ? h.checked + (h.checked === 1 ? " package \u00b7 all well" : " packages \u00b7 all well")
        : h.problems.length + " of " + h.checked + " need a look";
    }
    case "oldcode": {
      const a = Ceres.staleApps.length, v = Ceres.staleServices.length;
      if (a + v === 0) return "nothing";
      return [a ? a + (a === 1 ? " app" : " apps") : "", v ? v + (v === 1 ? " service" : " services") : ""]
        .filter(x => x).join(" \u00b7 ");
    }
    // No line here: its health is the body's, which has room for it.
    case "mirrors": return "";
    case "flatpak": return m.fpApps.length + (m.fpApps.length === 1 ? " app \u00b7 " : " apps \u00b7 ")
      + m.fpRuntimes.length + (m.fpRuntimes.length === 1 ? " runtime" : " runtimes")
      + (m.fpUnused.length ? " \u00b7 " + m.fpUnused.length + " unused" : "")
      + (win.fpRepair && win.fpRepair.problems.length ? " \u00b7 needs repair" : "");
    case "sync": return (m.synced ? "synced " + Cer.age(Date.now() - m.synced) : "never synced")
      + (m.aurList ? " \u00b7 AUR list " + Cer.age(Date.now() - m.aurList).replace(" ago", " old") : "");
    }
    return "";
  }
  // Running old code, as list rows: apps, then session services, each with
  // the replaced files it still holds (just their names).
  readonly property var oldCodeRows: {
    const out = [];
    const row = (g) => ({ name: g.name + (g.pids.length > 1 ? "  \u00d7" + g.pids.length : ""),
                          version: g.service ? g.unit : "",
                          right: g.files.map(f => f.replace(/^.*\//, "")).join(", ") });
    if (Ceres.staleApps.length) {
      out.push({ head: true, name: "Apps" });
      for (const g of Ceres.staleApps) out.push(row(g));
    }
    if (Ceres.staleServices.length) {
      out.push({ head: true, name: "Session services" });
      for (const g of Ceres.staleServices) out.push(row(g));
    }
    return out;
  }

  // Worth a look: the first server — the one pacman actually uses — is
  // behind or silent, a quarter of the list is behind, or the list is
  // older than three months.
  // What the pane lists: the ranking once there is one — each with its rate
  // and round trip — and otherwise the list you have, in pacman's order.
  readonly property var mirrorRows: {
    if (win.ranking) return [{ head: true, name: win.rankPinged < win.rankTotal
      ? "Timing " + win.rankPinged + " of " + win.rankTotal + " mirrors from here\u2026"
      : "Rating the quickest 12 on a real download \u2014 " + win.rankRated + " of 12\u2026" }];
    if (win.ranked) {
      const r = win.ranked;
      return [{ head: true, name: "The fastest " + r.ranked.length + " of " + r.answered + " that answered" }]
        .concat(r.ranked.map(x => ({ name: x.host,
          version: win.mirrors && win.mirrors.status[x.base] ? win.mirrors.status[x.base].country_code : "",
          dot: "ok",
          right: (x.rate / 1e6).toFixed(1) + " MB/s \u00b7 " + x.ms + "ms" })));
    }
    const h = win.mirrors;
    if (!h) return [];
    // Each server's health as a dot — green in sync, yellow a few hours
    // behind, red behind or not syncing, gray unknown to Arch — and only its
    // age beside it: a column of "synced 1h ago" said "synced" a hundred times.
    return [{ head: true, name: "Your list, in the order pacman tries it" }].concat(h.servers.map((v, i) => {
      const s = v.status;
      const lag = s && s.last_sync ? Date.now() - Date.parse(s.last_sync) : -1;
      return {
        name: v.host, version: v.country,
        dot: !h.statusOk ? "" : !s ? "" : Cer.mirrorBehind(s) ? "bad" : lag > 3 * 3600000 ? "warn" : "ok",
        right: !h.statusOk ? "" : !s ? "not in Arch's list"
          : lag < 0 ? "not syncing"
          : (Cer.mirrorBehind(s) ? "behind \u00b7 " : "") + Cer.age(lag)
      };
    }));
  }
  readonly property bool mirrorsWant: {
    const h = win.mirrors;
    if (!h || !h.servers.length) return false;
    const first = h.servers[0].status;
    return (h.statusOk && Cer.mirrorBehind(first)) || h.firstMs < 0
      || h.behind * 4 >= h.servers.length
      || Date.now() - h.modified > 90 * 86400000;
  }
  function maintWants(key) {
    const m = win.maint;
    if (!m) return false;
    return (key === "orphans" && m.orphans.length > 0) || (key === "pacnew" && m.pacnew.length > 0)
      || (key === "cache" && m.stale > 0) || (key === "oldcode" && Ceres.oldCode.length > 0)
      || (key === "aurhealth" && Ceres.aurHealth.problems.length > 0)
      || (key === "mirrors" && win.mirrorsWant)
      // Flatpak's leftovers are the system's hygiene too
      || (key === "flatpak" && (m.fpUnused.length > 0 || (!!win.fpRepair && win.fpRepair.problems.length > 0)));
  }

  // How an item stands, for its dot: "bad" when something is broken or
  // about to be (an AUR package gone, the first mirror behind or silent),
  // "warn" when there is something to do, "ok", or "" while not yet known.
  function maintLevel(key) {
    if (key === "aurhealth") {
      const h = Ceres.aurHealth;
      if (!h.ok) return "";
      return h.problems.some(p => p.gone) ? "bad" : h.problems.length ? "warn" : "ok";
    }
    if (key === "oldcode") return Ceres.oldCode.length ? "warn" : "ok";
    if (key === "mirrors") {
      const h = win.mirrors;
      if (!h) return "";
      if (h.servers.length && (h.firstMs < 0 || (h.statusOk && Cer.mirrorBehind(h.servers[0].status))))
        return "bad";
      return win.mirrorsWant ? "warn" : "ok";
    }
    if (!win.maint) return "";
    return win.maintWants(key) ? "warn" : "ok";
  }
  function levelInk(level) {
    return level === "bad" ? Zenon.red : level === "warn" ? Zenon.yellow
      : level === "ok" ? Zenon.green : Zenon.dimInk;
  }

  function loadPacnewDiff() {
    win.pnDiff = [];
    if (!win.maint || win.maint.pacnew.length === 0) return;
    pnProc.command = ["sh", "-c", Cer.pacnewDiffCommand(win.maint.pacnew[win.pnsel])];
    pnProc.running = true;
  }
  Process {
    id: pnProc
    stdout: StdioCollector {
      id: pnOut
      onStreamFinished: win.pnDiff = Cer.readReview(pnOut.text).lines
    }
  }

  // The merge needs an editor and a terminal — pacdiff -s asks sudo only
  // for the files it writes. The first diff viewer that is actually
  // installed, ZENU's list; a DIFFPROG you set yourself wins.
  function mergePacnew() {
    Quickshell.execDetached(["xdg-terminal-exec", "--title=Ceres", "--", "sh", "-c",
      "if [ -z \"$DIFFPROG\" ]; then for d in 'nvim -d' 'vim -d' vimdiff meld kdiff3; do "
      + "command -v ${d%% *} >/dev/null 2>&1 && DIFFPROG=$d && break; done; fi; "
      + "export DIFFPROG; pacdiff -s; printf '\\nPress RETURN to close.'; read _"]);
  }

  // ── the mirrors ─────────────────────────────────────────────────────────
  // Asked when the item is first chosen, not with the rest of Maintenance:
  // it reads Arch's status feed and times a server, which is the network,
  // and Maintenance is opened far more often than this is looked at.
  property var mirrors: null
  property bool mirrorsLoading: false
  // what an item looks up only when it is looked at: the mirrors' status,
  // Flatpak's repair dry run
  onMselChanged: {
    const it = win.maintItems[win.msel];
    if (!it) return;
    if (it.key === "mirrors" && !win.mirrors) win.loadMirrors();
    if (it.key === "flatpak" && !win.fpRepair) win.checkFlatpakRepair();
  }
  function loadMirrors() {
    if (mirrorProc.running) return;
    win.mirrorsLoading = true;
    mirrorProc.command = ["sh", "-c", Cer.mirrorHealthCommand()];
    mirrorProc.running = true;
  }
  Process {
    id: mirrorProc
    stdout: StdioCollector {
      id: mirrorOut
      onStreamFinished: { win.mirrors = Cer.readMirrorHealth(mirrorOut.text); win.mirrorsLoading = false; }
    }
  }

  // Ranking, streamed: one line per mirror as it answers, so the pane can
  // count them in. Then the quickest twelve are rated one at a time.
  property bool ranking: false
  property int rankTotal: 0
  property int rankPinged: 0
  property int rankRated: 0
  property var rankLines: []
  property var ranked: null
  function rankMirrors() {
    if (!win.mirrors || !win.mirrors.statusOk || win.ranking) return;
    const c = Cer.mirrorCandidates(win.mirrors.status);
    if (c.length === 0) return;
    win.ranked = null;
    win.rankLines = [];
    win.rankTotal = c.length;
    win.rankPinged = 0;
    win.rankRated = 0;
    win.ranking = true;
    rankProc.command = ["sh", "-c", Cer.rankCommand(c, 12)];
    rankProc.running = true;
  }
  Process {
    id: rankProc
    stdout: SplitParser {
      onRead: (line) => {
        win.rankLines.push(line);
        if (line.indexOf("ping ") === 0) win.rankPinged++;
        else if (line.indexOf("rate ") === 0) win.rankRated++;
      }
    }
    onExited: {
      win.ranked = Cer.readRank(win.rankLines.join("\n"), 10);
      win.rankLines = [];
      win.ranking = false;
    }
  }

  // The new list is written as you, then put in place as root — the old one
  // kept beside it as .ceres-bak — through the one password path.
  readonly property string mirrorDraft: Paths.cacheDir() + "/ceres/mirrorlist.new"
  function useRanked() {
    if (!win.ranked || win.ranked.ranked.length === 0) return;
    draftProc.command = ["sh", "-c", "mkdir -p " + Cer.q(Paths.cacheDir() + "/ceres") + " && printf '%s' "
      + Cer.q(Cer.mirrorlistText(win.ranked.ranked, Qt.formatDate(new Date(), "yyyy-MM-dd")))
      + " > " + Cer.q(win.mirrorDraft)];
    draftProc.running = true;
  }
  property bool mirrorsAfter: false
  Process {
    id: draftProc
    onExited: (code) => {
      if (code !== 0) return;
      // installed beside the mirrorlist and renamed over it, so there is no
      // moment where the file is half written — see ConfigView.save
      win.mirrorsAfter = Ceres.request(
        [["@sudo", "cp", "-p", Cer.MIRRORLIST, Cer.MIRRORLIST + ".ceres-bak"],
         ["@sudo", "install", "-m", "644", win.mirrorDraft, Cer.MIRRORLIST + ".ceres-new"],
         ["@sudo", "mv", "-f", Cer.MIRRORLIST + ".ceres-new", Cer.MIRRORLIST]],
        "use the " + win.ranked.ranked.length + " fastest mirrors from here", 0);
    }
  }

  // the primary action of the selected item, what ↵ does
  function maintGo(which) {
    const m = win.maint;
    const key = win.maintItems[win.msel].key;
    if (!m) return;
    if (key === "orphans" && m.orphans.length) {
      // THROUGH confirmFor, which is the one place a change is set up. Doing
      // it by hand here skipped `confirmKind`, so after a visit to Updates the
      // orphans were confirmed as UPDATES — and "go ahead" on an update of
      // everything-that-is-pending ran a full upgrade instead of a removal.
      const t = {};
      for (const o of m.orphans) t[o.name] = o;
      win.confirmFor(t);
    } else if (key === "pacnew" && m.pacnew.length) win.mergePacnew();
    else if (key === "cache") {
      if (which === "stale")
        // Not while pacman holds its lock: a download-* directory is where a
        // download IN PROGRESS lives, and it is only stale once nothing is
        // running. Refused rather than raced.
        Ceres.request([["@sudo", "sh", "-c",
                        "if [ -e /var/lib/pacman/db.lck ]; then echo 'error: pacman is running \u2014 try again when it has finished'; exit 1; fi; "
                        + "find /var/cache/pacman/pkg -maxdepth 1 -type d -name 'download-*' -exec rm -rf {} +"]],
                      "clear " + m.stale + (m.stale === 1 ? " stale download" : " stale downloads"), 0);
      else if (which === "uninstalled")
        Ceres.request([["@sudo", "paccache", "-ruk0"]], "drop cached files of uninstalled packages", 0);
      else
        Ceres.request([["@sudo", "paccache", "-rk" + win.keepVersions]],
                      "keep " + win.keepVersions + " versions of each package", 0);
    } else if (key === "clones") win.dropClones(which === "all");
    else if (key === "flatpak") {
      // the system's as root, yours without — each a no-op when there is
      // nothing to do
      // each only where its dry run found something: a clean installation
      // is not asked for a password to do nothing
      if (which === "repair") {
        const where = win.fpRepair ? win.fpRepair.problems.map(p => p.scope) : [];
        const steps = [];
        if (where.indexOf("system") >= 0) steps.push(["@sudo", "flatpak", "repair", "--system"]);
        if (where.indexOf("user") >= 0) steps.push(["@user", "flatpak repair --user"]);
        if (steps.length) { win.fpRepair = null; Ceres.request(steps, "repair Flatpak", 0); }
      } else {
        const steps = Cer.flatpakUnusedSteps(m.fpUnused);
        if (steps.length) Ceres.request(steps, "remove unused runtimes", 0);
      }
    }
    else if (key === "mirrors") {
      if (which === "rank" || !win.ranked) win.rankMirrors();
      else win.useRanked();
    }
    else if (key === "sync") {
      // the system's databases, then our AUR list; then a fresh look for
      // updates, since a sync is exactly when there may be new ones
      win.checkAfter = true;
      Ceres.request([["@sudo", "pacman", "-Sy"], ["@user", Cer.q(win.script) + " aur"]],
                    "sync package databases", 0);
    }
  }
  readonly property int keepVersions: 2
  property bool checkAfter: false

  // Clones are yours, not root's: no password, no transaction. paru clones
  // again the next time it needs one.
  function dropClones(all) {
    const m = win.maint;
    if (!m) return;
    const gone = m.clones.filter(c => all || !c.installed).map(c => c.name);
    if (gone.length === 0) return;
    cloneProc.command = ["rm", "-rf", "--"].concat(gone.map(n => Paths.cacheDir() + "/paru/clone/" + n));
    cloneProc.running = true;
  }
  Process {
    id: cloneProc
    onExited: win.loadMaint()
  }

  // The review said yes: the file goes in as root, and a fresh look for
  // updates follows, since repositories may have come or gone.
  function saveConf() {
    if (!configView.review || !configView.review.ok) return;
    win.checkAfter = true;
    configView.save();
  }

  // ── the transaction ─────────────────────────────────────────────────────
  Connections {
    target: Ceres
    function onSetupRequested() { win.showSetup = true; }
    function onAuthRequested() {
      if (!win.visible) return;
      Ceres.txClear();
      field.pw = "";
      field.failed = false;
      win.asking = true;
      keys.forceActiveFocus();
    }
    function onTxStateChanged() {
      if (Ceres.txState === "authfail") field.failed = true;
      if (Ceres.txState === "running") win.asking = false;
      // A change that went through leaves the list it was made from out of
      // date — what was available is installed, what was installed is gone.
      if (Ceres.txState === "done" || Ceres.txState === "failed") configView.jobDone(Ceres.txState === "done");
      if (Ceres.txState === "failed") win.checkAfter = false;
      if (Ceres.txState === "done") {
        if (win.checkAfter) { win.checkAfter = false; Ceres.check(); }
        if (win.mirrorsAfter) { win.mirrorsAfter = false; win.ranked = null; win.loadMirrors(); }
        win.showSetup = false;
        win.marks = ({});
        win.umarks = ({});
        win.overlay = "";
        win.search();
        win.infoFor = "";
        win.peek();
        win.loadHistory();
        win.loadMaint();
        storeView.refresh();
        cacheDelay.restart();
      }
    }
  }

  function back() {
    if (win.authUp) { win.cancelAuth(); return true; }
    // A job still running has nothing to step back to: Esc leaves it be
    // (shift+Esc cancels it). A finished one is put away.
    if (win.face === "tx") {
      if (Ceres.txBusy) return false;
      Ceres.txClear();
      return true;
    }
    if (win.face === "review") { win.overlay = "confirm"; return true; }
    if (win.face === "confirm") { win.overlay = ""; return true; }
    if (win.face === "conf") { win.overlay = ""; return true; }
    if (win.face === "fpoff" || win.face === "fpget") { win.overlay = ""; return true; }
    // off an app's page, back to the shelf or the results it was opened from
    if (win.tab === "store" && storeView.back()) return true;
    // Out of the field, then the text, then the marks, then the window — the
    // cheapest thing to redo goes first. Esc with nothing to step out of does
    // nothing: it never closes the window (user, 2026-10-15).
    const marked = (win.tab === "packages" && win.markCount > 0)
      || (win.tab === "updates" && win.umarkCount > 0);
    if (win.typing) {
      win.typing = false;
      if (win.filterText !== "" || marked) return true;
    }
    if (win.filterText !== "") { win.setFilter(""); return true; }
    if (win.tab === "packages" && win.markCount > 0) { win.marks = ({}); return true; }
    if (win.tab === "updates" && win.umarkCount > 0) { win.umarks = ({}); return true; }
    return false;
  }

  function move(d) {
    if (win.tab === "history") {
      let i = win.hsel;
      do { i += d; } while (i >= 0 && i < win.historyRows.length && win.historyRows[i].head);
      if (i >= 0 && i < win.historyRows.length) win.hsel = i;
      histList.positionViewAtIndex(win.hsel, ListView.Contain);
      return;
    }
    if (win.tab === "maintenance") {
      win.msel = Math.max(0, Math.min(win.maintItems.length - 1, win.msel + d));
      return;
    }
    if (win.tab === "settings") {
      configView.gsel = Math.max(0, Math.min(configView.groups.length - 1, configView.gsel + (d > 0 ? 1 : -1)));
      return;
    }
    if (win.tab === "packages") {
      if (win.rows.length === 0) return;
      win.sel = Math.max(0, Math.min(win.rows.length - 1, win.sel + d));
      pkgList.positionViewAtIndex(win.sel, ListView.Contain);
    } else {
      let i = win.usel;
      do { i += d; } while (i >= 0 && i < win.updateRows.length && win.updateRows[i].head);
      if (i >= 0 && i < win.updateRows.length) win.usel = i;
      updList.positionViewAtIndex(win.usel, ListView.Contain);
    }
  }

  // ── keys ────────────────────────────────────────────────────────────────
  Item {
    id: keys
    focus: true
    Keys.onReleased: (event) => {
      if (win.authUp) event.accepted = field.keyUp(event);
    }
    Keys.onPressed: (event) => {
      const k = event.key, ctrl = event.modifiers & Qt.ControlModifier;
      // SHIFT+ESC STOPS A RUNNING JOB, from wherever you are in the window —
      // plain escape still only hides it. See Ceres.cancel.
      if (k === Qt.Key_Escape && (event.modifiers & Qt.ShiftModifier) && Ceres.txBusy) {
        event.accepted = true;
        Ceres.cancel();
        return;
      }
      // ctrl+c over a job's log copies what is selected in it
      if (ctrl && k === Qt.Key_C && win.face === "tx"
          && txView.copy()) {
        event.accepted = true;
        return;
      }
      // the sheet takes every key while it is up
      if (win.authUp) { event.accepted = field.key(event); return; }
      if (win.settleUp) {
        event.accepted = true;
        if ((k === Qt.Key_Y || k === Qt.Key_Return || k === Qt.Key_Enter) && txView.settleable) txView.settle();
        else if (k === Qt.Key_T) Ceres.txInTerminal();
        else if (k === Qt.Key_Escape) win.settleAside = true;
        else if (k === Qt.Key_Left || k === Qt.Key_Right) txView.pickNext(k === Qt.Key_Left ? -1 : 1);
        return;
      }
      if (win.msgUp) {
        event.accepted = true;
        // ESC NEVER CLOSES CERES (user, 2026-10-15): it steps out of things;
        // the window closes as any window does
        if (Ceres.txBusy) return;
        if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Escape) Ceres.txClear();
        else if (k === Qt.Key_T && Ceres.txState === "failed") Ceres.txInTerminal();
        return;
      }
      if (win.face === "setup") {
        event.accepted = true;
        if (k === Qt.Key_Return || k === Qt.Key_Enter) Ceres.setup(setupView.choice, setupView.flatpak);
        else if ((k === Qt.Key_Left || k === Qt.Key_Right) && Ceres.deps.paru)
          setupView.choice = setupView.choice === "paru" ? "paru-git" : "paru";
        // the Flatpak box: space ticks it, as space marks a row
        else if (k === Qt.Key_Space && Ceres.flatpakAsk) setupView.flatpak = !setupView.flatpak;
        else if (k === Qt.Key_Escape && !Ceres.deps.paru) win.showSetup = false;
        return;
      }
      if (win.face === "news") {
        event.accepted = true;
        if (k === Qt.Key_Return || k === Qt.Key_Enter) Ceres.passNews();
        else if (k === Qt.Key_Escape) Ceres.holdBack();
        return;
      }
      if (k === Qt.Key_Escape) {
        event.accepted = true;
        win.back();
        return;
      }
      if (win.face === "tx") {
        if (Ceres.txBusy) return;
        if (k === Qt.Key_Return || k === Qt.Key_Enter) { event.accepted = true; Ceres.txClear(); }
        else if (k === Qt.Key_T && Ceres.txState === "failed") { event.accepted = true; Ceres.txInTerminal(); }
        // paru's unasked question, answered here — see TxView.settle
        else if (k === Qt.Key_Y && txView.settleable) { event.accepted = true; txView.settle(); }
        else if ((k === Qt.Key_Left || k === Qt.Key_Right) && txView.settling) {
          event.accepted = true;
          txView.pickNext(k === Qt.Key_Left ? -1 : 1);
        }
        return;
      }
      if (win.face === "review") {
        event.accepted = true;
        if (k === Qt.Key_Left || k === Qt.Key_H) win.openReview(win.reviewAt - 1);
        else if (k === Qt.Key_Right || k === Qt.Key_L) win.openReview(win.reviewAt + 1);
        else if (k === Qt.Key_J || k === Qt.Key_Down) reviewList.flick(0, -900);
        else if (k === Qt.Key_K || k === Qt.Key_Up) reviewList.flick(0, 900);
        return;
      }
      if (win.face === "fpget") {
        event.accepted = true;
        if (k === Qt.Key_Return || k === Qt.Key_Enter) win.goFlatpak();
        else if (!win.fpRemove && (k === Qt.Key_Left || k === Qt.Key_Right))
          win.fpScope = win.fpScope === "system" ? "user" : "system";
        return;
      }
      if (win.face === "fpoff") {
        event.accepted = true;
        if (k === Qt.Key_Return || k === Qt.Key_Enter) win.removeFlatpak();
        return;
      }
      if (win.face === "conf") {
        event.accepted = true;
        if (k === Qt.Key_Return || k === Qt.Key_Enter) win.saveConf();
        return;
      }
      if (win.face === "confirm") {
        event.accepted = true;
        if (k === Qt.Key_Return || k === Qt.Key_Enter) win.go();
        else if (k === Qt.Key_R) win.openReview(0);
        return;
      }
      // ── browsing ──
      if (ctrl && (k === Qt.Key_Tab || k === Qt.Key_Backtab)) {
        event.accepted = true;
        win.cycleTab(k === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier) ? -1 : 1);
        return;
      }
      if (ctrl && k >= Qt.Key_1 && k <= Qt.Key_6) {
        event.accepted = true;
        win.showTab(win.tabs[k - Qt.Key_1][0]);
        return;
      }
      // the Store walks a grid, not a list: its arrows are its own
      if (win.tab === "store") {
        if (!win.typing && !ctrl && !(event.modifiers & Qt.AltModifier) && event.text
            && /^[A-Za-z0-9]$/.test(event.text)) win.typing = true;
        event.accepted = storeView.key(event) || win.filterKey(event);
        return;
      }
      // shift+↑↓ marks as it goes, from where it started — shift+click's
      // range, by keys
      if ((event.modifiers & Qt.ShiftModifier) && (k === Qt.Key_Down || k === Qt.Key_Up)
          && (win.tab === "packages" || win.tab === "updates")) {
        event.accepted = true;
        const pk = win.tab === "packages";
        if ((pk ? win.anchor : win.uanchor) < 0) {
          if (pk) win.anchor = win.sel; else win.uanchor = win.usel;
        }
        win.move(k === Qt.Key_Down ? 1 : -1);
        if (pk) win.markRange(win.anchor >= 0 ? win.anchor : win.sel, win.sel);
        else win.markUpdateRange(win.uanchor >= 0 ? win.uanchor : win.usel, win.usel);
        return;
      }
      // a plain move drops the range's start: the next shift+↑↓ starts here
      if (k === Qt.Key_Down || k === Qt.Key_Up || k === Qt.Key_PageDown || k === Qt.Key_PageUp) { win.anchor = -1; win.uanchor = -1; }
      if (k === Qt.Key_Down || (ctrl && k === Qt.Key_J)) { event.accepted = true; win.move(1); return; }
      if (k === Qt.Key_Up || (ctrl && k === Qt.Key_K)) { event.accepted = true; win.move(-1); return; }
      if (k === Qt.Key_PageDown) { event.accepted = true; win.move(12); return; }
      if (k === Qt.Key_PageUp) { event.accepted = true; win.move(-12); return; }
      if (win.tab === "settings") {
        event.accepted = configView.key(event);
        return;
      }
      if (win.tab === "history") {
        event.accepted = true;
        if (k === Qt.Key_Return || k === Qt.Key_Enter) win.installCached(win.wayBack);
        else if (ctrl && k === Qt.Key_Z) {
          const r = win.historyRows[win.hsel];
          if (r && r.tx !== undefined) win.undoTransaction(r.tx);
        }
        else if (!win.typing && k === Qt.Key_J) win.move(1);
        else if (!win.typing && k === Qt.Key_K) win.move(-1);
        else event.accepted = win.filterKey(event);
        return;
      }
      if (win.tab === "maintenance") {
        event.accepted = true;
        if (k === Qt.Key_J) win.move(1);
        else if (k === Qt.Key_K) win.move(-1);
        else if (k === Qt.Key_Return || k === Qt.Key_Enter) win.maintGo("");
        else if (k === Qt.Key_R) {
          win.loadMaint(); Ceres.checkStale(); Ceres.checkAurHealth(true);
          if (win.maintItems[win.msel].key === "mirrors") { win.ranked = null; win.loadMirrors(); }
        }
        else event.accepted = false;
        return;
      }
      if (win.tab === "updates") {
        if (ctrl && k === Qt.Key_R) { event.accepted = true; Ceres.check(); }
        else if (k === Qt.Key_Tab || k === Qt.Key_Space) {
          event.accepted = true;
          win.toggleUmark(win.updateRows[win.usel]);
          win.move(1);
        }
        else if (k === Qt.Key_J || k === Qt.Key_K) { event.accepted = true; win.move(k === Qt.Key_J ? 1 : -1); }
        else if (ctrl && k === Qt.Key_D) { event.accepted = true; win.umarks = ({}); }
        else if (ctrl && k === Qt.Key_A) { event.accepted = true; win.markAllUpdates(); }
        else if ((k === Qt.Key_Return || k === Qt.Key_Enter) && Ceres.total > 0) {
          event.accepted = true;
          if (ctrl) Ceres.updateAll();
          else win.confirmUpdate();
        }
        else event.accepted = false;
        return;
      }
      // packages: typing is searching
      event.accepted = true;
      if (k === Qt.Key_Return || k === Qt.Key_Enter) win.confirm();
      // In the field, SHIFT+space marks: plain space belongs to the filter,
      // which takes several words — and a mark on space landed on the first
      // row of a list the filter was still narrowing. Out of it, space is a
      // mark again; tab is one either way.
      else if (k === Qt.Key_Tab || (k === Qt.Key_Space && (!win.typing || (event.modifiers & Qt.ShiftModifier)))) {
        win.toggleMark(win.rows[win.sel]); win.move(1);
      }
      else if (!win.typing && k === Qt.Key_J) win.move(1);
      else if (!win.typing && k === Qt.Key_K) win.move(-1);
      else if (ctrl && k === Qt.Key_S) win.installedOnly = !win.installedOnly;
      else if (ctrl && k === Qt.Key_D) win.marks = ({});
      else if (ctrl && k === Qt.Key_A) win.markAll();
      else event.accepted = win.filterKey(event);
    }
  }

  function verbGlyph(v) {
    return ({ upgraded: "\uF062", installed: "\uF067", removed: "\uF068",
              downgraded: "\uF063", reinstalled: "\uF01E" })[v] || "";
  }
  function verbInk(v) {
    return ({ upgraded: Zenon.blue, installed: Zenon.green, removed: Zenon.red,
              downgraded: Zenon.yellow, reinstalled: Zenon.cyan })[v] || Zenon.accentKey;
  }

  // ── pieces ──────────────────────────────────────────────────────────────
  function repoInk(repo) {
    if (/-testing$/.test(repo)) return Zenon.red;
    return ({ core: Zenon.cyan, extra: Zenon.green, multilib: Zenon.yellow,
              aur: Zenon.magenta, local: Zenon.white })[repo] || Zenon.accentKey;
  }

  component Rule: Rectangle {
    height: 1
    color: Zenon.border
  }





  // ── THE STAGE: everything a sheet covers ────────────────────────────────
  // The head, the notes and the body, as one item, so a sheet can soften all
  // of it at once — terminus' rule, content recedes while it is being asked
  // about. The key strip below is not in here: it describes the sheet, and
  // stays sharp. A layer only while a sheet is up; otherwise the stage would
  // go through an offscreen texture for the whole session.
  Item {
    id: stage
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: foot.top
    // NO BLUR UNDER A SHEET (user, 2026-10-14): the page stays sharp round
    // the card, as terminus' does; the card frosts what it covers itself
    // (Sheet.backdrop: stage)

    // ── ROWS GO UNDER THE HEAD ──────────────────────────────────────────────
    // Whichever lists are showing carry their scrolled-off rows on under the
    // head (and the notes, when they are up), frosted — see
    // morpheus/ScrollEdge. Before the head so it draws over them; `follow`
    // finds each view however deep in its page it sits.
    //
    // ONLY VIEWS WHOSE TOP IS THE CHROME'S. Maintenance's list and its
    // .pacnew diff stand under the page's own title, blurb, buttons and
    // facts: the stretch between them and the head is not a gap the rows
    // carry on through, it is that summary — and the rows were painted
    // over it, scrolling up across the description to the tabs.
    Repeater {
      model: [histList, hdetail, maintSide, pkgList, updList, infoPane].concat(storeView.edgeViews)
      delegate: ScrollEdge {
        required property var modelData
        view: modelData
        follow: true
        // TERMINUS' GLASS (user, 2026-10-17): its strip frosts the rows
        // whole — no fade, the card's 64 kernel, a 0.6 veil (stripFrost,
        // glassVeil). Same numbers here, through the same ScrollEdge.
        fade: false
        strength: 1
        blurMax: win.frostBlur
        scrim: win.frostVeil
        // the notes strip, when it is up, is the chrome's lowest bar. Over
        // Packages there is no bar to name: the rows frost from the column
        // headings' hairline all the way up through the head, one material,
        // rather than stopping at the headings (a bar's gap is drawn sharp)
        bar: modelData === pkgList ? null : notes.visible ? notes : head
        visible: modelData.visible
      }
    }
    // and up out of the foot: the same views, turned over, from each one's
    // bottom edge down through the foot (declared after the stage, so it
    // draws over them)
    Repeater {
      model: [histList, hdetail, maintSide, mdList, pnView, pkgList, updList, infoPane, configView.pageFlick]
        .concat(storeView.edgeViews)
      delegate: ScrollEdge {
        required property var modelData
        view: modelData
        below: true
        follow: true
        fade: false
        strength: 1
        blurMax: win.frostBlur
        scrim: win.frostVeil
        bar: foot
        // the .pacnew list stops short, over its diff — the same summary
        // rule as above, turned over: what follows it is not a gap
        // — and the mirrors' list has a frame of its own, which its rows stay in
        visible: modelData.visible
          && !(modelData === mdList && (mdetail.key === "pacnew" || mdList.framed))
      }
    }

    // ── the head ────────────────────────────────────────────────────────────
    Item {
      id: head
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      visible: !win.headHidden
      height: win.headHidden ? 0 : 56

      // ONE CONTROL, TWO HALVES: a switch between the two views rather than
      // two buttons that happen to sit together — terminus/Segments, the
      // suite's switch (this was its first, written here; 2026-10-11): one
      // border drawn over the halves, a hairline between, one highlight that
      // slides to the view you are on.
      Term.Segments {
        id: seg
        anchors.left: parent.left
        anchors.leftMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        height: 32
        textSize: Zenon.px(16)
        ink: Zenon.accentKey
        options: win.tabs
        // a restart or reboot still owed after an update: Updates wears the
        // note's own ink (user, 2026-10-17) — NoteBar.inkOf
        inks: Ceres.noteItems.some(n => n.level === "bad") ? { updates: Zenon.red }
          : Ceres.noteItems.some(n => n.level === "warn") ? { updates: Zenon.yellow } : ({})
        current: win.tab
        onChose: (v) => win.showTab(v)
      }

      // WHAT HAS BEEN TYPED, NOT A BOX. The keys never leave the window — see
      // `typing` — so a box to type into offered nothing; the query is simply
      // said here, with a caret after it while you are in it, and a click
      // puts you back in.
      // Beside it the one switch the search has.
      Row {
        id: headRight
        anchors.right: parent.right
        anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        spacing: 22

        // WHAT IS MARKED, up here with the filter it was chosen through. It
        // lived in the key strip and ran into the keys whenever both were long.
        Text {
          id: markTally
          anchors.verticalCenter: parent.verticalCenter
          visible: (win.tab === "packages" && win.markCount > 0)
                || (win.tab === "updates" && win.umarkCount > 0)
          // resting on it: the marked packages, by name (markBubble)
          HoverHandler { id: markHov }
          textFormat: Text.StyledText
          // +N and −N, in the colors the confirm sheet gives the same two
          // sides — a sign and a color say "install" and "remove" faster
          // than the words did. Updates are a +N too, in the yellow their marked
          // rows are tinted with.
          text: win.tab === "updates"
            ? "<font color='" + Zenon.yellow + "'>+" + win.umarkCount + "</font>"
            : (win.markInstalls ? "<font color='" + Zenon.green + "'>+" + win.markInstalls + "</font>" : "")
              + (win.markInstalls && win.markRemovals ? "  " : "")
              + (win.markRemovals ? "<font color='" + Zenon.red + "'>\u2212" + win.markRemovals + "</font>" : "")
          font.family: Zenon.face
          font.weight: Font.Bold
          font.pixelSize: Zenon.px(16)
        }

        // the search and the chips beside it, closer to each other than the
        // head's other pieces (user, 2026-10-15)
        Row {
          visible: win.filters || win.tab === "packages" || win.tab === "updates"
          anchors.verticalCenter: parent.verticalCenter
          spacing: 8

          // THE SEARCH IS A FIELD, at the right of the tab bar (user,
          // 2026-10-14): the Store's first, then every tab that filters — it
          // used to be the query said as a line. Still not a text box: the keys
          // never leave the window (see `typing`); it shows what is typed, with
          // a caret while you are in it, and a click puts you back in.
          Rectangle {
            id: searchField
            visible: win.filters
            anchors.verticalCenter: parent.verticalCenter
            width: 260
            height: 32
            radius: Zenon.windowRadius
            color: Zenon.wash(win.typing ? 0.08 : 0.04)
            // the frame stays the border; while you are in it, the ring every
            // focused field wears (terminus' HeldRing — user, 2026-10-15)
            border.width: 1
            border.color: Zenon.border
            Term.HeldRing {
              anchors.fill: parent
              radius: parent.radius
              z: 10
              on: win.typing && win.face === "browse"
            }
            Text {
              id: sfGlyph
              anchors.left: parent.left
              anchors.leftMargin: 10
              anchors.verticalCenter: parent.verticalCenter
              text: "\uF002"
              color: win.typing || win.filterText !== "" ? Zenon.cyan : Zenon.accentMuted
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(13)
            }
            Row {
              anchors.left: sfGlyph.right
              anchors.leftMargin: 9
              anchors.right: sfClear.visible ? sfClear.left : parent.right
              anchors.rightMargin: 10
              anchors.verticalCenter: parent.verticalCenter
              spacing: 1
              clip: true
              Text {
                visible: win.filterText !== ""
                text: win.filterText
                color: win.typing ? Zenon.white : Zenon.accentKey
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.pixelSize: Zenon.px(15)
              }
              Rectangle {
                id: sfCaret
                visible: win.face === "browse" && win.typing
                anchors.verticalCenter: parent.verticalCenter
                width: 2
                height: 15
                color: Zenon.white
                opacity: 0.3
                SequentialAnimation on opacity {
                  running: sfCaret.visible
                  loops: Animation.Infinite
                  NumberAnimation { to: 1; duration: 550; easing.type: Easing.InOutSine }
                  NumberAnimation { to: 0.3; duration: 550; easing.type: Easing.InOutSine }
                }
              }
              Text {
                visible: win.filterText === ""
                text: "Search"
                color: Zenon.accentMuted
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.pixelSize: Zenon.px(15)
              }
            }
            // THE TEXT, CLEARED (user, 2026-10-15): a × at the end while there
            // is any — ctrl+u's own, for the pointer; you stay in the field.
            // Terminus' tab close chip, the suite's one × (user, 2026-10-15)
            Term.ClearChip {
              id: sfClear
              shown: win.filterText !== ""
              anchors.right: parent.right
              anchors.rightMargin: 8
              anchors.verticalCenter: parent.verticalCenter
              size: Zenon.px(15)
              z: 1
              onClicked: { win.setFilter(""); win.typing = true; keys.forceActiveFocus(); }
            }
            TapHandler { onTapped: { win.typing = true; keys.forceActiveFocus(); } }
          }

          // A TOGGLE CHIP (user, 2026-10-15; the glyph U+F0C7 theirs): a condition on the search, on or
          // off — lit cyan like the lit tab while it holds. The glyph alone; the
          // tip names it.
          Rectangle {
            id: onlyInstalled
            visible: win.tab === "packages"
            anchors.verticalCenter: parent.verticalCenter
            width: 32
            height: 32
            radius: Zenon.windowRadius
            // PRESSED, DARKENED as terminus' ClearChip is (user, 2026-10-15)
            color: onlyTap.pressed ? Zenon.pressFill
                 : win.installedOnly ? Zenon.alpha(Zenon.cyan, 0.2)
                 : onlyHov.hovered ? Zenon.wash(0.08) : Zenon.wash(0.05)
            border.width: 1
            border.color: win.installedOnly ? Zenon.alpha(Zenon.cyan, 0.7) : Zenon.border
            Text {
              anchors.centerIn: parent
              text: "\uF0C7"
              color: win.installedOnly ? Zenon.cyan : onlyHov.hovered ? Zenon.white : Zenon.accentKey
              opacity: onlyTap.pressed ? Zenon.pressDim : 1
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(16)
            }
            HoverHandler {
              id: onlyHov
              onHoveredChanged: hovered ? headTip.show(onlyInstalled, "Installed only") : headTip.hide(onlyInstalled)
            }
            TapHandler { id: onlyTap; onTapped: { win.installedOnly = !win.installedOnly; keys.forceActiveFocus(); } }
          }

          // the way to make the list fresher — Updates only. A chip like the
          // Installed one, the glyph alone (user, 2026-10-15); when it last
          // checked rides in its tip. Lit while a check runs, the glyph turning.
          Rectangle {
            id: refreshChip
            visible: win.tab === "updates"
            anchors.verticalCenter: parent.verticalCenter
            width: 32
            height: 32
            radius: Zenon.windowRadius
            color: refreshTap.pressed ? Zenon.pressFill
                 : Ceres.checking ? Zenon.alpha(Zenon.cyan, 0.2)
                 : refreshHov.hovered ? Zenon.wash(0.08) : Zenon.wash(0.05)
            border.width: 1
            border.color: Ceres.checking ? Zenon.alpha(Zenon.cyan, 0.7) : Zenon.border
            Text {
              id: refresh
              anchors.centerIn: parent
              text: "\uF021"
              color: Ceres.checking ? Zenon.cyan : refreshHov.hovered ? Zenon.white : Zenon.accentKey
              opacity: refreshTap.pressed ? Zenon.pressDim : 1
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(16)
              RotationAnimation on rotation {
                running: Ceres.checking
                loops: Animation.Infinite
                from: 0; to: 360; duration: 900
                onRunningChanged: if (!running) refresh.rotation = 0
              }
            }
            HoverHandler {
              id: refreshHov
              onHoveredChanged: hovered ? headTip.show(refreshChip, win.checkTip) : headTip.hide(refreshChip)
            }
            TapHandler { id: refreshTap; onTapped: Ceres.check() }
          }
        }
      }


      Rule { anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right }
    }

    // ── THE MESSAGE BAR ──────────────────────────────────────────────
    // The notes Ceres keeps about its own answer — a failed check, a reboot
    // or a service restart owed, news unread. None of them is an update, and they
    // hold whether there are updates or not, so they sit in a bar of their
    // own above the list rather than as loose red lines that read like part
    // of it. Each row wears its own level; the bar wears the worst of them.
    // An Item around the bar so the margins count toward the height the body
    // is anchored under, and the whole thing takes no room when there is
    // nothing to say.
    Item {
      id: notes
      anchors.top: head.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      visible: win.tab === "updates" && win.page === "browse"
               && Ceres.noteItems.length > 0
      height: visible ? noteBar.height + 20 : 0

      // the bar itself — ceres/NoteBar, shared with the quick-access panel
      NoteBar {
        id: noteBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        anchors.topMargin: 10
      }
    }

    // ── the body ────────────────────────────────────────────────────────────
    Item {
      id: body
      anchors.top: notes.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom

      // ── History ─────────────────────────────────────────────────────
      // Transactions on the left, newest first, each under its date, what it
      // was and what it did. On the right, the selected package's way back:
      // what is installed now, and every version the cache still holds.
      Item {
        id: historyView
        visible: win.page === "browse" && win.tab === "history"
        anchors.fill: parent

        ListView {
          id: histList
          // Every row built, so the list's length is measured, not estimated
          // — see the row height. History is a few hundred small rows.
          cacheBuffer: 100000
          ScrollRail {
            target: histList
            // Against the divider, not the list 8 in from it. Placed by x:
            // hdiv is declared after the list, and an anchor to it from in
            // here is refused as not yet a sibling.
            parent: historyView
            x: hdiv.x - width
            anchors.top: histList.top
            anchors.bottom: histList.bottom
          }
          ElasticScroll { view: histList }
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          anchors.margins: 8
          width: Math.round(parent.width * 0.56) - 16
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          model: win.historyRows
          delegate: Item {
            id: hrow
            required property var modelData
            required property int index
            width: histList.width - 14
            // The heading is taller than a row, which is safe here only because
            // the list builds EVERY row (see its cacheBuffer): a ListView that
            // estimates its length from the rows built so far gets it wrong
            // with mixed heights, and the elastic scroll clamps to the guess.
            height: hrow.modelData.kind === "day"
              ? (hrow.modelData.first ? 0 : 14) + 7 + 17 + 7 + 1 : 30

            // ── the day, as terminus' sidebar names a section ────────
            // its SideHead, metric for metric: air 13, rule, air 7, name, air 7, rule —
            // the rules edge to edge across the list, under the scroll rail too
            Rectangle {
              visible: hrow.modelData.kind === "day" && !hrow.modelData.first
              y: 13
              width: histList.width
              height: 1
              color: Zenon.border
            }
            Text {
              visible: hrow.modelData.kind === "day"
              x: 15
              y: (hrow.modelData.first ? 0 : 14) + 7
              text: hrow.modelData.label || ""
              color: Zenon.accentKey
              font.family: Zenon.face
              font.weight: Font.Bold
              font.pixelSize: Zenon.px(15)
              font.letterSpacing: 1.2
            }
            Rectangle {
              visible: hrow.modelData.kind === "day"
              anchors.bottom: parent.bottom
              width: histList.width
              height: 1
              color: Zenon.border
            }

            // a transaction: when, what, how much
            Row {
              visible: hrow.modelData.kind === "tx"
              anchors.left: parent.left
              anchors.leftMargin: 10
              anchors.verticalCenter: parent.verticalCenter
              spacing: 12
              Text {
                text: hrow.modelData.time || ""
                color: Zenon.blue
                font.family: Zenon.face
                font.weight: Font.Bold
                font.pixelSize: Zenon.px(16)
              }
              Text {
                text: hrow.modelData.what || ""
                color: Zenon.accentKey
                font.family: Zenon.face
                font.weight: Font.Bold
                font.pixelSize: Zenon.px(16)
              }
              Text {
                text: hrow.modelData.counts || ""
                color: Zenon.accentMuted
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.pixelSize: Zenon.px(15)
              }
            }

            Rectangle {
              visible: !hrow.modelData.head
              anchors.fill: parent
              radius: Zenon.windowRadius
              color: hrow.index === win.hsel ? Zenon.menuHi : "transparent"
              border.width: hrow.index === win.hsel ? 1 : 0
              border.color: Zenon.border
            }
            ChangeRow {
              grow: 2
              visible: !hrow.modelData.head
              anchors.left: parent.left
              anchors.leftMargin: 10
              anchors.right: parent.right
              anchors.rightMargin: 10
              anchors.verticalCenter: parent.verticalCenter
              u: hrow.modelData.head ? null : hrow.modelData.e
              glyph: hrow.modelData.head ? "" : win.verbGlyph(hrow.modelData.e.verb)
              glyphInk: hrow.modelData.head ? Zenon.blue : win.verbInk(hrow.modelData.e.verb)
            }
            TapHandler {
              enabled: !hrow.modelData.head
              onTapped: { win.hsel = hrow.index; keys.forceActiveFocus(); }
              onDoubleTapped: { win.hsel = hrow.index; win.installCached(win.wayBack); }
            }
          }

          Text {
            anchors.centerIn: parent
            visible: win.historyRows.length === 0 && !historyProc.running
            text: win.hquery !== "" ? "nothing matches" : "no history"
            color: Zenon.accentMuted
            font.family: Zenon.face
            font.weight: Font.Bold
            font.pixelSize: Zenon.px(17)
          }
        }

        Rectangle {
          id: hdiv
          x: Math.round(parent.width * 0.56)
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          width: 1
          color: Zenon.border
        }

        // Scrolls: the cache and the archive together outgrow a short window.
        Flickable {
          id: hdetail
          ScrollRail {
            target: hdetail
            // Against the window's edge, not the pane's 16 in from it.
            parent: historyView
            anchors.right: parent.right
            anchors.top: hdetail.top
            anchors.bottom: hdetail.bottom
          }
          anchors.left: hdiv.right
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          anchors.margins: 16
          clip: true
          contentHeight: hdetailCol.implicitHeight
          boundsBehavior: Flickable.StopAtBounds
          visible: !!win.hevent
          ElasticScroll { view: hdetail }
          // a new package starts at its top
          Connections { target: win; function onHselChanged() { hdetail.contentY = 0; } }

          Column {
            id: hdetailCol
            width: hdetail.width - 14
            spacing: 8

            Text {
              text: win.hevent ? win.hevent.name : ""
              color: Zenon.white
              font.family: Zenon.face
              font.weight: Font.Bold
              font.pixelSize: Zenon.px(24)
            }
            // A FLATPAK'S EVENT: what it was, and why there is no way back
            Text {
              visible: !!win.hevent && !!win.hevent.flatpak
              width: parent.width
              wrapMode: Text.Wrap
              textFormat: Text.StyledText
              readonly property var tx: win.hevent ? win.history[win.historyRows[win.hsel].tx] : null
              text: !win.hevent || !win.hevent.flatpak ? ""
                : (win.hevent.runtime
                  ? "The shared runtimes Flatpak apps run on \u2014 pulled in with the app beside them, and taken out by Maintenance \u203A Flatpak once nothing needs them."
                  : "<font color='" + Zenon.accentMuted + "'>Flatpak</font>  " + Cer.esc(win.hevent.id || "")
                    + (tx && tx.scope ? "  <font color='" + Zenon.accentMuted + "'>\u00B7 " + (tx.scope === "user" ? "just you" : "everyone") + "</font>" : "")
                    + "<br><br>Flatpak keeps no older versions here to go back to; the Store has the app as it is now.")
              color: Zenon.white
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(16)
            }
            Text {
              visible: !win.hevent || !win.hevent.flatpak
              textFormat: Text.StyledText
              text: !win.hevent ? "" : (win.installedNow !== ""
                ? "<font color='" + Zenon.accentMuted + "'>installed now</font>  " + Cer.esc(win.installedNow)
                : "<font color='" + Zenon.accentMuted + "'>not installed</font>")
              color: Zenon.white
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(17)
              bottomPadding: 8
            }
            Text {
              visible: !win.hevent || !win.hevent.flatpak
              text: win.cached.length ? "In the package cache" : "Nothing of it in the package cache"
              color: Zenon.accentMuted
              font.family: Zenon.face
              font.weight: Font.Bold
              font.pixelSize: Zenon.px(15)
            }
            // every cached version, the way back and any other
            Repeater {
              model: win.cached
              delegate: VersionRow { required property var modelData; v: modelData }
            }
            // and beyond the cache, the archive: the ten newest it has
            Text {
              visible: win.archived.length > 0
              topPadding: 10
              text: "From the Arch archive"
              color: Zenon.accentMuted
              font.family: Zenon.face
              font.weight: Font.Bold
              font.pixelSize: Zenon.px(15)
            }
            Repeater {
              model: win.archived.slice(0, 10)
              delegate: VersionRow { required property var modelData; v: modelData }
            }
            Text {
              visible: win.archived.length > 10
              text: "+ " + (win.archived.length - 10) + " older in the archive"
              color: Zenon.accentMuted
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(15)
            }
            // what going back does not do
            Text {
              visible: win.cached.length > 0 || win.archived.length > 0
              width: parent.width
              wrapMode: Text.Wrap
              topPadding: 10
              text: "A version installed from here stays until the next full upgrade replaces it. "
                + "To hold it, add the package to IgnorePkg in /etc/pacman.conf."
              color: Zenon.accentMuted
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(15)
            }
          }
        }
      }

      // ── Settings: pacman.conf ─────────────────────────────────────────
      // ── the Store ────────────────────────────────────────────────────
      StoreView {
        id: storeView
        visible: win.page === "browse" && win.tab === "store"
        anchors.fill: parent
        query: win.squery
        script: win.script
        onChangeAsked: (row) => win.confirmOne(row)
        onFlatpakAsked: (app, remove) => win.askFlatpak(app, remove)
        onReleased: keys.forceActiveFocus()
        onSearchLeft: { win.sharedQuery = ""; win.typing = false; }
      }

      ConfigView {
        id: configView
        visible: win.page === "browse" && win.tab === "settings"
        anchors.fill: parent
        onReleased: keys.forceActiveFocus()
        onReviewAsked: win.overlay = "conf"
        onFlatpakRemoveAsked: { Ceres.listFlatpaks(); win.measureData(""); win.overlay = "fpoff"; }
      }

      // ── Maintenance ─────────────────────────────────────────────────
      // What wants doing on the left, with where it stands; the selected
      // one's detail and its actions on the right.
      Item {
        id: maintView
        visible: win.page === "browse" && win.tab === "maintenance"
        anchors.fill: parent

        // As wide as its content, as Config's is: the widest title or
        // summary, the dot's gutter, the padding. A share of the window
        // left most of it empty and squeezed the detail beside it.
        FontMetrics { id: mfTitle; font.family: Zenon.face; font.weight: Font.Bold; font.pixelSize: Zenon.px(17) }
        FontMetrics { id: mfSum; font.family: Zenon.face; font.pixelSize: Zenon.px(15) }
        readonly property real sideW: {
          let w = 0;
          for (const it of win.maintItems)
            w = Math.max(w, mfTitle.advanceWidth(it.title), mfSum.advanceWidth(win.maintSummary(it.key)));
          return Math.max(180, Math.ceil(w) + 26 + 16);
        }
        // Scrolls when the window is shorter than the list, and follows the
        // selection there from the keys.
        Flickable {
          id: maintSide
          ScrollRail {
            target: maintSide
            parent: maintSide
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
          }
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          width: maintView.sideW + 16
          clip: true
          contentHeight: maintList.implicitHeight + 16
          boundsBehavior: Flickable.StopAtBounds
          ElasticScroll { view: maintSide }
          Connections {
            target: win
            function onMselChanged() { win.keepInView(maintSide, 8 + win.msel * 60, 56); }
          }

          Column {
            id: maintList
            x: 8
            y: 8
            width: maintView.sideW
            spacing: 4
            Repeater {
              model: win.maintItems
              delegate: Rectangle {
                id: mrow
                required property var modelData
                required property int index
                width: maintList.width
                height: 56
                radius: Zenon.windowRadius
                color: mrow.index === win.msel ? Zenon.menuHi : "transparent"
                border.width: mrow.index === win.msel ? 1 : 0
                border.color: Zenon.border
                // every item says how it stands, not only the ones that want
                // something: green, yellow, red — and gray until it is known
                readonly property string level: win.maintLevel(mrow.modelData.key)
                Rectangle {
                  anchors.left: parent.left
                  anchors.leftMargin: 12
                  anchors.verticalCenter: parent.verticalCenter
                  width: 6; height: 6; radius: 3
                  color: win.levelInk(mrow.level)
                  opacity: mrow.level === "ok" ? 0.7 : 1
                  Behavior on color { ColorAnimation { duration: 180 } }
                }
                Column {
                  anchors.left: parent.left
                  anchors.leftMargin: 26
                  anchors.right: parent.right
                  anchors.rightMargin: 12
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: 2
                  Text {
                    text: mrow.modelData.title
                    color: Zenon.white
                    font.family: Zenon.face
                    font.weight: Font.Bold
                    font.pixelSize: Zenon.px(17)
                  }
                  Text {
                    // held to the column: the pane beside it is not its to write on
                    width: parent.width
                    elide: Text.ElideRight
                    visible: text !== ""
                    text: win.maintSummary(mrow.modelData.key)
                    color: mrow.level === "bad" ? Zenon.red
                      : mrow.level === "warn" ? Zenon.yellow : Zenon.accentMuted
                    font.family: Zenon.face
                    font.weight: Zenon.weight
                    font.pixelSize: Zenon.px(15)
                  }
                }
                TapHandler { onTapped: { win.msel = mrow.index; keys.forceActiveFocus(); } }
              }
            }
          }
        }

        Rectangle {
          id: mdiv
          x: maintView.sideW + 16
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          width: 1
          color: Zenon.border
        }

        Item {
          id: mdetail
          anchors.left: mdiv.right
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          anchors.margins: 16
          readonly property string key: win.maintItems[win.msel].key
          readonly property var m: win.maint

          Text {
            id: mdTitle
            text: win.maintItems[win.msel].title
            color: Zenon.white
            font.family: Zenon.face
            font.weight: Font.Bold
            font.pixelSize: Zenon.px(22)
          }
          Text {
            id: mdWhat
            anchors.top: mdTitle.bottom
            anchors.topMargin: 6
            width: parent.width
            wrapMode: Text.Wrap
            text: ({
              orphans: "Installed as dependencies of something that is no longer installed. Nothing needs them.",
              pacnew: "Configuration files pacman did not overwrite because you had changed them. The new version waits beside yours, as .pacnew, until they are merged.",
              cache: "Every package pacman has downloaded. Old versions are what History goes back to; stale downloads are left by interrupted transactions and are never reused.",
              clones: "paru's build directories for AUR packages. Cloned again whenever a rebuild needs one.",
              aurhealth: "What the AUR says about your AUR packages. Flagged out of date means someone reported that upstream has moved on and the package has not caught up; orphaned means it has no maintainer, and no one will update it; gone means it is no longer in the AUR at all. Any of these is worth a look before the package breaks.",
              oldcode: "Programs that were already running when an upgrade replaced their libraries. They keep using the old copies until they restart: restart the apps yourself, and Ceres restarts the session services. "
                + "Logging out does not do it \u2014 your services run as long as any session of yours does, a tty you started the desktop from included. Only your own processes can be seen; system services need root to inspect.",
              mirrors: "Where pacman downloads from, in the order it tries them. Health comes from archlinux.org's own mirror status, which checks every mirror for how far behind it is. "
                + "Ranking times every mirror it reports as fully synced from this machine, rates the quickest twelve on a real download, and offers the fastest ten. The list you have now is kept as mirrorlist.ceres-bak.",
              flatpak: "Flatpak's apps and the runtimes they share, for everyone and just for you. Removing unused runtimes takes out the ones no installed app needs any more \u2014 left behind as apps are removed and updated. "
                + "Repair checks every installed file against what Flathub published, and fetches again whatever does not match.",
              sync: "The system's package databases and ceres' list of AUR packages. Ceres checks for updates against its own copy, so these only move when something upgrades or you sync them here. "
                + "After a sync, update before installing anything new: installing onto freshly synced databases without upgrading can pull in libraries newer than what installed programs were built against."
            })[mdetail.key]
            color: Zenon.accentKey
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(16)
          }

          Row {
            id: mdBtns
            anchors.top: mdWhat.bottom
            anchors.topMargin: 14
            spacing: 8
            DialogButton {
              visible: mdetail.key === "orphans" && !!mdetail.m && mdetail.m.orphans.length > 0
              label: "Remove orphans"
              ink: Zenon.red
              primary: true
              onClicked: win.maintGo("")
            }
            DialogButton {
              visible: mdetail.key === "pacnew" && !!mdetail.m && mdetail.m.pacnew.length > 0
              label: "Merge in terminal"
              ink: Zenon.cyan
              primary: true
              onClicked: win.maintGo("")
            }
            DialogButton {
              visible: mdetail.key === "cache"
              ready: !!mdetail.m && !!mdetail.m.keep && mdetail.m.keep.n > 0
              label: "Keep " + win.keepVersions + " versions"
              ink: Zenon.cyan
              primary: true
              onClicked: win.maintGo("")
            }
            DialogButton {
              visible: mdetail.key === "cache"
              ready: !!mdetail.m && !!mdetail.m.uninst && mdetail.m.uninst.n > 0
              label: "Drop uninstalled"
              ink: Zenon.accentMuted
              onClicked: win.maintGo("uninstalled")
            }
            DialogButton {
              visible: mdetail.key === "cache" && !!mdetail.m && mdetail.m.stale > 0
              label: "Clear stale downloads"
              ink: Zenon.yellow
              onClicked: win.maintGo("stale")
            }
            DialogButton {
              visible: mdetail.key === "clones" && !!mdetail.m && mdetail.m.clones.some(c => !c.installed)
              label: "Delete uninstalled"
              ink: Zenon.cyan
              primary: true
              onClicked: win.maintGo("")
            }
            DialogButton {
              visible: mdetail.key === "mirrors" && !!win.ranked && win.ranked.ranked.length > 0
              label: "Use these " + (win.ranked ? win.ranked.ranked.length : 0)
              ink: Zenon.cyan
              primary: true
              onClicked: win.maintGo("")
            }
            DialogButton {
              visible: mdetail.key === "mirrors"
              ready: !win.ranking && !!win.mirrors && win.mirrors.statusOk
              label: win.ranking ? "Ranking\u2026" : win.ranked ? "Rank again" : "Rank from here"
              ink: win.ranked ? Zenon.accentMuted : Zenon.cyan
              primary: !win.ranked
              onClicked: win.maintGo("rank")
            }
            DialogButton {
              visible: mdetail.key === "oldcode" && Ceres.staleServices.length > 0
              label: Ceres.staleServices.length === 1 ? "Restart the service" : "Restart " + Ceres.staleServices.length + " services"
              ink: Zenon.cyan
              primary: true
              ready: !Ceres.txBusy
              onClicked: Ceres.restartStaleServices()
            }
            DialogButton {
              visible: mdetail.key === "flatpak"
              label: "Remove unused"
              ink: Zenon.cyan
              primary: true
              // only when there is something to remove (user, 2026-10-15)
              ready: !!mdetail.m && mdetail.m.fpUnused.length > 0 && !Ceres.txBusy
              onClicked: win.maintGo("")
            }
            DialogButton {
              visible: mdetail.key === "flatpak"
              label: !win.fpRepair ? "Checking\u2026" : "Repair"
              ink: Zenon.accentMuted
              // and only when the dry run found something to repair
              ready: !!win.fpRepair && win.fpRepair.problems.length > 0 && !Ceres.txBusy
              onClicked: win.maintGo("repair")
            }
            DialogButton {
              visible: mdetail.key === "sync"
              label: "Sync now"
              ink: Zenon.cyan
              primary: true
              onClicked: win.maintGo("")
            }
            DialogButton {
              visible: mdetail.key === "clones" && !!mdetail.m && mdetail.m.clones.length > 0
              label: "Delete all"
              ink: Zenon.red
              onClicked: win.maintGo("all")
            }
          }

          // WHAT EACH CACHE BUTTON WOULD DO, from paccache's own dry run — so a
          // button is never pressed to find out it had nothing to remove.
          Column {
            id: cacheFacts
            visible: mdetail.key === "cache" && !!mdetail.m && !!mdetail.m.keep
            anchors.top: mdBtns.bottom
            anchors.topMargin: 16
            width: parent.width
            spacing: 8
            readonly property var facts: !mdetail.m || !mdetail.m.keep ? [] : [
              ["Versions beyond the newest " + win.keepVersions, mdetail.m.keep],
              ["Files of uninstalled packages", mdetail.m.uninst],
              ["Stale downloads", { n: mdetail.m.stale, size: "" }]
            ]
            // Wide enough for the longest label: a fixed 250 let "Files of
            // uninstalled packages" run under its own value.
            readonly property real labelW: win.factLabelWidth(cacheFacts.facts)
            Repeater {
              model: cacheFacts.facts
              delegate: Row {
                required property var modelData
                spacing: 12
                Text {
                  width: cacheFacts.labelW
                  text: modelData[0]
                  color: Zenon.accentKey
                  font.family: Zenon.face
                  font.weight: Zenon.weight
                  font.pixelSize: Zenon.px(16)
                }
                Text {
                  text: modelData[1].n === 0 ? "none"
                    : modelData[1].n + (modelData[1].n === 1 ? " file" : " files")
                      + (modelData[1].size ? " · " + modelData[1].size : "")
                  color: modelData[1].n === 0 ? Zenon.accentMuted : Zenon.yellow
                  font.family: Zenon.face
                  font.weight: Zenon.weight
                  font.pixelSize: Zenon.px(16)
                }
              }
            }
          }

          // THE MIRRORS' HEALTH, in the body where there is room for it —
          // laid out as the cache's facts are.
          Column {
            id: mirrorFacts
            visible: mdetail.key === "mirrors" && !!win.mirrors
            anchors.top: mdBtns.bottom
            anchors.topMargin: visible ? 16 : 0
            height: visible ? implicitHeight : 0
            width: parent.width
            spacing: 8
            readonly property var facts: !win.mirrors ? [] : (() => {
                const h = win.mirrors;
                const first = h.servers.length ? h.servers[0].status : null;
                return [
                  ["Servers", String(h.servers.length), false],
                  ["Behind", !h.statusOk ? "unknown \u2014 no status from archlinux.org"
                    : h.behind === 0 ? "none" : h.behind + " of " + h.servers.length, h.behind * 4 >= h.servers.length],
                  ["First server", (h.servers.length ? h.servers[0].host : "none")
                    + (h.firstMs >= 0 ? " \u00b7 answers in " + h.firstMs + "ms" : " \u00b7 does not answer"),
                    h.firstMs < 0 || (h.statusOk && Cer.mirrorBehind(first))],
                  ["List written", Cer.age(Date.now() - h.modified), Date.now() - h.modified > 90 * 86400000]
                ];
              })()
            readonly property real labelW: win.factLabelWidth(mirrorFacts.facts)
            Repeater {
              model: mirrorFacts.facts
              delegate: Row {
                required property var modelData
                spacing: 12
                Text {
                  width: mirrorFacts.labelW
                  text: modelData[0]
                  color: Zenon.accentKey
                  font.family: Zenon.face
                  font.weight: Zenon.weight
                  font.pixelSize: Zenon.px(16)
                }
                Text {
                  // a long host and its answer time ran off the window's edge
                  width: mirrorFacts.width - mirrorFacts.labelW - 12
                  elide: Text.ElideRight
                  text: modelData[1]
                  color: modelData[2] ? Zenon.yellow : Zenon.accentMuted
                  font.family: Zenon.face
                  font.weight: Zenon.weight
                  font.pixelSize: Zenon.px(16)
                }
              }
            }
          }

          // THE MIRRORS' LIST, FRAMED: a hundred-odd servers under a summary
          // read as part of it with nothing between them — boxed as a job's
          // log is (TxView's LogPane), so the list is plainly its own thing.
          Rectangle {
            visible: mdList.framed
            anchors.fill: mdList
            anchors.margins: -6
            radius: Zenon.windowRadius
            color: Zenon.darken(0.25)
            border.width: 1
            border.color: Zenon.border
          }

          // the list behind the summary
          ListView {
            id: mdList
            readonly property bool framed: mdetail.key === "mirrors"
            ScrollRail {
              target: mdList
              // On the frame's edge when framed, else the window's; never the list's.
              parent: mdetail
              anchors.right: parent.right
              anchors.rightMargin: mdList.framed ? 0 : -mdetail.anchors.rightMargin
              anchors.top: mdList.top
              anchors.bottom: mdList.bottom
            }
            ElasticScroll { view: mdList }
            anchors.top: mirrorFacts.visible ? mirrorFacts.bottom : mdBtns.bottom
            anchors.topMargin: mdList.framed ? 14 + 6 : 14
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: mdList.framed ? 6 : 0
            anchors.rightMargin: mdList.framed ? 6 : 0
            height: mdetail.key === "pacnew" ? Math.min(contentHeight, 120)
              : parent.height - y - (mdList.framed ? 6 : 0)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            // THE RANKING ARRIVES rather than appears: the fastest ten settle
            // in one after another, top first, where your list just was —
            // the answer to the long wait gets a moment of its own. Only
            // then; every other change of this list is instant.
            populate: Transition {
              id: rankIn
              enabled: mdetail.key === "mirrors" && !!win.ranked
              SequentialAnimation {
                PropertyAction { property: "opacity"; value: 0 }
                PauseAnimation { duration: Math.min(rankIn.ViewTransition.index, 12) * 35 }
                ParallelAnimation {
                  NumberAnimation { property: "opacity"; to: 1; duration: 240; easing.type: Easing.OutCubic }
                  NumberAnimation {
                    property: "y"
                    from: rankIn.ViewTransition.destination.y - 8
                    to: rankIn.ViewTransition.destination.y
                    duration: 300; easing.type: Easing.OutCubic
                  }
                }
              }
            }
            model: !mdetail.m ? []
              : mdetail.key === "orphans" ? mdetail.m.orphans
              : mdetail.key === "clones" ? mdetail.m.clones
              : mdetail.key === "pacnew" ? mdetail.m.pacnew.map(p => ({ name: p }))
              : mdetail.key === "oldcode" ? win.oldCodeRows
              : mdetail.key === "mirrors" ? win.mirrorRows
              : mdetail.key === "flatpak" ? (mdetail.m.fpUnused.length
                    ? [{ head: true, name: "Unused \u2014 nothing needs them" }]
                      .concat(mdetail.m.fpUnused.map(u => ({ name: u.id, version: u.branch, right: u.scope === "user" ? "just you" : "everyone" })))
                    : [])
                  .concat(win.fpRepair && win.fpRepair.problems.length
                    ? [{ head: true, name: "Repair would fix" }].concat(win.fpRepair.problems.map(p => ({ name: p.text, right: p.scope })))
                    : [])
                  .concat([{ head: true, name: "Apps" }]).concat(mdetail.m.fpApps)
                  .concat([{ head: true, name: "Runtimes" }]).concat(mdetail.m.fpRuntimes)
              : mdetail.key === "aurhealth" ? Ceres.aurHealth.problems.map(p => ({
                  name: p.name,
                  right: p.gone ? "no longer in the AUR"
                    : [p.flagged ? "flagged out of date " + Cer.age(Date.now() - p.flagged) : "",
                       p.orphaned ? "orphaned" : ""].filter(x => x).join(" \u00b7 ") }))
              : []
            delegate: Rectangle {
              id: mitem
              required property var modelData
              required property int index
              readonly property bool picked: mdetail.key === "pacnew" && mitem.index === win.pnsel
              width: mdList.width - 14
              height: 28
              radius: Zenon.windowRadius
              color: mitem.picked ? Zenon.menuHi : "transparent"
              border.width: mitem.picked ? 1 : 0
              border.color: Zenon.border
              // a mirror's health — see mirrorRows
              Rectangle {
                visible: mitem.modelData.dot !== undefined && mitem.modelData.dot !== ""
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                width: 6; height: 6; radius: 3
                color: win.levelInk(mitem.modelData.dot || "")
                opacity: mitem.modelData.dot === "ok" ? 0.7 : 1
              }
              Text {
                anchors.left: parent.left
                anchors.leftMargin: mitem.modelData.dot !== undefined ? 24 : 10
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.StyledText
                font.weight: mitem.modelData.head ? Font.Bold : Font.Normal
                text: mitem.modelData.head ? "<font color='" + Zenon.accentMuted + "'>" + Cer.esc(mitem.modelData.name) + "</font>"
                  : Cer.esc(mitem.modelData.name) + (mitem.modelData.version
                  ? "  <font color='" + Zenon.accentMuted + "'>" + Cer.esc(mitem.modelData.version) + "</font>" : "")
                  + (mdetail.key === "clones" && !mitem.modelData.installed
                    ? "  <font color='" + Zenon.yellow + "'>not installed</font>" : "")
                color: Zenon.white
                font.family: Zenon.face
                font.pixelSize: Zenon.px(16)
              }
              Text {
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, mitem.width * 0.5)
                elide: Text.ElideLeft
                text: mitem.modelData.size ? Cer.bytes(mitem.modelData.size) : (mitem.modelData.right || "")
                color: Zenon.accentMuted
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.pixelSize: Zenon.px(15)
              }
              TapHandler {
                enabled: mdetail.key === "pacnew"
                onTapped: { win.pnsel = mitem.index; win.loadPacnewDiff(); }
              }
            }
          }

          // a .pacnew, as the change it would make
          ListView {
            id: pnView
            ScrollRail {
              target: pnView
              // Against the window's edge, not the pane's 16 in from it.
              parent: mdetail
              anchors.right: parent.right
              anchors.rightMargin: -mdetail.anchors.rightMargin
              anchors.top: pnView.top
              anchors.bottom: pnView.bottom
            }
            ElasticScroll { view: pnView }
            visible: mdetail.key === "pacnew" && win.pnDiff.length > 0
            anchors.top: mdList.bottom
            anchors.topMargin: 12
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: win.pnDiff
            delegate: Text {
              required property var modelData
              width: pnView.width - 14
              wrapMode: Text.WrapAnywhere
              text: modelData.text
              color: modelData.ink === "add" ? Zenon.green : modelData.ink === "del" ? Zenon.red
                : modelData.ink === "hunk" ? Zenon.cyan : Zenon.accentKey
              font.family: Zenon.faceCode
              font.weight: Zenon.codeWeight
              font.pixelSize: Zenon.px(15)
            }
          }
        }
      }

      // ── browse: list on the left, the row described on the right ─────
      Item {
        id: browse
        visible: win.page === "browse" && (win.tab === "updates" || win.tab === "packages")
        anchors.fill: parent

        Item {
          id: left
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          // The whole width when there is nothing to describe: an empty
          // Updates tab has no row to preview.
          readonly property bool alone: win.tab === "updates" && win.updateRows.length === 0
          width: alone ? parent.width : Math.round(parent.width * 0.56)

          // ── THE COLUMNS, SORTABLE ───────────────────────────────────────
          // terminus' heading bar (its ColHeadBar), the same strip: flush
          // with the top of the list and its full width, a hairline under
          // it, and the rows starting at that line and going on under it
          // frosted, as they do under the head — chrome, not a pill floating
          // over the rows with them showing through it sharp. Small fixed-
          // width capitals, the one the list is sorted by in cyan with its
          // direction. Click a heading to sort by it, again to turn it round.
          // With none chosen the search's own order stands — best match first.
          Item {
            id: colBar
            visible: win.tab === "packages"
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: visible ? 22 : 0

            Rectangle {
              anchors.bottom: parent.bottom
              width: parent.width
              height: 1
              color: Zenon.border
            }

            component ColHead: Item {
              id: ch
              property string label: ""
              property string key: ""
              property bool rightAlign: false
              height: 22
              readonly property bool on: win.sortKey === ch.key
              Text {
                anchors.fill: parent
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: ch.rightAlign ? Text.AlignRight : Text.AlignLeft
                text: ch.on ? ch.label + (win.sortDesc ? " \u25BE" : " \u25B4") : ch.label
                color: ch.on ? Zenon.cyan : (chHov.hovered ? Zenon.accentKey : Zenon.accentMuted)
                font.family: Zenon.faceFixed
                font.weight: Zenon.weight
                font.pixelSize: Zenon.px(12)
              }
              HoverHandler { id: chHov; cursorShape: Qt.PointingHandCursor }
              TapHandler { onTapped: { win.sortBy(ch.key); keys.forceActiveFocus(); } }
            }

            // on the rows' own columns: the list is inset 8 and its rows 14
            // short of its width, so name after the state glyph, size ending
            // where the size column ends, repo on the rows' right edge
            ColHead { x: 8 + 34; width: 200; label: "NAME"; key: "name" }
            ColHead { x: 8 + pkgList.width - 14 - 10 - 72 - 12 - 90; width: 90; label: "SIZE"; key: "size"; rightAlign: true }
            ColHead { x: 8 + pkgList.width - 14 - 10 - 72; width: 72; label: "REPO"; key: "repo"; rightAlign: true }
          }

          ListView {
            id: pkgList
            // terminus' scrollbar — see morpheus/ScrollRail. Parented out of the view
            // (to the pane), so it stays put instead of scrolling away.
            ScrollRail {
              target: pkgList
              // Against the pane's edge, not the list's 8 in from it.
              parent: left
              anchors.right: parent.right
              anchors.top: pkgList.top
              anchors.bottom: pkgList.bottom
            }
            ElasticScroll { view: pkgList }
            visible: win.tab === "packages"
            anchors.fill: parent
            anchors.margins: 8
            // the rows start at the headings' hairline — see colBar
            anchors.topMargin: colBar.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: win.rows
            delegate: Item {
              id: prow
              required property var modelData
              required property int index
              readonly property bool here: index === win.sel
              readonly property var mark: win.marks[modelData.name] || null
              width: pkgList.width - 14
              height: 28

              Rectangle {
                anchors.fill: parent
                radius: Zenon.windowRadius
                // the tint says what the mark will DO — green in, red out — the
                // same inks as the + and − and the count in the head
                // THE CURSOR ON A MARKED ROW (user, 2026-10-17: hard to see):
                // terminus' rule — the fill deepens and a cyan outline says
                // "you are here", whatever the mark (EntryRow.cursorOnly)
                color: prow.mark ? (prow.modelData.installed
                    ? Qt.rgba(Zenon.red.r, Zenon.red.g, Zenon.red.b, prow.here ? 0.24 : 0.12)
                    : Qt.rgba(Zenon.green.r, Zenon.green.g, Zenon.green.b, prow.here ? 0.22 : 0.10))
                  : prow.here ? Zenon.menuHi : "transparent"
                border.width: prow.here ? 1 : 0
                border.color: prow.mark ? Zenon.cyan : Zenon.border
              }

              // state, or what the mark will do to it
              Text {
                id: st
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                width: 18
                text: prow.mark ? (modelData.installed ? "" : "")
                  : modelData.state === "avail" ? "○" : "●"
                color: prow.mark ? (modelData.installed ? Zenon.red : Zenon.green)
                  : modelData.state === "explicit" ? Zenon.green
                  : modelData.state === "dep" ? Zenon.dimInk : Zenon.accentMuted
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.pixelSize: Zenon.px(15)
              }
              Text {
                anchors.left: st.right
                anchors.leftMargin: 6
                anchors.right: size.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                textFormat: Text.StyledText
                text: Cer.esc(modelData.name) + (modelData.version
                  ? "  <font color='" + Ceres.ink.muted + "'>" + Cer.esc(modelData.version) + "</font>" : "")
                color: Zenon.white
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.pixelSize: Zenon.px(17)
              }
              Text {
                id: size
                anchors.right: repo.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.size > 0 ? Cer.bytes(modelData.size) : ""
                color: Zenon.accentMuted
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.pixelSize: Zenon.px(15)
              }
              // THE REPO AS A TINTED PILL: thirty rows of bold colored
              // capitals were the loudest column in the list for the least
              // read fact in it. The ink is the same; it is carried by a
              // soft ground now, with the word in it smaller and plain.
              Item {
                id: repo
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                width: 72
                height: 18
                Rectangle {
                  readonly property color ink: win.repoInk(prow.modelData.repo)
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  width: repoWord.implicitWidth + 14
                  height: 18
                  radius: 9
                  color: Qt.rgba(ink.r, ink.g, ink.b, 0.13)
                  Text {
                    id: repoWord
                    anchors.centerIn: parent
                    text: prow.modelData.repo.toLowerCase().replace("-testing", "-t")
                    color: parent.ink
                    font.family: Zenon.face
                    font.weight: Zenon.weight
                    font.pixelSize: Zenon.px(12)
                  }
                }
              }

              TapHandler {
                acceptedModifiers: Qt.NoModifier
                onTapped: win.rowClick(prow.index, 0)
                onDoubleTapped: { win.sel = prow.index; win.confirmOne(prow.modelData); }
              }
              TapHandler {
                acceptedModifiers: Qt.ControlModifier
                onTapped: win.rowClick(prow.index, Qt.ControlModifier)
              }
              TapHandler {
                acceptedModifiers: Qt.ShiftModifier
                onTapped: win.rowClick(prow.index, Qt.ShiftModifier)
              }
              // a right click marks, or unmarks — the pointer's shift+space
              TapHandler {
                acceptedButtons: Qt.RightButton
                onTapped: { win.sel = prow.index; win.toggleMark(prow.modelData); keys.forceActiveFocus(); }
              }
              // resting here: a peek at it (win.peekAt, the Bubble above)
              HoverHandler {
                onHoveredChanged: hovered ? win.peekAt(prow, prow.modelData)
                  : win.peekRow === prow ? win.peekAt(null, null) : undefined
              }
            }

            Text {
              anchors.centerIn: parent
              visible: pkgList.count === 0 && !searchProc.running
              text: win.query !== "" ? "nothing matches" : "nothing here"
              color: Zenon.accentMuted
              font.family: Zenon.face
              font.weight: Font.Bold
              font.pixelSize: Zenon.px(17)
            }
          }

          ListView {
            id: updList
            ScrollRail {
              target: updList
              // Against the pane's edge, not the list's 8 in from it.
              parent: left
              anchors.right: parent.right
              anchors.top: updList.top
              anchors.bottom: updList.bottom
            }
            ElasticScroll { view: updList }
            visible: win.tab === "updates"
            anchors.fill: parent
            anchors.margins: 8
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: win.updateRows
            delegate: Item {
              id: urow
              required property var modelData
              required property int index
              width: updList.width - 14
              height: 28
              readonly property bool marked: !urow.modelData.head && !!win.umarks[urow.modelData.u.name]
              Rectangle {
                anchors.fill: parent
                radius: Zenon.windowRadius
                visible: !urow.modelData.head
                // see the packages' rows: a cursor on a marked row deepens
                // it and rings it in cyan
                color: urow.marked ? Qt.rgba(Zenon.yellow.r, Zenon.yellow.g, Zenon.yellow.b, urow.index === win.usel ? 0.22 : 0.10)
                  : urow.index === win.usel ? Zenon.menuHi : "transparent"
                border.width: urow.index === win.usel ? 1 : 0
                border.color: urow.marked ? Zenon.cyan : Zenon.border
              }
              Text {
                visible: urow.modelData.head
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: (urow.modelData.flatpak ? "\uF324" : urow.modelData.aur ? "" : "") + "  " + urow.modelData.label
                  + "  " + urow.modelData.n
                color: urow.modelData.flatpak ? Ceres.ink.flat : urow.modelData.aur ? Ceres.ink.aur : Ceres.ink.repo
                font.family: Zenon.face
                font.weight: Font.Bold
                font.pixelSize: Zenon.px(16)
              }
              Text {
                visible: urow.marked
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: "\uF062"
                color: Zenon.yellow
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.pixelSize: Zenon.px(15)
              }
              ChangeRow {
                grow: 2
                visible: !urow.modelData.head
                anchors.left: parent.left
                anchors.leftMargin: 32
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                u: urow.modelData.head ? null : urow.modelData.u
              }
              TapHandler {
                enabled: !urow.modelData.head
                acceptedModifiers: Qt.NoModifier
                onTapped: win.updateClick(urow.index, 0)
                onDoubleTapped: { win.usel = urow.index; win.confirmUpdates([urow.modelData]); }
              }
              TapHandler {
                enabled: !urow.modelData.head
                acceptedModifiers: Qt.ControlModifier
                onTapped: win.updateClick(urow.index, Qt.ControlModifier)
              }
              TapHandler {
                enabled: !urow.modelData.head
                acceptedModifiers: Qt.ShiftModifier
                onTapped: win.updateClick(urow.index, Qt.ShiftModifier)
              }
              TapHandler {
                enabled: !urow.modelData.head
                acceptedButtons: Qt.RightButton
                onTapped: { win.usel = urow.index; win.toggleUmark(urow.modelData); keys.forceActiveFocus(); }
              }
            }

            Text {
              anchors.centerIn: parent
              visible: win.updateRows.length === 0
              text: Ceres.lastOk > 0 ? "up to date" : "not checked yet"
              color: Zenon.accentMuted
              font.family: Zenon.face
              font.weight: Font.Bold
              font.pixelSize: Zenon.px(17)
            }
          }
        }

        Rectangle {
          id: divider
          visible: !left.alone
          anchors.left: left.right
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          width: 1
          color: Zenon.border
        }

        // ── the row, described ──────────────────────────────────────────
        Flickable {
          id: infoPane
          ScrollRail {
            target: infoPane
            // Against the window's edge, not the pane's 16 in from it.
            parent: browse
            anchors.right: parent.right
            anchors.top: infoPane.top
            anchors.bottom: infoPane.bottom
          }
          visible: !left.alone
          anchors.left: divider.right
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          anchors.margins: 16
          clip: true
          contentHeight: infoCol.implicitHeight
          boundsBehavior: Flickable.StopAtBounds
          ElasticScroll { view: infoPane }

          Column {
            id: infoCol
            width: infoPane.width - 14
            spacing: 8
            visible: !!win.info && win.info.fields.length > 0

            Text {
              width: parent.width
              wrapMode: Text.Wrap
              text: win.info ? (win.info.map["Name"] || "") : ""
              color: Zenon.white
              font.family: Zenon.face
              font.weight: Font.Bold
              font.pixelSize: Zenon.px(24)
            }
            Text {
              width: parent.width
              wrapMode: Text.Wrap
              text: win.info ? (win.info.map["Description"] || "") : ""
              color: Zenon.accentKey
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(17)
              bottomPadding: 10
            }

            Repeater {
              model: win.info ? win.info.fields.filter(f =>
                f[0] !== "Name" && f[0] !== "Description" && f[1] !== "" && f[1] !== "None") : []
              delegate: Row {
                id: frow
                required property var modelData
                width: infoCol.width
                spacing: 12
                readonly property bool link: /^https?:\/\//.test(frow.modelData[1])
                Text {
                  width: 150
                  text: frow.modelData[0]
                  color: Zenon.accentMuted
                  font.family: Zenon.face
                  font.weight: Zenon.weight
                  font.pixelSize: Zenon.px(16)
                }
                Text {
                  width: frow.width - 162
                  wrapMode: Text.Wrap
                  text: frow.modelData[1]
                  color: frow.link ? (linkHov.hovered ? Zenon.white : Zenon.blue) : Zenon.white
                  font.family: Zenon.face
                  font.weight: Zenon.weight
                  font.pixelSize: Zenon.px(16)
                  HoverHandler { id: linkHov; enabled: frow.link; cursorShape: Qt.PointingHandCursor }
                  TapHandler {
                    enabled: frow.link
                    onTapped: Quickshell.execDetached(["xdg-open", frow.modelData[1]])
                  }
                }
              }
            }

            // ── what needs it, and what it put on disk ──────────────────
            // Installed packages only; see Cer.extrasCommand. Headed like
            // terminus' sidebar sections and History's days.
            component InfoHead: Column {
              id: ih
              property string label: ""
              // a head that is also the toggle of the list under it: a
              // chevron beside the title, and the title takes the click
              property bool foldable: false
              property bool open: false
              signal toggle()
              width: infoCol.width
              topPadding: 14
              spacing: 7
              Rectangle { width: ih.width; height: 1; color: Zenon.border }
              Row {
                spacing: 8
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: ih.label
                  color: ih.foldable && ihHov.hovered ? Zenon.white : Zenon.accentKey
                  font.family: Zenon.face
                  font.weight: Font.Bold
                  font.pixelSize: Zenon.px(15)
                  font.letterSpacing: 1.2
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  visible: ih.foldable
                  text: ih.open ? "\uF078" : "\uF054"
                  color: ihHov.hovered ? Zenon.white : Zenon.cyan
                  font.family: Zenon.face
                  font.weight: Zenon.weight
                  font.pixelSize: Zenon.px(12)
                }
                HoverHandler { id: ihHov; enabled: ih.foldable; cursorShape: Qt.PointingHandCursor }
                TapHandler { enabled: ih.foldable; onTapped: ih.toggle() }
              }
            }
            InfoHead {
              visible: !!win.extras
              label: !win.extras ? "" : win.extras.rdeps.length === 0 ? "NEEDED BY NOTHING"
                : "NEEDED BY  " + win.extras.rdeps.length
            }
            // EACH ONE A WAY THERE: a chip per package, and a click on one
            // opens it in Packages — following a dependency up the tree is
            // what the list is read for. Past forty, the rest as a count.
            Flow {
              visible: !!win.extras && win.extras.rdeps.length > 0
              width: infoCol.width
              spacing: 6
              Repeater {
                model: win.extras ? win.extras.rdeps.slice(0, 40) : []
                delegate: Rectangle {
                  id: chip
                  required property string modelData
                  width: chipWord.implicitWidth + 16
                  height: 24
                  radius: 12
                  color: chipHov.hovered ? Zenon.headBg : "transparent"
                  border.width: 1
                  border.color: chipHov.hovered ? Zenon.accentKey : Zenon.border
                  Text {
                    id: chipWord
                    anchors.centerIn: parent
                    text: chip.modelData
                    color: chipHov.hovered ? Zenon.white : Zenon.accentKey
                    font.family: Zenon.face
                    font.weight: Zenon.weight
                    font.pixelSize: Zenon.px(14)
                  }
                  HoverHandler { id: chipHov; cursorShape: Qt.PointingHandCursor }
                  TapHandler { onTapped: win.jumpTo(chip.modelData) }
                }
              }
              Text {
                visible: !!win.extras && win.extras.rdeps.length > 40
                height: 24
                verticalAlignment: Text.AlignVCenter
                text: win.extras ? "and " + (win.extras.rdeps.length - 40) + " more" : ""
                color: Zenon.accentMuted
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.pixelSize: Zenon.px(14)
              }
            }
            InfoHead {
              visible: !!win.extras && win.extras.files.length > 0
              label: !win.extras ? "" : "FILES  " + win.extras.files.length
              // FOLDED when there are many: a package's file list is the
              // longest thing in the pane and the least often wanted, and it
              // pushed everything worth scrolling for out of reach. A handful
              // shows as it is; more waits behind the head, which opens it
              // and folds it again.
              foldable: !!win.extras && win.extras.files.length > 8
              open: win.filesOpen
              onToggle: win.filesOpen = !win.filesOpen
            }
            Column {
              visible: !!win.extras && win.extras.files.length > 0
                && (win.extras.files.length <= 8 || win.filesOpen)
              width: infoCol.width
              spacing: 2
              Repeater {
                model: win.extras ? win.extras.files.slice(0, 60) : []
                delegate: Text {
                  required property string modelData
                  width: infoCol.width
                  elide: Text.ElideMiddle
                  text: modelData
                  color: Zenon.accentKey
                  font.family: Zenon.faceFixed
                  font.weight: Zenon.weight
                  font.pixelSize: Zenon.px(15)
                }
              }
              Text {
                visible: !!win.extras && win.extras.files.length > 60
                text: win.extras ? "+ " + (win.extras.files.length - 60) + " more" : ""
                color: Zenon.accentMuted
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.pixelSize: Zenon.px(15)
              }
            }
          }

          Text {
            anchors.centerIn: parent
            visible: !win.info || win.info.fields.length === 0
            text: win.current ? "…" : ""
            color: Zenon.accentMuted
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(17)
          }
        }
      }

      // ── review ──────────────────────────────────────────────────────
      Item {
        visible: win.face === "review"
        anchors.fill: parent
        anchors.margins: 16

        Text {
          id: reviewHead
          anchors.left: parent.left
          anchors.top: parent.top
          text: (win.aurTargets[win.reviewAt] || "") + "  —  "
            + (!win.review ? "fetching the PKGBUILD…"
              : win.review.kind === "same" ? "unchanged since it was last built here"
              : win.review.kind === "new" ? "never built here — the whole PKGBUILD"
              : win.review.kind === "none" ? "the AUR has no such package"
              : "changes since it was last built here")
          color: Zenon.magenta
          font.family: Zenon.face
          font.weight: Font.Bold
          font.pixelSize: Zenon.px(16)
        }
        // A Flickable over a Column, not a ListView. The lines wrap, so
        // their heights differ, and a ListView only ESTIMATES the rows it has
        // not built yet — correcting originY and contentHeight as it builds
        // them. The elastic scroll animates against those bounds, so every
        // correction nudged the text mid-scroll: the jitter. A PKGBUILD is a
        // few hundred lines at most; laid out whole, the bounds are exact.
        Flickable {
          id: reviewList
          ScrollRail {
            target: reviewList
            // Against the window's edge, not the page's 16 in from it.
            parent: reviewList.parent
            anchors.right: parent.right
            anchors.rightMargin: -parent.anchors.rightMargin
            anchors.top: reviewList.top
            anchors.bottom: reviewList.bottom
          }
          ElasticScroll { view: reviewList }
          anchors.top: reviewHead.bottom
          anchors.topMargin: 10
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          contentHeight: reviewLines.implicitHeight
          // a new review starts at its top, as the ListView's model reset did
          Connections { target: win; function onReviewChanged() { reviewList.contentY = 0; } }
          Column {
            id: reviewLines
            width: reviewList.width - 14
            Repeater {
              model: win.review ? win.review.lines : []
              delegate: Text {
                required property var modelData
                width: reviewLines.width
                wrapMode: Text.WrapAnywhere
                text: modelData.text
                color: modelData.ink === "add" ? Zenon.green : modelData.ink === "del" ? Zenon.red
                  : modelData.ink === "hunk" ? Zenon.cyan : Zenon.accentKey
                font.family: Zenon.faceCode
                font.weight: Zenon.codeWeight
                font.pixelSize: Zenon.px(15)
              }
            }
          }
        }
      }

      // ── the transaction ─────────────────────────────────────────────

      SetupView {
        id: setupView
        visible: win.face === "setup"
        anchors.fill: parent
        anchors.margins: 24
      }

      NewsView {
        grow: 2
        visible: win.face === "news"
        anchors.fill: parent
        anchors.margins: 20
      }

      TxView {
        id: txView
        grow: 2
        // asked in settleSheet instead
        inlineSettle: false
        visible: win.face === "tx"
        anchors.fill: parent
        anchors.margins: 20
      }
    }
  }

  // What the keys do, for whatever is on screen.
  readonly property var hintRows: {
    if (win.authUp) return [["return", "confirm"], ["esc", "cancel"]];
    if (win.settleUp)
      return (txView.settleInfo.providers.length ? [["\u2190 \u2192", "provider"]] : [])
        .concat(txView.settleable ? [["y", txView.settleInfo.conflicts.length ? "replace and install" : "install"]] : [])
        .concat([["t", "open in terminal"], ["esc", "cancel"]]);
    if (win.msgUp) return Ceres.txBusy ? [["shift esc", "cancel"]]
      : Ceres.txState === "failed" ? [["return", "ok"], ["t", "open in terminal"]] : [["return", "ok"]];
    switch (win.face) {

    case "news": return [["return", "continue"], ["esc", "back"]];
    case "setup": return (Ceres.deps.paru ? [["\u2190 \u2192", "paru or paru-git"]] : [])
      .concat(Ceres.flatpakAsk ? [["space", "Flatpak apps"]] : [])
      .concat([["return", Ceres.deps.missing.length || setupView.flatpak ? "install" : "done"],
               ].concat(Ceres.deps.paru ? [] : [["esc", "not now"]]));
    case "tx":
      if (Ceres.txBusy) return [["shift esc", "cancel"]];
      if (txView.settleable)
        return (txView.settleInfo.providers.length ? [["\u2190 \u2192", "provider"]] : [])
          .concat([["y", txView.settleInfo.conflicts.length ? "replace and install" : "install"],
                   ["t", "open in terminal"], ["return", "back"]]);
      return Ceres.txState === "failed"
        ? [["t", "open in terminal"], ["return", "back"]]
        : [["return", "back"]];
    case "review": return [["← →", "other packages"], ["j k", "scroll"], ["esc", "back"]];
    case "fpoff": return [["return", "remove flatpak"], ["esc", "back"]];
    case "fpget": return win.fpRemove ? [["return", "remove"], ["esc", "back"]]
      : [["\u2190 \u2192", "everyone or just you"], ["return", "install"], ["esc", "back"]];
    case "conf":
      return (configView.review && configView.review.ok ? [["return", "save"]] : []).concat([["esc", "back"]]);
    case "confirm":
      if (win.blocked) return [["esc", "back"]];
      return [["return", "go ahead"]]
        .concat(win.aurTargets.length ? [["r", "review PKGBUILD"]] : [])
        .concat([["esc", "back"]]);
    }
    if (win.tab === "store") {
      if (storeView.lightbox !== "")
        return [["\u2190 \u2192", "screenshots"], ["esc", "close"]];
      if (storeView.view === "page")
        return [["return", storeView.app && storeView.app.installed ? "open" : "get"],
                ["\u2191 \u2193", "scroll"], ["esc", "back"]];
      // Discover has no cursor: across turns the features, up and down scroll
      return (storeView.view === "discover"
        ? [["\u2190 \u2192", "featured"], ["\u2191 \u2193", "scroll"], ["return", "open featured"]]
        : [["\u2190 \u2192 \u2191 \u2193", "move"], ["return", "app page"], ["ctrl return", "get / open"]])
        .concat([["alt \u2191 \u2193", "sections"]])
        .concat(win.typing ? (win.squery !== "" ? [["esc", "done typing"]] : []) : [["/", "search"]])
        .concat([["ctrl tab", "next"]]);
    }
    if (win.tab === "history")
      return (win.wayBack ? [["return", "go back to " + win.wayBack.version]] : [])
        .concat(win.hevent && !win.hevent.flatpak ? [["ctrl z", "undo this transaction"]] : [])
        .concat(win.typing ? [] : [["j k", "move"], ["/", "filter"]])
        .concat([["ctrl tab", "next"]]).concat(win.hquery === "" ? [] : [["esc", win.typing ? "done" : "clear"]]);
    if (win.tab === "maintenance")
      return [["j k", "choose"], ["return", "do it"], ["r", "recheck"], ["ctrl tab", "next"]];
    if (win.tab === "settings")
      return configView.hints.concat([["ctrl tab", "next"]]);
    if (win.tab === "updates")
      return Ceres.total === 0 ? [["ctrl r", "check"], ["ctrl tab", "next"]]
        : [["space", "mark"], ["ctrl a", "mark all"], ["return", win.umarkCount ? "update marked" : "update this"],
           ["ctrl return", "update all"], ["ctrl r", "check"], ["ctrl tab", "next"]];
    return [[win.typing ? "tab" : "space", "mark"]]
      .concat(win.typing ? (win.query !== "" || win.markCount > 0 ? [["esc", "done typing"]] : []) : [["/", "search"]])
      .concat([["ctrl a", "mark all"], ["return", win.markCount > 0 ? "review" : "install / remove"]])
      .concat(win.markCount > 0 ? [["ctrl d", "clear"]] : [])
      .concat([["ctrl s", "installed"], ["ctrl tab", "updates"]]);
  }

  // ── the foot ────────────────────────────────────────────────────────────
  // On the hint strip's ground, with its hairline — the same strip lexi,
  // ideo, zeus and folio stand their keys on.
  Item {
    id: foot
    anchors.bottom: parent.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    height: 40   // the window feet's height (clio, calypso, delphi); 50 stood too tall, 2026-10-17

    // see-through: the lists rise out of it — see the stage's ScrollEdges
    Rectangle { anchors.fill: parent; color: Zenon.hintFrostBg }
    Rule { anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right }


    // The keys, centered on the window — at the left once a button joins
    // them, and never into it: what does not fit before the buttons is
    // dropped from the end of the list (see HintRow.maxWidth), which is why
    // hintRows puts the keys you need most first.
    HintRow {
      id: footHints
      rows: win.hintRows
      anchors.verticalCenter: parent.verticalCenter
      // Centered when the strip is only keys; at the left the moment a button
      // joins it, so keys and buttons read as two ends of one strip rather
      // than a row that shifts off-center to make room. (A Row holding only
      // hidden children is zero wide.)
      x: footBtns.width > 0 ? 16 : Math.round((foot.width - width) / 2)
      maxWidth: foot.width - 32 - (footBtns.width > 0 ? footBtns.width + 12 + 24 : 0)
    }

    Row {
      id: footBtns
      anchors.right: parent.right
      anchors.rightMargin: 12
      anchors.verticalCenter: parent.verticalCenter
      spacing: 8

      DialogButton {
        visible: win.face === "setup"
        // only the Flatpak question left, answered no: nothing to install
        label: Ceres.deps.missing.length || setupView.flatpak ? "Install" : "Done"
        ink: Zenon.cyan
        primary: true
        onClicked: Ceres.setup(setupView.choice, setupView.flatpak)
      }
      DialogButton {
        visible: win.face === "browse" && Ceres.setupNeeded
        label: "Set up"
        ink: Zenon.yellow
        onClicked: win.showSetup = true
      }
      DialogButton {
        visible: win.face === "news"
        label: "Back"
        ink: Zenon.accentMuted
        onClicked: Ceres.holdBack()
      }
      DialogButton {
        visible: win.face === "news"
        label: "Continue"
        ink: Zenon.cyan
        primary: true
        onClicked: Ceres.passNews()
      }
      DialogButton {
        visible: win.face === "tx" && txView.settleable && !win.settleUp
        label: txView.settling && txView.settleInfo.conflicts.length ? "Replace and install" : "Install"
        ink: Zenon.cyan
        primary: true
        onClicked: txView.settle()
      }
      DialogButton {
        visible: win.face === "tx" && Ceres.txState === "failed"
        label: "Open in terminal"
        ink: Zenon.yellow
        onClicked: Ceres.txInTerminal()
      }
      DialogButton {
        visible: win.face === "tx" && !Ceres.txBusy
        label: "Back"
        ink: Zenon.accentMuted
        onClicked: Ceres.txClear()
      }
      DialogButton {
        visible: win.face === "browse" && win.tab === "packages" && win.markCount > 0
        label: "Review " + win.markCount
        ink: Zenon.cyan
        primary: true
        onClicked: win.confirm()
      }
      DialogButton {
        visible: win.face === "browse" && win.tab === "updates" && Ceres.total > 0
        label: "Update all"
        ink: Zenon.cyan
        primary: true
        onClicked: Ceres.updateAll()
      }
    }
  }

  // ── the password sheet ──────────────────────────────────────────────────
  // Behind it everything stops: the shield swallows clicks, the wheel and
  // hover, and a click away from the card cancels, as Esc does.
  Item {
    z: 30
    anchors.fill: parent
    visible: win.authUp || passSheet.cardInk > 0.01

    InputShield {
      visible: win.authUp
      onClicked: win.cancelAuth()
    }

    Sheet {
      backdrop: stage   // frosted over it — see morpheus/Sheet
      id: passSheet
      shown: win.authUp
      // from the top edge of the window, over the head as well as the body
      fromTop: 0
      cardW: 460
      cardH: field.implicitHeight + (field.purpose !== "" ? 22 : 0) + 20 + passBtns.height + 14

      PasswordField {
        grow: 2
        authSource: Ceres
        id: field
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: field.implicitHeight + (field.purpose !== "" ? 22 : 0) + 20
        purpose: Ceres.nextLabel
        onSubmitted: (p) => Ceres.upgradeAll(p)
        onCancelled: win.cancelAuth()
      }
      Row {
        id: passBtns
        anchors.top: field.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 8
        DialogButton {
          label: "Cancel"
          ink: Zenon.accentMuted
          onClicked: win.cancelAuth()
        }
        DialogButton {
          label: "Unlock"
          ink: Zenon.cyan
          primary: field.pw !== ""
          ready: field.pw !== ""
          onClicked: { const p = field.pw; field.pw = ""; Ceres.upgradeAll(p); }
        }
      }
    }
  }

  // ── the message sheet ───────────────────────────────────────────────────
  Item {
    z: 20
    anchors.fill: parent
    visible: win.msgUp || msgSheet.cardInk > 0.01

    InputShield {
      visible: win.msgUp
      onClicked: Ceres.txClear()
    }

    Sheet {
      backdrop: stage   // frosted over it — see morpheus/Sheet
      id: msgSheet
      shown: win.msgUp
      fromTop: 0
      cardW: 540
      cardH: msgCol.implicitHeight + 36

      Column {
        id: msgCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 18
        spacing: 8
        Text {
          width: parent.width
          wrapMode: Text.Wrap
          horizontalAlignment: Text.AlignHCenter
          text: {
            if (Ceres.txBusy) return (Ceres.txPhase !== "" && Ceres.txPhase !== "Starting")
              ? Ceres.txPhase : (Ceres.txState === "auth" ? "Authenticating" : "Working");
            if (Ceres.txState === "failed") return Ceres.txError;
            // the tool's own last word; "Done" if it said nothing worth repeating
            const l = Cer.summaryLine ? Cer.summaryLine(Ceres.txLog) : "";
            return l !== "" ? l.charAt(0).toUpperCase() + l.slice(1) : "Done";
          }
          color: Ceres.txState === "failed" ? Zenon.red : Zenon.white
          font.family: Zenon.face
          font.weight: Font.Bold
          font.pixelSize: Zenon.px(17)
        }
        // HOW FAR, when the job says (user, 2026-10-15): a Flatpak's
        // download — runtimes and all — reported as the whole job's share,
        // on the job page's own fill
        Rectangle {
          visible: Ceres.txBusy && !!Ceres.txTotal
          width: parent.width
          height: visible ? 30 : 0
          radius: Zenon.windowRadius
          color: Zenon.darken(0.25)
          border.width: 1
          border.color: Zenon.border
          clip: true
          Term.ProgressFill {
            anchors.fill: parent
            anchors.margins: 1
            radius: Zenon.windowRadius - 1
            frac: Ceres.txTotal ? Ceres.txTotal.frac : 0
            ink: Zenon.cyan
          }
          Text {
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: Ceres.txTotal ? Math.round(Ceres.txTotal.frac * 100) + "%" : ""
            color: Zenon.white
            font.family: Zenon.face
            font.weight: Font.Bold
            font.features: { "tnum": 1 }
            font.pixelSize: Zenon.px(14)
          }
          Text {
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: !Ceres.txTotal ? "" : [Ceres.txTotal.rate, Ceres.txTotal.eta].filter(x => x).join("  \u00B7  ")
            color: Zenon.accentKey
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.features: { "tnum": 1 }
            font.pixelSize: Zenon.px(14)
          }
        }
        // while it runs, the latest thing it said
        Text {
          visible: Ceres.txBusy
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
          text: Ceres.txLog.length ? Ceres.txLog[Ceres.txLog.length - 1] : ""
          color: Zenon.accentKey
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(15)
        }
        Text {
          visible: !Ceres.txBusy && Ceres.txDisk !== ""
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: Ceres.txDisk
          color: Zenon.accentKey
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(15)
        }
        // its answer, in the card rather than in the window's foot
        Row {
          visible: !Ceres.txBusy
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: 8
          topPadding: 6
          DialogButton {
            visible: Ceres.txState === "failed"
            label: "Open in terminal"
            ink: Zenon.yellow
            onClicked: Ceres.txInTerminal()
          }
          DialogButton {
            label: "OK"
            ink: Zenon.cyan
            primary: true
            onClicked: Ceres.txClear()
          }
        }
      }
    }
  }

  // ── the question paru could not ask — see settleUp ──────────────────────
  Item {
    z: 20
    anchors.fill: parent
    visible: win.settleUp || settleSheet.cardInk > 0.01

    InputShield {
      visible: win.settleUp
      onClicked: win.settleAside = true
    }

    Sheet {
      backdrop: stage   // frosted over it — see morpheus/Sheet
      id: settleSheet
      shown: win.settleUp
      fromTop: 0
      cardW: Math.min(620, win.width - 60)
      cardH: settleCol.implicitHeight + 40

      Column {
        id: settleCol
        readonly property var info: txView.settleInfo
        readonly property var conflicts: settleCol.info ? settleCol.info.conflicts : []
        readonly property var providers: settleCol.info ? settleCol.info.providers : []
        readonly property var gone: {
          const out = [];
          for (const c of settleCol.conflicts) for (const r of c.replaces) if (out.indexOf(r) < 0) out.push(r);
          return out;
        }
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 20
        spacing: 10

        Text {
          width: parent.width
          wrapMode: Text.Wrap
          text: settleCol.gone.length === 1 && txView.settleable ? "Replace " + settleCol.gone[0] + "?"
            : settleCol.conflicts.length ? "Packages in conflict" : "Which provider?"
          color: Zenon.white
          font.family: Zenon.face
          font.weight: Font.Bold
          font.pixelSize: Zenon.px(19)
        }
        Text {
          width: parent.width
          wrapMode: Text.Wrap
          text: !settleCol.conflicts.length
            ? "More than one package can provide this. Pick one and it is installed with it."
            : txView.settleable
              ? "What is coming in cannot be installed next to what you have. Going ahead removes "
                + (settleCol.gone.length === 1 ? "it" : "them") + " and installs the replacement in one transaction."
              : "Two of the packages coming in conflict with each other. Pick another provider, or settle it in a terminal."
          color: Zenon.accentKey
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(15)
        }

        // every replacement: what comes in, and what goes
        Repeater {
          model: settleCol.conflicts
          delegate: Text {
            required property var modelData
            width: settleCol.width
            wrapMode: Text.Wrap
            textFormat: Text.StyledText
            text: "<font color='" + Zenon.green + "'>+ " + modelData.pkg + "</font>"
              + (modelData.inner
                ? "  <font color='" + Zenon.accentMuted + "'>conflicts with</font>  "
                  + "<font color='" + Zenon.yellow + "'>" + modelData.replaces.join(", ") + "</font>"
                : "  <font color='" + Zenon.accentMuted + "'>replaces</font>  "
                  + "<font color='" + Zenon.red + "'>\u2212 " + modelData.replaces.join(", ") + "</font>")
            color: Zenon.ink
            font.family: Zenon.face
            font.weight: Font.Bold
            font.pixelSize: Zenon.px(16)
          }
        }

        // who still leans on what goes (Ceres.txNeeds, pacman's Required By)
        Repeater {
          model: settleCol.gone.filter((g) => (Ceres.txNeeds[g] || []).length > 0)
          delegate: Text {
            required property string modelData
            width: settleCol.width
            wrapMode: Text.Wrap
            text: modelData + " is required by " + Ceres.txNeeds[modelData].join(", ")
              + ". They stay only if the replacement provides what they need; pacman stops if it does not."
            color: Zenon.yellow
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(14)
          }
        }

        // a provider menu each, as the suite's switch
        Repeater {
          model: settleCol.providers
          delegate: Row {
            id: provLine
            required property var modelData
            spacing: 10
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: provLine.modelData.name + " from"
              color: Zenon.accentKey
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(15)
            }
            Term.Segments {
              anchors.verticalCenter: parent.verticalCenter
              textSize: Zenon.px(14)
              pad: 22
              options: provLine.modelData.options.map((o) => [o, o])
              current: txView.pickOf(provLine.modelData)
              onChose: (v) => txView.pick(provLine.modelData.name, v)
            }
          }
        }

        Row {
          anchors.right: parent.right
          spacing: 8
          topPadding: 8
          DialogButton {
            label: "Open in terminal"
            ink: Zenon.yellow
            onClicked: Ceres.txInTerminal()
          }
          DialogButton {
            label: "Cancel"
            onClicked: win.settleAside = true
          }
          DialogButton {
            visible: txView.settleable
            label: settleCol.conflicts.length ? "Replace and install" : "Install"
            ink: Zenon.cyan
            primary: true
            onClicked: txView.settle()
          }
        }
      }
    }
  }

  // ── pacman.conf's review ────────────────────────────────────────────────
  // diff's own account of the edits, and pacman-conf's verdict on the file
  // they make. Save only when pacman-conf has nothing new to say.
  Item {
    anchors.fill: parent
    z: 10
    visible: win.confUp || confSheet.cardInk > 0.01

    InputShield {
      visible: win.confUp
      onClicked: win.overlay = ""
    }

    Sheet {
      backdrop: stage   // frosted over it — see morpheus/Sheet
      id: confSheet
      shown: win.confUp
      fromTop: 0
      cardW: Math.min(1000, win.width - 60)
      readonly property var rv: configView.review
      readonly property var diffLines: confSheet.rv ? Cer.readReview(confSheet.rv.diff).lines : []
      cardH: Math.min(win.height - 90,
        70 + (confSheet.rv && !confSheet.rv.ok ? 30 + confSheet.rv.problems.length * 22 : 0)
        + Math.max(3, confSheet.diffLines.length) * 21 + confBtns.height + 44)

      Item {
        anchors.fill: parent
        anchors.margins: 16
        anchors.bottomMargin: 16 + confBtns.height + 12

        Text {
          id: confTitle
          text: "pacman.conf  <font color='" + Zenon.accentMuted + "'>"
            + configView.changes + (configView.changes === 1 ? " line changed" : " lines changed") + "</font>"
          textFormat: Text.StyledText
          color: Zenon.white
          font.family: Zenon.face
          font.weight: Font.Bold
          font.pixelSize: Zenon.px(20)
        }
        Text {
          id: confVerdict
          anchors.top: confTitle.bottom
          anchors.topMargin: 6
          text: !confSheet.rv ? "Checking with pacman-conf\u2026"
            : confSheet.rv.ok ? "pacman-conf reads it cleanly. The file you have now is kept as pacman.conf.ceres-bak."
            : "pacman-conf objects \u2014 fix these before saving:"
          color: !confSheet.rv ? Zenon.accentMuted : confSheet.rv.ok ? Zenon.green : Zenon.red
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(15)
        }
        Column {
          id: confProblems
          anchors.top: confVerdict.bottom
          anchors.topMargin: 4
          width: parent.width
          Repeater {
            model: confSheet.rv && !confSheet.rv.ok ? confSheet.rv.problems : []
            delegate: Text {
              required property string modelData
              width: confProblems.width
              elide: Text.ElideRight
              text: modelData.replace(/config file [^,]*, /, "")
              color: Zenon.red
              font.family: Zenon.faceCode
              font.weight: Zenon.codeWeight
              font.pixelSize: Zenon.px(14)
            }
          }
        }
        ListView {
          id: confDiff
          ScrollRail {
            target: confDiff
            // Against the card's edge, not the body's 16 in from it.
            parent: confDiff.parent
            anchors.right: parent.right
            anchors.rightMargin: -parent.anchors.rightMargin
            anchors.top: confDiff.top
            anchors.bottom: confDiff.bottom
          }
          ElasticScroll { view: confDiff }
          anchors.top: confProblems.bottom
          anchors.topMargin: 12
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          model: confSheet.diffLines
          delegate: Text {
            required property var modelData
            width: confDiff.width - 14
            height: 21
            elide: Text.ElideRight
            text: modelData.text
            color: modelData.ink === "add" ? Zenon.green : modelData.ink === "del" ? Zenon.red
              : modelData.ink === "hunk" ? Zenon.cyan : Zenon.accentKey
            font.family: Zenon.faceCode
            font.weight: Zenon.codeWeight
            font.pixelSize: Zenon.px(15)
          }
        }
      }

      Row {
        id: confBtns
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 14
        anchors.right: parent.right
        anchors.rightMargin: 16
        spacing: 8
        DialogButton {
          label: "Back"
          ink: Zenon.accentMuted
          onClicked: win.overlay = ""
        }
        DialogButton {
          label: "Save"
          ink: Zenon.cyan
          primary: !!confSheet.rv && confSheet.rv.ok
          ready: !!confSheet.rv && confSheet.rv.ok
          onClicked: win.saveConf()
        }
      }
    }
  }

  // ── one Flatpak app, in or out ──────────────────────────────────────────
  Item {
    anchors.fill: parent
    z: 10
    visible: win.fpGetUp || fpGetSheet.cardInk > 0.01

    InputShield {
      visible: win.fpGetUp
      onClicked: win.overlay = ""
    }

    Sheet {
      backdrop: stage   // frosted over it — see morpheus/Sheet
      id: fpGetSheet
      shown: win.fpGetUp
      fromTop: 0
      cardW: Math.min(720, win.width - 60)
      readonly property var a: win.fpApp
      readonly property var perms: win.fpPerms || []
      cardH: Math.min(win.height - 90, fpGetCol.implicitHeight + 36 + fpGetBtns.height + 26)

      Column {
        id: fpGetCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 18
        spacing: 14
        Row {
          spacing: 16
          StoreIcon {
            anchors.verticalCenter: parent.verticalCenter
            app: fpGetSheet.a
            size: 56
          }
          Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3
            Text {
              text: !fpGetSheet.a ? "" : (win.fpRemove ? "Remove " : "Install ") + fpGetSheet.a.name + (win.fpRemove ? "?" : "")
              color: Zenon.white
              font.family: Zenon.face
              font.weight: Font.Bold
              font.pixelSize: Zenon.px(20)
            }
            Text {
              text: win.fpRemove
                ? "Installed " + (win.fpScope === "user" ? "just for you" : "for everyone") + " from Flathub"
                : "From Flathub" + (fpGetSheet.a && fpGetSheet.a.verified ? " \u00B7 verified publisher" : "")
                  + (win.fpInfo && win.fpInfo["Download Size"]
                    ? "  \u00B7  " + win.fpInfo["Download Size"] + " download, " + win.fpInfo["Installed Size"] + " on disk" : "")
              color: Zenon.accentKey
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(15)
            }
          }
        }
        // where it goes — the last place chosen, to start with
        Term.Segments {
          visible: !win.fpRemove
          width: parent.width
          even: true
          strong: true
          textSize: Zenon.px(16)
          ink: Zenon.accentKey
          options: [["system", "For everyone", "asks for your password"],
                    ["user", "Just me", "only you \u00B7 no password"]]
          current: win.fpScope
          onChose: (v) => win.fpScope = v
        }
        // its runtime, when that comes first
        Text {
          visible: !win.fpRemove && !!win.fpRuntime
          width: parent.width
          wrapMode: Text.Wrap
          textFormat: Text.StyledText
          text: !win.fpRuntime ? "" : "<b>First, its runtime:</b> " + Cer.esc(win.fpRuntime.name || "the libraries it is built on")
            + " \u2014 " + win.fpRuntime.download + " more to download"
            + (win.fpRuntime.installed ? ", " + win.fpRuntime.installed + " on disk" : "")
            + ". Every app built on it shares it, so it comes down once."
          color: Zenon.accentKey
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(15)
        }
        // what its sandbox lets it touch, the worst first
        Text {
          visible: !win.fpRemove && win.fpPerms !== null
          width: parent.width
          wrapMode: Text.Wrap
          text: fpGetSheet.perms.length === 0 ? "Sealed: it asks for nothing beyond its window and sound."
            : "It may use: " + fpGetSheet.perms.slice(0, 5).map(p => p.text.charAt(0).toLowerCase() + p.text.slice(1)).join("; ")
              + (fpGetSheet.perms.length > 5 ? "; and " + (fpGetSheet.perms.length - 5) + " more" : "") + "."
          color: fpGetSheet.perms.some(p => p.level === "high") ? Zenon.yellow : Zenon.accentKey
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(15)
        }
        Text {
          visible: win.fpRemove
          width: parent.width
          wrapMode: Text.Wrap
          text: "Any runtime nothing else needs goes with it."
          color: Zenon.accentKey
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(15)
        }
        Check {
          visible: win.fpRemove && win.fpDataSize !== ""
          lit: win.fpDeleteData
          label: "Also delete what it kept \u2014 ~/.var/app/" + (fpGetSheet.a ? fpGetSheet.a.pkg : "") + ", " + win.fpDataSize
          onToggled: win.fpDeleteData = !win.fpDeleteData
        }
      }

      Row {
        id: fpGetBtns
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 14
        anchors.right: parent.right
        anchors.rightMargin: 16
        spacing: 8
        DialogButton {
          label: "Back"
          ink: Zenon.accentMuted
          onClicked: win.overlay = ""
        }
        DialogButton {
          label: win.fpRemove ? "Remove" : "Install"
          ink: win.fpRemove ? Zenon.red : Zenon.cyan
          primary: true
          ready: !Ceres.txBusy
          onClicked: win.goFlatpak()
        }
      }
    }
  }

  // ── Flatpak, taken away — what goes with it ─────────────────────────────
  Item {
    anchors.fill: parent
    z: 10
    visible: win.fpUp || fpSheet.cardInk > 0.01

    InputShield {
      visible: win.fpUp
      onClicked: win.overlay = ""
    }

    Sheet {
      backdrop: stage   // frosted over it — see morpheus/Sheet
      id: fpSheet
      shown: win.fpUp
      fromTop: 0
      cardW: Math.min(720, win.width - 60)
      readonly property var apps: Ceres.flatpakApps
      cardH: Math.min(win.height - 90, 190 + (fpSheet.apps.length ? 34 + Math.min(12, fpSheet.apps.length) * 26 : 0)
        + fpBtns.height + 30)

      Column {
        anchors.fill: parent
        anchors.margins: 18
        anchors.bottomMargin: 18 + fpBtns.height + 12
        spacing: 10
        Text {
          text: "Remove Flatpak?"
          color: Zenon.white
          font.family: Zenon.face
          font.weight: Font.Bold
          font.pixelSize: Zenon.px(20)
        }
        Text {
          width: parent.width
          wrapMode: Text.Wrap
          // everything that goes, said before it goes (user, 2026-10-15)
          text: (fpSheet.apps.length === 0 ? "No Flatpak apps are installed. "
            : (fpSheet.apps.length === 1 ? "This app goes" : "These " + fpSheet.apps.length + " apps go")
              + ", with every runtime. ")
            + "Then Flathub as a source, the flatpak package, and what Flatpak keeps itself \u2014 its stores in "
            + "/var/lib/flatpak and ~/.local/share/flatpak, and its cache \u2014 so nothing of it is left."
          color: Zenon.accentKey
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(15)
        }
        Column {
          visible: fpSheet.apps.length > 0
          width: parent.width
          topPadding: 4
          spacing: 4
          Repeater {
            model: fpSheet.apps.slice(0, 12)
            delegate: Row {
              required property var modelData
              width: parent.width
              height: 22
              spacing: 10
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "\uF324"
                color: Zenon.red
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.pixelSize: Zenon.px(14)
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 150
                elide: Text.ElideRight
                text: modelData.name
                color: Zenon.white
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.pixelSize: Zenon.px(15)
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.scope === "user" ? "just you" : "everyone"
                color: Zenon.accentMuted
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.pixelSize: Zenon.px(14)
              }
            }
          }
          Text {
            visible: fpSheet.apps.length > 12
            text: "and " + (fpSheet.apps.length - 12) + " more"
            color: Zenon.accentMuted
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(14)
          }
        }
        Check {
          visible: win.fpDataSize !== ""
          lit: win.fpDeleteData
          label: "Also delete what the apps kept \u2014 ~/.var/app, " + win.fpDataSize
          onToggled: win.fpDeleteData = !win.fpDeleteData
        }
      }

      Row {
        id: fpBtns
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 14
        anchors.right: parent.right
        anchors.rightMargin: 16
        spacing: 8
        DialogButton {
          label: "Back"
          ink: Zenon.accentMuted
          onClicked: win.overlay = ""
        }
        DialogButton {
          label: fpSheet.apps.length ? "Remove Flatpak and " + fpSheet.apps.length + (fpSheet.apps.length === 1 ? " app" : " apps")
            : "Remove Flatpak"
          ink: Zenon.red
          primary: true
          ready: !Ceres.txBusy
          onClicked: win.removeFlatpak()
        }
      }
    }
  }

  // ── the confirm sheet ───────────────────────────────────────────────────
  // What a change will do, over the list it was chosen from — the figures,
  // the two cards, and the answer, all in the card.
  Item {
    anchors.fill: parent
    z: 10
    visible: win.confirmUp || confirmSheet.cardInk > 0.01

    InputShield {
      visible: win.confirmUp
      onClicked: win.overlay = ""
    }

    Sheet {
      backdrop: stage   // frosted over it — see morpheus/Sheet
      id: confirmSheet
      shown: win.confirmUp
      fromTop: 0
      cardW: Math.min(1000, win.width - 60)
      // as tall as the longer card needs, within the window
      cardH: Math.min(win.height - 90,
        76 + 16 + (win.partial ? 70 : 0) + 60
        + Math.max(confirmView.installRows.length, confirmView.removeRows.length) * 28
        + Math.max(installCard.visible ? installCard.extraH : 0, removeCard.visible ? removeCard.extraH : 0)
        + 30 + confirmBtns.height + 12)

      // ── confirm ─────────────────────────────────────────────────────
      // Three figures across the top — what changes, what downloads, what the
      // disk does — and the change itself underneath as two cards, Install
      // and Remove, each with its targets first and what comes along with them
      // after. One card takes the whole width when there is only one side.
      Item {
        id: confirmView
        anchors.fill: parent
        anchors.margins: 16
        anchors.bottomMargin: 16 + confirmBtns.height + 12

        readonly property var p: win.plan
        readonly property bool undoing: win.confirmKind === "undo"
        readonly property var u: win.undo
        readonly property int inN: undoing ? (u ? u.back.length : 0)
          : (p ? p.install.length : 0) + win.aurTargets.length
        readonly property int outN: undoing ? (u ? u.remove.length : 0) : p ? p.remove.length : 0

        // entries for a card: { name, version, size, target, aur, head }
        readonly property var installRows: {
          if (undoing) {
            const out = [];
            if (!u) return out;
            for (const b of u.back)
              out.push({ name: b.name, version: (b.now ? b.now + " \u2192 " + b.version : b.version + " \u00b7 back")
                           + (b.url ? " \u00b7 from the archive" : ""),
                         size: 0, target: true });
            if (u.skipped.length) {
              out.push({ head: true, name: u.skipped.length === 1 ? "1 left as it is" : u.skipped.length + " left as they are" });
              for (const k of u.skipped) out.push({ name: k.name, version: k.why, size: 0, target: false });
            }
            return out;
          }
          const out = [];
          const byName = {};
          if (p) for (const e of p.install) byName[e.name] = e;
          for (const n of win.installNames) {
            const t = win.targets[n], e = byName[n];
            out.push({ name: n, version: (t.from ? t.from + " \u2192 " : "") + (e ? e.version : (t.version || "")),
                       size: e ? e.size : 0, target: true, aur: t.aur });
          }
          const deps = p ? p.install.filter(e => win.installNames.indexOf(e.name) < 0) : [];
          if (deps.length) {
            out.push({ head: true, name: deps.length === 1 ? "1 dependency" : deps.length + " dependencies" });
            for (const e of deps) out.push({ name: e.name, version: e.version, size: e.size, target: false });
          }
          return out;
        }
        readonly property var removeRows: {
          if (undoing) return u ? u.remove.map(r => ({ name: r.name, version: r.version, size: 0, target: true })) : [];
          const out = [];
          const byName = {};
          if (p) for (const e of p.remove) byName[e.name] = e;
          for (const n of win.removeNames) {
            const e = byName[n], t = win.targets[n];
            out.push({ name: n, version: e ? e.version : (t.version || ""),
                       size: e ? e.size : t.size, target: true });
          }
          const extra = p ? p.remove.filter(e => win.removeNames.indexOf(e.name) < 0) : [];
          if (extra.length) {
            out.push({ head: true, name: extra.length === 1 ? "1 no longer needed" : extra.length + " no longer needed" });
            for (const e of extra) out.push({ name: e.name, version: e.version, size: e.size, target: false });
          }
          return out;
        }

        component Stat: Rectangle {
          id: stat
          property string label: ""
          property string value: ""
          property string note: ""
          property color ink: Zenon.white
          height: 76
          radius: Zenon.windowRadius
          color: Zenon.headBg
          border.width: 1
          border.color: Zenon.border
          Column {
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            Text {
              text: stat.label
              color: Zenon.accentMuted
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(15)
            }
            Text {
              textFormat: Text.StyledText
              text: stat.value
              color: stat.ink
              font.family: Zenon.face
              font.weight: Font.Bold
              font.pixelSize: Zenon.px(24)
            }
          }
          Text {
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 10
            text: stat.note
            color: Zenon.magenta
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(14)
          }
        }

        Row {
          id: stats
          width: parent.width
          spacing: 12
          readonly property real cellW: (width - spacing * 2) / 3
          Stat {
            width: stats.cellW
            label: "Packages"
            value: win.planning ? "…"
              // a plan pacman refused has no packages in it; say what was
              // ASKED for rather than leaving the figure blank
              : win.blocked && !confirmView.undoing
                ? (win.installNames.length ? "<font color='" + Zenon.green + "'>+" + win.installNames.length + "</font>" : "")
                  + (win.installNames.length && win.removeNames.length ? "   " : "")
                  + (win.removeNames.length ? "<font color='" + Zenon.red + "'>\u2212" + win.removeNames.length + "</font>" : "")
              : (confirmView.inN ? "<font color='" + Zenon.green + "'>+" + confirmView.inN + "</font>" : "")
                + (confirmView.inN && confirmView.outN ? "   " : "")
                + (confirmView.outN ? "<font color='" + Zenon.red + "'>−" + confirmView.outN + "</font>" : "")
          }
          // An undo downloads only what the archive supplies and has no size
          // plan to show, so its two figures are where the copies come from
          // and what is being left alone.
          Stat {
            width: stats.cellW
            label: confirmView.undoing ? "From the archive" : "Download"
            value: win.planning ? "…"
              : confirmView.undoing ? String(confirmView.u ? confirmView.u.back.filter(b => b.url).length : 0)
              : win.blocked ? "\u2014"
              : Cer.bytes(confirmView.p ? confirmView.p.download : 0)
            note: win.aurTargets.length ? "+ AUR sources" : ""
          }
          Stat {
            width: stats.cellW
            label: confirmView.undoing ? "Left as they are" : "Disk"
            ink: confirmView.undoing && confirmView.u && confirmView.u.skipped.length ? Zenon.yellow : Zenon.white
            value: win.planning ? "…"
              : confirmView.undoing ? String(confirmView.u ? confirmView.u.skipped.length : 0)
              : !confirmView.p ? "…"
              : win.blocked ? "\u2014"
              : Cer.signed(confirmView.p.add - confirmView.p.replace - confirmView.p.free)
            note: win.aurTargets.length ? "+ AUR builds" : ""
          }
        }

        component Card: Rectangle {
          id: card
          property string title: ""
          property color ink: Zenon.green
          property bool removing: false
          property var entries: []
          property string error: ""
          property string detail: ""
          property var reasons: []
          readonly property var blocks: Cer.blockers(card.reasons)
          // what the banner adds to the card's height, for the sheet to make
          // room for — it was sized for the rows alone, and a banner pushed
          // the card's end down over the buttons
          readonly property real extraH: banner.visible ? banner.height + 10 : 0
          radius: Zenon.windowRadius
          color: "transparent"
          border.width: 1
          border.color: Zenon.border

          Text {
            id: cardTitle
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.margins: 16
            text: card.title
            color: card.ink
            font.family: Zenon.face
            font.weight: Font.Bold
            font.pixelSize: Zenon.px(18)
          }

          // Why this side cannot happen, in pacman's words, before anything else.
          Rectangle {
            id: banner
            visible: card.error !== ""
            anchors.top: cardTitle.bottom
            anchors.topMargin: 10
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            height: visible ? bannerCol.implicitHeight + 16 : 0
            radius: Zenon.windowRadius
            color: Qt.rgba(Zenon.red.r, Zenon.red.g, Zenon.red.b, 0.12)
            border.width: 1
            border.color: Zenon.red
            Column {
              id: bannerCol
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: 8
              spacing: 3
              Text {
                width: parent.width
                wrapMode: Text.Wrap
                text: card.error
                color: Zenon.red
                font.family: Zenon.face
                font.weight: Font.Bold
                font.pixelSize: Zenon.px(16)
              }
              // pacman's line under it, quieter, for when the plain words
              // above are not the whole story
              Text {
                width: parent.width
                visible: card.detail !== "" && card.detail !== card.error
                wrapMode: Text.Wrap
                text: card.detail
                color: Zenon.accentMuted
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.pixelSize: Zenon.px(14)
              }
              Item { width: 1; height: 4; visible: card.blocks.needs.length > 0 }
              // ONE LINE PER PACKAGE IN THE WAY, not one per dependency:
              // "hyprland needs hyprcursor, libhyprcursor.so" is the thing
              // to act on, and pacman's own phrasing said it twice over.
              Repeater {
                model: card.blocks.needs.slice(0, 6)
                delegate: Text {
                  required property var modelData
                  width: bannerCol.width
                  wrapMode: Text.Wrap
                  textFormat: Text.StyledText
                  // escaped: a dependency is written with its version bound,
                  // "foo<2" or "bar>=1", and StyledText read those as tags
                  text: "<b><font color='" + Zenon.white + "'>" + Strings.escapeHtml(modelData.by) + "</font></b>"
                    + "<font color='" + Zenon.accentMuted + "'>  needs  </font>"
                    + Strings.escapeHtml(modelData.deps.join(", "))
                  color: Zenon.accentKey
                  font.family: Zenon.face
                  font.weight: Zenon.weight
                  font.pixelSize: Zenon.px(15)
                }
              }
              Repeater {
                model: card.blocks.other.slice(0, 4)
                delegate: Text {
                  required property string modelData
                  width: bannerCol.width
                  wrapMode: Text.Wrap
                  text: modelData
                  color: Zenon.accentKey
                  font.family: Zenon.face
                  font.weight: Zenon.weight
                  font.pixelSize: Zenon.px(15)
                }
              }
              Text {
                visible: card.blocks.needs.length > 6
                text: "+ " + (card.blocks.needs.length - 6) + " more"
                color: Zenon.accentMuted
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.pixelSize: Zenon.px(15)
              }
              // and what to do about it
              Text {
                width: parent.width
                visible: card.removing && card.blocks.needs.length > 0
                topPadding: 4
                wrapMode: Text.Wrap
                text: "Mark " + (card.blocks.needs.length === 1 ? card.blocks.needs[0].by
                    : card.blocks.needs.length + " packages") + " for removal as well, or leave this installed."
                color: Zenon.accentMuted
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.italic: true
                font.pixelSize: Zenon.px(14)
              }
            }
          }

          ListView {
            id: entryList
            ScrollRail {
              target: entryList
              // Against the card's edge, not the list's 12 in from it.
              parent: card
              anchors.right: parent.right
              anchors.top: entryList.top
              anchors.bottom: entryList.bottom
            }
            ElasticScroll { view: entryList }
            anchors.top: banner.visible ? banner.bottom : cardTitle.bottom
            anchors.topMargin: 10
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            anchors.bottomMargin: 8
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: card.entries
            delegate: Item {
              id: ent
              required property var modelData
              width: entryList.width - 14
              // one height for every row — see the note on the history list
              height: 28

              Text {
                visible: !!ent.modelData.head
                anchors.left: parent.left
                anchors.leftMargin: 4
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 4
                text: ent.modelData.name
                color: Zenon.accentMuted
                font.family: Zenon.face
                font.weight: Font.Bold
                font.pixelSize: Zenon.px(15)
              }

              Text {
                id: entGlyph
                visible: !ent.modelData.head
                anchors.left: parent.left
                anchors.leftMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                width: 20
                text: ent.modelData.target ? (card.removing ? "" : win.confirmKind === "update" ? "\uF062" : win.confirmKind === "undo" ? "\uF0E2" : "") : "·"
                color: ent.modelData.target ? card.ink : Zenon.accentMuted
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.pixelSize: Zenon.px(15)
              }
              Text {
                id: entName
                visible: !ent.modelData.head
                anchors.left: entGlyph.right
                anchors.verticalCenter: parent.verticalCenter
                text: ent.modelData.name
                color: ent.modelData.target ? Zenon.white : Zenon.accentKey
                font.family: Zenon.face
                font.weight: ent.modelData.target ? Font.Bold : Font.Normal
                font.pixelSize: Zenon.px(ent.modelData.target ? 17 : 16)
              }
              Text {
                visible: !ent.modelData.head
                anchors.left: entName.right
                anchors.leftMargin: 8
                anchors.right: entSize.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: ent.modelData.version || ""
                color: Zenon.accentMuted
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.pixelSize: Zenon.px(15)
              }
              // AUR: no size to show until it is built, and a way to read what
              // will build it instead
              Rectangle {
                id: aurTag
                visible: !!ent.modelData.aur
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: aurText.implicitWidth + 16
                height: 22
                radius: Zenon.windowRadius
                color: aurHov.hovered ? Qt.rgba(Zenon.magenta.r, Zenon.magenta.g, Zenon.magenta.b, 0.18) : "transparent"
                border.width: 1
                border.color: aurHov.hovered ? Zenon.magenta : Zenon.border
                Text {
                  id: aurText
                  anchors.centerIn: parent
                  text: "AUR · review"
                  color: Zenon.magenta
                  font.family: Zenon.face
                  font.weight: Zenon.weight
                  font.pixelSize: Zenon.px(14)
                }
                HoverHandler { id: aurHov }
                TapHandler { onTapped: win.openReview(win.aurTargets.indexOf(ent.modelData.name)) }
              }
              Text {
                id: entSize
                visible: !ent.modelData.head && !ent.modelData.aur
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: ent.modelData.size > 0 ? Cer.bytes(ent.modelData.size) : ""
                color: Zenon.accentMuted
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.pixelSize: Zenon.px(15)
              }
            }
          }
        }

        Rectangle {
          id: partialNote
          visible: win.partial
          anchors.top: stats.bottom
          anchors.topMargin: visible ? 12 : 0
          anchors.left: parent.left
          anchors.right: parent.right
          height: visible ? partialText.implicitHeight + 18 : 0
          radius: Zenon.windowRadius
          color: Qt.rgba(Zenon.yellow.r, Zenon.yellow.g, Zenon.yellow.b, 0.10)
          border.width: 1
          border.color: Zenon.yellow
          Text {
            id: partialText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: 12
            wrapMode: Text.Wrap
            text: "A partial upgrade: " + win.installNames.length + " of " + Ceres.total
              + " updates. Arch does not support these \u2014 a library can move ahead of the programs built against it. "
              + "Update all (ctrl \u21b5) is the safe way."
            color: Zenon.yellow
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(16)
          }
        }

        Row {
          id: cards
          anchors.top: partialNote.bottom
          anchors.topMargin: 16
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          spacing: 12
          readonly property int n: (confirmView.installRows.length ? 1 : 0) + (win.removeNames.length ? 1 : 0)
          readonly property real cardW: n > 1 ? (width - spacing) / 2 : width

          Card {
            id: installCard
            visible: confirmView.installRows.length > 0
            width: cards.cardW
            height: cards.height
            title: (win.confirmKind === "update" ? "Update  " : win.confirmKind === "undo" ? "Go back  " : "Install  ")
              + win.installNames.length
            ink: win.confirmKind === "update" ? Zenon.blue : win.confirmKind === "undo" ? Zenon.yellow : Zenon.green
            entries: confirmView.installRows
            error: confirmView.p ? confirmView.p.installError : ""
          }
          Card {
            id: removeCard
            visible: win.removeNames.length > 0
            width: cards.cardW
            height: cards.height
            title: "Remove  " + win.removeNames.length
            ink: Zenon.red
            removing: true
            entries: confirmView.removeRows
            error: confirmView.p && confirmView.p.removeError !== ""
              ? "Can\u2019t remove \u2014 " + Cer.removeHeadline(confirmView.p.removeError).replace(/^./, c => c.toLowerCase()) : ""
            detail: confirmView.p ? confirmView.p.removeError : ""
            reasons: confirmView.p ? confirmView.p.blocked : []
          }
        }
      }

      Row {
        id: confirmBtns
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 14
        anchors.right: parent.right
        anchors.rightMargin: 16
        spacing: 8
        DialogButton {
          visible: win.aurTargets.length > 0
          label: "Review PKGBUILD"
          ink: Zenon.magenta
          onClicked: win.openReview(0)
        }
        DialogButton {
          label: "Back"
          ink: Zenon.accentMuted
          onClicked: win.overlay = ""
        }
        DialogButton {
          label: "Go ahead"
          ink: Zenon.cyan
          // an undo with nothing left to take back has nothing to go ahead with
          readonly property bool empty: win.confirmKind === "undo" && !win.planning
            && win.installNames.length + win.removeNames.length === 0
          primary: !win.planning && !win.blocked && !empty
          ready: !win.planning && !win.blocked && !empty
          onClicked: win.go()
        }
      }
    }
  }
}
