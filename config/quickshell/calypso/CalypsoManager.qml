// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// CALYPSO — the password manager: every vault you have, on whichever
// platform it lives (Bitwarden, 1Password, Proton Pass, KeePassXC, pass,
// gopass), in one window and one Quick Access.
//
// THIS IS THE PART THAT IS ALWAYS IN THE SHELL: the accounts, the line to
// the backend (bin/calypsod, calypso/core — Python, no Quickshell in it), the
// ipc handler and the .desktop entry. The window type is compiled on the
// first open. Quick Access (CalypsoPopup, the bar's layer) and the window
// both ask through here, so an account unlocked in one is open in the other.
//
//   accounts                      [{ id, kind, name, …the platform's own }]
//   states[id]                    { installed, configured, unlocked, user,
//                                   note, busy, error }
//   items                         every unlocked account's items, each with
//                                 `acct` beside the daemon's fields
//   call(op, acct, args, done, event) → id
//   unlock(acct, secret, done) · lock(acct) · lockAll()
//   addAccount(kind, values, secret, done) · removeAccount(acct)
//   install(kind, done)           the platform's CLI, through Ceres
//
// LOCKED BY ITSELF: after `lockAfter` minutes with nothing asked (oracle's
// "never" is 0), and whenever the screen locks — every account locked and
// the daemon stopped, so nothing it held in memory survives. "Never" also
// outlives a quickshell restart (see `lingers`).
//
// Reached through:
//   `qs ipc call Calypso open`     the window — bin/calypso, calypso.desktop
//   `qs ipc call Calypso window`   the window, or away again (SUPER+SHIFT+V)
//   `qs ipc call Calypso toggle`   Quick Access (SUPER+V)
//   `qs ipc call Calypso lock`     every account

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../morpheus"
import "../ceres"
import "../terminus"
import "../morpheus/lagnotes.js" as LagNotes
import "calypso.js" as C

Scope {
  id: mgr

  // terminus, handed in by shell.qml: its picker for a KeePass file
  property var fileManager: null
  // Quick Access, handed in by shell.qml
  property var quick: null

  readonly property int protocol: 1

  // ── ITS .desktop ENTRY ─────────────────────────────────────────────
  // Not shipped as a file: written into ~/.local/share/applications on
  // startup when missing, with this machine's path to bin/calypso (see
  // Desktop.installCommand), as plato's, alexandria's and delphi's are.
  Process {
    running: true
    command: ["sh", "-c", Desktop.installCommand("calypso", {
      Type: "Application",
      Name: "Calypso",
      GenericName: "Password Manager",
      Comment: "Your Bitwarden, 1Password, Proton Pass, KeePassXC and pass vaults, in ZENWORKS",
      Icon: "dialog-password",
      Categories: ["Utility", "Security"],
      Keywords: ["password", "passwords", "vault", "login", "totp", "2fa", "otp", "bitwarden",
                 "vaultwarden", "1password", "proton", "keepass", "keepassxc", "pass", "gopass"],
      Exec: Desktop.execLine(Quickshell.shellDir + "/calypso/bin/calypso"),
      Terminal: "false",
      StartupNotify: "false",
    })]
  }

  // ── WHAT IS KEPT ───────────────────────────────────────────────────
  property var accounts: []
  // calypso's own favorites, by C.keyOf (1Password's come with its items)
  property var favs: ({})
  // the window's place: { shelf, kind, acct, folder, tag }
  property var scope: ({ shelf: "all" })
  property string sort: "name"
  // minutes with nothing asked before every account locks; 0 = never
  property int lockAfter: 10
  // Quick Access' recently used, newest first (C.keyOf)
  property var recent: []
  // seconds a copied secret stays on the clipboard; 0 = until replaced
  property int clearAfter: 30
  FileView {
    id: stateFile
    path: Quickshell.statePath("calypso.json")
    blockLoading: true
    printErrors: false
  }
  Component.onCompleted: {
    try {
      const st = JSON.parse(stateFile.text() || "{}");
      if (Array.isArray(st.accounts)) mgr.accounts = st.accounts.filter((a) => a && a.id && C.PLATFORMS[a.kind]);
      if (st.favs && typeof st.favs === "object") mgr.favs = st.favs;
      if (st.scope && typeof st.scope === "object") mgr.scope = st.scope;
      if (st.sort === "name" || st.sort === "recent") mgr.sort = st.sort;
      if (typeof st.lockAfter === "number" && st.lockAfter >= 0) mgr.lockAfter = st.lockAfter;
      if (Array.isArray(st.recent)) mgr.recent = st.recent.slice(0, 40);
      if (typeof st.clearAfter === "number" && st.clearAfter >= 0) mgr.clearAfter = st.clearAfter;
      mgr.migrated = !!st.migrated;
    } catch (e) {}
    // The account rbw already had, before calypso kept accounts of its own
    // (it drove rbw alone until 2026-10-11): brought over once, so the
    // vault Quick Access opened yesterday is still there today.
    if (mgr.accounts.length === 0 && !mgr.migrated) mgr.adoptRbw();
  }
  property bool migrated: false
  // Counted done only once rbw has answered: with rbw not installed (yet)
  // it is asked again at the next start.
  function adoptRbw() {
    mgr.call("status", { id: "rbw-default", kind: "bitwarden", name: "Bitwarden" }, {}, (ok, st) => {
      if (!ok) return;
      mgr.migrated = true;
      mgr.keep_();
      if (!st.configured || mgr.accounts.length > 0) return;
      mgr.accounts = [{ id: "rbw-default", kind: "bitwarden", name: "Bitwarden" }];
      mgr.keep_();
      mgr.refresh(mgr.accounts[0]);
    });
  }
  function keep_() { keepTimer.restart(); }
  Timer {
    id: keepTimer
    interval: 400
    onTriggered: stateFile.setText(JSON.stringify({
      accounts: mgr.accounts, favs: mgr.favs, scope: mgr.scope, sort: mgr.sort,
      lockAfter: mgr.lockAfter, recent: mgr.recent, migrated: mgr.migrated, clearAfter: mgr.clearAfter }, null, 1))
  }
  function set(key, value) {
    if (mgr[key] === value) return;
    mgr[key] = value;
    mgr.keep_();
  }
  function setFav(it, on) {
    const f = Object.assign({}, mgr.favs);
    if (on) f[C.keyOf(it)] = true; else delete f[C.keyOf(it)];
    mgr.favs = f;
    mgr.keep_();
  }
  function used(it) {
    const k = C.keyOf(it);
    mgr.recent = [k].concat(mgr.recent.filter((r) => r !== k)).slice(0, 40);
    mgr.keep_();
  }
  function accountOf(id) { return mgr.accounts.find((a) => a.id === id) || null; }

  // ── THE BACKEND ────────────────────────────────────────────────────
  // terminus/LineDaemon, as delphi's. Held while a window or Quick Access
  // is up; otherwise let go a minute after the last request — but not while
  // anything is unlocked: the daemon's memory is where KeePass' database
  // and 1Password's session live.
  LineDaemon {
    id: line
    name: "calypso"
    command: ["python3", Quickshell.shellDir + "/calypso/bin/calypsod"]
    protocol: mgr.protocol
    goneText: "Calypso's backend stopped"
    onStopped: {
      // what the daemon held is gone with it: KeePass' and Proton's open
      // state, 1Password's session — asked afresh
      if (mgr.anyOpen) Qt.callLater(mgr.refreshAll);
    }
  }
  // NEVER MEANS NEVER (user, 2026-10-14): with auto-lock "Never" and an
  // account open, the daemon is told to stay when quickshell goes (it runs
  // apart, on a socket — core/server.py, OUTLIVING QUICKSHELL), and the
  // next shell finds the vaults as they were. Any other setting, or every
  // account locked, and it goes with the shell as it always did.
  readonly property bool lingers: mgr.lockAfter === 0 && mgr.anyOpen
  function sayLinger() { if (line.up) line.request("linger", { args: { on: mgr.lingers } }, null); }
  onLingersChanged: mgr.sayLinger()
  Connections { target: line; function onUpChanged() { mgr.sayLinger(); } }
  readonly property bool up: line.up
  readonly property string broken: line.broken
  readonly property bool anyOpen: mgr.accounts.some((a) => (mgr.states[a.id] || {}).unlocked)
  onAnyOpenChanged: if (mgr.anyOpen) line.hold("open"); else line.release("open")
  function hold(who) { line.hold(who); }
  function release(who) { line.release(who); }

  function call(op, acct, args, done, event) {
    mgr.touch();
    return line.request(op, { account: acct || null, args: args || {} }, done, event);
  }
  function cancel(id) { line.cancel(id); }

  // ── WHAT THE PLATFORMS ARE ─────────────────────────────────────────
  // [{ kind, name, cli, pkg, aur, asks, blurb, installed }]
  property var platforms: []
  function loadPlatforms(then) {
    mgr.call("platforms", null, {}, (ok, list) => {
      if (ok) mgr.platforms = list;
      if (then) then();
    });
  }
  function platformInfo(kind) { return mgr.platforms.find((p) => p.kind === kind) || null; }

  // ── EACH ACCOUNT'S STATE, AND ITS ITEMS ────────────────────────────
  property var states: ({})
  property var itemsBy: ({})
  function setState(id, patch) {
    const o = Object.assign({}, mgr.states);
    o[id] = Object.assign({}, o[id] || {}, patch);
    mgr.states = o;
  }
  readonly property var items: {
    let out = [];
    for (const a of mgr.accounts) {
      const st = mgr.states[a.id];
      if (st && st.unlocked && mgr.itemsBy[a.id]) out = out.concat(mgr.itemsBy[a.id]);
    }
    return out;
  }
  // NOT KNOWN YET IS NOT LOCKED (user, 2026-10-14): until the daemon has
  // answered `status`, an account is neither — a vault the daemon kept open
  // across a shell restart flashed the lock for the second bw takes to say
  // so. `known` comes with the first answer; until then the window and Quick
  // Access show the reading mark, never the password field.
  function isLocked(a) { const st = mgr.states[a.id] || {}; return !!st.known && !st.unlocked; }
  readonly property bool checking: mgr.accounts.some((a) => !(mgr.states[a.id] || {}).known)
  readonly property bool loading: mgr.checking || mgr.accounts.some((a) => (mgr.states[a.id] || {}).loading)

  function refresh(acct, then) {
    if (!acct) return;
    mgr.setState(acct.id, { busy: true });
    mgr.call("status", acct, {}, (ok, st, err) => {
      if (!ok) {
        mgr.setState(acct.id, { busy: false, known: true, unlocked: false, installed: !(err && err.kind === "missing"),
                                error: C.failWords(err) });
        if (then) then(false);
        return;
      }
      mgr.setState(acct.id, Object.assign({ busy: false, known: true, error: "" }, st));
      if (st.unlocked) mgr.loadItems(acct, then);
      else {
        mgr.dropItems(acct.id);
        if (then) then(true);
      }
    });
  }
  function refreshAll() { for (const a of mgr.accounts) mgr.refresh(a); }

  function loadItems(acct, then) {
    mgr.setState(acct.id, { loading: true });
    mgr.call("items", acct, {}, (ok, rows, err) => {
      mgr.setState(acct.id, { loading: false });
      if (!ok) {
        if (err && err.kind === "locked") { mgr.setState(acct.id, { unlocked: false }); mgr.dropItems(acct.id); }
        else mgr.setState(acct.id, { error: C.failWords(err) });
        if (then) then(false);
        return;
      }
      for (const r of rows) r.acct = acct.id;
      const o = Object.assign({}, mgr.itemsBy);
      o[acct.id] = rows;
      mgr.itemsBy = o;
      mgr.setState(acct.id, { error: "", count: rows.length });
      if (then) then(true);
      mgr.enrich(acct);
    });
  }
  // What a quick listing left out (pass and gopass read each entry with
  // gpg, ~120 ms apiece: listed from the names first, the usernames, sites
  // and codes after), merged in a batch at a time as the daemon says them.
  function enrich(acct) {
    mgr.call("enrich", acct, {}, () => {}, (ev) => {
      const rows = mgr.itemsBy[acct.id];
      if (!ev.rows || !rows) return;
      const by = {};
      for (const r of ev.rows) { r.acct = acct.id; by[r.id] = r; }
      const o = Object.assign({}, mgr.itemsBy);
      o[acct.id] = rows.map((r) => by[r.id] || r);
      mgr.itemsBy = o;
    });
  }
  function dropItems(id) {
    if (!mgr.itemsBy[id]) return;
    const o = Object.assign({}, mgr.itemsBy);
    delete o[id];
    mgr.itemsBy = o;
  }

  // done(ok, err)
  function unlock(acct, secret, done) {
    mgr.setState(acct.id, { busy: true, error: "" });
    mgr.call("unlock", acct, { secret: secret }, (ok, res, err) => {
      mgr.setState(acct.id, { busy: false });
      if (!ok) {
        if (done) done(false, err);
        return;
      }
      mgr.setState(acct.id, { unlocked: true });
      mgr.loadItems(acct);
      mgr.unlocked(acct.id);
      if (done) done(true, null);
    });
  }
  signal unlocked(string id)
  function lock(acct) {
    mgr.setState(acct.id, { unlocked: false });
    mgr.dropItems(acct.id);
    mgr.locked(acct.id);
    mgr.call("lock", acct, {}, () => {});
  }
  signal locked(string id)
  // every account, and the daemon stopped once they have gone: what it held
  // in memory goes with it
  function lockAll() {
    for (const a of mgr.accounts) {
      if ((mgr.states[a.id] || {}).unlocked) mgr.lock(a);
    }
    mgr.locked("");
    stopTimer.restart();
  }
  Timer { id: stopTimer; interval: 3000; onTriggered: if (!mgr.anyOpen) line.stop() }
  function sync(acct, done) {
    mgr.call("sync", acct, {}, (ok, res, err) => {
      if (ok) mgr.loadItems(acct);
      if (done) done(ok, err);
    });
  }

  // ── WRITING ────────────────────────────────────────────────────────
  // done(ok, result, err); the account's list is read again after
  function save(acct, id, draft, done) {
    mgr.call("save", acct, { item: id || null, draft: draft }, (ok, res, err) => {
      if (ok) mgr.loadItems(acct);
      if (done) done(ok, res, err);
    });
  }
  function remove(acct, id, permanent, done) {
    mgr.call("delete", acct, { item: id, permanent: !!permanent }, (ok, res, err) => {
      if (ok) { mgr.loadItems(acct); if (mgr.trashBy[acct.id]) mgr.loadTrash(acct); }
      if (done) done(ok, res, err);
    });
  }
  function restore(acct, id, done) {
    mgr.call("restore", acct, { item: id }, (ok, res, err) => {
      if (ok) { mgr.loadItems(acct); mgr.loadTrash(acct); }
      if (done) done(ok, res, err);
    });
  }
  function duplicate(acct, id, done) {
    mgr.call("duplicate", acct, { item: id }, (ok, res, err) => {
      if (ok) mgr.loadItems(acct);
      if (done) done(ok, res, err);
    });
  }
  // ── THE TRASH, BY ACCOUNT (the platforms that keep one) ────────────
  property var trashBy: ({})
  function loadTrash(acct) {
    mgr.call("trash", acct, {}, (ok, rows) => {
      const o = Object.assign({}, mgr.trashBy);
      o[acct.id] = ok ? rows.map((r) => Object.assign(r, { acct: acct.id })) : [];
      mgr.trashBy = o;
    });
  }
  readonly property var trashItems: {
    let out = [];
    for (const a of mgr.accounts) if ((mgr.states[a.id] || {}).unlocked && mgr.trashBy[a.id]) out = out.concat(mgr.trashBy[a.id]);
    return out;
  }
  // ── WATCHTOWER, BY ACCOUNT ─────────────────────────────────────────
  // { items: { id: [problems] }, counts, pwnedAt } — never kept on disk
  property var audits: ({})
  property bool auditing: false
  readonly property var flags: {
    const out = {};
    for (const id in mgr.audits) {
      const r = mgr.audits[id];
      if (!r || !(mgr.states[id] || {}).unlocked) continue;
      for (const iid in r.items) out[id + "\u0001" + iid] = r.items[iid];
    }
    return out;
  }
  function audit(pwned, done) {
    const open = mgr.accounts.filter((a) => (mgr.states[a.id] || {}).unlocked);
    if (open.length === 0) { if (done) done(true); return; }
    let left = open.length, bad = null;
    mgr.auditing = true;
    for (const a of open) {
      mgr.call("audit", a, { pwned: !!pwned }, (ok, res, err) => {
        if (ok) { const o = Object.assign({}, mgr.audits); o[a.id] = res; mgr.audits = o; }
        else bad = err;
        if (--left === 0) { mgr.auditing = false; if (done) done(!bad, bad); }
      });
    }
  }
  onLocked: (id) => {
    const o = Object.assign({}, mgr.audits);
    if (id === "") { mgr.audits = ({}); mgr.trashBy = ({}); return; }
    delete o[id];
    mgr.audits = o;
  }

  // ── THE AUTOMATIC LOCK ─────────────────────────────────────────────
  property double lastUse: Date.now()
  function touch() { mgr.lastUse = Date.now(); }
  Timer {
    interval: 30000
    repeat: true
    running: mgr.anyOpen && mgr.lockAfter > 0
    onTriggered: {
      if ((mgr.win && mgr.win.visible && mgr.win.active) || (mgr.quick && mgr.quick.shown)) { mgr.touch(); return; }
      if (Date.now() - mgr.lastUse > mgr.lockAfter * 60000) {
        mgr.lockAll();
        mgr.tell("Calypso locked itself after " + mgr.lockAfter + " minutes");
      }
    }
  }

  // ── ACCOUNTS COME AND GO ───────────────────────────────────────────
  // values: the setup form's; `secret` the password asked with it, or null.
  // done(ok, err, acct)
  function newId(kind) {
    let n = 1;
    while (mgr.accountOf(kind + "-" + n)) n++;
    return kind + "-" + n;
  }
  function addAccount(kind, values, secret, done) {
    const id = mgr.newId(kind);
    const name = C.accountName(kind, values, mgr.accounts.map((a) => a.name));
    const acct = { id: id, kind: kind, name: name };
    if (kind === "bitwarden" && mgr.accounts.some((a) => a.kind === "bitwarden"))
      acct.profile = id;       // rbw keeps one account per profile
    if (kind === "onepassword") acct.shorthand = id;
    const params = Object.assign({}, values);
    delete params.name;
    mgr.setState(id, { busy: true });
    mgr.call("setup", acct, { params: params, secret: secret }, (ok, res, err) => {
      if (!ok) {
        const o = Object.assign({}, mgr.states);
        delete o[id];
        mgr.states = o;
        if (done) done(false, err, null);
        return;
      }
      // what the platform settled on (a shorthand, a path) is kept with it
      const kept = Object.assign({}, acct, res.account || {});
      delete kept.secret;
      mgr.accounts = mgr.accounts.concat([kept]);
      mgr.keep_();
      mgr.refresh(kept);
      if (done) done(true, null, kept);
    }, (ev) => { if (done && ev.url) mgr.signInUrl(id, ev.url); });
  }
  // An account already here, signed in afresh (its platform signed out, or
  // a new tool for it): the same setup, the account kept. done(ok, err, acct)
  function resetup(acct, values, secret, done) {
    const params = Object.assign({}, values);
    delete params.name;
    mgr.setState(acct.id, { busy: true });
    mgr.call("setup", acct, { params: params, secret: secret }, (ok, res, err) => {
      mgr.setState(acct.id, { busy: false });
      if (!ok) { if (done) done(false, err, null); return; }
      const kept = Object.assign({}, acct, res.account || {});
      mgr.accounts = mgr.accounts.map((a) => a.id === acct.id ? kept : a);
      mgr.keep_();
      mgr.refresh(kept);
      if (done) done(true, null, kept);
    }, (ev) => { if (ev.url) mgr.signInUrl(acct.id, ev.url); });
  }
  // Proton's browser sign-in: the address to open, for whoever asked
  signal signInUrl(string id, string url)
  function rename(acct, name) {
    mgr.accounts = mgr.accounts.map((a) => a.id === acct.id ? Object.assign({}, a, { name: name }) : a);
    mgr.keep_();
  }
  function move(acct, d) {
    const i = mgr.accounts.findIndex((a) => a.id === acct.id);
    const j = i + d;
    if (i < 0 || j < 0 || j >= mgr.accounts.length) return;
    const list = mgr.accounts.slice();
    const t = list[i]; list[i] = list[j]; list[j] = t;
    mgr.accounts = list;
    mgr.keep_();
  }
  // `signOut`: also forget it on the platform's side (op account forget,
  // pass-cli logout); without, calypso only stops showing it
  function removeAccount(acct, signOut) {
    mgr.call(signOut ? "forget" : "lock", acct, {}, () => {});
    mgr.accounts = mgr.accounts.filter((a) => a.id !== acct.id);
    mgr.dropItems(acct.id);
    const o = Object.assign({}, mgr.states);
    delete o[acct.id];
    mgr.states = o;
    const f = {};
    for (const k in mgr.favs) if (k.indexOf(acct.id + "\u0001") !== 0) f[k] = true;
    mgr.favs = f;
    if (mgr.scope.acct === acct.id) mgr.scope = { shelf: "all" };
    mgr.keep_();
  }

  // ── A PLATFORM'S TOOL, INSTALLED WHEN IT IS CHOSEN ─────────────────
  // Through Ceres (Ceres.install), as delphi's forge tools: its own
  // password card and log. done(ok)
  readonly property var installing: Ceres.installing
  // the platform's package asked afresh first: it can depend on the
  // machine (Bitwarden's, on whether nodejs is installed)
  function install(kind, done) {
    mgr.loadPlatforms(() => mgr.install_(kind, done));
    return true;
  }
  function install_(kind, done) {
    const p = mgr.platformInfo(kind);
    if (!p) { if (done) done(false); return false; }
    if (Ceres.txBusy || Ceres.installing) { mgr.tell("Ceres is busy with another job — try again once it is done", true); return false; }
    const asked = Ceres.install(p.pkg, "for " + p.name + " in Calypso", (ok) => {
      if (ok) mgr.tell("Installed " + p.pkg);
      else mgr.tell(p.pkg + " was not installed" + (Ceres.txError ? ": " + Ceres.txError : ""), true);
      mgr.loadPlatforms(() => {
        if (ok) mgr.refreshAll();
        if (done) done(ok);
      });
    });
    if (!asked) mgr.tell("Ceres could not take the install of " + p.pkg + " — open Ceres to see why", true);
    return asked;
  }

  // ── SAYING HOW SOMETHING ENDED ─────────────────────────────────────
  function tell(text, bad) {
    if (mgr.win && mgr.win.visible) { mgr.win.say(text, bad); return; }
    if (mgr.quick && mgr.quick.shown) return;
    Quickshell.execDetached(["notify-send", "-a", "calypso"].concat(bad ? ["-u", "critical"] : []).concat(["Calypso", text]));
  }

  // ── THE WINDOW ─────────────────────────────────────────────────────
  // One, kept hidden when closed (delphi's rule: built afresh each open, a
  // window stalls); what it had revealed is forgotten as it hides.
  property var win: null
  LazyComponent {
    id: lazy
    source: Qt.resolvedUrl("CalypsoWindow.qml")
    tag: "calypso"
  }
  function withWindow(fn) {
    lazy.withReady(() => {
      let fresh = false;
      if (!mgr.win) {
        const t0 = Date.now();
        mgr.win = lazy.comp.createObject(mgr, { mgr: mgr });
        LagNotes.mark("calypso window", t0);
        if (!mgr.win) return;
        fresh = true;
      }
      fn(mgr.win, fresh);
      mgr.win.visible = true;
      if (!fresh) Hyprland.dispatch('hl.dsp.focus({ window = "title:^(calypso)$" })');
    });
  }
  function open() {
    if (mgr.quick && mgr.quick.shown) mgr.quick.closePopup();
    mgr.withWindow((w, fresh) => { w.wake(); });
  }
  function toggleWindow() {
    if (mgr.win && mgr.win.visible) { mgr.win.visible = false; return; }
    mgr.open();
  }
  // the window on one item (Quick Access' "open in calypso")
  function show(it) {
    mgr.withWindow((w) => { w.wake(); w.reveal(it); });
  }

  IpcHandler {
    target: "Calypso"
    function open(): string { mgr.open(); return "ok"; }
    function toggle(): string { if (mgr.quick) mgr.quick.toggle(); return "ok"; }
    // the window, shown or put away (SUPER+SHIFT+V)
    function window(): string { mgr.toggleWindow(); return "ok"; }
    function lock(): string { mgr.lockAll(); return "ok"; }
  }
}
