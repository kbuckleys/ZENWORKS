// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// DELPHI'S WINDOW. One repository at a time; its pages down the left:
//
//   Changes      what is not staged and what is, a file's diff beside them,
//                staged by file, by hunk or by line; the commit message
//   History      every branch's commits on a graph, a commit's files and diff
//   Branches     local, remote, tags: switch, create, merge, rebase, delete
//   Stashes      work put aside, and brought back
//   Worktrees    the other checkouts of this repository
//   Pull requests, Issues   the forge repository's — GitHub, GitLab,
//                Codeberg (ForgePage): read, say
//                something, open one, check a pull request out, merge
//   Accounts     GitHub, GitLab, Codeberg: sign in, your repositories —
//                clone, create, upload files (GitHubPage)
//   Repositories the ones opened before, the ones found on disk, clone, init
//
// The head says where you are and carries Fetch, Pull and Push (with how
// far ahead and behind); a network job's progress shows there. Everything
// git or ssh asks — a password, a passphrase, a new host's key — comes up
// as a card from the head, as does every confirmation and every failure.
//
// THE WORK IS NOT DONE HERE. Every request goes through the manager to the
// backend (delphi/core); this window only says what to do and draws what
// comes back. It refreshes when the backend's watcher says the repository
// moved — a commit in a terminal shows here as it lands.
//
//   ctrl+1…9  pages        ctrl+r  refresh       ctrl+o  open a repository
//   ctrl+shift+f fetch     ctrl+shift+l pull     ctrl+shift+p push
//   esc       unwinds, then closes

import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../morpheus"
import "../terminus"
import "delphi.js" as D
import "../terminus/terminus.js" as Terminus

FloatingWindow {
  id: win
  title: "delphi"
  color: Zenon.alpha(Zenon.layerBg, 0)
  implicitWidth: 1360
  implicitHeight: 880
  minimumSize: Qt.size(900, 560)

  property var mgr: null

  onVisibleChanged: if (!win.visible) Qt.callLater(() => {
    if (win.mgr) { win.unwatch(); win.mgr.release("window"); win.mgr.retire(win); }
    win.destroy();
  })
  onClosed: win.visible = false
  Component.onCompleted: {
    if (win.mgr) win.mgr.hold("window");
    Qt.callLater(win.checkTools);
    Qt.callLater(win.refocus);
  }

  // the cursor bars' re-seat after a workspace switch stranded a slide (see
  // terminus' thawPulse and SelectBar)
  property int thawPulse: 0
  Connections {
    target: Hyprland
    function onFocusedWorkspaceChanged() { win.thawPulse++; }
  }

  // THE highlight, as alexandria's: the page, the file, the commit all wear it
  readonly property color hiFill: Zenon.alpha(Zenon.cyan, 0.12)
  readonly property string home: Quickshell.env("HOME")

  // ── THE REPOSITORY ─────────────────────────────────────────────────────
  property string root: ""
  property var info: null
  property var st: null
  property var refs: ({ local: [], remote: [], tags: [] })
  property var remotes: []
  property int stashCount: 0
  readonly property var branch: win.st ? win.st.branch : null
  readonly property string branchName: !win.branch ? ""
    : win.branch.head || (win.branch.oid ? "detached at " + D.short(win.branch.oid) : "no commits yet")
  readonly property var state: win.st ? win.st.state : null
  readonly property string repoName: win.root === "" ? "" : D.baseName(win.root)
  // the forge repository behind origin, when there is one
  readonly property var origin: {
    const o = win.remotes.find((r) => r.name === "origin") || win.remotes[0];
    return o ? D.remoteOf(o.fetch || o.push) : null;
  }
  // where its pull requests and issues are: upstream's forge repository
  // for a fork, else origin's (D.hubOf) — { remote, full, web } or null
  readonly property var hub: D.hubOf(win.remotes)

  function openRepo(path) {
    if (!win.mgr) return;
    if (!path) { win.setPage("repos"); return; }
    win.mgr.call("discover", null, { path: path }, (ok, info) => {
      if (!ok || !info || info.bare) {
        win.say(info && info.bare ? "A bare repository has no working tree to show" : "Not in a repository: " + D.tilde(path, win.home), true);
        if (win.root === "") win.setPage("repos");
        return;
      }
      if (info.root !== win.root) {
        win.unwatch();
        win.root = info.root;
        win.info = info;
        win.st = null;
        win.refs = ({ local: [], remote: [], tags: [] });
        win.remotes = [];
        win.repoEpoch++;
        win.mgr.call("watch", win.root, {});
      }
      win.mgr.noteOpened(info.root, D.baseName(info.root));
      if (win.page === "repos") win.setPage(win.mgr.page !== "repos" ? win.mgr.page : "changes");
      win.refresh();
    });
  }
  // none open (the one open was deleted): the window back to its lists
  function closeRepo() {
    win.root = "";
    win.info = null;
    win.st = null;
    win.refs = ({ local: [], remote: [], tags: [] });
    win.remotes = [];
    win.repoEpoch++;
    win.setPage("repos");
  }
  // bumped on every repository change: pages drop what they held of the last
  property int repoEpoch: 0
  function unwatch() {
    if (win.root !== "" && win.mgr) win.mgr.call("unwatch", win.root, {});
  }

  // ── KEEPING UP ─────────────────────────────────────────────────────────
  // Status and refs on every change the watcher reports (gathered for a
  // moment: a rebase moves the index dozens of times); the pages refresh
  // what they show from the same signal (statusEpoch / refsEpoch).
  property int statusEpoch: 0
  property int refsEpoch: 0
  property bool loading: false
  function refresh() {
    win.refreshStatus();
    win.refreshRefs();
  }
  function refreshStatus() {
    if (win.root === "") return;
    const r = win.root;
    win.loading = true;
    win.mgr.call("status", r, {}, (ok, st, err) => {
      win.loading = false;
      if (r !== win.root) return;
      if (ok) { win.st = st; win.stashCount = st.stash; win.statusEpoch++; }
      else win.fail("Could not read the status", null, err);
    });
  }
  function refreshRefs() {
    if (win.root === "") return;
    const r = win.root;
    win.mgr.call("refs", r, {}, (ok, refs) => { if (ok && r === win.root) { win.refs = refs; win.refsEpoch++; } });
    win.mgr.call("remotes", r, {}, (ok, rs) => { if (ok && r === win.root) win.remotes = rs; });
  }
  Connections {
    target: win.mgr
    function onChanged(root, what) {
      if (root !== win.root) return;
      pendingWhat = pendingWhat.concat(what);
      changeTimer.restart();
    }
  }
  property var pendingWhat: []
  Timer {
    id: changeTimer
    interval: 120
    onTriggered: {
      const w = win.pendingWhat;
      win.pendingWhat = [];
      win.refreshStatus();
      if (w.indexOf("refs") >= 0 || w.indexOf("state") >= 0) win.refreshRefs();
    }
  }
  // A tree too big to watch is read again on ctrl+r. (Not on focus: a
  // FloatingWindow has no `active` to follow.)

  // ── DOING THINGS ───────────────────────────────────────────────────────
  // Every change goes through here: the request, the "busy" mark while it is
  // out, the failure card if it fails, and a refresh after (the watcher
  // would bring one too, but not before the next key is pressed).
  //   act(op, args, { label, then(result), network, quiet, done })
  property var busy: []        // [{ id, label, network, progress }]
  readonly property bool netBusy: win.busy.some((b) => b.network)
  readonly property var netJob: win.busy.find((b) => b.network) || null
  function act(op, args, opts) {
    const o = opts || {};
    const repo = o.repo !== undefined ? o.repo : win.root;
    const entry = { id: 0, label: o.label || "", network: !!o.network, progress: -1, phase: "" };
    entry.id = win.mgr.call(op, repo, args || {}, (ok, res, err) => {
      // the window closed while it ran: nothing left here to tell
      if (!win) return;
      win.busy = win.busy.filter((b) => b.id !== entry.id);
      if (ok) {
        if (o.said) win.say(o.said);
        if (o.then) o.then(res);
      } else if (err && err.kind === "cancelled") {
        win.say((o.label || "That") + " — stopped");
      } else {
        if (o.failed) o.failed(err);
        else win.fail((o.label || "That") + " did not work", null, err);
      }
      if (o.done) o.done(ok, res);
      if (o.refresh !== false) win.refresh();
    }, (ev) => {
      if (!win) return;
      if (ev.progress) {
        win.busy = win.busy.map((b) => b.id === entry.id
          ? Object.assign({}, b, { progress: ev.progress.percent, phase: ev.progress.phase }) : b);
      }
      if (o.event) o.event(ev);
    });
    if (o.label) win.busy = win.busy.concat([entry]);
    return entry.id;
  }
  function stop(id) { win.mgr.cancel(id); }

  // ── AN UPLOAD UNDER WAY ── is the manager's (DelphiManager.upload): it
  // goes on with this window closed, and the ring below draws it.

  // the three in the head
  function fetch() { win.act("fetch", {}, { label: "Fetching", network: true, said: "Fetched" }); }
  function pull() {
    win.act("pull", { mode: win.mgr.pullMode }, { label: "Pulling", network: true, said: "Pulled",
      failed: (err) => win.fail("Pull did not work", win.mgr.pullMode === "ff-only"
        ? "Your branch and its upstream have both moved. Merge or rebase them from Branches, or change how Pull integrates." : null, err) });
  }
  function push() {
    const b = win.branch;
    if (!b || !b.head) { win.say("Not on a branch — nothing to push", true); return; }
    // a branch with no commits yet has a name and nothing to send: said
    // plainly, not as git's "src refspec main does not match any"
    if (!b.oid) {
      win.say("Nothing to publish yet — stage your files and commit first", true);
      if (win.page !== "changes") win.setPage("changes");
      return;
    }
    if (!b.upstream) {
      // nowhere to push yet: the Accounts page's Publish — to a repository
      // there already, or a new one — rather than a toast to go and find it
      if (win.remotes.length === 0) {
        win.wantPublish = true;
        win.setPage("github");
        if (win.pageItem && win.pageItem.publishWanted) win.pageItem.publishWanted();
        return;
      }
      const remote = win.remotes.find((r) => r.name === "origin") ? "origin" : win.remotes[0].name;
      win.act("push", { remote: remote, branch: b.head, setUpstream: true },
              { label: "Pushing", network: true, said: "Published " + b.head + " to " + remote });
      return;
    }
    win.act("push", {}, { label: "Pushing", network: true, said: "Pushed",
      failed: (err) => {
        const t = String(err && err.error || "");
        if (/rejected|non-fast-forward|fetch first/.test(t)) {
          win.ask({ title: "The remote has commits you do not", glyph: "", ink: Zenon.yellow,
            detail: "Pull them in first, or overwrite them — only if no one else's work is there.",
            items: D.errorText(t).split("\n"),
            verb: "Pull first", verbInk: Zenon.cyan, then: () => win.pull() });
        } else win.fail("Push did not work", null, err);
      } });
  }
  // where each page's seams were dragged to (terminus/SeamGrip), by name —
  // the manager's, kept with delphi's state; 0 puts one back
  readonly property var splits: win.mgr ? win.mgr.splits : ({})
  function setSplit(key, v) { if (win.mgr) win.mgr.setSplit(key, v); }
  // Publish pressed with no remote: the Accounts page asks how, once it can
  property bool wantPublish: false
  function forcePush() {
    win.confirm({ question: "Force-push " + win.branchName + "?", glyph: "", ink: Zenon.red,
      detail: "Replaces the remote branch with yours. With a lease: refused if it moved since you last fetched.",
      verb: "Force-push", then: () => win.act("push", { force: true }, { label: "Pushing", network: true, said: "Pushed" }) });
  }

  // ── WHAT IT SAYS ───────────────────────────────────────────────────────
  property string said: ""
  property bool saidBad: false
  function say(t, bad) { win.said = t; win.saidBad = !!bad; sayTimer.restart(); }
  Timer { id: sayTimer; interval: 2400; onTriggered: win.said = "" }
  function copy(text, what) {
    Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | wl-copy", "sh", String(text)]);
    win.say("Copied " + (what || text));
  }
  function fail(title, detail, err) {
    const text = D.errorText(err ? err.error : "");
    // ssh not there: git cannot reach an ssh remote — said as that, with the
    // way to have it, rather than git's "cannot run ssh"
    if (/cannot run ssh|ssh: (command )?not found|unable to fork/i.test(String(err && err.error || ""))) {
      win.card_({ question: "ssh is not installed", glyph: "", ink: Zenon.yellow,
        detail: "This remote is reached over ssh, and ssh is not here. Ceres can install it (openssh) — it asks for your password — then try again.",
        items: text.split("\n"),
        choices: [{ label: "Install openssh", ink: Zenon.cyan, run: () => win.installNeed("openssh", "to reach ssh remotes") },
                  { label: "OK", ink: Zenon.muted }] });
      return;
    }
    win.card_({ question: title, glyph: "", ink: Zenon.red, detail: detail || "",
      items: text.split("\n"), choices: [{ label: "OK", ink: Zenon.muted }] });
  }

  // ── WHAT IS MISSING ────────────────────────────────────────────────────
  // The tools delphi leans on (delphi/core tools): asked on opening, on a
  // repository opened, after every install — and what is missing that
  // something here still needs is said in the sidebar, each with its
  // Install (through Ceres). Not only when signing in: a forge's sign-in
  // that outlived its tool (gh removed, gh's record still naming you) is
  // the commonest case (user, 2026-10-11).
  property var tools: null
  function checkTools() {
    win.mgr.call("tools", null, {}, (ok, t) => { if (ok && win) win.tools = t; });
  }
  readonly property var needs: {
    const t = win.tools, out = [];
    if (!t) return out;
    if (!t.gh && t.ghUser) out.push({ pkg: "github-cli", why: "Your GitHub sign-in (" + t.ghUser + ") goes through gh, which is not installed" });
    if (!t.glab && t.glabUser) out.push({ pkg: "glab", why: "Your GitLab sign-in (" + t.glabUser + ") goes through glab, which is not installed" });
    const viaSsh = win.remotes.some((r) => /^(ssh:\/\/|[^@\/\s]+@[^:\s]+:)/.test(r.fetch || r.push || ""));
    if (!t.ssh && viaSsh) out.push({ pkg: "openssh", why: "This repository's remote is reached over ssh, which is not installed" });
    if (!t.inotifywait) out.push({ pkg: "inotify-tools", why: "Without inotifywait, changes made outside Delphi show only on refresh" });
    return out;
  }
  // any install ended (here, or from the Accounts page): asked again
  Connections {
    target: win.mgr
    function onInstallingChanged() { if (win.mgr && !win.mgr.installing) win.checkTools(); }
  }
  function installNeed(pkg, why) {
    win.mgr.installTool(pkg, why, (ok) => {
      if (!win) return;
      win.checkTools();
      if (ok) win.refresh();
      if (ok && win.pageItem && win.pageItem.reload) win.pageItem.reload();
    });
  }

  // ── THE CARDS ──────────────────────────────────────────────────────────
  // One sheet, one card at a time, in the order asked: git's own questions
  // first (an operation is waiting on them), then everything else.
  //
  //   confirm({ question, glyph, ink, detail, items, verb, then, cancel })
  //   ask(form)                    a FormBody card — fields, a password
  //   card_({ question, …, choices: [{ label, ink, run, keep }] }) → id
  //                                any answers; the LAST is the way out (Esc,
  //                                a click off the card). `keep` leaves the
  //                                card up after its run — GitHub's sign-in
  //                                card, whose Open and Copy are not answers.
  //   dropCard(id)                 take one down (the sign-in that finished)
  property var sheetQueue: []
  property int cardN: 0
  readonly property var gitAsk: win.mgr && win.mgr.asks.length > 0 ? win.mgr.asks[0] : null
  readonly property var card: win.gitAsk ? win.askForm(win.gitAsk)
    : win.sheetQueue.length > 0 ? win.sheetQueue[0] : null
  readonly property bool carding: win.card !== null
  property int cardPick: 0
  onCardChanged: { win.cardPick = 0; if (!win.card) Qt.callLater(win.refocus); }
  function card_(c) {
    const id = ++win.cardN;
    // every answer speaks in a colour: one left without drew in Qt's default
    // black, heavier than the rest (the sign-in card's Copy, 2026-10-10)
    const choices = (c.choices || []).map((ch) => Object.assign({ ink: Zenon.muted }, ch));
    win.sheetQueue = win.sheetQueue.concat([Object.assign({ kind: "confirm", id: id }, c, { choices: choices })]);
    return id;
  }
  function dropCard(id) { win.sheetQueue = win.sheetQueue.filter((c) => c.id !== id); }
  function confirm(c) {
    return win.card_({ question: c.question, glyph: c.glyph || "", ink: c.ink || Zenon.cyan,
      detail: c.detail || "", items: c.items || [],
      choices: [{ label: c.verb || "OK", ink: c.ink || Zenon.cyan, run: c.then || null },
                { label: "Cancel", ink: Zenon.muted, run: c.cancel || null }] });
  }
  function ask(form) {
    const id = ++win.cardN;
    win.sheetQueue = win.sheetQueue.concat([Object.assign({ kind: "form", id: id }, form)]);
    return id;
  }
  // a confirmation's answer i
  function choose(i) {
    const c = win.card;
    if (!c || c.kind !== "confirm") return;
    if (c.gitAsk !== undefined) { win.mgr.answer(c.gitAsk, i === 0 ? "yes" : "no"); return; }
    const ch = c.choices[i];
    if (!ch) return;
    if (!ch.keep) win.dropCard(c.id);
    if (ch.run) ch.run();
  }
  // a form's answer
  function settleForm(ok, values) {
    const c = win.card;
    if (!c || c.kind !== "form") return;
    if (c.gitAsk !== undefined) { win.mgr.answer(c.gitAsk, ok ? values.answer : null); return; }
    win.dropCard(c.id);
    if (ok && c.then) c.then(values || {});
    else if (!ok && c.cancel) c.cancel();
  }
  // Esc, or a click off the card
  function dismiss() {
    const c = win.card;
    if (!c) return;
    if (c.kind === "form") win.settleForm(false, null);
    else win.choose(c.choices.length - 1);
  }
  // git's or ssh's question, as a card: a password hidden, a username typed,
  // a host key read and agreed to
  function askForm(q) {
    const a = D.askCard(q);
    if (a.confirm) return { kind: "confirm", gitAsk: q.ask, question: a.title,
      glyph: "", ink: Zenon.yellow, detail: "", items: a.detail.split("\n").filter((l) => l.trim() !== ""),
      choices: [{ label: "Trust it", ink: Zenon.yellow }, { label: "Cancel", ink: Zenon.muted }] };
    if (a.secret) return { kind: "form", gitAsk: q.ask, title: a.title, glyph: "", ink: Zenon.red,
      secret: { key: "answer", prompt: "input your " + a.title.toLowerCase(), purpose: a.detail }, verb: "Send" };
    return { kind: "form", gitAsk: q.ask, title: a.title, glyph: "", detail: a.detail,
      fields: [{ key: "answer", hint: a.title }], verb: "Send" };
  }

  // ── PAGES ──────────────────────────────────────────────────────────────
  readonly property var pages: [
    { id: "changes", label: "Changes", glyph: "" },
    { id: "history", label: "History", glyph: "" },
    { id: "branches", label: "Branches", glyph: "" },
    { id: "stashes", label: "Stashes", glyph: "" },
    { id: "worktrees", label: "Worktrees", glyph: "" },
    { id: "pulls", label: win.hub && D.FORGES[win.hub.forge] ? D.FORGES[win.hub.forge].pulls : "Pull requests", glyph: "\uF407" },
    { id: "issues", label: "Issues", glyph: "\uF41B" },
    { id: "github", label: "Accounts", glyph: "\uF0C2" },
    { id: "repos", label: "Repositories", glyph: "" },
  ]
  readonly property string page: win.mgr ? win.mgr.page : "changes"
  function setPage(p) {
    if (win.mgr) win.mgr.set("page", p);
    Qt.callLater(win.refocus);
  }
  function countOf(id) {
    if (!win.st) return "";
    if (id === "changes") {
      const n = win.st.unstaged.length + win.st.untracked.length + win.st.staged.length + win.st.conflicts.length;
      return n > 0 ? String(n) : "";
    }
    if (id === "branches") return win.refs.local.length > 0 ? String(win.refs.local.length) : "";
    if (id === "stashes") return win.stashCount > 0 ? String(win.stashCount) : "";
    return "";
  }
  readonly property var pageItem: pageLoader.item

  // ── KEYS ───────────────────────────────────────────────────────────────
  // The page's keys first (its list, its diff); what it does not take, here.
  function refocus() {
    if (win.carding) return;
    if (win.pageItem && win.pageItem.takeFocus) win.pageItem.takeFocus();
    else keySink.forceActiveFocus();
  }
  function key(e) {
    const k = e.key, ctrl = e.modifiers & Qt.ControlModifier, shift = e.modifiers & Qt.ShiftModifier;
    if (ctrl && k >= Qt.Key_1 && k <= Qt.Key_9) { win.setPage(win.pages[k - Qt.Key_1].id); return true; }
    if (ctrl && (k === Qt.Key_Tab || k === Qt.Key_Backtab)) {
      const ids = win.pages.map((p) => p.id);
      const d = (k === Qt.Key_Backtab || shift) ? -1 : 1;
      win.setPage(ids[(ids.indexOf(win.page) + d + ids.length) % ids.length]);
      return true;
    }
    if (ctrl && shift && k === Qt.Key_F) { win.fetch(); return true; }
    if (ctrl && shift && k === Qt.Key_L) { win.pull(); return true; }
    if (ctrl && shift && k === Qt.Key_P) { win.push(); return true; }
    if (ctrl && k === Qt.Key_R) { win.refresh(); if (win.pageItem && win.pageItem.reload) win.pageItem.reload(); return true; }
    if (ctrl && k === Qt.Key_O) { win.chooseRepo(); return true; }
    if (k === Qt.Key_Escape) {
      if (win.netJob) { win.stop(win.netJob.id); return true; }
      win.visible = false;
      return true;
    }
    return false;
  }
  function focusKeys() { keySink.forceActiveFocus(); }
  // the commit message being written, kept while you look at other pages
  property string draft: ""
  // the window's one tooltip, for pages: tip(item, text, key) / untip(item)
  function tip(item, text, keys) { tips.show(item, text, keys || ""); }
  function untip(item) { tips.hide(item); }
  function pageKey(e) {
    if (win.pageItem && win.pageItem.key && win.pageItem.key(e)) return true;
    return win.key(e);
  }
  Item {
    id: keySink
    focus: true
    Keys.onPressed: (e) => { if (win.pageKey(e)) e.accepted = true; }
  }
  readonly property var hintRows: {
    const own = win.pageItem && win.pageItem.hints ? win.pageItem.hints : [];
    return own.concat([["ctrl 1–9", "pages"], ["ctrl shift f l p", "fetch pull push"],
                       ["ctrl r", "refresh"], ["esc", win.netJob ? "stop" : "close"]]);
  }

  // ── PLACES ─────────────────────────────────────────────────────────────
  // terminus' own directory picker, and its windows for "show me"
  // THE REPOSITORY DROPDOWN, under the sidebar's chip: the ones opened before
  // (the open one ticked, by its name, its place beside it), then the ways to
  // another — a directory, a clone, every one there is
  function repoMenu() {
    const items = win.mgr.recents.slice(0, 14).map((r) => ({
      text: r.name, icon: r.root === win.root ? "\uF00C" : "\uF401", mark: D.tilde(r.root, win.home).replace(/\/[^/]*$/, ""),
      run: () => { if (r.root !== win.root) win.openRepo(r.root); } }));
    if (items.length > 0) items.push({ isSeparator: true });
    items.push({ text: "Open a directory…", icon: "\uF07C", mark: "ctrl o", run: () => win.chooseRepo() },
               { text: "Clone…", icon: "\uF019", run: () => { win.setPage("repos"); Qt.callLater(() => { if (win.pageItem && win.pageItem.clone) win.pageItem.clone(); }); } },
               { text: "All repositories…", icon: "\uF03A", run: () => win.setPage("repos") });
    const p = repoChip.mapToItem(stage, 0, repoChip.height + 4);
    repoPop.open(p.x, p.y, items);
  }
  function chooseRepo() {
    if (!win.mgr.fileManager) return;
    win.mgr.fileManager.choose(true, win.root !== "" ? win.root : win.home, (paths) => {
      if (paths && paths.length > 0) win.openRepo(paths[0]);
    });
  }
  function reveal(path) {
    if (win.mgr.fileManager) win.mgr.fileManager.reveal(path);
  }
  function edit(path) {
    if (win.mgr.editor) win.mgr.editor.open(path);
    else Quickshell.execDetached(["xdg-open", path]);
  }
  function abs(rel) { return win.root + "/" + rel; }

  // ── THE STAGE ──────────────────────────────────────────────────────────
  Item {
    id: stage
    anchors.fill: parent
    // no blur behind a card (user, 2026-10-10): the shield and the card's
    // own shadow say "answer this first"

    // the window's ground, everywhere but the sidebar (which wears the
    // thinner glass of an inactive tab, as alexandria's)
    Rectangle { z: -1; x: side.width; width: parent.width - x; height: side.height; color: Zenon.layerBg }
    Rectangle { z: -1; y: side.height; width: parent.width; height: parent.height - y; color: Zenon.layerBg }

    // ── the sidebar ──────────────────────────────────────────────────────
    Item {
      id: side
      // the window's whole height; the foot starts beside it (user, 2026-10-10)
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: 250

      Rectangle { anchors.fill: parent; color: Zenon.alpha(Zenon.tabAwayInk, Zenon.tabAway(Zenon.layerBg.a)) }
      Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Zenon.border }

      // the repository, and the branch it is on
      Rectangle {
        id: repoChip
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        height: 58
        radius: Zenon.windowRadius
        color: Zenon.wash(0.04)
        border.width: 1
        border.color: Zenon.border
        Text {
          id: repoGlyph
          x: 14
          anchors.verticalCenter: parent.verticalCenter
          text: ""
          color: Zenon.cyan
          font.family: Zenon.glyphFace
          font.pixelSize: Zenon.px(20)
        }
        Column {
          anchors.left: repoGlyph.right
          anchors.leftMargin: 12
          anchors.right: parent.right
          anchors.rightMargin: 12
          anchors.verticalCenter: parent.verticalCenter
          spacing: 2
          Text {
            width: parent.width
            elide: Text.ElideRight
            text: win.root === "" ? "No repository" : win.repoName
            color: Zenon.ink
            font.family: Zenon.face
            font.weight: Font.Bold
            font.pixelSize: Zenon.px(17)
          }
          Text {
            width: parent.width
            elide: Text.ElideRight
            text: win.root === "" ? "Open or clone one" : "  " + win.branchName
            color: win.branch && !win.branch.head ? Zenon.yellow : Zenon.muted
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(14)
          }
        }
        // a dropdown: every repository opened before, and the ways to another
        // (user, 2026-10-11) — the Repositories page is one row of it
        Text {
          anchors.right: parent.right
          anchors.rightMargin: 12
          anchors.verticalCenter: parent.verticalCenter
          text: "\uF078"
          color: Zenon.muted
          font.family: Zenon.glyphFace
          font.pixelSize: Zenon.px(11)
        }
        MouseArea {
          anchors.fill: parent
          onClicked: win.repoMenu()
        }
        HoverHandler {
          onHoveredChanged: hovered && win.root !== ""
            ? tips.show(repoChip, D.tilde(win.root, win.home), "") : tips.hide(repoChip)
        }
      }

      Column {
        id: pageCol
        anchors.top: repoChip.bottom
        anchors.topMargin: 12
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        spacing: 1
        Repeater {
          model: win.pages
          delegate: ShelfRow {
            id: pageRow
            required property var modelData
            required property int index
            width: pageCol.width
            glyph: pageRow.modelData.glyph
            label: pageRow.modelData.label
            count: win.countOf(pageRow.modelData.id)
            countInk: pageRow.modelData.id === "changes" && win.st && win.st.conflicts.length > 0 ? Zenon.red : Zenon.muted
            here: win.page === pageRow.modelData.id
            fill: win.hiFill
            opacity: win.root === "" && ["github", "repos"].indexOf(pageRow.modelData.id) < 0 ? 0.4 : 1
            onClicked: win.setPage(pageRow.modelData.id)
          }
        }
      }

      // what git is in the middle of: said where it cannot be missed
      Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: pageCol.bottom
        anchors.margins: 12
        anchors.topMargin: 16
        visible: !!win.state
        height: stateCol.implicitHeight + 20
        radius: Zenon.windowRadius
        color: Zenon.alpha(Zenon.yellow, 0.08)
        border.width: 1
        border.color: Zenon.alpha(Zenon.yellow, 0.4)
        Column {
          id: stateCol
          x: 12
          y: 10
          width: parent.width - 24
          spacing: 8
          Text {
            width: parent.width
            wrapMode: Text.Wrap
            text: !win.state ? "" : (win.state.op === "rebase" ? "Rebasing" + (win.state.steps ? "  " + win.state.step + " / " + win.state.steps : "")
              : win.state.op === "merge" ? "Merging" : win.state.op === "cherry-pick" ? "Cherry-picking"
              : win.state.op === "revert" ? "Reverting" : win.state.op === "am" ? "Applying patches" : "Bisecting")
            color: Zenon.yellow
            font.family: Zenon.face
            font.weight: Font.Bold
            font.pixelSize: Zenon.px(15)
          }
          Text {
            width: parent.width
            wrapMode: Text.Wrap
            visible: !!win.st && win.st.conflicts.length > 0
            text: win.st ? win.st.conflicts.length + (win.st.conflicts.length === 1 ? " conflict" : " conflicts") + " to resolve" : ""
            color: Zenon.soft
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(14)
          }
          Flow {
            width: parent.width
            spacing: 6
            visible: !!win.state && win.state.op !== "bisect"
            DialogButton {
              label: "Continue"
              ink: Zenon.cyan
              ready: !!win.st && win.st.conflicts.length === 0
              onClicked: win.sequence("continue")
            }
            DialogButton {
              visible: !!win.state && (win.state.op === "rebase" || win.state.op === "cherry-pick" || win.state.op === "am")
              label: "Skip"
              onClicked: win.sequence("skip")
            }
            DialogButton {
              label: "Abort"
              ink: Zenon.red
              onClicked: win.confirm({ question: "Abort the " + win.state.op + "?", glyph: "", ink: Zenon.red,
                detail: "Back to where you were before it started.", verb: "Abort", then: () => win.sequence("abort") })
            }
          }
        }
      }

      // what is missing, and its Install — see `needs`
      Rectangle {
        id: needBox
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: whoLine.top
        anchors.margins: 12
        visible: win.needs.length > 0
        height: needCol.implicitHeight + 20
        radius: Zenon.windowRadius
        color: Zenon.alpha(Zenon.yellow, 0.08)
        border.width: 1
        border.color: Zenon.alpha(Zenon.yellow, 0.4)
        Column {
          id: needCol
          x: 12
          y: 10
          width: parent.width - 24
          spacing: 10
          Text {
            text: "Missing"
            color: Zenon.yellow
            font.family: Zenon.face
            font.weight: Font.Bold
            font.pixelSize: Zenon.px(14)
          }
          Repeater {
            model: win.needs
            delegate: Column {
              required property var modelData
              width: needCol.width
              spacing: 6
              Text {
                width: parent.width
                wrapMode: Text.Wrap
                text: modelData.why
                color: Zenon.soft
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.pixelSize: Zenon.px(13)
              }
              DialogButton {
                label: win.mgr.installing && win.mgr.installing.pkg === modelData.pkg ? "Installing…" : "Install " + modelData.pkg
                ink: Zenon.cyan
                ready: !win.mgr.installing
                onClicked: win.installNeed(modelData.pkg, modelData.why.replace(/, which is not installed$/, ""))
              }
            }
          }
        }
      }

      // who commits: the first thing to set, said until it is
      Text {
        id: whoLine
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 14
        visible: !!win.info && !!win.info.identity
        elide: Text.ElideRight
        text: !win.info || !win.info.identity ? ""
          // the forge this repository is on, as its mark (user, 2026-10-11);
          // the person, when it is on none delphi knows
          : win.info.identity.name !== "" ? (win.hub && D.FORGES[win.hub.forge] ? D.FORGES[win.hub.forge].glyph : "\uF007") + "  " + win.info.identity.name + "  ·  " + win.info.identity.email
          : "  Who commits? Set your name"
        color: win.info && win.info.identity && win.info.identity.name === "" ? Zenon.yellow : Zenon.muted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(13)
        MouseArea { anchors.fill: parent; onClicked: win.askIdentity(null) }
      }
    }

    // ── WHAT SCROLLS UP GOES UNDER THE HEAD ──────────────────────────────
    // The suite's frost (morpheus/ScrollEdge, as ceres lays it): each of the
    // page's views (its edgeViews) carries its rows on past its top edge,
    // blurred, from the top of the window down — under the head, and under
    // the search fields and buttons that stand over the view, so those are
    // frosted by the same material (user, 2026-10-11). Declared before the
    // head, so the head's translucent ground tints them.
    Repeater {
      model: win.pageItem && win.pageItem.edgeViews ? win.pageItem.edgeViews : []
      delegate: ScrollEdge {
        required property var modelData
        view: modelData
        follow: true
        chromeTop: 0
        bar: null
        visible: !!modelData && modelData.visible
      }
    }

    // ── the head ─────────────────────────────────────────────────────────
    Item {
      id: head
      anchors.left: side.right
      anchors.right: parent.right
      anchors.top: parent.top
      // one row, the title and what it is about beside it (user, 2026-10-11:
      // two rows were taller than a head needs to be)
      height: 46
      // a header's translucent ground: the rows that go up under it (the
      // ScrollEdges below) show through it frosted, as in terminus and ceres
      Rectangle { anchors.fill: parent; color: Zenon.headBg }

      Item {
        anchors.left: parent.left
        anchors.leftMargin: 22
        anchors.right: sync.left
        anchors.rightMargin: 16
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        Text {
          id: headTitle
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          width: Math.min(implicitWidth, parent.width * 0.6)
          elide: Text.ElideRight
          text: win.pageItem && win.pageItem.title ? win.pageItem.title : (win.pages.find((p) => p.id === win.page) || {}).label || ""
          color: Zenon.ink
          font.family: Zenon.face
          font.weight: Font.Bold
          font.pixelSize: Zenon.px(19)
        }
        Text {
          anchors.left: headTitle.right
          anchors.leftMargin: 12
          anchors.right: parent.right
          anchors.baseline: headTitle.baseline
          elide: Text.ElideMiddle
          text: win.pageItem && win.pageItem.subtitle !== undefined ? win.pageItem.subtitle : D.tilde(win.root, win.home)
          color: Zenon.muted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(14)
        }
      }

      // Fetch · Pull · Push, or the network job under way
      Row {
        id: sync
        anchors.right: parent.right
        anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        // always: an upload or a clone runs with no repository open, and
        // its progress belongs here even then — only the three need one
        // ── an upload: a ring that fills as the files go, its count, and on
        // hover a bubble with every file (terminus/Bubble) ──
        Item {
          id: upPill
          visible: !!win.mgr.upload
          anchors.verticalCenter: parent.verticalCenter
          width: upRow.implicitWidth + 26
          height: 28
          readonly property int total: win.mgr.upload ? win.mgr.upload.entries.length : 0
          readonly property int sent: win.mgr.upload ? win.mgr.upload.entries.filter((e) => e.state === "sent").length : 0
          readonly property string phase: win.mgr.upload ? win.mgr.upload.phase : ""
          readonly property int waiting: win.mgr.upload ? win.mgr.upload.waiting || 0 : 0
          readonly property var site: D.FORGES[win.mgr.upload && win.mgr.upload.forge || "github"]
          readonly property color ink: upPill.phase === "failed" ? Zenon.red : upPill.phase === "done" ? Zenon.green : Zenon.cyan
          Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Zenon.alpha(upPill.ink, upHover.hovered ? 0.14 : 0.08)
            border.width: 1
            border.color: Zenon.alpha(upPill.ink, 0.4)
            Behavior on color { ColorAnimation { duration: Zenon.fast } }
          }
          Row {
            id: upRow
            anchors.centerIn: parent
            spacing: 9
            Canvas {
              id: ring
              anchors.verticalCenter: parent.verticalCenter
              width: 16
              height: 16
              // eased toward the share sent, so each file lands as a sweep
              property real share: upPill.phase === "done" ? 1
                : upPill.total > 0 ? upPill.sent / upPill.total : 0
              Behavior on share { NumberAnimation { duration: Zenon.normal; easing.type: Easing.OutCubic } }
              onShareChanged: requestPaint()
              Connections { target: Zenon; function onThemeEpochChanged() { ring.requestPaint(); } }
              onPaint: {
                const c = getContext("2d");
                c.reset();
                c.lineWidth = 2.2;
                c.lineCap = "round";
                c.strokeStyle = Zenon.alpha(upPill.ink, 0.25);
                c.beginPath(); c.arc(8, 8, 6.2, 0, Math.PI * 2); c.stroke();
                c.strokeStyle = upPill.ink;
                c.beginPath(); c.arc(8, 8, 6.2, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * Math.min(1, ring.share)); c.stroke();
              }
              // while the commit is made, the ring turns
              RotationAnimation on rotation {
                running: upPill.phase === "committing"
                loops: Animation.Infinite
                from: 0; to: 360; duration: 1100
              }
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: upPill.phase === "done" ? "Uploaded " + upPill.total
                : upPill.phase === "failed" ? "Upload stopped"
                : upPill.waiting > 0 ? upPill.site.name + " asked to wait " + upPill.waiting + " s"
                : upPill.phase === "committing" ? "Committing"
                : "Uploading " + Math.min(upPill.sent + 1, upPill.total) + " of " + upPill.total
              color: upPill.ink
              font.family: Zenon.face
              font.weight: Font.Bold
              font.features: { "tnum": 1 }
              font.pixelSize: Zenon.px(14)
            }
          }
          HoverHandler { id: upHover; onHoveredChanged: win.mgr.uploadLooked = hovered || upBubble.over }
          // stopping is asked first: a click meant for the bubble must not
          // throw an upload away
          TapHandler { onTapped: if (win.mgr.uploading) win.confirm({ question: "Stop the upload?", glyph: "\uF093", ink: Zenon.red,
            detail: "Nothing is committed: what was sent so far is left unused on " + upPill.site.name + ".", verb: "Stop", then: () => win.mgr.stopUpload() }) }
          Bubble {
            id: upBubble
            window: win
            target: upPill
            // held up while the pointer is on it, so its list can be scrolled
            sticky: true
            onOverChanged: win.mgr.uploadLooked = upHover.hovered || upBubble.over
            shown: upHover.hovered && !!win.mgr.upload
            cardWidth: 440
            Row {
              spacing: 8
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: upPill.site.glyph
                color: Zenon.ink
                font.family: Zenon.glyphFace
                font.pixelSize: Zenon.px(14)
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: win.mgr.upload ? win.mgr.upload.full + "  \u00b7  " + win.mgr.upload.branch + (win.mgr.upload.fresh ? "  (new branch)" : "") : ""
                color: Zenon.ink
                font.family: Zenon.face
                font.weight: Font.Bold
                font.pixelSize: Zenon.px(14)
              }
            }
            UploadRows {
              width: 440 - 28
              entries: win.mgr.upload ? win.mgr.upload.entries : []
              // the file under way kept in sight — not while you scroll
              follow: !upBubble.over
              maxRows: 10
            }
            Text {
              text: upPill.phase === "failed" ? "Stopped \u2014 nothing was committed"
                : upPill.phase === "done" ? "Committed \u2014 all " + upPill.total + " are there"
                : upPill.waiting > 0 ? upPill.site.name + " asked for a pause of " + upPill.waiting + " s \u2014 carrying on after it"
                : upPill.phase === "committing" ? "All sent \u2014 making the commit\u2026"
                : upPill.sent + " of " + upPill.total + " sent  \u00b7  the wheel scrolls  \u00b7  click the ring to stop"
              color: upPill.phase === "failed" ? Zenon.red : upPill.phase === "done" ? Zenon.green : Zenon.muted
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.features: { "tnum": 1 }
              font.pixelSize: Zenon.px(13)
            }
          }
        }
        Rectangle {
          visible: !!win.netJob
          anchors.verticalCenter: parent.verticalCenter
          width: netRow.implicitWidth + 30
          height: 28
          radius: 4
          color: Zenon.alpha(Zenon.cyan, 0.08)
          border.width: 1
          border.color: Zenon.alpha(Zenon.cyan, 0.4)
          Row {
            id: netRow
            anchors.centerIn: parent
            spacing: 10
            Working { anchors.verticalCenter: parent.verticalCenter; running: !!win.netJob; ink: Zenon.cyan; dot: 5; gap: 4 }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: !win.netJob ? "" : win.netJob.label
                + (win.netJob.progress >= 0 ? "  ·  " + win.netJob.phase.toLowerCase() + " " + win.netJob.progress + "%" : "…")
              color: Zenon.cyan
              font.family: Zenon.face
              font.weight: Font.Bold
              font.features: { "tnum": 1 }
              font.pixelSize: Zenon.px(15)
            }
          }
          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onClicked: if (win.netJob) win.stop(win.netJob.id)
            onContainsMouseChanged: containsMouse ? tips.show(parent, "Stop", "esc") : tips.hide(parent)
          }
        }
        DialogButton {
          visible: !win.netBusy && win.root !== ""
          label: "Fetch"
          onClicked: win.fetch()
        }
        DialogButton {
          visible: !win.netBusy && win.root !== ""
          label: win.branch && win.branch.behind > 0 ? "Pull  ↓" + win.branch.behind : "Pull"
          ink: win.branch && win.branch.behind > 0 ? Zenon.cyan : Zenon.muted
          ready: !!win.branch && !!win.branch.upstream
          onClicked: win.pull()
        }
        DialogButton {
          visible: !win.netBusy && win.root !== ""
          label: !win.branch ? "Push" : !win.branch.upstream && win.branch.head ? "Publish"
            : win.branch.ahead > 0 ? "Push  ↑" + win.branch.ahead : "Push"
          ink: win.branch && (win.branch.ahead > 0 || (!win.branch.upstream && win.branch.head)) ? Zenon.cyan : Zenon.muted
          primary: !!win.branch && win.branch.ahead > 0 && win.branch.behind === 0
          onClicked: win.push()
        }
      }
    }

    // ── the page ─────────────────────────────────────────────────────────
    Loader {
      id: pageLoader
      anchors.left: side.right
      anchors.right: parent.right
      anchors.top: head.bottom
      anchors.bottom: foot.top
      source: win.root === "" && ["github", "repos"].indexOf(win.page) < 0 ? "ReposPage.qml"
        : ({ changes: "ChangesPage.qml", history: "HistoryPage.qml", branches: "BranchesPage.qml",
             stashes: "StashesPage.qml", worktrees: "WorktreesPage.qml", github: "GitHubPage.qml",
             pulls: "ForgePage.qml", issues: "ForgePage.qml",
             repos: "ReposPage.qml" })[win.page] || "ChangesPage.qml"
      onLoaded: { item.win = win; Qt.callLater(win.refocus); }
    }
    Rectangle { anchors.left: side.right; anchors.right: parent.right; y: head.height; height: 1; color: Zenon.border }

    // ── what was just done, said once ────────────────────────────────────
    Rectangle {
      anchors.horizontalCenter: pageLoader.horizontalCenter
      anchors.bottom: foot.top
      anchors.bottomMargin: 18
      width: Math.min(saidText.implicitWidth + 32, pageLoader.width - 40)
      height: 34
      radius: Zenon.windowRadius
      color: Zenon.hud(0.85)
      border.width: 1
      border.color: win.saidBad ? Zenon.alpha(Zenon.red, 0.6) : Zenon.border
      opacity: win.said !== "" ? 1 : 0
      visible: opacity > 0
      Behavior on opacity { NumberAnimation { duration: Zenon.normal; easing.type: Easing.OutCubic } }
      Text {
        id: saidText
        anchors.centerIn: parent
        width: Math.min(implicitWidth, parent.width - 32)
        elide: Text.ElideRight
        text: win.said
        color: win.saidBad ? Zenon.red : Zenon.ink
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(15)
      }
    }

    // ── the foot ─────────────────────────────────────────────────────────
    Item {
      id: foot
      anchors.bottom: parent.bottom
      anchors.left: side.right
      anchors.right: parent.right
      // slimmer, as the head (user, 2026-10-11)
      height: 40
      Rectangle { anchors.fill: parent; color: Zenon.hintFrostBg }
      Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: Zenon.border }
      HintRow {
        rows: win.hintRows
        anchors.verticalCenter: parent.verticalCenter
        x: 16
        maxWidth: foot.width - 32 - (footBtns.width > 0 ? footBtns.width + 36 : 0)
      }
      Row {
        id: footBtns
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        Repeater {
          model: win.pageItem && win.pageItem.buttons ? win.pageItem.buttons : []
          delegate: DialogButton {
            required property var modelData
            visible: modelData.visible !== false
            label: modelData.label
            ink: modelData.ink || Zenon.muted
            primary: !!modelData.primary
            ready: modelData.ready !== false
            onClicked: modelData.run()
          }
        }
      }
    }
  }

  // ── the card ───────────────────────────────────────────────────────────
  InputShield { visible: win.carding; onClicked: win.dismiss() }
  Sheet {
    id: sheet
    shown: win.carding
    fromTop: head.height
    leftInset: side.width
    cardW: 540
    cardH: win.card && win.card.kind === "form" ? formBody.implicitHeight : confirmBody.implicitHeight
    ConfirmBody {
      id: confirmBody
      visible: !!win.card && win.card.kind === "confirm"
      width: parent.width
      question: win.card && win.card.question ? win.card.question : ""
      glyph: win.card && win.card.glyph ? win.card.glyph : ""
      glyphInk: win.card && win.card.ink ? win.card.ink : Zenon.white
      detail: win.card && win.card.detail ? win.card.detail : ""
      items: win.card && win.card.items ? win.card.items : []
      choices: win.card && win.card.choices ? win.card.choices : []
      pick: win.cardPick
      onPicked: (i) => win.cardPick = i
      onChose: (i) => win.choose(i)
      // a card about files on their way somewhere (the upload's breakdown):
      // where each lands, as the tree terminus and plato show — morpheus'
      // FileTree, of the given paths — with its size, new or replacing
      Rectangle {
        // (on the card, not `visible`: that is false while the sheet is)
        readonly property bool wanted: !!win.card && !!win.card.rows
        visible: wanted
        width: confirmBody.width - 36
        height: wanted ? Math.min(cardTree.flat.length, 10) * cardTree.rowH + 12 : 0
        radius: Zenon.windowRadius
        color: Zenon.wash(0.04)
        border.width: 1
        border.color: Zenon.border
        FileTree {
          id: cardTree
          anchors.fill: parent
          anchors.margins: 6
          window: win
          // given paths always, an empty list between cards: never the disk
          rootPath: win.card && win.card.treeRoot ? win.card.treeRoot : "repository"
          given: win.card && win.card.rows ? win.card.rows : []
          fontSize: Zenon.px(14)
          noteWidth: 150
          noteOf: (e) => e.isDir ? null : {
            text: "<font color='" + Zenon.muted + "'>" + Terminus.formatSize(e.size) + "</font>   " + (e.exists ? "replaces" : "new"),
            ink: e.exists ? Zenon.yellow : Zenon.green }
        }
      }
    }
    FormBody {
      id: formBody
      visible: !!win.card && win.card.kind === "form"
      width: parent.width
      form: win.card && win.card.kind === "form" ? win.card : null
      // a directory field's Choose…: terminus' picker, from where it points
      chooseDir: win.mgr && win.mgr.fileManager ? (start, reply) => win.mgr.fileManager.choose(true, start || win.home,
        (paths) => reply(paths && paths.length > 0 ? paths[0] : "")) : null
      onDone: (ok, values) => win.settleForm(ok, values)
    }
  }
  // a confirmation has no field to hold the keyboard: it is held here
  Item {
    id: cardKeys
    Keys.onPressed: (e) => {
      const c = win.card;
      e.accepted = true;
      if (!c || c.kind !== "confirm") return;
      const n = c.choices.length;
      if (e.key === Qt.Key_Escape) win.dismiss();
      else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) win.choose(win.cardPick);
      // the answers are drawn right to left (ConfirmBody): left is the next one
      else if (e.key === Qt.Key_Left || e.key === Qt.Key_Tab) win.cardPick = (win.cardPick + 1) % n;
      else if (e.key === Qt.Key_Right || e.key === Qt.Key_Backtab) win.cardPick = (win.cardPick + n - 1) % n;
    }
  }
  Connections {
    target: win
    function onCardChanged() {
      if (win.card && win.card.kind === "confirm") Qt.callLater(() => cardKeys.forceActiveFocus());
    }
  }

  // ── who you are, asked once ────────────────────────────────────────────
  // git refuses to commit without a name and an address; asked when it is
  // first needed (or from the sidebar), for every repository at once
  function askIdentity(then) {
    const id = win.info && win.info.identity ? win.info.identity : { name: "", email: "" };
    // the forge's account, when signed in — the one this repository is on,
    // else the Accounts page's: its name, and its private address for
    // commits (its Status: noreply) to start from
    const site = D.FORGES[win.hub ? win.hub.forge : win.mgr.forge] || D.FORGES.github;
    win.mgr.call(site.id + "Status", null, {}, (ok, gh) => {
      if (!win) return;
      const hub = ok && gh && gh.signedIn ? gh : null;
      win.ask({ title: "Who commits?", glyph: "",
        detail: "Git writes a name and an email into every commit, and will not commit without both. Set for all your repositories."
          + (hub && !id.email ? " The email below is " + site.name + "'s private one for your account: commits are linked to you, your real address stays out of them." : ""),
        fields: [{ key: "name", label: "Name", value: id.name || (hub ? hub.name || hub.login : ""), hint: "Ada Lovelace" },
                 { key: "email", label: "Email", value: id.email || (hub ? hub.noreply : ""), hint: "ada@example.com",
                   why: "git needs one" + (hub ? "" : " — your forge's private address (GitHub: Settings → Emails) works") }],
        verb: "Save",
        then: (v) => win.act("identitySet", { name: v.name.trim(), email: v.email.trim() }, {
          repo: null, said: "Saved — commits are now signed " + v.name.trim(),
          then: () => win.mgr.call("info", win.root, {}, (ok2, info) => { if (ok2) win.info = info; if (then) then(); }) }) });
    });
  }
  onRootChanged: {
    if (win.root !== "") win.mgr.call("info", win.root, {}, (ok, info) => { if (ok) win.info = info; });
    win.checkTools();
  }

  function sequence(action) {
    if (!win.state) return;
    win.act("sequence", { op: win.state.op, action: action }, { label: action === "abort" ? "Aborting" : "Continuing",
      then: (r) => { if (r && r.conflicts) win.say("Stopped on conflicts — resolve them in Changes", true); else if (r && r.done) win.say("Done"); } });
  }

  WindowTip { id: tips; window: win }
  PopMenu {
    id: repoPop
    parent: stage
    anchors.fill: parent
    window: win
    cardWidth: 340
    onClosed: win.refocus()
  }
}
