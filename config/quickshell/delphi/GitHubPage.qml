// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// GITHUB — the account, and its repositories: clone one, open it on the
// web, publish the repository you have open as a new one, or upload files
// straight to one (a commit made on GitHub — no clone, no git here).
//
// SIGNING IN is a card on the window's sheet, like every other question:
// the browser (gh's own sign-in — its one-time code shown on the card, Open
// and Copy beside it, and the card goes when GitHub says yes), or a personal
// access token pasted in, kept in the keyring. Either way git's own pushes
// to github.com use it too (delphi/core: gitrun.Creds).
//
//   ↑↓ repositories · return clone · u upload files · w open on the web
//   / filter · n new repository

import QtQuick
import Quickshell
import "../morpheus"
import "../terminus"
import "delphi.js" as D
import "../terminus/terminus.js" as Terminus

Item {
  id: pg
  property var win: null

  property var account: null      // githubStatus
  property bool checking: true
  readonly property bool signedIn: !!pg.account && pg.account.signedIn

  readonly property string title: "GitHub"
  readonly property string subtitle: pg.checking ? "Asking GitHub…"
    : pg.signedIn ? "Signed in as " + pg.account.login + (pg.account.source === "gh" ? " through gh" : " with a token")
    : "Not signed in"
  readonly property var hints: pg.signedIn
    ? [["return", "clone"], ["u", "upload files"], ["w", "web"], ["n", "new"], ["/", "filter"]]
    : [["return", "sign in"]]
  readonly property var buttons: pg.signedIn ? [
    { label: "Sign out", run: () => pg.signOut() },
    { label: "Upload files", visible: !!pg.repo, run: () => pg.upload(pg.repo) },
    { label: pg.win && pg.win.root !== "" && !pg.win.origin ? "Publish " + pg.win.repoName : "New repository",
      ink: Zenon.cyan, primary: true, run: () => pg.create() },
  ] : [{ label: "Sign in", ink: Zenon.cyan, primary: true, ready: !pg.checking, run: () => pg.signIn() }]
  function takeFocus() { if (!filter.focused && pg.win) pg.win.focusKeys(); }

  function reload() {
    pg.checking = true;
    pg.win.mgr.call("githubStatus", null, {}, (ok, st) => { if (!pg) return;
      pg.checking = false;
      pg.account = ok ? st : null;
      if (pg.signedIn) pg.loadRepos();
    });
  }
  Component.onCompleted: Qt.callLater(pg.reload)

  // ── signing in ─────────────────────────────────────────────────────────
  function signIn() {
    const gh = pg.account && pg.account.gh;
    const choices = [];
    if (gh) choices.push({ label: "Use the browser", ink: Zenon.cyan, run: () => pg.browser() });
    choices.push({ label: "Paste a token", ink: gh ? Zenon.muted : Zenon.cyan, run: () => pg.token() });
    choices.push({ label: "Cancel", ink: Zenon.muted });
    pg.win.card_({ question: "Sign in to GitHub", glyph: "", ink: Zenon.ink,
      detail: gh ? "In your browser, through the GitHub CLI — or with a personal access token you made."
                 : "With a personal access token (github.com → Settings → Developer settings). Installing github-cli adds signing in with the browser.",
      choices: choices });
  }
  function browser() {
    let codeCard = -1, job = -1;
    job = pg.win.act("githubLogin", {}, {
      repo: null, label: "Signing in", refresh: false,
      event: (ev) => { if (!pg) return;
        if (!ev.device || codeCard >= 0) return;
        const d = ev.device;
        codeCard = pg.win.card_({ question: "Your code:  " + d.code, glyph: "", ink: Zenon.cyan,
          detail: "Enter it at " + d.url.replace(/^https:\/\//, "") + " — this card goes by itself once GitHub says yes.",
          choices: [{ label: "Open GitHub", ink: Zenon.cyan, keep: true, run: () => Quickshell.execDetached(["xdg-open", d.url]) },
                    { label: "Copy the code", keep: true, run: () => pg.win.copy(d.code, "the code") },
                    { label: "Cancel", ink: Zenon.muted, run: () => pg.win.stop(job) }] });
      },
      done: () => { if (codeCard >= 0) pg.win.dropCard(codeCard); },
      then: (st) => { pg.account = st; pg.win.say("Signed in as " + st.login); pg.loadRepos(); },
    });
  }
  function token() {
    pg.win.ask({ title: "A personal access token", glyph: "",
      detail: "Made at github.com → Settings → Developer settings → Tokens, with access to your repositories. Kept in your keyring; git uses it for github.com too.",
      secret: { key: "token", prompt: "paste your token", purpose: "ctrl v pastes it" },
      verb: "Sign in",
      then: (v) => pg.win.act("githubSetToken", { token: v.token.trim() }, { repo: null, refresh: false,
        label: "Checking the token with GitHub", network: true,
        then: (r) => { pg.win.say("Signed in as " + r.login); pg.reload(); } }) });
  }
  function signOut() {
    const src = pg.account ? pg.account.source : "";
    pg.win.confirm({ question: "Sign out of GitHub?", glyph: "",
      detail: src === "gh" ? "gh forgets this account (gh auth logout)." : "The token leaves your keyring.",
      verb: "Sign out", then: () => pg.win.act(src === "gh" ? "githubLogout" : "githubForgetToken", {}, {
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
    pg.win.mgr.call("githubRepos", null, {}, (ok, rs, err) => { if (!pg) return;
      pg.loadingRepos = false;
      if (ok) pg.repos = rs;
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
  function web(r) { if (r) Quickshell.execDetached(["xdg-open", "https://github.com/" + r.full]); }

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
      pg.win.act("githubBranches", { full: r.full }, { repo: null, label: "Asking " + r.name + " for its branches",
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
  function review(r, paths, branches, v) {
    const dir = String(v.dir || "").trim().replace(/^\/+|\/+$/g, "");
    const files = paths.map((p) => ({ local: p, path: (dir ? dir + "/" : "") + D.baseName(p) }));
    const branch = String(v.branch || "").trim() || branches[0];
    const message = String(v.msg || "").trim();
    pg.win.act("githubPlan", { full: r.full, files: files, branch: branch }, { repo: null, label: "Looking at " + r.name,
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
                    run: () => pg.win.mgr.startUpload({ full: r.full, branch: plan.branch, fresh: plan.fresh, entries: entries }, sending, message) },
                  { label: "Back", run: () => pg.askUpload(r, paths, branches, v) },
                  { label: "Cancel" }] });
    } });
  }

  // New: an empty repository on GitHub — and, with one open here that has
  // nowhere to push, published to it in the same go
  function create() {
    const local = pg.win.root !== "" && !pg.win.origin;
    pg.win.ask({ title: local ? "Publish " + pg.win.repoName + " to GitHub" : "A new repository on GitHub", glyph: "",
      fields: [{ key: "name", label: "Name", value: local ? pg.win.repoName : "" },
               { key: "desc", label: "Description", hint: "optional", optional: true }],
      toggles: [{ key: "priv", label: "Private", value: true }],
      verb: local ? "Publish" : "Create",
      then: (v) => pg.win.act("githubCreate", { name: v.name.trim(), private: !!v.priv, description: v.desc.trim() }, {
        repo: null, label: "Creating", network: true, refresh: false,
        then: (r) => {
          pg.loadRepos();
          if (!local) { pg.win.say("Created " + r.full); return; }
          pg.win.act("remoteAdd", { name: "origin", url: r.https }, { then: () => {
            const b = pg.win.branch && pg.win.branch.head;
            if (!b) { pg.win.say("Created " + r.full + " — commit something, then Publish"); return; }
            pg.win.act("push", { remote: "origin", branch: b, setUpstream: true },
                       { label: "Publishing", network: true, said: "Published to " + r.full });
          } });
        } }) });
  }

  function key(e) {
    const k = e.key;
    if (e.modifiers & Qt.ControlModifier) return false;
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
    if (k === Qt.Key_Return || k === Qt.Key_Enter) { pg.clone(pg.repo); return true; }
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
      text: ""
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
      text: pg.account && pg.account.error ? "GitHub did not take the saved sign-in: " + pg.account.error
        : "Sign in to clone your repositories, publish new ones and upload files."
      color: Zenon.muted
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(15)
    }
    DialogButton {
      visible: !pg.checking
      anchors.horizontalCenter: parent.horizontalCenter
      label: "Sign in"
      ink: Zenon.cyan
      primary: true
      onClicked: pg.signIn()
    }
  }

  // ── signed in ──────────────────────────────────────────────────────────
  BulkField {
    id: filter
    visible: pg.signedIn
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
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
              { text: "Clone…", icon: "", mark: "return", run: () => pg.clone(rrow.r) },
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
        onDoubleClicked: pg.clone(rrow.r)
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
