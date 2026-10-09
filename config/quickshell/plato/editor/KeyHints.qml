// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// What can come next, after a command half typed and a pause: g, z, [ ],
// ctrl w, a register, an operator waiting for its motion (hints.js has the
// lists). The leader menu's idea for nvim's own keys, and the leader menu's
// card: a PlatoSheet rising from the status bar, the keys in terminus' rows
// in white, the title in the sand footer. But NOT MODAL — no scrim, no
// focus, no key taken. Keys go on to nvim as ever; the card is gone the
// moment the command is.

import QtQuick
import "../../morpheus"
import "hints.js" as Hints

PlatoSheet {
  id: hints

  required property var ed
  property bool active: true
  property real delay: 450

  modal: false
  fromBottom: true

  // what to show, once the keys have been waiting long enough
  property var shownFor: null
  readonly property var want: hints.active
    ? Hints.forKeys(hints.ed.pending, hints.ed.status ? hints.ed.status.op === true : false) : null
  onWantChanged: {
    if (!hints.want) { wait.stop(); hints.shownFor = null; }
    else if (hints.shownFor) hints.shownFor = hints.want;
    else wait.restart();
  }
  Timer {
    id: wait
    interval: hints.delay
    onTriggered: hints.shownFor = hints.want
  }
  shown: hints.shownFor !== null

  // the last list stays drawn while the card goes back down
  property var held: []
  onShownForChanged: if (hints.shownFor) hints.held = hints.shownFor.keys
  readonly property var list: hints.held
  // as many as the list wants (8 to a column, up to 3), as the window allows
  readonly property int columns: hints.fitColumns(Math.min(3, Math.max(1, Math.ceil(hints.list.length / 8))), hints.colW)
  readonly property int rowsN: Math.max(1, Math.ceil(hints.list.length / hints.columns))
  readonly property real colW: 300

  cardW: hints.columns * hints.colW + 20
  cardH: 12 + hints.rowsN * hints.rowH
  foot: false

  Grid {
    x: 10
    y: 6
    columns: hints.columns
    flow: Grid.TopToBottom
    rows: hints.rowsN
    Repeater {
      model: hints.list
      Item {
        id: entry
        required property var modelData
        width: hints.colW
        height: hints.rowH
        KeyCap {
          id: cap
          x: 8
          anchors.verticalCenter: parent.verticalCenter
          label: entry.modelData[0]
          fontSize: 12
        }
        Text {
          anchors.left: cap.right
          anchors.leftMargin: 12
          anchors.right: parent.right
          anchors.rightMargin: 8
          anchors.verticalCenter: parent.verticalCenter
          elide: Text.ElideRight
          textFormat: Text.PlainText
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: 16
          color: Zenon.white
          text: entry.modelData[1]
        }
      }
    }
  }
}
