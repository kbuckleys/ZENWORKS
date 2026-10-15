// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/

import QtQuick
import Quickshell
import Quickshell.Io
import "helpers.js" as Helpers
import "../oracle"
import "../ceres"
import "."
// qualified, for HeldRing alone
import "../terminus" as Term

Collapsible {
  id: root
  // Turned off in oracle this eases to zero width exactly as it does when
  // there is nothing pending — the pill shrink-wraps around what is left
  // rather than the module disappearing out of a layout mid-frame.
  // A restart owed is worth the slot on its own: it is the one thing on this
  // module that gets worse the longer it is ignored.
  active: Oracle.showUpdates && (root.hasUpdates || root.owed)
  openWidth: row.implicitWidth

  // Everything below is read off Ceres, which owns the checking, the
  // announcing and the memory of both. This module only draws the count.
  readonly property bool hasUpdates: Ceres.total > 0
  readonly property string countText: String(Ceres.total)
  // A reboot (kernel) or a service restart (user services on replaced code) is owed,
  // and the transaction that caused it has finished: the icon says so.
  readonly property bool owed: !Ceres.txBusy
    && (Ceres.restartNeeded || Ceres.staleServices.length > 0)
  property bool hovered: false
  signal activated()

  Row {
    id: row
    anchors.centerIn: parent
    leftPadding: Zenon.padModule
    rightPadding: Zenon.padModule

    Item {
      id: iconBox
      width: (root.hovered && root.hasUpdates ? countBox.implicitWidth : iconGlyph.implicitWidth) + Zenon.padModule * 2
      Behavior on width { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
      height: Zenon.slot
      anchors.verticalCenter: parent.verticalCenter

      // outlined while its menu is open (terminus/HeldRing.qml)
      Term.HeldRing {
        anchors.fill: parent
        anchors.topMargin: 3
        anchors.bottomMargin: 3
        on: menu.open
      }

      BarText {
        id: iconGlyph
        anchors.centerIn: parent
        text: root.owed ? "󰚰" : "󰏗"
        color: Zenon.yellow
        numeric: true
        font.pixelSize: Zenon.clockSize
        // stays up when there is no count to swap in — with only a restart
        // pending, hovering used to empty the chip
        opacity: !(root.hovered && root.hasUpdates) ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
      }

      Item {
        id: countBox
        anchors.centerIn: parent
        implicitWidth: Math.max(countGhost.implicitWidth, countLabel.implicitWidth)
        implicitHeight: Zenon.slot

        BarText {
          id: countGhost
          anchors.centerIn: parent
          text: "8".repeat(Math.max(1, String(root.countText).length))
          numeric: true
          color: Zenon.trough(Zenon.yellow)
          opacity: root.hovered && root.hasUpdates ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
        }

        BarText {
          id: countLabel
          anchors.centerIn: parent
          text: root.countText
          numeric: true
          color: Zenon.yellow
          opacity: root.hovered && root.hasUpdates ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
        }
      }
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    onEntered: root.hovered = true
    onExited: root.hovered = false
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    // Left is ceres' panel; right is its menu (the bell's, the tray's card).
    onClicked: (m) => {
      if (m.button === Qt.RightButton) menu.show();
      else root.activated();
    }
  }

  // ── THE UPDATES' MENU (user, 2026-10-14) ────────────────────────────
  // What ceres already does, from where the hand is: the panel, the whole
  // window on either tab, and a check now rather than at the next tick.
  TrayMenu {
    id: menu
    anchorItem: root
    items: [
      { text: "Show updates", icon: "󰏗" },
      { text: "Open Ceres", icon: "\uDB82\uDCC7" },
      { isSeparator: true },
      { text: Ceres.checking ? "Checking…" : "Check now", icon: "󰑓", enabled: !Ceres.checking && !Ceres.txBusy },
      { text: "Packages", icon: "\uF487" }
    ]
    onPicked: (i) => {
      if (i === 0) root.activated();
      else if (i === 1) Ceres.openWindow("updates");
      else if (i === 3) Ceres.check();
      else if (i === 4) Ceres.openWindow("packages");
    }
  }

  Tooltip {
    anchorItem: root
    cursorArea: mouse
    text: Ceres.describe(5)
    styled: true
    show: mouse.containsMouse && root.active && !menu.open
  }
}
