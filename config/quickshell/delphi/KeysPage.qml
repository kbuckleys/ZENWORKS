// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// SSH KEYS — the keys in ~/.ssh, and what each one is for: the hosts
// ~/.ssh/config gives it to, the forges that have it, the commits it signs,
// whether the host let it in when last tested (delphi/core/sshkeys.py).
//
//   n a new key: named, its hosts ticked, a passphrase; then ~/.ssh/config
//     told, the forges handed it (GitHub, GitLab, Codeberg — asked first),
//     the AUR's page opened to paste it, and every host tested
//   return/t test it · u give it to a host · a add it to a forge
//   m the agent remembers its passphrase, or no longer
//   c copy the public key · d to the trash (asked twice)
//
// Not tied to a repository: it is on the "Everywhere" side, like Accounts.

import QtQuick
import Quickshell
import "../morpheus"
import "../terminus"
import "delphi.js" as D

Item {
  id: pg
  property var win: null
  readonly property var edgeViews: [list]

  readonly property string title: "SSH keys"
  readonly property string subtitle: !pg.st ? "" : !pg.st.ssh ? "openssh is not installed"
    : (pg.keys.length === 0 ? "No keys yet" : pg.keys.length + (pg.keys.length === 1 ? " key" : " keys"))
      + (pg.st.agent ? "  ·  the agent keeps passphrases" : "")
  readonly property var hints: [["n", "new"], ["t", "test"], ["u", "use for a host"], ["a", "add to a forge"], ["m", "remember"], ["c", "copy"], ["d", "delete"]]
  readonly property var buttons: [
    { label: "Delete", ink: Zenon.red, visible: !!pg.key_ && !!pg.st && pg.st.ssh, run: () => pg.remove(pg.key_) },
    { label: "Test", visible: !!pg.key_ && pg.key_.hosts.length > 0, run: () => pg.test(pg.key_) },
    pg.st && !pg.st.ssh ? { label: "Install openssh", ink: Zenon.cyan, primary: true, run: () => pg.needOpenssh(null) }
                        : { label: "New key", ink: Zenon.cyan, primary: true, run: () => pg.newKey([]) },
  ]
  function takeFocus() { if (pg.win) pg.win.focusKeys(); }

  property var st: null
  readonly property var keys: pg.st ? pg.st.keys : []
  property int sel: 0
  readonly property var key_: pg.sel >= 0 && pg.sel < pg.keys.length ? pg.keys[pg.sel] : null
  // the forges that have each key: public key → [{ forge, id }]
  property var on: ({})
  // the last test of each host: host → sshkeys.read_test's answer
  property var tests: ({})

  function reload() {
    if (!pg.win) return;
    pg.win.mgr.call("sshStatus", null, {}, (ok, st) => {
      if (!pg) return;
      if (!ok) { pg.win.fail("Could not read ~/.ssh", null, st); return; }
      pg.st = st;
      pg.sel = Math.max(0, Math.min(pg.sel, st.keys.length - 1));
    });
    // which forge has which key, where signed in (GitHub needs a permission
    // to list them: without it, nothing is said rather than a failure)
    const found = {};
    let left = D.FORGE_ORDER.length;
    const done = () => { if (--left === 0 && pg) pg.on = found; };
    D.FORGE_ORDER.forEach((id) => {
      pg.win.mgr.call(id + "Status", null, {}, (ok, s) => {
        if (!pg || !ok || !s || !s.signedIn) { done(); return; }
        pg.win.mgr.call(id + "SshKeys", null, {}, (ok2, list) => {
          if (pg && ok2) list.forEach((k) => { (found[k.key] = found[k.key] || []).push({ forge: id, id: k.id }); });
          done();
        });
      });
    });
  }
  Component.onCompleted: Qt.callLater(pg.reload)

  function moveTo(i) {
    if (pg.keys.length === 0) return;
    pg.sel = Math.max(0, Math.min(pg.keys.length - 1, i));
    list.positionViewAtIndex(pg.sel, ListView.Contain);
  }
  function hostName(h) {
    const k = D.keyHosts().find((x) => x.host === h);
    return k ? k.name : h;
  }
  function forgesOf(k) { return (pg.on[k.public] || []).map((x) => D.FORGES[x.forge] ? D.FORGES[x.forge].name : x.forge); }
  // the same, as the row says it: a tested host marked ✓ or ✗ in its
  // colour, in place (user, 2026-10-25: "AUR" over "✓ AUR" said it twice)
  function usesLine(k) {
    return pg.usesOf(k).map((u, i) => {
      const t = i < k.hosts.length ? pg.tests[k.hosts[i]] : null;
      if (!t) return D.esc(u);
      return "<font color=\"" + (t.ok ? Zenon.green : Zenon.red) + "\">" + (t.ok ? "✓ " : "✗ ") + D.esc(u) + "</font>";
    }).join(", ");
  }
  function usesOf(k) {
    const out = k.hosts.map(pg.hostName);
    pg.forgesOf(k).forEach((n) => { if (out.indexOf(n) < 0) out.push(n + " (added)"); });
    if (k.signing) out.push("signs your commits");
    return out;
  }

  // openssh missing: Ceres installs it, then the session's agent is
  // started (the next login starts its own) and the page read again
  function needOpenssh(then) {
    pg.win.mgr.installTool("openssh", "for SSH keys", (done) => {
      if (!done || !pg) return;
      pg.win.act("sshAgentStart", {}, { repo: null, refresh: false, quiet: true,
        then: () => { if (!pg) return; pg.reload(); if (then) then(); } });
    });
  }

  // ── A NEW KEY ──────────────────────────────────────────────────────────
  // The form, the passphrase twice, the key made; then each ticked host in
  // turn: ~/.ssh/config, the forges, the AUR's page, a test of every one.
  function newKey(preset) {
    if (!pg.st) { Qt.callLater(() => { if (pg) pg.newKey(preset); }); return; }
    if (!pg.st.keygen) {
      pg.win.card_({ question: "SSH keys need openssh", glyph: "", ink: Zenon.ink,
        detail: "ssh-keygen, which makes them, comes with openssh — not installed. Ceres can install it (it asks for your password).",
        choices: [{ label: "Install openssh", ink: Zenon.cyan, run: () => pg.needOpenssh(() => pg.newKey(preset)) },
                  { label: "Cancel", ink: Zenon.accentMuted }] });
      return;
    }
    const hosts = D.keyHosts();
    const base = preset.length === 1 && preset[0] === "aur.archlinux.org" ? "aur" : "id_ed25519";
    let name = base, n = 2;
    while (pg.keys.some((k) => k.name === name)) name = base + "_" + n++;
    pg.win.ask({ title: "A new SSH key", glyph: "",
      detail: "Ed25519, kept in ~/.ssh and readable by you alone. With a passphrase, a copy of the key file is no use to anyone without it.",
      fields: [{ key: "name", label: "Name", value: name },
               { key: "comment", label: "Label", hint: "which computer it is on", optional: true }],
      toggles: hosts.map((h) => ({ key: "h:" + h.host, label: "For " + h.name, value: preset.indexOf(h.host) >= 0 }))
        .concat([{ key: "pass", label: "Protect it with a passphrase", value: true },
                 { key: "agent", label: "Remember the passphrase while I'm logged in", value: true }]),
      verb: "Next",
      then: (v) => {
        const chosen = hosts.filter((h) => v["h:" + h.host]).map((h) => h.host);
        const go = (pass) => pg.make(v.name.trim(), v.comment.trim(), pass, chosen, !!v.agent);
        if (!v.pass) { go(""); return; }
        pg.win.ask({ title: "Passphrase for " + v.name.trim(), glyph: "",
          secret: { key: "p", prompt: "Passphrase", purpose: "asked when the key is used (once per login with the agent)" }, verb: "Next",
          then: (a) => pg.win.ask({ title: "Once more", glyph: "",
            secret: { key: "p", prompt: "Passphrase again", purpose: "to be sure it is the one you meant" }, verb: "Make the key",
            then: (b) => {
              if (a.p !== b.p) { pg.win.say("The two passphrases differ — nothing was made", true); return; }
              go(a.p);
            } }) });
      } });
  }
  function make(name, comment, pass, hosts, agent) {
    pg.win.act("sshCreate", { name: name, comment: comment, passphrase: pass }, { repo: null, refresh: false, label: "Making the key",
      failed: (err) => pg.win.fail("The key was not made", null, err),
      then: (k) => {
        if (!pg) return;
        pg.reload();
        const next = () => pg.giveTo(k, hosts, agent, 0, () => pg.register(k, hosts, () => pg.testHosts(hosts)));
        if (agent && pg.st && !pg.st.agent) pg.win.act("sshAgentStart", {}, { repo: null, refresh: false, quiet: true, then: next, failed: next });
        else next();
      } });
  }
  // ~/.ssh/config, a host at a time; one with a block of its own shown first
  function giveTo(k, hosts, agent, i, done) {
    if (!pg) return;
    if (i >= hosts.length) { pg.reload(); done(); return; }
    const host = hosts[i];
    const next = () => pg.giveTo(k, hosts, agent, i + 1, done);
    pg.win.act("sshUse", { host: host, key: k.path, agent: agent }, { repo: null, refresh: false,
      failed: (err) => { pg.win.fail("~/.ssh/config was not changed for " + host, null, err); next(); },
      then: (res) => {
        if (res.state !== "differs") { next(); return; }
        pg.win.card_({ question: host + " has keys of its own", glyph: "", ink: Zenon.yellow,
          detail: "~/.ssh/config already says which key goes to " + host + ". Use the new one there instead? Only that line changes.",
          items: res.block.split("\n"),
          choices: [{ label: "Use the new key", ink: Zenon.cyan,
                      run: () => pg.win.act("sshUse", { host: host, key: k.path, agent: agent, replace: true }, { repo: null, refresh: false, then: next, failed: next }) },
                    { label: "Leave it", run: next }] });
      } });
  }
  // the forges signed in to, asked once; the hosts without a way to hand
  // it over (the AUR), their page opened to paste it
  function register(k, hosts, done) {
    const all = D.keyHosts().filter((h) => hosts.indexOf(h.host) >= 0);
    const apis = all.filter((h) => h.api !== "");
    const pages = all.filter((h) => h.api === "");
    const paste = () => {
      if (!pg) return;
      if (pages.length === 0) { done(); return; }
      const h = pages[0];
      pg.win.card_({ question: "Paste it on the " + h.name + "'s page", glyph: h.glyph, ink: Zenon.ink,
        detail: "The " + h.name + " has no way for Delphi to hand it the key: copy it, open the page, sign in, and paste it under "
          + (h.where || "your account's SSH keys") + ". Then test it.",
        items: [k.public.slice(0, 64) + "…"],
        choices: [{ label: "Copy the key", keep: true, run: () => pg.win.copy(k.public, "the public key") },
                  { label: "Open the " + h.name, keep: true, run: () => Quickshell.execDetached(["xdg-open", h.page]) },
                  { label: "Test it now", ink: Zenon.cyan, run: () => { pages.shift(); paste(); } },
                  { label: "Later", ink: Zenon.accentMuted, run: () => { pg.win.say("Test it from this page (t) once it is pasted"); } }] });
    };
    if (apis.length === 0) { paste(); return; }
    const signed = [];
    let left = apis.length;
    apis.forEach((h) => pg.win.mgr.call(h.api + "Status", null, {}, (ok, s) => {
      if (ok && s && s.signedIn) signed.push(h);
      if (--left > 0 || !pg) return;
      if (signed.length === 0) { paste(); return; }
      pg.win.card_({ question: "Add it to " + signed.map((h) => h.name).join(" and ") + "?", glyph: "", ink: Zenon.ink,
        detail: "Signed in there, so Delphi can add the public key to your account itself."
          + (apis.length > signed.length ? " Not signed in to " + apis.filter((h) => signed.indexOf(h) < 0).map((h) => h.name).join(", ") + ": add it there from this page later (a)." : ""),
        choices: [{ label: "Add it", ink: Zenon.cyan, run: () => pg.addTo(k, signed.map((h) => h.api), paste) },
                  { label: "Not now", ink: Zenon.accentMuted, run: paste }] });
    }));
  }
  function addTo(k, ids, done) {
    let left = ids.length;
    const one = () => { if (--left === 0 && pg) { pg.reload(); if (done) done(); } };
    ids.forEach((id) => {
      const f = D.FORGES[id];
      pg.win.act(id + "AddSshKey", { key: k.public, title: k.name + " (delphi, " + D.baseName(pg.win.home) + ")" }, {
        repo: null, network: true, refresh: false, label: "Adding the key to " + f.name,
        then: (res) => { pg.win.say(res.already ? f.name + " has it already" : "Added to " + f.name); one(); },
        failed: (err) => { pg.win.fail("Could not add the key to " + f.name, null, err); one(); } });
    });
  }
  // every host in turn; what each said kept for the row
  function testHosts(hosts) {
    const results = [];
    const next = (i) => {
      if (!pg) return;
      if (i >= hosts.length) {
        if (results.length === 0) return;
        const bad = results.filter((r) => !r.ok);
        pg.win.say(bad.length === 0 ? "Signed in to " + results.map((r) => pg.hostName(r.host)).join(", ") + " with it"
          : bad.map((r) => pg.hostName(r.host)).join(", ") + " did not let it in", bad.length > 0);
        if (bad.length === 1) {
          const r = bad[0];
          pg.win.card_({ question: pg.hostName(r.host) + " did not let it in", glyph: "", ink: Zenon.yellow,
            detail: D.SSH_WHY[r.why] || "", items: r.line ? [r.line] : [], choices: [{ label: "OK", ink: Zenon.accentMuted }] });
        }
        return;
      }
      const h = hosts[i];
      pg.win.act("sshTest", { host: h }, { repo: null, network: true, refresh: false, label: "Trying " + pg.hostName(h),
        then: (res) => { results.push(res); const t = Object.assign({}, pg.tests); t[h] = res; pg.tests = t; next(i + 1); },
        failed: (err) => { pg.win.fail("ssh did not run", null, err); } });
    };
    next(0);
  }

  // ── ON A KEY ───────────────────────────────────────────────────────────
  function test(k) {
    if (!k) return;
    if (k.hosts.length === 0) { pg.useFor(k); return; }
    pg.testHosts(k.hosts);
  }
  function useFor(k) {
    if (!k) return;
    const hosts = D.keyHosts().filter((h) => k.hosts.indexOf(h.host) < 0);
    pg.win.ask({ title: "Use " + k.name + " for…", glyph: "",
      detail: "~/.ssh/config is told to offer this key to each host ticked — a block added, nothing else in the file changed.",
      fields: [{ key: "other", label: "Another host", hint: "git.example.org", optional: true }],
      toggles: hosts.map((h) => ({ key: "h:" + h.host, label: h.name, value: false })),
      verb: "Use it",
      then: (v) => {
        const chosen = hosts.filter((h) => v["h:" + h.host]).map((h) => h.host);
        const other = D.hostOf(v.other);
        if (other && chosen.indexOf(other) < 0) chosen.push(other);
        if (chosen.length === 0) return;
        pg.giveTo(k, chosen, !!(pg.st && pg.st.agent), 0, () => pg.register(k, chosen, () => pg.testHosts(chosen)));
      } });
  }
  function addToForge(k) {
    if (!k) return;
    const have = (pg.on[k.public] || []).map((x) => x.forge);
    const ids = D.FORGE_ORDER.filter((id) => have.indexOf(id) < 0);
    if (ids.length === 0) { pg.win.say("Every forge Delphi knows has it already"); return; }
    pg.win.ask({ title: "Add " + k.name + " to…", glyph: "",
      detail: "The public key, added to your account on each forge ticked (you need to be signed in there).",
      toggles: ids.map((id) => ({ key: "f:" + id, label: D.FORGES[id].name, value: false })),
      verb: "Add",
      then: (v) => { const pick = ids.filter((id) => v["f:" + id]); if (pick.length > 0) pg.addTo(k, pick, null); } });
  }
  // REMEMBERED: the agent keeps the passphrase after the key's first use
  // in a login (AddKeysToAgent in its ~/.ssh/config blocks), or forgets it
  // now and asks every time (user, 2026-10-25)
  function toggleRemember(k) {
    if (!k) return;
    if (k.passphrase === false) { pg.win.say(k.name + " has no passphrase — nothing to remember"); return; }
    if (k.hosts.length === 0) { pg.win.say("Use " + k.name + " for a host first (u)"); return; }
    const on = !k.remember;
    pg.win.act("sshRemember", { key: k.path, on: on }, { repo: null, refresh: false, label: on ? "Remembering" : "Forgetting",
      then: (r) => {
        pg.reload();
        pg.win.say(!on ? "Its passphrase is asked every time now"
          : r.agent ? "Remembered after you type it once — until you log out"
          : "Set — but no agent runs to keep it: it starts at your next login");
      } });
  }
  // to the trash — asked twice, the second time naming what stops working
  function remove(k) {
    if (!k) return;
    const uses = pg.usesOf(k);
    pg.win.confirm({ question: "Delete " + k.name + "?", glyph: "", ink: Zenon.red,
      detail: "The key pair goes to the trash, and its lines leave ~/.ssh/config.",
      items: uses.length > 0 ? ["Used for: " + uses.join(", ")] : [],
      verb: "Delete",
      then: () => pg.win.confirm({ question: "Really delete " + k.name + "?", glyph: "", ink: Zenon.red,
        detail: (k.signing ? "Your commits are signed with it: signing stops working until you choose another key. " : "")
          + (k.hosts.length > 0 ? "ssh can no longer sign in to " + k.hosts.join(", ") + " with it. " : "")
          + "A new key is not the same key — a host has to be given the new one.",
        verb: "Delete it",
        then: () => pg.win.act("sshRemove", { key: k.path }, { repo: null, refresh: false, label: "Deleting",
          then: () => {
            const on = pg.on[k.public] || [];
            pg.reload();
            if (on.length === 0) { pg.win.say("Moved " + k.name + " to the trash"); return; }
            const names = on.map((x) => D.FORGES[x.forge] ? D.FORGES[x.forge].name : x.forge);
            pg.win.card_({ question: "Take it off " + names.join(" and ") + " too?", glyph: "", ink: Zenon.ink,
              detail: k.name + " is in the trash. The forges still accept it; with the key gone here, nothing needs it there.",
              choices: [{ label: "Take it off", ink: Zenon.cyan, run: () => on.forEach((x) =>
                            pg.win.act(x.forge + "DeleteSshKey", { id: x.id }, { repo: null, network: true, refresh: false,
                              label: "Removing it from " + (D.FORGES[x.forge] ? D.FORGES[x.forge].name : x.forge),
                              then: () => pg.reload() })) },
                        { label: "Leave it", ink: Zenon.accentMuted }] });
          } }) }) });
  }
  function menuFor(k) {
    return [
      { text: "Test it", icon: "", mark: "t", enabled: k.hosts.length > 0, run: () => pg.test(k) },
      { text: "Use it for a host…", icon: "", mark: "u", run: () => pg.useFor(k) },
      { text: "Add it to a forge…", icon: "", mark: "a", run: () => pg.addToForge(k) },
      { text: "Remember the passphrase", icon: k.remember ? "" : "", mark: "m",
        enabled: k.passphrase !== false && k.hosts.length > 0, run: () => pg.toggleRemember(k) },
      { text: "Copy the public key", icon: "", mark: "c", run: () => pg.win.copy(k.public, "the public key") },
      { isSeparator: true },
      { text: "Delete", icon: "", mark: "d", danger: true, run: () => pg.remove(k) },
    ];
  }

  function key(e) {
    const k = e.key;
    if (e.modifiers & Qt.ControlModifier) return false;
    if (k === Qt.Key_N) { pg.newKey([]); return true; }
    if (k === Qt.Key_Up || k === Qt.Key_K) { pg.moveTo(pg.sel - 1); return true; }
    if (k === Qt.Key_Down || k === Qt.Key_J) { pg.moveTo(pg.sel + 1); return true; }
    if (!pg.key_) return false;
    if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_T) { pg.test(pg.key_); return true; }
    if (k === Qt.Key_U) { pg.useFor(pg.key_); return true; }
    if (k === Qt.Key_A) { pg.addToForge(pg.key_); return true; }
    if (k === Qt.Key_M) { pg.toggleRemember(pg.key_); return true; }
    if (k === Qt.Key_C) { pg.win.copy(pg.key_.public, "the public key"); return true; }
    if (k === Qt.Key_D || k === Qt.Key_Delete) { pg.remove(pg.key_); return true; }
    if (k === Qt.Key_Menu) { menu.open(list.width / 2, (pg.sel + 1) * list.rowH - list.contentY, pg.menuFor(pg.key_), pg.sel); return true; }
    return false;
  }

  ListView {
    id: list
    anchors.fill: parent
    clip: true
    topMargin: 8
    bottomMargin: 8
    boundsBehavior: Flickable.StopAtBounds
    model: pg.keys
    readonly property int rowH: Math.round(Zenon.px(15) * 3.2)
    SelectBar { view: list; host: pg.win; index: pg.sel; on: pg.keys.length > 0; rowH: list.rowH; color: pg.win.hiFill; radius: Zenon.windowRadius; inset: 8 }
    delegate: Item {
      id: krow
      required property var modelData
      required property int index
      readonly property var k: krow.modelData
      width: list.width
      height: list.rowH
      Text {
        id: kglyph
        x: 24
        width: 22
        anchors.verticalCenter: parent.verticalCenter
        text: ""
        color: krow.k.passphrase === false ? Zenon.yellow : krow.index === pg.sel ? Zenon.ink : Zenon.accentSoft
        font.family: Zenon.glyphFace
        font.pixelSize: Zenon.px(16)
      }
      Column {
        anchors.left: kglyph.right
        anchors.leftMargin: 8
        anchors.right: kuse.left
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3
        Text {
          textFormat: Text.PlainText
          width: parent.width
          elide: Text.ElideRight
          text: krow.k.name
          color: krow.index === pg.sel ? Zenon.ink : Zenon.accentSoft
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(15)
        }
        Text {
          width: parent.width
          elide: Text.ElideRight
          text: [krow.k.type,
                 krow.k.passphrase === true ? (krow.k.remember ? "passphrase, remembered" : "passphrase, asked every time")
                   : krow.k.passphrase === false ? "no passphrase" : "",
                 krow.k.loaded ? "in the agent" : "",
                 krow.k.private ? "" : "public half only",
                 krow.k.fingerprint].filter((x) => x !== "").join("  ·  ")
          color: Zenon.accentMuted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(13)
        }
      }
      // what it is for, a tested host marked how it answered
      Text {
        id: kuse
        anchors.right: parent.right
        anchors.rightMargin: 24
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, list.width * 0.45)
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignRight
        textFormat: Text.StyledText
        text: pg.usesLine(krow.k) || "not used yet"
        color: pg.usesOf(krow.k).length > 0 ? Zenon.accentSoft : Zenon.accentMuted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(13)
      }
      HeldRing { anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8; on: menu.isOpen && menu.held === krow.index }
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (m) => {
          pg.moveTo(krow.index);
          if (m.button === Qt.RightButton) {
            const p = mapToItem(pg, m.x, m.y);
            menu.open(p.x, p.y, pg.menuFor(krow.k), krow.index);
            return;
          }
          pg.win.focusKeys();
        }
        onDoubleClicked: pg.test(krow.k)
      }
    }
    EmptyState {
      anchors.centerIn: parent
      visible: !!pg.st && pg.keys.length === 0
      text: !pg.st ? "" : !pg.st.ssh ? "openssh is not installed — Install openssh, above" : "No SSH keys yet — make one (n)"
    }
  }
  ElasticScroll { anchors.fill: list; view: list }
  Scrollbar { flick: list; anchors.right: list.right; anchors.top: list.top; anchors.bottom: list.bottom }

  PopMenu {
    id: menu
    anchors.fill: parent
    window: pg.win
    cardWidth: 280
    onClosed: pg.win.focusKeys()
  }
}
