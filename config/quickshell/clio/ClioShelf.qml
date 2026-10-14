// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ONE ROW OF CLIO'S SIDEBAR — the suite's ShelfRow, and what clio's rows
// add to it: a right click (menu(x, y) in the window's stage), the HeldRing
// while that menu is up, a fold for a container with containers in it, and being
// a place a dragged note can land (`drop`, lit while one is over it).

import QtQuick
import "../morpheus"
import "../terminus"

ShelfRow {
  id: row
  property var host: null
  property bool held: false
  property var drop: null
  property bool kids: false
  property bool shut: false
  property bool muted: false
  signal menu(real x, real y)
  signal toggled()

  width: parent ? parent.width : 200
  radius: 0
  indent: 18
  countIndent: 18
  fill: row.host && row.host.win ? row.host.win.hiFill : Zenon.alpha(Zenon.cyan, 0.12)
  opacity: row.muted ? 0.75 : 1
  readonly property bool hot: !!row.drop && !!row.host && row.host.dropHot === JSON.stringify(row.drop)
  Component.onCompleted: if (row.drop && row.host) row.host.register(row)
  Component.onDestruction: if (row.host) row.host.unregister(row)

  // ── SOMETHING CARRIED OVER IT: terminus' sidebar swell ──
  // the row grows a little and its outline breathes for as long as the
  // drop is on offer; on the Trash in yellow, a trashing (terminus/SideRow)
  readonly property color dropInk: !!row.drop && row.drop.shelf === "trash" ? Zenon.yellow : Zenon.cyan
  property real swell: row.hot ? 1 : 0
  Behavior on swell { NumberAnimation { duration: Zenon.fast; easing.type: Easing.OutCubic } }
  scale: 1 + 0.03 * row.swell
  property real breath: 0.35
  SequentialAnimation on breath {
    running: row.hot
    loops: Animation.Infinite
    NumberAnimation { to: 1; duration: 520; easing.type: Easing.InOutSine }
    NumberAnimation { to: 0.35; duration: 520; easing.type: Easing.InOutSine }
  }
  Rectangle {
    anchors.fill: parent
    anchors.leftMargin: 4
    anchors.rightMargin: 4
    radius: Zenon.windowRadius
    visible: row.swell > 0.01
    opacity: row.swell
    color: Zenon.alpha(row.dropInk, 0.14)
    border.width: 1
    border.color: Zenon.alpha(row.dropInk, row.breath)
  }
  // a container's own containers: shown or folded
  Text {
    visible: row.kids
    x: row.indent - 14
    anchors.verticalCenter: parent.verticalCenter
    text: row.shut ? "" : ""
    color: Zenon.muted
    font.family: Zenon.glyphFace
    font.pixelSize: Zenon.px(9)
    MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: row.toggled() }
  }
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.RightButton
    onClicked: (m) => {
      if (!row.host || !row.host.win) return;
      const p = mapToItem(row.host.win.stageItem, m.x, m.y);
      row.menu(p.x, p.y);
    }
  }
  HeldRing { anchors.fill: parent; anchors.margins: 2; radius: Zenon.windowRadius; on: row.held && row.host.win.menuRef.isOpen }
}
