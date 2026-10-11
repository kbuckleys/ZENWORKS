// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ACCOUNTS — GitHub, GitLab and Codeberg, one at a time (the switch at the
// top; delphi.js FORGES): the account, and its repositories — clone one,
// open it on the web, publish the repository you have open, or upload files
// straight to one (a commit made there — no clone, no git here). Every
// request is the chosen forge's own (op: "github…", "gitlab…", "codeberg…";
// delphi/core github.py, gitlab.py, forgejo.py answer to the same names).
//
// SIGNING IN is a card on the window's sheet, like every other question:
// the browser where the forge's own command-line tool can do it — gh (its
// one-time code shown on the card, Open and Copy beside it), glab (a page it
// opens) — or a personal access token pasted in, kept in the keyring. Either
// way git's own pushes there use it too (delphi/core: gitrun.Creds).
// Codeberg has no such tool: a token.
//
//   ↑↓ repositories · return clone · u upload files · w open on the web
//   / filter · n new repository · [ ] the forge before / after

import QtQuick
import Quickshell
import "../morpheus"
import "../terminus"
import "delphi.js" as D
import "../terminus/terminus.js" as Terminus

Item {
  id: pg
  property var win: null
  // the views whose rows carry on up under the window's head, frosted
  // (DelphiWindow's ScrollEdges) — only those with nothing but controls
  // between them and the head: a view under a title would paint over it
  readonly property var edgeViews: [list]

  // the forge shown, and the words and requests that are its own
  readonly property string forge: pg.win && pg.win.mgr ? pg.win.mgr.forge : "github"
  readonly property var site: D.FORGES[pg.forge] || D.FORGES.github
  // from `forge` itself, never `site`: in onForgeChanged a binding made
  // from it may not have caught up (the reload asked the forge just left)
  function op(name) { return (D.FORGES[pg.forge] || D.FORGES.github).id + name; }
  function switchTo(id) {
    if (!D.FORGES[id] || id === pg.forge) return;
    pg.win.mgr.set("forge", id);
  }
  onForgeChanged: {
    if (!pg.win) return;      // being made: the first reload comes on its own
    pg.account = null; pg.repos = []; pg.listError = ""; pg.sel = 0; filter.text = ""; pg.reload();
  }

  property var account: null      // the forge's Status
  // signed in before through the forge's tool, which is gone now: whom its
  // record still names (the window's tools) — a reinstall brings it back
  readonly property string was: pg.win && pg.win.tools && pg.site.cli && !pg.win.tools[pg.site.cli]
    ? (pg.win.tools[pg.site.cli + "User"] || "") : ""
  property bool checking: true
  readonly property bool signedIn: !!pg.account && pg.account.signedIn

  readonly property string title: pg.site.name
  readonly property string subtitle: pg.checking ? "Asking " + pg.site.name + "…"
    : pg.signedIn ? "Signed in as " + pg.account.login + (pg.account.source === pg.site.cli && pg.site.cli ? " through " + pg.site.cli : " with a token")
    : "Not signed in"
  readonly property var hints: pg.signedIn
    ? [["return", "open"], ["c", "clone"], ["u", "upload files"], ["w", "web"], ["n", "new"], ["/", "filter"], ["[ ]", "forge"]]
    : [["return", "sign in"], ["[ ]", "forge"]]
  readonly property var buttons: pg.signedIn ? [
    { label: "Sign out", run: () => pg.signOut() },
    { label: "Upload files", visible: !!pg.repo, run: () => pg.upload(pg.repo) },
    { label: pg.win && pg.win.root !== "" && !pg.win.origin ? "Publish " + pg.win.repoName : "New repository",
      ink: Zenon.cyan, primary: true, run: () => pg.create() },
  ] : pg.was !== "" ? [
    { label: "Sign in another way", run: () => pg.signIn() },
    { label: "Install " + pg.site.pkg, ink: Zenon.cyan, primary: true, ready: !pg.checking && !pg.win.mgr.installing, run: () => pg.installThenSignIn() },
  ] : [{ label: "Sign in", ink: Zenon.cyan, primary: true, ready: !pg.checking, run: () => pg.signIn() }]
  function takeFocus() { if (!filter.focused && pg.win) pg.win.focusKeys(); }

  // An answer is for the forge it was asked of: one that comes after the
  // switch has moved on is dropped — GitHub's account once landed under
  // GitLab's name this way (2026-10-11).
  function reload() {
    pg.checking = true;
    const asked = pg.forge;
    pg.win.mgr.call(pg.op("Status"), null, {}, (ok, st) => { if (!pg || asked !== pg.forge) return;
      pg.checking = false;
      pg.account = ok ? st : null;
      if (pg.signedIn) { pg.loadRepos(); pg.loadAccounts(); }
    });
  }
  Component.onCompleted: Qt.callLater(pg.reload)

  // ── accounts ───────────────────────────────────────────────────────────
  // Every account delphi can see on this forge (gh keeps several, one
  // active; glab and a keyring token one) — the account menu's rows.
  property var accountList: []
  property bool many: false
  function loadAccounts() {
    const asked = pg.forge;
    pg.win.mgr.call(pg.op("Accounts"), null, {}, (ok, a) => {
      if (!pg || asked !== pg.forge || !ok) return;
      pg.accountList = a.accounts;
      pg.many = a.many;
    });
  }
  // the menu on the account's name: switch to another, add one (where the
  // forge's tool keeps several), sign out
  function accountMenu() {
    const me = pg.account ? pg.account.login : "";
    const items = pg.accountList.map((a) => ({
      text: a.login + (a.source === "keyring" ? "  (token)" : ""), icon: a.active ? "\uF00C" : "\uF007",
      enabled: !a.active && pg.many, run: () => pg.switchAccount(a.login) }));
    if (pg.many) items.push({ text: "Add another account…", icon: "\uF067", run: () => pg.signIn(true) });
    items.push({ isSeparator: true },
               { text: "Sign out of " + me, icon: "\uF08B", danger: true, run: () => pg.signOut() });
    const p = accountChip.mapToItem(pg, 0, accountChip.height + 4);
    menu.open(p.x, p.y, items);
  }
  function switchAccount(login) {
    pg.win.act(pg.op("Switch"), { login: login }, { repo: null, refresh: false, network: true,
      label: "Switching to " + login,
      then: (st) => { if (!pg) return; pg.account = st; pg.repos = []; pg.loadRepos(); pg.loadAccounts();
                      pg.win.say("Now " + login + " on " + pg.site.name); } });
  }

  // ── signing in ─────────────────────────────────────────────────────────
  // `another`: an account added beside the one signed in (gh keeps both)
  function signIn(another) {
    // the browser, where the forge's own tool signs in (gh, glab), else a
    // token; the tool not installed, it is offered — Ceres installs it
    const has = !!pg.account && !!pg.account.cli;
    const cli = has && pg.site.cli !== "";
    const missing = !has && pg.site.cli !== "";
    const choices = [];
    if (cli) choices.push({ label: "Use the browser", ink: Zenon.cyan, run: () => pg.browser() });
    if (missing) choices.push({ label: "Install " + pg.site.pkg + ", then sign in", ink: Zenon.cyan, run: () => pg.installThenSignIn() });
    choices.push({ label: "Paste a token", ink: cli || missing ? Zenon.muted : Zenon.cyan, run: () => pg.token() });
    choices.push({ label: "Cancel", ink: Zenon.muted });
    pg.win.card_({ question: another ? "Another account on " + pg.site.name : "Sign in to " + pg.site.name, glyph: pg.site.glyph, ink: Zenon.ink,
      detail: cli ? "In your browser, through " + pg.site.cli + " — or with a personal access token you made."
          + (another ? " It is added beside " + pg.account.login + " and becomes the one in use; switch back from the account menu." : "")
        : missing ? "Signing in with the browser goes through " + pg.site.cli + ", which is not installed. Delphi can have Ceres install it ("
          + pg.site.pkg + " — Ceres asks for your password), or paste a personal access token (" + pg.site.tokens + ")."
        : "With a personal access token (" + pg.site.tokens + ").",
      choices: choices });
  }
  // the forge's tool, through Ceres, then the browser sign-in it gives —
  // once Ceres says it is in, and the daemon finds it
  function installThenSignIn() {
    const asked = pg.forge;
    pg.win.mgr.installTool(pg.site.pkg, "for signing in to " + pg.site.name, (ok) => {
      if (!pg || !ok || asked !== pg.forge) return;
      pg.win.mgr.call(pg.op("Status"), null, {}, (ok2, st) => {
        if (!pg || asked !== pg.forge || !ok2) return;
        pg.account = st;
        // its record kept the sign-in: back as it was, nothing to ask
        if (st.signedIn) { pg.win.say("Signed in again as " + st.login); pg.loadRepos(); pg.loadAccounts(); return; }
        if (st.cli) pg.browser();
      });
    });
  }
  function browser() {
    let codeCard = -1, job = -1;
    job = pg.win.act(pg.op("Login"), {}, {
      repo: null, label: "Signing in to " + pg.site.name, network: true, refresh: false,
      event: (ev) => { if (!pg) return;
        if (!ev.device || codeCard >= 0) return;
        const d = ev.device;
        // gh hands a one-time code to type; glab only a page to open
        codeCard = pg.win.card_(d.code ? { question: "Your code:  " + d.code, glyph: pg.site.glyph, ink: Zenon.cyan,
            detail: "Enter it at " + d.url.replace(/^https:\/\//, "") + " — this card goes by itself once " + pg.site.name + " says yes.",
            choices: [{ label: "Open " + pg.site.name, ink: Zenon.cyan, keep: true, run: () => Quickshell.execDetached(["xdg-open", d.url]) },
                      { label: "Copy the code", keep: true, run: () => pg.win.copy(d.code, "the code") },
                      { label: "Cancel", ink: Zenon.muted, run: () => pg.win.stop(job) }] }
          : { question: "Finish in your browser", glyph: pg.site.glyph, ink: Zenon.cyan,
            detail: pg.site.name + " asks there whether " + pg.site.cli + " may act for you. This card goes by itself once it says yes.",
            choices: [{ label: "Open the page again", ink: Zenon.cyan, keep: true, run: () => Quickshell.execDetached(["xdg-open", d.url]) },
                      { label: "Cancel", ink: Zenon.muted, run: () => pg.win.stop(job) }] });
      },
      done: () => { if (codeCard >= 0) pg.win.dropCard(codeCard); },
      then: (st) => { pg.account = st; pg.win.say("Signed in as " + st.login); pg.loadRepos(); },
    });
  }
  function token() {
    pg.win.ask({ title: "A personal access token", glyph: "",
      detail: "Made at " + pg.site.tokens + ", with access to your repositories. Kept in your keyring; git uses it for " + pg.site.host + " too.",
      secret: { key: "token", prompt: "paste your token", purpose: "ctrl v pastes it" },
      verb: "Sign in",
      then: (v) => pg.win.act(pg.op("SetToken"), { token: v.token.trim() }, { repo: null, refresh: false,
        label: "Checking the token with " + pg.site.name, network: true,
        // said where it was kept: delphi's own file, when there is no keyring
        then: (r) => { pg.win.say("Signed in as " + r.login + (r.where === "file" ? " — kept in Delphi's own file (no keyring running)" : "")); pg.reload(); } }) });
  }
  function signOut() {
    const src = pg.account ? pg.account.source : "";
    const viaCli = !!pg.site.cli && src === pg.site.cli;
    pg.win.confirm({ question: "Sign out of " + pg.site.name + "?", glyph: pg.site.glyph,
      detail: viaCli ? pg.site.cli + " forgets this account (" + pg.site.cli + " auth logout)." : "The token leaves your keyring.",
      verb: "Sign out", then: () => pg.win.act(viaCli ? pg.op("Logout") : pg.op("ForgetToken"), {}, {
        repo: null, refresh: false, then: () => { pg.repos = []; pg.reload(); } }) });
  }

  // ── the repositories ───────────────────────────────────────────────────
  property var repos: []
  property bool loadingRepos: false
  // why the last listing failed — said on the page with Retry, not as a card
  // to dismiss: the page is the answer to "what are my repositories"
  property string listError: ""
  property string query: ""
  readonly property var shown: pg.repos.filter((r) => pg.query === ""
    || (r.full + " " + r.description).toLowerCase().indexOf(pg.query.toLowerCase()) >= 0)
  property int sel: 0
  readonly property var repo: pg.sel >= 0 && pg.sel < pg.shown.length ? pg.shown[pg.sel] : null
  function loadRepos() {
    pg.loadingRepos = true;
    pg.listError = "";
    const asked = pg.forge;
    pg.win.mgr.call(pg.op("Repos"), null, {}, (ok, rs, err) => { if (!pg || asked !== pg.forge) return;
      pg.loadingRepos = false;
      if (ok) { pg.repos = rs; Qt.callLater(pg.publishWanted); }
      else pg.listError = D.errorText(err ? err.error : "");
    });
  }
  function moveTo(i) {
    if (pg.shown.length === 0) return;
    pg.sel = Math.max(0, Math.min(pg.shown.length - 1, i));
    list.positionViewAtIndex(pg.sel, ListView.Contain);
  }

  // Clone: where to (terminus' own directory picker), then the clone, its
  // progress in the head, and the window turned to it
  function clone(r) {
    if (!r || !pg.win.mgr.fileManager) return;
    pg.win.mgr.fileManager.choose(true, pg.win.home, (paths) => {
      if (!paths || paths.length === 0) return;
      const dest = paths[0].replace(/\/$/, "") + "/" + r.name;
      pg.win.act("clone", { url: r.https, dest: dest }, { repo: null, label: "Cloning " + r.name, network: true, refresh: false,
        said: "Cloned " + r.full, then: () => pg.win.openRepo(dest) });
    });
  }
  // OPEN one: the clone of it here when there is one (among the repositories
  // opened before — delphi/core whereCloned), else what can be done with it
  // — the double click went straight to cloning's directory picker, which
  // was not what a click on a repository meant (user, 2026-10-11)
  function openOne(r) {
    if (!r) return;
    const roots = pg.win.mgr.recents.map((x) => x.root);
    pg.win.mgr.call("whereCloned", null, { host: pg.site.host, full: r.full, roots: roots }, (ok, res) => {
      if (!pg) return;
      if (ok && res.root) { pg.win.openRepo(res.root); pg.win.setPage("changes"); return; }
      pg.win.card_({ question: r.full, glyph: pg.site.glyph, ink: Zenon.ink,
        detail: (r.description ? r.description + "  ·  " : "") + "Not cloned here yet.",
        choices: [{ label: "Clone…", ink: Zenon.cyan, run: () => pg.clone(r) },
                  { label: "Upload files…", run: () => pg.upload(r) },
                  { label: "Open on the web", run: () => pg.web(r) },
                  { label: "Cancel" }] });
    });
  }
  function web(r) { if (r) Quickshell.execDetached(["xdg-open", "https://" + pg.site.host + "/" + r.full]); }

  // Upload: files and directories chosen in terminus (many at once; a
  // directory brings everything under it, under its own name), where they
  // go in the repository, and what the commit says — one commit on GitHub,
  // no clone
  function upload(r) {
    if (!r || !pg.win.mgr.fileManager) return;
    pg.win.mgr.fileManager.choose(false, pg.win.home, (paths) => {
      if (!paths || paths.length === 0) return;
      // its branches first, for the dropdown (the default one on top); a
      // new one can be typed, and is made from the default branch
      // as a job in the head (its pill, Esc stops it): a stalled request
      // takes seconds, and a toast that fades said nothing was happening
      pg.win.act(pg.op("Branches"), { full: r.full }, { repo: null, label: "Asking " + r.name + " for its branches",
        network: true, refresh: false,
        then: (b) => { if (pg) pg.askUpload(r, paths, b.branches.length > 0 ? b.branches : [r.branch || "main"]); },
        failed: () => { if (pg) pg.askUpload(r, paths, [r.branch || "main"]); } });
    }, undefined, true, true);
  }
  // the form: where in the repository, the message, the branch (a new one
  // may be typed). `prev` refills it, coming Back from the breakdown.
  function askUpload(r, paths, branches, prev) {
    const names = paths.map((p) => D.baseName(p));
    const was = prev || {};
    pg.win.ask({ title: "Upload " + (paths.length === 1 ? names[0] : paths.length + " items") + " to " + r.full, glyph: "\uF093",
      fields: [{ key: "dir", label: "Into the directory", hint: "the top of the repository", optional: true, value: was.dir || "" },
               { key: "msg", label: "Commit message", value: was.msg || (paths.length === 1 ? "Add " + names[0] : "Add " + names.slice(0, 3).join(", ") + (paths.length > 3 ? " and " + (paths.length - 3) + " more" : "")) },
               { key: "branch", label: "Branch", options: branches,
                 value: was.branch && branches.indexOf(was.branch) >= 0 ? was.branch : branches[0],
                 other: "New branch\u2026", otherHint: "a name for the new branch" }],
      verb: "Review",
      then: (v) => pg.review(r, paths, branches, v) });
  }
  // the breakdown: every file, where it lands, how big, and whether one is
  // already there — asked of GitHub before anything is sent
  // v.contents: the one directory chosen is the repository's top — its
  // files land there, not under its name (a new repository filled from it)
  function review(r, paths, branches, v) {
    const dir = String(v.dir || "").trim().replace(/^\/+|\/+$/g, "");
    const files = v.contents ? [{ local: paths[0], path: dir }]
      : paths.map((p) => ({ local: p, path: (dir ? dir + "/" : "") + D.baseName(p) }));
    const branch = String(v.branch || "").trim() || branches[0];
    const message = String(v.msg || "").trim();
    pg.win.act(pg.op("Plan"), { full: r.full, files: files, branch: branch }, { repo: null, label: "Looking at " + r.name,
      network: true, refresh: false,
      failed: (err) => pg.win.fail("Could not look at " + r.full, null, err),
      then: (plan) => { if (!pg) return;
      const total = plan.files.reduce((n, f) => n + Math.max(0, f.size), 0);
      const replacing = plan.files.filter((f) => f.exists).length;
      if (plan.files.length === 0) { pg.win.say("Nothing to upload — those directories hold no files", true); return; }
      const entries = plan.files.map((f) => ({ name: D.baseName(f.path), path: f.path, size: f.size, exists: f.exists }));
      // what the plan found is what goes: the directories already opened
      // into their files, so the upload and its bubble name the same ones
      const sending = plan.files.map((f) => ({ local: f.local, path: f.path }));
      const n = sending.length;
      pg.win.card_({
        question: "Upload " + n + (n === 1 ? " file" : " files") + " to " + r.full + "?",
        glyph: "\uF093", ink: Zenon.cyan,
        detail: Terminus.formatSize(total) + "  \u00b7  "
          + (plan.fresh ? "onto a new branch " + plan.branch + ", made from " + plan["from"] : "onto " + plan.branch)
          + (replacing > 0 ? "  \u00b7  replaces " + replacing : "")
          + (plan.skipped > 0 ? "  \u00b7  leaves out " + plan.skipped + " (caches, and what git ignores)" : "")
          + "  \u00b7  \u201c" + D.subjectOf(message) + "\u201d",
        rows: entries,
        treeRoot: r.name,
        choices: [{ label: "Upload", ink: Zenon.cyan,
                    run: () => pg.win.mgr.startUpload({ full: r.full, branch: plan.branch, fresh: plan.fresh, entries: entries, forge: pg.forge }, sending, message) },
                  { label: "Back", run: () => pg.askUpload(r, paths, branches, v) },
                  { label: "Cancel" }] });
    } });
  }

  // New: a repository on GitHub — empty, or filled from a directory chosen
  // in terminus (a repository's history pushed, plain files uploaded); with
  // one open here that has nowhere to push, that one published to it
  function create() {
    const local = pg.win.root !== "" && !pg.win.origin;
    if (local) {
      pg.win.card_({ question: "Publish " + pg.win.repoName + " to " + pg.site.name, glyph: "", ink: Zenon.ink,
        detail: "To a repository you already have there — its history is taken in, and only what differs is left to commit — or as a new one.",
        choices: [{ label: "To an existing one…", ink: Zenon.cyan, run: () => pg.connectExisting(null) },
                  { label: "As a new repository", run: () => pg.askCreate({ dir: pg.win.root, repo: true, open: true }) },
                  { label: "Cancel" }] });
      return;
    }
    pg.win.card_({ question: "A new repository on " + pg.site.name, glyph: "", ink: Zenon.ink,
      detail: "Empty, or filled from a directory: a git repository's history is pushed; a plain directory's files are uploaded.",
      choices: [{ label: "From a directory…", ink: Zenon.cyan, run: () => pg.createFrom() },
                { label: "Empty", run: () => pg.askCreate(null) },
                { label: "Cancel" }] });
  }
  // the directory, in terminus' picker, and what it is: a repository's
  // own top, or files (a directory inside some repository is files too)
  function createFrom() {
    if (!pg.win.mgr.fileManager) return;
    pg.win.mgr.fileManager.choose(true, pg.win.home, (paths) => {
      if (!paths || paths.length === 0) return;
      const dir = paths[0].replace(/\/+$/, "");
      pg.win.mgr.call("discover", null, { path: dir }, (ok, info) => {
        if (!pg) return;
        pg.askCreate({ dir: dir, repo: !!ok && !!info && !info.bare && info.root === dir });
      });
    });
  }
  // from: null (empty), or { dir, repo, open } — `open`: the repository is
  // the one this window has open
  function askCreate(from) {
    const name = from ? D.baseName(from.dir).replace(/[^A-Za-z0-9._-]+/g, "-") : "";
    pg.win.ask({ title: !from ? "A new repository on " + pg.site.name : from.open ? "Publish " + name + " to " + pg.site.name : "A repository from " + D.baseName(from.dir),
      glyph: "",
      detail: !from ? "" : from.repo ? "Its history is pushed there: " + D.tilde(from.dir, pg.win.home)
        : "Its files are uploaded there, at the top — a commit made on " + pg.site.name + "; nothing is written into " + D.tilde(from.dir, pg.win.home) + ".",
      fields: [{ key: "name", label: "Name", value: name },
               { key: "desc", label: "Description", hint: "optional", optional: true }],
      toggles: [{ key: "priv", label: "Private", value: true }],
      verb: !from ? "Create" : from.repo ? "Publish" : "Create and review",
      then: (v) => pg.win.act(pg.op("Create"), { name: v.name.trim(), private: !!v.priv, description: v.desc.trim() }, {
        repo: null, label: "Creating " + v.name.trim(), network: true, refresh: false,
        // the name is taken — by one of yours, most likely the very one
        // meant: connecting to it is offered rather than a dead end
        failed: (err) => {
          const taken = /already exists/i.test(String(err && err.error || ""));
          const mine = taken ? pg.repos.find((x) => x.name.toLowerCase() === v.name.trim().toLowerCase()) : null;
          if (mine && from && from.repo) pg.win.card_({ question: "You already have " + mine.full, glyph: "", ink: Zenon.yellow,
            detail: "Connect " + D.baseName(from.dir) + " to it instead? Its history is taken in and only what differs is left to commit — nothing there is replaced.",
            choices: [{ label: "Connect to it", ink: Zenon.cyan, run: () => pg.connectExisting(mine, from.dir) },
                      { label: "Cancel" }] });
          else pg.win.fail("Could not create " + v.name.trim(), taken ? "A repository by that name is already on your account." : null, err);
        },
        then: (r) => {
          pg.loadRepos();
          if (!from) { pg.win.say("Created " + r.full); return; }
          if (from.repo) pg.publish(from.dir, r);
          // the breakdown first, as any upload: every file, new, then the ring
          else pg.review({ full: r.full, name: v.name.trim(), branch: r.branch }, [from.dir], [r.branch],
                         { contents: true, dir: "", msg: "Initial commit", branch: r.branch });
        } }) });
  }
  // the head's Publish, pressed with nowhere to push: asked here once
  // signed in and the repositories are known (connecting needs them)
  function publishWanted() {
    if (!pg || !pg.win || !pg.win.wantPublish || !pg.signedIn || pg.loadingRepos || pg.repos.length === 0) return;
    pg.win.wantPublish = false;
    pg.create();
  }

  // CONNECT: the repository here joined to one already on GitHub (made by
  // hand uploads, say). Chosen from yours — the one of the same name
  // first — then said exactly what happens before it does (delphi/core
  // repo.connect): history fetched, a branch with no commits put on it
  // with every file left as it is, so Changes shows only what differs.
  function connectExisting(r, dir) {
    const here = dir || pg.win.root;
    if (here === "" || pg.repos.length === 0) { pg.win.say("No repositories on " + pg.site.name + " to connect to", true); return; }
    if (r) { pg.confirmConnect(r, here); return; }
    const name = D.baseName(here).toLowerCase();
    const sorted = pg.repos.slice().sort((a, b) => (b.name.toLowerCase() === name) - (a.name.toLowerCase() === name));
    pg.win.ask({ title: "Connect " + D.baseName(here) + " to " + pg.site.name, glyph: "",
      detail: "Which of your repositories it is a copy of.",
      fields: [{ key: "full", label: "Repository", options: sorted.map((x) => x.full) }],
      verb: "Next",
      then: (v) => { const pick = pg.repos.find((x) => x.full === v.full); if (pick) pg.confirmConnect(pick, here); } });
  }
  function confirmConnect(r, here, onto) {
    // `onto`: the second asking, for a branch with commits of its own — the
    // card says what that does differently
    if (onto) {
      pg.win.act("connect", { url: r.https, branch: r.branch || null, onto: true }, { repo: here,
        label: "Putting " + D.baseName(here) + " on " + r.full, network: true,
        then: (res) => {
          pg.win.say("On " + r.full + "'s history — yours is kept on " + res.backup + "; Changes shows what differs");
          pg.win.openRepo(here);
          pg.win.setPage("changes");
        } });
      return;
    }
    pg.win.confirm({ question: "Connect " + D.baseName(here) + " to " + r.full + "?", glyph: "", ink: Zenon.cyan,
      detail: "Its history is downloaded and your branch is put on it. Your files stay exactly as they are; Changes then shows only what differs from " + r.full
        + ", to commit and push on top. Nothing on " + pg.site.name + " is replaced.",
      items: [D.tilde(here, pg.win.home) + "  →  " + r.full + " (" + (r.branch || "main") + ")"],
      verb: "Connect",
      then: () => pg.win.act("connect", { url: r.https, branch: r.branch || null, onto: !!onto }, { repo: here,
        label: "Connecting to " + r.full, network: true,
        then: (res) => {
          if (res.adopted && res.backup) pg.win.say("On " + r.full + "'s history — yours is kept on " + res.backup + "; Changes shows what differs");
          else if (res.adopted) pg.win.say("Connected — on " + r.full + "'s history; Changes shows what differs");
          else if (res.empty) pg.win.say("Connected — " + r.full + " is empty: commit, then Push");
          else if (res.unrelated) pg.win.card_({ question: "Not joined to " + r.full, glyph: "", ink: Zenon.yellow,
            detail: "This repository has commits of its own that share nothing with " + r.full + "'s. Its remote is set; nothing else changed. "
              + "Delphi can put your branch on top of theirs: your commits are kept on a backup branch, your files stay exactly as they are, and Changes shows what differs from "
              + r.full + " — commit that and push. A file " + r.full + " has and this folder does not shows as deleted: leave it unstaged to keep it there.",
            choices: [{ label: "Put mine on top of theirs", ink: Zenon.cyan, run: () => pg.confirmConnect(r, here, true) },
                      { label: "Leave it" }] });
          else pg.win.say("Connected — " + (res.tracking ? "tracking " + res.remote + "/" + res.branch : "remote added"));
          pg.win.openRepo(here);
          if (res.adopted) pg.win.setPage("changes");
        } }) });
  }

  // a repository on disk pushed to a new one: origin (or, if it has an
  // origin already, a remote called github), its branch published there,
  // and the window turned to it
  function publish(dir, r) {
    pg.win.mgr.call("remotes", dir, {}, (ok, rs) => {
      if (!pg) return;
      const name = ok && rs.some((x) => x.name === "origin") ? pg.forge : "origin";
      pg.win.act("remoteAdd", { name: name, url: r.https }, { repo: dir, refresh: false, then: () => {
        pg.win.mgr.call("status", dir, {}, (ok2, st) => {
          if (!pg) return;
          const b = ok2 && st.branch ? st.branch.head : "";
          if (!b) { pg.win.say("Created " + r.full + " — commit something, then Publish"); pg.win.openRepo(dir); return; }
          pg.win.act("push", { remote: name, branch: b, setUpstream: true }, { repo: dir, label: "Publishing " + b, network: true,
            said: "Published to " + r.full, then: () => pg.win.openRepo(dir) });
        });
      } });
    });
  }

  function key(e) {
    const k = e.key;
    if (e.modifiers & Qt.ControlModifier) return false;
    // the forge before / after
    if (k === Qt.Key_BracketLeft || k === Qt.Key_BracketRight) {
      const i = D.FORGE_ORDER.indexOf(pg.forge), n = D.FORGE_ORDER.length;
      pg.switchTo(D.FORGE_ORDER[(i + (k === Qt.Key_BracketRight ? 1 : n - 1)) % n]);
      return true;
    }
    if (!pg.signedIn) {
      if (k === Qt.Key_Return || k === Qt.Key_Enter) { pg.signIn(); return true; }
      return false;
    }
    if (k === Qt.Key_Slash) { filter.claim(); return true; }
    if (k === Qt.Key_N) { pg.create(); return true; }
    if (k === Qt.Key_Up || k === Qt.Key_K) { pg.moveTo(pg.sel - 1); return true; }
    if (k === Qt.Key_Down || k === Qt.Key_J) { pg.moveTo(pg.sel + 1); return true; }
    if (k === Qt.Key_PageUp) { pg.moveTo(pg.sel - 12); return true; }
    if (k === Qt.Key_PageDown) { pg.moveTo(pg.sel + 12); return true; }
    if (!pg.repo) return false;
    if (k === Qt.Key_Return || k === Qt.Key_Enter) { pg.openOne(pg.repo); return true; }
    if (k === Qt.Key_C) { pg.clone(pg.repo); return true; }
    if (k === Qt.Key_U) { pg.upload(pg.repo); return true; }
    if (k === Qt.Key_W) { pg.web(pg.repo); return true; }
    if (k === Qt.Key_Escape && pg.query !== "") { filter.text = ""; return true; }
    return false;
  }

  // ── not signed in ──────────────────────────────────────────────────────
  Column {
    visible: !pg.signedIn
    anchors.centerIn: parent
    width: Math.min(420, parent.width - 60)
    spacing: 14
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: pg.site.glyph
      color: Zenon.muted
      opacity: 0.5
      font.family: Zenon.glyphFace
      font.pixelSize: Zenon.px(64)
    }
    Working { anchors.horizontalCenter: parent.horizontalCenter; running: pg.checking }
    Text {
      visible: !pg.checking
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.Wrap
      text: pg.was !== "" ? "You were signed in to " + pg.site.name + " as " + pg.was + " through " + pg.site.cli
          + ", which is no longer installed. Install it (" + pg.site.pkg + ", through Ceres) to pick that sign-in up again — or sign in another way."
        : pg.account && pg.account.error ? pg.site.name + " did not take the saved sign-in: " + pg.account.error
        : "Sign in to clone your repositories, publish new ones and upload files."
          + (pg.site.cli && pg.account && !pg.account.cli
             ? "\n\n" + pg.site.cli + " is not installed: signing in with the browser needs it, and Delphi has Ceres install it when you choose that." : "")
      color: Zenon.muted
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(15)
    }
    DialogButton {
      visible: !pg.checking
      anchors.horizontalCenter: parent.horizontalCenter
      label: pg.was !== "" ? "Install " + pg.site.pkg : "Sign in"
      ink: Zenon.cyan
      primary: true
      onClicked: pg.was !== "" ? pg.installThenSignIn() : pg.signIn()
    }
  }

  // ── signed in ──────────────────────────────────────────────────────────
  // which forge: one at a time, the choice kept (DelphiManager.forge)
  Segments {
    id: forgeSwitch
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.margins: 12
    z: 2
    options: D.FORGE_ORDER.map((id) => [id, D.FORGES[id].name])
    current: pg.forge
    onChose: (v) => pg.switchTo(v)
  }
  // the account: its name, a menu on it (switch, add, sign out)
  Rectangle {
    id: accountChip
    visible: pg.signedIn
    anchors.right: parent.right
    anchors.rightMargin: 12
    anchors.verticalCenter: forgeSwitch.verticalCenter
    width: chipRow.implicitWidth + 24
    height: 28
    radius: Zenon.windowRadius
    color: Zenon.wash(0.04)
    border.width: 1
    border.color: Zenon.border
    Row {
      id: chipRow
      anchors.centerIn: parent
      spacing: 8
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: pg.site.glyph
        color: Zenon.ink
        font.family: Zenon.glyphFace
        font.pixelSize: Zenon.px(14)
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: pg.account && pg.account.login ? pg.account.login + (pg.accountList.length > 1 ? "  ·  " + pg.accountList.length + " accounts" : "") : ""
        color: Zenon.ink
        font.family: Zenon.face
        font.weight: Font.Bold
        font.pixelSize: Zenon.px(14)
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "\uF078"
        color: Zenon.muted
        font.family: Zenon.glyphFace
        font.pixelSize: Zenon.px(10)
      }
    }
    MouseArea { anchors.fill: parent; onClicked: pg.accountMenu() }
  }
  BulkField {
    id: filter
    visible: pg.signedIn
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: forgeSwitch.bottom
    anchors.margins: 12
    height: 32
    textSize: Zenon.px(15)
    ghost: "  Filter " + pg.repos.length + " repositories  ( / )"
    onTextChanged: { pg.query = filter.text.trim(); pg.sel = 0; }
    onAccepted: pg.win.focusKeys()
    Keys.onEscapePressed: { filter.text = ""; pg.win.focusKeys(); }
    Keys.onDownPressed: pg.win.focusKeys()
  }
  ListView {
    id: list
    visible: pg.signedIn
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: filter.bottom
    anchors.topMargin: 8
    anchors.bottom: parent.bottom
    clip: true
    bottomMargin: 8
    boundsBehavior: Flickable.StopAtBounds
    model: pg.shown
    readonly property int rowH: Math.round(Zenon.px(15) * 3.4)
    SelectBar { view: list; host: pg.win; index: pg.sel; rowH: list.rowH; color: pg.win.hiFill; radius: Zenon.windowRadius; inset: 8 }
    delegate: Item {
      id: rrow
      required property var modelData
      required property int index
      readonly property var r: rrow.modelData
      width: list.width
      height: list.rowH
      Text {
        id: rg
        x: 24
        anchors.verticalCenter: parent.verticalCenter
        text: rrow.r.private ? "" : rrow.r.fork ? "" : ""
        color: rrow.r.private ? Zenon.yellow : Zenon.muted
        font.family: Zenon.glyphFace
        font.pixelSize: Zenon.px(17)
      }
      Column {
        anchors.left: rg.right
        anchors.leftMargin: 14
        anchors.right: rwhen.left
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3
        Text {
          width: parent.width
          elide: Text.ElideRight
          text: rrow.r.full + (rrow.r.archived ? "   ·   archived" : "") + (rrow.r.empty ? "   ·   empty" : "")
          color: rrow.index === pg.sel ? Zenon.ink : Zenon.soft
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(16)
        }
        Text {
          visible: text !== ""
          width: parent.width
          elide: Text.ElideRight
          text: rrow.r.description
          color: Zenon.muted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(13)
        }
      }
      Text {
        id: rwhen
        anchors.right: parent.right
        anchors.rightMargin: 24
        anchors.verticalCenter: parent.verticalCenter
        text: rrow.r.pushed ? D.ago(Date.parse(rrow.r.pushed) / 1000, Date.now()) : ""
        color: Zenon.muted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.features: { "tnum": 1 }
        font.pixelSize: Zenon.px(13)
      }
      HeldRing { anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8; on: menu.isOpen && menu.held === rrow.index }
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (m) => {
          pg.sel = rrow.index;
          if (m.button === Qt.RightButton) {
            const p = mapToItem(pg, m.x, m.y);
            menu.open(p.x, p.y, [
              { text: "Open", icon: "", mark: "return", run: () => pg.openOne(rrow.r) },
              { text: "Clone…", icon: "", mark: "c", run: () => pg.clone(rrow.r) },
              { text: "Upload files…", icon: "", mark: "u", run: () => pg.upload(rrow.r) },
              { text: "Open on the web", icon: "", mark: "w", run: () => pg.web(rrow.r) },
              { isSeparator: true },
              { text: "Copy the HTTPS address", icon: "", run: () => pg.win.copy(rrow.r.https) },
              { text: "Copy the SSH address", icon: "", run: () => pg.win.copy(rrow.r.ssh) },
            ], rrow.index);
            return;
          }
          pg.win.focusKeys();
        }
        onDoubleClicked: pg.openOne(rrow.r)
      }
    }
    footer: Item { width: list.width; height: pg.loadingRepos ? 50 : 0; Working { anchors.centerIn: parent; running: pg.loadingRepos } }
    EmptyMark {
      anchors.centerIn: parent
      visible: pg.shown.length === 0 && !pg.loadingRepos && pg.listError === ""
      filtered: pg.query !== ""
      word: pg.query !== "" ? "" : "No repositories yet"
    }
    Column {
      anchors.centerIn: parent
      visible: pg.listError !== "" && !pg.loadingRepos
      width: Math.min(420, list.width - 60)
      spacing: 14
      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: "Could not list your repositories — " + pg.listError
        color: Zenon.muted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(15)
      }
      DialogButton {
        anchors.horizontalCenter: parent.horizontalCenter
        label: "Retry"
        ink: Zenon.cyan
        primary: true
        onClicked: pg.loadRepos()
      }
    }
  }
  ElasticScroll { anchors.fill: list; view: list; visible: pg.signedIn }
  Scrollbar { flick: list; visible: pg.signedIn; anchors.right: list.right; anchors.top: list.top; anchors.bottom: list.bottom }

  PopMenu {
    id: menu
    anchors.fill: parent
    window: pg.win
    cardWidth: 260
    onClosed: pg.win.focusKeys()
  }
}
