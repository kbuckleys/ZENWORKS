// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ACCOUNTS — every forge at once: GitHub, GitLab, Codeberg and servers of
// your own (delphi.js FORGES). One list of every repository on every
// account signed in, newest push first, each told apart by its forge's
// glyph, its name and its kind (user, 2026-10-17: the forge tabs went).
// Clone one, open it on the web, publish the repository you have open, or
// upload files straight to one (a commit made there — no clone, no git
// here). Every request is its forge's own (op: "github…", "gitlab…",
// "codeberg…"; delphi/core github.py, gitlab.py, forgejo.py answer to the
// same names).
//
// THE ACCOUNTS are chips above the list, one per forge signed in to (or
// once signed in to, its tool since uninstalled): each a menu — switch,
// add another, sign out. "Add account" beside them signs in to another.
//
// SIGNING IN is a card on the window's sheet, like every other question:
// the browser where the forge's own command-line tool can do it — gh (its
// one-time code shown on the card, Open and Copy beside it), glab (a page it
// opens) — or a personal access token pasted in, kept in the keyring. Either
// way git's own pushes there use it too (delphi/core: gitrun.Creds).
// Codeberg has no such tool: a token.
//
// A REPOSITORY ON MORE THAN ONE FORGE (user, 2026-10-17): one of the same
// name as a repository here says so on its row, and opening it offers to
// add it there as a remote and keep both in sync (DelphiWindow.joinForge)
// rather than a second clone.
//
//   ↑↓ repositories · return open · c clone · u upload files · w web
//   / filter · n new repository · a archive

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

  // ── THE FORGES ─────────────────────────────────────────────────────────
  // the three, then your own servers (read for the dependency: setServers
  // lays them into FORGE_ORDER, a plain array)
  readonly property var forges: { pg.win && pg.win.mgr ? pg.win.mgr.servers : null; return D.FORGE_ORDER.slice(); }
  function siteOf(id) { return D.FORGES[id] || D.FORGES.github; }
  function op(id, name) { return pg.siteOf(id).id + name; }
  // what is known of each, by id: { account (its Status), checking,
  // accounts, many, repos, loading, error }
  property var st: ({})
  function put(id, patch) {
    const o = Object.assign({}, pg.st);
    o[id] = Object.assign({}, o[id] || {}, patch);
    pg.st = o;
  }
  function stOf(id) { return pg.st[id] || {}; }
  function signedInTo(id) { const a = pg.stOf(id).account; return !!a && a.signedIn; }
  // an answer for a server removed meanwhile is dropped
  function alive(id) { return !!pg && !!D.FORGES[id]; }
  readonly property var signedIds: pg.forges.filter((id) => pg.st[id] && pg.st[id].account && pg.st[id].account.signedIn)
  readonly property bool checking: pg.forges.some((id) => !pg.st[id] || pg.st[id].checking)
  readonly property bool loadingRepos: pg.signedIds.some((id) => pg.st[id].loading)
  readonly property bool signedIn: pg.signedIds.length > 0
  onForgesChanged: {
    if (!pg.win) return;
    const o = {};
    for (const id of pg.forges) if (pg.st[id]) o[id] = pg.st[id];
    pg.st = o;
    for (const id of pg.forges) if (!o[id]) pg.reloadOne(id);
  }

  // signed in before through the forge's tool, which is gone now: whom its
  // record still names (the window's tools) — a reinstall brings it back
  function wasOf(id) {
    const s = pg.siteOf(id);
    return pg.win && pg.win.tools && s.cli && !pg.win.tools[s.cli] ? (pg.win.tools[s.cli + "User"] || "") : "";
  }
  // the chips: a forge signed in to, once signed in to, or whose sign-in
  // was refused
  readonly property var chips: { pg.win ? pg.win.tools : null;
    return pg.forges.filter((id) => pg.signedInTo(id) || pg.wasOf(id) !== "" || (pg.stOf(id).account && pg.stOf(id).account.error)); }

  readonly property string title: "Accounts"
  readonly property string subtitle: pg.checking && !pg.signedIn ? "Asking your forges…"
    : pg.signedIn ? pg.signedIds.map((id) => pg.stOf(id).account.login + " on " + pg.siteOf(id).name).join("  ·  ")
    : "Not signed in"
  readonly property var hints: pg.signedIn
    ? [["return", "open"], ["c", "clone"], ["u", "upload files"], ["w", "web"], ["a", pg.repo && pg.repo.archived ? "unarchive" : "archive"], ["n", "new"], ["/", "filter"]]
    : [["return", "add an account"]]
  readonly property var buttons: pg.signedIn ? [
    { label: "Upload files", visible: !!pg.repo, run: () => pg.upload(pg.repo) },
    { label: pg.win && pg.win.root !== "" && !pg.win.origin ? "Publish " + pg.win.repoName : "New repository",
      ink: Zenon.cyan, primary: true, run: () => pg.create() },
  ] : [{ label: "Add an account", ink: Zenon.cyan, primary: true, ready: !pg.checking, run: () => pg.addAccount() }]
  function takeFocus() { if (!filter.focused && pg.win) pg.win.focusKeys(); }

  // An answer is for the forge it was asked of, and only while that forge
  // is still there (a server can be removed meanwhile).
  function reload() {
    // a reload called for later, by a page already left: nothing to ask
    if (!pg || !pg.win || typeof pg.op !== "function") return;
    for (const id of pg.forges) pg.reloadOne(id);
  }
  function reloadOne(id) {
    if (!pg || !pg.win) return;
    pg.put(id, { checking: true });
    pg.win.mgr.call(pg.op(id, "Status"), null, {}, (ok, s) => { if (!pg.alive(id)) return;
      pg.put(id, { checking: false, account: ok ? s : null });
      if (pg.signedInTo(id)) { pg.loadRepos(id); pg.loadAccounts(id); }
      else pg.put(id, { repos: [], error: "" });
      Qt.callLater(pg.signInWanted);
    });
  }
  Component.onCompleted: Qt.callLater(pg.reload)

  // ── accounts ───────────────────────────────────────────────────────────
  // Every account delphi can see on a forge (gh keeps several, one active;
  // glab and a keyring token one) — its chip's menu's rows.
  function loadAccounts(id) {
    pg.win.mgr.call(pg.op(id, "Accounts"), null, {}, (ok, a) => {
      if (!pg.alive(id) || !ok) return;
      pg.put(id, { accounts: a.accounts, many: a.many });
    });
  }
  // the menu on an account's chip: switch to another, add one (where the
  // forge's tool keeps several), sign out; a forge's tool gone, install it
  function accountMenu(id, chip) {
    const s = pg.siteOf(id), x = pg.stOf(id), was = pg.wasOf(id);
    const items = [];
    if (pg.signedInTo(id)) {
      const me = x.account.login;
      (x.accounts || []).forEach((a) => items.push({
        text: a.login + (a.source === "keyring" ? "  (token)" : ""), icon: a.active ? "" : "",
        enabled: !a.active && !!x.many, run: () => pg.switchAccount(id, a.login) }));
      if (items.length === 0) items.push({ text: me, icon: "", enabled: false });
      if (x.many) items.push({ text: "Add another " + s.name + " account", icon: "", run: () => pg.signIn(id, true) });
      if (x.error) items.push({ isSeparator: true },
        { text: "Could not list its repositories", icon: "", enabled: false },
        { text: "Try again", icon: "", run: () => pg.loadRepos(id) });
      items.push({ isSeparator: true },
                 { text: "Open " + s.host, icon: "", run: () => Quickshell.execDetached(["xdg-open", "https://" + s.host + "/" + me]) },
                 { text: "Sign out of " + me, icon: "", danger: true, run: () => pg.signOut(id) });
    } else if (was !== "") {
      items.push({ text: "Install " + s.pkg + " to sign in again", icon: "", enabled: !pg.win.mgr.installing, run: () => pg.installThenSignIn(id) },
                 { text: "Sign in another way", icon: "", run: () => pg.signIn(id) });
    } else {
      items.push({ text: s.name + " refused the saved sign-in", icon: "", enabled: false },
                 { text: "Sign in again", icon: "", run: () => pg.signIn(id) });
    }
    if (s.server) items.push({ isSeparator: true }, { text: "Remove " + s.name, icon: "", danger: true, run: () => pg.removeServer(id) });
    const p = chip.mapToItem(pg, 0, chip.height + 4);
    menu.open(p.x, p.y, items);
  }
  function switchAccount(id, login) {
    const s = pg.siteOf(id);
    pg.win.act(pg.op(id, "Switch"), { login: login }, { repo: null, refresh: false, network: true,
      label: "Switching to " + login,
      then: (a) => { if (!pg.alive(id)) return; pg.put(id, { account: a, repos: [] }); pg.loadRepos(id); pg.loadAccounts(id);
                     pg.win.say("Now " + login + " on " + s.name); } });
  }
  // ADD ACCOUNT: a forge not signed in to yet, another account where the
  // forge's tool keeps several, or a server of your own
  // — a menu from the + chip (a card's row of answers ran out of room)
  function addAccount(at) {
    // every forge, the same way (user, 2026-10-17: not "another GitHub
    // account" alone): signed in, it adds another account; else it signs in
    const items = pg.forges.map((id) => ({ text: pg.siteOf(id).name, icon: pg.siteOf(id).glyph,
      mark: pg.signedInTo(id) ? "another" : "", run: () => pg.signIn(id, pg.signedInTo(id)) }));
    items.push({ isSeparator: true });
    items.push({ text: "A server of your own…", icon: "\uF233", run: () => pg.addServer() });
    const from = at || (pg.signedIn ? addChip : signInBtn);
    const p = from.mapToItem(pg, 0, from.height + 4);
    menu.open(p.x, p.y, items, "add");
  }
  // the window asked for one forge's sign-in (DelphiWindow.signInTo):
  // asked here once that forge's state is known
  function signInWanted() {
    if (!pg || !pg.win || pg.win.wantSignIn === "") return;
    const id = pg.win.wantSignIn;
    if (!D.FORGES[id]) { pg.win.wantSignIn = ""; return; }
    if (!pg.st[id] || pg.st[id].checking) return;
    pg.win.wantSignIn = "";
    if (!pg.signedInTo(id)) pg.signIn(id);
  }

  // ── A SERVER OF YOUR OWN ───────────────────────────────────────────────
  // A self-hosted GitLab, or a Forgejo or Gitea: which kind, then where;
  // then it is a forge like the others, signed in to with a token
  // (DelphiManager.servers, delphi.js setServers, server.route)
  function addServer() {
    const ask = (kind) => pg.win.ask({ title: "A " + D.SERVER_KINDS[kind].name + " server", glyph: D.SERVER_KINDS[kind].glyph,
      detail: "Its address — git.example.org, or the https:// one from your browser. Delphi talks to its API there, over https.",
      fields: [{ key: "host", label: "Address", hint: "git.example.org" },
               { key: "name", label: "Called", hint: "as Delphi shows it (optional)" }],
      verb: "Add",
      then: (v) => {
        const host = D.hostOf(v.host);
        if (host === "") { pg.win.say("That is not an address — git.example.org, say", true); return; }
        const id = pg.win.mgr.addServer(kind, host, v.name.trim());
        // its state comes with the forges' change; signing in after it
        pg.win.wantSignIn = id;
      } });
    pg.win.card_({ question: "Add a server of your own", glyph: "", ink: Zenon.ink,
      detail: "A GitLab you or your work runs, or a Forgejo or Gitea. Its repositories, pull requests and issues then work as GitHub's do here.",
      choices: [{ label: "GitLab", ink: Zenon.cyan, run: () => ask("gitlab") },
                { label: "Forgejo or Gitea", ink: Zenon.cyan, run: () => ask("forgejo") },
                { label: "Cancel", ink: Zenon.accentMuted }] });
  }
  function removeServer(id) {
    const s = pg.siteOf(id);
    if (!s.server) return;
    pg.win.confirm({ question: "Remove " + s.name + "?", glyph: s.glyph, ink: Zenon.red,
      detail: "Its repositories leave the list, and its token is forgotten. Your clones of them stay as they are.",
      verb: "Remove",
      then: () => {
        pg.win.mgr.call(s.id + "ForgetToken", null, {}, () => {});
        pg.win.mgr.removeServer(s.id);
      } });
  }

  // ── signing in ─────────────────────────────────────────────────────────
  // `another`: an account added beside the one signed in (gh keeps both)
  function signIn(id, another) {
    // GitLab holds one account at a time: glab keeps one, and its sign-in
    // lasts two hours unless glab renews it, so it cannot be kept aside to
    // switch back to. Another is had by signing out first.
    if (another && pg.signedInTo(id) && (id === "gitlab" || pg.siteOf(id).kind === "gitlab")) {
      const s0 = pg.siteOf(id), a0 = pg.stOf(id).account;
      pg.win.card_({ question: s0.name + " holds one account", glyph: s0.glyph, ink: Zenon.ink,
        detail: "You are signed in as " + a0.login + ". " + (a0.source === s0.cli ? s0.cli + " keeps one account per site, so" : "Here")
          + " another account means signing out of " + a0.login + " first. Your clones stay as they are.",
        choices: [{ label: "Sign out, then sign in", ink: Zenon.cyan, run: () => {
                      const viaCli = !!s0.cli && a0.source === s0.cli;
                      pg.win.act(viaCli ? pg.op(id, "Logout") : pg.op(id, "ForgetToken"), {}, { repo: null, refresh: false,
                        label: "Signing out of " + a0.login,
                        // asked again before signing in: the card's offers follow what it says
                        then: () => pg.win.mgr.call(pg.op(id, "Status"), null, {}, (ok, a) => { if (!pg.alive(id)) return;
                          pg.put(id, { account: ok ? a : null, repos: [], checking: false }); pg.signIn(id); }) }); } },
                  { label: "Cancel", ink: Zenon.accentMuted }] });
      return;
    }
    // the browser, where the forge's own tool signs in (gh, glab), else a
    // token; the tool not installed, it is offered — Ceres installs it
    const s = pg.siteOf(id), a = pg.stOf(id).account;
    const has = !!a && !!a.cli;
    const cli = has && s.cli !== "";
    const missing = !has && s.cli !== "";
    const choices = [];
    if (cli) choices.push({ label: "Use the browser", ink: Zenon.cyan, run: () => pg.browser(id) });
    if (missing) choices.push({ label: "Install " + s.pkg + ", then sign in", ink: Zenon.cyan, run: () => pg.installThenSignIn(id) });
    choices.push({ label: "Paste a token", ink: cli || missing ? Zenon.accentMuted : Zenon.cyan, run: () => pg.token(id) });
    choices.push({ label: "Cancel", ink: Zenon.accentMuted });
    pg.win.card_({ question: another ? "Another account on " + s.name : "Sign in to " + s.name, glyph: s.glyph, ink: Zenon.ink,
      detail: cli ? "In your browser, through " + s.cli + " — or with a personal access token you made."
          + (another ? " It is added beside " + a.login + " and becomes the one in use; switch back from its menu." : "")
        : missing ? "Signing in with the browser goes through " + s.cli + ", which is not installed. Delphi can have Ceres install it ("
          + s.pkg + " — Ceres asks for your password), or paste a personal access token (" + s.tokens + ")."
        : "With a personal access token (" + s.tokens + ").",
      choices: choices });
  }
  // signed in: its repositories join the list, and it is the forge the
  // window's other questions start from (who commits, say)
  function signedInNow(id, a, said) {
    if (!pg.alive(id)) return;
    pg.put(id, { account: a, checking: false });
    pg.win.mgr.set("forge", id);
    pg.win.say(said || "Signed in to " + pg.siteOf(id).name + " as " + a.login);
    pg.loadRepos(id); pg.loadAccounts(id);
  }
  // the forge's tool, through Ceres, then the browser sign-in it gives —
  // once Ceres says it is in, and the daemon finds it
  function installThenSignIn(id) {
    const s = pg.siteOf(id);
    pg.win.mgr.installTool(s.pkg, "for signing in to " + s.name, (ok) => {
      if (!pg.alive(id) || !ok) return;
      pg.win.mgr.call(pg.op(id, "Status"), null, {}, (ok2, a) => {
        if (!pg.alive(id) || !ok2) return;
        // its record kept the sign-in: back as it was, nothing to ask
        if (a.signedIn) { pg.signedInNow(id, a, "Signed in again as " + a.login); return; }
        pg.put(id, { account: a });
        if (a.cli) pg.browser(id);
      });
    });
  }
  function browser(id) {
    const s = pg.siteOf(id);
    let codeCard = -1, job = -1;
    job = pg.win.act(pg.op(id, "Login"), {}, {
      repo: null, label: "Signing in to " + s.name, network: true, refresh: false,
      event: (ev) => { if (!pg) return;
        if (!ev.device || codeCard >= 0) return;
        const d = ev.device;
        // gh hands a one-time code to type; glab only a page to open
        codeCard = pg.win.card_(d.code ? { question: "Your code:  " + d.code, glyph: s.glyph, ink: Zenon.cyan,
            detail: "Enter it at " + d.url.replace(/^https:\/\//, "") + " — this card goes by itself once " + s.name + " says yes.",
            choices: [{ label: "Open " + s.name, ink: Zenon.cyan, keep: true, run: () => Quickshell.execDetached(["xdg-open", d.url]) },
                      { label: "Copy the code", keep: true, run: () => pg.win.copy(d.code, "the code") },
                      { label: "Cancel", ink: Zenon.accentMuted, run: () => pg.win.stop(job) }] }
          : { question: "Finish in your browser", glyph: s.glyph, ink: Zenon.cyan,
            detail: s.name + " asks there whether " + s.cli + " may act for you. This card goes by itself once it says yes.",
            choices: [{ label: "Open the page again", ink: Zenon.cyan, keep: true, run: () => Quickshell.execDetached(["xdg-open", d.url]) },
                      { label: "Cancel", ink: Zenon.accentMuted, run: () => pg.win.stop(job) }] });
      },
      done: () => { if (codeCard >= 0) pg.win.dropCard(codeCard); },
      then: (a) => pg.signedInNow(id, a),
    });
  }
  function token(id) {
    const s = pg.siteOf(id);
    pg.win.ask({ title: "A personal access token for " + s.name, glyph: "",
      detail: "Made at " + s.tokens + ", with access to your repositories. Kept in your keyring; git uses it for " + s.host + " too.",
      secret: { key: "token", prompt: "paste your token", purpose: "ctrl v pastes it" },
      verb: "Sign in",
      then: (v) => pg.win.act(pg.op(id, "SetToken"), { token: v.token.trim() }, { repo: null, refresh: false,
        label: "Checking the token with " + s.name, network: true,
        // said where it was kept: delphi's own file, when there is no keyring
        then: (r) => { pg.win.say("Signed in to " + s.name + " as " + r.login + (r.where === "file" ? " — kept in Delphi's own file (no keyring running)" : ""));
                       pg.win.mgr.set("forge", id); pg.reloadOne(id); } }) });
  }
  function signOut(id) {
    const s = pg.siteOf(id), a = pg.stOf(id).account;
    const viaCli = !!s.cli && !!a && a.source === s.cli;
    pg.win.confirm({ question: "Sign out of " + s.name + "?", glyph: s.glyph,
      detail: (viaCli ? s.cli + " forgets this account (" + s.cli + " auth logout)." : "The token leaves your keyring.")
        + " Its repositories leave the list; your clones of them stay.",
      verb: "Sign out", then: () => pg.win.act(viaCli ? pg.op(id, "Logout") : pg.op(id, "ForgetToken"), {}, {
        repo: null, refresh: false, then: () => { if (pg.alive(id)) { pg.put(id, { repos: [] }); pg.reloadOne(id); } } }) });
  }

  // ── the repositories ───────────────────────────────────────────────────
  // every signed-in forge's, each marked with its forge, newest push first
  readonly property var repos: {
    const out = [];
    for (const id of pg.signedIds)
      for (const r of (pg.st[id].repos || [])) out.push(Object.assign({ forge: id }, r));
    return out.sort((a, b) => (Date.parse(b.pushed) || 0) - (Date.parse(a.pushed) || 0));
  }
  property string query: ""
  readonly property var shown: pg.repos.filter((r) => pg.query === ""
    || (r.full + " " + r.description + " " + pg.siteOf(r.forge).name).toLowerCase().indexOf(pg.query.toLowerCase()) >= 0)
  // the selection kept by which repository it is: another forge's answer
  // coming in moves the rows under it
  property string selKey: ""
  function keyOf(r) { return r ? r.forge + " " + r.full : ""; }
  readonly property int sel: { const i = pg.shown.findIndex((r) => pg.keyOf(r) === pg.selKey); return i >= 0 ? i : 0; }
  readonly property var repo: pg.sel >= 0 && pg.sel < pg.shown.length ? pg.shown[pg.sel] : null
  // the forges whose listing failed — said above the list with Retry, not
  // as a card to dismiss: the page is the answer to "what are my repositories"
  readonly property var listErrors: pg.signedIds.filter((id) => !!pg.st[id].error && !pg.st[id].loading)
  function loadRepos(id) {
    pg.put(id, { loading: true, error: "" });
    pg.win.mgr.call(pg.op(id, "Repos"), null, {}, (ok, rs, err) => { if (!pg.alive(id)) return;
      pg.put(id, ok ? { loading: false, repos: rs } : { loading: false, error: D.errorText(err ? err.error : "") });
      if (ok) { Qt.callLater(pg.publishWanted); Qt.callLater(pg.findClones); }
    });
  }
  function moveTo(i) {
    if (pg.shown.length === 0) return;
    const j = Math.max(0, Math.min(pg.shown.length - 1, i));
    pg.selKey = pg.keyOf(pg.shown[j]);
    list.positionViewAtIndex(j, ListView.Contain);
  }

  // ── WHICH ARE HERE ─────────────────────────────────────────────────────
  // The repositories opened before, by their remotes (delphi/core
  // clonesOf): "host/owner/name" → its clone here, and a repository name →
  // the clones with a remote by that name anywhere. A row says where its
  // clone is, or which repository here has its name — the same project on
  // another forge, most likely, to be kept in sync rather than cloned again.
  property var at: ({})
  property var named: ({})
  function findClones() {
    if (!pg || !pg.win) return;
    const roots = pg.win.mgr.recents.map((x) => x.root);
    pg.win.mgr.call("clonesOf", null, { roots: roots }, (ok, res) => {
      if (!pg || !ok) return;
      pg.at = res.at;
      // a directory's own name counts too: a repository with no remote yet
      const n = Object.assign({}, res.names);
      for (const root of roots) {
        const k = D.baseName(root).toLowerCase();
        n[k] = (n[k] || []).concat((n[k] || []).indexOf(root) < 0 ? [root] : []);
      }
      pg.named = n;
    });
  }
  function cloneOf(r) { return r ? pg.at[(pg.siteOf(r.forge).host + "/" + r.full).toLowerCase()] || "" : ""; }
  // the repository here of the same name, not already a clone of this one
  function twinOf(r) {
    if (!r || pg.cloneOf(r) !== "") return "";
    const roots = pg.named[r.name.toLowerCase()] || [];
    return roots.length > 0 ? roots[0] : "";
  }
  // kept in sync with the one here of its name: its remote added there
  function joinTwin(r) {
    const root = pg.twinOf(r);
    if (root === "") return;
    pg.win.confirm({ question: "Keep " + D.baseName(root) + " in sync with " + r.full + "?", glyph: pg.siteOf(r.forge).glyph, ink: Zenon.cyan,
      detail: r.full + " on " + pg.siteOf(r.forge).name + " is added to " + D.tilde(root, pg.win.home) + " as a remote. If their histories are one, Push there becomes Sync: "
        + "every forge it is on brought to the same commits, nothing overwritten. If they share nothing, Delphi says so and syncs nothing.",
      verb: "Keep in sync",
      then: () => pg.win.joinForge(root, pg.siteOf(r.forge), r, null) });
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
  // was not what a click on a repository meant (user, 2026-10-11). One
  // here of the same name comes first: keeping the two in sync.
  function openOne(r) {
    if (!r) return;
    const s = pg.siteOf(r.forge);
    const roots = pg.win.mgr.recents.map((x) => x.root);
    pg.win.mgr.call("whereCloned", null, { host: s.host, full: r.full, roots: roots }, (ok, res) => {
      if (!pg) return;
      if (ok && res.root) { pg.win.openRepo(res.root); pg.win.setPage("changes"); return; }
      const twin = pg.twinOf(r);
      const choices = twin !== "" ? [{ label: "Keep in sync", ink: Zenon.cyan, run: () => pg.joinTwin(r) },
                                     { label: "Clone anyway", run: () => pg.clone(r) }]
                                  : [{ label: "Clone", ink: Zenon.cyan, run: () => pg.clone(r) },
                                     { label: "Upload files", run: () => pg.upload(r) },
                                     { label: "Open on the web", run: () => pg.web(r) }];
      pg.win.card_({ question: r.full, glyph: s.glyph, ink: Zenon.ink,
        detail: (r.description ? r.description + "  ·  " : "") + s.name + "  ·  "
          + (twin !== "" ? "Not cloned here — but " + D.tilde(twin, pg.win.home) + " has its name: the same project on another forge, most likely."
                         : "Not cloned here yet."),
        choices: choices.concat([{ label: "Cancel" }]) });
    });
  }
  // ARCHIVE (user, 2026-10-14): read-only on the forge, kept — the clone
  // here, when there is one, can be forgotten in the same go
  // (DelphiWindow.archiveOnForge); an archived one unarchived
  function archive(r) {
    if (!r) return;
    const s = pg.siteOf(r.forge);
    const hub = { forge: r.forge, full: r.full };
    if (r.archived) {
      pg.win.confirm({ question: "Unarchive " + r.full + "?", glyph: s.glyph, ink: Zenon.cyan,
        detail: "It takes pushes, issues and pull requests again.", verb: "Unarchive",
        then: () => pg.win.act(pg.op(r.forge, "Archive"), { full: r.full, on: false }, { repo: null, network: true, refresh: false,
          label: "Unarchiving " + r.full, said: "Unarchived " + r.full, then: () => pg.markArchived(r, false) }) });
      return;
    }
    const roots = pg.win.mgr.recents.map((x) => x.root);
    pg.win.mgr.call("whereCloned", null, { host: s.host, full: r.full, roots: roots }, (ok, res) => {
      if (!pg) return;
      const root = ok && res.root ? res.root : "";
      pg.win.archiveOnForge(hub, { root: root, name: root ? D.baseName(root) : "", then: () => pg.markArchived(r, true) });
    });
  }
  function markArchived(r, on) {
    if (!pg.alive(r.forge)) return;
    pg.put(r.forge, { repos: (pg.stOf(r.forge).repos || []).map((x) => x.full === r.full ? Object.assign({}, x, { archived: on }) : x) });
  }
  function web(r) { if (r) Quickshell.execDetached(["xdg-open", "https://" + pg.siteOf(r.forge).host + "/" + r.full]); }

  // Upload: files and directories chosen in terminus (many at once; a
  // directory brings everything under it, under its own name), where they
  // go in the repository, and what the commit says — one commit on the
  // forge, no clone
  function upload(r) {
    if (!r || !pg.win.mgr.fileManager) return;
    pg.win.mgr.fileManager.choose(false, pg.win.home, (paths) => {
      if (!paths || paths.length === 0) return;
      // its branches first, for the dropdown (the default one on top); a
      // new one can be typed, and is made from the default branch
      // as a job in the head (its pill, Esc stops it): a stalled request
      // takes seconds, and a toast that fades said nothing was happening
      pg.win.act(pg.op(r.forge, "Branches"), { full: r.full }, { repo: null, label: "Asking " + r.name + " for its branches",
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
    pg.win.ask({ title: "Upload " + (paths.length === 1 ? names[0] : paths.length + " items") + " to " + r.full, glyph: "",
      fields: [{ key: "dir", label: "Into the directory", hint: "the top of the repository", optional: true, value: was.dir || "" },
               { key: "msg", label: "Commit message", value: was.msg || (paths.length === 1 ? "Add " + names[0] : "Add " + names.slice(0, 3).join(", ") + (paths.length > 3 ? " and " + (paths.length - 3) + " more" : "")) },
               { key: "branch", label: "Branch", options: branches,
                 value: was.branch && branches.indexOf(was.branch) >= 0 ? was.branch : branches[0],
                 other: "New branch", otherHint: "a name for the new branch" }],
      verb: "Review",
      then: (v) => pg.review(r, paths, branches, v) });
  }
  // the breakdown: every file, where it lands, how big, and whether one is
  // already there — asked of the forge before anything is sent
  // v.contents: the one directory chosen is the repository's top — its
  // files land there, not under its name (a new repository filled from it)
  function review(r, paths, branches, v) {
    const dir = String(v.dir || "").trim().replace(/^\/+|\/+$/g, "");
    const files = v.contents ? [{ local: paths[0], path: dir }]
      : paths.map((p) => ({ local: p, path: (dir ? dir + "/" : "") + D.baseName(p) }));
    const branch = String(v.branch || "").trim() || branches[0];
    const message = String(v.msg || "").trim();
    pg.win.act(pg.op(r.forge, "Plan"), { full: r.full, files: files, branch: branch }, { repo: null, label: "Looking at " + r.name,
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
        glyph: "", ink: Zenon.cyan,
        detail: Terminus.formatSize(total) + "  ·  "
          + (plan.fresh ? "onto a new branch " + plan.branch + ", made from " + plan["from"] : "onto " + plan.branch)
          + (replacing > 0 ? "  ·  replaces " + replacing : "")
          + (plan.skipped > 0 ? "  ·  leaves out " + plan.skipped + " (caches, and what git ignores)" : "")
          + "  ·  “" + D.subjectOf(message) + "”",
        rows: entries,
        treeRoot: r.name,
        choices: [{ label: "Upload", ink: Zenon.cyan,
                    run: () => pg.win.mgr.startUpload({ full: r.full, branch: plan.branch, fresh: plan.fresh, entries: entries, forge: r.forge }, sending, message) },
                  { label: "Back", run: () => pg.askUpload(r, paths, branches, v) },
                  { label: "Cancel" }] });
    } });
  }

  // which forge, when more than one is signed in to: asked, then `then(id)`
  function pickForge(question, then) {
    if (pg.signedIds.length === 1) { then(pg.signedIds[0]); return; }
    pg.win.pickForge(question, pg.signedIds, then);
  }
  // New: a repository on a forge — empty, or filled from a directory chosen
  // in terminus (a repository's history pushed, plain files uploaded); with
  // one open here that has nowhere to push, that one published to it
  function create() {
    if (!pg.signedIn) { pg.addAccount(); return; }
    const local = pg.win.root !== "" && !pg.win.origin;
    if (local) {
      pg.win.card_({ question: "Publish " + pg.win.repoName, glyph: "", ink: Zenon.ink,
        detail: "To a repository you already have — its history is taken in, and only what differs is left to commit — or as a new one.",
        choices: [{ label: "To an existing one", ink: Zenon.cyan, run: () => pg.connectExisting(null) },
                  { label: "As a new repository", run: () => pg.pickForge("Publish " + pg.win.repoName + " on…", (id) => pg.askCreate(id, { dir: pg.win.root, repo: true, open: true })) },
                  { label: "Cancel" }] });
      return;
    }
    pg.pickForge("A new repository on…", (id) => pg.win.card_({ question: "A new repository on " + pg.siteOf(id).name, glyph: pg.siteOf(id).glyph, ink: Zenon.ink,
      detail: "Empty, or filled from a directory: a git repository's history is pushed; a plain directory's files are uploaded.",
      choices: [{ label: "From a directory", ink: Zenon.cyan, run: () => pg.createFrom(id) },
                { label: "Empty", run: () => pg.askCreate(id, null) },
                { label: "Cancel" }] }));
  }
  // the directory, in terminus' picker, and what it is: a repository's
  // own top, or files (a directory inside some repository is files too)
  function createFrom(id) {
    if (!pg.win.mgr.fileManager) return;
    pg.win.mgr.fileManager.choose(true, pg.win.home, (paths) => {
      if (!paths || paths.length === 0) return;
      const dir = paths[0].replace(/\/+$/, "");
      pg.win.mgr.call("discover", null, { path: dir }, (ok, info) => {
        if (!pg) return;
        pg.askCreate(id, { dir: dir, repo: !!ok && !!info && !info.bare && info.root === dir });
      });
    });
  }
  // from: null (empty), or { dir, repo, open } — `open`: the repository is
  // the one this window has open
  function askCreate(id, from) {
    const s = pg.siteOf(id);
    const name = from ? D.baseName(from.dir).replace(/[^A-Za-z0-9._-]+/g, "-") : "";
    pg.win.ask({ title: !from ? "A new repository on " + s.name : from.open ? "Publish " + name + " to " + s.name : "A repository on " + s.name + " from " + D.baseName(from.dir),
      glyph: s.glyph,
      detail: !from ? "" : from.repo ? "Its history is pushed there: " + D.tilde(from.dir, pg.win.home)
        : "Its files are uploaded there, at the top — a commit made on " + s.name + "; nothing is written into " + D.tilde(from.dir, pg.win.home) + ".",
      fields: [{ key: "name", label: "Name", value: name },
               { key: "desc", label: "Description", hint: "optional", optional: true }],
      toggles: [{ key: "priv", label: "Private", value: true }],
      verb: !from ? "Create" : from.repo ? "Publish" : "Create and review",
      then: (v) => pg.win.act(pg.op(id, "Create"), { name: v.name.trim(), private: !!v.priv, description: v.desc.trim() }, {
        repo: null, label: "Creating " + v.name.trim() + " on " + s.name, network: true, refresh: false,
        // the name is taken — by one of yours, most likely the very one
        // meant: connecting to it is offered rather than a dead end
        failed: (err) => {
          const taken = /already exists/i.test(String(err && err.error || ""));
          const mine = taken ? pg.repos.find((x) => x.forge === id && x.name.toLowerCase() === v.name.trim().toLowerCase()) : null;
          if (mine && from && from.repo) pg.win.card_({ question: "You already have " + mine.full, glyph: s.glyph, ink: Zenon.yellow,
            detail: "Connect " + D.baseName(from.dir) + " to it instead? Its history is taken in and only what differs is left to commit — nothing there is replaced.",
            choices: [{ label: "Connect to it", ink: Zenon.cyan, run: () => pg.connectExisting(mine, from.dir) },
                      { label: "Cancel" }] });
          else pg.win.fail("Could not create " + v.name.trim(), taken ? "A repository by that name is already on your " + s.name + " account." : null, err);
        },
        then: (r) => {
          const made = Object.assign({ forge: id, name: v.name.trim() }, r);
          pg.loadRepos(id);
          if (!from) { pg.win.say("Created " + r.full + " on " + s.name); return; }
          if (from.repo) pg.publish(from.dir, made);
          // the breakdown first, as any upload: every file, new, then the ring
          else pg.review(made, [from.dir], [r.branch],
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

  // CONNECT: the repository here joined to one already on a forge (made by
  // hand uploads, say). Chosen from yours on every forge — the one of the
  // same name first — then said exactly what happens before it does
  // (delphi/core repo.connect): history fetched, a branch with no commits
  // put on it with every file left as it is, so Changes shows only what
  // differs.
  function connectExisting(r, dir) {
    const here = dir || pg.win.root;
    if (here === "" || pg.repos.length === 0) { pg.win.say("No repositories on your accounts to connect to", true); return; }
    if (r) { pg.confirmConnect(r, here); return; }
    const name = D.baseName(here).toLowerCase();
    const sorted = pg.repos.slice().sort((a, b) => (b.name.toLowerCase() === name) - (a.name.toLowerCase() === name));
    const label = (x) => x.full + "  ·  " + pg.siteOf(x.forge).name;
    pg.win.ask({ title: "Connect " + D.baseName(here), glyph: "",
      detail: "Which of your repositories it is a copy of.",
      fields: [{ key: "full", label: "Repository", options: sorted.map(label) }],
      verb: "Next",
      then: (v) => { const pick = sorted.find((x) => label(x) === v.full); if (pick) pg.confirmConnect(pick, here); } });
  }
  function confirmConnect(r, here, onto) {
    const s = pg.siteOf(r.forge);
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
    pg.win.confirm({ question: "Connect " + D.baseName(here) + " to " + r.full + "?", glyph: s.glyph, ink: Zenon.cyan,
      detail: "Its history is downloaded and your branch is put on it. Your files stay exactly as they are; Changes then shows only what differs from " + r.full
        + ", to commit and push on top. Nothing on " + s.name + " is replaced.",
      items: [D.tilde(here, pg.win.home) + "  →  " + r.full + " (" + (r.branch || "main") + ")"],
      verb: "Connect",
      then: () => pg.win.act("connect", { url: r.https, branch: r.branch || null, onto: !!onto }, { repo: here,
        label: "Connecting to " + r.full, network: true,
        then: (res) => {
          if (res.adopted && res.backup) pg.win.say("On " + r.full + "'s history — yours is kept on " + res.backup + "; Changes shows what differs");
          else if (res.adopted) pg.win.say("Connected — on " + r.full + "'s history; Changes shows what differs");
          else if (res.empty) pg.win.say("Connected — " + r.full + " is empty: commit, then Push");
          else if (res.unrelated) pg.win.card_({ question: "Not joined to " + r.full, glyph: s.glyph, ink: Zenon.yellow,
            detail: "This repository has commits of its own that share nothing with " + r.full + "'s. Its remote is set; nothing else changed. "
              + "Delphi can put your branch on top of theirs: your commits are kept on a backup branch, your files stay exactly as they are, and Changes shows what differs from "
              + r.full + " — commit that and push. A file " + r.full + " has and this directory does not shows as deleted: leave it unstaged to keep it there.",
            choices: [{ label: "Put mine on top of theirs", ink: Zenon.cyan, run: () => pg.confirmConnect(r, here, true) },
                      { label: "Leave it" }] });
          else pg.win.say("Connected — " + (res.tracking ? "tracking " + res.remote + "/" + res.branch : "remote added"));
          pg.win.openRepo(here);
          if (res.adopted) pg.win.setPage("changes");
        } }) });
  }

  // a repository on disk pushed to a new one: origin (or, if it has an
  // origin already, a remote named for the forge), its branch published
  // there, and the window turned to it
  function publish(dir, r) {
    pg.win.mgr.call("remotes", dir, {}, (ok, rs) => {
      if (!pg) return;
      const name = ok && rs.some((x) => x.name === "origin") ? pg.win.remoteNameFor(pg.siteOf(r.forge), r.https, rs) : "origin";
      pg.win.act("remoteAdd", { name: name, url: r.https }, { repo: dir, refresh: false, then: () => {
        pg.win.mgr.call("status", dir, {}, (ok2, s) => {
          if (!pg) return;
          const b = ok2 && s.branch ? s.branch.head : "";
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
    if (!pg.signedIn) {
      if (k === Qt.Key_Return || k === Qt.Key_Enter) { pg.addAccount(); return true; }
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
    if (k === Qt.Key_A) { pg.archive(pg.repo); return true; }
    if (k === Qt.Key_Escape && pg.query !== "") { filter.text = ""; return true; }
    return false;
  }

  // ── not signed in anywhere ─────────────────────────────────────────────
  Column {
    visible: !pg.signedIn
    anchors.centerIn: parent
    width: Math.min(440, parent.width - 60)
    spacing: 14
    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 22
      Repeater {
        model: D.FORGE_ORDER.slice(0, 3)
        delegate: Text {
          required property var modelData
          text: D.FORGES[modelData].glyph
          color: Zenon.accentMuted
          opacity: 0.5
          font.family: Zenon.glyphFace
          font.pixelSize: Zenon.px(48)
        }
      }
    }
    Working { anchors.horizontalCenter: parent.horizontalCenter; running: pg.checking }
    Text {
      visible: !pg.checking
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.Wrap
      text: pg.chips.length > 0 ? "Not signed in anywhere right now — the chips above say why, and their menus put it right."
        : "Sign in to GitHub, GitLab, Codeberg or a server of your own to clone your repositories, publish new ones and upload files. Every account's repositories show here together."
      color: Zenon.accentMuted
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(15)
    }
    DialogButton {
      id: signInBtn
      visible: !pg.checking
      anchors.horizontalCenter: parent.horizontalCenter
      label: "Add an account"
      ink: Zenon.cyan
      primary: true
      onClicked: pg.addAccount(signInBtn)
    }
  }

  // ── the accounts: a chip each, a menu on each, and Add ─────────────────
  Flow {
    id: strip
    visible: pg.chips.length > 0 || pg.signedIn
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: 12
    spacing: 8
    z: 2
    Repeater {
      model: pg.chips
      delegate: Rectangle {
        id: chip
        required property var modelData
        readonly property string fid: chip.modelData
        readonly property var s: pg.siteOf(chip.fid)
        readonly property var x_: pg.stOf(chip.fid)
        readonly property bool inside: pg.signedInTo(chip.fid)
        readonly property bool bad: !chip.inside || !!chip.x_.error
        width: chipRow.implicitWidth + 24
        height: 28
        radius: Zenon.windowRadius
        color: chipPress.pressed ? Zenon.pressFill : Zenon.wash(0.04)
        border.width: 1
        border.color: menu.isOpen && menu.held === "chip:" + chip.fid ? Zenon.cyan : chip.bad ? Zenon.yellow : Zenon.border
        Row {
          id: chipRow
          anchors.centerIn: parent
          spacing: 8
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: chip.s.glyph
            color: chip.bad ? Zenon.yellow : Zenon.ink
            font.family: Zenon.glyphFace
            font.pixelSize: Zenon.px(14)
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: chip.inside ? chip.x_.account.login : pg.wasOf(chip.fid) !== "" ? pg.wasOf(chip.fid) : chip.s.name
            color: Zenon.ink
            font.family: Zenon.face
            font.weight: Font.Bold
            font.pixelSize: Zenon.px(14)
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            // what it is, and how it stands: the forge, a second account, a
            // tool gone, a listing that failed, its repositories coming
            text: chip.s.name
              + (chip.inside && (chip.x_.accounts || []).length > 1 ? "  ·  " + chip.x_.accounts.length + " accounts" : "")
              + (!chip.inside ? (pg.wasOf(chip.fid) !== "" ? "  ·  " + chip.s.cli + " missing" : "  ·  signed out") : "")
              + (chip.inside && chip.x_.error ? "  ·  not listed" : "")
            visible: !(chip.inside === false && pg.wasOf(chip.fid) === "")
            color: Zenon.accentMuted
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(13)
          }
          Working { anchors.verticalCenter: parent.verticalCenter; visible: running; running: !!chip.x_.loading || !!chip.x_.checking; dot: 3; gap: 3 }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: ""
            color: Zenon.accentMuted
            font.family: Zenon.glyphFace
            font.pixelSize: Zenon.px(10)
          }
        }
        MouseArea { id: chipPress; anchors.fill: parent; onClicked: { pg.accountMenu(chip.fid, chip); menu.held = "chip:" + chip.fid; } }
      }
    }
    // a new account: another forge, another account on one, a server —
    // the suite's small + (AddChip), centered on the chips' line
    Item {
      width: addChip.width + 8
      height: 28
      AddChip {
        id: addChip
        anchors.centerIn: parent
        size: Zenon.px(15)
        held: menu.isOpen && menu.held === "add"
        onClicked: pg.addAccount(addChip)
        HoverHandler { onHoveredChanged: hovered ? pg.win.tip(addChip, "Add an account") : pg.win.untip(addChip) }
      }
    }
  }
  BulkField {
    id: filter
    visible: pg.signedIn
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: strip.bottom
    anchors.margins: 12
    height: 32
    textSize: Zenon.px(15)
    ghost: "  Filter " + pg.repos.length + " repositories  ( / )"
    clearable: true
    onTextChanged: { pg.query = filter.text.trim(); pg.selKey = ""; }
    onAccepted: pg.win.focusKeys()
    Keys.onEscapePressed: { filter.text = ""; pg.win.focusKeys(); }
    Keys.onDownPressed: pg.win.focusKeys()
  }
  // a forge whose listing failed, said above the list with Retry
  Column {
    id: errs
    visible: pg.signedIn && pg.listErrors.length > 0
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: filter.bottom
    anchors.topMargin: errs.visible ? 8 : 0
    anchors.leftMargin: 24
    anchors.rightMargin: 24
    height: errs.visible ? implicitHeight : 0
    spacing: 4
    Repeater {
      model: pg.listErrors
      delegate: Text {
        required property var modelData
        width: errs.width
        elide: Text.ElideRight
        textFormat: Text.StyledText
        text: "<font color='" + Zenon.hex(Zenon.yellow) + "'>" + D.esc(pg.siteOf(modelData).name) + "</font> could not list its repositories — "
          + D.esc(String(pg.stOf(modelData).error || "").split("\n")[0]) + "   <font color='" + Zenon.hex(Zenon.cyan) + "'><b>Retry</b></font>"
        color: Zenon.accentMuted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(13)
        MouseArea { anchors.fill: parent; onClicked: pg.loadRepos(parent.modelData) }
      }
    }
  }
  ListView {
    id: list
    visible: pg.signedIn
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: errs.bottom
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
      readonly property var s: pg.siteOf(rrow.r.forge)
      // its clone here, or the repository here of its name
      readonly property string here: { pg.at; return pg.cloneOf(rrow.r); }
      readonly property string twin: { pg.named; pg.at; return pg.twinOf(rrow.r); }
      width: list.width
      height: list.rowH
      // its forge
      Text {
        id: rf
        x: 24
        width: Zenon.px(20)
        horizontalAlignment: Text.AlignHCenter
        anchors.verticalCenter: parent.verticalCenter
        text: rrow.s.glyph
        color: rrow.index === pg.sel ? Zenon.ink : Zenon.accentSoft
        font.family: Zenon.glyphFace
        font.pixelSize: Zenon.px(18)
      }
      // its kind: private, a fork, public
      Text {
        id: rg
        anchors.left: rf.right
        anchors.leftMargin: 10
        width: Zenon.px(15)
        horizontalAlignment: Text.AlignHCenter
        anchors.verticalCenter: parent.verticalCenter
        text: rrow.r.private ? "" : rrow.r.fork ? "" : ""
        color: rrow.r.private ? Zenon.yellow : Zenon.accentMuted
        font.family: Zenon.glyphFace
        font.pixelSize: Zenon.px(14)
      }
      Column {
        anchors.left: rg.right
        anchors.leftMargin: 14
        anchors.right: rside.left
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3
        Text {
          width: parent.width
          elide: Text.ElideRight
          textFormat: Text.StyledText
          text: D.esc(rrow.r.full) + (rrow.r.archived ? "&nbsp;&nbsp;&nbsp;<font color='" + Zenon.hex(Zenon.yellow) + "'>archived</font>" : "")
            + (rrow.r.empty ? "&nbsp;&nbsp;&nbsp;<font color='" + Zenon.hex(Zenon.accentMuted) + "'>empty</font>" : "")
          color: rrow.r.archived ? Zenon.accentMuted : rrow.index === pg.sel ? Zenon.ink : Zenon.accentSoft
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(16)
        }
        Text {
          visible: text !== ""
          width: parent.width
          elide: Text.ElideRight
          text: rrow.r.description
          color: Zenon.accentMuted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(13)
        }
      }
      Column {
        id: rside
        anchors.right: parent.right
        anchors.rightMargin: 24
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3
        Text {
          anchors.right: parent.right
          text: rrow.r.pushed ? D.ago(Date.parse(rrow.r.pushed) / 1000, Date.now()) : ""
          color: Zenon.accentMuted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.features: { "tnum": 1 }
          font.pixelSize: Zenon.px(13)
        }
        // where it is here: its clone, or the one of its name (another
        // forge's copy, most likely — a click away from kept in sync)
        Text {
          anchors.right: parent.right
          visible: text !== ""
          width: Math.min(implicitWidth, rrow.width * 0.38)
          elide: Text.ElideMiddle
          text: rrow.here !== "" ? "  " + D.tilde(rrow.here, pg.win.home)
            : rrow.twin !== "" ? "  same name as " + D.tilde(rrow.twin, pg.win.home) : ""
          color: rrow.here !== "" ? Zenon.accentMuted : Zenon.cyan
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(12)
        }
      }
      HeldRing { anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8; on: menu.isOpen && menu.held === rrow.index }
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (m) => {
          pg.selKey = pg.keyOf(rrow.r);
          if (m.button === Qt.RightButton) {
            const p = mapToItem(pg, m.x, m.y);
            const items = [
              { text: "Open", icon: "", mark: "return", run: () => pg.openOne(rrow.r) },
              { text: "Clone", icon: "", mark: "c", run: () => pg.clone(rrow.r) },
            ];
            if (rrow.twin !== "") items.push({ text: "Keep " + D.baseName(rrow.twin) + " in sync with it…", icon: "", run: () => pg.joinTwin(rrow.r) });
            items.push(
              { text: "Upload files", icon: "", mark: "u", run: () => pg.upload(rrow.r) },
              { text: "Open on the web", icon: "", mark: "w", run: () => pg.web(rrow.r) },
              { text: rrow.r.archived ? "Unarchive" : "Archive…", icon: "", mark: "a", run: () => pg.archive(rrow.r) },
              { isSeparator: true },
              { text: "Copy the HTTPS address", icon: "", run: () => pg.win.copy(rrow.r.https) },
              { text: "Copy the SSH address", icon: "", run: () => pg.win.copy(rrow.r.ssh) });
            menu.open(p.x, p.y, items, rrow.index);
            return;
          }
          pg.win.focusKeys();
        }
        onDoubleClicked: pg.openOne(rrow.r)
      }
    }
    // the first answer awaited in the list's middle, as every page does; more
    // coming after rows are there, under them
    footer: Item { width: list.width; height: pg.loadingRepos && pg.shown.length > 0 ? 50 : 0; Working { anchors.centerIn: parent; running: pg.loadingRepos && pg.shown.length > 0 } }
    Working { anchors.centerIn: parent; running: pg.loadingRepos && pg.shown.length === 0; visible: running }
    EmptyState {
      anchors.centerIn: parent
      visible: pg.shown.length === 0 && !pg.loadingRepos && pg.listErrors.length === 0
      filtered: pg.query !== ""
      text: pg.query !== "" ? "No matches" : "No repositories yet"
    }
  }
  ElasticScroll { anchors.fill: list; view: list; visible: pg.signedIn }
  Scrollbar { flick: list; visible: pg.signedIn; anchors.right: list.right; anchors.top: list.top; anchors.bottom: list.bottom }

  PopMenu {
    id: menu
    anchors.fill: parent
    window: pg.win
    cardWidth: 280
    onClosed: pg.win.focusKeys()
  }
}
