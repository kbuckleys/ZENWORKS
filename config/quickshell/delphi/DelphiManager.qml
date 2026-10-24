// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// DELPHI — the git client; and git, for the rest of the shell. Plato and
// terminus ask THIS rather than running git themselves, so there is one
// backend, one set of credentials and one way of asking for a password.
//
// THIS IS THE PART THAT IS ALWAYS IN THE SHELL: an ipc handler, the .desktop
// entry, and the line to the backend. The backend (bin/delphid, delphi/core —
// Python, no Quickshell in it) is started on the first request and let go of
// a minute after the last user has gone; the window type is compiled on the
// first open and let go of with its window. Nobody using git costs nothing.
//
//   call(op, repo, args, done, event) → id   one request; done(ok, result,
//                                            err), event(ev) for progress
//   cancel(id)                               stop it, and what git started
//   hold(who) / release(who)                 keep the backend up (a window)
//   asks                                     git's and ssh's open questions;
//                                            answer(ask, text | null)
//   changed(root, what)                      a watched repository moved
//
// Reached through:
//   `qs ipc call Delphi open ""`        the window, on the last repository
//   `qs ipc call Delphi open <path>`    the window, on the repository there —
//                                       bin/delphi, its .desktop entry

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../morpheus"
import "../ceres"
import "../terminus"
import "../morpheus/lagnotes.js" as LagNotes
import "delphi.js" as D
import "../morpheus/hypr.js" as Hypr

Scope {
  id: mgr

  // terminus and plato, handed in by shell.qml: Show in terminus, open a
  // file in plato, choose a directory
  property var fileManager: null
  property var editor: null

  // the protocol this side speaks; a daemon saying another is refused,
  // loudly, rather than half-understood (delphi/core/server.py PROTOCOL)
  readonly property int protocol: 1

  // ── ITS .desktop ENTRY ─────────────────────────────────────────────
  // Not shipped as a file: written into ~/.local/share/applications on
  // startup when missing, with this machine's path to bin/delphi (see
  // Desktop.installCommand), as plato's, picasso's and alexandria's are.
  // inode/directory is offered (Open with → Delphi on a repository in
  // terminus), never made the default.
  Process {
    running: true
    command: ["sh", "-c", Desktop.installCommand("delphi", {
      Type: "Application",
      Name: "Delphi",
      GenericName: "Git Client",
      Comment: "Stage, commit, branch, sync and browse history with git, in ZENWORKS",
      Icon: "git",
      Categories: ["Development", "RevisionControl"],
      Keywords: ["git", "commit", "branch", "diff", "merge", "rebase", "github", "gitlab", "codeberg", "repository", "version control"],
      Exec: Desktop.execLine(Quickshell.shellDir + "/delphi/bin/delphi", "%f"),
      Terminal: "false",
      StartupNotify: "false",
      MimeType: ["inode/directory"],
    })]
  }

  // ── WHAT IS KEPT ───────────────────────────────────────────────────
  // repositories opened, newest first; the page the window was on; the
  // directories looked through for repositories; how pull integrates
  property var recents: []
  // repositories forgotten: left off the list, and out of what a scan finds,
  // until opened again — their files are not touched
  property var hidden: []
  // where each page's seams were dragged to (terminus/SeamGrip), by name
  property var splits: ({})
  function setSplit(key, v) {
    const o = Object.assign({}, mgr.splits);
    if (v > 0) o[key] = Math.round(v); else delete o[key];
    mgr.splits = o;
    mgr.keep_();
  }
  property string page: "changes"
  property var scanRoots: ["~"]
  property string pullMode: "ff-only"
  // the open repository fetched quietly every few minutes (DelphiWindow
  // quietFetch) — Fetch's right-click turns it off
  property bool autoFetch: true
  // root → when it was last fetched (ms), quietly or not; this session only
  property var fetchedAt: ({})
  function noteFetched(root) {
    const o = Object.assign({}, mgr.fetchedAt);
    o[root] = Date.now();
    mgr.fetchedAt = o;
  }
  // the forge the Accounts page shows: github | gitlab | codeberg
  property string forge: "github"
  // ── CI: WHAT THE FORGES' CHECKS SAY OF A COMMIT ────────────────────
  // One answer per forge, repository and commit, shared by History, the
  // pull requests and the push chip: { state, runs, at }. A finished one
  // is kept; one still running is asked again after 15 s, "none" after a
  // minute (a push's checks take a moment to start).
  property var ci: ({})
  property var _ciAsking: ({})
  function ciKey(forge, full, sha) { return forge + "|" + full + "|" + sha; }
  function ciOf(forge, full, sha) { return mgr.ci[mgr.ciKey(forge, full, sha)] || null; }
  function ciAsk(forge, full, shas) {
    const f = D.FORGES[forge];
    if (!f || !full || !shas || shas.length === 0) return;
    const now = Date.now();
    const want = shas.filter((sha) => {
      const k = mgr.ciKey(forge, full, sha);
      if (mgr._ciAsking[k]) return false;
      const c = mgr.ci[k];
      return !c || (c.state === "pending" && now - c.at > 15000) || (c.state === "none" && now - c.at > 60000);
    }).slice(0, 40);
    if (want.length === 0) return;
    const asking = Object.assign({}, mgr._ciAsking);
    for (const sha of want) asking[mgr.ciKey(forge, full, sha)] = true;
    mgr._ciAsking = asking;
    mgr.call(f.id + "ChecksMany", null, { full: full, shas: want }, (ok, res) => {
      const a = Object.assign({}, mgr._ciAsking), o = Object.assign({}, mgr.ci);
      for (const sha of want) {
        const k = mgr.ciKey(forge, full, sha);
        delete a[k];
        if (ok && res[sha]) o[k] = Object.assign({ at: Date.now() }, res[sha]);
      }
      mgr._ciAsking = a;
      if (ok) mgr.ci = o;
    });
  }

  // where Push sends a repository's branch, by its root: the remotes ticked
  // in the head's push menu (none ticked: its upstream, as git would)
  property var pushTo: ({})
  function setPushTo(root, remotes) {
    const o = Object.assign({}, mgr.pushTo);
    if (remotes && remotes.length > 0) o[root] = remotes; else delete o[root];
    mgr.pushTo = o;
    mgr.keep_();
  }
  // KEPT IN SYNC (user, 2026-10-17): the repositories, by root, whose Push
  // is a Sync — every remote fetched, branches brought level, pushed to
  // each one behind (delphi/core repo.sync)
  property var syncs: ({})
  function setSync(root, on) {
    const o = Object.assign({}, mgr.syncs);
    if (on) o[root] = true; else delete o[root];
    mgr.syncs = o;
    mgr.keep_();
  }
  // OVER SSH (user, 2026-10-25): the forges, by id, whose clones and new
  // remotes take the ssh address — turned on from an account's chip once
  // ssh gets in there; HTTPS everywhere else
  property var sshFor: ({})
  function setSshFor(id, on) {
    const o = Object.assign({}, mgr.sshFor);
    if (on) o[id] = true; else delete o[id];
    mgr.sshFor = o;
    mgr.keep_();
  }
  // servers of your own (a self-hosted GitLab, a Forgejo or Gitea):
  // [{ kind, host, name }], laid into delphi.js' FORGES (D.setServers)
  property var servers: []
  onServersChanged: D.setServers(mgr.servers)
  function addServer(kind, host, name) {
    const id = D.serverId(kind, host);
    mgr.servers = mgr.servers.filter((s) => D.serverId(s.kind, s.host) !== id)
      .concat([{ kind: kind, host: host.toLowerCase(), name: name || host }]);
    mgr.keep_();
    return id;
  }
  function removeServer(id) {
    if (mgr.forge === id) mgr.forge = "github";
    mgr.servers = mgr.servers.filter((s) => D.serverId(s.kind, s.host) !== id);
    mgr.keep_();
  }
  FileView {
    id: stateFile
    path: Quickshell.statePath("delphi.json")
    blockLoading: true
    printErrors: false
  }
  Component.onCompleted: {
    try {
      const st = JSON.parse(stateFile.text() || "{}");
      if (Array.isArray(st.recents)) mgr.recents = st.recents.filter((r) => r && typeof r.root === "string");
      if (st.splits && typeof st.splits === "object") mgr.splits = st.splits;
      if (Array.isArray(st.hidden)) mgr.hidden = st.hidden.filter((h) => typeof h === "string");
      // the Stow page is gone (2026-10-24): one saved there opens Changes
      if (typeof st.page === "string") mgr.page = st.page === "dotfiles" ? "changes" : st.page;
      if (Array.isArray(st.scanRoots) && st.scanRoots.length > 0) mgr.scanRoots = st.scanRoots;
      if (["ff-only", "rebase", "merge"].indexOf(st.pullMode) >= 0) mgr.pullMode = st.pullMode;
      if (typeof st.autoFetch === "boolean") mgr.autoFetch = st.autoFetch;
      if (Array.isArray(st.servers)) mgr.servers = st.servers.filter((s) => s && D.SERVER_KINDS[s.kind] && D.hostOf(s.host));
      if (D.FORGES[st.forge]) mgr.forge = st.forge;
      if (st.pushTo && typeof st.pushTo === "object") mgr.pushTo = st.pushTo;
      if (st.syncs && typeof st.syncs === "object") mgr.syncs = st.syncs;
      if (st.sshFor && typeof st.sshFor === "object") mgr.sshFor = st.sshFor;
    } catch (e) {}
  }
  function keep_() { keepTimer.restart(); }
  Timer {
    id: keepTimer
    interval: 400
    onTriggered: stateFile.setText(JSON.stringify({
      recents: mgr.recents, hidden: mgr.hidden, splits: mgr.splits, page: mgr.page, scanRoots: mgr.scanRoots, pullMode: mgr.pullMode, autoFetch: mgr.autoFetch, forge: mgr.forge, servers: mgr.servers, pushTo: mgr.pushTo, syncs: mgr.syncs, sshFor: mgr.sshFor }, null, 1))
  }
  function set(key, value) {
    if (mgr[key] === value) return;
    mgr[key] = value;
    mgr.keep_();
  }
  function noteOpened(root, name) {
    mgr.recents = D.remember(mgr.recents, root, name || D.baseName(root), Date.now(), 24);
    mgr.hidden = mgr.hidden.filter((h) => h !== root);
    mgr.keep_();
  }
  // off delphi's lists — opened before, and found on disk — the directory
  // left as it is
  function forget(root) {
    mgr.recents = mgr.recents.filter((r) => r.root !== root);
    if (mgr.hidden.indexOf(root) < 0) mgr.hidden = mgr.hidden.concat([root]);
    mgr.keep_();
  }
  // off every list, Forgotten too — one whose files are gone from disk,
  // with nothing left to come back to
  function drop(root) {
    mgr.recents = mgr.recents.filter((r) => r.root !== root);
    mgr.hidden = mgr.hidden.filter((h) => h !== root);
    mgr.keep_();
  }
  // back on the lists (found on disk again) without opening it
  function unforget(root) {
    mgr.hidden = mgr.hidden.filter((h) => h !== root);
    mgr.keep_();
  }

  // ── THE BACKEND ────────────────────────────────────────────────────
  // One process, JSON lines both ways — terminus/LineDaemon, the suite's
  // line to a backend (calypso's too). A window holds it while it is open; a
  // one-off question from terminus or plato starts it, and it goes a minute
  // after the last.
  LineDaemon {
    id: line
    name: "delphi"
    command: ["python3", Quickshell.shellDir + "/delphi/bin/delphid"]
    protocol: mgr.protocol
    goneText: "The git backend stopped"
    onHeard: (ev) => mgr.event_(ev)
    onStopped: mgr.asks = []
  }
  readonly property bool up: line.up
  readonly property string broken: line.broken
  readonly property bool wanted: line.wanted
  readonly property int inFlight: line.inFlight
  function event_(ev) {
    if (ev.ask !== undefined) {
      mgr.asks = mgr.asks.concat([ev]);
      return;
    }
    if (ev.changed !== undefined) {
      mgr.changed(ev.changed, ev.what || []);
      return;
    }
  }

  function call(op, repo, args, done, event) {
    return line.request(op, { repo: repo || null, args: args || {} }, done, event);
  }
  function cancel(id) { line.cancel(id); }
  function hold(who) { line.hold(who); }
  function release(who) { line.release(who); }

  // ── AN UPLOAD UNDER WAY ────────────────────────────────────────────
  // Files committed to a forge — GitHub, GitLab, Codeberg (job.forge) — with
  // no clone (the Accounts page, GitHubPage.qml). The manager's,
  // not the window's: closing the window must neither stop it nor lose
  // what became of it (2026-10-11 — an upload begun with no repository
  // open showed no ring, Esc stopped it unseen, and its answer reached a
  // window already gone). It holds the backend while it runs; the window's
  // ring and bubble draw `upload`; how it ended is said in the window when
  // one is up, and as a notification when none is.
  //   { id, full, branch, fresh, entries: [{ name, path, size, exists,
  //     state }], phase: sending | committing | done | failed,
  //     waiting: seconds the forge asked to pause for, or 0, forge }
  property var upload: null
  readonly property bool uploading: !!mgr.upload && mgr.upload.phase !== "done" && mgr.upload.phase !== "failed"
  // the window's bubble is being read: the finished ring stays meanwhile
  property bool uploadLooked: false
  function startUpload(job, files, message) {
    if (mgr.uploading) { mgr.tell("An upload is already going — wait for it, or stop it from its ring", true); return false; }
    uploadLinger.stop();
    const set = (patch) => { if (mgr.upload) mgr.upload = Object.assign({}, mgr.upload, patch); };
    const each = (fn) => mgr.upload.entries.map(fn);
    mgr.upload = Object.assign({ phase: "sending", id: -1, waiting: 0 }, job,
      { entries: job.entries.map((e) => Object.assign({ state: "waiting" }, e)) });
    const n = job.entries.length;
    mgr.hold("upload");
    const site = (D.FORGES[job.forge || "github"] || D.FORGES.github);
    const id = mgr.call(site.id + "Upload", null, { full: job.full, files: files, message: message, branch: job.branch }, (ok, res, err) => {
      mgr.release("upload");
      set({ waiting: 0 });
      if (ok) {
        set({ phase: "done", entries: each((e) => Object.assign({}, e, { state: "sent" })) });
        mgr.tell("Uploaded " + n + (n === 1 ? " file" : " files") + " to " + job.full + " (" + job.branch + ")");
      } else {
        set({ phase: "failed", entries: each((e) => e.state === "sent" ? e : Object.assign({}, e, { state: e.state === "sending" ? "failed" : e.state })) });
        if (err && err.kind === "cancelled") mgr.tell("Upload stopped — nothing was committed", true);
        else mgr.tellFailure("The upload did not finish", "Nothing was committed — the files are not on " + site.name + " (" + job.full + ").", err);
      }
      uploadLinger.restart();
    }, (ev) => {
      if (!mgr.upload) return;
      // the forge asked for a pause (its limit on making content): said on the
      // ring until the next thing moves
      if (ev.phase === "waiting") { set({ waiting: ev.seconds }); return; }
      if (ev.file) set({ waiting: 0, entries: each((e) => e.path === ev.file ? Object.assign({}, e, { state: ev.state }) : e) });
      if (ev.phase) set({ waiting: 0, phase: ev.phase });
    });
    set({ id: id });
    return true;
  }
  function stopUpload() { if (mgr.uploading) mgr.cancel(mgr.upload.id); }
  // the finished ring stays a moment, then goes — not while it is read
  Timer {
    id: uploadLinger
    interval: 5000
    onTriggered: { if (mgr.uploadLooked) uploadLinger.restart(); else mgr.upload = null; }
  }

  // ── A TOOL IT NEEDS, INSTALLED WHEN IT IS ASKED FOR ──────────────────
  // gh for GitHub's sign-in, glab for GitLab's: installed when the forge
  // that needs one is chosen and it is not there, not up front for every
  // forge (user, 2026-10-11). Through Ceres, the suite's package manager —
  // its own password card, its own log — so delphi never runs pacman or asks
  // for a password itself. `done(ok)` once Ceres says how it went.
  // Ceres.install does the asking; this says how it went.
  readonly property var installing: Ceres.installing      // { pkg }
  function installTool(pkg, why, done) {
    if (Ceres.txBusy || Ceres.installing) { mgr.tell("Ceres is busy with another job — try again once it is done", true); return false; }
    const asked = Ceres.install(pkg, why, (ok, how) => {
      if (ok) mgr.tell("Installed " + pkg);
      else mgr.tell(pkg + " was not installed" + (how === "cancelled" ? "" : Ceres.txError ? ": " + Ceres.txError : ""), how !== "cancelled");
      if (done) done(ok);
    });
    if (!asked) mgr.tell("Ceres could not take the install of " + pkg + " — open Ceres to see why", true);
    return asked;
  }

  // ── SAYING HOW SOMETHING ENDED ─────────────────────────────────────
  // In the window when it is up; otherwise a notification, through
  // notify-send so it lands in howler's history as terminus' jobs do.
  function tell(text, bad) {
    if (mgr.win && mgr.win.visible) { mgr.win.say(text, bad); return; }
    Quickshell.execDetached(["notify-send", "-a", "delphi"].concat(bad ? ["-u", "critical"] : []).concat(["Delphi", text]));
  }
  function tellFailure(title, detail, err) {
    if (mgr.win && mgr.win.visible) { mgr.win.fail(title, detail, err); return; }
    Quickshell.execDetached(["notify-send", "-a", "delphi", "-u", "critical", title,
      detail + "\n" + D.errorText(err ? err.error : "")]);
  }

  // ── QUESTIONS FROM GIT AND SSH ─────────────────────────────────────
  // Each is a card in whichever delphi window is up (the window opens if
  // none is: a push started from plato still needs its password asked).
  property var asks: []
  function answer(ask, text) {
    mgr.asks = mgr.asks.filter((a) => a.ask !== ask);
    line.request("answer", { args: { ask: ask, text: text } });
  }
  onAsksChanged: if (mgr.asks.length > 0 && !(mgr.win && mgr.win.visible)) mgr.withWindow(() => {})

  signal changed(string root, var what)

  // ── THE WINDOW ─────────────────────────────────────────────────────
  // One, reused: opening another repository turns the window to it.
  property var win: null
  LazyComponent {
    id: lazy
    source: Qt.resolvedUrl("DelphiWindow.qml")
    tag: "delphi"
  }
  function withWindow(fn) {
    lazy.withReady(() => {
      let fresh = false;
      if (!mgr.win) {
        const t0 = Date.now();
        mgr.win = lazy.comp.createObject(mgr, { mgr: mgr });
        LagNotes.mark("delphi window", t0);
        if (!mgr.win) return;
        fresh = true;
      }
      // Raised only when it was ON SCREEN already: a kept window that was
      // hidden is mapped by the line below, and Hyprland focuses a window
      // it maps; asked in the same tick, it had no such window yet
      // ("hl.focus: window not found", 2026-10-18).
      const was = !fresh && mgr.win.visible;
      fn(mgr.win, fresh);
      mgr.win.visible = true;
      if (was) Hyprland.dispatch(Hypr.focusTitle("delphi"));
    });
  }
  function retire(w) {
    if (mgr.win === w) mgr.win = null;
    if (!mgr.win && lazy.waiting.length === 0) lazy.comp = null;
  }

  function open(path) {
    const p = String(path || "").trim();
    mgr.withWindow((w, fresh) => {
      if (p !== "") w.openRepo(p);
      else if (fresh) w.openRepo(mgr.recents.length > 0 ? mgr.recents[0].root : "");
    });
  }

  // ── FOR THE REST OF THE SHELL ──────────────────────────────────────
  // Terminus' "Open in Delphi" and plato's status bar: the window on the
  // repository a path is in, on the page asked for.
  function show(path, page) {
    mgr.withWindow((w) => { w.openRepo(path); if (page) w.setPage(page); });
  }

  // One file's history: its repository opened, History narrowed to it
  // (plato's right-click, terminus' row menu).
  function history(file) {
    mgr.withWindow((w) => { w.historyFile = file; w.openRepo(file); w.setPage("history"); });
  }

  // Who wrote each line of a file, as it is now: History narrowed to it,
  // its blame in place of the diff, at the line asked about (plato).
  function blame(file, line) {
    mgr.withWindow((w) => {
      w.historyFile = file;
      w.openRepo(file);
      w.setPage("history");
      w.blameWanted = { file: file, line: line || 0 };
    });
  }

  IpcHandler {
    target: "Delphi"
    function open(path: string): string { mgr.open(path); return "ok"; }
  }
}
