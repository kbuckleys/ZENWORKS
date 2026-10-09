// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// The bell. Deliberately knows nothing about howler: shell.qml feeds it the
// numbers and handles the click, exactly like every other module here, so the
// bar and the notification daemon stay separable.

import QtQuick
import "../oracle"
import "."
// qualified, for HeldRing alone
import "../terminus" as Term

Collapsible {
  id: root
  // Silenced, it stays even with nothing unread: the struck bell is the only
  // place do not disturb is visible, and the right click that ends it.
  active: Oracle.showNotifications && (root.unread > 0 || root.silent)
  openWidth: row.implicitWidth

  // arrived since the history panel was last opened
  property int unread: 0
  // everything the panel would show
  property int total: 0
  property string tooltipText: ""
  // do not disturb and music tracking, as howler has them — shown as ticks in
  // the right-click menu, which asks for the other state through the signals
  property bool silent: false
  property bool trackMusic: false
  property bool hovered: false

  signal activated()
  signal cleared()
  signal silenceToggled()
  signal trackMusicToggled()

  Row {
    id: row
    anchors.centerIn: parent
    leftPadding: Zenon.padModule
    rightPadding: Zenon.padModule
    spacing: 0

    Item {
      id: iconBox
      width: (root.hovered && root.unread > 0 ? countBox.implicitWidth : iconGlyph.implicitWidth) + Zenon.padModule * 2
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
        text: root.silent ? "󰂛" : "󰂜"
        color: root.silent ? Zenon.muted : Zenon.yellow
        numeric: true
        font.pixelSize: Zenon.clockSize
        // a silenced bell with nothing to count keeps its glyph under the pointer
        opacity: !(root.hovered && root.unread > 0) ? 1 : 0
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
          text: "8".repeat(Math.max(1, String(root.unread).length))
          numeric: true
          color: Zenon.trough(Zenon.yellow)
          opacity: root.hovered && root.unread > 0 ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
        }

        BarText {
          id: countLabel
          anchors.centerIn: parent
          text: String(root.unread)
          numeric: true
          color: Zenon.yellow
          opacity: root.hovered && root.unread > 0 ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
        }
      }
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    onEntered: root.hovered = true
    onExited: root.hovered = false
    onClicked: (e) => {
      if (e.button === Qt.MiddleButton) root.cleared();
      else if (e.button === Qt.RightButton) menu.show();
      else root.activated();
    }
  }

  // ── THE BELL'S MENU ─────────────────────────────────────────────────
  // The tray's own card, hung off the pill the way a tray app's menu is.
  // Everything here is also somewhere else — the panel, oracle, the middle
  // click — this is where your hand already is.
  TrayMenu {
    id: menu
    anchorItem: root
    items: [
      { text: "Open history", icon: "󰂚" },
      { isSeparator: true },
      { text: "Do not disturb", icon: "󰂛", mark: root.silent },
      { text: "Keep track changes", icon: "\uF001", mark: root.trackMusic },
      { isSeparator: true },
      { text: "Clear all", icon: "󰎟", enabled: root.total > 0 || root.unread > 0 }
    ]
    onPicked: (i) => {
      if (i === 0) root.activated();
      else if (i === 2) root.silenceToggled();
      else if (i === 3) root.trackMusicToggled();
      else if (i === 5) root.cleared();
    }
  }

  Tooltip {
    anchorItem: root
    cursorArea: mouse
    styled: true
    text: root.silent
      ? "<b>Do not disturb</b>" + (root.unread > 0 && root.tooltipText !== "" ? "\n" + root.tooltipText : "")
      : root.tooltipText
    show: mouse.containsMouse && !menu.open && (root.silent || (root.unread > 0 && root.tooltipText !== ""))
  }
}
