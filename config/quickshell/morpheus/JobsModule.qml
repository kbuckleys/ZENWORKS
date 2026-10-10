// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// The jobs, on the bar. Only while there are some: a copy you started and
// walked away from — the window closed, the shell still copying — is the
// case this is for, and an idle download arrow would be a permanent
// invitation to check on nothing. The glyph and the overall percentage here;
// the list itself one hover away in JobsPanel, which is the same card
// terminus' drawer shows.

import QtQuick
import "."

Collapsible {
  id: root

  active: Jobs.model.count > 0
  openWidth: row.implicitWidth

  property bool hovered: mouse.containsMouse
  signal activated()

  // the drawer's own rule: red for bad news, green once everything that ran
  // has landed, cyan while anything is still going
  readonly property color tone: Jobs.faults > 0 ? Zenon.red
    : (Jobs.live === 0 && Jobs.done > 0 ? Zenon.green : Zenon.cyan)

  // No glyph: the number is the module. It is drawn the way the clock is —
  // live digits over the same digits unlit — so the two read as one family,
  // and the ghost is always three wide, so 7% and 100% take the same room
  // and the meters beside it never shuffle. "!" is DSEG's digit-wide blank.
  Row {
    id: row
    anchors.centerIn: parent
    leftPadding: Zenon.padModule
    rightPadding: Zenon.padModule
    spacing: 2

    Item {
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(ghost.implicitWidth, digits.implicitWidth)
      height: Zenon.slot

      BarText {
        id: ghost
        anchors.centerIn: parent
        text: "888"
        numeric: true
        color: Zenon.trough(root.tone)
      }
      BarText {
        id: digits
        anchors.centerIn: parent
        text: ("!!" + Jobs.pct).slice(-3)
        numeric: true
        color: root.tone
      }
    }
    BarText {
      anchors.verticalCenter: parent.verticalCenter
      text: "%"
      color: root.tone
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    onClicked: root.activated()
  }
}
