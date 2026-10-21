// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// HERMES' NETWORK PAGE — the wired links, each with its facts, and Wi-Fi:
// its networks where NetworkManager runs it, or what it would take where
// it does not (systemd-networkd shows a wired link perfectly well and has
// nothing to say about Wi-Fi).

import QtQuick
import "../morpheus"
import "../morpheus/controls" as Ctl
import "hermes.js" as H

Column {
  id: page

  property var win: null
  // the window's cursor, on the networks
  property int sel: 0
  readonly property int count: Hermes.wifiReady ? Hermes.networks.length : 0
  readonly property var wireds: Hermes.probe.links.filter((l) => l.kind === "wired")
  // the Wi-Fi link while it has an address: its facts under the networks
  readonly property var wifiLink: Hermes.probe.links.find((l) => l.kind === "wifi" && l.carrier) || null

  spacing: 16

  // ── the wired links ────────────────────────────────────────────────────
  Repeater {
    model: page.wireds.length
    delegate: HermesCard {
      required property int index
      readonly property var modelData: page.wireds[index] || ({})
      readonly property bool up: modelData.carrier && modelData.up
      glyph: up ? H.G.wired : H.G.wiredOff
      glyphInk: up ? Zenon.cyan : Zenon.accentMuted
      title: "Wired"
      note: modelData.name
      HermesFact { label: "Status"; value: up ? "Connected" + (modelData.speed ? " · " + H.speedWords(modelData.speed) : "") : "Unplugged" }
      HermesFact { label: "IPv4"; value: modelData.ipv4.join("\n") }
      HermesFact { label: "IPv6"; value: modelData.ipv6.join("\n") }
      HermesFact { label: "Gateway"; value: modelData.gateway }
      HermesFact { label: "DNS"; value: up ? Hermes.probe.dns.join("\n") : "" }
      HermesFact { label: "Hardware address"; value: modelData.mac }
      HermesFact { label: "Managed by"; value: H.linkStack(Hermes.probe, modelData) }
    }
  }

  // ── wi-fi ──────────────────────────────────────────────────────────────
  // no adapter, and nothing else either: the page says so once
  HermesSetup {
    width: parent.width
    topPadding: 40
    visible: Hermes.probe.known && !Hermes.probe.wifiHw && !Hermes.wifiReady && page.wireds.length === 0
    glyph: H.G.wiredOff
    title: "No network adapter"
    body: "Hermes found no wired or wireless network hardware on this machine."
  }
  EmptyState {
    width: parent.width
    visible: Hermes.probe.known && !Hermes.probe.wifiHw && !Hermes.wifiReady && page.wireds.length > 0
    text: "No Wi-Fi adapter on this machine"
  }
  // an adapter, but nobody to drive it from here
  HermesCard {
    visible: Hermes.probe.wifiHw && !Hermes.nmRunning
    glyph: H.G.wifiOff
    glyphInk: Zenon.accentMuted
    title: "Wi-Fi"
    HermesSetup {
      width: parent.width
      bottomPadding: 22
      glyph: H.G.wifiLock
      title: "Wi-Fi needs NetworkManager"
      body: "This machine's network is run by " + H.stackWords(Hermes.probe.stack)
        + ". NetworkManager takes over from it — the wired link keeps working — and then Wi-Fi and VPNs are managed here."
      action: "Switch to NetworkManager…"
      busy: Hermes.setupKind === "networkmanager"
      onGo: if (page.win) page.win.askSwitch = true
    }
  }
  HermesCard {
    id: wifiCard
    visible: Hermes.wifiReady
    glyph: Hermes.wifiOn ? (Hermes.wifiNet ? H.wifiGlyph(Hermes.wifiNet.strength) : H.G.wifi[0]) : H.G.wifiOff
    glyphInk: Hermes.wifiOn ? Zenon.cyan : Zenon.accentMuted
    title: "Wi-Fi"
    note: !Hermes.wifiOn ? "Off" : Hermes.wifiNet ? Hermes.wifiNet.name : "Not connected"
    trailing: [
      Ctl.Check {
        lit: Hermes.wifiOn
        onToggled: Hermes.setWifi(!Hermes.wifiOn)
      }
    ]

    EmptyState {
      width: parent.width
      height: 60
      verticalAlignment: Text.AlignVCenter
      visible: Hermes.networks.length === 0
      text: Hermes.wifiOn ? "Looking for networks…" : "Wi-Fi is off"
    }
    Item {
      width: parent.width
      height: netCol.height + (Hermes.networks.length > 0 ? 8 : 0)
      visible: Hermes.networks.length > 0
      CursorBand { parent: netCol.parent; repeater: netRep; index: page.sel; shown: page.win ? page.win.listFocus : true }
      Column {
        id: netCol
        width: parent.width
        Repeater {
          id: netRep
          model: Hermes.networks.length
          delegate: HermesRow {
            readonly property var modelData: Hermes.networks[index] || ({})
            required property int index
            width: netCol.width
            height: 42
            kind: "wifi"
            row: modelData
            flash: page.win ? page.win.rowFlash : null
            at: index
            picked: index === page.sel
            onClicked: { page.sel = index; if (page.win) page.win.activate(); }
          }
        }
      }
    }
    Rectangle { width: parent.width; height: 1; color: Zenon.border; visible: !!page.wifiLink }
    Item { width: 1; height: 6; visible: !!page.wifiLink }
    HermesFact { label: "IPv4"; value: page.wifiLink ? page.wifiLink.ipv4.join("\n") : "" }
    HermesFact { label: "Gateway"; value: page.wifiLink ? page.wifiLink.gateway : "" }
    HermesFact { label: "Hardware address"; value: page.wifiLink ? page.wifiLink.mac : "" }
    HermesFact { label: "Managed by"; value: page.wifiLink ? H.linkStack(Hermes.probe, page.wifiLink) : "" }
  }
}
