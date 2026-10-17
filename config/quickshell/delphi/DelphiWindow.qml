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
//   Releases     the forge repository's releases, and a new one with its
//                notes written for you (ReleasesPage)
//   Dotfiles     its GNU Stow packages: what stow would link, and what is
//                in the way; a config copied in; the command to run (never
//                run here — DotfilesPage, core/stow.py)
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

  // CLOSED, IT IS KEPT, hidden: built afresh on every open, the window
  // cost a 130–240 ms stall each time it came up (LagWatch, 2026-10-11 —
  // the build itself 31–41 ms, the rest its first draw). Hidden, it lets go
  // of the backend and its file watch; shown again, it takes them back and
  // looks at the repository afresh, as terminus' kept window does.
  property bool _shownOnce: false
  onVisibleChanged: {
    if (!win.mgr) return;
    if (!win.visible) {
      win.unwatch();
      win.mgr.release("window");
      return;
    }
    if (!win._shownOnce) { win._shownOnce = true; return; }
    win.mgr.hold("window");
    if (win.root !== "") { win.mgr.call("watch", win.root, {}); win.refresh(); }
    Qt.callLater(win.checkTools);
    Qt.callLater(win.refocus);
  }
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
  readonly property color hiFill: Zenon.menuHi
  readonly property string home: Quickshell.env("HOME")

  // ── THE REPOSITORY ─────────────────────────────────────────────────────
  property string root: ""
  // History narrowed to one file (DelphiManager.history), absolute; one
  // outside the open repository counts for nothing
  property string historyFile: ""
  // a blame asked for from outside (DelphiManager.blame), for History to
  // take up once it has the repository: { file, line } or null
  property var blameWanted: null
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
  // (servers of your own count: a remote on one is that server's)
  readonly property var hub: { win.mgr ? win.mgr.servers : null; return D.hubOf(win.remotes); }

  function openRepo(path) {
    if (!win.mgr) return;
    if (!path) { win.setPage("repos"); return; }
    win.mgr.call("discover", null, { path: path }, (ok, info) => {
      if (!ok || !info || info.bare) {
        // one delphi still lists, whose files went: the way off the lists,
        // rather than a toast and the same row there next time
        const listed = win.mgr.recents.some((r) => r.root === path) || win.mgr.hidden.indexOf(path) >= 0;
        if (listed && !(info && info.bare)) {
          win.card_({ question: D.baseName(path) + " is not here any more", glyph: "\uF071", ink: Zenon.yellow,
            detail: "Its directory is gone, or no longer a repository. Removing it takes it off Delphi's lists; its forge is not touched.",
            items: [D.tilde(path, win.home)],
            choices: [{ label: "Remove from Delphi", ink: Zenon.cyan, run: () => { win.mgr.drop(path); win.say("Removed " + D.baseName(path)); } },
                      { label: "Keep it listed", ink: Zenon.accentMuted }] });
          if (win.root === "") win.setPage("repos");
          return;
        }
        win.say(info && info.bare ? "A bare repository has no working tree to show" : "Not in a repository: " + D.tilde(path, win.home), true);
        if (win.root === "") win.setPage("repos");
        return;
      }
      if (info.root !== win.root) {
        win.unwatch();
        win.root = info.root;
        win.info = info;
        // a narrowed History belongs to the repository its file is in
        if (win.historyFile.indexOf(info.root + "/") !== 0) win.historyFile = "";
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
  // FORGET one: off delphi's lists, nothing on disk or on its forge touched
  // — for a repository no longer kept up. The open one is closed first, so
  // it does not come straight back. Opening it again remembers it.
  function forgetRepo(root, name) {
    if (!root || !win.mgr) return;
    if (root === win.root) { win.unwatch(); win.closeRepo(); }
    win.mgr.forget(root);
    win.say("Forgot " + (name || D.baseName(root)) + " — files and forge untouched; it waits under Forgotten in Repositories");
  }
  // APPLY A PATCH (user, 2026-10-14): a file chosen in terminus — a
  // mailbox one (History's Save as a patch, a forge's .patch) lands as its
  // commits through git am, stopping on conflicts as a rebase does; a plain
  // diff lands as staged changes (delphi/core apply_patch)
  function applyPatch() {
    if (!win.mgr.fileManager || win.root === "") return;
    win.mgr.fileManager.choose(false, win.home, (paths) => {
      if (!paths || paths.length === 0) return;
      win.act("applyPatch", { path: paths[0] }, { label: "Applying " + D.baseName(paths[0]),
        then: (r) => {
          if (r.conflicts) { win.say("Stopped on conflicts — resolve them in Changes", true); win.setPage("changes"); return; }
          win.say(r.how === "commits" ? "Applied " + D.baseName(paths[0]) + " as commits" : "Applied — the changes are staged");
          win.setPage(r.how === "commits" ? "history" : "changes");
        },
        failed: (err) => win.fail("The patch does not apply", "It may be for another version of these files, or already applied.", err) });
    });
  }
  // ARCHIVE ON ITS FORGE (user, 2026-10-14): for one no longer kept up and
  // not to be deleted — the forge's copy goes read-only (no pushes, issues
  // or pull requests; it says it is archived), and can be unarchived from
  // the Accounts page. hub: { forge, full } (D.hubOf). With o.root, the
  // copy here can be forgotten in the same go.
  function archiveOnForge(hub, o) {
    const f = D.FORGES[hub.forge];
    if (!f) return;
    const opts = o || {};
    const run = (forget) => win.act(f.id + "Archive", { full: hub.full, on: true }, { repo: null, network: true, refresh: false,
      label: "Archiving " + hub.full, said: "Archived " + hub.full + " on " + f.name + (forget ? " — and forgotten here" : ""),
      then: () => { if (forget) win.forgetRepo(opts.root, opts.name); if (opts.then) opts.then(); } });
    const choices = [{ label: "Archive", ink: Zenon.yellow, run: () => run(false) }];
    if (opts.root) choices.push({ label: "Archive and forget it here", ink: Zenon.yellow, run: () => run(true) });
    choices.push({ label: "Cancel", ink: Zenon.accentMuted });
    win.card_({ question: "Archive " + hub.full + "?", glyph: f.glyph, ink: Zenon.yellow,
      detail: "It stays on " + f.name + ", read-only: nothing can be pushed, and issues and pull requests close to new activity. "
        + "Its page says it is archived. You can unarchive it from the Accounts page."
        + (opts.root ? " Forgetting it here leaves its files where they are." : ""),
      choices: choices });
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
        if (o.stopped) o.stopped();
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
  function fetch() {
    const root = win.root;
    win.act("fetch", {}, { label: "Fetching", network: true, said: "Fetched", then: () => win.mgr.noteFetched(root) });
  }

  // ── FETCHED IN THE BACKGROUND (user, 2026-10-14) ──────────────────────
  // The open repository, every five minutes while the window is up (and a
  // few seconds after one is opened, when it was not fetched lately): so
  // Pull's ↓ and History's Incoming say what is there now. It never asks
  // for anything (delphi/core fetch_quiet), shows no pill, and a failure
  // is silent — a Fetch pressed says what is wrong.
  readonly property int fetchEvery: 5 * 60 * 1000
  property bool quietFetching: false
  function quietFetch() {
    if (!win.mgr.autoFetch || win.quietFetching || win.netBusy || win.root === "" || win.remotes.length === 0) return;
    const root = win.root;
    if (Date.now() - (win.mgr.fetchedAt[root] || 0) < win.fetchEvery - 5000) return;
    win.quietFetching = true;
    win.mgr.call("fetchQuiet", root, {}, (ok) => {
      if (!win) return;
      win.quietFetching = false;
      if (!ok) return;
      win.mgr.noteFetched(root);
      if (root === win.root) win.refresh();
    });
  }
  Timer {
    interval: 30000
    repeat: true
    running: win.visible && win.mgr && win.mgr.autoFetch && win.root !== ""
    onTriggered: win.quietFetch()
  }
  Timer { id: fetchSoon; interval: 4000; onTriggered: win.quietFetch() }
  onRemotesChanged: if (win.remotes.length > 0) fetchSoon.restart()
  // Fetch's and Pull's right-click: how each behaves
  function fetchMenu(item) {
    const items = [{ text: "Fetch now", icon: "\uF021", mark: "ctrl shift f", run: () => win.fetch() },
                   { text: "Fetch every 5 minutes, quietly", icon: win.mgr.autoFetch ? "\uF00C" : "",
                     run: () => { win.mgr.set("autoFetch", !win.mgr.autoFetch); if (win.mgr.autoFetch) win.quietFetch(); } }];
    const at = win.mgr.fetchedAt[win.root];
    if (at) items.push({ isSeparator: true }, { text: "Last fetched " + D.ago(Math.floor(at / 1000), Date.now()), icon: "\uF017", enabled: false });
    const p = item.mapToItem(stage, 0, item.height + 4);
    repoPop.open(p.x, p.y, items);
  }
  function pullMenu(item) {
    const ways = [["ff-only", "Only fast-forward"], ["rebase", "Rebase your commits onto theirs"], ["merge", "Merge when both moved"]];
    const items = [{ text: "Pull now", icon: "\uF019", mark: "ctrl shift l", enabled: !!win.branch && !!win.branch.upstream, run: () => win.pull() },
                   { isSeparator: true }];
    for (const w of ways) items.push({ text: w[1], icon: win.mgr.pullMode === w[0] ? "\uF00C" : "",
                                       run: () => win.mgr.set("pullMode", w[0]) });
    const p = item.mapToItem(stage, 0, item.height + 4);
    repoPop.open(p.x, p.y, items);
  }
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
    if (win.syncing) { win.syncAll(); return; }
    if (win.pushNothing) { win.say("Nothing to push — every place it goes has this commit"); return; }
    if (win.pushTargets.length > 0) { win.pushMany(win.pushTargets); return; }
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
      win.pushShow([remote]);
      win.act("push", { remote: remote, branch: b.head, setUpstream: true },
              { label: "Pushing", network: true, said: "Published " + b.head + " to " + remote, stopped: () => win.pushEnd(false, true), done: (ok) => win.pushEnd(ok) });
      return;
    }
    win.pushShow([b.upstream.split("/")[0]]);
    win.act("push", {}, { label: "Pushing", network: true, said: "Pushed", then: () => win.watchCi(), stopped: () => win.pushEnd(false, true), done: (ok) => win.pushEnd(ok),
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
  // ── WHERE PUSH SENDS IT ────────────────────────────────────────────────
  // (user, 2026-10-11: one forge at a time was not enough.) The remotes
  // ticked in the push menu, by name — those still there; none ticked, the
  // upstream as before. Kept per repository (DelphiManager.pushTo).
  readonly property var pushTargets: {
    const want = win.mgr && win.root !== "" ? win.mgr.pushTo[win.root] || [] : [];
    return want.filter((n) => win.remotes.some((r) => r.name === n));
  }
  // NOTHING TO PUSH: the commit you are on is already where Push would
  // send it — the upstream with nothing ahead, or every ticked remote's
  // copy of the branch at it (as last fetched or pushed). Push is dimmed
  // then (user, 2026-10-11); a branch not published anywhere never is.
  readonly property bool pushNothing: {
    const b = win.branch;
    if (!b || !b.oid || !b.head) return false;
    if (win.pushTargets.length === 0) return !!b.upstream && b.ahead === 0;
    return win.pushTargets.every((r) => {
      const e = win.refs.remote.find((x) => x.name === r + "/" + b.head);
      return !!e && e.sha === b.oid;
    });
  }
  // a remote, said by its forge where delphi knows it (GitHub, Codeberg…)
  function remoteWord(r) {
    const o = D.remoteOf(r.push || r.fetch || "");
    const f = o ? D.forgeOfHost(o.host) : null;
    return { glyph: f ? f.glyph : "\uF0C2", where: f ? f.name : o ? o.host : (r.push || r.fetch || "") };
  }
  // ── THE CHECKS ON WHAT WAS PUSHED ──────────────────────────────────────
  // The commit you are on, as each place Push sends it has it: the forge's
  // checks for it there (DelphiManager.ci), asked when the commit changes,
  // after a push, and every 15 s while any is still running or a push has
  // not had its checks start yet (ten minutes at most).
  function remoteHub(r) {
    const o = r ? D.remoteOf(r.push || r.fetch || "") : null;
    const f = o ? D.forgeOfHost(o.host) : null;
    return f ? { forge: f.id, full: o.full, name: f.name } : null;
  }
  readonly property string headSha: win.branch && win.branch.oid ? win.branch.oid : ""
  readonly property var pushNames: win.syncing ? win.remotes.map((r) => r.name) : win.pushTargets.length > 0 ? win.pushTargets
    : win.branch && win.branch.upstream ? [win.branch.upstream.split("/")[0]] : []
  function headCiOf(name) {
    win.mgr.ci;
    const h = win.remoteHub(win.remotes.find((x) => x.name === name));
    return h && win.headSha !== "" ? win.mgr.ciOf(h.forge, h.full, win.headSha) : null;
  }
  function askHeadCi() {
    if (win.headSha === "" || !win.visible) return;
    for (const n of win.pushNames) {
      const h = win.remoteHub(win.remotes.find((x) => x.name === n));
      if (h) win.mgr.ciAsk(h.forge, h.full, [win.headSha]);
    }
  }
  property real ciWatchUntil: 0
  onHeadShaChanged: Qt.callLater(win.askHeadCi)
  onPushNamesChanged: Qt.callLater(win.askHeadCi)
  Timer {
    interval: 15000
    repeat: true
    running: win.visible && win.headSha !== ""
      && (Date.now() < win.ciWatchUntil || win.pushNames.some((n) => { const c = win.headCiOf(n); return !!c && c.state === "pending"; }))
    onTriggered: win.askHeadCi()
  }
  function watchCi() { win.ciWatchUntil = Date.now() + 10 * 60 * 1000; Qt.callLater(win.askHeadCi); }

  function pushItems() {
    const t = win.pushTargets, all = win.remotes.length > 0 && t.length === win.remotes.length;
    const tick = (names) => win.mgr.setPushTo(win.root, names);
    const items = win.remotes.map((r) => {
      const on = t.indexOf(r.name) >= 0, w = win.remoteWord(r);
      return { text: r.name + "   " + w.where, icon: on ? "\uF00C" : w.glyph, keep: true,
               mark: win.branch && win.branch.upstream && win.branch.upstream.indexOf(r.name + "/") === 0 ? "upstream" : "",
               run: () => { tick(on ? t.filter((n) => n !== r.name) : t.concat([r.name])); pushPop.setItems(win.pushItems()); } };
    });
    items.push({ isSeparator: true },
      { text: "All of them", icon: all ? "\uF00C" : "\uF0E8", keep: true,
        run: () => { tick(all ? [] : win.remotes.map((r) => r.name)); pushPop.setItems(win.pushItems()); } },
      { text: "Just the upstream", icon: t.length === 0 ? "\uF00C" : "\uF062", keep: true,
        run: () => { tick([]); pushPop.setItems(win.pushItems()); } });
    if (win.remotes.length > 1) {
      const on = !!win.mgr.syncs[win.root];
      items.push({ isSeparator: true },
        { text: "Keep them all in sync", icon: on ? "\uF00C" : "\uF46A", keep: true,
          run: () => { win.mgr.setSync(win.root, !on); pushPop.setItems(win.pushItems()); } },
        { text: "Sync now", icon: "\uF021", run: () => win.syncAll() });
    }
    items.push({ isSeparator: true }, { text: "Sync with other forges…", icon: "\uF46A", run: () => win.putOnForge() });
    return items;
  }
  function pushMenu(at) {
    const p = at.mapToItem(stage, 0, at.height + 6);
    pushPop.open(p.x, p.y, win.pushItems());
  }
  // to each ticked remote in turn; one that refuses does not stop the rest
  function pushMany(names) {
    const b = win.branch, done = [], bad = [];
    win.pushShow(names);
    const next = (i) => {
      if (!win) return;
      if (i >= names.length) {
        win.pushEnd(done.length > 0);
        if (done.length > 0) win.watchCi();
        win.say(bad.length === 0 ? "Pushed to " + done.join(", ")
          : (done.length > 0 ? "Pushed to " + done.join(", ") + " — " : "") + bad.join(", ") + (bad.length === 1 ? " refused it" : " refused it"), bad.length > 0);
        win.refresh();
        return;
      }
      const r = names[i];
      const up = !!b.upstream && b.upstream.indexOf(r + "/") === 0;
      win.act("push", up ? {} : { remote: r, branch: b.head, setUpstream: !b.upstream && i === 0 }, {
        label: "Pushing to " + r + (names.length > 1 ? "  (" + (i + 1) + " of " + names.length + ")" : ""),
        network: true, refresh: false,
        then: () => { done.push(r); next(i + 1); },
        // stopped: the rest are not gone on to, and the push is over
        stopped: () => { win.pushEnd(false, true); win.refresh(); },
        failed: (err) => { bad.push(r); win.fail("Push to " + r + " did not work", null, err); next(i + 1); } });
    };
    next(0);
  }
  // ── KEPT IN SYNC ON EVERY FORGE (user, 2026-10-17) ─────────────────────
  // "Why can't I just keep the repo synced in all forges?" A repository
  // here with a remote on each forge, and Sync in place of Push: every
  // remote fetched, each branch any of them has brought to its newest tip
  // here and there (fast-forward only — a remote with commits the others
  // lack is said, never overwritten), tags everywhere (delphi/core
  // repo.sync). Turned on per repository from the push menu (mgr.syncs),
  // and by syncing a repository with other forges.
  readonly property bool syncing: !!win.mgr && win.root !== "" && !!win.mgr.syncs[win.root] && win.remotes.length > 1
  function syncAll() {
    const root = win.root;
    win.act("sync", {}, { label: "Syncing " + win.remotes.length + " remotes", network: true,
      then: (res) => {
        if (!win) return;
        win.mgr.noteFetched(root);
        win.watchCi();
        const word = (n) => { const r = win.remotes.find((x) => x.name === n); return r ? win.remoteWord(r).where : n; };
        const pushed = res.branches.filter((b) => b.pushed.length > 0);
        const moved = res.branches.filter((b) => b.moved);
        const split = res.branches.filter((b) => b.diverged.length > 0);
        const parts = [];
        if (moved.length > 0) parts.push("brought " + moved.map((b) => b.name).join(", ") + " up to date here");
        if (pushed.length > 0) {
          const where = [];
          pushed.forEach((b) => b.pushed.forEach((n) => { if (where.indexOf(n) < 0) where.push(n); }));
          parts.push("sent " + (pushed.length === 1 ? pushed[0].name : pushed.length + " branches") + " to " + where.map(word).join(", "));
        }
        if (split.length === 0 && res.failed.length === 0) {
          win.say(parts.length > 0 ? "Synced — " + parts.join("; ") : "Synced — every remote already had everything");
          return;
        }
        const items = split.map((b) => b.name + ":  " + b.diverged.map((n) => n === "here" ? "this copy" : word(n)).join(", ")
                                    + (b.diverged.length === 1 ? " has" : " have") + " commits the newest one does not")
          .concat(res.failed.map((f) => word(f.remote) + ":  " + (f.step === "fetch" ? "could not be fetched" : f.step === "tags" ? "refused some tags" : "refused the push")
                                    + " — " + D.errorText(f.error).split("\n")[0]));
        win.card_({ question: parts.length > 0 ? "Synced, mostly" : "Not everything could be synced", glyph: "", ink: Zenon.yellow,
          detail: (parts.length > 0 ? "Delphi " + parts.join("; ") + ". " : "")
            + (split.length > 0 ? "Where a branch went two ways, nothing was overwritten: merge or rebase it from Branches (its copy on each remote is there), then Sync again." : ""),
          items: items,
          choices: split.length > 0 ? [{ label: "Open Branches", ink: Zenon.cyan, run: () => win.setPage("branches") }, { label: "Close" }] : [{ label: "Close" }] });
      } });
  }
  // the name a forge's remote takes here: its id (github, gitlab, codeberg)
  // or, for a server of your own, its name — numbered if taken by another
  function remoteNameFor(f, url, rs) {
    const base = f.server ? String(f.name).toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "") || "forge" : f.id;
    let name = base, n = 2;
    const same = (r) => { const a = D.remoteOf(r.push || r.fetch || ""), b = D.remoteOf(url); return !!a && !!b && a.host === b.host && a.full.toLowerCase() === b.full.toLowerCase(); };
    while (rs.some((r) => r.name === name && !same(r))) name = base + "-" + n++;
    return name;
  }
  // SYNC WITH OTHER FORGES (user, 2026-10-17: a list to tick, the
  // buttons only to confirm or cancel): the forges it is not on yet, each
  // a tick, and nothing more asked — on each, its repository of the same
  // name if there is one, else a new one made; added as a remote, checked
  // to share this one's history (one that shares none is taken back out),
  // then kept in sync and synced once at the end
  function putOnForge(root0) {
    const root = root0 || win.root;
    if (root === "") return;
    win.mgr.call("remotes", root, {}, (ok, rs0) => {
      if (!win) return;
      const rs = ok ? rs0 : [];
      const on = rs.map((r) => { const o = D.remoteOf(r.push || r.fetch || ""); return o ? o.host : ""; });
      const left = D.FORGE_ORDER.filter((id) => on.indexOf(D.FORGES[id].host) < 0);
      if (left.length === 0) { win.say("It is on every forge Delphi knows already"); return; }
      win.ask({ title: "Sync " + D.baseName(root) + " with other forges", glyph: "\uF46A",
        detail: "On each forge ticked, it syncs with your repository of the same name — or with a new one, made for it if there is none. From then on Push is Sync: every forge kept at the same commits.",
        toggles: left.map((id) => ({ key: "f:" + id, label: D.FORGES[id].name, value: true }))
          .concat([{ key: "priv", label: "Make new ones private", value: true }]),
        verb: "Sync",
        then: (v) => {
          const ids = left.filter((id) => v["f:" + id]);
          if (ids.length === 0) { win.say("No forge ticked — nothing done"); return; }
          win.putOnMany(root, ids, !!v.priv, rs);
        } });
    });
  }
  function putOnMany(root, ids, priv, rs0) {
    const name = D.baseName(root), out = [];
    let rs = rs0.slice();
    const next = (i) => {
      if (!win) return;
      if (i >= ids.length) { win.putOnDone(root, out); return; }
      const id = ids[i], f = D.FORGES[id];
      const note = (word, ok) => { out.push({ f: f, word: word, ok: !!ok }); next(i + 1); };
      const failed = (what) => (err) => note(what + " — " + D.errorText(err ? err.error : "").split("\n")[0]);
      const join = (r, made) => {
        const remote = win.remoteNameFor(f, r.https, rs);
        win.act("mirrorAdd", { name: remote, url: r.https }, { repo: root, refresh: false, label: "Adding " + r.full, network: true,
          failed: failed("could not reach " + r.full),
          then: (res) => {
            rs = rs.concat([{ name: remote, fetch: r.https, push: r.https }]);
            if (res.empty || res.related) { note((made ? "new repository " + r.full : "your " + r.full) + " — synced", true); return; }
            // a stranger of the same name: not joined, its remote gone again
            win.mgr.call("remoteRemove", root, { name: remote }, () => {});
            rs = rs.filter((x) => x.name !== remote);
            note(res.unborn ? "left alone — " + name + " has no commits yet" : r.full + " is another repository (no history shared) — left alone");
          } });
      };
      win.act(id + "Status", {}, { repo: null, refresh: false, label: "Asking " + f.name, network: true,
        failed: failed("could not be asked"),
        then: (st) => {
          if (!st.signedIn) { note("not signed in — sign in on the Accounts page, then try again"); return; }
          win.act(id + "Repos", {}, { repo: null, refresh: false, label: "Looking for " + name + " on " + f.name, network: true,
            failed: failed("could not list your repositories"),
            then: (repos) => {
              const mine = repos.find((r) => r.name.toLowerCase() === name.toLowerCase());
              if (mine) { join(mine, false); return; }
              win.act(id + "Create", { name: name.replace(/[^A-Za-z0-9._-]+/g, "-"), private: priv, description: "" }, {
                repo: null, refresh: false, label: "Creating " + name + " on " + f.name, network: true,
                failed: failed("could not create " + name),
                then: (r) => join(r, true) });
            } });
        } });
    };
    next(0);
  }
  // what happened on each, said once: all well, a toast and the sync;
  // anything not, a card listing every forge
  function putOnDone(root, out) {
    const joined = out.filter((o) => o.ok);
    if (joined.length > 0) {
      win.mgr.setSync(root, true);
      if (root !== win.root) win.openRepo(root);
      Qt.callLater(() => { if (win && win.root === root) { win.refresh(); win.syncAll(); } });
    }
    if (joined.length === out.length) {
      win.say("Syncing with " + joined.map((o) => o.f.name).join(", ") + " — Push is Sync from now on");
      return;
    }
    win.card_({ question: joined.length > 0 ? "Synced with " + joined.map((o) => o.f.name).join(", ") : "Not synced anywhere", glyph: "\uF46A",
      ink: joined.length > 0 ? Zenon.ink : Zenon.yellow,
      detail: joined.length > 0 ? "Those are synced now, and Push is Sync from now on." : "",
      items: out.map((o) => o.f.name + ":  " + o.word),
      choices: [{ label: "Close" }] });
  }
  // the remote added and looked at: related or empty, synced at once and
  // kept in sync; a history that shares nothing is said, the remote taken
  // back out unless kept
  function joinForge(root, f, r, rs0) {
    const go = (rs) => {
      const remote = win.remoteNameFor(f, r.https, rs);
      win.act("mirrorAdd", { name: remote, url: r.https }, { repo: root, label: "Adding " + r.full, network: true,
        then: (res) => {
          if (!win) return;
          if (res.empty || res.related) {
            win.mgr.setSync(root, true);
            if (root !== win.root) win.openRepo(root);
            win.say((res.empty ? r.full + " is empty — " : "Same history as " + r.full + " — ") + "syncing; Push is Sync from now on");
            Qt.callLater(() => { if (win && win.root === root) win.syncAll(); });
            return;
          }
          win.card_({ question: r.full + " is another repository", glyph: f.glyph, ink: Zenon.yellow,
            detail: res.unborn ? D.baseName(root) + " has no commits yet. Connect it from the Accounts page instead: it takes " + r.full + "'s history in."
              : "Its history and " + D.baseName(root) + "'s share no commit, so syncing would only make a mess. The remote " + remote + " was added; take it back out?",
            choices: [{ label: "Take it out", ink: Zenon.cyan, run: () => win.act("remoteRemove", { name: remote }, { repo: root, said: "Took " + remote + " back out" }) },
                      { label: "Keep the remote" }] });
        } });
    };
    if (rs0) go(rs0);
    else win.mgr.call("remotes", root, {}, (ok, rs) => { if (win) go(ok ? rs : []); });
  }
  // WHICH FORGE: answers on the card while two fit beside Cancel (the
  // card is a fixed width), else a dropdown on a form
  function pickForge(question, ids, then, detail) {
    if (ids.length <= 2) {
      win.card_({ question: question, glyph: "\uF0C2", ink: Zenon.ink, detail: detail || "",
        choices: ids.map((id) => ({ label: D.FORGES[id].name, ink: Zenon.cyan, run: () => then(id) }))
          .concat([{ label: "Cancel", ink: Zenon.accentMuted }]) });
      return;
    }
    win.ask({ title: question, glyph: "\uF0C2", detail: detail || "",
      fields: [{ key: "forge", label: "Forge", options: ids.map((id) => D.FORGES[id].name) }],
      verb: "Next",
      then: (v) => { const id = ids.find((x) => D.FORGES[x].name === v.forge); if (id) then(id); } });
  }
  // the Accounts page, signing in to one forge (it asks once it is up)
  property string wantSignIn: ""
  function signInTo(id) {
    win.wantSignIn = id;
    win.setPage("github");
    if (win.pageItem && win.pageItem.signInWanted) win.pageItem.signInWanted();
  }
  function forcePush() {
    win.confirm({ question: "Force-push " + win.branchName + "?", glyph: "", ink: Zenon.red,
      detail: "Replaces the remote branch with yours. With a lease: refused if it moved since you last fetched.",
      verb: "Force-push", then: () => {
        if (win.branch && win.branch.upstream) win.pushShow([win.branch.upstream.split("/")[0]]);
        win.act("push", { force: true }, { label: "Pushing", network: true, said: "Pushed", stopped: () => win.pushEnd(false, true), done: (ok) => win.pushEnd(ok) });
      } });
  }

  // ── WHAT A PUSH SENDS, popped from the pill (user, 2026-10-14) ─────────
  // The commits going out, as the remote's copy of the branch does not have
  // them yet (repo.changelog since it), in a Bubble from the "Pushing" pill
  // for as long as the push runs and a moment after it lands. A branch no
  // remote has yet goes whole: said, not listed.
  //   { where, commits (null while read), more, state going|done|failed|stopped }
  property var pushing: null
  readonly property int pushListMax: 12
  function pushShow(names) {
    const b = win.branch;
    if (!b || !b.head) return;
    pushLinger.stop();
    let since = "";
    for (const r of names) {
      const e = win.refs.remote.find((x) => x.name === r + "/" + b.head);
      if (e) { since = e.name; break; }
    }
    if (since === "" && b.upstream) since = b.upstream;
    win.pushing = { where: names.join(", "), branch: b.head, commits: since === "" ? [] : null,
                    whole: since === "", more: 0, state: "going" };
    if (since === "") return;
    win.mgr.call("changelog", win.root, { since: since, until: "HEAD" }, (ok, cs) => {
      if (!win || !win.pushing) return;
      const list = ok && cs ? cs : [];
      win.pushing = Object.assign({}, win.pushing, {
        commits: list.slice(0, win.pushListMax), more: Math.max(0, list.length - win.pushListMax) });
    });
  }
  function pushEnd(ok, stopped) {
    // once: a stopped push is also done (act's done after its stopped)
    if (!win.pushing || win.pushing.state !== "going") return;
    win.pushing = Object.assign({}, win.pushing, { state: ok ? "done" : stopped ? "stopped" : "failed" });
    pushLinger.restart();
  }
  Timer { id: pushLinger; interval: 2600; onTriggered: win.pushing = null }

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
                  { label: "OK", ink: Zenon.accentMuted }] });
      return;
    }
    win.card_({ question: title, glyph: "", ink: Zenon.red, detail: detail || "",
      items: text.split("\n"), choices: [{ label: "OK", ink: Zenon.accentMuted }] });
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
  // delphi/CardSheet — the queue, the sheet and its bodies; git's own
  // question goes first, as its `lead`
  readonly property var gitAsk: win.mgr && win.mgr.asks.length > 0 ? win.mgr.asks[0] : null
  readonly property var card: cards.card
  readonly property bool carding: cards.carding
  function card_(c) { return cards.card_(c); }
  function dropCard(id) { cards.dropCard(id); }
  function confirm(c) { return cards.confirm(c); }
  function ask(form) { return cards.ask(form); }
  function dismiss() { cards.dismiss(); }
  // git's or ssh's question, as a card: a password hidden, a username typed,
  // a host key read and agreed to
  function askForm(q) {
    const a = D.askCard(q);
    if (a.confirm) return { kind: "confirm", gitAsk: q.ask, question: a.title,
      glyph: "", ink: Zenon.yellow, detail: "", items: a.detail.split("\n").filter((l) => l.trim() !== ""),
      choices: [{ label: "Trust it", ink: Zenon.yellow }, { label: "Cancel", ink: Zenon.accentMuted }] };
    if (a.secret) return { kind: "form", gitAsk: q.ask, title: a.title, glyph: "", ink: Zenon.red,
      secret: { key: "answer", prompt: "input your " + a.title.toLowerCase(), purpose: a.detail }, verb: "Send" };
    return { kind: "form", gitAsk: q.ask, title: a.title, glyph: "", detail: a.detail,
      fields: [{ key: "answer", hint: a.title }], verb: "Send" };
  }

  // ── PAGES ──────────────────────────────────────────────────────────────
  // In three groups, each under its heading (user, 2026-10-11: the list
  // wanted a more logical arrangement): this repository's own work, its
  // forge's (named for the forge it is on), and what is not about one
  // repository. Ctrl 1–9 follow this order.
  readonly property var pages: [
    { id: "changes", label: "Changes", glyph: "", group: "repo" },
    { id: "history", label: "History", glyph: "", group: "repo" },
    { id: "branches", label: "Branches", glyph: "", group: "repo" },
    { id: "stashes", label: "Stashes", glyph: "", group: "repo" },
    { id: "worktrees", label: "Worktrees", glyph: "", group: "repo" },
    { id: "dotfiles", label: "Dotfiles", glyph: "\uF487", group: "repo" },
    { id: "pulls", label: win.hub && D.FORGES[win.hub.forge] ? D.FORGES[win.hub.forge].pulls : "Pull requests", glyph: "\uF407", group: "forge" },
    { id: "issues", label: "Issues", glyph: "\uF41B", group: "forge" },
    { id: "releases", label: "Releases", glyph: "\uF412", group: "forge" },
    { id: "repos", label: "Repositories", glyph: "", group: "all" },
    { id: "github", label: "Accounts", glyph: "\uF0C2", group: "all" },
  ]
  function groupWord(g) {
    return g === "repo" ? "Repository"
      : g === "forge" ? (win.hub && D.FORGES[win.hub.forge] ? D.FORGES[win.hub.forge].name : "Forge")
      : "Everywhere";
  }
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
    // Escape stops a fetch, pull or push, and never closes the window
    // (user, 2026-10-15) — a window you work in is closed on purpose
    if (k === Qt.Key_Escape) {
      if (win.netJob) win.stop(win.netJob.id);
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
                       ["ctrl r", "refresh"]].concat(win.netJob ? [["esc", "stop"]] : []));
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
    items.push({ text: "Open a directory", icon: "\uF07C", mark: "ctrl o", run: () => win.chooseRepo() },
               { text: "Clone", icon: "\uF019", run: () => { win.setPage("repos"); Qt.callLater(() => { if (win.pageItem && win.pageItem.clone) win.pageItem.clone(); }); } },
               { text: "All repositories", icon: "\uF03A", run: () => win.setPage("repos") });
    if (win.root !== "") {
      const name = D.baseName(win.root), root = win.root;
      items.push({ isSeparator: true }, { text: "Apply a patch…", icon: "\uF0EA", run: () => win.applyPatch() },
                 { text: "Sync with other forges…", icon: "\uF46A", run: () => win.putOnForge(root) });
      if (win.remotes.length > 1) items.push({ text: win.syncing ? "Stop keeping its remotes in sync" : "Keep its remotes in sync", icon: "\uF021",
                                               run: () => win.mgr.setSync(root, !win.mgr.syncs[root]) });
      if (win.hub) items.push({ text: "Archive on " + (D.FORGES[win.hub.forge] ? D.FORGES[win.hub.forge].name : win.hub.host) + "…", icon: "\uF187",
                                run: () => win.archiveOnForge(D.hubOf(win.remotes, true) || win.hub, { root: root, name: name }) });
      items.push({ isSeparator: true },
                 { text: "Forget " + name, icon: "\uF070", run: () => win.forgetRepo(root, name) });
    }
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

      // TERMINUS' AND PLATO'S TWO LAYERS (user, 2026-10-14: "all must
      // match"): an inactive tab's thinner glass, then the sheet's veil
      // over it. The veil alone left this a pale band beside them.
      Rectangle { anchors.fill: parent; color: Zenon.alpha(Zenon.tabAwayInk, Zenon.tabAway(Zenon.layerBg.a)) }
      Rectangle { anchors.fill: parent; color: Zenon.ground; opacity: 0.6 }
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
        // pressed, darker — and kept so while its menu is open (user,
        // 2026-10-11: no ring, the press itself held). The suite's shade
        // since 2026-10-15, the fill only: the words keep their ink (user)
        color: repoPress.pressed || repoPop.isOpen ? Zenon.pressFill : Zenon.wash(0.04)
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
            color: win.branch && !win.branch.head ? Zenon.yellow : Zenon.accentMuted
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
          color: repoPop.isOpen ? Zenon.cyan : Zenon.accentMuted
          rotation: repoPop.isOpen ? 180 : 0
          Behavior on rotation { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.travelEase } }
          font.family: Zenon.glyphFace
          font.pixelSize: Zenon.px(11)
        }
        MouseArea {
          id: repoPress
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
        // the first heading brings its own air (SideHead's airIn)
        anchors.topMargin: 4
        // edge to edge: the cursor spans the sidebar (user, 2026-10-11)
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 1
        Repeater {
          model: win.pages
          delegate: Column {
            id: pageItem
            required property var modelData
            required property int index
            width: pageCol.width
            // a group's heading over its first page (terminus' SideHead)
            SideHead {
              visible: pageItem.index === 0 || win.pages[pageItem.index - 1].group !== pageItem.modelData.group
              first: pageItem.index === 0
              ruled: false
              label: win.groupWord(pageItem.modelData.group)
            }
          ShelfRow {
            id: pageRow
            readonly property var modelData: pageItem.modelData
            width: pageCol.width
            radius: 0
            indent: 18
            glyph: pageRow.modelData.glyph
            label: pageRow.modelData.label
            count: win.countOf(pageRow.modelData.id)
            countInk: pageRow.modelData.id === "changes" && win.st && win.st.conflicts.length > 0 ? Zenon.red : Zenon.accentMuted
            here: win.page === pageRow.modelData.id
            fill: win.hiFill
            opacity: win.root === "" && ["github", "repos"].indexOf(pageRow.modelData.id) < 0 ? 0.4 : 1
            onClicked: win.setPage(pageRow.modelData.id)
          }
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
            color: Zenon.accentSoft
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
                color: Zenon.accentSoft
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
        color: win.info && win.info.identity && win.info.identity.name === "" ? Zenon.yellow : Zenon.accentMuted
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

    // ── AND WHAT IS STILL TO COME, UNDER THE FOOT ────────────────────────
    // The same frost turned over (user, 2026-10-11): rows past a view's
    // bottom rise out of the hint bar. Only views that run down to it — a
    // page names them (footViews) when some of its views stop short, at a
    // reply or a commit box; otherwise its edgeViews.
    Repeater {
      model: !win.pageItem ? [] : win.pageItem.footViews !== undefined ? win.pageItem.footViews
        : win.pageItem.edgeViews || []
      delegate: ScrollEdge {
        required property var modelData
        view: modelData
        below: true
        follow: true
        bar: foot
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
          id: headSub
          anchors.left: headTitle.right
          anchors.leftMargin: 12
          anchors.baseline: headTitle.baseline
          width: Math.min(implicitWidth, parent.width - x - (pushChip.visible ? pushChip.width + 12 : 0))
          elide: Text.ElideMiddle
          text: win.pageItem && win.pageItem.subtitle !== undefined ? win.pageItem.subtitle : D.tilde(win.root, win.home)
          color: Zenon.accentMuted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(14)
        }
        // ── WHERE PUSH GOES, beside the branch (a page that says so) ──
        // Each remote it pushes to, by its forge's glyph and name: the
        // ticked ones, or the upstream; with a choice of remotes, a click
        // opens the menu to tick them (pushItems).
        Rectangle {
          id: pushChip
          readonly property var names: win.syncing ? win.remotes.map((r) => r.name) : win.pushTargets.length > 0 ? win.pushTargets
            : win.branch && win.branch.upstream ? [win.branch.upstream.split("/")[0]] : []
          readonly property bool choice: win.remotes.length > 0
          visible: !!win.pageItem && !!win.pageItem.showsPush && win.root !== "" && win.remotes.length > 0
          anchors.left: headSub.right
          anchors.leftMargin: 12
          anchors.verticalCenter: headTitle.verticalCenter
          width: chipRow.implicitWidth + 22
          height: Math.round(Zenon.px(14) * 2)
          radius: height / 2
          color: chipPress.pressed ? Zenon.pressFill : Zenon.wash(0.05)
          border.width: 1
          border.color: Zenon.border
          Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: 7
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "\uF062"
              color: Zenon.accentMuted
              font.family: Zenon.glyphFace
              font.pixelSize: Zenon.px(11)
            }
            Repeater {
              model: pushChip.names.length > 0 ? pushChip.names : ["—"]
              delegate: Row {
                required property var modelData
                required property int index
                readonly property var r: win.remotes.find((x) => x.name === modelData) || null
                readonly property var w: r ? win.remoteWord(r) : null
                spacing: 5
                anchors.verticalCenter: parent.verticalCenter
                Text {
                  visible: index > 0
                  anchors.verticalCenter: parent.verticalCenter
                  text: "+"
                  color: Zenon.accentMuted
                  font.family: Zenon.face
                  font.pixelSize: Zenon.px(13)
                }
                Text {
                  visible: !!parent.w
                  anchors.verticalCenter: parent.verticalCenter
                  text: parent.w ? parent.w.glyph : ""
                  color: Zenon.cyan
                  font.family: Zenon.glyphFace
                  font.pixelSize: Zenon.px(13)
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  // the forge's name where it is one delphi knows, else the remote's
                  text: !parent.r ? "not published"
                    : parent.w && D.forgeOfHost((D.remoteOf(parent.r.push || parent.r.fetch || "") || {}).host) ? parent.w.where : modelData
                  color: Zenon.ink
                  font.family: Zenon.face
                  font.weight: Zenon.weight
                  font.pixelSize: Zenon.px(13)
                }
                // its checks on the commit you are on, there
                CiDot {
                  anchors.verticalCenter: parent.verticalCenter
                  size: Zenon.px(8)
                  c: win.headCiOf(modelData)
                }
              }
            }
            Text {
              visible: pushChip.choice
              anchors.verticalCenter: parent.verticalCenter
              text: "\uF078"
              color: pushPop.isOpen ? Zenon.cyan : Zenon.accentMuted
              rotation: pushPop.isOpen ? 180 : 0
              Behavior on rotation { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.travelEase } }
              font.family: Zenon.glyphFace
              font.pixelSize: Zenon.px(10)
            }
          }
          MouseArea {
            id: chipPress
            anchors.fill: parent
            enabled: pushChip.choice
            onClicked: win.pushMenu(pushChip)
          }
          HeldRing { anchors.fill: parent; radius: parent.radius; z: 10; on: pushPop.isOpen }
          HoverHandler { id: chipHover }
          // resting on it: each place's checks, each a click from its log
          Bubble {
            window: win
            target: pushChip
            sticky: true
            shown: chipHover.hovered && !pushPop.isOpen && pushChip.names.some((n) => { const c = win.headCiOf(n); return !!c && c.state !== "none"; })
            cardWidth: 380
            Repeater {
              model: pushChip.names
              delegate: Column {
                id: rc
                required property var modelData
                readonly property var c: win.headCiOf(modelData)
                readonly property var h: win.remoteHub(win.remotes.find((x) => x.name === modelData))
                visible: !!c && c.state !== "none"
                width: 352
                spacing: 6
                Text {
                  width: parent.width
                  elide: Text.ElideRight
                  textFormat: Text.StyledText
                  text: "<b>" + (rc.h ? rc.h.name : rc.modelData) + "</b>  <font color='" + Zenon.hex(Zenon.accentMuted) + "'>" + D.ciWords(rc.c) + "</font>"
                  color: Zenon.ink
                  font.family: Zenon.face
                  font.weight: Zenon.weight
                  font.pixelSize: Zenon.px(14)
                }
                CiRuns { width: parent.width; c: rc.c; most: 6 }
              }
            }
          }
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
            // POPS ON ITS OWN while the upload runs, and a moment after it
            // lands, as a push's does (user, 2026-10-14); then on hover
            shown: !!win.mgr.upload && (upHover.hovered || upBubble.popped)
            property bool popped: false
            readonly property bool running: !!win.mgr.upload && upPill.phase !== "done" && upPill.phase !== "failed"
            onRunningChanged: { if (upBubble.running) { upLinger.stop(); upBubble.popped = true; } else upLinger.restart(); }
            Component.onCompleted: upBubble.popped = upBubble.running
            Timer { id: upLinger; interval: 2600; onTriggered: upBubble.popped = false }
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
              color: upPill.phase === "failed" ? Zenon.red : upPill.phase === "done" ? Zenon.green : Zenon.accentMuted
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.features: { "tnum": 1 }
              font.pixelSize: Zenon.px(13)
            }
          }
        }
        Rectangle {
          id: netPill
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
            // the bubble says what is going; the tip only while it is not up
            onContainsMouseChanged: containsMouse && !pushBubble.shown ? tips.show(parent, "Stop", "esc") : tips.hide(parent)
          }
        }
        // the commits a push is sending (win.pushing); it hangs from the pill
        // while it runs, and from Push once it has landed
        Bubble {
          id: pushBubble
          window: win
          target: netPill.visible ? netPill : pushBtn
          // not while the page holds the push in its own place (Changes, clean)
          shown: !!win.pushing && win.visible && !(win.pageItem && win.pageItem.holdsPush)
          cardWidth: 460
          PushSummary { p: win.pushing; lineWidth: 460 - 28 }
        }
        DialogButton {
          id: fetchBtn
          visible: !win.netBusy && win.root !== ""
          label: "Fetch"
          onClicked: win.fetch()
          MouseArea { anchors.fill: parent; acceptedButtons: Qt.RightButton; onClicked: win.fetchMenu(fetchBtn) }
        }
        DialogButton {
          id: pullBtn
          visible: !win.netBusy && win.root !== ""
          label: win.branch && win.branch.behind > 0 ? "Pull  ↓" + win.branch.behind : "Pull"
          ink: win.branch && win.branch.behind > 0 ? Zenon.cyan : Zenon.accentMuted
          ready: !!win.branch && !!win.branch.upstream
          onClicked: win.pull()
          MouseArea { anchors.fill: parent; acceptedButtons: Qt.RightButton; onClicked: win.pullMenu(pullBtn) }
        }
        // Push: where it goes is the chip beside the page's title (pushChip)
        Row {
          visible: !win.netBusy && win.root !== ""
          spacing: 2
          DialogButton {
            id: pushBtn
            readonly property int n: win.pushTargets.length
            label: !win.branch ? "Push"
              : win.syncing ? "Sync" + (win.branch.ahead > 0 ? "  ↑" + win.branch.ahead : "")
              : pushBtn.n > 1 ? (pushBtn.n === win.remotes.length ? "Push to all" : "Push to " + pushBtn.n)
                + (win.branch.ahead > 0 ? "  ↑" + win.branch.ahead : "")
              : pushBtn.n === 1 ? "Push to " + win.pushTargets[0]
              : !win.branch.upstream && win.branch.head ? "Publish"
              : win.branch.ahead > 0 ? "Push  ↑" + win.branch.ahead : "Push"
            ink: win.syncing ? Zenon.cyan : !win.pushNothing && win.branch && (win.branch.ahead > 0 || pushBtn.n > 0 || (!win.branch.upstream && win.branch.head)) ? Zenon.cyan : Zenon.accentMuted
            ready: win.syncing || !win.pushNothing
            primary: !win.syncing && !win.pushNothing && !!win.branch && (win.branch.ahead > 0 || pushBtn.n > 0) && win.branch.behind === 0
            onClicked: win.push()
          }
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
             stashes: "StashesPage.qml", worktrees: "WorktreesPage.qml", dotfiles: "DotfilesPage.qml", releases: "ReleasesPage.qml", github: "GitHubPage.qml",
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
      // the head's translucent ground: the rows under it (the foot's
      // ScrollEdges) show through frosted, as under the head
      Rectangle { anchors.fill: parent; color: Zenon.headBg }
      Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: Zenon.border }
      HintRow {
        rows: win.hintRows
        anchors.verticalCenter: parent.verticalCenter
        // centered while the strip is only keys; at the left once a button
        // joins it (as ceres' foot) — a Row of hidden children is zero wide
        x: footBtns.width > 0 ? 16 : Math.round((foot.width - width) / 2)
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
            ink: modelData.ink || Zenon.accentMuted
            primary: !!modelData.primary
            ready: modelData.ready !== false
            onClicked: modelData.run()
          }
        }
      }
    }
  }

  // ── the card ───────────────────────────────────────────────────────────
  CardSheet {
    id: cards
    fromTop: head.height
    leftInset: side.width
    cardW: 540
    lead: win.gitAsk ? win.askForm(win.gitAsk) : null
    onLeadChose: (i) => win.mgr.answer(win.gitAsk.ask, i === 0 ? "yes" : "no")
    onLeadSettled: (ok, values) => win.mgr.answer(win.gitAsk.ask, ok ? values.answer : null)
    onCleared: win.refocus()
    // a terminus picker for a FormBody directory field, from where it points
    chooseDir: win.mgr && win.mgr.fileManager ? (start, reply) => win.mgr.fileManager.choose(true, start || win.home,
      (paths) => reply(paths && paths.length > 0 ? paths[0] : "")) : null
    // a card about files on their way somewhere (the upload's breakdown):
    // where each lands, as the tree terminus and plato show — morpheus'
    // FileTree, of the given paths — with its size, new or replacing
    Rectangle {
      // (on the card, not `visible`: that is false while the sheet is)
      readonly property bool wanted: !!win.card && !!win.card.rows
      visible: wanted
      width: cards.cardW - 36
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
          text: "<font color='" + Zenon.accentMuted + "'>" + Terminus.formatSize(e.size) + "</font>   " + (e.exists ? "replaces" : "new"),
          ink: e.exists ? Zenon.yellow : Zenon.green }
      }
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
    win.mgr.call("signingStatus", null, {}, (okS, sig) => {
    win.mgr.call(site.id + "Status", null, {}, (ok, gh) => {
      if (!win) return;
      const hub = ok && gh && gh.signedIn ? gh : null;
      const signing = okS && sig ? sig : { on: false };
      win.ask({ title: "Who commits?", glyph: "",
        detail: "Git writes a name and an email into every commit, and will not commit without both. Set for all your repositories."
          + (hub && !id.email ? " The email below is " + site.name + "'s private one for your account: commits are linked to you, your real address stays out of them." : ""),
        fields: [{ key: "name", label: "Name", value: id.name || (hub ? hub.name || hub.login : ""), hint: "Ada Lovelace" },
                 { key: "email", label: "Email", value: id.email || (hub ? hub.noreply : ""), hint: "ada@example.com",
                   why: "git needs one" + (hub ? "" : " — your forge's private address (GitHub: Settings → Emails) works") }],
        toggles: [{ key: "sign", label: "Sign my commits with an SSH key — forges show them as Verified", value: !!signing.on }],
        verb: "Save",
        then: (v) => win.act("identitySet", { name: v.name.trim(), email: v.email.trim() }, {
          repo: null, said: "Saved — commits are now made by " + v.name.trim(),
          then: () => {
            win.mgr.call("info", win.root, {}, (ok2, info) => { if (ok2) win.info = info; if (then) then(); });
            if (!!v.sign && !signing.on) win.askSigning(v.email.trim());
            else if (!v.sign && signing.on) win.act("signingOff", {}, { repo: null, said: "Commits are no longer signed" });
          } }) });
    });
    });
  }

  // ── SIGNING COMMITS (core/signing.py) ──────────────────────────────────
  // With an SSH key: one already there, or one made for it; git told to
  // sign every commit and tag with it; then, where you are signed in, the
  // key registered with the forge as a signing key, so it shows Verified.
  // ssh-keygen missing: Ceres installs openssh first.
  function askSigning(email) {
    win.mgr.call("signingStatus", null, {}, (ok, st) => {
      if (!win || !ok) return;
      if (!st.keygen) {
        win.card_({ question: "Signing needs openssh", glyph: "\uF084", ink: Zenon.ink,
          detail: "git signs with ssh-keygen, which comes with openssh — not installed. Ceres can install it (it asks for your password).",
          choices: [{ label: "Install openssh", ink: Zenon.cyan, run: () => win.mgr.installTool("openssh", "for signing your commits", (done) => { if (done && win) win.askSigning(email); }) },
                    { label: "Cancel", ink: Zenon.accentMuted }] });
        return;
      }
      const use = (key, create) => win.act("signingSetup", { key: key, create: create, email: email }, {
        repo: null, label: create ? "Making a signing key" : "Setting up signing",
        then: (r) => { if (win) win.offerSigningKey(r); } });
      const choices = st.keys.map((k) => ({ label: "Use " + D.baseName(k.path).replace(/\.pub$/, ""), run: () => use(k.path, false) }));
      choices.push({ label: "Make a new key for signing", ink: Zenon.cyan, run: () => use("", true) }, { label: "Cancel", ink: Zenon.accentMuted });
      win.card_({ question: "Sign with which key?", glyph: "\uF084", ink: Zenon.ink,
        detail: (st.keys.length > 0 ? "Your SSH keys are below, or make one only for signing. " : "There is no SSH key here yet. ")
          + "A new one is made without a passphrase, so git signs without asking — kept in ~/.ssh, readable by you alone.",
        items: st.keys.map((k) => D.tilde(k.path, win.home) + (k.comment ? "  ·  " + k.comment : "")),
        choices: choices });
    });
  }
  // the key, registered with each forge you are signed in to (asked first)
  function offerSigningKey(r) {
    const ids = D.FORGE_ORDER.slice();
    const found = [];
    let left = ids.length;
    const ask = () => {
      if (!win) return;
      if (found.length === 0) { win.say("Commits are signed now — add the key to your forge so they show Verified"); return; }
      win.card_({ question: "Commits are signed now", glyph: "\uF00C", ink: Zenon.green,
        detail: "For them to show as Verified, the forge needs the key — as a signing key. Add it to "
          + found.map((f) => f.name).join(" and ") + "?",
        items: [r.public.slice(0, 60) + "…"],
        choices: [{ label: "Add it", ink: Zenon.cyan, run: () => found.forEach((f) =>
                      win.act(f.id + "AddSigningKey", { key: r.public, title: "delphi signing (" + win.home.split("/").pop() + ")" }, {
                        repo: null, network: true, label: "Adding the key to " + f.name, refresh: false,
                        then: (res) => win.say(res.already ? f.name + " already has it" : "Added to " + f.name
                          + (res.verify ? " — confirm it there once: " + res.verify : "")),
                        failed: (err) => win.fail("Could not add the key to " + f.name, null, err) })) },
                  { label: "Copy the key", run: () => win.copy(r.public, "the public key") },
                  { label: "Not now", ink: Zenon.accentMuted }] });
    };
    for (const id of ids) {
      win.mgr.call(D.FORGES[id].id + "Status", null, {}, (ok, st) => {
        if (ok && st && st.signedIn) found.push(D.FORGES[id]);
        if (--left === 0) ask();
      });
    }
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
  // where Push goes: the remotes, ticked; stays up while you tick
  PopMenu {
    id: pushPop
    parent: stage
    anchors.fill: parent
    window: win
    cardWidth: 330
    onClosed: win.refocus()
  }
  PopMenu {
    id: repoPop
    parent: stage
    anchors.fill: parent
    window: win
    cardWidth: 340
    onClosed: win.refocus()
  }
}
