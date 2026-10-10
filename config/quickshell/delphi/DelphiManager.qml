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
import "../morpheus/lagnotes.js" as LagNotes
import "delphi.js" as D

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
      Keywords: ["git", "commit", "branch", "diff", "merge", "rebase", "github", "repository", "version control"],
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
  property string page: "changes"
  property var scanRoots: ["~"]
  property string pullMode: "ff-only"
  property bool showIgnored: false
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
      if (Array.isArray(st.hidden)) mgr.hidden = st.hidden.filter((h) => typeof h === "string");
      if (typeof st.page === "string") mgr.page = st.page;
      if (Array.isArray(st.scanRoots) && st.scanRoots.length > 0) mgr.scanRoots = st.scanRoots;
      if (["ff-only", "rebase", "merge"].indexOf(st.pullMode) >= 0) mgr.pullMode = st.pullMode;
    } catch (e) {}
  }
  function keep_() { keepTimer.restart(); }
  Timer {
    id: keepTimer
    interval: 400
    onTriggered: stateFile.setText(JSON.stringify({
      recents: mgr.recents, hidden: mgr.hidden, page: mgr.page, scanRoots: mgr.scanRoots, pullMode: mgr.pullMode }, null, 1))
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

  // ── THE BACKEND ────────────────────────────────────────────────────
  // One process, JSON lines both ways. Requests made before it has said
  // "ready" wait in `_out` and go the moment it does.
  property bool up: false
  property string broken: ""
  property var _out: []
  property var _pending: ({})
  property int _n: 0
  property var _users: ({})
  readonly property bool wanted: Object.keys(mgr._users).length > 0

  Process {
    id: daemon
    command: ["python3", Quickshell.shellDir + "/delphi/bin/delphid"]
    stdinEnabled: true
    stdout: SplitParser {
      onRead: (line) => mgr.hear_(line)
    }
    stderr: SplitParser {
      onRead: (line) => console.warn("delphid:", line)
    }
    onExited: (code) => {
      mgr.up = false;
      // every request still out fails now, not never
      const p = mgr._pending;
      mgr._pending = ({});
      for (const k in p) {
        try { if (p[k].done) p[k].done(false, null, { kind: "gone", error: "The git backend stopped" }); } catch (e) {}
      }
      mgr.asks = [];
      if (code !== 0 && code !== 15 && mgr.wanted) {
        console.warn("delphi: backend exited", code);
        restartTimer.start();
      }
    }
  }
  // a crash with someone still using it: back, once a second at most
  Timer { id: restartTimer; interval: 1000; onTriggered: if (mgr.wanted) mgr.start_() }
  function start_() {
    if (daemon.running) return;
    mgr.broken = "";
    daemon.running = true;
  }
  function send_(msg) {
    if (!mgr.up) {
      mgr._out.push(msg);
      mgr.start_();
      return;
    }
    daemon.write(JSON.stringify(msg) + "\n");
  }
  function hear_(line) {
    let m;
    try { m = JSON.parse(line); } catch (e) { console.warn("delphi: not JSON:", line); return; }
    if (m.id === undefined || m.id === null) {
      mgr.event_(m.event || {});
      return;
    }
    const p = mgr._pending[m.id];
    if (!p) return;
    if (m.event) {
      if (p.event) { try { p.event(m.event); } catch (e) { console.warn("delphi:", e); } }
      return;
    }
    delete mgr._pending[m.id];
    mgr._pendingChanged();
    if (p.done) {
      try { p.done(!!m.ok, m.ok ? m.result : null, m.ok ? null : m); }
      catch (e) { console.warn("delphi:", p.op, e); }
    }
  }
  function event_(ev) {
    if (ev.ready) {
      if (ev.protocol !== mgr.protocol) {
        mgr.broken = "The git backend speaks protocol " + ev.protocol + ", this window " + mgr.protocol;
        console.warn("delphi:", mgr.broken);
        daemon.running = false;
        return;
      }
      mgr.up = true;
      const q = mgr._out;
      mgr._out = [];
      for (const msg of q) daemon.write(JSON.stringify(msg) + "\n");
      return;
    }
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
    const id = ++mgr._n;
    mgr._pending[id] = { op: op, done: done || null, event: event || null };
    mgr._pendingChanged();
    mgr.send_({ id: id, op: op, repo: repo || null, args: args || {} });
    if (!mgr.wanted) idleTimer.restart();
    return id;
  }
  function cancel(id) {
    if (!mgr._pending[id]) return;
    mgr.send_({ id: ++mgr._n, op: "cancel", args: { id: id } });
  }
  readonly property int inFlight: Object.keys(mgr._pending).length

  // ── WHO NEEDS IT ───────────────────────────────────────────────────
  // A window holds the backend while it is open; a one-off question from
  // terminus or plato starts it and the idle timer lets it go again.
  function hold(who) {
    const u = Object.assign({}, mgr._users);
    u[who] = true;
    mgr._users = u;
    idleTimer.stop();
    mgr.start_();
  }
  function release(who) {
    const u = Object.assign({}, mgr._users);
    delete u[who];
    mgr._users = u;
    if (!mgr.wanted) idleTimer.restart();
  }
  Timer {
    id: idleTimer
    interval: 60000
    onTriggered: {
      if (mgr.wanted || mgr.inFlight > 0) { idleTimer.restart(); return; }
      mgr.up = false;
      daemon.running = false;
    }
  }

  // ── AN UPLOAD UNDER WAY ────────────────────────────────────────────
  // Files committed to GitHub with no clone (GitHubPage). The manager's,
  // not the window's: closing the window must neither stop it nor lose
  // what became of it (2026-10-11 — an upload begun with no repository
  // open showed no ring, Esc stopped it unseen, and its answer reached a
  // window already gone). It holds the backend while it runs; the window's
  // ring and bubble draw `upload`; how it ended is said in the window when
  // one is up, and as a notification when none is.
  //   { id, full, branch, fresh, entries: [{ name, path, size, exists,
  //     state }], phase: sending | committing | done | failed,
  //     waiting: seconds GitHub asked to pause for, or 0 }
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
    const id = mgr.call("githubUpload", null, { full: job.full, files: files, message: message, branch: job.branch }, (ok, res, err) => {
      mgr.release("upload");
      set({ waiting: 0 });
      if (ok) {
        set({ phase: "done", entries: each((e) => Object.assign({}, e, { state: "sent" })) });
        mgr.tell("Uploaded " + n + (n === 1 ? " file" : " files") + " to " + job.full + " (" + job.branch + ")");
      } else {
        set({ phase: "failed", entries: each((e) => e.state === "sent" ? e : Object.assign({}, e, { state: e.state === "sending" ? "failed" : e.state })) });
        if (err && err.kind === "cancelled") mgr.tell("Upload stopped — nothing was committed", true);
        else mgr.tellFailure("The upload did not finish", "Nothing was committed — the files are not on " + job.full + ".", err);
      }
      uploadLinger.restart();
    }, (ev) => {
      if (!mgr.upload) return;
      // GitHub asked for a pause (its limit on making content): said on the
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
    mgr.send_({ id: ++mgr._n, op: "answer", args: { ask: ask, text: text } });
  }
  onAsksChanged: if (mgr.asks.length > 0 && !mgr.win) mgr.withWindow(() => {})

  signal changed(string root, var what)

  // ── THE WINDOW ─────────────────────────────────────────────────────
  // One, reused: opening another repository turns the window to it.
  property var win: null
  property var _comp: null
  property var _waiting: []
  function _withComponent(fn) {
    if (mgr._comp && mgr._comp.status === Component.Ready) { fn(); return; }
    mgr._waiting.push(fn);
    if (mgr._comp) return;
    const comp = Qt.createComponent(Qt.resolvedUrl("DelphiWindow.qml"), Component.Asynchronous);
    mgr._comp = comp;
    const settle = () => {
      if (comp.status === Component.Loading) return;
      const queued = mgr._waiting;
      mgr._waiting = [];
      if (comp.status !== Component.Ready) {
        console.warn("delphi:", comp.errorString());
        mgr._comp = null;
        return;
      }
      for (const f of queued) f();
    };
    if (comp.status === Component.Loading) comp.statusChanged.connect(settle);
    else settle();
  }
  function withWindow(fn) {
    mgr._withComponent(() => {
      let fresh = false;
      if (!mgr.win) {
        const t0 = Date.now();
        mgr.win = mgr._comp.createObject(mgr, { mgr: mgr });
        LagNotes.mark("delphi window", t0);
        if (!mgr.win) return;
        fresh = true;
      }
      fn(mgr.win, fresh);
      mgr.win.visible = true;
      if (!fresh) Hyprland.dispatch('hl.dsp.focus({ window = "title:^(delphi)$" })');
    });
  }
  function retire(w) {
    if (mgr.win === w) mgr.win = null;
    if (!mgr.win && mgr._waiting.length === 0) mgr._comp = null;
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

  IpcHandler {
    target: "Delphi"
    function open(path: string): string { mgr.open(path); return "ok"; }
  }
}
