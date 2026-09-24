// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// CERES — the package manager, as a window.
//
// ZENU's views, without a terminal in the way:
//
//   Updates    what is pending, with what each one is, and Update all
//   Packages   the repos and the AUR, searched as you type; mark with space
//              or tab, ↵ to see exactly what the change will do and cost
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
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import "../morpheus"
import "."
import "../oracle"
import "ceres.js" as Cer

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
  property string tab: "updates"
  // The views, in switch order: [name, label]. Round 4 adds to this.
  readonly property var tabs: [
    ["updates", Ceres.total > 0 ? "Updates  " + Ceres.total : "Updates"],
    ["packages", "Packages"],
    ["history", "History"],
    ["maintenance", win.maint && win.maintCount > 0 ? "Maintenance  " + win.maintCount : "Maintenance"],
    ["settings", configView.changes > 0 ? "Settings  " + configView.changes : "Settings"]
  ]
  // The label column of a list of [label, value, ...] fact rows (the cache's
  // and the mirrors'): as wide as the longest label, never narrower than the
  // 250 the rows used to be fixed at, so short lists keep their alignment.
  FontMetrics { id: mfFact; font.family: Zenon.face; font.pixelSize: 16 }
  function factLabelWidth(facts) {
    let w = 250;
    for (const f of facts || []) w = Math.max(w, Math.ceil(mfFact.advanceWidth(String(f[0]))));
    return w;
  }

  function showTab(t) {
    win.tab = t;
    if (t === "packages" && win.found.length === 0) win.search();
    if (t === "history") win.loadHistory();
    if (t === "maintenance") win.loadMaint();
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
  readonly property bool msgUp: win.quietJob && !win.authUp
  // how far in the sheets are, for the stage's blur
  readonly property real sheetInk: Math.max(passSheet.cardInk, msgSheet.cardInk,
                                            confirmSheet.cardInk, resultSheet.cardInk, confSheet.cardInk)
  // ONE SHEET AT A TIME. Go ahead on the confirm asks for the password, and
  // the password's sheet came up BEHIND the confirm's — the prompt was there
  // and could not be seen until the confirm was dismissed. The confirm steps
  // aside while the password is asked for, and comes back if it is cancelled.
  readonly property bool confirmUp: win.face === "confirm" && !win.authUp
  // WHAT THE PAGE IS, under whatever sheet is over it. The confirm and the
  // result are sheets now, so the page beneath them is the one they came
  // from — the list, still there, softened.
  readonly property string page: (win.face === "confirm" || win.face === "result" || win.face === "conf")
    ? "browse" : win.face
  // pacman.conf's review: a sheet over the Settings tab, like the confirm
  readonly property bool confUp: win.face === "conf" && !win.authUp
  // THE HEAD STANDS DOWN while there is nothing it could do: through
  // onboarding, and for the whole of a job — tabs and a filter over a
  // progress bar are only noise.
  readonly property bool headHidden: win.onboarding || win.face === "tx"
  function cancelAuth() {
    win.asking = false; field.pw = ""; field.failed = false;
    Ceres.txClear(); Ceres.forgetNext();
  }
  // ONBOARDING: from the setup screen through its password and its install,
  // there is no tab to switch to and nothing to filter — the head is not
  // shown until paru is here and ceres is ceres.
  readonly property bool onboarding: win.face === "setup"
    || (Ceres.deps.paru && win.face === "tx")
  readonly property string face: {
    const s = Ceres.txState;
    // a finished job that changed packages: its result is a sheet over the
    // page it was started from
    if (s === "done" && !win.quietJob) return "result";
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
  }

  function dismiss() {
    field.pw = "";
    win.asking = false;
    if (!Ceres.txBusy) Ceres.forgetNext();
    if (Ceres.txState === "done" || Ceres.txState === "authfail") Ceres.txClear();
    win.visible = false;
  }

  // ── Packages: the query, the rows, the marks ───────────────────────────
  property string query: ""
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

  function search() {
    searchProc.command = ["sh", "-c", Cer.searchCommand(win.script, win.installedOnly, win.query)];
    searchProc.running = true;
  }

  Process {
    id: searchProc
    stdout: StdioCollector {
      id: searchOut
      onStreamFinished: {
        win.found = Cer.parseRows(searchOut.text);
        win.sel = 0;
        pkgList.positionViewAtBeginning();
        win.peek();
      }
    }
  }

  // ctrl+a: every row on screen marked, or — when they all are already —
  // none of them. What is on screen, not the whole catalogue: a search for
  // "gst" and ctrl+a means those, and nothing else.
  function markAll() {
    const all = win.rows.every(r => !!win.marks[r.name]);
    const m = Object.assign({}, win.marks);
    for (const r of win.rows) { if (all) delete m[r.name]; else m[r.name] = r; }
    win.marks = m;
  }
  function markAllUpdates() {
    const rows = win.updateRows.filter(r => !r.head);
    const all = rows.every(r => !!win.umarks[r.u.name]);
    const m = {};
    if (!all) for (const r of rows) m[r.u.name] = r;
    win.umarks = m;
  }

  function toggleMark(r) {
    if (!r) return;
    const m = Object.assign({}, win.marks);
    if (m[r.name]) delete m[r.name];
    else m[r.name] = r;
    win.marks = m;
  }

  // ── Updates: the pending list, with headings ────────────────────────────
  // typed in the Updates tab; narrows the list by name, as the other tabs do
  property string uquery: ""
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
    return out;
  }

  // ── THE FILTER, WHICHEVER TAB ───────────────────────────────────────────
  // Every list tab filters as you type, and each keeps its own text — the
  // header shows the one for the tab on screen. Maintenance has five rows
  // and nothing to filter.
  readonly property bool filters: win.tab !== "maintenance" && win.tab !== "settings"
  readonly property string filterText:
    win.tab === "packages" ? win.query : win.tab === "history" ? win.hquery
    : win.tab === "updates" ? win.uquery : ""
  function setFilter(t) {
    if (win.tab === "packages") win.query = t;
    else if (win.tab === "history") win.hquery = t;
    else if (win.tab === "updates") win.uquery = t;
  }
  // One place typing is understood, for every tab that filters. Returns
  // whether the key was a filter key.
  function filterKey(event) {
    const k = event.key, ctrl = event.modifiers & Qt.ControlModifier;
    if (ctrl && k === Qt.Key_U) { win.setFilter(""); return true; }
    if (ctrl && k === Qt.Key_W) { win.setFilter(win.filterText.replace(/\S*\s*$/, "")); return true; }
    if (k === Qt.Key_Backspace) { win.setFilter(win.filterText.slice(0, -1)); return true; }
    // terminus' "go to the filter": here typing IS the filter, and no
    // package name holds a slash, so the habit costs nothing
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
    return r && !r.head ? { name: r.u.name, repo: "update", aur: r.aur } : null;
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
      infoProc.running = false;
      infoProc.command = ["sh", "-c", Cer.infoCommand(win.script, c.name, repo)];
      infoProc.running = true;
      // what needs it and what it put on disk: only for what is installed
      win.extras = null;
      extrasProc.running = false;
      if (c.installed || c.repo === "update") {
        extrasProc.command = ["sh", "-c", Cer.extrasCommand(c.name)];
        extrasProc.running = true;
      }
    }
  }
  Process {
    id: infoProc
    stdout: StdioCollector {
      id: infoOut
      onStreamFinished: win.info = Cer.parseInfo(infoOut.text)
    }
  }
  // what needs the package and what it installed — installed packages only
  property var extras: null
  Process {
    id: extrasProc
    stdout: StdioCollector {
      id: extrasOut
      onStreamFinished: win.extras = Cer.readExtras(extrasOut.text)
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
    planProc.command = ["sh", "-c", Cer.planCommand(
      win.installNames.filter(n => !win.targets[n].aur), win.removeNames)];
    planProc.running = true;
  }
  Process {
    id: planProc
    stdout: StdioCollector {
      id: planOut
      onStreamFinished: { win.plan = Cer.readPlan(planOut.text); win.planning = false; }
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
    if (!r || r.head) return;
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
    planProc.command = ["sh", "-c", Cer.planCommand(
      list.filter(r => !r.aur).map(r => r.u.name), [], Ceres.dbPath)];
    planProc.running = true;
  }
  function confirmUpdate() {
    const marked = Object.keys(win.umarks).map(n => win.umarks[n]);
    if (marked.length) win.confirmUpdates(marked);
    else {
      const r = win.updateRows[win.usel];
      if (r && !r.head) win.confirmUpdates([r]);
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
    if (!t || win.txBusyGuard()) return;
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
  function txBusyGuard() { return Ceres.txBusy; }
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
    planProc.command = ["sh", "-c", Cer.planCommand([], p.remove.map(r => r.name))];
    planProc.running = true;
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
      if (!win.partial) { Ceres.request(Cer.upgradeSteps(), "", -1); return; }
      Ceres.request([["-Sy", "--needed"].concat(names)],
                    "update " + names.length + " of " + Ceres.total + " \u00b7 partial upgrade",
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
    reviewProc.command = ["sh", "-c", Cer.reviewCommand(win.aurTargets[win.reviewAt])];
    reviewProc.running = true;
  }
  Process {
    id: reviewProc
    stdout: StdioCollector {
      id: reviewOut
      onStreamFinished: win.review = Cer.readReview(reviewOut.text)
    }
  }

  // ── History: pacman.log as transactions ────────────────────────────────
  property var history: []
  property string hquery: ""
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
        win.history = Cer.readHistory(historyOut.text);
        win.hsel = win.firstEvent(win.historyRows);
      }
    }
  }

  // headings and events in one model; typing narrows it to one package
  readonly property var historyRows: {
    const out = [];
    const q = win.hquery.toLowerCase();
    let lastDay = "";
    for (let ti = 0; ti < win.history.length; ti++) {
      const t = win.history[ti];
      const ev = q.trim() === "" ? t.events : t.events.filter(e => Cer.matchesAll(e.name, q));
      if (ev.length === 0) continue;
      const tally = Cer.tally(ev), parts = [];
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
      for (const e of ev) out.push({ head: false, e: e, tx: ti });
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
      if (!e) return;
      cacheProc.forName = e.name;
      cacheProc.command = ["sh", "-c", "pacman -Q -- " + Cer.q(e.name)
        + " 2>/dev/null | cut -d' ' -f2; echo '@@cache'; " + Cer.cachedCommand(e.name)];
      cacheProc.running = true;
    }
  }
  Process {
    id: cacheProc
    property string forName: ""
    stdout: StdioCollector {
      id: cacheOut
      onStreamFinished: {
        const parts = cacheOut.text.split("@@cache\n");
        win.installedNow = (parts[0] || "").trim();
        win.cached = Cer.byVersion(Cer.readCached(cacheProc.forName, parts[1] || "")).reverse();
        // and what the Arch archive has beyond it
        archiveProc.forName = cacheProc.forName;
        archiveProc.command = ["sh", "-c", Cer.archiveCommand(cacheProc.forName)];
        archiveProc.running = true;
      }
    }
  }

  // THE ARCH ARCHIVE: every version ever built, for when the cache has let
  // one go. Newest first, only what the cache does not already hold.
  property var archived: []
  Process {
    id: archiveProc
    property string forName: ""
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
    if (!e) return null;
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
      color: vrow.current ? Zenon.muted : Zenon.white
      font.family: Zenon.face
      font.pixelSize: 16
    }
    Text {
      anchors.right: parent.right
      anchors.rightMargin: 12
      anchors.verticalCenter: parent.verticalCenter
      text: vrow.current ? "installed" : vrow.back ? "\u21b5 go back"
        : (vrow.v && vrow.v.url ? "download" : "install")
      color: vrow.current ? Zenon.muted : vrow.back ? Zenon.yellow : Zenon.keyInk
      font.family: Zenon.face
      font.pixelSize: 14
    }
    TapHandler { enabled: !vrow.current; onTapped: win.installCached(vrow.v) }
  }

  // ── Maintenance ────────────────────────────────────────────────────────
  property var maint: null
  property int msel: 0
  property int pnsel: 0
  property var pnDiff: []
  readonly property var maintItems: [
    { key: "orphans", title: "Orphaned packages" },
    { key: "pacnew", title: "Configuration files" },
    { key: "cache", title: "Package cache" },
    { key: "clones", title: "AUR build clones" },
    { key: "sync", title: "Package databases" },
    { key: "mirrors", title: "Mirrors" },
    { key: "oldcode", title: "Running old code" },
    { key: "aurhealth", title: "AUR health" }
  ]
  // how many things want doing, for the tab's label
  readonly property int maintCount: !win.maint ? 0
    : (win.maint.orphans.length ? 1 : 0) + (win.maint.pacnew.length ? 1 : 0)
      + (win.maint.stale ? 1 : 0)

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
          right: (x.rate / 1e6).toFixed(1) + " MB/s \u00b7 " + x.ms + "ms" })));
    }
    const h = win.mirrors;
    if (!h) return [];
    return [{ head: true, name: "Your list, in the order pacman tries it" }].concat(h.servers.map((v, i) => ({
      name: v.host, version: v.country,
      right: !h.statusOk ? "" : !v.status ? "not in Arch's list"
        : Cer.mirrorBehind(v.status) ? (v.status.last_sync ? "behind \u00b7 synced " + Cer.age(Date.now() - Date.parse(v.status.last_sync)) : "not syncing")
        : "synced " + Cer.age(Date.now() - Date.parse(v.status.last_sync)) })));
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
      || (key === "cache" && m.stale > 0) || (key === "oldcode" && Ceres.staleApps.length > 0)
      || (key === "aurhealth" && Ceres.aurHealth.problems.length > 0)
      || (key === "mirrors" && win.mirrorsWant);
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
  onMselChanged: if (win.maintItems[win.msel].key === "mirrors" && !win.mirrors) win.loadMirrors()
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
      win.mirrorsAfter = true;
      Ceres.request([["@sudo", "cp", "-p", Cer.MIRRORLIST, Cer.MIRRORLIST + ".ceres-bak"],
                     ["@sudo", "install", "-m", "644", win.mirrorDraft, Cer.MIRRORLIST]],
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
        cacheDelay.restart();
      }
    }
  }

  function back() {
    if (win.authUp) { win.cancelAuth(); return true; }
    // A job still running is not a step back — it is the window going away
    // while the job carries on, which is what the hint promises. Answering
    // "handled" here left Esc doing nothing at all.
    if (win.face === "tx") {
      if (Ceres.txBusy) return false;
      Ceres.txClear();
      return true;
    }
    if (win.face === "review") { win.overlay = "confirm"; return true; }
    if (win.face === "confirm") { win.overlay = ""; return true; }
    if (win.face === "conf") { win.overlay = ""; return true; }
    // Marks go before the window does: Esc with things marked means "not
    // these", and only once nothing is marked does it mean "close".
    if (win.tab === "packages" && win.markCount > 0) { win.marks = ({}); return true; }
    if (win.tab === "updates" && win.umarkCount > 0) { win.umarks = ({}); return true; }
    if (win.filterText !== "") { win.setFilter(""); return true; }
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
      configView.gsel = Math.max(0, Math.min(5, configView.gsel + (d > 0 ? 1 : -1)));
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
      // the sheet takes every key while it is up
      if (win.authUp) { event.accepted = field.key(event); return; }
      if (win.msgUp) {
        event.accepted = true;
        if (Ceres.txBusy) { if (k === Qt.Key_Escape) win.dismiss(); return; }
        if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Escape) Ceres.txClear();
        else if (k === Qt.Key_T && Ceres.txState === "failed") Ceres.txInTerminal();
        return;
      }
      if (win.face === "setup") {
        event.accepted = true;
        if (k === Qt.Key_Return || k === Qt.Key_Enter) Ceres.setup(setupView.choice);
        else if (k === Qt.Key_Left || k === Qt.Key_Right)
          setupView.choice = setupView.choice === "paru" ? "paru-git" : "paru";
        else if (k === Qt.Key_Escape) { if (Ceres.deps.paru) win.dismiss(); else win.showSetup = false; }
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
        if (!win.back()) win.dismiss();
        return;
      }
      if (win.face === "result") {
        event.accepted = true;
        if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Escape) Ceres.txClear();
        return;
      }
      if (win.face === "tx") {
        if (Ceres.txBusy) return;
        if (k === Qt.Key_Return || k === Qt.Key_Enter) { event.accepted = true; Ceres.txClear(); }
        else if (k === Qt.Key_T && Ceres.txState === "failed") { event.accepted = true; Ceres.txInTerminal(); }
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
      if (ctrl && k >= Qt.Key_1 && k <= Qt.Key_5) {
        event.accepted = true;
        win.showTab(win.tabs[k - Qt.Key_1][0]);
        return;
      }
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
        else if ((k === Qt.Key_Space && (event.modifiers & Qt.ShiftModifier)) || k === Qt.Key_Tab) {
          event.accepted = true;
          win.toggleUmark(win.updateRows[win.usel]);
          win.move(1);
        }
        else if (ctrl && k === Qt.Key_D) { event.accepted = true; win.umarks = ({}); }
        else if (ctrl && k === Qt.Key_A) { event.accepted = true; win.markAllUpdates(); }
        else if ((k === Qt.Key_Return || k === Qt.Key_Enter) && Ceres.total > 0) {
          event.accepted = true;
          if (ctrl) Ceres.request(Cer.upgradeSteps(), "", -1);
          else win.confirmUpdate();
        }
        else event.accepted = win.filterKey(event);
        return;
      }
      // packages: typing is searching
      event.accepted = true;
      if (k === Qt.Key_Return || k === Qt.Key_Enter) win.confirm();
      // SHIFT+space marks: plain space belongs to the filter, which takes
      // several words — and a mark on space landed on the first row of a
      // list the filter was still narrowing.
      else if ((k === Qt.Key_Space && (event.modifiers & Qt.ShiftModifier)) || k === Qt.Key_Tab) {
        win.toggleMark(win.rows[win.sel]); win.move(1);
      }
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
              downgraded: Zenon.yellow, reinstalled: Zenon.cyan })[v] || Zenon.keyInk;
  }

  // ── pieces ──────────────────────────────────────────────────────────────
  function repoInk(repo) {
    if (/-testing$/.test(repo)) return Zenon.red;
    return ({ core: Zenon.cyan, extra: Zenon.green, multilib: Zenon.yellow,
              aur: Zenon.magenta, local: Zenon.white })[repo] || Zenon.keyInk;
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
    layer.enabled: win.sheetInk > 0.01
    layer.effect: MultiEffect {
      blurEnabled: true
      blurMax: 40
      blur: win.sheetInk
      autoPaddingEnabled: false
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
      // two buttons that happen to sit together. One border, a hairline
      // between the halves, and the lit half filled.
      //
      // The fill ROUNDS ITS OWN OUTER CORNERS. `clip` only ever cuts to a
      // rectangle, so the lit end tab's square corner showed past the
      // switch's rounded one; the first and last halves now carry the same
      // radius on their outside corners, and the border is drawn OVER the
      // halves so no fill can ever sit on top of it.
      Item {
        id: seg
        anchors.left: parent.left
        anchors.leftMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        width: segRow.implicitWidth
        height: 32

        Rectangle {
          anchors.fill: parent
          z: 1
          radius: Zenon.windowRadius
          color: "transparent"
          border.width: 1
          border.color: Zenon.border
        }

        Row {
          id: segRow
          anchors.fill: parent
          Repeater {
            model: win.tabs
            delegate: Row {
              id: half
              required property var modelData
              required property int index
              height: seg.height
              Rectangle {
                visible: half.index > 0
                width: 1
                height: parent.height
                color: Zenon.border
              }
              Rectangle {
                readonly property bool on: win.tab === half.modelData[0]
                readonly property bool first: half.index === 0
                readonly property bool last: half.index === win.tabs.length - 1
                width: halfText.implicitWidth + 32
                height: parent.height
                topLeftRadius: first ? Zenon.windowRadius : 0
                bottomLeftRadius: first ? Zenon.windowRadius : 0
                topRightRadius: last ? Zenon.windowRadius : 0
                bottomRightRadius: last ? Zenon.windowRadius : 0
                // the lit tab wears the list's own highlight — one "this one" for
              // the whole window
              color: on ? Zenon.headBg : "transparent"
                Behavior on color { ColorAnimation { duration: Zenon.fast } }
                Text {
                  id: halfText
                  anchors.centerIn: parent
                  text: half.modelData[1]
                  color: parent.on ? Zenon.cyan : Zenon.keyInk
                  font.family: Zenon.face
                  font.weight: Font.Bold
                  font.pixelSize: 16
                }
                TapHandler { onTapped: win.showTab(half.modelData[0]) }
              }
            }
          }
        }
      }

      // WHAT HAS BEEN TYPED, NOT A FIELD. Typing anywhere in the tab searches,
      // so a box to type into offered something that was never needed — the
      // query is simply said here, with a caret after it, and nothing to click.
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
          anchors.verticalCenter: parent.verticalCenter
          visible: (win.tab === "packages" && win.markCount > 0)
                || (win.tab === "updates" && win.umarkCount > 0)
          textFormat: Text.StyledText
          text: win.tab === "updates"
            ? "<font color='" + Zenon.yellow + "'>" + win.umarkCount + " marked</font>"
            : (win.markInstalls ? "<font color='" + Zenon.green + "'>" + win.markInstalls + " to install</font>" : "")
              + (win.markInstalls && win.markRemovals ? "  <font color='" + Zenon.muted + "'>\u00b7</font>  " : "")
              + (win.markRemovals ? "<font color='" + Zenon.red + "'>" + win.markRemovals + " to remove</font>" : "")
          font.family: Zenon.face
          font.weight: Font.Bold
          font.pixelSize: 16
        }

        Row {
          visible: win.filters
          anchors.verticalCenter: parent.verticalCenter
          spacing: 8
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "\uF002"
            color: win.filterText !== "" ? Zenon.cyan : Zenon.muted
            font.family: Zenon.face
            font.pixelSize: 15
          }
          Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            Text {
              text: win.filterText !== "" ? win.filterText
                : (win.tab === "packages" ? "type to search" : "type to filter")
              color: win.filterText !== "" ? Zenon.white : Zenon.muted
              font.family: Zenon.face
              font.pixelSize: 17
            }
            Rectangle {
              id: qCaret
              visible: win.face === "browse" && win.filterText !== ""
              anchors.verticalCenter: parent.verticalCenter
              width: 2
              height: 16
              color: Zenon.white
              opacity: 0.3
              SequentialAnimation on opacity {
                running: qCaret.visible
                loops: Animation.Infinite
                NumberAnimation { to: 1; duration: 550; easing.type: Easing.InOutSine }
                NumberAnimation { to: 0.3; duration: 550; easing.type: Easing.InOutSine }
              }
            }
          }
        }

        // A CHECKBOX: it is a condition on the search, on or off, and a box
        // with a tick says exactly that. The same cyan as the lit tab.
        Row {
          id: onlyInstalled
          visible: win.tab === "packages"
          anchors.verticalCenter: parent.verticalCenter
          spacing: 8
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 16
            height: 16
            radius: Zenon.windowRadius - 1
            color: win.installedOnly ? Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.2) : "transparent"
            border.width: 1
            border.color: win.installedOnly ? Zenon.cyan : Zenon.keyInk
            Text {
              anchors.centerIn: parent
              visible: win.installedOnly
              text: "\uF00C"
              color: Zenon.cyan
              font.family: Zenon.face
              font.pixelSize: 10
            }
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Installed"
            color: win.installedOnly ? Zenon.white : Zenon.keyInk
            font.family: Zenon.face
            font.pixelSize: 16
          }
          TapHandler { onTapped: { win.installedOnly = !win.installedOnly; keys.forceActiveFocus(); } }
        }

        // how fresh the list is, and the way to make it fresher — Updates only
        Row {
          visible: win.tab === "updates"
          anchors.verticalCenter: parent.verticalCenter
          spacing: 10
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Ceres.checking ? "checking…"
              : Ceres.lastOk > 0 ? "checked " + Cer.age(Ceres.now - Ceres.lastOk) : ""
            color: Zenon.muted
            font.family: Zenon.face
            font.pixelSize: 14
          }
          Text {
            id: refresh
            anchors.verticalCenter: parent.verticalCenter
            text: ""
            color: refreshHov.hovered ? Zenon.white : Zenon.keyInk
            font.family: Zenon.face
            font.pixelSize: 16
            RotationAnimation on rotation {
              running: Ceres.checking
              loops: Animation.Infinite
              from: 0; to: 360; duration: 900
              onRunningChanged: if (!running) refresh.rotation = 0
            }
            HoverHandler { id: refreshHov }
            TapHandler { onTapped: Ceres.check() }
          }
        }
      }


      Rule { anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right }
    }

    // ── THE MESSAGE BAR ──────────────────────────────────────────────
    // The notes Ceres keeps about its own answer — a failed check, a reboot
    // or a re-login owed, news unread. None of them is an update, and they
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

      function inkOf(level) {
        return level === "bad" ? Zenon.red : level === "warn" ? Zenon.yellow : Zenon.blue;
      }
      function glyphOf(level) {
        return level === "bad" ? "\uF06A" : level === "warn" ? "\uF071" : "\uF05A";
      }
      readonly property color worst: {
        const items = Ceres.noteItems;
        if (items.some(n => n.level === "bad")) return Zenon.red;
        if (items.some(n => n.level === "warn")) return Zenon.yellow;
        return Zenon.blue;
      }

      Rectangle {
        id: noteBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        anchors.topMargin: 10
        height: noteCol.implicitHeight + 16
        radius: Zenon.windowRadius
        color: Qt.rgba(notes.worst.r, notes.worst.g, notes.worst.b, 0.10)
        border.width: 1
        border.color: Qt.rgba(notes.worst.r, notes.worst.g, notes.worst.b, 0.45)

        Column {
          id: noteCol
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: 12
          anchors.rightMargin: 12
          spacing: 4
          Repeater {
            model: Ceres.noteItems
            delegate: Row {
              required property var modelData
              width: noteCol.width
              height: 24
              spacing: 10
              Text {
                width: 18
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignHCenter
                text: notes.glyphOf(modelData.level)
                color: notes.inkOf(modelData.level)
                font.family: Zenon.face
                font.pixelSize: 15
              }
              Text {
                width: parent.width - 28
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: modelData.text
                color: Zenon.white
                font.family: Zenon.face
                font.pixelSize: 16
              }
            }
          }
        }
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
            parent: histList
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
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
              color: Zenon.keyInk
              font.family: Zenon.face
              font.weight: Font.Bold
              font.pixelSize: 15
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
                font.pixelSize: 16
              }
              Text {
                text: hrow.modelData.what || ""
                color: Zenon.keyInk
                font.family: Zenon.face
                font.weight: Font.Bold
                font.pixelSize: 16
              }
              Text {
                text: hrow.modelData.counts || ""
                color: Zenon.muted
                font.family: Zenon.face
                font.pixelSize: 15
              }
            }

            Rectangle {
              visible: !hrow.modelData.head
              anchors.fill: parent
              radius: Zenon.windowRadius
              color: hrow.index === win.hsel ? Zenon.headBg : "transparent"
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
            color: Zenon.muted
            font.family: Zenon.face
            font.weight: Font.Bold
            font.pixelSize: 17
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

        Column {
          anchors.left: hdiv.right
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: 16
          spacing: 8
          visible: !!win.hevent

          Text {
            text: win.hevent ? win.hevent.name : ""
            color: Zenon.white
            font.family: Zenon.face
            font.weight: Font.Bold
            font.pixelSize: 24
          }
          Text {
            textFormat: Text.StyledText
            text: !win.hevent ? "" : (win.installedNow !== ""
              ? "<font color='" + Zenon.muted + "'>installed now</font>  " + Cer.esc(win.installedNow)
              : "<font color='" + Zenon.muted + "'>not installed</font>")
            color: Zenon.white
            font.family: Zenon.face
            font.pixelSize: 17
            bottomPadding: 8
          }
          Text {
            text: win.cached.length ? "In the package cache" : "Nothing of it in the package cache"
            color: Zenon.muted
            font.family: Zenon.face
            font.weight: Font.Bold
            font.pixelSize: 15
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
            color: Zenon.muted
            font.family: Zenon.face
            font.weight: Font.Bold
            font.pixelSize: 15
          }
          Repeater {
            model: win.archived.slice(0, 10)
            delegate: VersionRow { required property var modelData; v: modelData }
          }
          Text {
            visible: win.archived.length > 10
            text: "+ " + (win.archived.length - 10) + " older in the archive"
            color: Zenon.muted
            font.family: Zenon.face
            font.pixelSize: 15
          }
          // what going back does not do
          Text {
            visible: win.cached.length > 0 || win.archived.length > 0
            width: parent.width
            wrapMode: Text.Wrap
            topPadding: 10
            text: "A version installed from here stays until the next full upgrade replaces it. "
              + "To hold it, add the package to IgnorePkg in /etc/pacman.conf."
            color: Zenon.muted
            font.family: Zenon.face
            font.pixelSize: 15
          }
        }
      }

      // ── Settings: pacman.conf ─────────────────────────────────────────
      ConfigView {
        id: configView
        visible: win.page === "browse" && win.tab === "settings"
        anchors.fill: parent
        onReleased: keys.forceActiveFocus()
        onReviewAsked: win.overlay = "conf"
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
        FontMetrics { id: mfTitle; font.family: Zenon.face; font.weight: Font.Bold; font.pixelSize: 17 }
        FontMetrics { id: mfSum; font.family: Zenon.face; font.pixelSize: 15 }
        readonly property real sideW: {
          let w = 0;
          for (const it of win.maintItems)
            w = Math.max(w, mfTitle.advanceWidth(it.title), mfSum.advanceWidth(win.maintSummary(it.key)));
          return Math.max(180, Math.ceil(w) + 26 + 16);
        }
        Column {
          id: maintList
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.margins: 8
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
              color: mrow.index === win.msel ? Zenon.headBg : "transparent"
              border.width: mrow.index === win.msel ? 1 : 0
              border.color: Zenon.border
              Rectangle {
                visible: win.maintWants(mrow.modelData.key)
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                width: 6; height: 6; radius: 3
                color: Zenon.yellow
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
                  font.pixelSize: 17
                }
                Text {
                  // held to the column: the pane beside it is not its to write on
                  width: parent.width
                  elide: Text.ElideRight
                  visible: text !== ""
                  text: win.maintSummary(mrow.modelData.key)
                  color: win.maintWants(mrow.modelData.key) ? Zenon.yellow : Zenon.muted
                  font.family: Zenon.face
                  font.pixelSize: 15
                }
              }
              TapHandler { onTapped: { win.msel = mrow.index; keys.forceActiveFocus(); } }
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
            font.pixelSize: 22
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
              oldcode: "Programs that were already running when an upgrade replaced their libraries. They keep using the old copies until they restart: restart the apps, and log out and back in for the session services. Only your own processes can be seen; system services need root to inspect.",
              mirrors: "Where pacman downloads from, in the order it tries them. Health comes from archlinux.org's own mirror status, which checks every mirror for how far behind it is. "
                + "Ranking times every mirror it reports as fully synced from this machine, rates the quickest twelve on a real download, and offers the fastest ten. The list you have now is kept as mirrorlist.ceres-bak.",
              sync: "The system's package databases and ceres' list of AUR packages. Ceres checks for updates against its own copy, so these only move when something upgrades or you sync them here. "
                + "After a sync, update before installing anything new: installing onto freshly synced databases without upgrading can pull in libraries newer than what installed programs were built against."
            })[mdetail.key]
            color: Zenon.keyInk
            font.family: Zenon.face
            font.pixelSize: 16
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
              ink: Zenon.muted
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
              ink: win.ranked ? Zenon.muted : Zenon.cyan
              primary: !win.ranked
              onClicked: win.maintGo("rank")
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
                  color: Zenon.keyInk
                  font.family: Zenon.face
                  font.pixelSize: 16
                }
                Text {
                  text: modelData[1].n === 0 ? "none"
                    : modelData[1].n + (modelData[1].n === 1 ? " file" : " files")
                      + (modelData[1].size ? " · " + modelData[1].size : "")
                  color: modelData[1].n === 0 ? Zenon.muted : Zenon.yellow
                  font.family: Zenon.face
                  font.pixelSize: 16
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
                  color: Zenon.keyInk
                  font.family: Zenon.face
                  font.pixelSize: 16
                }
                Text {
                  text: modelData[1]
                  color: modelData[2] ? Zenon.yellow : Zenon.muted
                  font.family: Zenon.face
                  font.pixelSize: 16
                }
              }
            }
          }

          // the list behind the summary
          ListView {
            id: mdList
            ScrollRail {
              target: mdList
              parent: mdList
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.bottom: parent.bottom
            }
            ElasticScroll { view: mdList }
            anchors.top: mirrorFacts.visible ? mirrorFacts.bottom : mdBtns.bottom
            anchors.topMargin: 14
            anchors.left: parent.left
            anchors.right: parent.right
            height: mdetail.key === "pacnew" ? Math.min(contentHeight, 120) : parent.height - y
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: !mdetail.m ? []
              : mdetail.key === "orphans" ? mdetail.m.orphans
              : mdetail.key === "clones" ? mdetail.m.clones
              : mdetail.key === "pacnew" ? mdetail.m.pacnew.map(p => ({ name: p }))
              : mdetail.key === "oldcode" ? win.oldCodeRows
              : mdetail.key === "mirrors" ? win.mirrorRows
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
              color: mitem.picked ? Zenon.headBg : "transparent"
              border.width: mitem.picked ? 1 : 0
              border.color: Zenon.border
              Text {
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.StyledText
                font.weight: mitem.modelData.head ? Font.Bold : Font.Normal
                text: mitem.modelData.head ? "<font color='" + Zenon.muted + "'>" + Cer.esc(mitem.modelData.name) + "</font>"
                  : Cer.esc(mitem.modelData.name) + (mitem.modelData.version
                  ? "  <font color='" + Zenon.muted + "'>" + Cer.esc(mitem.modelData.version) + "</font>" : "")
                  + (mdetail.key === "clones" && !mitem.modelData.installed
                    ? "  <font color='" + Zenon.yellow + "'>not installed</font>" : "")
                color: Zenon.white
                font.family: Zenon.face
                font.pixelSize: 16
              }
              Text {
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, mitem.width * 0.5)
                elide: Text.ElideLeft
                text: mitem.modelData.size ? Cer.bytes(mitem.modelData.size) : (mitem.modelData.right || "")
                color: Zenon.muted
                font.family: Zenon.face
                font.pixelSize: 15
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
              parent: pnView
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.bottom: parent.bottom
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
                : modelData.ink === "hunk" ? Zenon.cyan : Zenon.keyInk
              font.family: "monospace"
              font.pixelSize: 15
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
          // terminus' heading bar: small fixed-width capitals, the one the
          // list is sorted by in cyan with its direction. Click a heading to
          // sort by it, again to turn it round. With none chosen the search's
          // own order stands — best match first.
          Rectangle {
            id: colBar
            visible: win.tab === "packages"
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.leftMargin: 8
            anchors.topMargin: 6
            width: pkgList.width - 14
            height: 22
            radius: Zenon.windowRadius
            color: Zenon.headBg

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
                color: ch.on ? Zenon.cyan : Zenon.muted
                font.family: Zenon.faceFixed
                font.pixelSize: 14
              }
              TapHandler { onTapped: { win.sortBy(ch.key); keys.forceActiveFocus(); } }
            }

            // laid out on the rows' own columns: name after the state glyph,
            // size ending where the size column ends, repo on the right edge
            ColHead { x: 34; width: 200; label: "NAME"; key: "name" }
            ColHead { x: colBar.width - 10 - 72 - 12 - 90; width: 90; label: "SIZE"; key: "size"; rightAlign: true }
            ColHead { x: colBar.width - 10 - 72; width: 72; label: "REPO"; key: "repo"; rightAlign: true }
          }

          ListView {
            id: pkgList
            // terminus' scrollbar — see morpheus/ScrollRail. Parented to the view
            // itself, so in a Flickable it stays put instead of scrolling away.
            ScrollRail {
              target: pkgList
              parent: pkgList
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.bottom: parent.bottom
            }
            ElasticScroll { view: pkgList }
            visible: win.tab === "packages"
            anchors.fill: parent
            anchors.topMargin: colBar.height + 10
            anchors.margins: 8
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
                color: prow.mark ? (prow.modelData.installed
                    ? Qt.rgba(Zenon.red.r, Zenon.red.g, Zenon.red.b, 0.12)
                    : Qt.rgba(Zenon.green.r, Zenon.green.g, Zenon.green.b, 0.10))
                  : prow.here ? Zenon.headBg : "transparent"
                border.width: prow.here ? 1 : 0
                border.color: Zenon.border
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
                  : modelData.state === "dep" ? Zenon.dim : Zenon.muted
                font.family: Zenon.face
                font.pixelSize: 15
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
                font.pixelSize: 17
              }
              Text {
                id: size
                anchors.right: repo.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.size > 0 ? Cer.bytes(modelData.size) : ""
                color: Zenon.muted
                font.family: Zenon.face
                font.pixelSize: 15
              }
              Text {
                id: repo
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                width: 72
                horizontalAlignment: Text.AlignRight
                text: modelData.repo.toUpperCase().replace("-TESTING", "-T")
                color: win.repoInk(modelData.repo)
                font.family: Zenon.face
                font.weight: Font.Bold
                font.pixelSize: 14
              }

              TapHandler {
                onTapped: { win.sel = prow.index; keys.forceActiveFocus(); }
                onDoubleTapped: { win.sel = prow.index; win.confirmOne(prow.modelData); }
              }
              // a right click marks, or unmarks — the pointer's shift+space
              TapHandler {
                acceptedButtons: Qt.RightButton
                onTapped: { win.sel = prow.index; win.toggleMark(prow.modelData); keys.forceActiveFocus(); }
              }
            }

            Text {
              anchors.centerIn: parent
              visible: pkgList.count === 0 && !searchProc.running
              text: win.query !== "" ? "nothing matches" : "nothing here"
              color: Zenon.muted
              font.family: Zenon.face
              font.weight: Font.Bold
              font.pixelSize: 17
            }
          }

          ListView {
            id: updList
            ScrollRail {
              target: updList
              parent: updList
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.bottom: parent.bottom
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
                color: urow.marked ? Qt.rgba(Zenon.yellow.r, Zenon.yellow.g, Zenon.yellow.b, 0.10)
                  : urow.index === win.usel ? Zenon.headBg : "transparent"
                border.width: urow.index === win.usel ? 1 : 0
                border.color: Zenon.border
              }
              Text {
                visible: urow.modelData.head
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: (urow.modelData.aur ? "" : "") + "  " + urow.modelData.label
                  + "  " + urow.modelData.n
                color: urow.modelData.aur ? Ceres.ink.aur : Ceres.ink.repo
                font.family: Zenon.face
                font.weight: Font.Bold
                font.pixelSize: 16
              }
              Text {
                visible: urow.marked
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: "\uF062"
                color: Zenon.yellow
                font.family: Zenon.face
                font.pixelSize: 15
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
                onTapped: { win.usel = urow.index; keys.forceActiveFocus(); }
                onDoubleTapped: { win.usel = urow.index; win.confirmUpdates([urow.modelData]); }
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
              color: Zenon.muted
              font.family: Zenon.face
              font.weight: Font.Bold
              font.pixelSize: 17
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
            parent: infoPane
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
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
              font.pixelSize: 24
            }
            Text {
              width: parent.width
              wrapMode: Text.Wrap
              text: win.info ? (win.info.map["Description"] || "") : ""
              color: Zenon.keyInk
              font.family: Zenon.face
              font.pixelSize: 17
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
                  color: Zenon.muted
                  font.family: Zenon.face
                  font.pixelSize: 16
                }
                Text {
                  width: frow.width - 162
                  wrapMode: Text.Wrap
                  text: frow.modelData[1]
                  color: frow.link ? (linkHov.hovered ? Zenon.white : Zenon.blue) : Zenon.white
                  font.family: Zenon.face
                  font.pixelSize: 16
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
              width: infoCol.width
              topPadding: 14
              spacing: 7
              Rectangle { width: ih.width; height: 1; color: Zenon.border }
              Text {
                text: ih.label
                color: Zenon.keyInk
                font.family: Zenon.face
                font.weight: Font.Bold
                font.pixelSize: 15
                font.letterSpacing: 1.2
              }
            }
            InfoHead {
              visible: !!win.extras
              label: !win.extras ? "" : win.extras.rdeps.length === 0 ? "NEEDED BY NOTHING"
                : "NEEDED BY  " + win.extras.rdeps.length
            }
            Text {
              visible: !!win.extras && win.extras.rdeps.length > 0
              width: infoCol.width
              wrapMode: Text.Wrap
              text: !win.extras ? "" : win.extras.rdeps.slice(0, 40).join("   ")
                + (win.extras.rdeps.length > 40 ? "   and " + (win.extras.rdeps.length - 40) + " more" : "")
              color: Zenon.white
              font.family: Zenon.face
              font.pixelSize: 16
              lineHeight: 1.2
            }
            InfoHead {
              visible: !!win.extras && win.extras.files.length > 0
              label: !win.extras ? "" : "FILES  " + win.extras.files.length
            }
            Column {
              visible: !!win.extras && win.extras.files.length > 0
              width: infoCol.width
              spacing: 2
              Repeater {
                model: win.extras ? win.extras.files.slice(0, 60) : []
                delegate: Text {
                  required property string modelData
                  width: infoCol.width
                  elide: Text.ElideMiddle
                  text: modelData
                  color: Zenon.keyInk
                  font.family: Zenon.faceFixed
                  font.pixelSize: 15
                }
              }
              Text {
                visible: !!win.extras && win.extras.files.length > 60
                text: win.extras ? "+ " + (win.extras.files.length - 60) + " more" : ""
                color: Zenon.muted
                font.family: Zenon.face
                font.pixelSize: 15
              }
            }
          }

          Text {
            anchors.centerIn: parent
            visible: !win.info || win.info.fields.length === 0
            text: win.current ? "…" : ""
            color: Zenon.muted
            font.family: Zenon.face
            font.pixelSize: 17
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
          font.pixelSize: 16
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
            parent: reviewList
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
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
                  : modelData.ink === "hunk" ? Zenon.cyan : Zenon.keyInk
                font.family: "monospace"
                font.pixelSize: 15
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
        grow: 2
        visible: win.face === "tx"
        anchors.fill: parent
        anchors.margins: 20
      }
    }
  }

  // What the keys do, for whatever is on screen.
  readonly property var hintRows: {
    if (win.authUp) return [["return", "confirm"], ["esc", "cancel"]];
    if (win.msgUp) return Ceres.txBusy ? [["esc", "hide \u2014 it keeps going"]]
      : Ceres.txState === "failed" ? [["return", "ok"], ["t", "open in terminal"]] : [["return", "ok"]];
    switch (win.face) {

    case "news": return [["return", "continue"], ["esc", "back"]];
    case "setup": return (Ceres.deps.paru ? [["\u2190 \u2192", "paru or paru-git"]] : [])
      .concat([["return", "install"], ["esc", Ceres.deps.paru ? "close" : "not now"]]);
    case "tx":
      if (Ceres.txBusy) return [["esc", "hide — it keeps going"]];
      return Ceres.txState === "failed"
        ? [["t", "open in terminal"], ["return", "back"], ["esc", "close"]]
        : [["return", "back"], ["esc", "close"]];
    case "review": return [["← →", "other packages"], ["j k", "scroll"], ["esc", "back"]];
    case "result": return [["return", "ok"]];
    case "conf":
      return (configView.review && configView.review.ok ? [["return", "save"]] : []).concat([["esc", "back"]]);
    case "confirm":
      if (win.blocked) return [["esc", "back"]];
      return [["return", "go ahead"]]
        .concat(win.aurTargets.length ? [["r", "review PKGBUILD"]] : [])
        .concat([["esc", "back"]]);
    }
    if (win.tab === "history")
      return (win.wayBack ? [["return", "go back to " + win.wayBack.version]] : [])
        .concat(win.hevent ? [["ctrl z", "undo this transaction"]] : [])
        .concat([["ctrl tab", "next"], ["esc", win.hquery !== "" ? "clear" : "close"]]);
    if (win.tab === "maintenance")
      return [["j k", "choose"], ["return", "do it"], ["r", "recheck"], ["ctrl tab", "next"], ["esc", "close"]];
    if (win.tab === "settings")
      return configView.hints.concat([["ctrl tab", "next"], ["esc", "close"]]);
    if (win.tab === "updates")
      return Ceres.total === 0 ? [["ctrl r", "check"], ["ctrl tab", "next"], ["esc", "close"]]
        : [["shift space", "mark"], ["ctrl a", "mark all"], ["return", win.umarkCount ? "update marked" : "update this"],
           ["ctrl return", "update all"], ["ctrl r", "check"], ["ctrl tab", "next"]];
    return [["shift space", "mark"], ["ctrl a", "mark all"], ["return", win.markCount > 0 ? "review" : "install / remove"]]
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
    height: 50

    Rectangle { anchors.fill: parent; color: Zenon.hintBg }
    Rule { anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right }


    // The keys, centred on the window — nudged left only if the buttons on
    // the right would otherwise run into them.
    HintRow {
      id: footHints
      rows: win.hintRows
      anchors.verticalCenter: parent.verticalCenter
      // Centred when the strip is only keys; at the left the moment a button
      // joins it, so keys and buttons read as two ends of one strip rather
      // than a row that shifts off-centre to make room. (A Row holding only
      // hidden children is zero wide.)
      x: footBtns.width > 0 ? 16 : Math.round((foot.width - width) / 2)
    }

    Row {
      id: footBtns
      anchors.right: parent.right
      anchors.rightMargin: 12
      anchors.verticalCenter: parent.verticalCenter
      spacing: 8

      DialogButton {
        visible: win.face === "setup"
        label: "Install"
        ink: Zenon.cyan
        primary: true
        onClicked: Ceres.setup(setupView.choice)
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
        ink: Zenon.muted
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
        visible: win.face === "tx" && Ceres.txState === "failed"
        label: "Open in terminal"
        ink: Zenon.yellow
        onClicked: Ceres.txInTerminal()
      }
      DialogButton {
        visible: win.face === "tx" && !Ceres.txBusy
        label: "Back"
        ink: Zenon.muted
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
        onClicked: Ceres.request(Cer.upgradeSteps(), "", -1)
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
      id: passSheet
      shown: win.authUp
      // from the top edge of the window, over the head as well as the body
      fromTop: 0
      cardW: 460
      cardH: field.implicitHeight + (field.purpose !== "" ? 22 : 0) + 20 + passBtns.height + 14

      PasswordField {
        grow: 2
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
          ink: Zenon.muted
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
          font.pixelSize: 17
        }
        // while it runs, the latest thing it said
        Text {
          visible: Ceres.txBusy
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
          text: Ceres.txLog.length ? Ceres.txLog[Ceres.txLog.length - 1] : ""
          color: Zenon.keyInk
          font.family: Zenon.face
          font.pixelSize: 15
        }
        Text {
          visible: !Ceres.txBusy && Ceres.txDisk !== ""
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: Ceres.txDisk
          color: Zenon.keyInk
          font.family: Zenon.face
          font.pixelSize: 15
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
          text: "pacman.conf  <font color='" + Zenon.muted + "'>"
            + configView.changes + (configView.changes === 1 ? " line changed" : " lines changed") + "</font>"
          textFormat: Text.StyledText
          color: Zenon.white
          font.family: Zenon.face
          font.weight: Font.Bold
          font.pixelSize: 20
        }
        Text {
          id: confVerdict
          anchors.top: confTitle.bottom
          anchors.topMargin: 6
          text: !confSheet.rv ? "Checking with pacman-conf\u2026"
            : confSheet.rv.ok ? "pacman-conf reads it cleanly. The file you have now is kept as pacman.conf.ceres-bak."
            : "pacman-conf objects \u2014 fix these before saving:"
          color: !confSheet.rv ? Zenon.muted : confSheet.rv.ok ? Zenon.green : Zenon.red
          font.family: Zenon.face
          font.pixelSize: 15
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
              font.family: "monospace"
              font.pixelSize: 14
            }
          }
        }
        ListView {
          id: confDiff
          ScrollRail {
            target: confDiff
            parent: confDiff
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
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
              : modelData.ink === "hunk" ? Zenon.cyan : Zenon.keyInk
            font.family: "monospace"
            font.pixelSize: 15
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
          ink: Zenon.muted
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
      id: confirmSheet
      shown: win.confirmUp
      fromTop: 0
      cardW: Math.min(1000, win.width - 60)
      // as tall as the longer card needs, within the window
      cardH: Math.min(win.height - 90,
        76 + 16 + (win.partial ? 70 : 0) + 60
        + Math.max(confirmView.installRows.length, confirmView.removeRows.length) * 28
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
              color: Zenon.muted
              font.family: Zenon.face
              font.pixelSize: 15
            }
            Text {
              textFormat: Text.StyledText
              text: stat.value
              color: stat.ink
              font.family: Zenon.face
              font.weight: Font.Bold
              font.pixelSize: 24
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
            font.pixelSize: 14
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
          property var reasons: []
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
            font.pixelSize: 18
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
                font.pixelSize: 16
              }
              Repeater {
                model: card.reasons.slice(0, 8)
                delegate: Text {
                  required property string modelData
                  width: bannerCol.width
                  elide: Text.ElideRight
                  text: modelData
                  color: Zenon.keyInk
                  font.family: Zenon.face
                  font.pixelSize: 15
                }
              }
              Text {
                visible: card.reasons.length > 8
                text: "+ " + (card.reasons.length - 8) + " more"
                color: Zenon.muted
                font.family: Zenon.face
                font.pixelSize: 15
              }
            }
          }

          ListView {
            id: entryList
            ScrollRail {
              target: entryList
              parent: entryList
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.bottom: parent.bottom
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
                color: Zenon.muted
                font.family: Zenon.face
                font.weight: Font.Bold
                font.pixelSize: 15
              }

              Text {
                id: entGlyph
                visible: !ent.modelData.head
                anchors.left: parent.left
                anchors.leftMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                width: 20
                text: ent.modelData.target ? (card.removing ? "" : win.confirmKind === "update" ? "\uF062" : win.confirmKind === "undo" ? "\uF0E2" : "") : "·"
                color: ent.modelData.target ? card.ink : Zenon.muted
                font.family: Zenon.face
                font.pixelSize: 15
              }
              Text {
                id: entName
                visible: !ent.modelData.head
                anchors.left: entGlyph.right
                anchors.verticalCenter: parent.verticalCenter
                text: ent.modelData.name
                color: ent.modelData.target ? Zenon.white : Zenon.keyInk
                font.family: Zenon.face
                font.weight: ent.modelData.target ? Font.Bold : Font.Normal
                font.pixelSize: ent.modelData.target ? 17 : 16
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
                color: Zenon.muted
                font.family: Zenon.face
                font.pixelSize: 15
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
                  font.pixelSize: 14
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
                color: Zenon.muted
                font.family: Zenon.face
                font.pixelSize: 15
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
            font.pixelSize: 16
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
            visible: win.removeNames.length > 0
            width: cards.cardW
            height: cards.height
            title: "Remove  " + win.removeNames.length
            ink: Zenon.red
            removing: true
            entries: confirmView.removeRows
            error: confirmView.p && confirmView.p.removeError !== ""
              ? "This removal cannot happen: " + confirmView.p.removeError : ""
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
          ink: Zenon.muted
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

  // ── the result sheet ────────────────────────────────────────────────────
  // What a finished job changed, over the page it was started from.
  Item {
    anchors.fill: parent
    z: 10
    visible: win.face === "result" || resultSheet.cardInk > 0.01

    InputShield {
      visible: win.face === "result"
      onClicked: Ceres.txClear()
    }

    Sheet {
      id: resultSheet
      shown: win.face === "result"
      fromTop: 0
      cardW: Math.min(760, win.width - 60)
      cardH: Math.min(win.height - 90, 70 + Ceres.txEvents.length * 28 + 60)

      TxView {
        grow: 2
        anchors.fill: parent
        anchors.margins: 18
        anchors.bottomMargin: 18 + resultOk.height + 12
      }
      DialogButton {
        id: resultOk
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 14
        anchors.right: parent.right
        anchors.rightMargin: 16
        label: "OK"
        ink: Zenon.cyan
        primary: true
        onClicked: Ceres.txClear()
      }
    }
  }
}
