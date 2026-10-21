// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// The connection icon: hermes' own glyph (U+F1542), coloured by the
// connection — what it is connected to is in the tooltip. A click opens
// hermes' quick panel; the right click is its menu, which can also take
// the icon off the bar (Oracle's "Connections" switch, the same setting).
//
// Like the bell, it knows nothing about hermes: shell.qml hands it the
// glyphs, the tooltip and the switches' states, and hears the clicks back.

import QtQuick
import "../oracle"
import "."
// qualified, for HeldRing alone
import "../terminus" as Term

Collapsible {
  id: root

  active: Oracle.showHermes && root.glyphs.length > 0
  openWidth: row.implicitWidth

  // [{ glyph, role: "ok" | "off" | "down" }]
  property var glyphs: []
  property string tooltipText: ""
  // the menu's ticks, and whether each switch is there to flip at all
  property bool wifiOn: false
  property bool wifiReady: false
  property bool btOn: false
  property bool btReady: false
  property bool nightOn: false
  property bool nightReady: false

  signal activated()
  signal windowWanted()
  signal wifiToggled()
  signal btToggled()
  signal nightToggled()

  readonly property alias hovered: mouse.containsMouse

  Row {
    id: row
    anchors.centerIn: parent
    leftPadding: Zenon.padModule
    rightPadding: Zenon.padModule
    spacing: 0

    Item {
      id: iconBox
      width: glyphRow.implicitWidth + Zenon.padModule * 2
      height: Zenon.slot
      anchors.verticalCenter: parent.verticalCenter

      // outlined while its menu is open (terminus/HeldRing.qml)
      Term.HeldRing {
        anchors.fill: parent
        anchors.topMargin: 3
        anchors.bottomMargin: 3
        on: menu.open
      }

      Row {
        id: glyphRow
        anchors.centerIn: parent
        spacing: 6
        Repeater {
          model: root.glyphs
          delegate: BarText {
            required property var modelData
            text: modelData.glyph
            // connected in the clock's ink; off quiet; a link that is down
            // in the yellow that says something is wrong
            color: modelData.role === "ok" ? Zenon.cyan : modelData.role === "down" ? Zenon.yellow : Zenon.muted
            numeric: true
            font.pixelSize: Zenon.clockSize
          }
        }
      }
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    onClicked: (e) => {
      if (e.button === Qt.RightButton) menu.show();
      else if (e.button === Qt.MiddleButton) root.windowWanted();
      else root.activated();
    }
  }

  // ── THE ICON'S MENU ─────────────────────────────────────────────────
  // The switches your hand is already near, the window, and the icon's own
  // place on the bar — off here is off in Oracle, and Oracle brings it back.
  TrayMenu {
    id: menu
    anchorItem: root
    items: [
      { text: "Open Control Hub", icon: "\u{F1542}" },
      { isSeparator: true },
      { text: "Wi-Fi", icon: "\u{F05A9}", mark: root.wifiOn, enabled: root.wifiReady },
      { text: "Bluetooth", icon: "\u{F00AF}", mark: root.btOn, enabled: root.btReady },
      { text: "Night light", icon: "\u{F0594}", mark: root.nightOn, enabled: root.nightReady },
      { isSeparator: true },
      { text: "Hide from the bar", icon: "\u{F0209}" }
    ]
    onPicked: (i) => {
      if (i === 0) root.windowWanted();
      else if (i === 2) root.wifiToggled();
      else if (i === 3) root.btToggled();
      else if (i === 4) root.nightToggled();
      else if (i === 6) Oracle.set("showHermes", false);
    }
  }

  Tooltip {
    anchorItem: root
    cursorArea: mouse
    styled: true
    // centered (user, 2026-10-20): the link over its address, one block
    align: Text.AlignHCenter
    text: root.tooltipText
    show: mouse.containsMouse && !menu.open && root.tooltipText !== ""
  }
}
