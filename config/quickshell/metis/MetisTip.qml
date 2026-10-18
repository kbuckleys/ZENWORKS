// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/

import QtQuick
import "../morpheus"

// A TIP BESIDE THE FIELD: what a word you typed was taken as — "qatar →
// QAR", "rent = 1,200" — at the right of the field while you type, so the
// code you could not remember is learned without asking for it. Quieter
// than a chip: it is not something to pick, only to read (and to hover,
// for the bubble with the rest).
Rectangle {
  id: tip

  property string word: ""
  property string to: ""
  property string joiner: "→"
  readonly property bool hovered: hover.containsMouse

  width: row.implicitWidth + 14
  height: 24
  radius: 5
  color: Zenon.alpha(Zenon.border, 0)
  Behavior on color { ColorAnimation { duration: Zenon.fast } }
  border.width: 1
  border.color: Zenon.alpha(Zenon.border, 0.8)

  opacity: 0
  scale: 0.9
  Component.onCompleted: arrive.start()
  ParallelAnimation {
    id: arrive
    NumberAnimation { target: tip; property: "opacity"; to: 1; duration: Zenon.normal; easing.type: Zenon.ease }
    NumberAnimation { target: tip; property: "scale"; to: 1; duration: Zenon.slow; easing.type: Easing.OutBack }
  }

  Row {
    id: row
    anchors.centerIn: parent
    spacing: 5

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: tip.word
      color: Zenon.muted
      font.family: Zenon.face
      font.weight: 500
      font.pixelSize: Zenon.px(12)
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: tip.joiner
      color: Zenon.blue
      font.family: Zenon.face
      font.weight: Font.Bold
      font.pixelSize: Zenon.px(12)
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: tip.to
      color: Zenon.keyInk
      font.family: Zenon.face
      font.weight: Font.Bold
      font.pixelSize: Zenon.px(12)
      font.features: { "tnum": 1 }
    }
  }

  MouseArea {
    id: hover
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.NoButton
  }
}
