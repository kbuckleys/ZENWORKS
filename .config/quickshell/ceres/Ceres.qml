// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// CERES — what is waiting to be installed, known without being asked.
//
// This replaces waybar-updates, and it is shaped by what that got wrong:
//
//   IT POLLED. Every six seconds, forever, a burst of checkupdates, pacman,
//   pacman-conf, sha256sum and vercmp, to notice a change that happens a few
//   times a day. Here nothing runs while nothing happens. The network check
//   is on the wall clock (see `due`), and the only other trigger is pacman
//   itself: its lock file vanishing is the end of a transaction, from this
//   shell or any terminal, and that re-reads the list OFFLINE in a quarter
//   of a second.
//
//   A FAILED CHECK SAID "UP TO DATE". checkupdates exits 1 when it cannot
//   reach a mirror, paru prints an error and exits 1, and both came out as an
//   empty list. Here a failure keeps the last list it had, says how old that
//   is, and tries again in five minutes rather than an hour.
//
//   IT FORGOT EVERYTHING AT EACH START, and went online to find it again.
//   Here the last answer is on disk and on the bar from the first frame.
//
//   OURS WAS MISCONFIGURED. Its -c counts six-second cycles, not seconds, so
//   the "60 minute" check this shell asked for ran every six hours.

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../oracle"
import "../morpheus"
import "ceres.js" as Cer

Singleton {
  id: root

  // ── the answer ──────────────────────────────────────────────────────────
  property var repo: []
  property var aur: []
  readonly property int total: root.repo.length + root.aur.length
  // The running kernel's modules have been upgraded away — see restartCommand.
  property bool restartNeeded: false

  // ── how good the answer is ──────────────────────────────────────────────
  // Wall-clock milliseconds. lastOk is the last time BOTH halves answered;
  // lastTry the last time either was asked.
  property real lastOk: 0
  property real lastTry: 0
  property int failures: 0
  property string error: ""
  property bool checking: false
  // Ticks once a minute so "3h ago" stays true without anything running.
  property real now: Date.now()
  readonly property bool stale: root.failures > 0 && root.lastOk > 0

  // Keys ("name version") already announced — see Cer.arrivals.
  property var told: []

  // ── WHAT IS STILL RUNNING REPLACED CODE ──────────────────────────────────
  // After an upgrade, the programs and user services that still have the old
  // copy of a replaced library mapped — see Cer.staleCommand. Read at startup
  // and after every transaction, since those are the only times it changes.
  property var oldCode: []
  readonly property var staleApps: root.oldCode.filter(g => !g.service)
  readonly property var staleServices: root.oldCode.filter(g => g.service)
  function checkStale() { if (!staleProc.running) staleProc.running = true; }
  Process {
    id: staleProc
    command: ["sh", "-c", Cer.staleCommand()]
    stdout: StdioCollector {
      id: staleOut
      onStreamFinished: root.oldCode = Cer.readStale(staleOut.text)
    }
  }

  // ── AUR HEALTH ──────────────────────────────────────────────────────────
  // What the AUR says about the AUR packages installed here — flagged out of
  // date, orphaned, gone. Asked on the news' schedule (at most every three
  // hours) and after a transaction, when the set may have changed.
  property var aurHealth: ({ ok: false, checked: 0, problems: [] })
  property real aurHealthAt: 0
  function checkAurHealth(force) {
    if (aurHealthProc.running) return;
    if (!force && Date.now() - root.aurHealthAt < 3 * 3600 * 1000) return;
    aurHealthProc.running = true;
  }
  Process {
    id: aurHealthProc
    command: ["sh", "-c", Cer.aurHealthCommand()]
    stdout: StdioCollector {
      id: aurHealthOut
      onStreamFinished: {
        const r = Cer.readAurHealth(aurHealthOut.text);
        if (!r.ok) return;            // offline: keep the last answer
        root.aurHealth = r;
        root.aurHealthAt = Date.now();
      }
    }
  }

  // ── WHAT CERES STANDS ON ────────────────────────────────────────────────
  // Checked at startup and after every transaction. Anything missing is
  // named with its package and its purpose, and whatever needs paru is sent
  // to setup rather than left to fail — see setupSteps.
  property var deps: ({ missing: [], paru: false, cargo: false })
  readonly property bool setupNeeded: root.deps.missing.length > 0
  readonly property string buildDir: Paths.cacheDir() + "/ceres/build"
  signal setupRequested()
  property bool _checkAfterSetup: false

  function checkDeps() { depsProc.running = true; }
  Process {
    id: depsProc
    command: ["sh", "-c", Cer.depsCommand()]
    stdout: StdioCollector {
      id: depsOut
      onStreamFinished: root.deps = Cer.readDeps(depsOut.text)
    }
  }

  // `paru` is "paru", "paru-git" or "" when paru is already here.
  function setup(paru) {
    const steps = Cer.setupSteps(root.deps, root.deps.paru ? (paru || "paru") : "", root.buildDir,
                                 Quickshell.shellDir + "/scripts/ceres.sh");
    // and once it is all in, a fresh look for updates
    root._checkAfterSetup = true;
    if (steps.length === 0) return;
    const n = root.deps.missing.filter(m => !m.aur).length;
    root.request(steps,
      "install " + root.deps.missing.map(m => m.pkg).join(", "),
      n + (root.deps.paru ? 1 : 0));
  }

  // ── Arch news ───────────────────────────────────────────────────────────
  // The feed, as last fetched; the last full upgrade, which is what it is
  // measured against; and the links put aside. Unread is what was published
  // since that upgrade and has not been put aside — news older than the
  // upgrade is about an upgrade already done.
  property var news: []
  property real newsFetched: 0
  property real lastUpgrade: 0
  property var dismissedNews: []
  // NOTHING IS UNREAD UNTIL THE LAST UPGRADE IS KNOWN. The feed and the log
  // are read at the same moment after startup, and a feed that landed first
  // was measured against 0 — every item unread, the bar announcing ten
  // items of news and an upgrade stopping for news long since upgraded past.
  // The last upgrade is also kept on disk, so it is known from the first frame.
  readonly property var unreadNews: Oracle.ceresNews && root.lastUpgrade > 0
    ? Cer.unreadNews(root.news, root.lastUpgrade, root.dismissedNews) : []

  function dismissNews(links) {
    const d = root.dismissedNews.slice();
    for (const l of links) if (d.indexOf(l) < 0) d.push(l);
    // only what the feed still carries is worth remembering
    const live = root.news.map(n => n.link);
    root.dismissedNews = d.filter(l => live.indexOf(l) >= 0);
    root.save();
  }

  function fetchNews() {
    if (!Oracle.ceresNews || newsProc.running) return;
    newsProc.running = true;
  }
  Process {
    id: newsProc
    command: ["sh", "-c", Cer.newsCommand()]
    stdout: StdioCollector {
      id: newsOut
      onStreamFinished: {
        const r = Cer.readNews(newsOut.text);
        if (!r.ok) return;          // offline: keep what we had
        root.news = r.items;
        root.newsFetched = Date.now();
        root.save();
      }
    }
  }
  Process {
    id: upgradeProc
    command: ["sh", "-c", Cer.lastUpgradeCommand()]
    stdout: StdioCollector {
      id: upgradeOut
      onStreamFinished: {
        const t = Cer.logStamp(upgradeOut.text.trim());
        if (t > 0 && t !== root.lastUpgrade) { root.lastUpgrade = t; root.save(); }
      }
    }
  }

  // ── READ BEFORE UPGRADING ──────────────────────────────────────────────
  // An upgrade with unread news does not go straight to the password: it
  // stops at the news, the way paru does. Continuing puts those items aside
  // and carries on with exactly the request that was held.
  property bool newsGate: false
  property var _held: null
  function passNews() {
    const h = root._held;
    root.dismissNews(root.unreadNews.map(n => n.link));
    root.newsGate = false;
    root._held = null;
    if (h) root.request(h.steps, h.label, h.expected);
  }
  function holdBack() {
    root.newsGate = false;
    root._held = null;
    root.forgetNext();
  }

  readonly property string dbPath: Paths.cacheDir() + "/ceres/checkup-db"

  // ── on the bar ──────────────────────────────────────────────────────────
  // The lines above the lists: what is wrong with the answer, if anything.
  //
  // Each carries how much it matters — "bad" stops things working, "warn" is
  // owed but can wait, "info" is only worth knowing — so the window's message
  // bar can say so with more than one shade of red. `notes` is the same lines
  // as plain text, for the tooltip and the panel.
  readonly property var noteItems: {
    const out = [];
    // Short: they head a tooltip whose other lines are "name old → new".
    if (root.failures > 0) {
      const why = root.error !== "" ? root.error : "check failed";
      out.push({ level: "bad", text: root.lastOk > 0
        ? "Checked " + Cer.age(root.now - root.lastOk) + " — " + why
        : "Not checked yet — " + why });
    }
    if (root.setupNeeded)
      out.push({ level: "bad",
        text: "Setup needed: " + Cer.nameList(root.deps.missing.map(m => m.pkg), 2) });
    if (root.restartNeeded) out.push({ level: "warn", text: "Reboot needed: kernel upgraded" });
    if (root.staleApps.length)
      out.push({ level: "warn", text: "Restart " + Cer.nameList(root.staleApps.map(g => g.name), 2) });
    if (root.staleServices.length)
      out.push({ level: "warn", text: root.staleServices.length
        + (root.staleServices.length === 1 ? " service needs" : " services need") + " a re-login" });
    if (root.unreadNews.length)
      out.push({ level: "info", text: root.unreadNews.length + " unread Arch news"
        + (root.unreadNews.length === 1 ? " item" : " items") });
    return out;
  }
  readonly property var notes: root.noteItems.map(n => n.text)

  readonly property var ink: ({
    muted: "#6b7089", arrow: "#fab387", repo: "#7aa2f7", aur: "#c099ff",
    warn: "#e78284"
  })

  function describe(limit) {
    return Cer.describe(root.repo, root.aur, root.ink, limit, root.notes);
  }

  // ── asking ──────────────────────────────────────────────────────────────
  // Two processes, run together, joined in `landed`: the repo sync is the
  // slow half and the AUR request has no reason to wait for it.
  property int _pending: 0
  property var _repoOut: null
  property var _aurOut: null
  property bool _online: false

  function check() {
    if (root.checking) return;
    if (Date.now() - root.newsFetched > 3 * 3600 * 1000) root.fetchNews();
    root.checkAurHealth(false);
    root.checking = true;
    root._online = true;
    root.lastTry = Date.now();
    root._repoOut = null;
    root._aurOut = null;
    root._pending = 2;
    repoProc.command = ["sh", "-c", "mkdir -p " + Cer.q(root.dbPath) + "; "
      + Cer.repoCommand(root.dbPath, true)];
    repoProc.running = true;
    aurProc.command = ["sh", "-c", Cer.aurCommand()];
    aurProc.running = true;
  }

  // After a transaction: the same question without the network. Only once
  // there has been an online answer — before that the private database does
  // not exist and --nosync has nothing to compare against.
  function recheck() {
    restartProc.running = true;
    upgradeProc.running = true;
    root.checkStale();
    root.checkAurHealth(true);
    if (root.checking || root.lastOk === 0) return;
    root.checking = true;
    root._online = false;
    root._repoOut = null;
    root._aurOut = null;
    root._pending = 2;
    repoProc.command = ["sh", "-c", Cer.repoCommand(root.dbPath, false)];
    repoProc.running = true;
    aurProc.command = ["sh", "-c", Cer.aurRecheckCommand(root.aur)];
    aurProc.running = true;
  }

  function landed() {
    if (--root._pending > 0) return;
    root.checking = false;
    const r = root._repoOut, a = root._aurOut;
    // Each half that answered is believed, whatever the other did: a mirror
    // being down says nothing about the AUR.
    if (r && r.ok) root.repo = r.list;
    if (a && a.ok) root.aur = a.list;
    if (root._online) {
      if (r && r.ok && a && a.ok) {
        root.lastOk = Date.now();
        root.failures = 0;
        root.error = "";
      } else {
        root.failures++;
        // checkupdates only ever says "Cannot fetch updates", which is true
        // of a dead mirror and of no network alike; paru names the cause. So
        // when either half can say "offline", that is the reason given.
        const errs = [r && !r.ok ? r.error : "", a && !a.ok ? a.error : ""]
          .filter(e => e !== "");
        root.error = errs.indexOf("offline") >= 0 ? "offline"
          : (errs[0] || "check failed");
        console.warn("ceres: check failed (" + root.failures + "): " + root.error);
      }
    }
    root.announce();
    root.save();
  }

  Process {
    id: repoProc
    stdout: StdioCollector {
      id: repoText
      onStreamFinished: {
        root._repoOut = Cer.readRepo(repoText.text);
        root.landed();
      }
    }
  }

  Process {
    id: aurProc
    stdout: StdioCollector {
      id: aurText
      onStreamFinished: {
        root._aurOut = Cer.readAur(aurText.text);
        root.landed();
      }
    }
  }

  Process {
    id: restartProc
    command: ["sh", "-c", Cer.restartCommand()]
    stdout: StdioCollector {
      id: restartText
      onStreamFinished: root.restartNeeded = restartText.text.trim() === "restart"
    }
  }

  // ── telling ─────────────────────────────────────────────────────────────
  // Only arrivals. The toast is the tooltip — the same builder, so the two
  // can never describe the same list differently — minus the notes, which
  // are about the answer rather than news.
  function announce() {
    const all = root.repo.concat(root.aur);
    const fresh = Cer.arrivals(all, root.told);
    root.told = Cer.stillTold(all, root.told).concat(fresh.map(Cer.keyOf));
    if (fresh.length === 0 || !Oracle.updateNotify) return;
    // -w and a default action, so CLICKING the toast is an answer this
    // process hears: howler invokes a toast's `default` action on a left
    // click, and notify-send prints its name. A newer toast replaces an
    // older one still waiting — it says everything the older one did.
    if (toastProc.running) toastProc.running = false;
    toastProc.command = [
      "notify-send", "-a", root.appName, "-u", "normal", "-w",
      "-A", "default=Open", "",
      Cer.describe(root.repo, root.aur, root.ink, 5, [])
    ];
    toastProc.running = true;
  }

  // The panel, asked for.
  signal openRequested()
  // The full window, on one of its views ("updates", "packages"). Clicking
  // an update toast asks for this: a toast is news, and the window is where
  // the news is read in full.
  signal windowRequested(string view)
  function openWindow(view) { root.checkDeps(); root.windowRequested(view || "updates"); }
  // A keybind's version: open on that view, or close if it is already the
  // one on screen.
  signal windowToggleRequested(string view)
  // Set by CeresManager. The window answers password requests while it is
  // up; the panel answers the rest.
  property bool windowShown: false
  // and the bar's click / a keybind, which can also close it
  signal toggleRequested()

  Process {
    id: toastProc
    stdout: SplitParser {
      onRead: (line) => { if (line.trim() === "default") root.openWindow("updates"); }
    }
  }

  // Howler files these under its own name rather than in the history; see
  // Howler.selfUpdateApp, which names the same string.
  readonly property string appName: "ceres"

  // ── a transaction ───────────────────────────────────────────────────────
  // Here rather than in whatever draws it, so closing the panel never
  // touches a running upgrade: the panel is a view of this, and opening it
  // again mid-run shows the run where it has got to.
  //
  //   ""          nothing has run
  //   "auth"      the password is on its way to sudo
  //   "running"   sudo took it; paru is working
  //   "done"      finished clean
  //   "authfail"  sudo refused the password; nothing ran
  //   "failed"    paru stopped with an error
  property string txState: ""
  readonly property bool txBusy: root.txState === "auth" || root.txState === "running"
  property string txPhase: ""
  property var txLog: []
  property var txEvents: []
  property int txExpected: 0
  property string txError: ""
  property string txDisk: ""
  property var txSteps: []
  property var _sizesBefore: null

  readonly property string fifoPath:
    (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/ceres-askpass"
  readonly property string askpassPath: Quickshell.shellDir + "/scripts/ceres-askpass.sh"

  // The password is written to the wrapper's stdin the moment it starts and
  // is not kept: this function's argument is the only copy ceres holds, and
  // it goes out of scope on return.
  // What the next password is FOR. A full upgrade unless something smaller
  // has been asked for — installs and removals from the window, or a
  // rehearsal. `nextLabel` says which, on the password field, so the field
  // never asks for a password without saying what it will be used for.
  property var nextSteps: Cer.upgradeSteps()
  property int nextExpected: -1
  property string nextLabel: ""

  // Asks for a password for these steps: the panel or the window answers
  // with its field, whichever is on screen — unless one is still
  // remembered, in which case the steps simply run.
  function request(steps, label, expected) {
    if (root.txBusy) return false;
    // Anything paru is asked to do, with no paru to ask: setup comes first.
    if (root.deps.paru && steps.some(a => a[0] !== "@sudo" && a[0] !== "@user")) {
      root.setupRequested();
      return false;
    }
    if (Cer.isUpgrade(steps) && root.unreadNews.length > 0) {
      root._held = { steps: steps, label: label, expected: expected };
      root.newsGate = true;
      return true;
    }
    root.nextSteps = steps;
    root.nextLabel = label;
    root.nextExpected = expected;
    if (root._pw !== "") root.upgradeAll(root._pw);
    else root.authRequested();
    return true;
  }

  // ── THE PASSWORD, REMEMBERED THE WAY SUDO REMEMBERS IT ─────────────────
  // sudo keeps a password good for five minutes after it was last used, but
  // keyed to the process that asked (no terminal: its parent pid), and every
  // ceres transaction is a new process — so it asked again for each action
  // however recently the last one had taken it. This is sudo's own rule kept
  // here instead: five minutes from the last SUCCESSFUL use, refreshed by each
  // one, forgotten at once when sudo refuses it or the screen locks.
  //
  // The cost is plain: for those minutes the password is in this process's
  // memory rather than only for the length of one transaction.
  property string _pw: ""
  property string _trying: ""
  readonly property bool remembered: root._pw !== ""
  Timer {
    id: pwExpiry
    interval: 5 * 60 * 1000
    onTriggered: root.forgetPassword()
  }
  function forgetPassword() {
    root._pw = "";
    root._trying = "";
    pwExpiry.stop();
  }
  signal authRequested()

  // Back to a full upgrade: for leaving the password field, closing the
  // panel, or sudo having taken the password.
  function forgetNext() {
    root.nextSteps = Cer.upgradeSteps();
    root.nextExpected = -1;
    root.nextLabel = "";
  }

  function upgradeAll(password) {
    if (root.txBusy || !password) return;
    root.txSteps = root.nextSteps;
    root.txState = "auth";
    root.txPhase = "Authenticating";
    root.txLog = [];
    root.txEvents = [];
    root.txError = "";
    root.txDisk = "";
    root.txExpected = root.nextExpected >= 0 ? root.nextExpected : root.total;
    root._trying = password;
    root._sizesBefore = null;
    sizeProc.after = false;
    sizeProc.running = true;
    logTail.running = true;
    runProc.command = ["sh", "-c", Cer.runCommand(root.fifoPath, root.askpassPath, root.txSteps)];
    runProc.running = true;
    runProc.write(password + "\n");
  }

  // Back to the list, once a result has been read.
  function txClear() {
    if (!root.txBusy) root.txState = "";
  }

  // What a human has to answer: the same transaction, prompts and all, in a
  // terminal.
  function txInTerminal() {
    Quickshell.execDetached(["xdg-terminal-exec", "--title=Ceres", "--", "sh", "-c",
      Cer.terminalCommand(root.txSteps.length ? root.txSteps : Cer.upgradeSteps())
        + "; printf '\\nPress RETURN to close.'; read _"]);
  }

  function txLine(line) {
    if (line === "@@authed") {
      // ONLY NOW is the request spent. Clearing it when the password was
      // SENT meant a wrong password dropped a rehearsal on the floor, and
      // the retry ran whatever came next — a full upgrade. sudo accepting
      // the password is the moment the transaction is committed to.
      root.forgetNext();
      // sudo took it: remembered, for five minutes from now
      root._pw = root._trying;
      root._trying = "";
      pwExpiry.restart();
      root.txState = "running";
      root.txPhase = "Starting";
      return;
    }
    const ex = /^@@exit (-?\d+)$/.exec(line);
    if (ex) { root.txFinish(parseInt(ex[1], 10)); return; }
    const ph = Cer.phaseOf(line);
    if (ph !== "") root.txPhase = ph;
    const l = root.txLog.slice();
    l.push(line);
    while (l.length > 400) l.shift();
    root.txLog = l;
  }

  function txFinish(code) {
    if (!root.txBusy) return;
    // A moment for pacman.log's last lines to arrive: pacman writes the log
    // as it goes, but tail reads it on its own schedule.
    finishSettle.code = code;
    finishSettle.restart();
  }

  Timer {
    id: finishSettle
    interval: 400
    property int code: 0
    onTriggered: {
      logTail.running = false;
      const code = finishSettle.code;
      if (code === Cer.AUTH_FAILED) {
        // wrong, or no longer right: nothing is remembered
        root.forgetPassword();
        root.txState = "authfail";
        root.txPhase = "";
        return;
      }
      root.txError = code === 0 ? "" : (Cer.failureOf(root.txLog)
        || "paru stopped (exit " + code + ")");
      root.txState = code === 0 ? "done" : "failed";
      root.checkDeps();
      if (root._checkAfterSetup) { root._checkAfterSetup = false; if (code === 0) root.check(); }
      root.txPhase = "";
      sizeProc.after = true;
      sizeProc.running = true;
    }
  }

  Process {
    id: runProc
    stdinEnabled: true
    stdout: SplitParser { onRead: (line) => root.txLine(line) }
    // The mark is the normal ending; this is the abnormal one — the wrapper
    // killed before it could print it.
    onExited: (code) => { if (root.txBusy && !finishSettle.running) root.txFinish(code || -1); }
  }

  Process {
    id: logTail
    command: ["tail", "-n0", "-F", "/var/log/pacman.log"]
    stdout: SplitParser {
      onRead: (line) => {
        const e = Cer.readEvent(line);
        if (!e) return;
        root.txEvents = root.txEvents.concat([e]);
      }
    }
  }

  Process {
    id: sizeProc
    property bool after: false
    command: ["expac", "-Q", "%n %m"]
    stdout: StdioCollector {
      id: sizeText
      onStreamFinished: {
        const m = Cer.parseSizes(sizeText.text);
        if (!sizeProc.after) { root._sizesBefore = m; return; }
        if (root._sizesBefore)
          root.txDisk = Cer.diskLine(Cer.diskDelta(root._sizesBefore, m));
      }
    }
  }

  // ── when ────────────────────────────────────────────────────────────────
  // Once a minute, and all it does is subtract. A Timer alone would not
  // survive suspend: it counts time awake, so a laptop closed for the night
  // would wait out the rest of its hour after opening. The wall clock does
  // not have that problem.
  Timer {
    id: tick
    interval: 60000
    repeat: true
    running: true
    onTriggered: root.tickNow()
  }

  function tickNow() {
    root.now = Date.now();
    if (!root.checking && Cer.due(root.now, root.lastTry, root.lastOk,
                                  root.failures, Oracle.updateCheckMins))
      root.check();
  }

  // Not at the first frame: the shell has enough to do then, and the last
  // answer is already on the bar from disk.
  Timer {
    id: firstLook
    interval: 8000
    running: true
    onTriggered: {
      restartProc.running = true;
      upgradeProc.running = true;
      root.checkDeps();
      root.checkStale();
      root.checkAurHealth(false);
      // News on its own clock too: the update check may not be due for most
      // of an hour, and news that waited for it would be that late.
      if (Date.now() - root.newsFetched > 3 * 3600 * 1000) root.fetchNews();
      root.tickNow();
    }
  }

  // ── pacman, finishing ───────────────────────────────────────────────────
  // db.lck exists for exactly as long as a transaction runs, and pacman is
  // the only thing that removes it. Watching the directory for that one
  // delete catches every upgrade, install and removal on the machine —
  // including the ones typed into a terminal — with no process ever asking.
  Process {
    id: lockWatch
    running: true
    command: ["inotifywait", "-m", "-q", "-e", "delete", "--format", "%f",
              "/var/lib/pacman"]
    stdout: SplitParser {
      onRead: (line) => { if (line.trim() === "db.lck") settle.restart(); }
    }
    // Nothing stops this on purpose, so an exit is a fault. Re-armed after a
    // pause rather than at once, so a watch that cannot start does not spin.
    onExited: rearm.restart()
  }
  Timer { id: rearm; interval: 5000; onTriggered: lockWatch.running = true }
  // An -Syu can take the lock more than once (paru: repo, then each AUR
  // build), so the recheck waits for the lock to stay gone a moment.
  Timer { id: settle; interval: 1500; onTriggered: root.recheck() }

  // ── remembered ──────────────────────────────────────────────────────────
  FileView {
    id: stateFile
    path: Quickshell.statePath("ceres.json")
    blockLoading: true
    printErrors: false
  }

  function save() {
    stateFile.setText(JSON.stringify({
      repo: root.repo, aur: root.aur, lastOk: root.lastOk,
      lastTry: root.lastTry, failures: root.failures, error: root.error,
      told: root.told, news: root.news, newsFetched: root.newsFetched,
      dismissedNews: root.dismissedNews, lastUpgrade: root.lastUpgrade
    }));
  }

  Component.onCompleted: {
    // At once, not with the rest after startup: a handful of `command -v`,
    // and the window must not open onto a list it cannot fill.
    root.checkDeps();
    let s = null;
    try { s = JSON.parse(stateFile.text()); } catch (e) {}
    if (!s) return;
    root.repo = s.repo || [];
    root.aur = s.aur || [];
    root.lastOk = s.lastOk || 0;
    root.lastTry = s.lastTry || 0;
    root.failures = s.failures || 0;
    root.error = s.error || "";
    root.told = s.told || [];
    root.news = s.news || [];
    root.newsFetched = s.newsFetched || 0;
    root.dismissedNews = s.dismissedNews || [];
    root.lastUpgrade = s.lastUpgrade || 0;
  }

  IpcHandler {
    target: "Ceres"

    function status(): string {
      return "repo=" + root.repo.length + " aur=" + root.aur.length
        + " checking=" + root.checking + " failures=" + root.failures
        + " error=" + (root.error || "-")
        + " lastOk=" + (root.lastOk ? Cer.age(Date.now() - root.lastOk) : "never")
        + " restart=" + root.restartNeeded
        + "\n" + root.repo.concat(root.aur)
            .map(u => u.name + " " + u.from + " -> " + u.to).join("\n");
    }

    function check(): string {
      if (root.checking) return "already checking";
      root.check();
      return "checking";
    }

    // The whole transaction path — password, progress, summary — on a
    // reinstall of one installed package, so it can be tried without
    // spending the pending updates. -S without -y: no sync, so no partial
    // upgrade, and the same version comes back out of the package cache.
    function rehearse(pkg: string): string {
      if (root.txBusy) return "busy";
      if (!/^[A-Za-z0-9@._+-]+$/.test(pkg)) return "not a package name";
      root.request([["-S", pkg]], "rehearsal: reinstall " + pkg, 1);
      return "rehearsing a reinstall of " + pkg;
    }

    // The update toast again, as if the list had just arrived.
    function retoast(): string {
      if (root.total === 0) return "nothing pending to announce";
      root.told = [];
      root.announce();
      return "sent";
    }

    function aurhealth(): string {
      const h = root.aurHealth;
      if (!h.ok) return "not checked yet";
      return h.checked + " checked, " + h.problems.length + " need a look"
        + h.problems.map(p => "\n" + p.name + (p.gone ? " gone" : "") + (p.flagged ? " flagged" : "")
                                   + (p.orphaned ? " orphaned" : "")).join("");
    }

    function stale(): string {
      root.checkStale();
      return root.oldCode.length === 0 ? "nothing running replaced code"
        : root.oldCode.map(g => (g.service ? "[service " + g.unit + "] " : "") + g.name
            + " x" + g.pids.length + ": " + g.files.join(", ")).join("\n");
    }

    function deps(): string {
      return root.deps.missing.length === 0 ? "all present"
        : root.deps.missing.map(m => m.pkg + (m.aur ? " (AUR)" : "") + ": " + m.why.join("; ")).join("\n");
    }

    function toggle(): string {
      root.toggleRequested();
      return "toggled";
    }

    function toggleWindow(view: string): string {
      root.windowToggleRequested(view || "updates");
      return "toggled window " + (view || "updates");
    }

    function window(view: string): string {
      root.openWindow(view);
      return "window " + (view || "updates");
    }

    function open(): string {
      root.openRequested();
      return "open";
    }

    // The news gate, on demand: the newest item is treated as unread (as
    // if the last upgrade came just before it) and an Update all is asked
    // for behind it. The real last upgrade comes back at the next recheck.
    function previewNews(): string {
      if (root.news.length === 0) return "no news fetched yet";
      root.dismissedNews = root.dismissedNews.filter(l => l !== root.news[0].link);
      root.lastUpgrade = root.news[0].date - 1;
      root.request(Cer.upgradeSteps(), "", -1);
      return "gate: " + root.news[0].title;
    }

    function news(): string {
      return "items=" + root.news.length + " unread=" + root.unreadNews.length
        + " lastUpgrade=" + (root.lastUpgrade ? new Date(root.lastUpgrade).toISOString() : "?")
        + " gate=" + root.newsGate
        + "\n" + root.unreadNews.map(n => n.title).join("\n");
    }

    function tx(): string {
      return "state=" + (root.txState || "-") + " phase=" + (root.txPhase || "-")
        + " events=" + root.txEvents.length + "/" + root.txExpected
        + " error=" + (root.txError || "-") + " disk=" + (root.txDisk || "-");
    }

    function recheck(): string {
      root.recheck();
      return "rechecking";
    }
  }
}
