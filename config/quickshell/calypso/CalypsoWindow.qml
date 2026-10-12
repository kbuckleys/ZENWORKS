// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// CALYPSO'S WINDOW — three columns, as 1Password lays its own out:
//
//   the sidebar   all items, favourites, one-time passwords; the kinds
//                 (logins, cards, notes…); your accounts, each on its
//                 platform, locked or open; the folders and tags in view
//   the list      a search over everything open, A–Z or most recent,
//                 under letter or age headings
//   the item      its face and name, its fields in cards — a secret as
//                 dots until revealed, the one-time password live — its
//                 notes, tags and dates (ItemDetail)
//
// A locked account in view is its lock (LockPane, the suite's password
// field); no account yet is the platforms to choose from (PlatformGrid).
// Every card — adding an account, a sign-in, a removal — is the suite's
// sheet (delphi/CardSheet); every right click a PopMenu, its target held in
// a HeldRing; an account pointed at says more in a Bubble.
//
// The window draws and asks; the vaults are the manager's (CalypsoManager)
// and the daemon's (calypso/core) — a secret reaches here only when revealed.
//
//   typing / ctrl+f    search          ↑ ↓  ctrl+j/k   items
//   return  ctrl+c     copy the password          ctrl+shift+c  the username
//   ctrl+alt+c         copy the one-time code     ctrl+r        reveal
//   ctrl+o             open the website           ctrl+d        favourite
//   ctrl+1…3           all · favourites · codes   ctrl+tab      sort
//   ctrl+s  sync       ctrl+n  add an account     ctrl+l        lock all
//   esc     unwinds: the search, the scope, then closes

import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../morpheus"
import "../terminus"
import "../delphi"
import "../ceres"
import "calypso.js" as C

FloatingWindow {
  id: win
  title: "calypso"
  color: Zenon.alpha(Zenon.layerBg, 0)
  implicitWidth: 1280
  implicitHeight: 820
  minimumSize: Qt.size(940, 560)

  property var mgr: null

  // CLOSED, IT IS KEPT, hidden (delphi's rule) — and what it had revealed
  // is forgotten as it goes
  onVisibleChanged: {
    if (!win.mgr) return;
    if (!win.visible) {
      win.forget();
      win.mgr.release("window");
      return;
    }
    win.mgr.hold("window");
  }
  onClosed: win.visible = false
  Component.onCompleted: if (win.mgr) win.mgr.hold("window")

  // the cursor bar's re-seat after a workspace switch (terminus' thawPulse)
  property int thawPulse: 0
  Connections {
    target: Hyprland
    function onFocusedWorkspaceChanged() { win.thawPulse++; }
  }

  readonly property color hiFill: Zenon.alpha(Zenon.cyan, 0.12)
  readonly property int headH: 46
  readonly property int footH: 40
  // morpheus/WindowTip is a popup, not an Item
  readonly property var tipsItem: tips
  readonly property Item stageItem: stage
  readonly property Item listView: list

  // the window comes up (open, or shown again): the accounts asked afresh
  function wake() {
    win.mgr.loadPlatforms();
    win.mgr.refreshAll();
    Qt.callLater(win.refocus);
  }

  // ── WHERE YOU ARE ──────────────────────────────────────────────────────
  readonly property var scope: win.mgr ? win.mgr.scope : ({ shelf: "all" })
  function setScope(s) {
    if (win.editing) { win.cancelEdit(() => win.setScope(s)); return; }
    win.mgr.set("scope", s);
    if (s.shelf === "trash") for (const a of win.mgr.accounts)
      if ((win.mgr.states[a.id] || {}).unlocked && C.can(win.mgr.platformInfo(a.kind), "restore")) win.mgr.loadTrash(a);
    win.toTop = true;
    win.refocus();
  }
  property string query: ""
  readonly property string sort: win.mgr ? win.mgr.sort : "name"
  // the trash shelf lists what the platforms keep in theirs; Watchtower's,
  // what it found something wrong with (mgr.flags)
  readonly property bool inTrash: win.scope.shelf === "trash"
  readonly property bool watching: win.scope.shelf === "watch" && !win.scope.audit
  readonly property var shown: !win.mgr ? []
    : win.inTrash ? C.shelve(win.mgr.trashItems, { acct: win.scope.acct }, win.query, win.mgr.favs, win.sort)
    : C.shelve(win.mgr.items, win.scope, win.query, win.mgr.favs, win.sort, win.mgr.flags)
  // the list's rows: each item, and whether a heading goes over it
  readonly property var rows: {
    const out = [];
    let last = null;
    const now = Date.now();
    for (const it of win.shown) {
      const sec = win.query !== "" ? "" : C.sectionOf(it, win.sort, now);
      out.push({ it: it, head: sec !== last && sec !== "" ? sec : "" });
      last = sec;
    }
    return out;
  }
  // THE LIST'S MODEL, KEPT IN PLACE. A ListView handed a new array starts
  // again from its top, and the array was new on every rebuild (an
  // account's status, entries filling in): the list jumped to the top in
  // the middle of a scroll (user's capture, 2026-10-12). Same items in the
  // same order: only what changed is set, and the view stays put; a new
  // search or scope is a new list, and starts at the top as it should.
  ListModel { id: rowModel }
  onRowsChanged: win.syncRows()
  function syncRows() {
    const r = win.rows;
    let same = rowModel.count === r.length;
    for (let i = 0; same && i < r.length; i++) same = rowModel.get(i).key === C.keyOf(r[i].it);
    if (same) {
      for (let i = 0; i < r.length; i++) if (rowModel.get(i).head !== r[i].head) rowModel.setProperty(i, "head", r[i].head);
      return;
    }
    rowModel.clear();
    for (const x of r) rowModel.append({ key: C.keyOf(x.it), head: x.head });
  }
  readonly property int rowH: 46 + Zenon.px(4)
  readonly property int secH: 30
  readonly property var tops: {
    const t = [];
    let y = 0;
    for (const r of win.rows) { t.push(y + (r.head !== "" ? win.secH : 0)); y += win.rowH + (r.head !== "" ? win.secH : 0); }
    return t;
  }
  property int sel: 0
  readonly property var item: win.sel >= 0 && win.sel < win.shown.length ? win.shown[win.sel] : null

  // who the item belongs to
  function acctOf(it) { return it && win.mgr ? win.mgr.accountOf(it.acct) || {} : {}; }
  function isFav(it) { return C.isFav(it, win.mgr ? win.mgr.favs : {}); }
  function toggleFav(it) {
    if (!it) return;
    if (it.fav) { win.say("A favourite in " + C.platform(win.acctOf(it).kind).name + " itself — change it there"); return; }
    win.mgr.setFav(it, !win.isFav(it));
  }

  // keep the item you were on across a new list (a search, a reload);
  // a new scope or search lands on the top
  property bool toTop: false
  property string lastKey: ""
  onShownChanged: Qt.callLater(win.reseat)
  // A list rebuilt under the user (an account's status, entries filling in,
  // a sync) keeps its place: the view moves only when the cursor itself
  // has to (its item went, a new search or scope lands on the top). It used
  // to bring the cursor back into view on every rebuild, and a rebuild
  // during a scroll threw the list back to the top (user's capture,
  // 2026-10-12).
  // An item asked for by name (just made, saved, copied): kept wanted
  // across rebuilds until the list has it — a rebuild before it arrives
  // would otherwise settle on whatever row was there — then gone
  property string wantKey: ""
  function want(key) { win.wantKey = key; wantExpiry.restart(); Qt.callLater(win.reseat); }
  Timer { id: wantExpiry; interval: 6000; onTriggered: win.wantKey = "" }
  function reseat() {
    if (win.wantKey !== "") {
      const w = win.shown.findIndex((i) => C.keyOf(i) === win.wantKey);
      if (w >= 0) {
        win.wantKey = "";
        win.sel = w;
        win.thawPulse++;
        list.positionViewAtIndex(w, ListView.Contain);
        return;
      }
    }
    const top = win.toTop;
    let at = top ? 0 : win.shown.findIndex((i) => C.keyOf(i) === win.lastKey);
    win.toTop = false;
    const lost = at < 0;
    if (lost) at = Math.min(Math.max(0, win.sel), win.shown.length - 1);
    at = Math.max(0, at);
    if (at === win.sel && !top && !lost) return;
    win.sel = at;
    win.thawPulse++;
    list.positionViewAtIndex(win.sel, top ? ListView.Beginning : ListView.Contain);
  }
  function move(d) {
    if (win.shown.length === 0) return;
    win.sel = Math.max(0, Math.min(win.shown.length - 1, win.sel + d));
    list.positionViewAtIndex(win.sel, ListView.Contain);
  }

  // ── THE ITEM IN FULL ───────────────────────────────────────────────────
  property var detail: null
  property bool detailBusy: false
  property string detailErr: ""
  // secrets shown, by ref — only ever what Reveal asked for
  property var revealed: ({})
  // the live one-time code: { code, period, left }
  property var code: null
  property int detailAsk: 0
  onItemChanged: {
    const k = C.keyOf(win.item);
    if (k === win.lastKey && win.detail) return;
    win.lastKey = k;
    win.loadDetail();
  }
  function loadDetail(secret) {
    win.revealed = ({});
    win.code = null;
    win.detailErr = "";
    const it = win.item;
    if (!it || win.inTrash) { win.detail = null; win.detailBusy = false; return; }
    if (secret === undefined) win.detail = null;
    win.detailBusy = true;
    const n = ++win.detailAsk;
    win.mgr.call("detail", win.acctOf(it), { item: it.id, secret: secret === undefined ? null : secret }, (ok, d, err) => {
      if (n !== win.detailAsk) return;
      win.detailBusy = false;
      if (!ok) {
        if (err && err.kind === "locked") { win.mgr.refresh(win.acctOf(it)); return; }
        win.detailErr = C.failWords(err);
        return;
      }
      if (d.reprompt && secret !== undefined) { win.say("Wrong master password", true); return; }
      win.detail = d;
      if (d.sections && d.sections.some((s) => s.fields.some((f) => f.kind === "totp"))) win.loadCode();
    });
  }
  function reprompt(secret) { win.loadDetail(secret); }
  function loadCode() {
    const it = win.item;
    if (!it || !win.visible) return;
    const f = win.fieldWith("totp");
    win.mgr.call("totp", win.acctOf(it), { item: it.id, ref: f ? f.ref : "totp" }, (ok, c) => {
      if (ok && win.item === it) win.code = c;
    });
  }
  function fieldWith(role) {
    if (!win.detail) return null;
    for (const s of win.detail.sections || [])
      for (const f of s.fields) if (f.role === role || (role === "totp" && f.kind === "totp")) return f;
    return null;
  }
  // nothing kept from before: the window hiding, an account locking
  function forget() {
    win.bigValue = "";
    win.genOpen = false;
    if (win.editing) { win.editing = false; win.editSt = null; }
    win.revealed = ({});
    win.code = null;
    win.detail = null;
    win.lastKey = "";
  }
  Connections {
    target: win.mgr
    function onLocked(id) { if (id === "" || (win.item && win.item.acct === id)) win.forget(); }
    function onUnlocked(id) { if (win.lockTarget === id) win.lockTarget = ""; Qt.callLater(win.refocus); }
  }

  // ── WHAT A FIELD DOES ──────────────────────────────────────────────────
  property string copiedRef: ""
  Timer { id: copiedTimer; interval: 1600; onTriggered: win.copiedRef = "" }
  function copyField(f) {
    const it = win.item;
    if (!f || !it) return;
    const said = (what, clears) => {
      win.copiedRef = f.ref;
      copiedTimer.restart();
      win.say("Copied " + what + (clears ? " — cleared from the clipboard in " + win.mgr.clearAfter + " s" : ""));
    };
    if (f.kind === "totp") {
      win.mgr.call("copy", win.acctOf(it), { item: it.id, ref: f.ref, totp: true }, (ok, r, err) => {
        if (ok) said("the one-time code", false); else win.failed(err, () => win.copyField(f));
      });
    } else if (f.secret) {
      win.mgr.call("copy", win.acctOf(it), { item: it.id, ref: f.ref, clear: win.mgr.clearAfter }, (ok, r, err) => {
        if (ok) said(f.label, win.mgr.clearAfter > 0); else win.failed(err, () => win.copyField(f));
      });
    } else {
      win.mgr.call("copyText", null, { text: f.value }, (ok, r, err) => {
        if (ok) said(f.label, false); else win.failed(err, () => win.copyField(f));
      });
    }
    win.mgr.used(it);
  }
  function copyRole(role) {
    const f = win.fieldWith(role);
    if (f) win.copyField(f);
    else win.say(win.item ? "This item has no " + (role === "totp" ? "one-time password" : role) : "Nothing chosen", true);
  }
  function revealField(f) {
    const it = win.item;
    if (!f || !it) return;
    if (win.revealed[f.ref] !== undefined) {
      const o = Object.assign({}, win.revealed);
      delete o[f.ref];
      win.revealed = o;
      return;
    }
    win.mgr.call("reveal", win.acctOf(it), { item: it.id, ref: f.ref }, (ok, r, err) => {
      if (!ok) { win.say(C.failWords(err), true); return; }
      if (win.item !== it) return;
      const o = Object.assign({}, win.revealed);
      o[f.ref] = r.value;
      win.revealed = o;
      revealTimer.restart();
    });
  }
  // a revealed secret goes back to dots after a minute on its own
  Timer { id: revealTimer; interval: 60000; onTriggered: win.revealed = ({}) }
  function openUrl(u) {
    const url = /^[a-z][a-z0-9+.-]*:/i.test(u) ? u : "https://" + u;
    Quickshell.execDetached(["xdg-open", url]);
  }
  function website() {
    const it = win.item;
    const f = win.detail ? (win.detail.sections || []).flatMap((s) => s.fields).find((x) => x.kind === "url") : null;
    if (f) win.openUrl(f.value);
    else if (it && it.host) win.openUrl(it.host);
    else win.say("This item has no website", true);
  }

  // ── THE MENUS ──────────────────────────────────────────────────────────
  // what the open menu is about, for its HeldRing: "i:<key>", "f:<ref>",
  // "a:<id>", "detail"
  property string menuHeld: ""
  function itemMenu(it, x, y, held) {
    if (!it) return;
    const user = !!it.sub, codes = it.totp !== false && it.kind === "login";
    const fav = win.isFav(it);
    if (win.inTrash) { win.trashMenu(it, x, y); return; }
    win.menuHeld = held || "i:" + C.keyOf(it);
    menu.open(x, y, [
      { text: "Copy password", icon: "\u{F018F}", mark: "ctrl c", run: () => win.copyRole("password") },
      { text: "Copy username", icon: "", mark: "ctrl shift c", enabled: user, run: () => win.copyRole("username") },
      { text: "Copy one-time code", icon: "\u{F097F}", mark: "ctrl alt c", enabled: codes, run: () => win.copyRole("totp") },
      { isSeparator: true },
      { text: "Open the website", icon: "", mark: "ctrl o", enabled: !!it.host, run: () => win.website() },
      { text: fav ? "Leave favourites" : "Add to favourites", icon: fav ? "" : "", mark: "ctrl d", run: () => win.toggleFav(it) },
      { isSeparator: true },
      { text: "Edit", icon: "\uF044", mark: "ctrl e", enabled: win.canEdit(it), run: () => win.editItem() },
      { text: "Duplicate", icon: "\u{F0191}", enabled: win.canDuplicate(it), run: () => win.duplicateItem(it) },
      { text: "Show the password in large type", icon: "\u{F027F}", enabled: !!win.fieldWith("password"), run: () => win.largeType() },
      { isSeparator: true },
      { text: "Lock " + (win.acctOf(it).name || "its account"), icon: "\uF023", run: () => win.mgr.lock(win.acctOf(it)) },
    ].concat(C.deleteWord(win.infoOf(it)) === "" ? [] : [
      { text: C.deleteWord(win.infoOf(it)) + "…", icon: "\u{F0A7A}", mark: "delete", danger: true, run: () => win.deleteItem(it, false) }]));
  }
  // in the trash, what can be done is bring it back or let it go
  function trashMenu(it, x, y) {
    win.menuHeld = "i:" + C.keyOf(it);
    menu.open(x, y, [
      { text: "Restore", icon: "\u{F099B}", run: () => win.restoreItem(it) },
      { isSeparator: true },
      { text: "Delete forever…", icon: "\u{F0A7A}", danger: true, run: () => win.deleteItem(it, true) }]);
  }
  function menuAt(x, y, items) { menu.open(x, y, items); }
  function fieldMenu(f, x, y) {
    if (!f) return;
    win.menuHeld = "f:" + f.ref;
    const items = [{ text: "Copy " + f.label, icon: "\u{F018F}", run: () => win.copyField(f) }];
    if (f.secret && f.kind !== "totp")
      items.push({ text: win.revealed[f.ref] !== undefined ? "Hide" : "Reveal", icon: "", run: () => win.revealField(f) });
    if (f.kind === "url") items.push({ text: "Open in the browser", icon: "", run: () => win.openUrl(f.value) });
    if (f.kind === "email") items.push({ text: "Write to " + f.value, icon: "", run: () => win.openUrl("mailto:" + f.value) });
    menu.open(x, y, items);
  }
  function accountMenu(a, x, y) {
    const st = win.mgr.states[a.id] || {};
    const i = win.mgr.accounts.indexOf(a);
    win.menuHeld = "a:" + a.id;
    menu.open(x, y, [
      st.unlocked ? { text: "Lock", icon: "", run: () => win.mgr.lock(a) }
                  : { text: "Unlock…", icon: "", run: () => { win.setScope({ shelf: "all", acct: a.id }); } },
      { text: "Sync", icon: "", enabled: !!st.unlocked && a.kind !== "keepass", run: () => win.syncAcct(a) },
      { isSeparator: true },
      { text: "Rename…", icon: "", run: () => win.renameAccount(a) },
      { text: "Move up", icon: "", enabled: i > 0, run: () => win.mgr.move(a, -1) },
      { text: "Move down", icon: "", enabled: i < win.mgr.accounts.length - 1, run: () => win.mgr.move(a, 1) },
      { isSeparator: true },
      { text: "Remove…", icon: "", danger: true, run: () => win.removeAccount(a) },
    ]);
  }
  // the head's account chip: which accounts the window shows
  function scopeMenu() {
    const items = [{ text: "Every account", icon: win.scope.acct ? "" : "",
                     run: () => win.setScope(Object.assign({}, win.scope, { acct: "", folder: "", tag: "" })) }];
    for (const a of win.mgr.accounts) {
      const st = win.mgr.states[a.id] || {};
      items.push({ text: a.name + (st.unlocked ? "" : "  (locked)"), icon: win.scope.acct === a.id ? "" : C.platform(a.kind).glyph,
                   run: () => win.setScope({ shelf: "all", acct: a.id }) });
    }
    items.push({ isSeparator: true }, { text: "Add an account…", icon: "\uF067", mark: "ctrl shift n", run: () => win.addAccount() },
               { text: "Password generator…", icon: "\u{F076E}", mark: "ctrl g", run: () => win.openGenerator(null) },
               { text: "Settings…", icon: "\u{F08BB}", run: () => win.setOpen = true });
    const p = acctChip.mapToItem(stage, 0, acctChip.height + 4);
    win.menuHeld = "chip";
    menu.open(p.x, p.y, items);
  }
  function lockAfterMenu(x, y) {
    const opts = [[1, "1 minute"], [5, "5 minutes"], [10, "10 minutes"], [30, "30 minutes"], [60, "an hour"], [0, "Never"]];
    menu.open(x, y, opts.map((o) => ({ text: o[0] === 0 ? "Never on its own" : "After " + o[1], icon: win.mgr.lockAfter === o[0] ? "" : "",
                                         run: () => win.mgr.set("lockAfter", o[0]) })));
  }

  // ── ACCOUNTS: ADDED, SIGNED IN, REMOVED ────────────────────────────────
  property bool adding: false
  function addAccount() {
    win.mgr.loadPlatforms();
    win.adding = true;
  }
  function choosePlatform(kind) {
    win.adding = false;
    const info = win.mgr.platformInfo(kind);
    const p = C.platform(kind);
    if (info && !info.installed) {
      cards.card_({ question: "Install " + info.pkg + "?", glyph: p.glyph, ink: Zenon[p.ink],
        detail: p.name + " is read through " + info.cli + ", which is not installed. Ceres installs it"
          + (info.aur ? " from the AUR" : "") + " — it asks for your password — then you sign in.",
        choices: [{ label: "Install " + info.pkg, ink: Zenon.cyan, run: () => win.mgr.install(kind, (ok) => { if (ok) win.askSetup(kind); }) },
                  { label: "Cancel", ink: Zenon.muted }] });
      return;
    }
    win.askSetup(kind);
  }
  // `again`: an account already here whose platform is signed out (a new
  // tool for it, bw after rbw) — the same questions, the account kept
  function askSetup(kind, how, again) {
    if (kind === "proton" && !how) {
      cards.card_({ question: "Sign in to Proton Pass", glyph: C.platform(kind).glyph, ink: Zenon.magenta,
        detail: "In your browser — the way for SSO and security keys — or here, with your email and password.",
        choices: [{ label: "Use the browser", ink: Zenon.cyan, run: () => win.protonBrowser(again) },
                  { label: "Sign in here", ink: Zenon.muted, run: () => win.askSetup(kind, "here", again) },
                  { label: "Cancel", ink: Zenon.muted }] });
      return;
    }
    const form = C.setupForm(kind, how);
    const p = C.platform(kind);
    const st = again ? win.mgr.states[again.id] || {} : {};
    const fields = form.fields.filter((f) => !(again && f.key === "name"))
      .map((f) => again && again[f.key] ? Object.assign({}, f, { value: again[f.key] })
                : again && f.key === "email" && st.user ? Object.assign({}, f, { value: st.user }) : f);
    cards.ask({ title: again ? "Sign in to " + again.name : form.title, glyph: p.glyph, ink: Zenon[p.ink],
      detail: form.detail, fields: fields, toggles: kind === "keepass" && !again
        ? [{ key: "create", label: "Make a new database there", value: false }] : [],
      verb: form.then2 === "setup" ? "Continue" : again ? "Sign in" : "Add",
      then: (v) => {
        const values = Object.assign({ how: how }, v);
        // the password on its own card, after the fields: 1Password's and
        // Bitwarden's sign-in needs it, and a new KeePass database is made
        // with one
        const pw = form.then2 === "setup" || (kind === "keepass" && v.create);
        if (!pw) { win.runSetup(kind, values, null, again); return; }
        cards.ask({ title: kind === "keepass" ? "A password for the new database" : "Your " + p.name + " password",
          glyph: "\uF023", ink: Zenon.red,
          secret: { key: "pw", prompt: kind === "keepass" ? "input a master password" : "input your master password",
                    purpose: kind === "keepass" ? "locks " + (v.path || "the database") : "signs " + (v.email || "you") + " in to " + p.name },
          verb: kind === "keepass" ? "Make it" : "Sign in",
          then: (s) => win.runSetup(kind, values, s.pw, again) });
      } });
  }
  property int setupCard: -1
  function runSetup(kind, values, secret, again) {
    const p = C.platform(kind);
    win.busyText = (again ? "Signing in to " : "Adding ") + p.name + "…";
    const done = (ok, err, acct) => {
      win.busyText = "";
      if (win.setupCard >= 0) { cards.dropCard(win.setupCard); win.setupCard = -1; }
      if (!ok && err && err.kind === "2fa") {
        // two-step login: the code, and the way it came — then the same
        // sign-in again with it
        cards.ask({ title: "Two-step login", glyph: "\u{F0565}", ink: Zenon.cyan, detail: C.failWords(err),
          fields: [{ key: "method", label: "Code from", options: [["app", "Authenticator app"], ["email", "Email"], ["key", "YubiKey"]],
                     value: values.method || "app" },
                   { key: "code", label: "Code", hint: "123456" }],
          verb: "Sign in", then: (v) => win.runSetup(kind, Object.assign({}, values, v), secret, again) });
        return;
      }
      if (!ok) {
        cards.card_({ question: again ? "Not signed in to " + p.name : p.name + " was not added", glyph: p.glyph, ink: Zenon.red,
          detail: C.failWords(err),
          choices: [{ label: "Try again", ink: Zenon.cyan, run: () => win.askSetup(kind, values.how, again) },
                    { label: "Close", ink: Zenon.muted }] });
        return;
      }
      win.say((again ? "Signed in to " : "Added ") + acct.name);
      win.setScope({ shelf: "all", acct: acct.id });
    };
    if (again) win.mgr.resetup(again, values, secret, done);
    else win.mgr.addAccount(kind, values, secret, done);
  }
  // A failure that is only a package missing (the daemon's "needs": wtype,
  // wl-clipboard, the QR scan's zbar grim slurp): Ceres installs them, then
  // `retry` does what was asked again. Anything else is said.
  function failed(err, retry) {
    if (err && err.kind === "needs" && err.pkgs && err.pkgs.length > 0) {
      cards.card_({ question: "Install " + err.pkgs.join(", ") + "?", glyph: "\uF019", ink: Zenon.cyan,
        detail: C.failWords(err) + ". Ceres installs " + (err.pkgs.length > 1 ? "them" : "it") + " — it asks for your password.",
        choices: [{ label: "Install", ink: Zenon.cyan, run: () => Ceres.install(err.pkgs, "for calypso", (ok) => { if (ok && retry) retry(); }) },
                  { label: "Cancel", ink: Zenon.muted }] });
      return;
    }
    if (err && err.kind === "cancelled") return;
    win.say(C.failWords(err), true);
  }
  // a tool the account's platform needs, missing: Ceres installs it, then
  // the account is asked again (and signed in, if it is signed out)
  function installFor(acct) {
    win.mgr.install(acct.kind, (ok) => {
      if (!ok) return;
      win.mgr.refresh(acct, () => {
        const st = win.mgr.states[acct.id] || {};
        if (st.installed !== false && st.configured === false) win.askSetup(acct.kind, "", acct);
      });
    });
  }
  // Proton's browser sign-in: its address on a card, Open and Copy, up until
  // pass-cli says the sign-in landed
  function protonBrowser(again) {
    win.setupCard = cards.card_({ question: "Sign in to Proton Pass in your browser", glyph: C.platform("proton").glyph, ink: Zenon.magenta,
      detail: "Waiting for pass-cli to give the address…", choices: [{ label: "Cancel", ink: Zenon.muted }] });
    win.runSetup("proton", { how: "browser" }, null, again);
  }
  Connections {
    target: win.mgr
    function onSignInUrl(id, url) {
      if (win.setupCard >= 0) cards.dropCard(win.setupCard);
      win.setupCard = cards.card_({ question: "Sign in to Proton Pass in your browser", glyph: C.platform("proton").glyph, ink: Zenon.magenta,
        detail: "Open this address, sign in there, and calypso carries on by itself:\n" + url,
        choices: [{ label: "Open", ink: Zenon.cyan, keep: true, run: () => win.openUrl(url) },
                  { label: "Copy", ink: Zenon.muted, keep: true, run: () => win.mgr.call("copyText", null, { text: url }, () => win.say("Copied the address")) },
                  { label: "Cancel", ink: Zenon.muted }] });
    }
  }
  function renameAccount(a) {
    cards.ask({ title: "Rename " + a.name, glyph: C.platform(a.kind).glyph, ink: Zenon[C.platform(a.kind).ink],
      fields: [{ key: "name", label: "Name", value: a.name }], verb: "Rename",
      then: (v) => { if (v.name.trim() !== "") win.mgr.rename(a, v.name.trim()); } });
  }
  function removeAccount(a) {
    const p = C.platform(a.kind);
    const signs = a.kind === "onepassword" || a.kind === "proton";
    cards.card_({ question: "Remove " + a.name + "?", glyph: p.glyph, ink: Zenon.red,
      detail: "It leaves calypso. Nothing in the vault itself is touched"
        + (signs ? " — and " + p.name + " can be signed out on this machine too." : "."),
      choices: (signs ? [{ label: "Remove and sign out", ink: Zenon.red, run: () => win.mgr.removeAccount(a, true) }] : [])
        .concat([{ label: "Remove", ink: Zenon.red, run: () => win.mgr.removeAccount(a, false) },
                 { label: "Cancel", ink: Zenon.muted }]) });
  }
  property string busyText: ""
  function syncAcct(a) {
    win.busyText = "Syncing " + a.name + "…";
    win.mgr.sync(a, (ok, err) => {
      win.busyText = "";
      if (ok) win.say("Synced " + a.name); else win.say(C.failWords(err), true);
    });
  }
  function syncAll() {
    const open = win.mgr.accounts.filter((a) => (win.mgr.states[a.id] || {}).unlocked && a.kind !== "keepass");
    if (open.length === 0) { win.say("Nothing open to sync", true); return; }
    let left = open.length;
    win.busyText = "Syncing…";
    for (const a of open) win.mgr.sync(a, () => { if (--left === 0) { win.busyText = ""; win.say("Synced"); } });
  }

  // ── WRITING: NEW ITEMS, EDITS, THE TRASH ────────────────────────────────
  function infoOf(it) { return it && win.mgr ? win.mgr.platformInfo(win.acctOf(it).kind) : null; }
  function canEdit(it) { return !!it && !win.inTrash && C.can(win.infoOf(it), "edit") && !!win.detail && !win.detail.reprompt; }
  function canDuplicate(it) { return !!it && !win.inTrash && C.canCreate(win.infoOf(it), it.kind); }
  function canAttach(it) { return !!it && !win.inTrash && C.can(win.infoOf(it), "attachments") && !!win.detail; }
  // the open accounts a new item of `kind` may go in
  function writable(kind) {
    return !win.mgr ? [] : win.mgr.accounts.filter((a) => (win.mgr.states[a.id] || {}).unlocked
      && C.canCreate(win.mgr.platformInfo(a.kind), kind));
  }
  function newItemMenu() {
    const kinds = C.KINDS.filter((k) => win.writable(k.id).length > 0);
    if (kinds.length === 0) { win.say(win.mgr.anyOpen ? "None of the open accounts can make items from here" : "Unlock an account first", true); return; }
    const p = newBtn.mapToItem(stage, 0, newBtn.height + 4);
    menu.open(p.x, p.y, kinds.map((k) => ({ text: "New " + k.one.toLowerCase(), icon: k.glyph, run: () => win.newItem(k.id) })));
  }
  property bool editing: false
  property var editSt: null
  property bool saving: false
  function newItem(kind) {
    const w = win.writable(kind);
    const acct = w.find((a) => a.id === win.scope.acct) || w[0];
    if (!acct) return;
    win.editSt = C.editState(null, kind, acct.id, win.scope.folder || "");
    win.editing = true;
  }
  function editItem() {
    if (!win.canEdit(win.item)) return;
    const st = C.editState(win.detail, "", win.item.acct);
    st.id = win.item.id;
    st.fav = !!win.item.fav;
    win.editSt = st;
    win.editing = true;
  }
  function editKey(e) {
    const ctrl = e.modifiers & Qt.ControlModifier;
    if (ctrl && e.key === Qt.Key_S) { win.saveEdit(); return true; }
    if (ctrl && e.key === Qt.Key_G) { win.openGenerator(null); return true; }
    if (e.key === Qt.Key_Escape) { win.cancelEdit(); return true; }
    return false;
  }
  function saveEdit() {
    const st = win.editSt;
    if (!st || win.saving) return;
    const draft = C.draftOf(st);
    if (draft.title === "") { win.say("It needs a name", true); return; }
    const acct = win.mgr.accountOf(st.acct);
    win.saving = true;
    win.mgr.save(acct, st.id, draft, (ok, res, err) => {
      win.saving = false;
      if (!ok) { win.failed(err, null); return; }
      win.editing = false;
      win.editSt = null;
      win.say(st.id ? "Saved" : "Made " + draft.title);
      // the item, as it is now: picked when the list comes back
      win.detail = null;
      if (res && res.id) win.want(st.acct + "\u0001" + res.id);
      Qt.callLater(win.loadDetail);
    });
  }
  // `then`: what to do once the editor has gone (a scope change asked for
  // while editing)
  function cancelEdit(then) {
    const go = () => { win.editing = false; win.editSt = null; win.refocus(); if (then) then(); };
    if (editorLoader.item && editorLoader.item.dirty) {
      cards.card_({ question: "Leave without saving?", glyph: "\uF044", ink: Zenon.yellow,
        detail: "What was changed here is lost.",
        choices: [{ label: "Discard", ink: Zenon.red, run: go }, { label: "Keep editing", ink: Zenon.muted }] });
      return;
    }
    go();
  }
  function revealForEdit(ref, cb) {
    const st = win.editSt;
    if (!st || !st.id) return;
    win.mgr.call("reveal", win.mgr.accountOf(st.acct), { item: st.id, ref: ref }, (ok, r, err) => {
      if (ok) cb(r.value); else win.failed(err, null);
    });
  }
  function scanQr(cb) {
    win.say("Draw a box round the QR code");
    win.mgr.call("scanQr", null, {}, (ok, r, err) => {
      if (ok) { cb(r.uri); win.say("Read the one-time password"); }
      else win.failed(err, () => win.scanQr(cb));
    });
  }
  function deleteItem(it, permanent) {
    if (!it) return;
    const info = win.infoOf(it);
    const word = permanent ? "Delete forever" : C.deleteWord(info);
    const gone = permanent || (info && info.can && info.can.delete === "delete");
    cards.card_({ question: word + " " + it.title + "?", glyph: "\u{F0A7A}", ink: Zenon.red,
      detail: gone ? "It cannot be brought back." : info.can.delete === "archive"
        ? "Into 1Password's archive — it can be brought back from there in 1Password."
        : "Into " + C.platform(win.acctOf(it).kind).name + "'s trash, where it can be restored.",
      choices: [{ label: word, ink: Zenon.red, run: () => win.mgr.remove(win.acctOf(it), it.id, permanent, (ok, r, err) => {
                  if (ok) win.say((gone ? "Deleted " : "Moved ") + it.title + (gone ? "" : " out of the way")); else win.failed(err, null); }) },
                { label: "Cancel", ink: Zenon.muted }] });
  }
  function restoreItem(it) {
    win.mgr.restore(win.acctOf(it), it.id, (ok, r, err) => { if (ok) win.say("Restored " + it.title); else win.failed(err, null); });
  }
  function duplicateItem(it) {
    win.mgr.duplicate(win.acctOf(it), it.id, (ok, r, err) => {
      if (!ok) { win.failed(err, null); return; }
      if (r && r.id) win.want(it.acct + "\u0001" + r.id);
      win.say("Made a copy of " + it.title);
    });
  }
  // ── the password in large type ──
  property string bigValue: ""
  property string bigLabel: ""
  function largeType() {
    const f = win.fieldWith("password");
    const it = win.item;
    if (!f || !it) return;
    win.mgr.call("reveal", win.acctOf(it), { item: it.id, ref: f.ref }, (ok, r, err) => {
      if (!ok) { win.failed(err, null); return; }
      win.bigLabel = it.title + "  \u00b7  " + f.label;
      win.bigValue = r.value;
    });
  }
  // ── the generator, on its sheet; `cb` a field waiting for it ──
  property bool genOpen: false
  property var genUse: null
  function openGenerator(cb) { win.genUse = cb || null; win.genOpen = true; genPane.make(); }
  property bool setOpen: false
  // ── files kept with an item ──
  function saveAttachment(att) {
    const it = win.item;
    if (!it || !win.mgr.fileManager) return;
    win.mgr.fileManager.choose(false, Quickshell.env("HOME"), (paths) => {
      if (!paths || paths.length === 0) return;
      win.mgr.call("attachmentSave", win.acctOf(it), { item: it.id, att: att.id, path: paths[0] }, (ok, r, err) => {
        if (ok) win.say("Saved " + att.name); else win.failed(err, null);
      });
    }, att.name);
  }
  function addAttachment() {
    const it = win.item;
    if (!it || !win.mgr.fileManager) return;
    win.mgr.fileManager.choose(false, Quickshell.env("HOME"), (paths) => {
      if (!paths || paths.length === 0) return;
      win.busyText = "Attaching…";
      win.mgr.call("attachmentAdd", win.acctOf(it), { item: it.id, path: paths[0] }, (ok, r, err) => {
        win.busyText = "";
        if (!ok) { win.failed(err, null); return; }
        win.say("Attached " + paths[0].replace(/.*\//, ""));
        win.loadDetail();
      });
    });
  }
  function removeAttachment(att) {
    const it = win.item;
    cards.confirm({ question: "Remove " + att.name + "?", glyph: "\u{F03E2}", ink: Zenon.red,
      detail: "It goes from the item for good.", verb: "Remove",
      then: () => win.mgr.call("attachmentRemove", win.acctOf(it), { item: it.id, att: att.id }, (ok, r, err) => {
        if (!ok) { win.failed(err, null); return; }
        win.say("Removed " + att.name);
        win.loadDetail();
      }) });
  }

  // ── THE LOCK IN VIEW ───────────────────────────────────────────────────
  // the account the lock pane is for: the one in view if it is locked; with
  // every account locked, the one chosen on its switch (else the first)
  property string lockTarget: ""
  readonly property var lockedAccts: win.mgr ? win.mgr.accounts.filter((a) => !(win.mgr.states[a.id] || {}).unlocked) : []
  readonly property bool noneOpen: !!win.mgr && win.mgr.accounts.length > 0 && !win.mgr.anyOpen
  readonly property var lockAcct: {
    if (!win.mgr) return null;
    if (win.scope.acct) {
      const a = win.mgr.accountOf(win.scope.acct);
      return a && !(win.mgr.states[a.id] || {}).unlocked ? a : null;
    }
    if (!win.noneOpen) return null;
    return win.lockedAccts.find((a) => a.id === win.lockTarget) || win.lockedAccts[0] || null;
  }
  readonly property bool welcoming: !!win.mgr && win.mgr.accounts.length === 0

  // ── SAID ONCE ──────────────────────────────────────────────────────────
  property string said: ""
  property bool saidBad: false
  function say(t, bad) { win.said = t; win.saidBad = !!bad; sayTimer.restart(); }
  Timer { id: sayTimer; interval: 2600; onTriggered: win.said = "" }

  // ── KEYS ───────────────────────────────────────────────────────────────
  function refocus() {
    if (cards.carding || win.adding || win.genOpen || win.setOpen || win.bigValue !== "") { if (!cards.carding) keySink.forceActiveFocus(); return; }
    if (win.editing) { if (editorLoader.item) editorLoader.item.focusFirst(); return; }
    if (win.lockAcct) keySink.forceActiveFocus();
    else searchField.forceActiveFocus();
  }
  function unwind() {
    if (win.adding) { win.adding = false; win.refocus(); return; }
    if (win.query !== "") { searchField.text = ""; return; }
    if (win.scope.acct || win.scope.kind || win.scope.folder || win.scope.tag || win.scope.shelf !== "all") {
      win.setScope({ shelf: "all" });
      return;
    }
    win.visible = false;
  }
  // what every key means, whichever of the window's things has the focus
  function key(e) {
    const ctrl = e.modifiers & Qt.ControlModifier, shift = e.modifiers & Qt.ShiftModifier,
          alt = e.modifiers & Qt.AltModifier;
    if (win.adding) {
      if (e.key === Qt.Key_Escape) { win.unwind(); return true; }
      return addGrid.key(e);
    }
    if (win.genOpen) return genPane.key(e) || true;
    if (win.bigValue !== "") { win.bigValue = ""; return true; }
    if (win.setOpen) { if (e.key === Qt.Key_Escape || e.key === Qt.Key_Return) win.setOpen = false; return true; }
    if (win.editing) return win.editKey(e);
    if (ctrl && e.key === Qt.Key_L) { win.mgr.lockAll(); return true; }
    if (ctrl && shift && e.key === Qt.Key_N) { win.addAccount(); return true; }
    if (ctrl && e.key === Qt.Key_N) { win.newItemMenu(); return true; }
    if (ctrl && e.key === Qt.Key_G) { win.openGenerator(null); return true; }
    if (win.lockAcct && !win.welcoming) {
      if (e.key === Qt.Key_Escape && lockPane.key(e)) return true;
      if (e.key === Qt.Key_Escape) { win.unwind(); return true; }
      return lockPane.key(e);
    }
    if (e.key === Qt.Key_Escape) { win.unwind(); return true; }
    if (ctrl && e.key === Qt.Key_C) { win.copyRole(alt ? "totp" : shift ? "username" : "password"); return true; }
    if (ctrl && e.key === Qt.Key_R) { const f = win.fieldWith("password"); if (f) win.revealField(f); return true; }
    if (ctrl && e.key === Qt.Key_O) { win.website(); return true; }
    if (ctrl && e.key === Qt.Key_D) { win.toggleFav(win.item); return true; }
    if (ctrl && e.key === Qt.Key_E) { win.editItem(); return true; }
    if (e.key === Qt.Key_Delete && win.item) { if (win.inTrash) win.deleteItem(win.item, true); else if (C.deleteWord(win.infoOf(win.item)) !== "") win.deleteItem(win.item, false); return true; }
    if (ctrl && e.key === Qt.Key_S) { win.syncAll(); return true; }
    if (ctrl && (e.key === Qt.Key_F)) { searchField.forceActiveFocus(); searchField.selectAll(); return true; }
    if (ctrl && e.key === Qt.Key_Tab) { win.mgr.set("sort", win.sort === "name" ? "recent" : "name"); return true; }
    if (ctrl && e.key >= Qt.Key_1 && e.key <= Qt.Key_5) { win.setScope({ shelf: C.SHELVES[e.key - Qt.Key_1].id }); return true; }
    if (e.key === Qt.Key_Down || (ctrl && e.key === Qt.Key_J)) { win.move(1); return true; }
    if (e.key === Qt.Key_Up || (ctrl && e.key === Qt.Key_K)) { win.move(-1); return true; }
    if (e.key === Qt.Key_PageDown) { win.move(8); return true; }
    if (e.key === Qt.Key_PageUp) { win.move(-8); return true; }
    if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { win.copyRole(win.item && win.item.kind === "note" ? "" : "password"); return true; }
    return false;
  }
  Item {
    id: keySink
    focus: true
    Keys.onPressed: (e) => {
      if (win.key(e)) { e.accepted = true; return; }
      // typing goes to the search
      if (!win.lockAcct && e.text && e.text.length > 0 && !(e.modifiers & (Qt.ControlModifier | Qt.MetaModifier))
          && e.text.charCodeAt(0) >= 32) {
        searchField.forceActiveFocus();
        searchField.text += e.text;
        e.accepted = true;
      }
    }
    Keys.onReleased: (e) => { if (win.lockAcct) lockPane.keyUp(e); }
  }

  // ── THE STAGE ──────────────────────────────────────────────────────────
  Item {
    id: stage
    anchors.fill: parent

    Rectangle { z: -1; x: side.width; width: parent.width - x; height: parent.height; color: Zenon.layerBg }

    // ── the sidebar ──────────────────────────────────────────────────────
    Item {
      id: side
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: 250

      Rectangle { anchors.fill: parent; color: Zenon.alpha(Zenon.tabAwayInk, Zenon.tabAway(Zenon.layerBg.a)) }
      Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Zenon.border }

      // which accounts are in view — a menu of them (scopeMenu)
      Rectangle {
        id: acctChip
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        height: 58
        radius: Zenon.windowRadius
        color: Zenon.wash(0.04)
        border.width: 1
        border.color: Zenon.border
        readonly property var acct: win.mgr && win.scope.acct ? win.mgr.accountOf(win.scope.acct) : null
        ItemTile {
          id: chipTile
          x: 12
          anchors.verticalCenter: parent.verticalCenter
          size: 34
          glyph: acctChip.acct ? C.platform(acctChip.acct.kind).glyph : ""
          ink: acctChip.acct ? C.platform(acctChip.acct.kind).ink : "cyan"
        }
        Column {
          anchors.left: chipTile.right
          anchors.leftMargin: 11
          anchors.right: chipArrow.left
          anchors.rightMargin: 8
          anchors.verticalCenter: parent.verticalCenter
          spacing: 2
          Text {
            width: parent.width
            elide: Text.ElideRight
            text: acctChip.acct ? acctChip.acct.name : "Calypso"
            color: Zenon.ink
            font.family: Zenon.face
            font.weight: Font.Bold
            font.pixelSize: Zenon.px(16)
          }
          Text {
            width: parent.width
            elide: Text.ElideRight
            text: !win.mgr ? "" : acctChip.acct ? C.platform(acctChip.acct.kind).name
              : win.mgr.accounts.length === 0 ? "No accounts yet"
              : win.mgr.accounts.length === 1 ? "1 account" : "Every account (" + win.mgr.accounts.length + ")"
            color: Zenon.muted
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(13)
          }
        }
        Text {
          id: chipArrow
          anchors.right: parent.right
          anchors.rightMargin: 12
          anchors.verticalCenter: parent.verticalCenter
          text: ""
          color: win.menuHeld === "chip" && menu.isOpen ? Zenon.cyan : Zenon.muted
          rotation: win.menuHeld === "chip" && menu.isOpen ? 180 : 0
          Behavior on rotation { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.travelEase } }
          font.family: Zenon.glyphFace
          font.pixelSize: Zenon.px(11)
        }
        MouseArea { id: chipPress; anchors.fill: parent; onClicked: win.scopeMenu() }
        Rectangle {
          anchors.fill: parent
          radius: parent.radius
          color: Zenon.wash(0.12)
          visible: chipPress.pressed || (win.menuHeld === "chip" && menu.isOpen)
        }
      }

      Flickable {
        id: sideFlick
        anchors.top: acctChip.bottom
        anchors.topMargin: 4
        anchors.bottom: addRow.top
        anchors.left: parent.left
        anchors.right: parent.right
        contentHeight: sideCol.implicitHeight + 12
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        interactive: contentHeight > height

        Column {
          id: sideCol
          width: sideFlick.width
          spacing: 1

          // the shelves
          SideHead { first: true; ruled: false; label: "Vault" }
          Repeater {
            model: C.SHELVES
            delegate: ShelfRow {
              required property var modelData
              width: sideCol.width
              radius: 0
              indent: 18
              glyph: modelData.glyph
              label: modelData.label
              here: !win.scope.kind && !win.scope.folder && !win.scope.tag && (win.scope.shelf || "all") === modelData.id
              fill: win.hiFill
              visible: modelData.id !== "trash" || (!!win.mgr && win.mgr.accounts.some((a) =>
                (win.mgr.states[a.id] || {}).unlocked && C.can(win.mgr.platformInfo(a.kind), "restore")))
              count: !win.mgr ? ""
                : modelData.id === "trash" ? (win.mgr.trashItems.length > 0 ? String(win.mgr.trashItems.length) : "")
                : modelData.id === "watch" ? (win.mgr.auditing ? "\u2026" : Object.keys(win.mgr.audits).length === 0 ? "" : String(C.count(win.mgr.items, { shelf: "watch", acct: win.scope.acct }, win.mgr.favs, win.mgr.flags)))
                : String(C.count(win.mgr.items, { shelf: modelData.id, acct: win.scope.acct }, win.mgr.favs))
              countInk: modelData.id === "watch" && Object.keys(win.mgr ? win.mgr.flags : {}).length > 0 ? Zenon.yellow : Zenon.muted
              onClicked: win.setScope({ shelf: modelData.id, acct: win.scope.acct })
            }
          }

          // the kinds there are
          SideHead { ruled: false; label: "Categories"; visible: kindRep.count > 0 }
          Repeater {
            id: kindRep
            model: win.mgr ? C.KINDS.filter((k) => C.count(win.mgr.items, { kind: k.id, acct: win.scope.acct }, win.mgr.favs) > 0) : []
            delegate: ShelfRow {
              required property var modelData
              width: sideCol.width
              radius: 0
              indent: 18
              glyph: modelData.glyph
              label: modelData.label
              here: win.scope.kind === modelData.id
              fill: win.hiFill
              count: String(C.count(win.mgr.items, { kind: modelData.id, acct: win.scope.acct }, win.mgr.favs))
              onClicked: win.setScope({ shelf: "all", kind: modelData.id, acct: win.scope.acct })
            }
          }

          // the accounts, each locked or open
          SideHead { ruled: false; label: "Accounts"; visible: !!win.mgr && win.mgr.accounts.length > 0 }
          Repeater {
            model: win.mgr ? win.mgr.accounts : []
            delegate: ShelfRow {
              id: acctRow
              required property var modelData
              readonly property var st: win.mgr.states[modelData.id] || {}
              width: sideCol.width
              radius: 0
              indent: 18
              glyph: C.platform(modelData.kind).glyph
              label: modelData.name
              here: win.scope.acct === modelData.id && !win.scope.kind && !win.scope.folder && !win.scope.tag && (win.scope.shelf || "all") === "all"
              fill: win.hiFill
              count: acctRow.st.busy || acctRow.st.loading ? "…"
                : acctRow.st.installed === false ? ""
                : acctRow.st.unlocked ? String(acctRow.st.count !== undefined ? acctRow.st.count : "") : ""
              countInk: acctRow.st.installed === false || acctRow.st.error ? Zenon.red : acctRow.st.unlocked ? Zenon.muted : Zenon.yellow
              onClicked: win.setScope({ shelf: "all", acct: modelData.id })
              MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.RightButton
                onClicked: (m) => { const p = mapToItem(stage, m.x, m.y); win.accountMenu(acctRow.modelData, p.x, p.y); }
              }
              HoverHandler { id: acctHover }
              HeldRing { anchors.fill: parent; anchors.margins: 2; radius: Zenon.windowRadius; on: win.menuHeld === "a:" + acctRow.modelData.id && menu.isOpen }
              // more about it, pointed at: the platform, who, the state
              Bubble {
                window: win
                target: acctRow
                shown: acctHover.hovered && !menu.isOpen
                cardWidth: 320
                lean: true
                Row {
                  spacing: 10
                  ItemTile { size: 30; glyph: C.platform(acctRow.modelData.kind).glyph; ink: C.platform(acctRow.modelData.kind).ink }
                  Column {
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                      text: acctRow.modelData.name
                      color: Zenon.ink
                      font.family: Zenon.face
                      font.weight: Font.Bold
                      font.pixelSize: Zenon.px(14)
                    }
                    Text {
                      text: C.platform(acctRow.modelData.kind).name + (acctRow.st.user ? "  ·  " + acctRow.st.user : "")
                      color: Zenon.muted
                      font.family: Zenon.face
                      font.weight: Zenon.weight
                      font.pixelSize: Zenon.px(12)
                    }
                  }
                }
                Text {
                  width: 280
                  wrapMode: Text.Wrap
                  text: acctRow.st.installed === false ? "Its tool is not installed — choose it again to install it"
                    : acctRow.st.error ? acctRow.st.error
                    : acctRow.st.unlocked ? "Open · " + (acctRow.st.count || 0) + " items" + (acctRow.st.server ? " · " + acctRow.st.server : "")
                    : "Locked" + (acctRow.st.note ? " · " + acctRow.st.note : "")
                  color: acctRow.st.installed === false || acctRow.st.error ? Zenon.red : acctRow.st.unlocked ? Zenon.green : Zenon.yellow
                  font.family: Zenon.face
                  font.weight: Zenon.weight
                  font.pixelSize: Zenon.px(12)
                }
              }
            }
          }

          // the folders (vaults, groups) of what is in view
          SideHead { ruled: false; label: "Folders"; visible: folderRep.count > 0 }
          Repeater {
            id: folderRep
            model: win.mgr ? C.folders(win.mgr.items.filter((i) => !win.scope.acct || i.acct === win.scope.acct)).slice(0, 60) : []
            delegate: ShelfRow {
              required property var modelData
              width: sideCol.width
              radius: 0
              indent: 18 + modelData.depth * 14
              glyph: ""
              label: modelData.leaf
              here: win.scope.folder === modelData.name
              fill: win.hiFill
              count: String(modelData.count)
              onClicked: win.setScope({ shelf: "all", acct: win.scope.acct, folder: modelData.name })
            }
          }
          SideHead { ruled: false; label: "Tags"; visible: tagRep.count > 0 }
          Repeater {
            id: tagRep
            model: win.mgr ? C.tags(win.mgr.items.filter((i) => !win.scope.acct || i.acct === win.scope.acct)).slice(0, 40) : []
            delegate: ShelfRow {
              required property var modelData
              width: sideCol.width
              radius: 0
              indent: 18
              glyph: ""
              label: modelData.name
              here: win.scope.tag === modelData.name
              fill: win.hiFill
              count: String(modelData.count)
              onClicked: win.setScope({ shelf: "all", acct: win.scope.acct, tag: modelData.name })
            }
          }
        }
      }
      ElasticScroll { anchors.fill: sideFlick; view: sideFlick }

      // adding one, at the sidebar's foot (as 1Password's "New Vault")
      ShelfRow {
        id: addRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 6
        radius: 0
        indent: 18
        glyph: ""
        label: "Add an account"
        countInk: Zenon.muted
        count: "ctrl n"
        here: win.adding
        fill: win.hiFill
        onClicked: win.addAccount()
      }
    }

    // ── the list ─────────────────────────────────────────────────────────
    Item {
      id: listCol
      anchors.left: side.right
      anchors.top: head.bottom
      anchors.bottom: foot.top
      width: Math.round(Math.min(400, Math.max(300, (win.width - side.width) * 0.34)))
      visible: !win.welcoming && !win.lockAcct && !win.watching
      // editing: the list waits (a click there would leave the edit)
      enabled: !win.editing
      opacity: win.editing ? 0.45 : 1
      Behavior on opacity { NumberAnimation { duration: Zenon.fast } }

      Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Zenon.border }

      ListView {
        id: list
        anchors.top: listBar.bottom
        anchors.topMargin: 6
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        clip: true
        bottomMargin: 8
        boundsBehavior: Flickable.StopAtBounds
        model: rowModel
        cacheBuffer: 600
        SelectBar {
          view: list
          host: win
          index: win.sel
          rowH: win.rowH
          // where the row really is: a ListView of rows of two heights
          // (with a heading, without) keeps its own count of where each
          // sits, and moves its origin as it builds them — a sum of
          // heights put the bar half a row off (user, 2026-10-12)
          rowY: {
            void [list.contentY, list.originY, list.count, win.rows, win.sel];
            const d = win.sel >= 0 ? list.itemAtIndex(win.sel) : null;
            if (!d) return win.tops.length > win.sel && win.sel >= 0 ? win.tops[win.sel] - list.originY : -1;
            return d.y - list.originY + (d.head !== "" ? win.secH : 0);
          }
          on: win.shown.length > 0
          color: win.hiFill
          radius: Zenon.windowRadius
          inset: 8
        }
        delegate: Item {
          id: rowItem
          required property string head
          required property int index
          readonly property var it: win.shown[index] || ({ title: "", sub: "", tags: [] })
          readonly property bool here: index === win.sel
          width: list.width
          height: win.rowH + (head !== "" ? win.secH : 0)
          // a heading over the first of its letter (or age)
          Text {
            visible: rowItem.head !== ""
            x: 18
            height: win.secH
            verticalAlignment: Text.AlignBottom
            bottomPadding: 6
            text: rowItem.head
            color: Zenon.muted
            font.family: Zenon.face
            font.weight: Font.DemiBold
            font.pixelSize: Zenon.px(12)
            font.letterSpacing: 0.6
          }
          Item {
            id: rowBody
            y: rowItem.head !== "" ? win.secH : 0
            width: parent.width
            height: win.rowH
            ItemTile {
              id: tile
              x: 18
              anchors.verticalCenter: parent.verticalCenter
              item: rowItem.it
              size: 34
              lit: rowItem.here
            }
            Column {
              anchors.left: tile.right
              anchors.leftMargin: 12
              anchors.right: marks.left
              anchors.rightMargin: 8
              anchors.verticalCenter: parent.verticalCenter
              spacing: 1
              Text {
                width: parent.width
                elide: Text.ElideRight
                textFormat: Text.StyledText
                text: C.highlight(rowItem.it.title, win.query, Zenon.cyan)
                color: rowItem.here ? Zenon.ink : Zenon.soft
                font.family: Zenon.face
                font.weight: Font.DemiBold
                font.pixelSize: Zenon.px(15)
              }
              Text {
                width: parent.width
                elide: Text.ElideRight
                visible: text !== ""
                text: rowItem.it.sub || rowItem.it.host || (win.scope.acct ? "" : (win.acctOf(rowItem.it).name || ""))
                color: Zenon.muted
                font.family: Zenon.face
                font.weight: Zenon.weight
                font.pixelSize: Zenon.px(13)
              }
            }
            Row {
              id: marks
              anchors.right: parent.right
              anchors.rightMargin: 18
              anchors.verticalCenter: parent.verticalCenter
              spacing: 6
              Text {
                visible: rowItem.it.totp === true
                text: "\u{F097F}"
                color: Zenon.alpha(Zenon.cyan, 0.8)
                font.family: Zenon.glyphFace
                font.pixelSize: Zenon.px(12)
              }
              Text {
                visible: win.isFav(rowItem.it)
                text: ""
                color: Zenon.sand
                font.family: Zenon.glyphFace
                font.pixelSize: Zenon.px(12)
              }
            }
            MouseArea {
              anchors.fill: parent
              acceptedButtons: Qt.LeftButton | Qt.RightButton
              onClicked: (m) => {
                if (m.button === Qt.RightButton) {
                  // right click is a question about the row: the cursor
                  // stays — but the menu's verbs act on the item in view,
                  // so the row is brought into view first
                  win.sel = rowItem.index;
                  const p = mapToItem(stage, m.x, m.y);
                  win.itemMenu(rowItem.it, p.x, p.y);
                  return;
                }
                win.sel = rowItem.index;
                win.refocus();
              }
              onDoubleClicked: win.copyRole("password")
            }
            HeldRing { anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8; anchors.topMargin: 1; anchors.bottomMargin: 1
                       radius: Zenon.windowRadius; on: menu.isOpen && win.menuHeld === "i:" + C.keyOf(rowItem.it) }
          }
        }
        EmptyMark {
          anchors.centerIn: parent
          visible: list.count === 0 && !!win.mgr && !win.mgr.loading
          filtered: win.query !== ""
          word: win.query !== "" ? "" : win.mgr && !win.mgr.anyOpen ? "Locked" : "Nothing here"
        }
        Working {
          anchors.centerIn: parent
          running: list.count === 0 && !!win.mgr && win.mgr.loading
          visible: running
        }
      }
      ElasticScroll { anchors.fill: list; view: list }
      Scrollbar { flick: list; anchors.right: list.right; anchors.top: list.top; anchors.bottom: list.bottom }
      ScrollEdge { view: list; below: true; follow: true; bar: foot }
      // ── WHAT SCROLLS UP GOES UNDER THE SEARCH AND THE HEAD ──
      // morpheus/ScrollEdge, as alexandria's glyph grid under its search
      // strip: the rows carry on, frosted, under this column's own chrome
      // (the search, the order switch) and on up under the window's head.
      // Before the chrome, so the chrome's translucent ground tints them.
      Item {
        id: listChrome
        y: -head.height
        width: parent.width
        height: head.height + list.y
      }
      ScrollEdge { view: list; follow: true; bar: listChrome }
      // the chrome's ground: the head's own translucent one
      Rectangle {
        width: parent.width - 1
        height: list.y
        color: Zenon.headBg
      }

      // the search: everything open, every word somewhere
      Rectangle {
        id: search
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        height: 36
        radius: Zenon.windowRadius
        color: Zenon.wash(0.06)
        border.width: 1
        border.color: Zenon.border
        Text {
          id: lens
          anchors.left: parent.left
          anchors.leftMargin: 13
          anchors.verticalCenter: parent.verticalCenter
          text: ""
          color: Zenon.muted
          font.family: Zenon.glyphFace
          font.pixelSize: Zenon.px(13)
        }
        TextInput {
          id: searchField
          cursorDelegate: Caret { field: searchField }
          anchors.left: lens.right
          anchors.leftMargin: 9
          anchors.right: clear.visible ? clear.left : parent.right
          anchors.rightMargin: clear.visible ? 8 : 13
          anchors.verticalCenter: parent.verticalCenter
          onTextChanged: if (win.query !== text) { win.toTop = true; win.query = text; }
          color: Zenon.ink
          selectionColor: Zenon.alpha(Zenon.cyan, 0.4)
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(15)
          clip: true
          Keys.onPressed: (e) => {
            // the field's own keys first: its text, its cursor
            if (e.key === Qt.Key_Escape && searchField.text !== "") { searchField.text = ""; e.accepted = true; return; }
            if ((e.key === Qt.Key_Left || e.key === Qt.Key_Right || e.key === Qt.Key_Home || e.key === Qt.Key_End
                 || e.key === Qt.Key_Backspace || e.key === Qt.Key_Delete) && !(e.modifiers & Qt.ControlModifier)) return;
            if ((e.modifiers & Qt.ControlModifier) && (e.key === Qt.Key_A || e.key === Qt.Key_V || e.key === Qt.Key_X
                 || (e.key === Qt.Key_C && searchField.selectedText !== ""))) return;
            if (win.key(e)) e.accepted = true;
          }
          Text {
            visible: searchField.text === ""
            anchors.verticalCenter: parent.verticalCenter
            text: !win.mgr ? "" : "Search " + (win.scope.acct ? (win.mgr.accountOf(win.scope.acct) || {}).name || "" : "everything")
            color: Zenon.muted
            font: searchField.font
          }
        }
        ClearChip {
          id: clear
          size: Zenon.px(15)
          shown: searchField.text !== ""
          anchors.right: parent.right
          anchors.rightMargin: 9
          anchors.verticalCenter: parent.verticalCenter
          onClicked: { searchField.text = ""; searchField.forceActiveFocus(); }
        }
        HeldRing { anchors.fill: parent; radius: parent.radius; z: 10; on: searchField.activeFocus }
      }

      // how the list is ordered, and how many there are
      Item {
        id: listBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: search.bottom
        anchors.topMargin: 8
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        height: 30
        Text {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: win.shown.length === 1 ? "1 item" : win.shown.length + " items"
          color: Zenon.muted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(13)
          font.features: { "tnum": 1 }
        }
        Segments {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          options: [["name", "A–Z"], ["recent", "Recent"]]
          current: win.sort
          textSize: Zenon.px(12)
          onChose: (v) => { win.mgr.set("sort", v); win.toTop = true; }
        }
      }

    }

    // ── the item ─────────────────────────────────────────────────────────
    ItemDetail {
      id: detailPane
      win: win
      anchors.left: listCol.right
      anchors.right: parent.right
      anchors.top: head.bottom
      anchors.bottom: foot.top
      visible: !win.welcoming && !win.lockAcct && !win.watching && !win.editing
    }
    // ── the item being made or changed ───────────────────────────────────
    Loader {
      id: editorLoader
      anchors.left: listCol.right
      anchors.right: parent.right
      anchors.top: head.bottom
      anchors.bottom: foot.top
      active: win.editing && !win.lockAcct
      visible: active
      // handed in here, not bound inside: in the editor's own scope `win`
      // is its property, and `win: win` bound it to itself
      sourceComponent: Component { ItemEditor {} }
      onLoaded: { item.win = win; item.st = win.editSt; Qt.callLater(() => { if (item) item.focusFirst(); }); }
      Keys.onPressed: (e) => { if (win.editKey(e)) e.accepted = true; }
    }
    // ── Watchtower's overview ────────────────────────────────────────────
    WatchPane {
      id: watchPane
      win: win
      anchors.left: side.right
      anchors.right: parent.right
      anchors.top: head.bottom
      anchors.bottom: foot.top
      visible: win.watching && !win.welcoming && !win.lockAcct
    }
    ScrollEdge { view: detailPane.flick; follow: true; bar: head; visible: detailPane.visible }
    ScrollEdge { view: detailPane.flick; below: true; follow: true; bar: foot; visible: detailPane.visible }
    ScrollEdge { view: editorLoader.item ? editorLoader.item.flick : null; follow: true; bar: head; visible: !!editorLoader.item }
    ScrollEdge { view: editorLoader.item ? editorLoader.item.flick : null; below: true; follow: true; bar: foot; visible: !!editorLoader.item }

    // ── a locked account in view ─────────────────────────────────────────
    LockPane {
      id: lockPane
      win: win
      anchors.left: side.right
      anchors.right: parent.right
      anchors.top: head.bottom
      anchors.bottom: foot.top
      visible: !win.welcoming && !!win.lockAcct
      acct: win.lockAcct
      choices: win.noneOpen && !win.scope.acct ? win.lockedAccts : []
      onVisibleChanged: if (visible) Qt.callLater(win.refocus)
    }

    // ── no account yet: where do your passwords live? ────────────────────
    Item {
      anchors.left: side.right
      anchors.right: parent.right
      anchors.top: head.bottom
      anchors.bottom: foot.top
      visible: win.welcoming && !win.adding
      Column {
        anchors.centerIn: parent
        width: Math.min(parent.width - 80, 760)
        spacing: 22
        Column {
          width: parent.width
          spacing: 6
          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: "Where do your passwords live?"
            color: Zenon.ink
            font.family: Zenon.face
            font.weight: Font.Bold
            font.pixelSize: Zenon.px(26)
          }
          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: "Calypso reads them where they are, through each platform's own tool — installed for you when you choose it. Add as many as you keep."
            color: Zenon.muted
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(15)
          }
        }
        PlatformGrid {
          id: welcomeGrid
          width: parent.width
          win: win
          onChosen: (k) => win.choosePlatform(k)
        }
      }
    }

    // ── the head ─────────────────────────────────────────────────────────
    Item {
      id: head
      anchors.left: side.right
      anchors.right: parent.right
      anchors.top: parent.top
      height: win.headH
      Rectangle { anchors.fill: parent; color: Zenon.headBg }
      Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Zenon.border }
      Text {
        id: headTitle
        anchors.left: parent.left
        anchors.leftMargin: 22
        anchors.verticalCenter: parent.verticalCenter
        text: {
          const s = win.scope;
          if (win.welcoming) return "Welcome";
          if (win.editing) return win.editSt && win.editSt.id ? "Editing" : "New " + C.kindOf(win.editSt ? win.editSt.kind : "").one.toLowerCase();
          if (s.shelf === "watch") return s.audit ? "Watchtower \u203a " + C.problem(s.audit).label : "Watchtower";
          if (s.shelf === "trash") return "Trash";
          if (win.lockAcct) return "Locked";
          if (s.kind) return C.kindOf(s.kind).label;
          if (s.folder) return s.folder.split(" / ").pop();
          if (s.tag) return " " + s.tag;
          return (C.SHELVES.find((x) => x.id === (s.shelf || "all")) || C.SHELVES[0]).label;
        }
        color: Zenon.ink
        font.family: Zenon.face
        font.weight: Font.Bold
        font.pixelSize: Zenon.px(19)
      }
      Text {
        anchors.left: headTitle.right
        anchors.leftMargin: 12
        anchors.baseline: headTitle.baseline
        anchors.right: headBtns.left
        anchors.rightMargin: 16
        elide: Text.ElideRight
        text: !win.mgr || win.welcoming ? "" : win.lockAcct ? win.lockAcct.name
          : win.scope.acct ? (win.mgr.accountOf(win.scope.acct) || {}).name || ""
          : win.mgr.accounts.filter((a) => (win.mgr.states[a.id] || {}).unlocked).length + " of " + win.mgr.accounts.length + " accounts open"
        color: Zenon.muted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(14)
      }
      Row {
        id: headBtns
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        DialogButton {
          visible: win.editing
          label: "Cancel"
          onClicked: win.cancelEdit()
        }
        BusyButton {
          visible: win.editing
          label: win.editSt && win.editSt.id ? "Save" : "Make it"
          ink: Zenon.cyan
          primary: true
          busy: win.saving
          busyText: "Saving…"
          onClicked: win.saveEdit()
        }
        DialogButton {
          id: newBtn
          visible: !win.editing && !win.welcoming && !!win.mgr && win.mgr.anyOpen
          label: "\uF067  New"
          ink: Zenon.cyan
          onClicked: win.newItemMenu()
        }
        BusyButton {
          visible: !win.editing && !win.welcoming && !!win.mgr && win.mgr.anyOpen
          label: "Sync"
          busy: win.busyText !== ""
          busyText: win.busyText
          ready: !!win.mgr && win.mgr.anyOpen
          onClicked: win.syncAll()
        }
        DialogButton {
          id: lockBtn
          visible: !win.editing && !!win.mgr && win.mgr.anyOpen
          label: "Lock"
          ink: Zenon.yellow
          onClicked: win.mgr.lockAll()
          // its right click: how soon calypso locks itself
          MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.RightButton
            onClicked: (m) => { const p = mapToItem(stage, m.x, m.y); win.lockAfterMenu(p.x, p.y); }
          }
          HoverHandler {
            onHoveredChanged: hovered ? tips.show(lockBtn, win.mgr.lockAfter > 0
              ? "Every account — and on its own after " + win.mgr.lockAfter + " min (right click)" : "Every account (right click: when on its own)", "ctrl l")
              : tips.hide(lockBtn)
          }
        }
      }
    }

    // ── what was just done, said once ────────────────────────────────────
    Rectangle {
      anchors.horizontalCenter: detailPane.visible ? detailPane.horizontalCenter : head.horizontalCenter
      anchors.bottom: foot.top
      anchors.bottomMargin: 18
      width: Math.min(saidText.implicitWidth + 32, 560)
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
      height: win.footH
      Rectangle { anchors.fill: parent; color: Zenon.headBg }
      Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: Zenon.border }
      HintRow {
        rows: win.hintRows
        anchors.verticalCenter: parent.verticalCenter
        x: 16
        maxWidth: foot.width - 32
      }
    }
  }

  readonly property var hintRows: win.adding ? [["←→↑↓", "choose"], ["return", "add"], ["esc", "back"]]
    : win.genOpen ? [["space", "another"], ["←→", "longer, shorter"], ["ctrl c", "copy"], ["return", win.genUse ? "use it" : "copy"], ["esc", "close"]]
    : win.editing ? [["tab", "next field"], ["ctrl g", "generator"], ["ctrl s", "save"], ["esc", "cancel"]]
    : win.watching ? [["click a card", "its items"], ["esc", "back"]]
    : win.welcoming ? [["return", "add"], ["esc", "close"]]
    : win.lockAcct ? [["return", lockPane.missing ? "install" : lockPane.signedOut ? "sign in" : "unlock"]].concat(win.noneOpen && win.lockedAccts.length > 1 ? [["tab", "account"]] : []).concat([["esc", "close"]])
    : [["↑↓", "item"], ["return", "copy password"], ["ctrl shift c", "username"], ["ctrl alt c", "code"],
       ["ctrl r", "reveal"], ["ctrl o", "website"], ["ctrl d", "favourite"], ["ctrl l", "lock"], ["esc", win.query !== "" ? "clear" : "close"]]

  // ── adding an account: the platforms, on a sheet ───────────────────────
  InputShield { visible: win.adding && !win.welcoming; onClicked: { win.adding = false; win.refocus(); } }
  Sheet {
    id: addSheet
    shown: win.adding
    fromTop: win.headH
    leftInset: side.width
    cardW: Math.min(win.width - side.width - 80, 780)
    cardH: addCol.implicitHeight + 40
    Column {
      id: addCol
      x: 22
      y: 20
      width: parent.width - 44
      spacing: 16
      Row {
        spacing: 12
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: ""
          color: Zenon.cyan
          font.family: Zenon.glyphFace
          font.pixelSize: Zenon.px(18)
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "Add an account"
          color: Zenon.ink
          font.family: Zenon.face
          font.weight: Font.Bold
          font.pixelSize: Zenon.px(19)
        }
      }
      PlatformGrid {
        id: addGrid
        width: parent.width
        win: win
        onChosen: (k) => win.choosePlatform(k)
      }
    }
  }
  onAddingChanged: if (win.adding) keySink.forceActiveFocus()

  // ── the generator, large type, settings: each on a sheet ───────────────
  InputShield { visible: win.genOpen; onClicked: { win.genOpen = false; win.refocus(); } }
  Sheet {
    shown: win.genOpen
    fromTop: win.headH
    leftInset: side.width
    cardW: Math.min(win.width - side.width - 80, 640)
    cardH: genPane.implicitHeight
    GeneratorPane {
      id: genPane
      width: parent.width
      win: win
      using: !!win.genUse
      onUsed: (v) => { const cb = win.genUse; win.genOpen = false; win.genUse = null; if (cb) cb(v); win.refocus(); }
      onClosed: { win.genOpen = false; win.genUse = null; win.refocus(); }
    }
  }
  onGenOpenChanged: if (win.genOpen) keySink.forceActiveFocus()
  InputShield { visible: win.bigValue !== ""; onClicked: { win.bigValue = ""; win.refocus(); } }
  Sheet {
    shown: win.bigValue !== ""
    fromTop: win.headH
    leftInset: side.width
    cardW: Math.min(win.width - side.width - 80, 860)
    cardH: bigPane.implicitHeight
    LargeType { id: bigPane; width: parent.width; value: win.bigValue; label: win.bigLabel }
  }
  onBigValueChanged: if (win.bigValue !== "") keySink.forceActiveFocus(); else Qt.callLater(win.refocus)
  InputShield { visible: win.setOpen; onClicked: { win.setOpen = false; win.refocus(); } }
  Sheet {
    shown: win.setOpen
    fromTop: win.headH
    leftInset: side.width
    cardW: 560
    cardH: setPane.implicitHeight
    SettingsPane { id: setPane; width: parent.width; win: win; onClosed: { win.setOpen = false; win.refocus(); } }
  }
  onSetOpenChanged: if (win.setOpen) keySink.forceActiveFocus()

  // ── the cards ──────────────────────────────────────────────────────────
  CardSheet {
    id: cards
    fromTop: win.headH
    leftInset: side.width
    cardW: 540
    onCleared: win.refocus()
    chooseDir: win.mgr && win.mgr.fileManager ? (start, reply) => win.mgr.fileManager.choose(true, start || Quickshell.env("HOME"),
      (paths) => reply(paths && paths.length > 0 ? paths[0] : "")) : null
    chooseFile: win.mgr && win.mgr.fileManager ? (start, reply) => win.mgr.fileManager.choose(false, start || Quickshell.env("HOME"),
      (paths) => reply(paths && paths.length > 0 ? paths[0] : "")) : null
  }

  // ── the window's one menu, and its one tooltip ─────────────────────────
  PopMenu {
    id: menu
    parent: stage
    anchors.fill: parent
    window: win
    cardWidth: 270
    onClosed: { win.menuHeld = ""; win.refocus(); }
  }
  WindowTip { id: tips; window: win }
}
