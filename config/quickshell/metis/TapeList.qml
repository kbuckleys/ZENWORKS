// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/

import QtQuick
import "../morpheus"
import "metis.js" as Metis

// THE TAPE (ctrl+h). The kept answers as a till roll: oldest at the top,
// the newest at the bottom where the roll comes out, the question muted on
// the left and what it came to on the right. Space marks a row and the
// marked ones are added up underneath — by qalc, so 5 km and 300 m add.
// The names you have set (rent = 1200) head it, so they are not forgotten.
Item {
  id: tape

  property var rows: []          // oldest first
  property int idx: -1
  property var marks: ({})       // index → true
  property string sum: ""        // the marked rows added up, or "" / "…"
  property bool sumBad: false
  property var names: []         // [{name, shown}]
  signal picked(int index)
  signal toggled(int index)
  signal nameClicked(string name)

  readonly property int rowH: 28
  readonly property int markedCount: Object.keys(tape.marks).length
  readonly property int namesH: tape.names.length > 0 ? 32 : 0
  readonly property int listH: Math.min(7, Math.max(1, tape.rows.length)) * tape.rowH
  readonly property int sumH: tape.markedCount > 0 ? 34 : 0
  implicitHeight: tape.namesH + tape.listH + tape.sumH + 8

  function reveal(i) { list.positionViewAtIndex(i, ListView.Contain); }

  // the names, as quiet tags; a click puts one in the field
  Row {
    id: nameRow
    visible: tape.names.length > 0
    x: 16
    height: tape.namesH
    spacing: 6

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: "Names"
      color: Zenon.muted
      font.family: Zenon.face
      font.weight: Font.Bold
      font.pixelSize: Zenon.px(11)
    }
    Repeater {
      model: tape.names
      delegate: MetisTip {
        required property var modelData
        anchors.verticalCenter: parent.verticalCenter
        word: modelData.name
        joiner: "="
        to: Metis.group(modelData.shown)
        MouseArea {
          anchors.fill: parent
          onClicked: tape.nameClicked(modelData.name)
        }
      }
    }
  }

  ListView {
    id: list
    // the chosen one slides (morpheus/CursorBand), rather than each row lighting
    CursorBand { follows: list; index: tape.idx }
    y: tape.namesH
    width: parent.width
    height: tape.listH
    clip: true
    model: tape.rows
    currentIndex: tape.idx
    boundsBehavior: Flickable.StopAtBounds
    Component.onCompleted: positionViewAtEnd()
    onCountChanged: positionViewAtEnd()

    delegate: Rectangle {
      id: row
      required property var modelData
      required property int index
      readonly property bool marked: tape.marks[row.index] === true
      readonly property bool sel: row.index === tape.idx
      width: list.width
      height: tape.rowH
      color: rowHover.pressed ? Zenon.alpha(Zenon.border, 0.35) : Zenon.alpha(Zenon.border, 0)
      Behavior on color { ColorAnimation { duration: Zenon.fast } }

      // the marked rows' tick, in the gutter
      Text {
        x: 16
        anchors.verticalCenter: parent.verticalCenter
        text: row.marked ? "" : row.modelData.pin ? "" : "·"
        color: row.marked ? Zenon.green : row.modelData.pin ? Zenon.blue : Zenon.muted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(12)
      }
      Text {
        x: 36
        width: parent.width - 36 - answerText.implicitWidth - 32
        anchors.verticalCenter: parent.verticalCenter
        text: row.modelData.expr
        elide: Text.ElideRight
        color: row.sel ? Zenon.keyInk : Zenon.muted
        font.family: Zenon.face
        font.weight: 500
        font.pixelSize: Zenon.px(13)
      }
      Text {
        id: answerText
        anchors.right: parent.right
        anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        text: Metis.group(row.modelData.result)
        color: row.marked ? Zenon.green : row.sel ? Zenon.blue : Zenon.keyInk
        font.family: Zenon.face
        font.weight: Font.Bold
        font.pixelSize: Zenon.px(14)
        font.features: { "tnum": 1 }
      }
      MouseArea {
        id: rowHover
        anchors.fill: parent
        hoverEnabled: true
        // a click marks; a double click brings the question back
        onClicked: tape.toggled(row.index)
        onDoubleClicked: tape.picked(row.index)
      }
    }
  }

  // the sum of what is marked, ruled off like a till's total
  Item {
    visible: tape.markedCount > 0
    y: tape.namesH + tape.listH + 4
    width: parent.width
    height: tape.sumH

    Rectangle {
      x: 16
      width: parent.width - 32
      height: 1
      color: Zenon.border
    }
    Text {
      x: 16
      anchors.verticalCenter: parent.verticalCenter
      text: "Σ  " + tape.markedCount + " marked"
      color: Zenon.muted
      font.family: Zenon.face
      font.weight: Font.Bold
      font.pixelSize: Zenon.px(12)
    }
    Text {
      anchors.right: parent.right
      anchors.rightMargin: 16
      anchors.verticalCenter: parent.verticalCenter
      text: tape.sumBad ? "These don't add up" : Metis.group(tape.sum)
      color: tape.sumBad ? Zenon.red : Zenon.green
      font.family: Zenon.face
      font.weight: Font.Bold
      font.pixelSize: Zenon.px(16)
      font.features: { "tnum": 1 }
    }
  }
}
