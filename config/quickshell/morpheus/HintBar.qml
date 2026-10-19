// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE HINT STRIP — the bar at a window's or a panel's foot that the keys
// (HintRow) stand on: its height, its frosted ground, its hairline, and
// where the keys sit. It was ceres' foot; every other window and panel drew
// its own, at 22, 26, 28, 32, 34 or 40 px on one of two grounds (user,
// 2026-10-19: "make all hint bars follow the same properties as ceres'
// hint bar, bar height included. consolidate"). One file now, ceres
// included.
//
//     HintBar { rows: popup.hints() }
//
//     HintBar {                          // buttons at the right end
//       rows: win.hintRows
//       DialogButton { label: "Install"; … }
//     }
//
//     HintBar {                          // a word before the keys
//       rows: …
//       leading: Text { text: query; … }
//     }
//
// The keys (with whatever stands before them) are centered, and start at
// the left the moment buttons stand at the right end, so keys and buttons
// read as the two ends of one strip rather than a row shifting off-center.
// What does not fit is dropped from the END of the list (HintRow.maxWidth),
// which is why every holder lists the keys you need most first.
//
// `note`, when set, takes the keys' place for a moment: "copied", "saved".

import QtQuick
import "."

Item {
  id: bar
  property var rows: []
  // a word for a moment, over the keys (they fade out under it)
  property string note: ""
  property color noteInk: Zenon.accentKey
  // the hairline along the top edge, where the strip meets what it is under
  property bool rule: true
  property color ground: Zenon.hintFrostBg
  // the buttons at the right end: a holder's children land here
  default property alias trailing: trail.data
  // something before the keys at the left (terminus' sheets put the query)
  property alias leading: lead.data
  // over the whole strip, the keys' place taken (ideo's format chooser)
  property alias overlay: over.data
  readonly property alias hintRow: hints
  // how wide the keys want to be, all of them shown (a panel sizing itself
  // to its strip reads this)
  readonly property real needW: hints.implicitWidth + 32
    + (lead.width > 0 ? lead.width + 16 : 0) + (trail.width > 0 ? trail.width + 36 : 0)

  implicitHeight: Zenon.hintBarH
  height: implicitHeight

  // see-through: lists rise out of it (the views' ScrollEdges)
  Rectangle { anchors.fill: parent; color: bar.ground }
  Rectangle {
    visible: bar.rule
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    height: 1
    color: Zenon.border
  }

  // CENTERED AS ONE GROUP — what stands before the keys and the keys —
  // unless something stands at the right end, when they start at the left
  // so the two ends read as one strip (user, 2026-10-19: center the hints
  // in terminus' sheets and plato's settings, which put a word first)
  readonly property bool flanked: trail.width > 0
  readonly property real groupW: (lead.width > 0 ? lead.width + 16 : 0) + hints.width
  Row {
    id: lead
    x: bar.flanked ? 16 : Math.max(16, Math.round((bar.width - bar.groupW) / 2))
    anchors.verticalCenter: parent.verticalCenter
    spacing: 8
  }

  HintRow {
    id: hints
    rows: bar.rows
    anchors.verticalCenter: parent.verticalCenter
    x: lead.width > 0 ? lead.x + lead.width + 16
      : (bar.flanked ? 16 : Math.round((bar.width - width) / 2))
    maxWidth: bar.width - 32
      - (lead.width > 0 ? lead.width + 16 : 0)
      - (trail.width > 0 ? trail.width + 12 + 24 : 0)
    opacity: bar.note !== "" ? 0 : 1
    Behavior on opacity { NumberAnimation { duration: Zenon.fast } }
  }

  Text {
    anchors.centerIn: parent
    visible: opacity > 0.01
    opacity: bar.note !== "" ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Zenon.fast } }
    text: bar.note
    color: bar.noteInk
    font.family: Zenon.face
    font.weight: 600
    font.pixelSize: Zenon.px(15)
  }

  Row {
    id: trail
    anchors.right: parent.right
    anchors.rightMargin: 12
    anchors.verticalCenter: parent.verticalCenter
    spacing: 8
  }

  Item {
    id: over
    anchors.fill: parent
  }
}
