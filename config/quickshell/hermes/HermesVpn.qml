// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// HERMES' VPN PAGE — NetworkManager's VPN and WireGuard connections, up or
// down, and Import… for a WireGuard .conf or an OpenVPN .ovpn. Without
// NetworkManager, the WireGuard links that are up, to look at, and what it
// would take to manage them here.

import QtQuick
import "../morpheus"
import "hermes.js" as H

Column {
  id: page

  property var win: null
  property int sel: 0
  readonly property var rows: Hermes.vpns
  readonly property int count: page.rows.length

  spacing: 16

  HermesCard {
    glyph: Hermes.vpnActive !== "" ? H.G.vpnOn : H.G.vpn
    glyphInk: Hermes.vpnActive !== "" ? Zenon.green : Zenon.accentMuted
    title: "Connections"
    note: Hermes.vpnActive !== "" ? "Connected to " + Hermes.vpnActive : ""
    EmptyState {
      width: parent.width
      height: 64
      verticalAlignment: Text.AlignVCenter
      visible: page.rows.length === 0
      text: Hermes.nmRunning ? "No VPN connections yet — Import… adds a WireGuard or OpenVPN file"
        : "No WireGuard links are up"
    }
    Item {
      width: parent.width
      height: vpnCol.height + (page.rows.length > 0 ? 8 : 0)
      visible: page.rows.length > 0
      CursorBand { parent: vpnCol.parent; repeater: vpnRep; index: page.sel; shown: page.win ? page.win.listFocus : true }
      Column {
        id: vpnCol
        width: parent.width
        Repeater {
          id: vpnRep
          model: page.rows.length
          delegate: HermesRow {
            readonly property var modelData: page.rows[index] || ({})
            required property int index
            width: vpnCol.width
            height: 42
            kind: "vpn"
            row: modelData
            flash: page.win ? page.win.rowFlash : null
            at: index
            picked: index === page.sel
            onClicked: { page.sel = index; if (page.win) page.win.activate(); }
          }
        }
      }
    }
  }

  HermesCard {
    visible: Hermes.probe.known && !Hermes.nmRunning
    glyph: H.G.info
    glyphInk: Zenon.accentMuted
    title: "Managing VPNs"
    HermesSetup {
      width: parent.width
      bottomPadding: 22
      glyph: H.G.vpn
      ink: Zenon.green
      title: "VPNs are managed through NetworkManager"
      body: "This machine's network is run by " + H.stackWords(Hermes.probe.stack)
        + ". With NetworkManager in its place, WireGuard and OpenVPN connections are imported, started and stopped here."
      action: "Switch to NetworkManager…"
      busy: Hermes.setupKind === "networkmanager"
      onGo: if (page.win) page.win.askSwitch = true
    }
  }
}
