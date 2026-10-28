// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// HERMES' WINDOW — the four sections chosen in the head, as System Journal
// (hestia) lays its pages out (user, 2026-10-21), the section full width
// under it:
//
//   Network     the wired links and their facts; Wi-Fi's networks
//   Bluetooth   the adapter, your devices, the ones nearby
//   VPN         the connections, up and down; Import…
//   Display     brightness per screen; the night light
//   Printers    CUPS' printers and jobs, adding one; SANE's scanners
//
// Every piece that is missing is set up from its own page (HermesSetup,
// through Ceres). A passphrase is asked for on a sheet, and so is the one
// thing Hermes does that changes how the machine works: swapping
// systemd-networkd for NetworkManager.
//
//   ↑ ↓  the list           return  join, connect, up or down
//   ctrl+1…5  section       delete  forget (a printer: remove)
//   ctrl+r    look again    s       search (Bluetooth)
//   esc       closes

import QtQuick
import Quickshell
import "../morpheus"
import "../morpheus/controls" as Ctl
import "../terminus"
import "../ceres" as Cer
import "hermes.js" as H

FloatingWindow {
  id: hw
  title: "hermes"
  color: Zenon.alpha(Zenon.layerBg, 0)
  // the size the user keeps it at (2026-10-21: 820 × 720, read off the
  // open window) — narrower since the sidebar went into the head
  implicitWidth: 820
  implicitHeight: 720
  minimumSize: Qt.size(820, 520)

  readonly property int headH: 60
  readonly property string section: Hermes.section

  onVisibleChanged: {
    if (hw.visible) { Hermes.hold(); return; }
    Hermes.release();
    Qt.callLater(() => { Hermes.retire(hw); hw.destroy(); });
  }
  onClosed: hw.visible = false
  Component.onCompleted: Hermes.hold()

  // ── THE PAGE IN VIEW, AND ITS CURSOR ───────────────────────────────────
  // the Printers page, loaded by file (see printPage)
  readonly property var printItem: printPage.item
  readonly property var page: ({ network: netPage, bluetooth: btPage, vpn: vpnPage, display: dispPage, printers: hw.printItem })[hw.section] || netPage
  // the cursor shows once the keys have been used, as terminus' does
  property bool listFocus: false
  function move(d) {
    const p = hw.page;
    if (!p || p.count === 0) return;
    hw.listFocus = true;
    p.sel = Math.max(0, Math.min(p.count - 1, p.sel + d));
  }
  function rowNow() {
    const p = hw.page;
    if (!p) return null;
    if (p === netPage) return Hermes.networks[p.sel] || null;
    if (p === btPage) return btPage.rowAt(p.sel);
    if (p === vpnPage) return vpnPage.rows[p.sel] || null;
    if (p === hw.printItem) return p.rows[p.sel] || null;
    return null;
  }
  // the row flashes, then it acts (user, 2026-10-21: morpheus/RowFlash)
  RowFlash { id: listFlash }
  readonly property alias rowFlash: listFlash
  function activate() {
    const r = hw.rowNow(), p = hw.page;
    if (!r) return;
    hw.listFocus = true;
    listFlash.flashThen(p.sel, () => hw.activateNow(r), () => hw.page === p ? p.sel : -1);
  }
  function activateNow(r) {
    // a row clicked is a row chosen: its cursor and its Forget show
    hw.listFocus = true;
    if (hw.page === netPage) {
      if (Hermes.join(r, "") === "ask") { hw.pskNet = r; hw.pskFailed = false; }
    } else if (hw.page === btPage) Hermes.toggleDevice(r);
    else if (hw.page === vpnPage) {
      if (!r.managed) Hermes.tell("Without NetworkManager, " + r.name + " is only shown here", true);
      else Hermes.toggleVpn(r);
    }
  }
  function forgetNow() {
    const r = hw.rowNow();
    if (!r) return;
    if (hw.page === netPage) Hermes.forget(r);
    else if (hw.page === btPage && r.paired) Hermes.forgetDevice(r);
    else if (hw.page === hw.printItem) hw.page.remove(r);
  }
  // what a section says beside its name in the head (the sidebar's counts)
  function sectionCount(id) {
    let c = "";
    if (id === "network") c = Hermes.wifiNet ? Hermes.wifiNet.name
      : Hermes.wired && Hermes.wired.carrier ? H.speedWords(Hermes.wired.speed) : "";
    else if (id === "bluetooth") c = Hermes.btConnected > 0 ? String(Hermes.btConnected) : "";
    else if (id === "vpn") c = Hermes.vpnActive !== "" ? "On" : "";
    else if (id === "printers") c = hw.printItem && hw.printItem.info.jobs.length > 0 ? String(hw.printItem.info.jobs.length) : "";
    else c = Hermes.nightActive ? "Night" : "";
    // a long network name would push the segments into the name and buttons
    if (c.length > 16) c = c.slice(0, 15) + "\u2026";
    return c !== "" ? "  " + c : "";
  }
  function setSection(id) {
    listFlash.cancel();
    Hermes.setSection(id);
    hw.listFocus = false;
    pageFlick.contentY = 0;
  }

  // ── THE SHEETS' STATE ──────────────────────────────────────────────────
  property var pskNet: null
  property bool pskFailed: false
  property bool askSwitch: false
  function submitPsk(pw) {
    if (!hw.pskNet || pw === "") return;
    Hermes.join(hw.pskNet, pw);
    hw.pskNet = null;
    hw.refocus();
  }
  Connections {
    target: Hermes
    function onAskAgain(name) {
      if (!hw.visible) return;
      const n = Hermes.networks.find((x) => x.name === name);
      if (!n) return;
      hw.pskNet = n;
      hw.pskFailed = true;
    }
  }
  function refocus() { Qt.callLater(() => keySink.forceActiveFocus()); }

  // ── KEYS ───────────────────────────────────────────────────────────────
  Item {
    id: keySink
    focus: true
    Keys.onPressed: (e) => {
      const ctrl = e.modifiers & Qt.ControlModifier;
      e.accepted = true;
      if (hw.pskNet) {
        if (e.key === Qt.Key_Escape && pskField.pw === "") { hw.pskNet = null; return; }
        pskField.key(e);
        return;
      }
      if (hw.askSwitch) {
        if (e.key === Qt.Key_Escape) hw.askSwitch = false;
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { hw.askSwitch = false; Hermes.setup("networkmanager"); }
        return;
      }
      if (e.key === Qt.Key_Escape) { hw.visible = false; return; }
      if (ctrl && e.key >= Qt.Key_1 && e.key < Qt.Key_1 + H.SECTIONS.length) { hw.setSection(H.SECTIONS[e.key - Qt.Key_1].id); return; }
      if (ctrl && e.key === Qt.Key_R) {
        Hermes.reprobe();
        if (hw.section === "display") Hermes.readDdc();
        if (hw.section === "printers" && hw.printItem) hw.printItem.look();
        return;
      }
      if (e.key === Qt.Key_S && hw.section === "bluetooth" && Hermes.btReady) { Hermes.scan(!Hermes.btScanning); return; }
      if (e.key === Qt.Key_Down || (ctrl && e.key === Qt.Key_J)) { hw.move(1); return; }
      if (e.key === Qt.Key_Up || (ctrl && e.key === Qt.Key_K)) { hw.move(-1); return; }
      if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { hw.activate(); return; }
      if (e.key === Qt.Key_Delete) { hw.forgetNow(); return; }
      e.accepted = false;
    }
    Keys.onReleased: (e) => { if (hw.pskNet) pskField.keyUp(e); }
  }

  // ── THE STAGE ──────────────────────────────────────────────────────────
  Item {
    id: stage
    anchors.fill: parent

    Rectangle { z: -1; anchors.fill: parent; color: Zenon.layerBg }

    // ── the head ─────────────────────────────────────────────────────────
    // System Journal's head (user, 2026-10-21: "control hub gets the same
    // layout"): the name on the left, the four sections as Segments in the
    // middle with what each has to say beside it, the page's buttons on the
    // right — no sidebar, the page full width under it
    Item {
      id: head
      z: 3
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      height: hw.headH
      Rectangle { anchors.fill: parent; color: Zenon.headBg }
      Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Zenon.border }
      Column {
        id: brandWords
        x: 20
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, sections.x - x - 16)
        spacing: 1
        Text {
          // the window's own name (user, 2026-10-20); the app is still hermes
          text: "Control Hub"
          color: Zenon.ink
          font.family: Zenon.face
          font.weight: Zenon.titleWeight
          font.pixelSize: Zenon.px(17)
        }
        Text {
          width: parent.width
          elide: Text.ElideRight
          text: Hermes.probe.known ? "Network by " + H.stacksShort(Hermes.probe) : "Looking…"
          color: Zenon.accentMuted
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(12)
        }
      }
      // on the right, before the page's own buttons (user, 2026-10-22)
      Segments {
        id: sections
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: headBtns.left
        anchors.rightMargin: headBtns.width > 0 ? 12 : 0
        options: H.SECTIONS.map((s) => [s.id, s.label + hw.sectionCount(s.id)])
        current: hw.section
        onChose: (v) => hw.setSection(v)
      }
      Row {
        id: headBtns
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        BusyButton {
          visible: hw.section === "bluetooth" && Hermes.btReady && Hermes.btOn
          label: "Search"
          busy: Hermes.btScanning
          busyText: "Searching…"
          onClicked: Hermes.scan(!Hermes.btScanning)
        }
        DialogButton {
          visible: hw.section === "vpn" && Hermes.nmRunning
          label: "Import…"
          onClicked: Hermes.chooseVpnFile()
        }
        DialogButton {
          visible: hw.listFocus && hw.section === "network" && Hermes.wifiReady && !!hw.rowNow() && !!hw.rowNow().known
          label: "Forget"
          onClicked: hw.forgetNow()
        }
        DialogButton {
          visible: hw.listFocus && hw.section === "bluetooth" && !!hw.rowNow() && !!hw.rowNow().paired
          label: "Forget"
          onClicked: hw.forgetNow()
        }
      }
    }

    // ── the page ─────────────────────────────────────────────────────────
    Flickable {
      id: pageFlick
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: head.bottom
      anchors.bottom: foot.top
      contentHeight: pageBox.height + 48
      boundsBehavior: Flickable.StopAtBounds
      clip: true

      Item {
        id: pageBox
        x: 28
        y: 24
        width: pageFlick.width - 56
        height: hw.page ? hw.page.implicitHeight : 0

        HermesNetwork { id: netPage; width: parent.width; win: hw; visible: hw.section === "network" }
        HermesBluetooth { id: btPage; width: parent.width; win: hw; visible: hw.section === "bluetooth" }
        HermesVpn { id: vpnPage; width: parent.width; win: hw; visible: hw.section === "vpn" }
        HermesDisplay { id: dispPage; width: parent.width; win: hw; visible: hw.section === "display" }
        // by file, so a new page needs no shell restart (a qmldir type does)
        Loader {
          id: printPage
          width: parent.width
          active: hw.section === "printers" || !!printPage.item
          visible: hw.section === "printers"
          source: "HermesPrint.qml"
          onLoaded: hw.printItem.win = hw
        }
      }
    }
    ElasticScroll { anchors.fill: pageFlick; view: pageFlick }
    Scrollbar { flick: pageFlick; anchors.right: pageFlick.right; anchors.top: pageFlick.top; anchors.bottom: pageFlick.bottom }
    ScrollEdge { view: pageFlick; follow: true; bar: head }
    ScrollEdge { view: pageFlick; below: true; follow: true; bar: foot }

    // ── what was just done, said once ────────────────────────────────────
    Ctl.Said {
      anchors.horizontalCenter: pageFlick.horizontalCenter
      anchors.bottom: foot.top
      anchors.bottomMargin: 18
      text: Hermes.said
      bad: Hermes.saidBad
    }

    // ── the foot ─────────────────────────────────────────────────────────
    HintBar {
      id: foot
      anchors.bottom: parent.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      rows: hw.hintRows
    }
  }

  readonly property var hintRows: hw.pskNet ? [["return", "join"], ["esc", "back"]]
    : hw.askSwitch ? [["return", "switch"], ["esc", "cancel"]]
    : hw.section === "network" && Hermes.wifiReady ? [["↑↓", "network"], ["return", "join, leave"], ["delete", "forget"], ["ctrl 1-5", "section"], ["esc", "close"]]
    : hw.section === "bluetooth" && Hermes.btReady ? [["↑↓", "device"], ["return", "connect"], ["s", "search"], ["delete", "forget"], ["ctrl 1-5", "section"], ["esc", "close"]]
    : hw.section === "printers" && hw.page && hw.page.count > 0 ? [["↑↓", "printer"], ["delete", "remove"], ["ctrl 1-5", "section"], ["ctrl r", "look again"], ["esc", "close"]]
    : hw.section === "vpn" && Hermes.vpns.length > 0 ? [["↑↓", "connection"], ["return", "up, down"], ["ctrl 1-5", "section"], ["esc", "close"]]
    : [["ctrl 1-5", "section"], ["ctrl r", "look again"], ["esc", "close"]]

  // ── the passphrase, on a sheet ─────────────────────────────────────────
  InputShield { visible: !!hw.pskNet; onClicked: { hw.pskNet = null; hw.refocus(); } }
  Sheet {
    shown: !!hw.pskNet
    fromTop: hw.headH
    cardW: Math.min(hw.width - 80, 560)
    cardH: pskCol.implicitHeight + 40
    Column {
      id: pskCol
      x: 22
      y: 20
      width: parent.width - 44
      spacing: 14
      Row {
        spacing: 12
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: H.G.wifiLock
          color: Zenon.cyan
          font.family: Zenon.glyphFace
          font.pixelSize: Zenon.px(18)
        }
        Text {
          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          text: hw.pskNet ? "Join " + hw.pskNet.name : ""
          color: Zenon.ink
          font.family: Zenon.face
          font.weight: Zenon.titleWeight
          font.pixelSize: Zenon.px(19)
        }
      }
      Cer.PasswordField {
        id: pskField
        width: parent.width
        washRadius: Zenon.windowRadius
        failed: hw.pskFailed
        prompt: "password"
        purpose: hw.pskFailed ? "that password was not right" : hw.pskNet ? H.securityWords(hw.pskNet.security) : ""
        onSubmitted: (pw) => hw.submitPsk(pw)
        onCancelled: { hw.pskNet = null; hw.refocus(); }
      }
    }
  }
  onPskNetChanged: if (hw.pskNet) keySink.forceActiveFocus()

  // ── swapping the network stack: said plainly before it is done ─────────
  InputShield { visible: hw.askSwitch; onClicked: { hw.askSwitch = false; hw.refocus(); } }
  Sheet {
    shown: hw.askSwitch
    fromTop: hw.headH
    cardW: Math.min(hw.width - 80, 600)
    cardH: switchCol.implicitHeight + 40
    Column {
      id: switchCol
      x: 22
      y: 20
      width: parent.width - 44
      spacing: 14
      Text {
        text: "Switch to NetworkManager?"
        color: Zenon.ink
        font.family: Zenon.face
        font.weight: Zenon.titleWeight
        font.pixelSize: Zenon.px(19)
      }
      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        text: "Ceres installs NetworkManager, turns " + H.stackWords(Hermes.probe.stack)
          + " off and starts NetworkManager in its place, now and at every boot. The network drops for a few seconds while they swap. "
          + "A wired link set up by DHCP comes straight back; a static address or anything set in /etc/systemd/network has to be set again in NetworkManager."
        color: Zenon.accentMuted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(14)
      }
      Row {
        spacing: 8
        DialogButton { label: "Cancel"; onClicked: { hw.askSwitch = false; hw.refocus(); } }
        DialogButton {
          label: "Switch"
          primary: true
          onClicked: { hw.askSwitch = false; Hermes.setup("networkmanager"); hw.refocus(); }
        }
      }
    }
  }
  onAskSwitchChanged: if (hw.askSwitch) keySink.forceActiveFocus()
}
