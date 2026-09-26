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

Collapsible {
  id: root
  // Turned off in oracle this eases to zero width exactly as it does when
  // there is nothing pending — the pill shrink-wraps around what is left
  // rather than the module disappearing out of a layout mid-frame.
  // A restart owed is worth the slot on its own: it is the one thing on this
  // module that gets worse the longer it is ignored.
  active: Oracle.showUpdates && (root.hasUpdates || Ceres.restartNeeded)
  openWidth: row.implicitWidth

  // Everything below is read off Ceres, which owns the checking, the
  // announcing and the memory of both. This module only draws the count.
  readonly property bool hasUpdates: Ceres.total > 0
  readonly property string countText: String(Ceres.total)
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

      BarText {
        id: iconGlyph
        anchors.centerIn: parent
        text: "󰏗"
        color: Zenon.yellow
        numeric: true
        font.pixelSize: Zenon.clockSize
        opacity: !root.hovered ? 1 : 0
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
    // Left is ceres' panel; right is the whole of ceres, on its Updates tab.
    onClicked: (m) => {
      if (m.button === Qt.RightButton)
        Quickshell.execDetached(["qs", "ipc", "call", "Ceres", "window", "updates"]);
      else root.activated();
    }
  }

  Tooltip {
    anchorItem: root
    cursorArea: mouse
    text: Ceres.describe(5)
    styled: true
    show: mouse.containsMouse && root.active
  }
}
