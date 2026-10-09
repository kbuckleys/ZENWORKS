// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/

import QtQuick
import "../morpheus"

// One chip under an answer: another unit, a name it might have meant, an
// example to try, or — with the field empty — a kept answer, its question
// (`sub`) muted in front.
//
// A row of them arrives one after another (`order`), a few frames apart, so
// it reads as growing out of the answer rather than being swapped in.
Rectangle {
  id: chip

  property string label: ""
  property string sub: ""
  property bool sel: false
  // a kept answer pinned to the front of the row (ctrl+p)
  property bool pinned: false
  property int order: 0
  signal clicked()

  width: row.implicitWidth + 18
  height: 26
  radius: 5
  // selected: blue, outlined — a grey fill alone was too quiet to find
  color: chip.sel ? Qt.rgba(Zenon.blue.r, Zenon.blue.g, Zenon.blue.b, 0.14)
    : hover.containsMouse ? Qt.rgba(Zenon.border.r, Zenon.border.g, Zenon.border.b, 0.45)
    : Zenon.alpha(Zenon.border, 0)
  Behavior on color { ColorAnimation { duration: Zenon.fast } }
  border.width: 1
  border.color: chip.sel ? Qt.rgba(Zenon.blue.r, Zenon.blue.g, Zenon.blue.b, 0.65) : Zenon.border
  Behavior on border.color { ColorAnimation { duration: Zenon.fast } }

  opacity: 0
  transform: Translate { id: lift; y: 6 }
  Component.onCompleted: arrive.start()
  SequentialAnimation {
    id: arrive
    PauseAnimation { duration: Math.min(chip.order, 8) * 25 }
    ParallelAnimation {
      NumberAnimation { target: chip; property: "opacity"; to: 1; duration: Zenon.normal; easing.type: Zenon.ease }
      NumberAnimation { target: lift; property: "y"; to: 0; duration: Zenon.normal; easing.type: Easing.OutCubic }
    }
  }

  Row {
    id: row
    anchors.centerIn: parent
    spacing: 7

    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: chip.pinned
      text: "\uF08D"
      color: Zenon.blue
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(12)
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: chip.sub !== ""
      // a long question is the least of what the chip says
      width: Math.min(implicitWidth, 170)
      elide: Text.ElideRight
      text: chip.sub
      color: Zenon.muted
      font.family: Zenon.face
      font.weight: 500
      font.pixelSize: Zenon.px(13)
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: chip.label
      color: chip.sel ? Zenon.blue : Zenon.keyInk
      Behavior on color { ColorAnimation { duration: Zenon.fast } }
      font.family: Zenon.face
      font.weight: Font.Bold
      font.pixelSize: Zenon.px(14)
      font.features: { "tnum": 1 }
    }
  }

  MouseArea {
    id: hover
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: chip.clicked()
  }
}
