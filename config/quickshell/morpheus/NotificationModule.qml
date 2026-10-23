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
  // with nothing in the history, only when asked to stay (Oracle's
  // notifBellAlways, on by default; also in the menu below)
  active: Oracle.showNotifications
    && (Oracle.notifBellAlways || root.total > 0 || root.unread > 0 || root.silent)
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
  // Do not disturb, the switch itself (silent above is "quiet for any
  // reason" — the switch, a timer running, quiet hours — which is what the
  // struck bell says); why it is quiet, for the tooltip; focus's two
  // switches, as ticks (2026-10-21)
  property bool dnd: false
  property string quietWhy: ""
  property bool focusTimers: false
  property bool quietHours: false

  signal activated()
  signal cleared()
  signal silenceToggled()
  signal trackMusicToggled()
  signal focusTimersToggled()
  signal quietHoursToggled()

  Row {
    id: row
    anchors.centerIn: parent
    leftPadding: Zenon.padModule
    rightPadding: Zenon.padModule
    spacing: 0

    Item {
      id: iconBox
      width: iconGlyph.implicitWidth + Zenon.padModule * 2
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
        // the theme's accent either way, as Control Hub's icon wears it
        // (user, 2026-10-23): something unread is said by the badge
        // (U+F0D59), not a second colour; silenced, it greys like a switch off
        text: root.silent ? "󰂛" : root.unread > 0 ? "\u{F0D59}" : "󰂜"
        color: root.silent ? Zenon.muted : Zenon.cyan
        numeric: true
        font.pixelSize: Zenon.clockSize
      }
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
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
      { text: "Do not disturb", icon: "󰂛", mark: root.dnd },
      { text: "Quiet while a timer runs", icon: "\u{F051B}", mark: root.focusTimers },
      { text: "Quiet hours", icon: "\u{F0594}", mark: root.quietHours },
      { text: "Keep track changes", icon: "\uF001", mark: root.trackMusic },
      { text: "Show with no history", icon: "󰂜", mark: Oracle.notifBellAlways },
      { isSeparator: true },
      { text: "Clear all", icon: "󰎟", enabled: root.total > 0 || root.unread > 0 }
    ]
    onPicked: (i) => {
      if (i === 0) root.activated();
      else if (i === 2) root.silenceToggled();
      else if (i === 3) root.focusTimersToggled();
      else if (i === 4) root.quietHoursToggled();
      else if (i === 5) root.trackMusicToggled();
      else if (i === 6) Oracle.set("notifBellAlways", !Oracle.notifBellAlways);
      else if (i === 8) root.cleared();
    }
  }

  Tooltip {
    anchorItem: root
    cursorArea: mouse
    styled: true
    text: root.silent
      ? "<b>" + (root.quietWhy !== "" ? root.quietWhy : "Do not disturb") + "</b>" + (root.unread > 0 && root.tooltipText !== "" ? "\n" + root.tooltipText : "")
      : root.tooltipText
    show: mouse.containsMouse && !menu.open && (root.silent || (root.unread > 0 && root.tooltipText !== ""))
  }
}
