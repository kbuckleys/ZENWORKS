// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// CHANGES — the files that differ, in the order they are worked through
// (conflicts, then what is not staged, then what is), the chosen one's diff
// beside them, and the message under them.
//
// Each section is a TREE — the files under their directories, drawn with
// terminus' own row (terminus/EntryRow on a terminus/TreeHost): its glyphs,
// guides, chevrons and git letters, so a change looks the same here as in
// the file manager and in plato's tree (user, 2026-10-11: a flat list of
// paths was "completely out of context"). A directory stages, unstages or
// discards everything under it.
//
//   the list   ↑↓ rows · space stage / unstage · d discard · e edit in plato
//              / filter by path (esc clears) ·
//              ctrl click mark · shift click / shift ↑↓ mark a range — then
//              space, d act on every one marked · esc clears the marks
//              ← → close / open a directory (→ on a file: the diff)
//              return a directory: close / open; a file: stage / unstage
//              a stage all · shift a unstage all · tab the diff · c message
//   the diff   ↑↓ lines · shift ↑↓ a range · [ ] hunks · space stage the
//              range or the hunk · l just this line · d discard it · e edit
//              here · esc back to the list
//   message    ctrl return commit · esc back to the list

import QtQuick
import Quickshell
import "../morpheus"
import "../terminus"
import "../picasso"
import "delphi.js" as D
import "../terminus/terminus.js" as Terminus
import "../morpheus/icons.js" as Icons

Item {
  id: pg
  property var win: null
  // the views whose rows carry on up under the window's head, frosted
  // (DelphiWindow's ScrollEdges) — only those with nothing but controls
  // between them and the head: a view under a title would paint over it
  readonly property var edgeViews: [list, diff.view]
  // the views that run down to the foot (the list stops at the commit box)
  readonly property var footViews: [diff.view]

  // ── the filter ─────────────────────────────────────────────────────────
  // What is typed in the field over the list (/): only the changes whose
  // path has it are shown, in their tree; a section's Stage all becomes
  // "Stage these" and takes only those.
  property string query: ""
  readonly property var shownSt: {
    const st = pg.win ? pg.win.st : null;
    const q = pg.query.toLowerCase();
    if (!st || q === "") return st;
    const has = (e) => (String(e.path) + " " + (e.from || "")).toLowerCase().indexOf(q) >= 0;
    return Object.assign({}, st, { staged: st.staged.filter(has), unstaged: st.unstaged.filter(has),
                                   untracked: st.untracked.filter(has), conflicts: st.conflicts.filter(has) });
  }
  function stageShown(sec) {
    const st = pg.shownSt;
    if (!st) return;
    const paths = sec === "staged" ? st.staged.map((e) => e.path)
      : st.unstaged.map((e) => e.path).concat(st.untracked.map((e) => e.path));
    if (paths.length === 0) return;
    pg.win.act(sec === "staged" ? "unstage" : "stage", { paths: paths },
               { said: (sec === "staged" ? "Unstaged " : "Staged ") + paths.length + " matching “" + pg.query + "”" });
  }

  // directories put away, by D.treeRows' key
  property var closed: ({})
  // the tree's rows, each file and directory also as the entry terminus'
  // row draws ({ e }: glyph and ink as a listing's), a directory wearing the
  // worst state beneath it. Each section is its own little tree, rooted at
  // "/<section>", so a file both staged and not is two entries.
  readonly property var rows: {
    const rs = D.treeRows(D.sections(pg.shownSt), pg.closed);
    for (const r of rs) {
      if (r.head) continue;
      if (r.isDir) r.state = r.states.reduce((a, b) => Terminus.gitWorse(a, b), "");
      const name = r.name;
      r.e = Terminus.enrich([{ name: name, path: "/" + r.sec + "/" + r.path, isDir: !!r.isDir, isLink: false,
        broken: false, isExec: false, mode: 0, isHidden: name.charAt(0) === ".", size: 1, mtime: 0 }], Icons)[0];
    }
    return rs;
  }
  // git's letters, for the rows' gutter (TreeHost.marks)
  readonly property var marks: {
    const out = {};
    for (const r of pg.rows) if (!r.head) out[r.e.path] = r.state;
    return out;
  }
  TreeHost {
    id: treeHost
    fontSize: Zenon.px(15)
    root: "/"
    marks: pg.marks
    noteWidth: 44
  }
  function setOpen(r, open) {
    if (!r || !r.isDir) return;
    const c = Object.assign({}, pg.closed);
    if (open) delete c[r.key]; else c[r.key] = true;
    pg.closed = c;
  }
  property int cur: -1
  readonly property var file: pg.cur >= 0 && pg.cur < pg.rows.length && !pg.rows[pg.cur].head ? pg.rows[pg.cur] : null
  property string area: "list"     // list | diff | message
  readonly property int stagedCount: pg.win && pg.win.st ? pg.win.st.staged.length : 0
  readonly property bool clean: !!pg.win && !!pg.win.st && pg.rows.every((r) => r.head)

  readonly property string title: "Changes"
  // the branch only: where Push sends it is the chip beside it in the head
  // (DelphiWindow's pushChip — the upstream named here read as the only
  // place it would go, 2026-10-11)
  readonly property string subtitle: !pg.win || !pg.win.st ? "" : pg.win.branchName
  readonly property bool showsPush: true
  readonly property var hints: pg.area === "message"
    ? [["ctrl return", "commit"], ["esc", "back"]]
    : pg.area === "diff"
    ? [["space", diff.ranged ? "lines" : "hunk"], ["l", "line"], ["shift ↑↓", "range"], ["[ ]", "hunks"],
       ["d", "discard"], ["e", "edit"], ["tab", "files"]]
    : pg.markedCount > 0
    ? [["space", (pg.markedRows[0].area === "staged" ? "unstage " : "stage ") + pg.markedCount + " marked"],
       ["d", "discard them"], ["shift ↑↓", "mark more"], ["esc", "clear marks"], ["c", "message"]]
    : pg.file && pg.file.isDir
    ? [["space", (pg.file.area === "staged" ? "unstage " : "stage ") + pg.file.count], ["← →", "close / open"],
       ["d", "discard"], ["a", "stage all"], ["c", "message"]]
    : [["space", pg.file && pg.file.area === "staged" ? "unstage" : "stage"], ["a", "stage all"],
       ["d", "discard"], ["e", "edit"], ["i", "keep out"], ["tab", "diff"], ["c", "message"], ["/", "filter"]]
  readonly property var lead: pg.chosenRows()[0] || null
  readonly property var buttons: [
    { label: pg.markedCount > 0 ? "Discard " + pg.markedCount : "Discard", ink: Zenon.red,
      visible: !!pg.lead && pg.lead.area !== "staged" && pg.lead.area !== "conflict", run: () => pg.discard() },
    { label: (pg.lead && pg.lead.area === "staged" ? "Unstage" : "Stage") + (pg.markedCount > 0 ? " " + pg.markedCount : ""),
      visible: !!pg.lead && pg.lead.area !== "conflict", run: () => pg.toggle() },
  ]

  function takeFocus() {
    if (changeFilter.focused) return;
    if (pg.area === "message") msgWell.claim();
    else if (pg.win) pg.win.focusKeys();
  }

  // ── following the list as it changes ──────────────────────────────────
  // The file you were on stays chosen across a refresh; a file staged away
  // leaves the cursor where the work is (delphi.js reseat).
  // ── marked rows, to act on together ──────────────────────────────────
  // Keyed sec + ":" + path (a directory's key is the same shape). One
  // section at a time: marks in Staged and in Changes would ask one key to
  // stage and unstage at once.
  property var marked: ({})
  property int anchor: -1          // where a shift range starts
  readonly property var markedRows: pg.rows.filter((r) => !r.head && pg.marked[r.sec + ":" + r.path])
  readonly property int markedCount: pg.markedRows.length
  function keyOf(r) { return r.sec + ":" + r.path; }
  function mark(i, on) {
    const r = pg.rows[i];
    if (!r || r.head) return;
    const m = Object.assign({}, pg.marked);
    // another section's marks give way
    for (const k in m) if (k.split(":")[0] !== r.sec) delete m[k];
    if (on === undefined ? !m[pg.keyOf(r)] : on) m[pg.keyOf(r)] = true; else delete m[pg.keyOf(r)];
    pg.marked = m;
  }
  function markRange(from, to) {
    const a = pg.rows[from];
    if (!a || a.head) return;
    const m = {};
    for (let i = Math.min(from, to); i <= Math.max(from, to); ++i) {
      const r = pg.rows[i];
      if (r && !r.head && r.sec === a.sec) m[pg.keyOf(r)] = true;
    }
    pg.marked = m;
  }
  function clearMarks() { pg.marked = ({}); pg.anchor = -1; }
  // what an action takes: the marked rows if any, else the cursor's
  function chosenRows() { return pg.markedCount > 0 ? pg.markedRows : (pg.file ? [pg.file] : []); }

  property var want: null
  onRowsChanged: {
    // marks on rows that went (staged away, committed) go with them
    if (pg.markedCount !== Object.keys(pg.marked).length) {
      const m = {};
      for (const r of pg.markedRows) m[pg.keyOf(r)] = true;
      pg.marked = m;
    }
    const i = D.reseat(pg.rows, pg.want, pg.cur);
    pg.cur = i;
    if (pg.file) pg.want = { path: pg.file.path, sec: pg.file.sec };
    pg.loadDiff();
  }
  function moveTo(i) {
    if (i < 0 || i >= pg.rows.length || pg.rows[i].head) return;
    pg.cur = i;
    pg.want = { path: pg.rows[i].path, sec: pg.rows[i].sec };
    list.positionViewAtIndex(i, ListView.Contain);
    diffWait.restart();
  }
  function step(d) { pg.moveTo(D.nextFile(pg.rows, pg.cur, d)); }

  // ── the diff beside ────────────────────────────────────────────────────
  property var diffFiles: []
  property int diffMore: -1
  property string diffFor: ""
  property bool diffLoading: false
  Timer { id: diffWait; interval: 50; onTriggered: pg.loadDiff() }
  function argsFor(f) {
    return { path: f.path, staged: f.area === "staged", untracked: f.area === "untracked", budget: 6000 };
  }
  function loadDiff() {
    const f = pg.file;
    if (!f || !pg.win || f.area === "conflict" || f.isDir) { pg.diffFiles = []; pg.diffFor = ""; pg.diffMore = -1; return; }
    const key = f.area + ":" + f.path;
    const fresh = key !== pg.diffFor;
    pg.diffLoading = true;
    pg.win.mgr.call("diff", pg.win.root, pg.argsFor(f), (ok, res) => { if (!pg) return;
      if (!pg.file || pg.file.area + ":" + pg.file.path !== key) return;
      pg.diffLoading = false;
      pg.diffFiles = ok ? res.files : [];
      pg.diffMore = ok && res.more !== null ? res.more : -1;
      pg.diffFor = key;
      if (fresh) diff.toFirst();
    });
  }
  function moreDiff() {
    const f = pg.file;
    if (!f || pg.diffMore < 0) return;
    const key = pg.diffFor;
    pg.win.mgr.call("diff", pg.win.root, Object.assign(pg.argsFor(f), { start: pg.diffMore }), (ok, res) => { if (!pg) return;
      if (!ok || key !== pg.diffFor) return;
      const a = pg.diffFiles.slice();
      for (const g of res.files) {
        const last = a[a.length - 1];
        if (last && last.new === g.new) a[a.length - 1] = Object.assign({}, last, { hunks: last.hunks.concat(g.hunks) });
        else a.push(g);
      }
      pg.diffFiles = a;
      pg.diffMore = res.more !== null ? res.more : -1;
    });
  }

  // ── doing ──────────────────────────────────────────────────────────────
  function toggle() {
    if (pg.markedCount > 0) {
      const rs = pg.markedRows, staged = rs[0].area === "staged";
      if (rs[0].area === "conflict") return;
      const paths = [].concat.apply([], rs.map((r) => r.isDir ? r.paths : [r.path]));
      const n = new Set(paths).size;
      pg.win.act(staged ? "unstage" : "stage", { paths: Array.from(new Set(paths)) },
                 { said: (staged ? "Unstaged " : "Staged ") + n + (n === 1 ? " file" : " files"), then: () => pg.clearMarks() });
      return;
    }
    const f = pg.file;
    if (!f) return;
    if (f.isDir) {
      if (f.area === "staged") pg.win.act("unstage", { paths: f.paths }, { said: "Unstaged " + f.count + " in " + f.name });
      else if (f.area !== "conflict") pg.win.act("stage", { paths: f.paths }, { said: "Staged " + f.count + " in " + f.name });
      return;
    }
    if (f.area === "staged") pg.win.act("unstage", { paths: [f.path] }, {});
    else if (f.area !== "conflict") pg.win.act("stage", { paths: [f.path] }, {});
  }
  function stageAll() { pg.win.act("stageAll", {}, { said: "Staged everything" }); }
  function unstageAll() { pg.win.act("unstageAll", {}, { said: "Unstaged everything" }); }
  // part of the file: the range, or the hunk under the cursor, or one line
  function stagePart(oneLine) {
    const f = pg.file;
    const chosen = oneLine ? diff.chosenLine() : diff.chosen();
    if (!f || !chosen) return;
    const op = f.area === "staged" ? "unstageLines" : "stageLines";
    const args = { path: f.path, chosen: chosen };
    if (f.area === "untracked") args.untracked = true;
    pg.win.act(op, args, { then: () => { diff.anchor = -1; } });
  }
  function discard() {
    const f = pg.file;
    if (pg.markedCount > 0) {
      const rs = pg.markedRows;
      if (rs[0].area === "staged" || rs[0].area === "conflict") return;
      const all = Array.from(new Set([].concat.apply([], rs.map((r) => r.isDir ? r.paths : [r.path]))));
      const fresh = new Set([].concat.apply([], rs.map((r) => r.isDir ? r.untracked : (r.area === "untracked" ? [r.path] : []))));
      const tracked = all.filter((p) => !fresh.has(p)), news = all.filter((p) => fresh.has(p));
      pg.win.confirm({ question: "Discard the changes to " + all.length + (all.length === 1 ? " file?" : " files?"), glyph: "", ink: Zenon.red,
        detail: "They go back to how they were staged or committed"
          + (news.length > 0 ? "; " + news.length + " new " + (news.length === 1 ? "one is" : "ones are") + " deleted — git has no copy" : "") + ".",
        items: all.slice(0, 8).concat(all.length > 8 ? ["… and " + (all.length - 8) + " more"] : []),
        verb: "Discard", then: () => {
          if (tracked.length > 0) pg.win.act("discard", { paths: tracked }, { said: "Discarded " + all.length });
          if (news.length > 0) pg.win.act("clean", { paths: news }, { said: "Discarded " + all.length });
          pg.clearMarks();
        } });
      return;
    }
    if (!f || f.area === "staged" || f.area === "conflict") return;
    if (f.isDir) {
      const tracked = f.paths.filter((p) => f.untracked.indexOf(p) < 0);
      pg.win.confirm({ question: "Discard the changes in " + f.name + "?", glyph: "", ink: Zenon.red,
        detail: f.count + (f.count === 1 ? " file goes" : " files go") + " back to how they were staged or committed"
          + (f.untracked.length > 0 ? "; " + f.untracked.length + " new " + (f.untracked.length === 1 ? "one is" : "ones are") + " deleted — git has no copy of " + (f.untracked.length === 1 ? "it" : "them") : "") + ".",
        items: f.paths.slice(0, 8).concat(f.paths.length > 8 ? ["… and " + (f.paths.length - 8) + " more"] : []),
        verb: "Discard", then: () => {
          if (tracked.length > 0) pg.win.act("discard", { paths: tracked }, { said: "Discarded " + f.name });
          if (f.untracked.length > 0) pg.win.act("clean", { paths: f.untracked }, { said: "Discarded " + f.name });
        } });
      return;
    }
    const part = pg.area === "diff" && f.area !== "untracked" ? (diff.ranged ? diff.chosen() : diff.chosen()) : null;
    if (f.area === "untracked") {
      pg.win.confirm({ question: "Delete " + f.name + "?", glyph: "", ink: Zenon.red,
        detail: "It is new — git has never seen it, so there is no copy to bring back.",
        items: [f.path], verb: "Delete", then: () => pg.win.act("clean", { paths: [f.path] }, { said: "Deleted " + f.name }) });
      return;
    }
    if (part) {
      pg.win.confirm({ question: diff.ranged ? "Discard these lines?" : "Discard this hunk?", glyph: "", ink: Zenon.red,
        detail: "Your edit to " + f.name + " there is undone in the file.", verb: "Discard",
        then: () => pg.win.act("discardLines", { path: f.path, chosen: part }, {}) });
      return;
    }
    pg.win.confirm({ question: "Discard your changes to " + f.name + "?", glyph: "", ink: Zenon.red,
      detail: "The file goes back to how it was staged (or committed). Unstaged edits are not kept anywhere.",
      items: [f.path], verb: "Discard", then: () => pg.win.act("discard", { paths: [f.path] }, { said: "Discarded " + f.name }) });
  }
  function edit() {
    const f = pg.file;
    if (f && f.isDir) { pg.win.reveal(pg.win.abs(f.path)); return; }
    if (!f || f.kind === "deleted") return;
    pg.win.edit(pg.win.abs(pg.area === "diff" && diff.pathAtCursor !== "" ? diff.pathAtCursor : f.path));
  }
  // ── KEPT OUT OF THE REPOSITORY, KEPT ON DISK ───────────────────────────
  // (user, 2026-10-11: a binary spoot builds into its own bin/.) Not yet
  // tracked: an ignore rule — .gitignore for everyone who clones it, or
  // this machine only (the git directory's info/exclude); by its path, or
  // every file of its kind. Tracked: untracked first (repo.untrack): the
  // next commit takes it out of the repository, the file stays.
  function keepOut(f) {
    f = f || pg.file;
    if (!f || f.area === "conflict") return;
    const tracked = f.isDir ? !pg.allUntracked(f) : !(f.kind === "untracked" || f.area === "untracked");
    const name = f.isDir ? f.path + "/" : f.path;
    const pattern = "/" + (f.isDir ? f.path.replace(/\/+$/, "") + "/" : f.path);
    const ext = !f.isDir && /\.[A-Za-z0-9]+$/.test(f.name) ? "*" + f.name.slice(f.name.lastIndexOf(".")) : "";
    if (!tracked) {
      const choices = [{ label: "In .gitignore", ink: Zenon.cyan, run: () => pg.win.act("ignore", { patterns: [pattern] }, { said: name + " is ignored — commit .gitignore so it stays so" }) },
                       { label: "Only on this machine", run: () => pg.win.act("ignore", { patterns: [pattern], where: "exclude" }, { said: name + " is ignored here" }) }];
      if (ext !== "") choices.push({ label: "Every " + ext + " file", run: () => pg.win.act("ignore", { patterns: [ext] }, { said: "Every " + ext + " file is ignored" }) });
      choices.push({ label: "Cancel", ink: Zenon.accentMuted });
      pg.win.card_({ question: "Keep " + name + " out of the repository?", glyph: "\uF070", ink: Zenon.ink,
        detail: "It stays on your disk; git stops offering it. In .gitignore for everyone who clones the repository, or only on this machine (.git/info/exclude).",
        items: [pattern], choices: choices });
      return;
    }
    const all = f.isDir ? f.paths : [f.path];
    pg.win.card_({ question: "Stop tracking " + name + "?", glyph: "\uF070", ink: Zenon.yellow,
      detail: "It leaves the repository with your next commit (and the remote's when you push), and stays on your disk. An ignore rule keeps it from coming back.",
      items: all.length > 8 ? all.slice(0, 8).concat(["… and " + (all.length - 8) + " more"]) : all,
      choices: [{ label: "Stop tracking", ink: Zenon.yellow, run: () => pg.win.act("untrack", { paths: [f.path] }, { said: name + " untracked — commit to take it out of the repository" }) },
                { label: "Stop tracking, ignore here only", run: () => pg.win.act("untrack", { paths: [f.path], where: "exclude" }, { said: name + " untracked — commit to take it out" }) },
                { label: "Cancel", ink: Zenon.accentMuted }] });
  }
  // a directory row whose files git does not track at all
  function allUntracked(f) {
    const st = pg.win.st;
    if (!st || !f.isDir) return false;
    const pre = f.path.replace(/\/+$/, "") + "/";
    return !st.unstaged.concat(st.staged).some((e) => e.path.indexOf(pre) === 0);
  }
  // ── the row menu ──────────────────────────────────────────────────────
  function rowMenu(item, index) {
    const f = pg.rows[index];
    if (!f || f.head) return;
    const staged = f.area === "staged", conflict = f.area === "conflict";
    const items = [];
    if (!conflict) items.push({ text: staged ? "Unstage" : "Stage", icon: staged ? "\uF068" : "\uF067", mark: "space", run: () => pg.toggle() });
    if (!conflict && !staged) items.push({ text: "Discard changes", icon: "\uF0E2", mark: "d", danger: true, run: () => pg.discard() });
    items.push({ isSeparator: true });
    if (!f.isDir && f.kind !== "deleted") items.push({ text: "Edit in plato", icon: "\uF044", mark: "e", run: () => pg.edit() });
    items.push({ text: "Show in terminus", icon: "\uF07C", run: () => pg.win.reveal(pg.win.abs(f.path)) });
    if (!conflict) items.push({ isSeparator: true },
      { text: "Keep out of the repository", icon: "\uF070", mark: "i", run: () => pg.keepOut(f) });
    const p = item.mapToItem(pg, 40, item.height);
    rowPop.open(p.x, p.y, items, index);
  }

  // a conflict: one side whole, or the file as edited (markers gone) marked done
  function resolve(how) {
    const f = pg.file;
    if (!f || f.area !== "conflict") return;
    if (how === "ours" || how === "theirs") pg.win.act("take", { path: f.path, side: how }, { said: "Took " + how + " for " + f.name });
    else pg.win.act("markResolved", { paths: [f.path] }, { said: f.name + " resolved" });
  }

  // ── committing ─────────────────────────────────────────────────────────
  property bool amend: false
  readonly property var note: D.messageNote(msgWell.text)
  // left empty, the message is written from what is staged (D.autoMessage
  // — "Add README.md and LICENSE"): git wants one, and a blank title reads
  // as nothing in a history (user, 2026-10-11: "do i really need one?")
  readonly property string autoMsg: pg.win && pg.win.st ? D.autoMessage(pg.win.st.staged) : ""
  readonly property bool typed: msgWell.text.trim() !== ""
  readonly property bool canCommit: (pg.note.ok || (!pg.typed && !pg.amend && pg.autoMsg !== "")) && (pg.stagedCount > 0 || pg.amend)
    && !!pg.win && !!pg.win.st && pg.win.st.conflicts.length === 0
  onAmendChanged: {
    if (pg.amend && msgWell.text.trim() === "") {
      pg.win.mgr.call("lastMessage", pg.win.root, {}, (ok, m) => { if (!pg) return; if (ok && msgWell.text.trim() === "") msgWell.text = m; });
    }
  }
  // ── taking the last commit back ──────────────────────────────────────
  readonly property bool canUndo: !!pg.win && !!pg.win.branch && !!pg.win.branch.oid && !pg.amend
  property string lastSubject: ""
  function readSubject() {
    if (!pg.win || !pg.canUndo) { pg.lastSubject = ""; return; }
    pg.win.mgr.call("lastMessage", pg.win.root, {}, (ok, m) => {
      if (pg.win && ok) pg.lastSubject = String(m || "").split("\n")[0];
    });
  }
  readonly property string headOid: pg.win && pg.win.branch && pg.win.branch.oid ? pg.win.branch.oid : ""
  onHeadOidChanged: pg.readSubject()
  onWinChanged: Qt.callLater(pg.readSubject)
  function undoCommit() {
    if (!pg.canUndo) return;
    const b = pg.win.branch;
    const go = () => pg.win.act("undoCommit", {}, {
      label: "Undoing the commit",
      then: (r) => {
        // the message back in the box, unless one is being written
        if (msgWell.text.trim() === "" && r && r.message) msgWell.text = r.message;
        pg.win.say("Commit undone — its changes are staged again");
      } });
    // on the remote already: undoing it here leaves it there, and the next
    // push would have to force
    if (b.upstream && b.ahead === 0)
      pg.win.confirm({ question: "Undo a commit that is already pushed?", glyph: "\uF0E2", ink: Zenon.yellow,
        detail: "“" + pg.lastSubject + "” is on " + b.upstream + " too. It stays there; pushing again afterwards needs a force-push.",
        verb: "Undo it here", then: go });
    else go();
  }

  function commit() {
    if (!pg.canCommit) {
      if (pg.stagedCount === 0 && !pg.amend) pg.win.say("Nothing staged to commit", true);
      else if (!pg.note.ok) { pg.area = "message"; pg.takeFocus(); }
      return;
    }
    const id = pg.win.info && pg.win.info.identity;
    if (id && (id.name === "" || id.email === "")) { pg.win.askIdentity(() => pg.commit()); return; }
    const text = pg.typed ? msgWell.text : pg.autoMsg;
    const amending = pg.amend;
    pg.win.act("commit", { message: text, amend: amending }, {
      label: "Committing",
      said: amending ? "Amended" : pg.typed ? "Committed" : "Committed — “" + text + "”",
      then: () => { msgWell.text = ""; pg.win.draft = ""; pg.amend = false; pg.area = "list"; pg.takeFocus(); } });
  }

  // ── keys ───────────────────────────────────────────────────────────────
  function key(e) {
    const k = e.key, ctrl = e.modifiers & Qt.ControlModifier, shift = e.modifiers & Qt.ShiftModifier;
    if (ctrl && (k === Qt.Key_Return || k === Qt.Key_Enter)) { pg.commit(); return true; }
    // ctrl z: the last commit taken back — not in the message, whose own it is
    if (ctrl && k === Qt.Key_Z && pg.area !== "message") { pg.undoCommit(); return true; }
    if (ctrl) return false;
    if (pg.area === "diff") {
      if (k === Qt.Key_Escape) { if (diff.anchor >= 0) diff.anchor = -1; else pg.area = "list"; return true; }
      if (k === Qt.Key_Tab || k === Qt.Key_Backtab) { pg.area = "list"; return true; }
      if (k === Qt.Key_Up || k === Qt.Key_K) { diff.move(-1, !!shift); return true; }
      if (k === Qt.Key_Down || k === Qt.Key_J) { diff.move(1, !!shift); return true; }
      if (k === Qt.Key_PageUp) { diff.page(-1); return true; }
      if (k === Qt.Key_PageDown) { diff.page(1); return true; }
      if (k === Qt.Key_BracketLeft) { diff.jumpHunk(-1); return true; }
      if (k === Qt.Key_BracketRight) { diff.jumpHunk(1); return true; }
      if (k === Qt.Key_N) { diff.jump(shift ? -1 : 1); return true; }
      if (k === Qt.Key_Space || k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_S || k === Qt.Key_U) { pg.stagePart(false); return true; }
      if (k === Qt.Key_L) { pg.stagePart(true); return true; }
      if (k === Qt.Key_D) { pg.discard(); return true; }
      if (k === Qt.Key_E) { pg.edit(); return true; }
      if (k === Qt.Key_C) { pg.area = "message"; pg.takeFocus(); return true; }
      return false;
    }
    if (shift && (k === Qt.Key_Up || k === Qt.Key_Down)) {
      if (pg.anchor < 0) pg.anchor = pg.cur;
      const to = D.nextFile(pg.rows, pg.cur, k === Qt.Key_Up ? -1 : 1);
      // a range stays in its section
      if (pg.rows[to] && pg.rows[pg.anchor] && pg.rows[to].sec === pg.rows[pg.anchor].sec) { pg.moveTo(to); pg.markRange(pg.anchor, to); }
      return true;
    }
    if (k === Qt.Key_Escape && pg.markedCount > 0) { pg.clearMarks(); return true; }
    if (k === Qt.Key_Slash) { changeFilter.claim(); return true; }
    if (k === Qt.Key_Escape && pg.query !== "") { changeFilter.text = ""; return true; }
    if (k === Qt.Key_Up || k === Qt.Key_K) { pg.anchor = -1; pg.step(-1); return true; }
    if (k === Qt.Key_Down || k === Qt.Key_J) { pg.anchor = -1; pg.step(1); return true; }
    if (k === Qt.Key_Home) { pg.moveTo(D.nextFile(pg.rows, -1, 1)); return true; }
    if (k === Qt.Key_End) { pg.moveTo(D.nextFile(pg.rows, pg.rows.length, -1)); return true; }
    // a directory: → opens it (and once open, steps in), ← closes it (and
    // once closed, goes up to the one it is in); return opens or closes
    const f = pg.file;
    if (f && f.isDir && (k === Qt.Key_Right || k === Qt.Key_L)) { if (!f.expanded) pg.setOpen(f, true); else pg.step(1); return true; }
    if (f && (k === Qt.Key_Left || k === Qt.Key_H)) {
      if (f.isDir && f.expanded) pg.setOpen(f, false);
      else for (let i = pg.cur - 1; i >= 0 && !pg.rows[i].head; --i)
        if (pg.rows[i].isDir && pg.rows[i].depth === f.depth - 1) { pg.moveTo(i); break; }
      return true;
    }
    if (f && f.isDir && (k === Qt.Key_Return || k === Qt.Key_Enter)) { pg.setOpen(f, !f.expanded); return true; }
    if (k === Qt.Key_Space || k === Qt.Key_Return || k === Qt.Key_Enter) { pg.toggle(); return true; }
    if (k === Qt.Key_Tab || k === Qt.Key_Right || k === Qt.Key_L) { if (pg.file && !pg.file.isDir) pg.area = "diff"; return true; }
    if (k === Qt.Key_A) { if (shift) pg.unstageAll(); else pg.stageAll(); return true; }
    if (k === Qt.Key_D) { pg.discard(); return true; }
    if (k === Qt.Key_E) { pg.edit(); return true; }
    if (k === Qt.Key_I) { pg.keepOut(); return true; }
    if (k === Qt.Key_C) { pg.area = "message"; pg.takeFocus(); return true; }
    if (pg.file && pg.file.area === "conflict") {
      if (k === Qt.Key_O) { pg.resolve("ours"); return true; }
      if (k === Qt.Key_T) { pg.resolve("theirs"); return true; }
      if (k === Qt.Key_R) { pg.resolve("done"); return true; }
    }
    return false;
  }
  onAreaChanged: Qt.callLater(pg.takeFocus)

  // ── the files ──────────────────────────────────────────────────────────
  Item {
    id: left
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: pg.win && pg.win.splits.changes ? pg.win.splits.changes : Math.round(Math.min(440, Math.max(320, pg.width * 0.32)))

    BulkField {
      id: changeFilter
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: 10
      height: 30
      textSize: Zenon.px(14)
      ghost: "  Filter changes  ( / )"
      clearable: true
      onTextChanged: pg.query = changeFilter.text.trim()
      onAccepted: { pg.area = "list"; pg.win.focusKeys(); }
      Keys.onEscapePressed: { changeFilter.text = ""; pg.win.focusKeys(); }
      Keys.onDownPressed: pg.win.focusKeys()
    }
    ListView {
      id: list
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: changeFilter.bottom
      anchors.topMargin: 2
      anchors.bottom: box.top
      clip: true
      topMargin: 6
      bottomMargin: 6
      boundsBehavior: Flickable.StopAtBounds
      model: pg.rows
      readonly property int rowH: treeHost.rowH + 4
      SelectBar {
        view: list
        host: pg.win
        index: Math.max(0, pg.cur)
        rowH: list.rowH
        on: pg.cur >= 0
        color: pg.area === "list" ? pg.win.hiFill : Zenon.wash(0.05)
        radius: Zenon.windowRadius
        inset: 8
      }
      delegate: Item {
        id: frow
        required property var modelData
        required property int index
        readonly property var r: frow.modelData
        width: list.width
        height: list.rowH

        // ── a section's head ──
        Item {
          anchors.fill: parent
          visible: !!frow.r.head
          GroupHead {
            inset: 16
            title: frow.r.head ? frow.r.title : ""
            count: frow.r.head ? frow.r.count : -1
            ink: frow.r.id === "conflict" ? Zenon.red : Zenon.accentMuted
          }
          Text {
            visible: !!frow.r.head && frow.r.count > 0 && frow.r.id !== "conflict"
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 4
            text: pg.query !== "" ? (frow.r.id === "staged" ? "Unstage these" : "Stage these")
              : frow.r.id === "staged" ? "Unstage all" : "Stage all"
            color: headMa.containsMouse ? Zenon.cyan : Zenon.accentMuted
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(13)
            MouseArea {
              id: headMa
              anchors.fill: parent
              anchors.margins: -6
              hoverEnabled: true
              onClicked: pg.query !== "" ? pg.stageShown(frow.r.id) : frow.r.id === "staged" ? pg.unstageAll() : pg.stageAll()
            }
          }
        }

        // ── a file or a directory: terminus' row ──
        EntryRow {
          id: erow
          anchors.fill: parent
          anchors.leftMargin: 8
          anchors.rightMargin: 8
          visible: !frow.r.head
          host: treeHost
          entry: frow.r.head ? null : frow.r.e
          depth: frow.r.depth || 0
          guide: frow.r.guide === undefined ? -1 : frow.r.guide
          inTree: true
          branch: !!frow.r.isDir
          expanded: !!frow.r.expanded
          showMeta: false
          actionable: false
          dim: frow.r.kind === "deleted"
          current: frow.index === pg.cur
          ticked: !frow.r.head && !!pg.marked[frow.r.sec + ":" + frow.r.path]
          live: pg.area === "list"
          passive: false
          onToggled: { pg.moveTo(frow.index); pg.setOpen(frow.r, !frow.r.expanded); }
          // ctrl: mark it; shift: mark from the last one to it; plain: the
          // cursor here, the marks cleared — as terminus clicks
          onChosen: (right, shift, ctrl) => {
            if (right) { pg.area = "list"; pg.moveTo(frow.index); pg.rowMenu(erow, frow.index); return; }
            pg.area = "list";
            if (ctrl) { pg.mark(frow.index); pg.anchor = frow.index; }
            else if (shift) { if (pg.anchor < 0) pg.anchor = pg.cur; pg.markRange(pg.anchor, frow.index); }
            else { pg.clearMarks(); }
            pg.moveTo(frow.index);
            pg.takeFocus();
          }
          // double click: a directory opens or closes, a file is staged or unstaged
          onOpened: { pg.moveTo(frow.index); if (frow.r.isDir) pg.setOpen(frow.r, !frow.r.expanded); else pg.toggle(); }
          // how many files a directory holds
          Text {
            visible: !!frow.r.isDir
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: frow.r.isDir ? String(frow.r.count) : ""
            color: Zenon.accentMuted
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.features: { "tnum": 1 }
            font.pixelSize: Zenon.px(13)
          }
          HoverHandler {
            onHoveredChanged: hovered && !frow.r.head
              ? pg.win.tip(erow, frow.r.path + (frow.r.from ? "  ←  " + frow.r.from : ""), frow.r.isDir ? frow.r.count + " files" : (frow.r.how || frow.r.word))
              : pg.win.untip(erow)
          }
        }
      }
      EmptyMark {
        anchors.centerIn: parent
        visible: pg.clean
        filtered: pg.query !== ""
        word: pg.query !== "" ? "" : "Nothing to commit"
      }
    }
    ElasticScroll { anchors.fill: list; view: list }
    Scrollbar { flick: list; anchors.right: list.right; anchors.top: list.top; anchors.bottom: list.bottom }

    // ── the message ──────────────────────────────────────────────────────
    Item {
      id: box
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: 196
      Rectangle { width: parent.width; height: 1; color: Zenon.border }

      MessageWell {
        id: msgWell
        x: 12
        y: 12
        width: parent.width - 24
        height: 112
        ghost: pg.stagedCount > 0 ? "Left empty, it says “" + pg.autoMsg + "” — or say what it does: a short first line, then more after a blank line"
          : "Stage something to commit, then say what it does"
        // the subject's length, as it is typed: 50 is the habit, 72 the wall
        note: pg.note.text
        noteInk: Zenon[pg.note.ink]
        passKeys: (e) => pg.win.key(e)
        // the draft lives on the window: a trip to History and back keeps it
        Component.onCompleted: msgWell.text = pg.win ? pg.win.draft : ""
        onTextChanged: if (pg.win) pg.win.draft = msgWell.text
        onFocusedChanged: if (msgWell.focused) pg.area = "message"
        onSubmitted: pg.commit()
        onEscaped: pg.area = "list"
        onTabbed: pg.area = "list"
      }
      Switch {
        anchors.left: msgWell.left
        anchors.top: msgWell.bottom
        anchors.topMargin: 16
        width: 200
        height: 28
        // short: the undo glyph and Commit share the row (2026-10-14)
        label: "Amend last"
        on: pg.amend
        onToggled: pg.amend = !pg.amend
      }
      // UNDO THE LAST COMMIT (user, 2026-10-14): what it changed staged
      // again and its message back in the box — undoCommit
      DialogButton {
        id: undoBtn
        visible: pg.canUndo
        anchors.right: commitBtn.left
        anchors.rightMargin: 8
        anchors.top: commitBtn.top
        // U+F054D (user, 2026-10-14): a word overlapped the Amend switch
        label: "\u{F054D}"
        glyph: true
        ink: Zenon.accentMuted
        onClicked: pg.undoCommit()
        HoverHandler {
          onHoveredChanged: if (pg.win) hovered
            ? pg.win.tip(undoBtn, "Take back “" + pg.lastSubject + "” — its changes stay staged", "ctrl z")
            : pg.win.untip(undoBtn)
        }
      }
      DialogButton {
        id: commitBtn
        anchors.right: msgWell.right
        anchors.top: msgWell.bottom
        anchors.topMargin: 14
        label: pg.amend ? "Amend" : pg.stagedCount > 0 ? "Commit " + pg.stagedCount : "Commit"
        ink: Zenon.cyan
        primary: pg.canCommit
        ready: pg.canCommit
        onClicked: pg.commit()
      }
    }
  }

  // ── the diff ───────────────────────────────────────────────────────────
  DiffView {
    id: diff
    anchors.left: left.right
    anchors.leftMargin: 1
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    visible: !pg.file || pg.file.area !== "conflict"
    host: pg.win
    files: pg.diffFiles
    more: pg.diffMore >= 0
    editable: !!pg.file && pg.file.area !== "conflict"
    empty: !pg.file ? "" : pg.file.isDir
      ? pg.file.count + (pg.file.count === 1 ? " file" : " files") + " in " + pg.file.name + " — space "
        + (pg.file.area === "staged" ? "unstages" : "stages") + (pg.file.count === 1 ? " it" : " them all")
      : pg.diffLoading ? "" : "No changes"
    onActivated: (chosen) => { pg.area = "diff"; pg.stagePart(false); }
    onWantMore: pg.moreDiff()
    // a click in the diff is working in the diff
    onTouched: pg.area = "diff"
  }
  // CLEAN (user, 2026-10-14: "nothing to commit" alone said nothing
  // else): in the diff's place, the last commit, where the branch stands
  // with its upstream and when that was last asked, and what to do about it
  //
  // A PUSH, in the same place (user, 2026-10-14): while one runs the clean
  // view fades out and the push (PushSummary: where, a meter, the commits)
  // fades in; once it has landed and lingered, out it goes and the clean
  // view — the branch's new standing — comes back. One, then the other,
  // never both at once. The push bubble stays down meanwhile (holdsPush).
  readonly property bool holdsPush: pg.clean && pg.query === ""
  readonly property bool wantPush: !!pg.win && !!pg.win.pushing
  property bool pushUp: false      // which of the two has the place
  property real placeOp: 1         // and how far in it is
  onWantPushChanged: placeSwap.restart()
  Component.onCompleted: pg.pushUp = pg.wantPush
  SequentialAnimation {
    id: placeSwap
    NumberAnimation { target: pg; property: "placeOp"; to: 0; duration: Zenon.normal; easing.type: Easing.InCubic }
    ScriptAction { script: pg.pushUp = pg.wantPush }
    NumberAnimation { target: pg; property: "placeOp"; to: 1; duration: Zenon.normal; easing.type: Easing.OutCubic }
  }
  PushSummary {
    anchors.centerIn: diff
    lineWidth: Math.min(diff.width - 48, 520)
    centered: true
    spacing: 10
    visible: pg.holdsPush && pg.pushUp && opacity > 0
    opacity: pg.pushUp ? pg.placeOp : 0
    p: pg.win ? pg.win.pushing : null
    job: pg.win ? pg.win.netJob : null
  }
  Column {
    anchors.centerIn: diff
    width: Math.min(diff.width - 48, 520)
    visible: pg.holdsPush && !pg.pushUp && opacity > 0
    opacity: pg.pushUp ? 0 : pg.placeOp
    spacing: 10
    readonly property var b: pg.win && pg.win.branch ? pg.win.branch : null
    readonly property var tip: pg.win ? (pg.win.refs.local || []).find((r) => r.current) || null : null
    readonly property real fetched: pg.win && pg.win.mgr.fetchedAt[pg.win.root] || 0
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      text: "All committed"
      color: Zenon.ink
      font.family: Zenon.face
      font.weight: Font.Bold
      font.pixelSize: Zenon.px(17)
    }
    Text {
      visible: !!parent.tip
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
      text: parent.tip ? "Last: “" + parent.tip.subject + "”  ·  " + D.ago(parent.tip.when, Date.now()) : ""
      color: Zenon.accentSoft
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(14)
    }
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.Wrap
      readonly property var b: parent.b
      text: !b || !b.oid ? "No commits yet"
        : !b.upstream ? (pg.win.remotes.length > 0 ? "Not published yet" : "No remote — this is the only copy")
        : (b.ahead === 0 && b.behind === 0 ? "Up to date with " + b.upstream
           : [b.ahead > 0 ? "↑" + b.ahead + " to push" : "", b.behind > 0 ? "↓" + b.behind + " to pull" : ""].filter((w) => w).join("  ·  ")
             + "  —  " + b.upstream)
          + (parent.fetched ? "  ·  fetched " + D.ago(Math.floor(parent.fetched / 1000), Date.now()) : "")
      color: !b || !b.upstream ? Zenon.accentMuted : b.ahead > 0 || b.behind > 0 ? Zenon.cyan : Zenon.green
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(14)
    }
    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 8
      topPadding: 4
      DialogButton { label: "History"; onClicked: pg.win.setPage("history") }
      DialogButton { label: "Apply a patch"; onClicked: pg.win.applyPatch() }
      DialogButton {
        visible: !!parent.parent.b && parent.parent.b.behind > 0
        label: "Pull  ↓" + (parent.parent.b ? parent.parent.b.behind : 0)
        ink: Zenon.cyan
        onClicked: pg.win.pull()
      }
      DialogButton {
        visible: !!parent.parent.b && !!parent.parent.b.oid && (parent.parent.b.ahead > 0 || !parent.parent.b.upstream) && pg.win.remotes.length > 0
        label: parent.parent.b && parent.parent.b.upstream ? "Push  ↑" + parent.parent.b.ahead : "Publish"
        ink: Zenon.cyan
        primary: true
        onClicked: pg.win.push()
      }
    }
  }
  // the edge the diff wears while it has the keys
  Rectangle {
    anchors.fill: diff
    visible: pg.area === "diff" && diff.visible
    color: "transparent"
    border.width: 1
    border.color: Zenon.alpha(Zenon.cyan, 0.35)
  }

  // ── a conflict, one at a time (ConflictView) ──────────────────────────
  ConflictView {
    id: conflictView
    anchors.fill: diff
    visible: !!pg.file && pg.file.area === "conflict" && (conflictView.readable || conflictView.loading)
    win: pg.win
    file: pg.file && pg.file.area === "conflict" ? pg.file : null
    onWholeFile: (side) => pg.resolve(side)
    onEditIt: pg.edit()
  }
  // ── or, one it cannot read (binary, or a side deleted it): the file
  // whole, either side's — what each side did, and the ways out
  Column {
    visible: !!pg.file && pg.file.area === "conflict" && !conflictView.readable && !conflictView.loading
    anchors.centerIn: diff
    width: Math.min(460, diff.width - 60)
    spacing: 14
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      text: ""
      color: Zenon.red
      font.family: Zenon.glyphFace
      font.pixelSize: Zenon.px(40)
    }
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.Wrap
      text: pg.file ? pg.file.name + " — " + pg.file.how : ""
      color: Zenon.ink
      font.family: Zenon.face
      font.weight: Font.Bold
      font.pixelSize: Zenon.px(18)
    }
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.Wrap
      text: "Take one side whole, or edit the file in plato — keep what you want between the <<<<<<< and >>>>>>> marks, delete the marks — then mark it resolved."
      color: Zenon.accentMuted
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(14)
    }
    Flow {
      anchors.horizontalCenter: parent.horizontalCenter
      width: Math.min(parent.width, implicitWidth)
      spacing: 8
      DialogButton { label: "Take ours"; onClicked: pg.resolve("ours") }
      DialogButton { label: "Take theirs"; onClicked: pg.resolve("theirs") }
      DialogButton { label: "Edit in plato"; ink: Zenon.cyan; onClicked: pg.edit() }
      DialogButton { label: "Mark resolved"; ink: Zenon.green; primary: true; onClicked: pg.resolve("done") }
    }
  }
  PopMenu {
    id: rowPop
    anchors.fill: parent
    window: pg.win
    cardWidth: 280
    onClosed: pg.takeFocus()
  }
  // the seam between the files and the diff: dragged, it stays
  SeamGrip {
    frame: pg
    at: left.width
    min: 260
    max: pg.width - 360
    onMoved: (p) => pg.win.setSplit("changes", p)
    onReset: pg.win.setSplit("changes", 0)
  }
}
