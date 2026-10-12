// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A LOCKED VAULT — the window's whole right side while the account in view
// is locked: its platform's face, its name and who, and the suite's password
// field (ceres/PasswordField, calypso's own once — the lock breathing, the
// dots, the shake). Several locked and none open: a switch (terminus'
// Segments) says which one the field is for.
//
// A platform that keeps its own session (Proton Pass) asks for nothing: an
// Open button instead of the field.
//
// It draws; the window hands it the keys (key(e), keyUp(e)).

import QtQuick
import "../morpheus"
import "../terminus"
import "../ceres"
import "calypso.js" as C

Item {
  id: lock
  property var win: null
  property var acct: null
  // the locked accounts to choose among (more than one: the switch)
  property var choices: []
  readonly property var st: lock.win && lock.acct ? (lock.win.mgr.states[lock.acct.id] || {}) : ({})
  readonly property var info: lock.win && lock.acct ? lock.win.mgr.platformInfo(lock.acct.kind) : null
  // what stands between it and opening: its tool missing (installed through
  // Ceres here), or the tool signed out (signed in again here) — the
  // password field only once neither (user, 2026-10-12: "bw is not
  // installed" with only a password field under it)
  readonly property bool missing: lock.st.installed === false || (!!lock.info && !lock.info.installed)
  readonly property bool signedOut: !lock.missing && lock.st.configured === false
  readonly property bool asks: !lock.missing && !lock.signedOut && (!lock.info || lock.info.asks !== "")
  readonly property var p: C.platform(lock.acct ? lock.acct.kind : "")
  property string failure: ""
  property bool busy: false

  function key(e) {
    if (!lock.asks) {
      if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { lock.act(); return true; }
      return false;
    }
    if (e.key === Qt.Key_Escape && field.pw === "") return false;
    if ((e.key === Qt.Key_Tab || e.key === Qt.Key_Backtab) && lock.choices.length > 1) {
      const ids = lock.choices.map((a) => a.id);
      const i = ids.indexOf(lock.acct.id);
      lock.win.lockTarget = ids[(i + (e.key === Qt.Key_Tab ? 1 : ids.length - 1)) % ids.length];
      return true;
    }
    return field.key(e);
  }
  function keyUp(e) { if (lock.asks) field.keyUp(e); }

  function act() {
    if (lock.missing) lock.win.installFor(lock.acct);
    else if (lock.signedOut) lock.win.askSetup(lock.acct.kind, "", lock.acct);
    else lock.submit("");
  }
  function submit(secret) {
    if (!lock.acct || lock.busy) return;
    lock.busy = true;
    lock.failure = "";
    lock.win.mgr.unlock(lock.acct, secret, (ok, err) => {
      lock.busy = false;
      if (ok) return;
      if (err && err.kind === "auth") { field.failed = true; lock.failure = C.authNote(err); }
      else lock.failure = C.failWords(err);
    });
  }
  onAcctChanged: { lock.failure = ""; field.pw = ""; field.failed = false; }

  Column {
    anchors.centerIn: parent
    anchors.verticalCenterOffset: -30
    width: Math.min(parent.width - 80, 460)
    spacing: 14

    ItemTile {
      anchors.horizontalCenter: parent.horizontalCenter
      size: 84
      ringed: false
      glyph: lock.p.glyph
      ink: lock.p.ink
      lit: true
    }
    Column {
      width: parent.width
      spacing: 4
      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: lock.acct ? lock.acct.name : ""
        color: Zenon.ink
        font.family: Zenon.face
        font.weight: Font.Bold
        font.pixelSize: Zenon.px(22)
      }
      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideMiddle
        text: lock.st.user ? lock.p.name + "  ·  " + lock.st.user : lock.p.name
        color: Zenon.muted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(14)
      }
    }
    // which one, when several are locked
    Segments {
      anchors.horizontalCenter: parent.horizontalCenter
      visible: lock.choices.length > 1
      options: lock.choices.map((a) => [a.id, a.name])
      current: lock.acct ? lock.acct.id : ""
      onChose: (v) => lock.win.lockTarget = v
    }
    Item { width: 1; height: 4 }
    Rectangle {
      visible: lock.asks
      width: parent.width
      height: 76
      radius: Zenon.windowRadius + 4
      color: Zenon.wash(0.04)
      border.width: 1
      border.color: Zenon.border
      PasswordField {
        id: field
        anchors.fill: parent
        grow: 2
        washRadius: Zenon.windowRadius + 4
        busy: lock.busy
        prompt: C.unlockPrompt(lock.info ? lock.info.asks : "password")
        purpose: lock.busy ? "unlocking…" : "unlocks " + (lock.acct ? lock.acct.name : "the vault")
        onSubmitted: (pw) => lock.submit(pw)
        onCancelled: lock.win.unwind()
      }
    }
    BusyButton {
      visible: !lock.asks
      anchors.horizontalCenter: parent.horizontalCenter
      label: lock.missing ? "Install " + (lock.info ? lock.info.pkg : lock.p.name)
        : lock.signedOut ? "Sign in to " + lock.p.name : "Open " + (lock.acct ? lock.acct.name : "")
      ink: Zenon.cyan
      primary: true
      busy: lock.busy || (lock.missing && !!lock.win && !!lock.win.mgr.installing)
      busyText: lock.missing ? "Installing…" : "Opening…"
      onClicked: lock.act()
    }
    Text {
      visible: lock.missing || lock.signedOut
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.Wrap
      text: lock.missing
        ? lock.p.name + " is read through " + (lock.info ? lock.info.cli : "its own tool") + ", which is not installed. Ceres installs it"
          + (lock.info && lock.info.aur ? " from the AUR" : "") + " — it asks for your password."
        : lock.p.name + " is signed out on this machine. Sign in once; after that the master password opens it."
      color: Zenon.muted
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(13)
    }
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.Wrap
      visible: text !== ""
      text: lock.failure !== "" ? lock.failure : lock.missing || lock.signedOut ? "" : lock.st.error || ""
      color: Zenon.red
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(13)
    }
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.Wrap
      text: lock.info ? lock.info.blurb : ""
      color: Zenon.alpha(Zenon.muted, 0.8)
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(12)
    }
  }
}
