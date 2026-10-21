// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// HERMES' WINDOW — the four sections in a sidebar, as Calypso and Ceres lay
// theirs out, and the section on the right:
//
//   Network     the wired links and their facts; Wi-Fi's networks
//   Bluetooth   the adapter, your devices, the ones nearby
//   VPN         the connections, up and down; Import…
//   Display     brightness per screen; the night light
//
// Every piece that is missing is set up from its own page (HermesSetup,
// through Ceres). A passphrase is asked for on a sheet, and so is the one
// thing Hermes does that changes how the machine works: swapping
// systemd-networkd for NetworkManager.
//
//   ↑ ↓  the list           return  join, connect, up or down
//   ctrl+1…4  section       delete  forget
//   ctrl+r    look again    s       search (Bluetooth)
//   esc       closes

import QtQuick
import Quickshell
import "../morpheus"
import "../terminus"
import "../ceres" as Cer
import "hermes.js" as H

FloatingWindow {
  id: hw
  title: "hermes"
  color: Zenon.alpha(Zenon.layerBg, 0)
  implicitWidth: 1080
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
  readonly property var page: ({ network: netPage, bluetooth: btPage, vpn: vpnPage, display: dispPage })[hw.section] || netPage
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
    return null;
  }
  function activate() {
    const r = hw.rowNow();
    if (!r) return;
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
  }
  function setSection(id) {
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
      if (ctrl && e.key >= Qt.Key_1 && e.key <= Qt.Key_4) { hw.setSection(H.SECTIONS[e.key - Qt.Key_1].id); return; }
      if (ctrl && e.key === Qt.Key_R) {
        Hermes.reprobe();
        if (hw.section === "display") Hermes.readDdc();
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

    Rectangle { z: -1; x: side.width; width: parent.width - x; height: parent.height; color: Zenon.layerBg }

    // ── the sidebar ──────────────────────────────────────────────────────
    Item {
      id: side
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: 240

      // terminus' and calypso's two layers: an inactive tab's glass, then
      // the sheet's veil over it
      Rectangle { anchors.fill: parent; color: Zenon.alpha(Zenon.tabAwayInk, Zenon.tabAway(Zenon.layerBg.a)) }
      Rectangle { anchors.fill: parent; color: Zenon.ground; opacity: 0.6 }
      Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Zenon.border }

      Item {
        id: brand
        width: parent.width
        height: hw.headH
        Text {
          id: brandGlyph
          x: 20
          anchors.verticalCenter: parent.verticalCenter
          // hermes' own glyph, U+F1542, as cynosure and icarus show it
          text: "\u{F1542}"
          color: Zenon.cyan
          font.family: Zenon.glyphFace
          font.pixelSize: Zenon.px(20)
        }
        Column {
          anchors.left: brandGlyph.right
          anchors.leftMargin: 12
          anchors.right: parent.right
          anchors.rightMargin: 12
          anchors.verticalCenter: parent.verticalCenter
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
      }

      Column {
        anchors.top: brand.bottom
        anchors.topMargin: 4
        width: parent.width
        spacing: 1
        Repeater {
          model: H.SECTIONS
          delegate: ShelfRow {
            required property var modelData
            width: parent.width
            radius: 0
            indent: 18
            glyph: modelData.glyph
            label: modelData.label
            here: hw.section === modelData.id
            count: {
              const id = modelData.id;
              if (id === "network") return Hermes.wifiNet ? Hermes.wifiNet.name
                : Hermes.wired && Hermes.wired.carrier ? H.speedWords(Hermes.wired.speed) : "";
              if (id === "bluetooth") return Hermes.btConnected > 0 ? String(Hermes.btConnected) : "";
              if (id === "vpn") return Hermes.vpnActive !== "" ? "On" : "";
              return Hermes.nightActive ? "Night" : "";
            }
            countInk: Zenon.accentMuted
            onClicked: hw.setSection(modelData.id)
          }
        }
      }
    }

    // ── the head ─────────────────────────────────────────────────────────
    Item {
      id: head
      anchors.left: side.right
      anchors.right: parent.right
      anchors.top: parent.top
      height: hw.headH
      Rectangle { anchors.fill: parent; color: Zenon.headBg }
      Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Zenon.border }
      Text {
        id: headTitle
        anchors.left: parent.left
        anchors.leftMargin: 24
        anchors.verticalCenter: parent.verticalCenter
        text: (H.SECTIONS.find((s) => s.id === hw.section) || H.SECTIONS[0]).label
        color: Zenon.ink
        font.family: Zenon.face
        font.weight: Zenon.titleWeight
        font.pixelSize: Zenon.px(19)
      }
      Text {
        anchors.left: headTitle.right
        anchors.leftMargin: 12
        anchors.baseline: headTitle.baseline
        anchors.right: headBtns.left
        anchors.rightMargin: 16
        elide: Text.ElideRight
        text: hw.section === "network" ? (Hermes.wired ? Hermes.wired.name : Hermes.wifiDevice ? Hermes.wifiDevice.name : "")
          : hw.section === "bluetooth" ? (Hermes.btReady && Hermes.btOn ? Hermes.btConnected + " connected" : "")
          : hw.section === "vpn" ? (Hermes.vpnActive !== "" ? Hermes.vpnActive : "")
          : Hermes.screens.length === 1 ? "1 screen" : Hermes.screens.length > 1 ? Hermes.screens.length + " screens" : ""
        color: Zenon.accentMuted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(14)
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
          ink: Zenon.blue
          busy: Hermes.btScanning
          busyText: "Searching…"
          onClicked: Hermes.scan(!Hermes.btScanning)
        }
        DialogButton {
          visible: hw.section === "vpn" && Hermes.nmRunning
          label: "Import…"
          ink: Zenon.green
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
      anchors.left: side.right
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
      }
    }
    ElasticScroll { anchors.fill: pageFlick; view: pageFlick }
    Scrollbar { flick: pageFlick; anchors.right: pageFlick.right; anchors.top: pageFlick.top; anchors.bottom: pageFlick.bottom }
    ScrollEdge { view: pageFlick; follow: true; bar: head }
    ScrollEdge { view: pageFlick; below: true; follow: true; bar: foot }

    // ── what was just done, said once ────────────────────────────────────
    Rectangle {
      anchors.horizontalCenter: pageFlick.horizontalCenter
      anchors.bottom: foot.top
      anchors.bottomMargin: 18
      width: Math.min(saidText.implicitWidth + 32, 560)
      height: 34
      radius: Zenon.windowRadius
      color: Zenon.hud(0.85)
      border.width: 1
      border.color: Hermes.saidBad ? Zenon.alpha(Zenon.red, 0.6) : Zenon.border
      opacity: Hermes.said !== "" ? 1 : 0
      visible: opacity > 0
      Behavior on opacity { NumberAnimation { duration: Zenon.normal; easing.type: Easing.OutCubic } }
      Text {
        id: saidText
        anchors.centerIn: parent
        width: Math.min(implicitWidth, parent.width - 32)
        elide: Text.ElideRight
        text: Hermes.said
        color: Hermes.saidBad ? Zenon.red : Zenon.ink
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(15)
      }
    }

    // ── the foot ─────────────────────────────────────────────────────────
    HintBar {
      id: foot
      anchors.bottom: parent.bottom
      anchors.left: side.right
      anchors.right: parent.right
      rows: hw.hintRows
    }
  }

  readonly property var hintRows: hw.pskNet ? [["return", "join"], ["esc", "back"]]
    : hw.askSwitch ? [["return", "switch"], ["esc", "cancel"]]
    : hw.section === "network" && Hermes.wifiReady ? [["↑↓", "network"], ["return", "join, leave"], ["delete", "forget"], ["ctrl 1-4", "section"], ["esc", "close"]]
    : hw.section === "bluetooth" && Hermes.btReady ? [["↑↓", "device"], ["return", "connect"], ["s", "search"], ["delete", "forget"], ["ctrl 1-4", "section"], ["esc", "close"]]
    : hw.section === "vpn" && Hermes.vpns.length > 0 ? [["↑↓", "connection"], ["return", "up, down"], ["ctrl 1-4", "section"], ["esc", "close"]]
    : [["ctrl 1-4", "section"], ["ctrl r", "look again"], ["esc", "close"]]

  // ── the passphrase, on a sheet ─────────────────────────────────────────
  InputShield { visible: !!hw.pskNet; onClicked: { hw.pskNet = null; hw.refocus(); } }
  Sheet {
    shown: !!hw.pskNet
    fromTop: hw.headH
    leftInset: side.width
    cardW: Math.min(hw.width - side.width - 80, 560)
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
    leftInset: side.width
    cardW: Math.min(hw.width - side.width - 80, 600)
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
          ink: Zenon.yellow
          primary: true
          onClicked: { hw.askSwitch = false; Hermes.setup("networkmanager"); hw.refocus(); }
        }
      }
    }
  }
  onAskSwitchChanged: if (hw.askSwitch) keySink.forceActiveFocus()
}
