// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A row in one of Hermes' lists — a Wi-Fi network, a Bluetooth device, a
// VPN connection — for the quick panel and the window alike.
//
//   kind  "wifi" | "bt" | "vpn"
//   row   Hermes.networks[i] | Hermes.devices[i] | Hermes.vpns[i]
//
// The cursor is the list's CursorBand; the row only says what it is.

import QtQuick
import "../morpheus"
import "hermes.js" as H

Item {
  id: r

  property string kind: "wifi"
  property var row: null
  property bool picked: false
  signal clicked()

  readonly property bool live: !!r.row && (r.kind === "vpn" ? r.row.active : r.row.connected)
  readonly property string glyph: !r.row ? ""
    : r.kind === "wifi" ? H.wifiGlyph(r.row.strength)
    : r.kind === "bt" ? H.btGlyph(r.row.icon)
    : r.row.active ? H.G.vpnOn : H.G.vpn
  readonly property string stateWords: {
    const x = r.row;
    if (!x) return "";
    if (r.kind === "wifi") return x.busy ? "Joining…" : x.connected ? "Connected" : x.known ? "Saved" : H.securityWords(x.security);
    if (r.kind === "bt") {
      const bat = x.battery >= 0 ? H.batteryWords(x.battery) : "";
      return x.busy ? "…" : x.connected ? "Connected" + (bat ? " · " + bat : "") : x.paired ? "Paired" : "";
    }
    return x.active ? "Connected" : x.type === "wireguard" ? "WireGuard" : "VPN";
  }

  Text {
    id: icon
    x: 18
    anchors.verticalCenter: parent.verticalCenter
    width: 24
    text: r.glyph
    color: r.live ? Zenon.cyan : Zenon.accentMuted
    font.family: Zenon.glyphFace
    font.pixelSize: Zenon.px(17)
  }
  Text {
    id: name
    anchors.left: icon.right
    anchors.leftMargin: 10
    anchors.verticalCenter: parent.verticalCenter
    // up to the state words, eliding there (a width from its own
    // implicitWidth looped the binding)
    anchors.right: stateText.left
    anchors.rightMargin: 16
    elide: Text.ElideRight
    text: r.row ? r.row.name : ""
    color: r.live ? Zenon.cyan : r.picked ? Zenon.ink : Zenon.white
    font.family: Zenon.face
    font.weight: r.live ? Zenon.titleWeight : 600
    font.pixelSize: Zenon.px(15)
  }
  Text {
    id: lockGlyph
    anchors.right: parent.right
    anchors.rightMargin: 18
    anchors.verticalCenter: parent.verticalCenter
    // a fixed cell: sized from its own implicitWidth, it looped
    width: visible ? 14 : 0
    horizontalAlignment: Text.AlignHCenter
    visible: r.kind === "wifi" && !!r.row && !H.securityOpen(r.row.security)
    text: H.G.lock
    color: Zenon.accentMuted
    font.family: Zenon.glyphFace
    font.pixelSize: Zenon.px(12)
  }
  Text {
    id: stateText
    anchors.right: lockGlyph.left
    anchors.rightMargin: lockGlyph.visible ? 8 : 0
    anchors.verticalCenter: parent.verticalCenter
    text: r.stateWords
    color: r.live ? Zenon.cyan : Zenon.accentMuted
    font.family: Zenon.face
    font.weight: Zenon.weight
    font.pixelSize: Zenon.px(13)
  }
  MouseArea { anchors.fill: parent; onClicked: r.clicked() }
}
