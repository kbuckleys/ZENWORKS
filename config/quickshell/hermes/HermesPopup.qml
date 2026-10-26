// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// HERMES' QUICK PANEL — the bar's icon, opened: out of the pill like every
// layer, with the four things you reach for without opening a window.
//
//   main    four tiles (the network — Wi-Fi, or the wired link where there
//           is no Wi-Fi —, Bluetooth, VPN, night light), each on or off at
//           return, lit in the one accent (HermesTile); under "Display" a
//           brightness slider per screen that can be dimmed, and the night
//           light's warmth while it is on, read in segment digits
//   wifi    the networks, joined at return; a passphrase asked for here
//   bt      the devices, connected at return; s searches for more
//   vpn     the connections NetworkManager has, up or down at return
//   psk     the passphrase for the network being joined
//
// A tile whose piece is missing (no NetworkManager, no BlueZ, no
// hyprsunset) opens the window on its section, where it is set up.
// Everything it shows and does is the Hermes singleton's.
//
//   `qs ipc call Hermes toggle`          this panel
//   `qs ipc call Hermes window <section>` the window
//   `qs ipc call Hermes night`           the night light, on or off
//   `qs ipc call Hermes wifi` / `bluetooth`   the radio, on or off

import QtQuick
import Quickshell.Io
import Quickshell.Hyprland
import "../morpheus"
import "../morpheus/gridnav.js" as Nav
import "../terminus"
import "../morpheus/controls" as Ctl
import "../ceres" as Cer
import "hermes.js" as H

LayerPopup {
  id: popup

  // main · wifi · bt · vpn · psk
  property string mode: "main"
  property int sel: 0
  property int tileSel: 0
  property var pskNet: null
  property bool joining: false

  readonly property int pad: 12
  readonly property int tileH: 64
  readonly property int headH: 46
  readonly property int cellH: 42
  readonly property int visibleRows: 7
  readonly property int emptyH: 72
  readonly property int sliderH: 36
  readonly property int labelH: 24

  focusable: true

  HyprlandFocusGrab {
    windows: [ popup ]
    active: popup.shown
    onCleared: popup.closePopup()
  }

  // ── THE TILES ──────────────────────────────────────────────────────────
  readonly property bool wifiTile: Hermes.probe.wifiHw || Hermes.wifiReady
  readonly property var tiles: {
    const p = Hermes.probe;
    const out = [];
    // the network
    if (popup.wifiTile) {
      const ready = Hermes.wifiReady;
      out.push({ id: "net", glyph: !ready || !Hermes.wifiOn ? H.G.wifiOff : Hermes.wifiNet ? H.wifiGlyph(Hermes.wifiNet.strength) : H.G.wifi[0],
                 title: "Wi-Fi", on: ready && Hermes.wifiOn, ready: ready,
                 sub: !ready ? "Set up in Control Hub" : !Hermes.wifiOn ? "Off" : Hermes.wifiNet ? Hermes.wifiNet.name : "Not connected",
                 list: ready ? "wifi" : "" });
    } else {
      const w = Hermes.wired;
      const up = !!w && w.carrier && w.up;
      out.push({ id: "net", glyph: up ? H.G.wired : H.G.wiredOff, title: "Wired", on: up, ready: true,
                 sub: !w ? "No network adapter" : up ? (w.speed ? H.speedWords(w.speed) : "Connected") : "Unplugged",
                 list: "" });
    }
    // bluetooth — and with BlueZ there but no adapter to switch, the tile
    // switches BlueZ itself: off stops the service (user, 2026-10-21)
    {
      const ready = Hermes.btReady;
      const service = !ready && p.bt.installed && p.bt.hw;
      const names = Hermes.devices.filter((d) => d.connected).map((d) => d.name);
      if (service) out.push({ id: "bt", glyph: p.bt.running ? H.G.bt : H.G.btOff, title: "Bluetooth",
                 on: p.bt.running, ready: true, service: true,
                 sub: Hermes.setupKind === "bluetoothStop" || Hermes.setupKind === "bluetoothStart" ? "Working…"
                   : !p.bt.running ? "Off" : H.btStuck(p) ? "On · adapter not answering" : "On · restart the shell",
                 list: "" });
      else out.push({ id: "bt", glyph: ready && Hermes.btOn ? (names.length > 0 ? H.G.btOn : H.G.bt) : H.G.btOff,
                 title: "Bluetooth", on: ready && Hermes.btOn, ready: ready,
                 sub: !p.bt.hw && !ready ? "No adapter" : !ready && H.btStuck(p) ? "Adapter not answering" : !ready && p.bt.running ? "Restart the shell" : !ready ? "Set up in Control Hub" : !Hermes.btOn ? "Off"
                   : names.length === 1 ? names[0] : names.length > 1 ? names.length + " devices" : "On",
                 list: ready ? "bt" : "" });
    }
    // vpn
    {
      const vs = Hermes.vpns;
      const managed = vs.filter((v) => v.managed);
      out.push({ id: "vpn", glyph: Hermes.vpnActive !== "" ? H.G.vpnOn : H.G.vpn, title: "VPN",
                 on: Hermes.vpnActive !== "", ready: managed.length > 0,
                 sub: Hermes.vpnActive !== "" ? Hermes.vpnActive : vs.length === 0 ? "None set up"
                   : managed.length === 0 ? "Not managed here" : managed.length === 1 ? managed[0].name : managed.length + " connections",
                 list: managed.length > 1 ? "vpn" : "" });
    }
    // night light
    {
      const ready = p.display.hyprsunset;
      out.push({ id: "night", glyph: H.G.night, title: "Night light", on: Hermes.nightActive, ready: ready,
                 sub: !ready ? "Set up in Control Hub" : Hermes.nightSun ? (Hermes.nightActive ? "Until sunrise" : "At sunset")
                   : Hermes.nightActive ? H.kelvinWords(Hermes.kelvin) : "Off",
                 list: "" });
    }
    return out;
  }
  readonly property var sectionOf: ({ net: "network", bt: "bluetooth", vpn: "vpn", night: "display" })

  // return on a tile: its switch, or the window where it is set up
  function pressTile(t) {
    if (!t) return;
    if (!t.ready) { popup.openWindow(popup.sectionOf[t.id]); return; }
    if (t.id === "net") {
      if (popup.wifiTile) Hermes.setWifi(!Hermes.wifiOn);
      else popup.openWindow("network");
    } else if (t.id === "bt") {
      if (t.service) Hermes.setup(Hermes.probe.bt.running ? "bluetoothStop" : "bluetoothStart");
      else Hermes.setBluetooth(!Hermes.btOn);
    } else if (t.id === "vpn") {
      const managed = Hermes.vpns.filter((v) => v.managed);
      const on = managed.find((v) => v.active);
      if (on) Hermes.toggleVpn(on);
      else if (managed.length === 1) Hermes.toggleVpn(managed[0]);
      else popup.openList("vpn");
    } else if (t.id === "night") Hermes.toggleNight();
  }
  function openList(m) {
    if (!m) return;
    popup.mode = m;
    popup.sel = 0;
    popup.syncFocus();
  }

  // ── THE LISTS ──────────────────────────────────────────────────────────
  readonly property var rows: popup.mode === "wifi" ? Hermes.networks
    : popup.mode === "bt" ? Hermes.devices
    : popup.mode === "vpn" ? Hermes.vpns.filter((v) => v.managed) : []
  onRowsChanged: if (popup.sel >= popup.rows.length) popup.sel = Math.max(0, popup.rows.length - 1)

  // ── THE CHOSEN ONE FLASHES, THEN IT ACTS (user, 2026-10-21) ──────────
  // morpheus/RowFlash on the rows, ChosenFlash in the tiles (a grid)
  RowFlash { id: rowFlash }
  function activateRow() {
    const r = popup.rows[popup.sel], mode = popup.mode;
    if (!r) return;
    rowFlash.flashThen(popup.sel, () => { if (popup.mode === mode) popup.activateRowNow(r); }, () => popup.sel);
  }
  function pressTileAt(i) {
    const t = popup.tiles[i];
    if (t) Nav.fireCell(tileRep.itemAt(i), () => popup.pressTile(t));
  }
  function activateRowNow(r) {
    if (popup.mode === "wifi") {
      const how = Hermes.join(r, "");
      if (how === "ask") { popup.pskNet = r; popup.mode = "psk"; popup.syncFocus(); }
    } else if (popup.mode === "bt") Hermes.toggleDevice(r);
    else if (popup.mode === "vpn") Hermes.toggleVpn(r);
  }
  function forgetRow() {
    const r = popup.rows[popup.sel];
    if (!r) return;
    if (popup.mode === "wifi") Hermes.forget(r);
    else if (popup.mode === "bt" && r.paired) Hermes.forgetDevice(r);
  }
  function submitPsk(pw) {
    if (!popup.pskNet || pw === "") return;
    Hermes.join(popup.pskNet, pw);
    popup.mode = "wifi";
    popup.syncFocus();
  }
  // a wrong passphrase: asked again, for the same network
  Connections {
    target: Hermes
    function onAskAgain(name) {
      if (!popup.shown) return;
      const n = Hermes.networks.find((x) => x.name === name);
      if (!n) return;
      popup.pskNet = n;
      popup.mode = "psk";
      pskField.failed = true;
      popup.syncFocus();
    }
  }

  // ── OPEN, CLOSE ────────────────────────────────────────────────────────
  function openPopup() {
    popup.shown = true;
    popup.collapsing = false;
    popup.mode = "main";
    popup.sel = 0;
    popup.tileSel = 0;
    popup.pskNet = null;
    Hermes.hold();
    focusRetry.begin();
    popup.playOpen();
    popup.syncFocus();
  }

  function closePopup() {
    if (!popup.shown || popup.collapsing) return;
    rowFlash.cancel();
    popup.collapsing = true;
    popup.playClose();
    Hermes.release();
  }
  function toggle() { if (popup.shown && !popup.collapsing) popup.closePopup(); else popup.openPopup(); }
  function openWindow(section) {
    popup.closePopup();
    Hermes.open(section || "");
  }
  function back() {
    if (popup.mode === "psk") { popup.mode = "wifi"; popup.syncFocus(); return; }
    if (popup.mode !== "main") {
      const from = { wifi: 0, bt: 1, vpn: 2 }[popup.mode];
      popup.mode = "main";
      if (from !== undefined) popup.tileSel = from;
      popup.syncFocus();
      return;
    }
    popup.closePopup();
  }
  function syncFocus() {
    Qt.callLater(() => { if (popup.shown) bgRoot.forceActiveFocus(); });
  }

  IpcHandler {
    target: "Hermes"
    function toggle(): string { popup.toggle(); return "ok"; }
    function window(section: string): string { Hermes.open(section); return "ok"; }
    function night(): string { Hermes.toggleNight(); return Hermes.nightWanted ? "on" : "off"; }
    // a color filter by id (gray invert protan deutan tritan); the one worn
    // again, or "", turns it off
    function filter(id: string): string {
      Hermes.setFilter(id === Hermes.filter || !H.filterKnown(id) ? "" : id);
      return Hermes.filter === "" ? "off" : Hermes.filter;
    }
    function wifi(): string {
      if (!Hermes.wifiReady) return "no wi-fi";
      Hermes.setWifi(!Hermes.wifiOn);
      return Hermes.wifiOn ? "off" : "on";
    }
    // the brightness keys: `qs ipc call Hermes brightness 5` (or -5)
    function brightness(delta: string): string {
      const d = parseInt(delta, 10);
      if (isNaN(d) || Hermes.screens.length === 0) return "no screen to dim";
      Hermes.stepBrightness(d);
      return "ok";
    }
    function bluetooth(): string {
      if (!Hermes.btReady && Hermes.probe.bt.installed) {
        Hermes.setup(Hermes.probe.bt.running ? "bluetoothStop" : "bluetoothStart");
        return Hermes.probe.bt.running ? "stopping" : "starting";
      }
      if (!Hermes.btReady) return "no bluetooth";
      Hermes.setBluetooth(!Hermes.btOn);
      return Hermes.btOn ? "off" : "on";
    }
  }

  // ── THE HINTS ──────────────────────────────────────────────────────────
  function hints() {
    if (popup.mode === "psk") return [["return", "join"], ["esc", "back"]];
    if (popup.mode === "wifi") return [["↑↓", "network"], ["return", "join, leave"], ["delete", "forget"], ["esc", "back"]];
    if (popup.mode === "bt") return [["↑↓", "device"], ["return", "connect"], ["s", Hermes.btScanning ? "stop" : "search"], ["delete", "forget"], ["esc", "back"]];
    if (popup.mode === "vpn") return [["↑↓", "connection"], ["return", "up, down"], ["esc", "back"]];
    const t = popup.tiles[popup.tileSel];
    return [["arrows", "choose"], ["return", t && !t.ready ? "set up" : "on, off"]]
      .concat(t && t.list ? [["tab", "list"]] : [])
      .concat([["alt o", "control hub"], ["esc", "close"]]);
  }

  // ── SIZE ───────────────────────────────────────────────────────────────
  // as wide as its hints need, 500 at the least (calypso's rule): the
  // strip was cut off at "alt o" in the fixed 500
  HintRow { id: hintMeasure; opacity: 0; rows: popup.hints() }
  readonly property int panelWidth: Math.max(500, Math.ceil(hintMeasure.implicitWidth + 64))
  readonly property int panelTarget: Zenon.layerWidth(popup.panelWidth)
  property real liveWidth: (popup.morphMode && popup.statusbar && popup.statusbar.pillWidth > 0)
    ? popup.statusbar.pillWidth : popup.panelTarget
  Behavior on liveWidth {
    enabled: !popup.morphMode
    NumberAnimation { duration: Zenon.slow; easing.type: Zenon.ease }
  }
  readonly property int sliderCount: Hermes.screens.length + (Hermes.nightActive && !Hermes.nightSun ? 1 : 0)
    + (Hermes.nightSun && Hermes.nightActive ? 1 : 0)
  function calcHeight() {
    if (popup.mode === "main")
      return popup.pad + 2 * popup.tileH + 8 + popup.pad
        + (popup.sliderCount > 0 ? popup.labelH + popup.sliderCount * popup.sliderH + popup.pad : 0) + Zenon.hintBarH;
    if (popup.mode === "psk") return popup.headH + 132 + Zenon.hintBarH;
    const n = popup.rows.length;
    return popup.headH + (n === 0 ? popup.emptyH : Math.min(n, popup.visibleRows) * popup.cellH) + Zenon.hintBarH;
  }

  // ── THE PANEL ──────────────────────────────────────────────────────────
  MouseArea { anchors.fill: parent; z: 0; onClicked: popup.closePopup() }

  LayerPanel {
    id: panel
    host: popup
    ground: bgRoot
    width: Math.round(popup.liveWidth)
    height: popup.calcHeight()

    PanelGround {
      id: bgRoot

      // ── main ──────────────────────────────────────────────────────────
      Item {
        id: mainView
        anchors.fill: parent
        visible: opacity > 0.01
        opacity: popup.mode === "main" ? 1 : 0
        x: popup.mode === "main" ? 0 : -24
        Behavior on opacity { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }
        Behavior on x { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }

        Item {
          id: tileBox
          x: popup.pad
          y: popup.pad
          width: parent.width - 2 * popup.pad
          height: 2 * popup.tileH + 8

          CursorBand { repeater: tileRep; index: popup.tileSel; radius: Zenon.radiusCard }

          Grid {
            id: tileGrid
            anchors.fill: parent
            columns: 2
            spacing: 8
            // BY COUNT, not by the array: the tiles are a new array whenever
            // anything on one changes (the warmth dragged rewrites the night
            // light's line), and a Repeater handed one rebuilt all four — the
            // cursor jumped with every step of the slider (user, 2026-10-20)
            Repeater {
              id: tileRep
              model: popup.tiles.length
              delegate: HermesTile {
                required property int index
                width: (tileGrid.width - tileGrid.spacing) / 2
                height: popup.tileH
                tile: popup.tiles[index] || null
                picked: index === popup.tileSel
                onPressed: { popup.tileSel = index; popup.pressTileAt(index); }
                onListed: { popup.tileSel = index; popup.openList(popup.tiles[index].list); }
              }
            }
          }
        }

        Column {
          id: sliders
          anchors.top: tileBox.bottom
          anchors.topMargin: popup.pad
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.leftMargin: popup.pad - 6
          anchors.rightMargin: popup.pad - 6
          // BY COUNT, not by the array: every brightness change makes a new
          // screens array, and a Repeater handed one rebuilt its sliders —
          // the one being dragged included, which dropped the drag (user,
          // 2026-10-20). Only a screen coming or going rebuilds them now.
          // what the sliders are, as the suite's sections are headed: the
          // window's own name for them (brightness and warmth alike)
          SectionLabel {
            visible: popup.sliderCount > 0
            x: 14
            height: popup.labelH
            verticalAlignment: Text.AlignVCenter
            text: "Display"
          }
          Repeater {
            model: Hermes.screens.length
            delegate: PrefSlider {
              required property int index
              readonly property var modelData: Hermes.screens[index] || ({ label: "", pct: 0 })
              width: sliders.width
              height: popup.sliderH
              labelW: 170
              label: "\u{F00DF}  " + modelData.label
              value: modelData.pct
              from: 1
              to: 100
              wheelStep: 5
              readout: modelData.pct + "%"
              segments: true
              ghost: "888"
              readoutW: 62
              onMoved: (v) => Hermes.setBrightness(modelData, v)
            }
          }
          PrefSlider {
            visible: Hermes.nightActive
            width: sliders.width
            height: popup.sliderH
            labelW: 170
            label: "\u{F0594}  Warmth"
            value: Hermes.kelvin
            from: H.KELVIN_MIN
            to: H.KELVIN_MAX
            wheelStep: 100
            readout: (Hermes.kelvin / 1000).toFixed(1) + "k"
            segments: true
            ghost: "8.8"
            readoutW: 62
            onMoved: (v) => Hermes.setKelvin(v)
          }
        }

        HintBar {
          anchors.bottom: parent.bottom
          width: parent.width
          rows: popup.mode === "main" ? popup.hints() : []
          note: Hermes.said
          noteInk: Hermes.saidBad ? Zenon.red : Zenon.accentKey
        }
      }

      // ── a list ────────────────────────────────────────────────────────
      Item {
        id: listView
        anchors.fill: parent
        visible: opacity > 0.01
        opacity: popup.mode !== "main" ? 1 : 0
        x: popup.mode !== "main" ? 0 : 24
        Behavior on opacity { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }
        Behavior on x { NumberAnimation { duration: Zenon.normal; easing.type: Zenon.ease } }

        // the head: back, what this is, and its switch
        Item {
          id: listHead
          width: parent.width
          height: popup.headH
          Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Zenon.border }
          Text {
            id: backGlyph
            x: 16
            anchors.verticalCenter: parent.verticalCenter
            text: ""
            color: backPress.pressed ? Zenon.ink : Zenon.accentMuted
            font.family: Zenon.glyphFace
            font.pixelSize: Zenon.px(13)
            MouseArea { id: backPress; anchors.fill: parent; anchors.margins: -10; onClicked: popup.back() }
          }
          Text {
            anchors.left: backGlyph.right
            anchors.leftMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            text: popup.mode === "psk" ? (popup.pskNet ? popup.pskNet.name : "")
              : popup.mode === "wifi" ? "Wi-Fi" : popup.mode === "bt" ? "Bluetooth" : "VPN"
            color: Zenon.ink
            font.family: Zenon.face
            font.weight: Zenon.titleWeight
            font.pixelSize: Zenon.px(17)
          }
          Text {
            anchors.right: headSwitch.visible ? headSwitch.left : parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            visible: popup.mode === "bt" && Hermes.btScanning
            text: "Searching…"
            color: Zenon.cyan
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(13)
          }
          Ctl.Check {
            id: headSwitch
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            visible: popup.mode === "wifi" || popup.mode === "bt"
            lit: popup.mode === "wifi" ? Hermes.wifiOn : Hermes.btOn
            onToggled: popup.mode === "wifi" ? Hermes.setWifi(!Hermes.wifiOn) : Hermes.setBluetooth(!Hermes.btOn)
          }
        }

        EmptyState {
          anchors.top: listHead.bottom
          width: parent.width
          height: popup.emptyH
          verticalAlignment: Text.AlignVCenter
          visible: popup.mode !== "psk" && popup.rows.length === 0
          text: popup.mode === "wifi" ? (Hermes.wifiOn ? "Looking for networks…" : "Wi-Fi is off")
            : popup.mode === "bt" ? (!Hermes.btOn ? "Bluetooth is off" : Hermes.btScanning ? "Searching…" : "No devices yet — s searches")
            : "No connections"
        }

        ListView {
          id: rowList
          anchors.top: listHead.bottom
          width: parent.width
          height: Math.min(popup.rows.length, popup.visibleRows) * popup.cellH
          visible: popup.mode !== "psk"
          clip: true
          // by count, as the tiles: the rows are a new array at every change
          // of a signal or a battery, and a view handed one starts again
          model: popup.mode === "psk" ? 0 : popup.rows.length
          currentIndex: popup.sel
          ElasticScroll { view: rowList }
          CursorBand { follows: rowList; index: popup.sel }
          delegate: HermesRow {
            required property int index
            readonly property var modelData: popup.rows[index] || null
            width: rowList.width
            height: popup.cellH
            kind: popup.mode
            row: modelData
            picked: index === popup.sel
            flash: rowFlash
            at: index
            onClicked: { popup.sel = index; popup.activateRow(); }
          }
        }
        Scrollbar {
          flick: rowList
          visible: popup.mode !== "psk"
          x: rowList.width - width
          y: rowList.y
          height: rowList.height
        }

        Column {
          anchors.top: listHead.bottom
          anchors.topMargin: 18
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.leftMargin: 22
          anchors.rightMargin: 22
          spacing: 10
          visible: popup.mode === "psk"
          Cer.PasswordField {
            id: pskField
            width: parent.width
            washRadius: Zenon.windowRadius
            prompt: "password"
            purpose: popup.pskNet ? "joins " + popup.pskNet.name + " · " + H.securityWords(popup.pskNet.security) : ""
            onSubmitted: (pw) => popup.submitPsk(pw)
            onCancelled: popup.back()
          }
        }

        HintBar {
          anchors.bottom: parent.bottom
          width: parent.width
          rows: popup.mode !== "main" ? popup.hints() : []
          note: Hermes.said
          noteInk: Hermes.saidBad ? Zenon.red : Zenon.accentKey
        }
      }

      // ── KEYS ──────────────────────────────────────────────────────────
      Keys.onReleased: (event) => { if (popup.mode === "psk") pskField.keyUp(event); }
      Keys.onPressed: (event) => {
        const alt = event.modifiers & Qt.AltModifier;
        if (popup.mode === "psk") {
          event.accepted = true;
          if (event.key === Qt.Key_Escape && pskField.pw === "") { popup.back(); return; }
          pskField.key(event);
          return;
        }
        event.accepted = true;
        if (event.key === Qt.Key_Escape) { popup.back(); return; }
        if (alt && event.key === Qt.Key_O) {
          const t = popup.tiles[popup.tileSel];
          popup.openWindow(popup.mode === "main" ? (t ? popup.sectionOf[t.id] : "")
            : { wifi: "network", bt: "bluetooth", vpn: "vpn" }[popup.mode]);
          return;
        }
        if (popup.mode === "main") {
          const n = popup.tiles.length;
          if (event.key === Qt.Key_Left) popup.tileSel = (popup.tileSel + n - 1) % n;
          else if (event.key === Qt.Key_Right) popup.tileSel = (popup.tileSel + 1) % n;
          else if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) popup.tileSel = (popup.tileSel + 2) % n;
          else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)
            popup.pressTileAt(popup.tileSel);
          else if (event.key === Qt.Key_Tab) {
            const t = popup.tiles[popup.tileSel];
            if (t && t.list) popup.openList(t.list);
          }
          else event.accepted = false;
          return;
        }
        if (event.key === Qt.Key_Backspace) { popup.back(); return; }
        const len = popup.rows.length;
        if (event.key === Qt.Key_S && popup.mode === "bt") { Hermes.scan(!Hermes.btScanning); return; }
        if (event.key === Qt.Key_Delete) { popup.forgetRow(); return; }
        if (len === 0) return;
        const step = (d) => { popup.sel = Math.max(0, Math.min(len - 1, popup.sel + d)); rowList.positionViewAtIndex(popup.sel, ListView.Contain); };
        if (event.key === Qt.Key_Down) step(1);
        else if (event.key === Qt.Key_Up) step(-1);
        else if (event.key === Qt.Key_PageDown) step(popup.visibleRows);
        else if (event.key === Qt.Key_PageUp) step(-popup.visibleRows);
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) popup.activateRow();
        else event.accepted = false;
      }
    }
  }

  FocusRetry {
    id: focusRetry
    live: popup.shown
    took: bgRoot.activeFocus
    onPlace: popup.syncFocus()
  }
}
