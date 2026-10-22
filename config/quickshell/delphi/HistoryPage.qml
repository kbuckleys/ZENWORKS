// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// HISTORY — every branch's commits on one graph, newest first, read a page
// at a time from one `git log` the backend keeps open (so the 100 000th
// commit costs what the first did); the chosen commit beside them: its
// message, its files, and a file's diff.
//
// From a commit (its menu, or the keys): copy its id, a branch there, check
// it out, cherry-pick it onto yours, revert it, move your branch to it, or
// rework everything after it — reorder, reword, squash, drop — in the plan
// (RebasePlan.qml), which runs as one interactive rebase.
//
// Which history (v): this branch, incoming, Compare (two refs: what one
// has that the other lacks, and the whole difference), Lost (commits no
// ref holds any more — the reflog's and dangling ones, each with what left
// it, to branch or cherry-pick back), and every repository.
//
//   ↑↓ commits · tab its files · / search (s: messages or the changes
//   themselves) · c copy id · b branch here · p cherry-pick · i rework from
//   here · menu: everything else (a patch of it, too)

import QtQuick
import Quickshell
import "../morpheus"
import "../terminus"
import "delphi.js" as D
import "../terminus/terminus.js" as Terminus
import "../morpheus/icons.js" as Icons

Item {
  id: pg
  property var win: null
  // the views whose rows carry on up under the window's head, frosted
  // (DelphiWindow's ScrollEdges) — only those with nothing but controls
  // between them and the head: a view under a title would paint over it
  readonly property var edgeViews: pg.planning ? [] : pg.scope === "all" ? [acrossList] : [list, fileList]
  // the views that run down to the foot (the files stop at the diff)
  readonly property var footViews: pg.planning ? [] : pg.scope === "all" ? [acrossList] : [list, diff.view]

  readonly property string title: pg.planning ? "Rework " + plan.steps.length + " commits" : "History"
  readonly property string subtitle: pg.planning ? "onto " + D.short(plan.base) + "  ·  drag or alt ↑↓ to reorder"
    : pg.scope === "all" ? pg.across.length + " repositories, newest first in each"
    : pg.scope === "compare" ? (!pg.cmpReady ? "Choose two branches or tags"
        : pg.cmpCount ? pg.cmpTo + " has " + pg.cmpCount.right + (pg.cmpCount.right === 1 ? " commit " : " commits ") + pg.cmpFrom + " lacks"
          + (pg.cmpCount.left > 0 ? "  ·  " + pg.cmpCount.left + " the other way" : "") : "")
    : pg.scope === "lost" ? (pg.lostLoading ? "Looking through the reflogs…"
        : pg.commits.length === 0 && pg.ended ? "Nothing lost — every commit is on a branch"
        : pg.commits.length + " commits no branch holds  ·  kept about 90 days  ·  b branch, p cherry-pick")
    : pg.scope === "incoming" ? (pg.win && pg.win.branch && pg.win.branch.upstream
        ? (pg.commits.length === 0 && pg.ended ? "nothing incoming — up to date with " : pg.commits.length + " not pulled yet from ") + pg.win.branch.upstream
        : "this branch follows nothing upstream")
    : pg.commits.length + (pg.ended ? "" : "+") + (pg.commits.length === 1 && pg.ended ? " commit" : " commits") + (pg.onlyPath !== "" ? " to " + pg.onlyPath : "")
      + (pg.query !== "" ? (pg.searchIn === "changes" ? " that added or removed “" : " matching “") + pg.query + "”" : "")
  readonly property var hints: pg.planning ? plan.hints
    : pg.area === "files" ? [["↑↓", "files"], ["shift ↑↓", "diff"], ["e", "edit"], ["w", pg.blamePath !== "" ? "the diff" : "who wrote it"]]
        .concat(pg.shownFiles[pg.fileSel] && pg.shownFiles[pg.fileSel].status === "D" && pg.scope !== "all" ? [["r", "bring back"]] : []).concat([["tab", "commits"]])
    : pg.scope === "all" ? [["↑↓", "commits"], ["tab", "files"], ["return", "open there"], ["v", "which history"]]
    : pg.scope === "compare" && pg.whole ? [["↓", "its commits"], ["tab", "files"], ["x", "swap"], ["v", "which history"]]
    : [["↑↓", "commits"], ["tab", "files"], ["v", "which history"], ["/", "search"], ["s", pg.searchIn === "changes" ? "search messages" : "search changes"]]
      .concat(pg.scope === "compare" ? [["a", "the whole difference"], ["x", "swap"]] : []).concat([["c", "copy id"], ["b", "branch here"],
       ["p", "cherry-pick"], ["i", "rework from here"], ["f", "only a file"], ["menu", "more"]]).concat(pg.onlyPath !== "" ? [["esc", "every file"]] : [])
  // what the chosen commit removed: each can be brought back from it
  readonly property var removed: pg.commit && pg.commit.range ? [] : pg.shownFiles.filter((f) => f.status === "D")
  readonly property var buttons: pg.planning ? plan.buttons : [
    { label: pg.removed.length === 1 ? "Bring back " + D.baseName(pg.removed[0].path) : "Bring back " + pg.removed.length + " removed",
      visible: pg.removed.length > 0 && pg.scope !== "all", run: () => pg.bringBack(pg.removed) },
    { label: "Save as patches", visible: pg.scope === "compare" && pg.cmpReady && !!pg.cmpCount && pg.cmpCount.right > 0,
      run: () => pg.savePatch(pg.cmpFrom, pg.cmpTo) },
    { label: "Restore as a branch", ink: Zenon.cyan, primary: true, visible: pg.scope === "lost" && !!pg.commit,
      run: () => pg.branchHere(pg.commit) },
  ]

  // ── ONE FILE'S HISTORY ─────────────────────────────────────────────────
  // Asked for from plato or terminus (DelphiManager.history): only the
  // commits that changed it, and that file chosen in each. Relative to the
  // repository; a file outside the one open narrows nothing.
  readonly property string onlyPath: {
    const f = pg.win ? pg.win.historyFile : "", r = pg.win ? pg.win.root : "";
    return r !== "" && f.indexOf(r + "/") === 0 ? f.slice(r.length + 1) : "";
  }
  onOnlyPathChanged: {
    if (!pathField.focused && pathField.text.trim() !== pg.onlyPath) pathField.text = pg.onlyPath;
    if (pg.win && pg.win.root !== "") pg.reload();
  }
  // the file filter's text (relative to the repository; ~ or the whole path
  // will do), as what History is narrowed to — empty: every file
  function filterPath(text) {
    const t = String(text || "").trim().replace(/^~(?=\/)/, pg.win.home);
    const r = pg.win.root;
    pg.win.historyFile = t === "" ? "" : t.indexOf(r + "/") === 0 ? t : r + "/" + t.replace(/^\.?\/+/, "");
  }
  function everyFile() {
    pg.win.historyFile = "";
  }

  function takeFocus() {
    if (pg.planning) plan.takeFocus();
    else if (search.focused || pathField.focused) return;
    else if (pg.win) pg.win.focusKeys();
  }

  // ── WHICH HISTORY ──────────────────────────────────────────────────────
  // branch: every branch's commits, on the graph (as it always was)
  // incoming: what the upstream has that this branch has not pulled — others'
  //   work, by who made it; fetched first, so it is what is there now
  // all: every repository opened before, its latest commits under its name;
  //   one chosen opens there (user, 2026-10-11: history by repository, and
  //   a way to see commits from others)
  property string scope: "branch"
  property var across: []
  property bool acrossLoading: false
  property string jumpSha: ""
  property int acrossSel: -1
  function acrossStep(d) {
    const rs = pg.acrossRows;
    let i = pg.acrossSel;
    do { i += d; } while (i >= 0 && i < rs.length && rs[i].head);
    if (i >= 0 && i < rs.length) { pg.acrossSel = i; acrossList.positionViewAtIndex(i, ListView.Contain); }
  }
  function setScope(sc) {
    if (sc === pg.scope) return;
    pg.scope = sc;
    if (sc === "all") { pg.loadAcross(); return; }
    if (sc === "compare" && !pg.cmpReady) pg.compareDefaults();
    if (sc === "compare") pg.whole = true;
    if (sc === "incoming" && pg.win.branch && pg.win.branch.upstream) {
      pg.win.act("fetch", {}, { label: "Fetching what is new", network: true, refresh: false,
        then: () => { if (pg) pg.reload(); }, failed: () => { if (pg) pg.reload(); } });
      pg.commits = [];
      return;
    }
    pg.reload();
  }
  function loadAcross() {
    pg.acrossLoading = true;
    const roots = pg.win.mgr.recents.map((r) => r.root);
    pg.win.mgr.call("across", null, { roots: roots, count: 12 }, (ok, res) => {
      if (!pg) return;
      pg.acrossLoading = false;
      pg.across = ok ? res : [];
      // the first commit chosen, so the right side shows something
      if (pg.acrossSel < 0 || !pg.acrossRows[pg.acrossSel] || pg.acrossRows[pg.acrossSel].head)
        pg.acrossSel = pg.acrossRows.findIndex((r) => !r.head);
      detailWait.restart();
    });
  }
  readonly property var acrossRows: {
    const out = [];
    for (const r of pg.across) {
      out.push({ head: true, root: r.root, name: D.baseName(r.root), count: r.commits.length });
      for (const c of r.commits) out.push(Object.assign({ root: r.root }, c));
    }
    return out;
  }
  // a commit chosen there: its repository opened, its history on it
  function jumpTo(r) {
    pg.jumpSha = r.sha;
    pg.scope = "branch";
    if (r.root !== pg.win.root) pg.win.openRepo(r.root);
    else pg.reload();
  }

  // ── COMPARE (user, 2026-10-14) ─────────────────────────────────────────
  // Two refs: the commits To has that From lacks (From..To), and, chosen
  // first, the whole difference To made since they parted (From...To) —
  // files and diff as a commit's are. x swaps them.
  property string cmpFrom: ""
  property string cmpTo: ""
  property var cmpCount: null
  property bool whole: true
  readonly property bool cmpReady: pg.cmpFrom !== "" && pg.cmpTo !== "" && pg.cmpFrom !== pg.cmpTo
  // From: what this branch follows, else main or master, else another
  // branch; To: this branch
  function compareDefaults() {
    const local = pg.win.refs.local || [];
    const here = local.find((b) => b.current);
    pg.cmpTo = here ? here.name : "HEAD";
    const other = (n) => n !== pg.cmpTo && (local.some((b) => b.name === n) || (pg.win.refs.remote || []).some((b) => b.name === n));
    pg.cmpFrom = here && here.upstream ? here.upstream
      : ["main", "master", "origin/main", "origin/master"].find(other) || (local.find((b) => !b.current) || { name: "" }).name;
  }
  function swapCompare() {
    const f = pg.cmpFrom;
    pg.cmpFrom = pg.cmpTo;
    pg.cmpTo = f;
    pg.whole = true;
    pg.reload();
  }
  function askCount() {
    pg.cmpCount = null;
    if (!pg.cmpReady) return;
    const a = pg.cmpFrom, b = pg.cmpTo;
    pg.win.mgr.call("countBetween", pg.win.root, { a: a, b: b }, (ok, res) => {
      if (pg && ok && pg.cmpFrom === a && pg.cmpTo === b) pg.cmpCount = res;
    });
  }
  // a ref chosen from a menu: branches, then remote ones, then the tags
  function pickRef(item, which) {
    const refs = pg.win.refs;
    const items = [];
    const add = (list, icon, most) => {
      for (const r of (list || []).slice(0, most))
        items.push({ text: r.name, icon: icon, mark: D.ago(r.when, Date.now()),
                     run: () => { if (which === "from") pg.cmpFrom = r.name; else pg.cmpTo = r.name; pg.whole = true; pg.reload(); } });
    };
    add(refs.local, "\uE725", 12);
    if (items.length) items.push({ isSeparator: true });
    add(refs.remote, "\uF0C2", 8);
    const tags = (refs.tags || []).slice().sort((x, y) => y.when - x.when);
    if (tags.length) { items.push({ isSeparator: true }); add(tags, "\uF02B", 6); }
    const p = item.mapToItem(pg, 0, item.height + 4);
    menu.open(p.x, p.y, items);
  }

  // ── LOST (user, 2026-10-14) ────────────────────────────────────────────
  // delphi/core lost: the tips no ref reaches, each with what left it
  // ("reset: moving to HEAD~2"), drawn as one log (tips --not --all)
  property var lostNotes: ({})
  property bool lostLoading: false

  // ── SEARCH IN ──────────────────────────────────────────────────────────
  // messages (git log --grep) or the changes themselves (-S: the commits
  // that added or removed the text)
  property string searchIn: "messages"
  function toggleSearchIn() {
    pg.searchIn = pg.searchIn === "messages" ? "changes" : "messages";
    if (pg.query !== "") pg.reload();
  }

  // ── PATCHES ────────────────────────────────────────────────────────────
  // a commit (or Compare's From..To) as mailbox patch files, in a
  // directory chosen in terminus — Apply a patch (Changes) takes them back
  function savePatch(rev, upto) {
    if (!pg.win.mgr.fileManager) return;
    const root = pg.commitRoot;
    pg.win.mgr.fileManager.choose(true, pg.win.home, (paths) => {
      if (!paths || paths.length === 0) return;
      pg.win.act("formatPatch", { rev: rev, upto: upto || null, dest: paths[0] }, { repo: root, refresh: false,
        label: "Writing patches",
        then: (res) => pg.win.say(res.files.length === 1 ? "Saved " + D.baseName(res.files[0])
          : "Saved " + res.files.length + " patches in " + D.tilde(paths[0], pg.win.home)) });
    });
  }

  // ── THE LOG ────────────────────────────────────────────────────────────
  property var commits: []
  property int session: -1
  property bool ended: false
  property bool paging: false
  property string query: ""
  property int sel: 0
  // the commit the right side shows: every repository's list has its own
  // rows, each in its own repository (commitRoot) — the right side read
  // them from the open one, so it showed nothing there (user, 2026-10-11)
  readonly property var commit: pg.scope === "all"
    ? (pg.acrossRows[pg.acrossSel] && !pg.acrossRows[pg.acrossSel].head ? pg.acrossRows[pg.acrossSel] : null)
    : pg.scope === "compare" && pg.whole ? (pg.cmpReady ? pg.rangeCommit : null)
    : pg.sel >= 0 && pg.sel < pg.commits.length ? pg.commits[pg.sel] : null
  // Compare's whole difference, standing where a commit would
  readonly property var rangeCommit: ({ range: true, sha: "", parents: [], refs: [], author: "", when: 0,
    subject: "Everything " + pg.cmpTo + " changed since it parted from " + pg.cmpFrom })
  readonly property string commitRoot: pg.scope === "all" && pg.commit ? pg.commit.root : pg.win ? pg.win.root : ""
  function absOf(path) { return pg.commitRoot + "/" + path; }
  onAcrossSelChanged: if (pg.scope === "all") detailWait.restart()
  onScopeChanged: { pg.area = "commits"; detailWait.restart(); }
  onWholeChanged: detailWait.restart()
  property string wantSha: ""
  readonly property string headSha: pg.win && pg.win.branch ? pg.win.branch.oid || "" : ""

  function reload() {
    if (!pg.win || pg.win.root === "") return;
    if (pg.commit && pg.scope !== "all") pg.wantSha = pg.commit.sha;
    if (pg.session >= 0) pg.win.mgr.call("logClose", pg.win.root, { session: pg.session });
    pg.session = -1;
    pg.ended = false;
    if (pg.scope === "all") return;
    const args = pg.query === "" ? {} : pg.searchIn === "changes" ? { pickaxe: pg.query } : { grep: pg.query };
    if (pg.onlyPath !== "") args.path = pg.onlyPath;
    if (pg.scope === "incoming") {
      if (!pg.win.branch || !pg.win.branch.upstream) { pg.commits = []; pg.ended = true; return; }
      args.revs = ["HEAD..@{upstream}"];
    }
    if (pg.scope === "compare") {
      pg.askCount();
      if (!pg.cmpReady) { pg.commits = []; pg.ended = true; return; }
      args.revs = [pg.cmpFrom + ".." + pg.cmpTo];
      detailWait.restart();
    }
    const root = pg.win.root;
    if (pg.scope === "lost") {
      pg.lostLoading = true;
      pg.commits = [];
      pg.win.mgr.call("lost", root, {}, (ok, res) => { if (!pg) return;
        pg.lostLoading = false;
        if (!ok || root !== pg.win.root || pg.scope !== "lost") { pg.ended = true; return; }
        pg.lostNotes = res.notes;
        if (res.tips.length === 0) { pg.commits = []; pg.ended = true; return; }
        args.revs = res.tips.concat(["--not", "--all"]);
        pg.openLog(root, args);
      });
      return;
    }
    pg.openLog(root, args);
  }
  function openLog(root, args) {
    pg.win.mgr.call("logOpen", root, args, (ok, res) => { if (!pg) return;
      if (!ok || root !== pg.win.root) return;
      pg.session = res.session;
      pg.commits = [];
      // a page still out belongs to the session just closed (its answer is
      // dropped by its sid): it must not hold this one's first page back —
      // two reloads close together left History empty (2026-10-11)
      pg.paging = false;
      pg.more(true);
    });
  }
  function more(first) {
    if (pg.session < 0 || pg.ended || pg.paging) return;
    pg.paging = true;
    const sid = pg.session;
    pg.win.mgr.call("logPage", pg.win.root, { session: sid, count: first ? 400 : 600 }, (ok, res) => { if (!pg) return;
      pg.paging = false;
      if (!ok || sid !== pg.session) return;
      pg.commits = pg.commits.concat(res.commits);
      pg.ended = res.end;
      if (first) {
        const want = pg.jumpSha !== "" ? pg.jumpSha : pg.wantSha;
        pg.jumpSha = "";
        const i = want !== "" ? pg.commits.findIndex((c) => c.sha === want) : -1;
        pg.sel = Math.max(0, i);
        pg.wantSha = "";
        pg.ciAsk(pg.commits.slice(0, 40).map((c) => c.sha));
        list.positionViewAtIndex(pg.sel, ListView.Contain);
        pg.loadCommit();
      }
    });
  }
  Component.onCompleted: { Qt.callLater(pg.reload); Qt.callLater(pg.takeBlame); }
  Component.onDestruction: if (pg.session >= 0 && pg.win) pg.win.mgr.call("logClose", pg.win.root, { session: pg.session })
  Connections {
    target: pg.win
    function onRefsEpochChanged() { if (!pg.planning) pg.reload(); }
    function onRepoEpochChanged() { pg.commits = []; pg.reload(); }
  }

  function moveTo(i) {
    if (pg.commits.length === 0) return;
    // Compare: above the first commit is the whole difference
    if (pg.scope === "compare" && i < 0) { pg.whole = true; return; }
    if (pg.scope === "compare") pg.whole = false;
    pg.sel = Math.max(0, Math.min(pg.commits.length - 1, i));
    list.positionViewAtIndex(pg.sel, ListView.Contain);
    if (pg.sel > pg.commits.length - 80) pg.more(false);
    detailWait.restart();
  }

  // ── CI ────────────────────────────────────────────────────────────────
  // The forge's checks for this repository's commits (DelphiManager.ci):
  // asked for the newest forty when the history loads, and for a commit
  // when it is chosen; in the open repository only (the hub).
  readonly property var hub: pg.win ? pg.win.hub : null
  function ciOf(sha) {
    if (!pg.hub || !pg.win) return null;
    pg.win.mgr.ci;
    return pg.win.mgr.ciOf(pg.hub.forge, pg.hub.full, sha);
  }
  function ciAsk(shas) { if (pg.hub && pg.scope !== "all") pg.win.mgr.ciAsk(pg.hub.forge, pg.hub.full, shas); }

  // ── WHO WROTE THIS (BlameView, in place of the diff) ──────────────────
  // A file's lines with the commit that last changed each: from a commit's
  // files (w) as of that commit, following the commits as you move; from
  // plato or terminus (DelphiManager.blame) as the file is now.
  property string blamePath: ""
  property string blameAt: "commit"   // commit | head
  property int blameLine: 0
  // one asked for from plato or terminus, taken up when its repository is
  readonly property var blameWanted: pg.win ? pg.win.blameWanted : null
  onBlameWantedChanged: Qt.callLater(pg.takeBlame)
  function takeBlame() {
    const b = pg.win ? pg.win.blameWanted : null;
    if (!b || pg.win.root === "" || b.file.indexOf(pg.win.root + "/") !== 0) return;
    pg.win.blameWanted = null;
    pg.blameFile(b.file.slice(pg.win.root.length + 1), "head", b.line);
  }
  Connections { target: pg.win; function onRootChanged() { Qt.callLater(pg.takeBlame); } }
  function blameFile(path, at, line) {
    pg.blameAt = at || "commit";
    pg.blameLine = line || 0;
    pg.blamePath = path;
  }

  // ── A PEEK AT A COMMIT ─────────────────────────────────────────────────
  // The pointer resting on a commit that is not the chosen one: its whole
  // message, who and when, and how many files it touched, in terminus'
  // Bubble hanging from the row — without moving the selection (as the
  // pull requests peek, 2026-10-11).
  property Item peekRow: null
  property var peekC: null
  property var peekMsg: null
  property int peekFiles: -1
  Timer { id: peekWait; interval: Zenon.hoverWait; onTriggered: pg.loadPeek() }
  function peekAt(row, c) {
    pg.peekRow = row;
    pg.peekC = c;
    pg.peekMsg = null;
    pg.peekFiles = -1;
    if (c) peekWait.restart(); else peekWait.stop();
  }
  function loadPeek() {
    const c = pg.peekC;
    if (!c || !pg.win) return;
    const sha = c.sha, root = pg.win.root;
    pg.win.mgr.call("message", root, { sha: sha }, (ok, m) => { if (pg && ok && pg.peekC && pg.peekC.sha === sha) pg.peekMsg = m; });
    pg.win.mgr.call("files", root, { sha: sha }, (ok, fs) => { if (pg && ok && pg.peekC && pg.peekC.sha === sha) pg.peekFiles = fs.length; });
  }
  onSelChanged: pg.peekMsg = null
  Bubble {
    id: peekBubble
    window: pg.win
    target: pg.peekRow
    shown: !!pg.peekMsg && !!pg.peekC && !(pg.commit && pg.commit.sha === pg.peekC.sha) && !pg.win.carding
    cardWidth: 480
    readonly property string body: pg.peekMsg ? String(pg.peekMsg.body || "") : ""
    readonly property string rest: peekBubble.body.indexOf("\n") >= 0 ? peekBubble.body.slice(peekBubble.body.indexOf("\n") + 1).trim() : ""
    Text {
      width: 452
      wrapMode: Text.Wrap
      maximumLineCount: 3
      elide: Text.ElideRight
      text: pg.peekC ? pg.peekC.subject : ""
      color: Zenon.ink
      font.family: Zenon.face
      font.weight: Font.Bold
      font.pixelSize: Zenon.px(15)
    }
    Text {
      width: 452
      visible: peekBubble.rest !== ""
      wrapMode: Text.Wrap
      maximumLineCount: 10
      elide: Text.ElideRight
      text: peekBubble.rest
      color: Zenon.accentSoft
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(14)
    }
    Text {
      width: 452
      elide: Text.ElideRight
      text: !pg.peekC ? "" : pg.peekC.author + "  ·  " + D.stamp(pg.peekC.when) + "  ·  " + D.short(pg.peekC.sha)
        + (pg.peekFiles >= 0 ? "  ·  " + pg.peekFiles + (pg.peekFiles === 1 ? " file" : " files") : "")
      color: Zenon.accentMuted
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.features: { "tnum": 1 }
      font.pixelSize: Zenon.px(13)
    }
  }

  // ── THE COMMIT ─────────────────────────────────────────────────────────
  property var message: null
  property var files: []
  // the files as filtered (the field above them; / in the files): every
  // key, the selection and Bring back act on these
  property string fileQuery: ""
  readonly property var shownFiles: pg.fileQuery === "" ? pg.files
    : pg.files.filter((f) => (f.path + " " + (f.from || "")).toLowerCase().indexOf(pg.fileQuery.toLowerCase()) >= 0)
  onFileQueryChanged: { pg.fileSel = 0; pg.loadFileDiff(); }
  property int fileSel: 0
  property var diffFiles: []
  property string area: "commits"
  Timer { id: detailWait; interval: 60; onTriggered: pg.loadCommit() }
  function loadCommit() {
    const c = pg.commit;
    if (c && !c.range) pg.ciAsk([c.sha]);
    if (!c) { pg.message = null; pg.files = []; pg.diffFiles = []; return; }
    if (c.range) {
      const a = pg.cmpFrom, b = pg.cmpTo;
      pg.message = null;
      pg.win.mgr.call("filesBetween", pg.win.root, { a: a, b: b }, (ok, fs) => { if (!pg) return;
        if (!ok || !pg.commit || !pg.commit.range || pg.cmpFrom !== a || pg.cmpTo !== b) return;
        pg.files = fs;
        pg.fileSel = 0;
        pg.loadFileDiff();
      });
      return;
    }
    const sha = c.sha, root = pg.commitRoot;
    pg.win.mgr.call("message", root, { sha: sha }, (ok, m) => { if (!pg) return; if (ok && pg.commit && pg.commit.sha === sha) pg.message = m; });
    pg.win.mgr.call("files", root, { sha: sha }, (ok, fs) => { if (!pg) return;
      if (!ok || !pg.commit || pg.commit.sha !== sha) return;
      pg.files = fs;
      pg.fileSel = pg.onlyPath !== "" ? Math.max(0, pg.shownFiles.findIndex((f) => f.path === pg.onlyPath)) : 0;
      pg.loadFileDiff();
    });
  }
  function loadFileDiff() {
    const c = pg.commit, f = pg.shownFiles[pg.fileSel];
    if (!c || !f) { pg.diffFiles = []; return; }
    const sha = c.sha, path = f.path;
    const ask = c.range ? ["compare", { a: pg.cmpFrom, b: pg.cmpTo, path: path, budget: 6000 }]
                        : ["show", { rev: sha, path: path, budget: 6000 }];
    pg.win.mgr.call(ask[0], pg.commitRoot, ask[1], (ok, res) => { if (!pg) return;
      if (ok && pg.commit && pg.commit.sha === sha && pg.shownFiles[pg.fileSel] && pg.shownFiles[pg.fileSel].path === path) {
        pg.diffFiles = res.files;
        diff.toFirst();
      }
    });
  }
  function moveFile(d) {
    if (pg.shownFiles.length === 0) return;
    pg.fileSel = Math.max(0, Math.min(pg.shownFiles.length - 1, pg.fileSel + d));
    fileList.positionViewAtIndex(pg.fileSel, ListView.Contain);
    // blaming: the next file's, at the same commit
    if (pg.blamePath !== "" && pg.shownFiles[pg.fileSel]) pg.blameFile(pg.shownFiles[pg.fileSel].path, pg.blameAt, 0);
    pg.loadFileDiff();
  }

  // ── WHAT CAN BE DONE FROM A COMMIT ─────────────────────────────────────
  // BRING BACK what it removed: as each was just before it, on disk and
  // staged — to commit and push, and it is back (user, 2026-10-11: LICENSE
  // and README.md went with a "Stage all" of a folder that lacked them).
  function bringBack(fs) {
    const c = pg.commit;
    if (!c || !fs || fs.length === 0) return;
    const names = fs.map((f) => D.baseName(f.path));
    pg.win.confirm({ question: "Bring back " + (fs.length === 1 ? names[0] : fs.length + " files") + "?", glyph: "", ink: Zenon.cyan,
      detail: "As " + (fs.length === 1 ? "it was" : "they were") + " just before " + D.short(c.sha) + " “" + D.subjectOf(c.subject) + "”. "
        + (fs.length === 1 ? "It is" : "They are") + " put back and staged: commit and push to have " + (fs.length === 1 ? "it" : "them") + " on the remote again.",
      items: fs.slice(0, 8).map((f) => f.path).concat(fs.length > 8 ? ["… and " + (fs.length - 8) + " more"] : []),
      verb: "Bring back",
      then: () => pg.win.act("bringBack", { sha: c.sha, paths: fs.map((f) => f.path) }, {
        said: "Brought back " + (fs.length === 1 ? names[0] : fs.length + " files") + " — staged, ready to commit",
        then: () => pg.win.setPage("changes") }) });
  }

  function branchHere(c) {
    pg.win.ask({ title: "A branch at " + D.short(c.sha), glyph: "",
      detail: c.subject, fields: [{ key: "name", label: "Name", hint: "feature/what-it-is" }],
      toggles: [{ key: "switch", label: "Switch to it", value: true }], verb: "Create",
      then: (v) => pg.win.act("branchCreate", { name: v.name.trim(), start: c.sha, switch: v["switch"] },
                              { said: "Branch " + v.name.trim() + " created" }) });
  }
  function checkout(c) {
    pg.win.confirm({ question: "Check out " + D.short(c.sha) + "?", glyph: "",
      detail: "Detached: you are on the commit, not on a branch. Make a branch there before committing, or the commits are easy to lose.",
      verb: "Check out", then: () => pg.win.act("switch", { name: c.sha, detach: true }, { said: "On " + D.short(c.sha) }) });
  }
  function cherryPick(c) {
    pg.win.act("cherryPick", { shas: [c.sha] }, { label: "Cherry-picking",
      then: (r) => pg.win.say(r && r.conflicts ? "Stopped on conflicts — resolve them in Changes" : "Picked " + D.short(c.sha) + " onto " + pg.win.branchName, r && r.conflicts) });
  }
  function revert(c) {
    pg.win.confirm({ question: "Revert " + D.short(c.sha) + "?", glyph: "",
      detail: "A new commit that undoes it: “" + c.subject + "”", verb: "Revert",
      then: () => pg.win.act("revert", { sha: c.sha }, { then: (r) => pg.win.say(r && r.conflicts ? "Stopped on conflicts — resolve them in Changes" : "Reverted", r && r.conflicts) }) });
  }
  function resetTo(c) {
    pg.win.ask({ title: "Move " + pg.win.branchName + " to " + D.short(c.sha) + "?", glyph: "", ink: Zenon.red,
      detail: "The commits after it leave the branch. Soft keeps their changes staged, mixed keeps them unstaged; hard throws them away, and your uncommitted work with them.",
      toggles: [{ key: "hard", label: "Hard — discard the changes too", value: false },
                { key: "soft", label: "Soft — keep them staged", value: false }],
      verb: "Move", verbInk: Zenon.red,
      then: (v) => pg.win.act("reset", { rev: c.sha, mode: v.hard ? "hard" : v.soft ? "soft" : "mixed" }, { said: "Moved to " + D.short(c.sha) }) });
  }
  function rework(c) {
    if (pg.win.st && (pg.win.st.staged.length + pg.win.st.unstaged.length) > 0) {
      pg.win.say("Commit or stash your changes first", true);
      return;
    }
    pg.win.mgr.call("rebasePlan", pg.win.root, { base: c.sha }, (ok, steps) => { if (!pg) return;
      if (!ok || steps.length === 0) { pg.win.say("Nothing after " + D.short(c.sha) + " to rework", true); return; }
      plan.begin(c.sha, steps);
    });
  }
  readonly property bool planning: plan.active

  function menuFor(c) {
    const here = c.sha === pg.headSha;
    return [
      { text: "Copy id", icon: "", mark: "c", run: () => pg.win.copy(c.sha, D.short(c.sha)) },
      { text: "Copy message", icon: "", run: () => pg.win.copy(c.subject, "the message") },
      { isSeparator: true },
      { text: "Branch here", icon: "", mark: "b", run: () => pg.branchHere(c) },
      { text: "Check out", icon: "", enabled: !here, run: () => pg.checkout(c) },
      { text: "Cherry-pick onto " + pg.win.branchName, icon: "", mark: "p", enabled: !here, run: () => pg.cherryPick(c) },
      { text: "Revert", icon: "", run: () => pg.revert(c) },
      { isSeparator: true },
      { text: "Rework the commits after it", icon: "", mark: "i", enabled: !here, run: () => pg.rework(c) },
      { text: "Move " + pg.win.branchName + " here", icon: "", enabled: !here, danger: true, run: () => pg.resetTo(c) },
      { isSeparator: true },
      { text: "Save as a patch…", icon: "\uF0C7", run: () => pg.savePatch(c.sha) },
    ];
  }

  // ── KEYS ───────────────────────────────────────────────────────────────
  function key(e) {
    if (pg.planning) return plan.key(e);
    const k = e.key, ctrl = e.modifiers & Qt.ControlModifier, shift = e.modifiers & Qt.ShiftModifier;
    if (ctrl) return false;
    // which history: this branch → incoming → every repository → …
    if (k === Qt.Key_V) {
      const order = ["branch", "incoming", "compare", "lost", "all"];
      pg.setScope(order[(order.indexOf(pg.scope) + 1) % order.length]);
      return true;
    }
    if (k === Qt.Key_Tab || k === Qt.Key_Backtab) { pg.area = pg.area === "files" ? "commits" : "files"; return true; }
    if (pg.scope === "all" && pg.area !== "files") {
      if (k === Qt.Key_Up || k === Qt.Key_K) { pg.acrossStep(-1); return true; }
      if (k === Qt.Key_Down || k === Qt.Key_J) { pg.acrossStep(1); return true; }
      if ((k === Qt.Key_Return || k === Qt.Key_Enter) && pg.acrossRows[pg.acrossSel]) { pg.jumpTo(pg.acrossRows[pg.acrossSel]); return true; }
      return false;
    }
    if (k === Qt.Key_S && pg.area !== "files" && pg.scope !== "compare") { pg.toggleSearchIn(); return true; }
    if (pg.scope === "compare" && pg.area !== "files") {
      if (k === Qt.Key_X) { pg.swapCompare(); return true; }
      if (k === Qt.Key_A) { pg.whole = true; return true; }
      if (pg.whole && (k === Qt.Key_Down || k === Qt.Key_J)) { pg.moveTo(0); return true; }
      if (pg.whole && pg.commit) return false;
    }
    if (k === Qt.Key_F && pg.area !== "files" && pg.scope !== "compare") { pathField.claim(); return true; }
    if (k === Qt.Key_Slash) { if (pg.area === "files") fileFilter.claim(); else search.claim(); return true; }
    if (pg.area === "files") {
      if (shift && (k === Qt.Key_Up || k === Qt.Key_Down)) { diff.move(k === Qt.Key_Up ? -1 : 1, false); return true; }
      if (k === Qt.Key_Up || k === Qt.Key_K) { pg.moveFile(-1); return true; }
      if (k === Qt.Key_Down || k === Qt.Key_J) { pg.moveFile(1); return true; }
      if (k === Qt.Key_PageUp) { diff.page(-1); return true; }
      if (k === Qt.Key_PageDown) { diff.page(1); return true; }
      if (k === Qt.Key_W && pg.shownFiles[pg.fileSel] && !(pg.commit && pg.commit.range)) {
        if (pg.blamePath !== "") pg.blamePath = ""; else pg.blameFile(pg.shownFiles[pg.fileSel].path, "commit", 0);
        return true;
      }
      if (k === Qt.Key_Escape && pg.blamePath !== "") { pg.blamePath = ""; return true; }
      if (k === Qt.Key_E && pg.shownFiles[pg.fileSel]) { pg.win.edit(pg.absOf(pg.shownFiles[pg.fileSel].path)); return true; }
      if (k === Qt.Key_R && pg.shownFiles[pg.fileSel] && pg.shownFiles[pg.fileSel].status === "D" && pg.scope !== "all") { pg.bringBack([pg.shownFiles[pg.fileSel]]); return true; }
      if (k === Qt.Key_Escape) { pg.area = "commits"; return true; }
      return false;
    }
    if (k === Qt.Key_Up || k === Qt.Key_K) { pg.moveTo(pg.sel - 1); return true; }
    if (k === Qt.Key_Down || k === Qt.Key_J) { pg.moveTo(pg.sel + 1); return true; }
    if (k === Qt.Key_PageUp) { pg.moveTo(pg.sel - 15); return true; }
    if (k === Qt.Key_PageDown) { pg.moveTo(pg.sel + 15); return true; }
    if (k === Qt.Key_Home) { pg.moveTo(0); return true; }
    if (k === Qt.Key_End) { pg.moveTo(pg.commits.length - 1); return true; }
    if (!pg.commit || pg.commit.range) return false;
    if (k === Qt.Key_C) { pg.win.copy(pg.commit.sha, D.short(pg.commit.sha)); return true; }
    if (k === Qt.Key_B) { pg.branchHere(pg.commit); return true; }
    if (k === Qt.Key_P) { pg.cherryPick(pg.commit); return true; }
    if (k === Qt.Key_I) { pg.rework(pg.commit); return true; }
    if (k === Qt.Key_Menu || (shift && k === Qt.Key_F10)) {
      const it = list.itemAtIndex(pg.sel);
      const p = it ? it.mapToItem(pg, 60, it.height) : Qt.point(60, 60);
      menu.open(p.x, p.y, pg.menuFor(pg.commit), pg.sel);
      return true;
    }
    if (k === Qt.Key_Escape && pg.query !== "") { search.text = ""; pg.query = ""; pg.reload(); return true; }
    if (k === Qt.Key_Escape && pg.onlyPath !== "") { pg.everyFile(); return true; }
    return false;
  }

  // ── the commits ────────────────────────────────────────────────────────
  Item {
    id: left
    visible: !pg.planning
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: pg.win && pg.win.splits.history ? pg.win.splits.history : Math.round(pg.width * 0.56)

    Segments {
      id: scopes
      // centered in the column, the search under it (user, 2026-10-11)
      x: Math.round((parent.width - width) / 2)
      y: 12
      textSize: Zenon.px(14)
      options: [["branch", "This branch"],
                ["incoming", "Incoming" + (pg.win && pg.win.branch && pg.win.branch.behind > 0 ? "  " + pg.win.branch.behind : "")],
                ["compare", "Compare"], ["lost", "Lost"],
                ["all", "Everywhere"]]
      current: pg.scope
      onChose: (v) => pg.setScope(v)
    }
    BulkField {
      id: search
      visible: pg.scope !== "all" && pg.scope !== "compare"
      readonly property bool under: true
      x: 12
      y: scopes.y + scopes.height + 8
      width: Math.round((parent.width - 32) * 0.42)
      height: scopes.height
      textSize: Zenon.px(14)
      ghost: pg.searchIn === "changes" ? "  Search the changes  ( / )" : "  Search messages  ( / )"
      clearable: true
      // narrows as it is typed (user, 2026-10-12), a beat after the last key
      function apply() {
        typing.stop();
        const q = search.text.trim();
        if (q !== pg.query) { pg.query = q; pg.reload(); }
      }
      onTextChanged: if (search.focused) typing.restart()
      onAccepted: { search.apply(); pg.win.focusKeys(); }
      Keys.onEscapePressed: { search.text = ""; search.apply(); pg.win.focusKeys(); }
      onTabbed: pathField.claim()
      onCleared: search.apply()
      Timer { id: typing; interval: 220; onTriggered: search.apply() }
    }
    // ONE FILE'S HISTORY, AS A FILTER (user, 2026-10-11: from plato it
    // narrowed History with no way back but leaving the page): the file it
    // is narrowed to, there to edit or clear — and a path typed here
    // narrows it the same way
    // what the search looks in: messages, or the changes themselves (s)
    Segments {
      id: searchIn
      visible: search.visible
      anchors.left: search.right
      anchors.leftMargin: 8
      y: search.y
      textSize: Zenon.px(13)
      options: [["messages", "Messages"], ["changes", "Changes"]]
      current: pg.searchIn
      onChose: (v) => { if (v !== pg.searchIn) pg.toggleSearchIn(); }
    }
    // COMPARE's two refs, in place of the search: From → To, and a swap
    Row {
      id: cmpRow
      visible: pg.scope === "compare"
      x: 12
      y: scopes.y + scopes.height + 8
      height: scopes.height
      spacing: 8
      DialogButton {
        id: fromBtn
        anchors.verticalCenter: parent.verticalCenter
        label: (pg.cmpFrom || "Choose") + "  ▾"
        onClicked: pg.pickRef(fromBtn, "from")
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "→"
        color: Zenon.accentMuted
        font.family: Zenon.face
        font.pixelSize: Zenon.px(16)
      }
      DialogButton {
        id: toBtn
        anchors.verticalCenter: parent.verticalCenter
        label: (pg.cmpTo || "Choose") + "  ▾"
        ink: Zenon.cyan
        onClicked: pg.pickRef(toBtn, "to")
      }
      DialogButton {
        anchors.verticalCenter: parent.verticalCenter
        label: "⇄  Swap"
        ready: pg.cmpReady
        onClicked: pg.swapCompare()
      }
    }
    BulkField {
      id: pathField
      visible: pg.scope !== "all" && pg.scope !== "compare"
      anchors.left: searchIn.right
      anchors.leftMargin: 8
      anchors.right: parent.right
      anchors.rightMargin: 12
      y: search.y
      height: search.height
      textSize: Zenon.px(14)
      ghost: "  Only a file or directory  ( f )"
      clearable: true
      Component.onCompleted: pathField.text = pg.onlyPath
      // as typed too, a little later than the search (a half-typed path
      // narrows to nothing)
      onTextChanged: if (pathField.focused) pathTyping.restart()
      onAccepted: { pathTyping.stop(); pg.filterPath(pathField.text); pg.win.focusKeys(); }
      Keys.onEscapePressed: { pathTyping.stop(); pathField.text = ""; if (pg.onlyPath !== "") pg.filterPath(""); pg.win.focusKeys(); }
      onBackTabbed: search.claim()
      onCleared: { pathTyping.stop(); if (pg.onlyPath !== "") pg.filterPath(""); }
      Timer { id: pathTyping; interval: 400; onTriggered: pg.filterPath(pathField.text) }
    }

    ListView {
      id: list
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: cmpRow.visible ? cmpRow.bottom : search.visible && search.under ? search.bottom : scopes.bottom
      anchors.topMargin: 8
      anchors.bottom: parent.bottom
      visible: pg.scope !== "all"
      clip: true
      bottomMargin: 6
      boundsBehavior: Flickable.StopAtBounds
      model: pg.commits
      cacheBuffer: 800
      reuseItems: true
      readonly property int rowH: Math.round(Zenon.px(15) * 2.2)
      onContentYChanged: if (contentY + height > contentHeight - 600) pg.more(false)
      SelectBar { view: list; host: pg.win; index: pg.sel; on: !(pg.scope === "compare" && pg.whole); rowH: list.rowH; color: pg.area === "commits" ? pg.win.hiFill : Zenon.wash(0.05) }
      // Compare: the whole difference, a row above the commits
      header: Item {
        width: list.width
        height: pg.scope === "compare" && pg.cmpReady ? list.rowH + 6 : 0
        visible: height > 0
        Rectangle {
          anchors.fill: parent
          anchors.leftMargin: 8
          anchors.rightMargin: 8
          anchors.bottomMargin: 6
          radius: Zenon.windowRadius
          color: pg.whole ? (pg.area === "commits" ? pg.win.hiFill : Zenon.wash(0.05)) : wholePress.pressed ? Zenon.wash(0.04) : "transparent"
          border.width: 1
          border.color: Zenon.border
          Text {
            x: 14
            width: parent.width - 28
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: "⇄   The whole difference" + (pg.whole && pg.files.length > 0 ? "  ·  " + pg.files.length + (pg.files.length === 1 ? " file" : " files") : "")
            color: pg.whole ? Zenon.ink : Zenon.accentSoft
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(15)
          }
          HoverHandler { id: wholeHover }
          MouseArea { id: wholePress; anchors.fill: parent; onClicked: { pg.area = "commits"; pg.whole = true; pg.win.focusKeys(); } }
        }
      }
      delegate: Item {
        id: crow
        required property var modelData
        required property int index
        readonly property var c: crow.modelData
        width: list.width
        height: list.rowH
        GraphCell {
          id: gcell
          x: 8
          height: parent.height
          g: crow.c.graph
          merge: crow.c.parents.length > 1
          head: crow.c.sha === pg.headSha
        }
        Row {
          id: chipRow
          anchors.left: gcell.right
          anchors.leftMargin: 6
          anchors.verticalCenter: parent.verticalCenter
          spacing: 5
          Repeater {
            model: D.chips(crow.c.refs).slice(0, 3)
            delegate: Rectangle {
              required property var modelData
              height: Zenon.px(19)
              width: chipText.implicitWidth + 14
              radius: Zenon.radiusControl
              color: Zenon.alpha(Zenon[modelData.ink], modelData.here ? 0.22 : 0.12)
              border.width: modelData.here ? 1 : 0
              border.color: Zenon[modelData.ink]
              Text {
                id: chipText
                anchors.centerIn: parent
                text: modelData.glyph + " " + modelData.label
                color: Zenon[modelData.ink]
                font.family: Zenon.face
                font.weight: Font.Bold
                font.pixelSize: Zenon.px(12)
              }
            }
          }
        }
        Text {
          anchors.left: chipRow.right
          anchors.leftMargin: chipRow.width > 0 ? 8 : 0
          anchors.right: who.left
          anchors.rightMargin: 12
          anchors.verticalCenter: parent.verticalCenter
          elide: Text.ElideRight
          text: crow.c.subject
          color: crow.index === pg.sel ? Zenon.ink : Zenon.accentSoft
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(15)
        }
        Text {
          id: who
          anchors.right: ciCell.left
          anchors.rightMargin: 12
          anchors.verticalCenter: parent.verticalCenter
          readonly property var note: pg.scope === "lost" ? pg.lostNotes[crow.c.sha] : null
          width: Math.min(implicitWidth, note ? 240 : 130)
          elide: Text.ElideRight
          text: note ? note.what : crow.c.author
          color: Zenon.accentMuted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(13)
        }
        // what the forge's checks said of it (CiDot), in a column of its
        // own so the dates stay aligned; none where nothing was asked
        Item {
          id: ciCell
          anchors.right: when.left
          anchors.rightMargin: pg.hub ? 10 : 0
          anchors.verticalCenter: parent.verticalCenter
          width: pg.hub ? Zenon.px(9) : 0
          height: Zenon.px(9)
          CiDot { anchors.centerIn: parent; c: pg.ciOf(crow.c.sha) }
        }
        Text {
          id: when
          anchors.right: parent.right
          anchors.rightMargin: 16
          anchors.verticalCenter: parent.verticalCenter
          width: Zenon.px(64)
          horizontalAlignment: Text.AlignRight
          text: D.ago(crow.c.when, Date.now())
          color: Zenon.accentMuted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.features: { "tnum": 1 }
          font.pixelSize: Zenon.px(13)
        }
        HeldRing { anchors.fill: parent; anchors.margins: 2; on: menu.isOpen && menu.held === crow.index }
        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          onClicked: (m) => {
            if (m.button === Qt.RightButton) {
              const p = mapToItem(pg, m.x, m.y);
              menu.open(p.x, p.y, pg.menuFor(crow.c), crow.index);
              return;
            }
            pg.area = "commits";
            pg.moveTo(crow.index);
            pg.win.focusKeys();
          }
        }
        // resting on a commit not chosen: a peek at it (peekBubble)
        HoverHandler {
          onHoveredChanged: hovered ? pg.peekAt(crow, crow.c)
            : pg.peekRow === crow ? pg.peekAt(null, null) : undefined
        }
      }
      footer: Item {
        width: list.width
        height: pg.ended && !pg.lostLoading ? 0 : 40
        Working { anchors.centerIn: parent; running: pg.paging || pg.lostLoading }
      }
      EmptyState {
        anchors.centerIn: parent
        visible: pg.commits.length === 0 && pg.ended && !pg.lostLoading
        filtered: pg.query !== ""
        text: pg.query !== "" ? "No matches"
          : pg.scope === "lost" ? "Nothing lost — every commit is on a branch"
          : pg.scope === "compare" ? (pg.cmpReady ? pg.cmpTo + " has nothing " + pg.cmpFrom + " lacks" : "Choose two branches or tags")
          : pg.scope === "incoming" ? "Nothing incoming"
          : "No commits yet"
      }
    }
    ElasticScroll { anchors.fill: list; view: list }

    // ── every repository, its latest commits under its name ──────────────
    ListView {
      id: acrossList
      visible: pg.scope === "all"
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: scopes.bottom
      anchors.topMargin: 8
      anchors.bottom: parent.bottom
      clip: true
      bottomMargin: 6
      boundsBehavior: Flickable.StopAtBounds
      model: pg.acrossRows
      readonly property int rowH: Math.round(Zenon.px(15) * 2.2)
      SelectBar { view: acrossList; host: pg.win; index: pg.acrossSel; on: pg.acrossSel >= 0; rowH: acrossList.rowH; color: pg.win.hiFill; radius: Zenon.windowRadius; inset: 8 }
      delegate: Item {
        id: arow
        required property var modelData
        required property int index
        readonly property var r: arow.modelData
        width: acrossList.width
        height: acrossList.rowH
        GroupHead {
          visible: !!arow.r.head
          inset: 18
          title: arow.r.head ? arow.r.name : ""
          count: arow.r.head ? arow.r.count : -1
          note: arow.r.head ? D.tilde(arow.r.root, pg.win.home) : ""
        }
        Text {
          visible: !arow.r.head
          x: 30
          width: parent.width - 30 - whoText.width - 34
          anchors.verticalCenter: parent.verticalCenter
          elide: Text.ElideRight
          text: arow.r.subject || ""
          color: arow.r.root === pg.win.root ? Zenon.ink : Zenon.accentSoft
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(15)
        }
        Text {
          id: whoText
          visible: !arow.r.head
          anchors.right: parent.right
          anchors.rightMargin: 18
          anchors.verticalCenter: parent.verticalCenter
          text: arow.r.head ? "" : arow.r.author + "   " + D.ago(arow.r.when, Date.now())
          color: Zenon.accentMuted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(13)
        }
        MouseArea {
          anchors.fill: parent
          enabled: !arow.r.head
          onClicked: { pg.acrossSel = arow.index; pg.win.focusKeys(); }
          onDoubleClicked: pg.jumpTo(arow.r)
        }
      }
      Working { anchors.centerIn: parent; running: pg.acrossLoading; visible: pg.acrossLoading }
      EmptyState { anchors.centerIn: parent; visible: !pg.acrossLoading && pg.acrossRows.length === 0; text: "No repositories opened yet" }
    }
    ElasticScroll { anchors.fill: acrossList; view: acrossList; visible: pg.scope === "all" }
    Scrollbar { flick: acrossList; visible: pg.scope === "all"; anchors.right: acrossList.right; anchors.top: acrossList.top; anchors.bottom: acrossList.bottom }
    Scrollbar { flick: list; anchors.right: list.right; anchors.top: list.top; anchors.bottom: list.bottom }
  }

  // ── the commit ─────────────────────────────────────────────────────────
  Item {
    id: right
    visible: !pg.planning
    anchors.left: left.right
    anchors.leftMargin: 1
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom

    Column {
      id: headCol
      x: 18
      y: 14
      width: parent.width - 36
      spacing: 6
      visible: !!pg.commit
      Text {
        width: parent.width
        wrapMode: Text.Wrap
        maximumLineCount: 3
        elide: Text.ElideRight
        text: pg.commit ? pg.commit.subject : ""
        color: Zenon.ink
        font.family: Zenon.face
        font.weight: Font.Bold
        font.pixelSize: Zenon.px(17)
      }
      Text {
        width: parent.width
        elide: Text.ElideRight
        text: !pg.commit ? "" : pg.commit.range ? pg.cmpFrom + "..." + pg.cmpTo + "  ·  " + pg.files.length + (pg.files.length === 1 ? " file" : " files")
            + (pg.cmpCount ? "  ·  " + pg.cmpCount.right + (pg.cmpCount.right === 1 ? " commit" : " commits") : "")
          : pg.commit.author + "  ·  " + D.stamp(pg.commit.when) + "  ·  " + D.short(pg.commit.sha)
          + (pg.scope === "lost" && pg.lostNotes[pg.commit.sha] ? "  ·  left by “" + pg.lostNotes[pg.commit.sha].what + "”"
             + (pg.lostNotes[pg.commit.sha].when ? " " + D.ago(pg.lostNotes[pg.commit.sha].when, Date.now()) : "") : "")
          + ((pg.commit.parents || []).length > 1 ? "  ·  merge of " + pg.commit.parents.length : "")
          + (pg.scope === "all" ? "  ·  " + D.baseName(pg.commitRoot) : "")
          + (pg.message && pg.message.signature === "G" ? "  ·   signed" : "")
        color: Zenon.accentMuted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(13)
        MouseArea { anchors.fill: parent; onClicked: if (pg.commit && !pg.commit.range) pg.win.copy(pg.commit.sha, D.short(pg.commit.sha)) }
      }
      // the body, when there is more than the subject; in a room of its own
      // so the wheel and the bar can lie over it
      Item {
      width: parent.width
      height: bodyFlick.height
      visible: bodyText.text !== ""
      Flickable {
        id: bodyFlick
        width: parent.width
        height: Math.min(bodyText.implicitHeight, 120)
        clip: true
        contentHeight: bodyText.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        Text {
          id: bodyText
          width: bodyFlick.width
          wrapMode: Text.Wrap
          textFormat: Text.PlainText
          text: {
            if (!pg.message) return "";
            const b = pg.message.body;
            const i = b.indexOf("\n");
            return i < 0 ? "" : b.slice(i + 1).replace(/^\s+/, "");
          }
          color: Zenon.accentSoft
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(14)
        }
      }
      ElasticScroll { anchors.fill: bodyFlick; view: bodyFlick }
      Scrollbar { flick: bodyFlick; anchors.right: bodyFlick.right; anchors.top: bodyFlick.top; anchors.bottom: bodyFlick.bottom }
      }
      // signed, and whether git could check it (D.signatureOf)
      Text {
        readonly property var sig: pg.message ? D.signatureOf(pg.message.signature, pg.message.signer) : null
        visible: !!sig
        width: parent.width
        elide: Text.ElideRight
        text: sig ? sig.glyph + "  " + sig.words : ""
        color: sig ? Zenon[sig.ink] : Zenon.accentMuted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(13)
      }
      // what the forge's checks said of it, each a click from its log
      Row {
        readonly property var c: pg.commit ? pg.ciOf(pg.commit.sha) : null
        visible: !!c && c.state !== "none"
        spacing: 8
        CiDot { anchors.verticalCenter: parent.verticalCenter; c: parent.c }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: !parent.c ? "" : D.ciWords(parent.c)
          color: !parent.c ? Zenon.accentMuted : parent.c.state === "failure" ? Zenon.red : parent.c.state === "success" ? Zenon.green
            : parent.c.state === "pending" ? Zenon.yellow : Zenon.accentMuted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(13)
        }
      }
      CiRuns {
        width: parent.width
        c: pg.commit ? pg.ciOf(pg.commit.sha) : null
        visible: !!c && c.runs && c.runs.length > 0 && c.state !== "success"
        most: 6
      }
    }
    Rectangle { id: headRule; y: headCol.y + headCol.height + 12; width: parent.width; height: 1; color: Zenon.border; visible: !!pg.commit }

    // its files go up under the filter field, the commit's message and the
    // window's head, frosted — the window's ScrollEdge (edgeViews), drawn
    // under this page, so the title and message read over it (user,
    // 2026-10-11: the frost carried up through them)
    // its files, filtered by what is typed here
    BulkField {
      id: fileFilter
      visible: pg.files.length > 1
      anchors.top: headRule.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.margins: 10
      height: pg.files.length > 1 ? 30 : 0
      textSize: Zenon.px(14)
      ghost: "  Filter " + pg.files.length + " files  ( / )"
      clearable: true
      onTextChanged: pg.fileQuery = fileFilter.text.trim()
      onAccepted: { pg.area = "files"; pg.win.focusKeys(); }
      Keys.onEscapePressed: { fileFilter.text = ""; pg.area = "files"; pg.win.focusKeys(); }
      Keys.onDownPressed: { pg.area = "files"; pg.win.focusKeys(); }
    }
    ListView {
      id: fileList
      anchors.top: fileFilter.visible ? fileFilter.bottom : headRule.bottom
      anchors.topMargin: fileFilter.visible ? 4 : 0
      anchors.left: parent.left
      anchors.right: parent.right
      height: pg.win && pg.win.splits.historyFiles ? Math.min(contentHeight + 8, pg.win.splits.historyFiles)
        : Math.min(contentHeight + 8, Math.round(right.height * 0.3))
      clip: true
      topMargin: 4
      bottomMargin: 4
      boundsBehavior: Flickable.StopAtBounds
      model: pg.shownFiles
      readonly property int rowH: Math.round(Zenon.px(14) * 2)
      SelectBar { view: fileList; host: pg.win; index: pg.fileSel; rowH: fileList.rowH; color: pg.area === "files" ? pg.win.hiFill : Zenon.wash(0.05) }
      delegate: Item {
        id: frow
        required property var modelData
        required property int index
        readonly property var probe: ({ name: D.baseName(frow.modelData.path), path: frow.modelData.path, size: 1 })
        width: fileList.width
        height: fileList.rowH
        Text {
          id: fg
          x: 18
          width: 20
          anchors.verticalCenter: parent.verticalCenter
          text: Terminus.glyphOf(frow.probe, Icons)
          color: Zenon[Terminus.inkKeyOf(frow.probe)]
          font.family: Zenon.glyphFace
          font.pixelSize: Zenon.px(14)
        }
        Text {
          anchors.left: fg.right
          anchors.leftMargin: 6
          anchors.right: counts.left
          anchors.rightMargin: 10
          anchors.verticalCenter: parent.verticalCenter
          elide: Text.ElideMiddle
          text: (frow.modelData.from ? frow.modelData.from + "  →  " : "") + frow.modelData.path
          color: frow.modelData.status === "D" ? Zenon.accentMuted : frow.index === pg.fileSel ? Zenon.ink : Zenon.accentSoft
          font.strikeout: frow.modelData.status === "D"
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(14)
        }
        Text {
          id: counts
          anchors.right: parent.right
          anchors.rightMargin: 18
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.StyledText
          text: frow.modelData.status === "D" ? "<font color=\"" + Zenon.hex(Zenon.red) + "\">removed</font>"
            : frow.modelData.added === null ? "binary"
            : "<font color=\"" + Zenon.hex(Zenon.green) + "\">+" + frow.modelData.added + "</font>  "
              + "<font color=\"" + Zenon.hex(Zenon.red) + "\">−" + frow.modelData.deleted + "</font>"
          color: Zenon.accentMuted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.features: { "tnum": 1 }
          font.pixelSize: Zenon.px(13)
        }
        MouseArea {
          anchors.fill: parent
          onClicked: { pg.area = "files"; pg.fileSel = frow.index; pg.loadFileDiff(); pg.win.focusKeys(); }
          onDoubleClicked: pg.win.edit(pg.absOf(frow.modelData.path))
        }
      }
    }
    // the wheel and the bar, as every list has them
    ElasticScroll { anchors.fill: fileList; view: fileList }
    Scrollbar { flick: fileList; anchors.right: fileList.right; anchors.top: fileList.top; anchors.bottom: fileList.bottom }
    // (the line under the files is the seam's own, below)
    Item { id: filesRule; anchors.top: fileList.bottom; width: parent.width; height: 1; visible: pg.files.length > 0 }
    // the seam between its files and their diff
    SeamGrip {
      vertical: false
      visible: pg.files.length > 0
      frame: right
      at: filesRule.y
      min: fileList.y + 60
      max: right.height - 160
      onMoved: (p) => pg.win.setSplit("historyFiles", p - fileList.y)
      onReset: pg.win.setSplit("historyFiles", 0)
    }

    BlameView {
      id: blameView
      anchors.top: filesRule.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      visible: pg.blamePath !== ""
      win: pg.win
      path: pg.blamePath
      rev: pg.blameAt === "head" ? "" : pg.commit ? pg.commit.sha : ""
      line: pg.blameLine
      onPicked: (sha) => { pg.blamePath = ""; pg.jumpSha = sha; pg.reload(); }
      onClosed: pg.blamePath = ""
    }
    DiffView {
      id: diff
      visible: pg.blamePath === ""
      anchors.top: filesRule.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      host: pg.win
      files: pg.diffFiles
      editable: false
      empty: ""
    }
  }

  // ── reworking the commits after one ────────────────────────────────────
  RebasePlan {
    id: plan
    anchors.fill: parent
    win: pg.win
    onFinished: { pg.reload(); Qt.callLater(pg.takeFocus); }
  }

  PopMenu {
    id: menu
    anchors.fill: parent
    window: pg.win
    cardWidth: 260
    onClosed: pg.win.focusKeys()
  }
  // the seams: commits | the commit, and its files | their diff
  SeamGrip {
    visible: !pg.planning
    frame: pg
    at: left.width
    min: 320
    max: pg.width - 360
    onMoved: (p) => pg.win.setSplit("history", p)
    onReset: pg.win.setSplit("history", 0)
  }
}
