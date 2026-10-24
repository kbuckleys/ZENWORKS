// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// REMOTES — where this repository fetches from and pushes to: each one's
// name, address, HTTPS or SSH, the one the branch follows, and one that
// pushes somewhere else than it fetches from.
//
//   n add · r rename · return/e edit the addresses · s switch HTTPS ↔ SSH
//   (SSH tested first: no key that gets in, and the SSH keys page offers to
//   make one) · f fetch it · w its page on the web · d remove

import QtQuick
import Quickshell
import "../morpheus"
import "../terminus"
import "delphi.js" as D

Item {
  id: pg
  property var win: null
  readonly property var edgeViews: [list]

  readonly property string title: "Remotes"
  readonly property string subtitle: pg.rows.length === 0 ? "Not connected anywhere"
    : pg.rows.length + (pg.rows.length === 1 ? " remote" : " remotes")
  readonly property var hints: [["n", "add"], ["r", "rename"], ["e", "edit"], ["s", "ssh / https"], ["f", "fetch"], ["w", "web"], ["d", "remove"]]
  readonly property var buttons: [
    { label: "Remove", ink: Zenon.red, visible: !!pg.row, run: () => pg.remove(pg.row) },
    { label: pg.row && D.protocolOf(pg.row.fetch) === "SSH" ? "Use HTTPS" : "Use SSH",
      visible: !!pg.row && D.otherUrl(pg.row.fetch) !== "", run: () => pg.switchWay(pg.row) },
    { label: "Add remote", ink: Zenon.cyan, primary: true, run: () => pg.add() },
  ]
  function takeFocus() { if (pg.win) pg.win.focusKeys(); }
  function reload() { if (pg.win) pg.win.refreshRefs(); }

  readonly property var rows: pg.win ? pg.win.remotes : []
  property int sel: 0
  readonly property var row: pg.sel >= 0 && pg.sel < pg.rows.length ? pg.rows[pg.sel] : null
  // the remote the checked-out branch follows ("origin/main" → origin)
  readonly property string upstream: pg.win && pg.win.branch && pg.win.branch.upstream ? String(pg.win.branch.upstream).split("/")[0] : ""
  onRowsChanged: pg.sel = Math.max(0, Math.min(pg.sel, pg.rows.length - 1))
  Component.onCompleted: Qt.callLater(pg.reload)

  function moveTo(i) {
    if (pg.rows.length === 0) return;
    pg.sel = Math.max(0, Math.min(pg.rows.length - 1, i));
    list.positionViewAtIndex(pg.sel, ListView.Contain);
  }
  function selectName(name) {
    const i = pg.rows.findIndex((r) => r.name === name);
    if (i >= 0) pg.moveTo(i);
  }
  // a change: the list read again, the push menu's ticks kept by name
  function changed(said, name) {
    pg.win.say(said);
    pg.win.refreshRefs();
    if (name) Qt.callLater(() => { if (pg) pg.selectName(name); });
  }
  function hostOf(url) { const r = D.remoteOf(url); return r ? r.host : ""; }
  function forgeOf(url) {
    const h = pg.hostOf(url);
    if (h === "aur.archlinux.org") return { name: "AUR", glyph: "" };
    return D.forgeOfHost(h);
  }
  function webOf(url) {
    const r = D.remoteOf(url);
    if (!r) return "";
    // the AUR's page for a package is under /packages
    if (r.host === "aur.archlinux.org") return "https://aur.archlinux.org/packages/" + r.full.replace(/\.git$/, "");
    return r.web.replace(/\.git$/, "");
  }
  readonly property var nameOk: /^[A-Za-z0-9][A-Za-z0-9._\/-]*$/

  function add() {
    const has = (n) => pg.rows.some((r) => r.name === n);
    pg.win.ask({ title: "Add a remote", glyph: "",
      detail: "Another place this repository is kept: a forge's repository, the AUR's package, a directory on a server.",
      fields: [{ key: "url", label: "Address", hint: "git@github.com:you/name.git  or  https://…" },
               { key: "name", label: "Name", value: has("origin") ? "" : "origin", hint: "origin", why: "git needs one" }],
      toggles: [{ key: "fetch", label: "Fetch it now", value: true }],
      verb: "Add",
      then: (v) => {
        const url = v.url.trim(), name = v.name.trim();
        if (!pg.nameOk.test(name) || has(name)) { pg.win.say(has(name) ? "There is a remote called " + name + " already" : "A remote's name is letters, digits, dots and dashes", true); return; }
        pg.win.act("remoteAdd", { name: name, url: url }, { label: "Adding " + name,
          then: () => {
            pg.changed("Added " + name, name);
            if (v.fetch) pg.win.act("fetch", { remote: name }, { label: "Fetching " + name, network: true, said: "Fetched " + name });
          } });
      } });
  }
  function rename(r) {
    if (!r) return;
    pg.win.ask({ title: "Rename " + r.name, glyph: "",
      detail: "The branches that follow it follow the new name.",
      fields: [{ key: "name", label: "New name", value: r.name }], verb: "Rename",
      then: (v) => {
        const name = v.name.trim();
        if (name === r.name) return;
        if (!pg.nameOk.test(name) || pg.rows.some((x) => x.name === name)) { pg.win.say("That name is taken or not allowed", true); return; }
        const root = pg.win.root;
        pg.win.act("remoteRename", { old: r.name, "new": name }, { label: "Renaming",
          then: () => {
            // Push's ticks are kept by remote name: carried over
            const ticks = pg.win.mgr.pushTo[root];
            if (ticks) pg.win.mgr.setPushTo(root, ticks.map((n) => n === r.name ? name : n));
            pg.changed(r.name + " is " + name + " now", name);
          } });
      } });
  }
  function edit(r) {
    if (!r) return;
    const own = r.push && r.push !== r.fetch;
    pg.win.ask({ title: "Addresses of " + r.name, glyph: "",
      detail: "Pushes go where it fetches from, unless it has a push address of its own.",
      fields: [{ key: "url", label: "Fetch from", value: r.fetch },
               { key: "push", label: "Push to", value: own ? r.push : "", hint: "the same", optional: true }],
      verb: "Save",
      then: (v) => {
        const url = v.url.trim(), push = v.push.trim();
        const args = { name: r.name, url: url, push: push !== "" && push !== url ? push : (own ? "" : null) };
        pg.win.act("remoteSetUrl", args, { label: "Saving", then: () => pg.changed("Saved " + r.name, r.name) });
      } });
  }
  // HTTPS ↔ SSH. To SSH only once ssh gets in: a key that works, or the
  // way to one (the SSH keys page, its host ticked)
  function switchWay(r) {
    if (!r) return;
    const to = D.otherUrl(r.fetch);
    if (to === "") { pg.win.say("Delphi cannot tell the other address of " + r.name, true); return; }
    const own = r.push && r.push !== r.fetch;
    const apply = () => pg.win.act("remoteSetUrl", { name: r.name, url: to, push: own ? (D.otherUrl(r.push) || null) : null }, {
      label: "Switching", then: () => pg.changed(r.name + " goes over " + D.protocolOf(to) + " now", r.name) });
    if (D.protocolOf(to) !== "SSH") { apply(); return; }
    const t = D.sshTarget(to);
    pg.win.act("sshTest", { host: t.host, user: t.user }, { repo: null, label: "Trying ssh to " + t.host, network: true, refresh: false,
      failed: (err) => pg.win.fail("ssh did not run", null, err),
      then: (res) => {
        if (res.ok) { apply(); return; }
        pg.win.card_({ question: "No key gets you into " + t.host, glyph: "", ink: Zenon.yellow,
          detail: (D.SSH_WHY[res.why] || "ssh could not get in.") + " Switch once a key works, or make one now.",
          items: res.line ? [res.line] : [],
          choices: [{ label: "Make a key for it", ink: Zenon.cyan, run: () => pg.win.newKeyFor(t.host) },
                    { label: "Switch anyway", run: apply },
                    { label: "Cancel", ink: Zenon.accentMuted }] });
      } });
  }
  function remove(r) {
    if (!r) return;
    const root = pg.win.root;
    pg.win.confirm({ question: "Remove " + r.name + "?", glyph: "", ink: Zenon.red,
      detail: "Only the connection, here: " + r.fetch + " itself is not touched, and its copies of the branches here go with it.",
      verb: "Remove",
      then: () => pg.win.act("remoteRemove", { name: r.name }, { label: "Removing",
        then: () => {
          const ticks = pg.win.mgr.pushTo[root];
          if (ticks) pg.win.mgr.setPushTo(root, ticks.filter((n) => n !== r.name));
          pg.changed("Removed " + r.name);
        } }) });
  }
  function fetchOne(r) {
    if (!r) return;
    const root = pg.win.root;
    pg.win.act("fetch", { remote: r.name }, { label: "Fetching " + r.name, network: true, said: "Fetched " + r.name,
      then: () => pg.win.mgr.noteFetched(root) });
  }
  function web(r) {
    const u = r ? pg.webOf(r.push || r.fetch) : "";
    if (u) Quickshell.execDetached(["xdg-open", u]);
  }
  function menuFor(r) {
    const ssh = D.protocolOf(r.fetch) === "SSH";
    const items = [
      { text: "Edit the addresses", icon: "", mark: "e", run: () => pg.edit(r) },
      { text: "Rename", icon: "", mark: "r", run: () => pg.rename(r) },
      { text: ssh ? "Use HTTPS" : "Use SSH", icon: "", mark: "s", enabled: D.otherUrl(r.fetch) !== "", run: () => pg.switchWay(r) },
      { isSeparator: true },
      { text: "Fetch it", icon: "", mark: "f", run: () => pg.fetchOne(r) },
      { text: "Open on the web", icon: "", mark: "w", enabled: pg.webOf(r.fetch) !== "", run: () => pg.web(r) },
      { text: "Copy the address", icon: "", run: () => pg.win.copy(r.fetch, "the address") },
      { isSeparator: true },
      { text: "Remove", icon: "", mark: "d", danger: true, run: () => pg.remove(r) },
    ];
    return items;
  }

  function key(e) {
    const k = e.key;
    if (e.modifiers & Qt.ControlModifier) return false;
    if (k === Qt.Key_N) { pg.add(); return true; }
    if (k === Qt.Key_Up || k === Qt.Key_K) { pg.moveTo(pg.sel - 1); return true; }
    if (k === Qt.Key_Down || k === Qt.Key_J) { pg.moveTo(pg.sel + 1); return true; }
    if (!pg.row) return false;
    if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_E) { pg.edit(pg.row); return true; }
    if (k === Qt.Key_R) { pg.rename(pg.row); return true; }
    if (k === Qt.Key_S) { pg.switchWay(pg.row); return true; }
    if (k === Qt.Key_F) { pg.fetchOne(pg.row); return true; }
    if (k === Qt.Key_W) { pg.web(pg.row); return true; }
    if (k === Qt.Key_D || k === Qt.Key_Delete) { pg.remove(pg.row); return true; }
    if (k === Qt.Key_Menu) { menu.open(list.width / 2, (pg.sel + 1) * list.rowH - list.contentY, pg.menuFor(pg.row), pg.sel); return true; }
    return false;
  }

  ListView {
    id: list
    anchors.fill: parent
    clip: true
    topMargin: 8
    bottomMargin: 8
    boundsBehavior: Flickable.StopAtBounds
    model: pg.rows
    readonly property int rowH: Math.round(Zenon.px(15) * 3.2)
    SelectBar { view: list; host: pg.win; index: pg.sel; rowH: list.rowH; color: pg.win.hiFill; radius: Zenon.windowRadius; inset: 8 }
    delegate: Item {
      id: rrow
      required property var modelData
      required property int index
      readonly property var r: rrow.modelData
      readonly property var forge: pg.forgeOf(rrow.r.fetch)
      readonly property string way: D.protocolOf(rrow.r.fetch)
      readonly property bool ownPush: !!rrow.r.push && rrow.r.push !== rrow.r.fetch
      width: list.width
      height: list.rowH
      Text {
        id: rglyph
        x: 24
        width: 22
        anchors.verticalCenter: parent.verticalCenter
        text: rrow.forge ? rrow.forge.glyph : ""
        color: rrow.index === pg.sel ? Zenon.ink : Zenon.accentSoft
        font.family: Zenon.glyphFace
        font.pixelSize: Zenon.px(16)
      }
      Column {
        anchors.left: rglyph.right
        anchors.leftMargin: 8
        anchors.right: rway.left
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3
        Row {
          spacing: 10
          Text {
            text: rrow.r.name
            color: rrow.index === pg.sel ? Zenon.ink : Zenon.accentSoft
            font.family: Zenon.face
            font.weight: rrow.r.name === pg.upstream ? Font.Bold : Zenon.weight
            font.pixelSize: Zenon.px(15)
          }
          Text {
            anchors.baseline: parent.children[0].baseline
            visible: text !== ""
            text: (rrow.r.name === pg.upstream ? "followed by " + (pg.win.branch ? pg.win.branch.head : "this branch") : "")
              + (rrow.ownPush ? (rrow.r.name === pg.upstream ? "  ·  " : "") + "pushes elsewhere" : "")
            color: rrow.ownPush ? Zenon.yellow : Zenon.cyan
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(13)
          }
        }
        Text {
          width: parent.width
          elide: Text.ElideMiddle
          text: rrow.r.fetch + (rrow.ownPush ? "   →   " + rrow.r.push : "")
          color: Zenon.accentMuted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(13)
        }
      }
      // HTTPS or SSH, as a word at the row's end
      Text {
        id: rway
        anchors.right: parent.right
        anchors.rightMargin: 24
        anchors.verticalCenter: parent.verticalCenter
        text: rrow.way || "local"
        color: rrow.way === "SSH" ? Zenon.green : Zenon.accentMuted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(13)
      }
      HeldRing { anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8; on: menu.isOpen && menu.held === rrow.index }
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (m) => {
          pg.moveTo(rrow.index);
          if (m.button === Qt.RightButton) {
            const p = mapToItem(pg, m.x, m.y);
            menu.open(p.x, p.y, pg.menuFor(rrow.r), rrow.index);
            return;
          }
          pg.win.focusKeys();
        }
        onDoubleClicked: pg.edit(rrow.r)
      }
    }
    EmptyState { anchors.centerIn: parent; visible: pg.rows.length === 0; text: "No remotes — add one (n), or publish from Changes" }
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
