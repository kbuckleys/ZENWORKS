// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/

import QtQuick
import "../morpheus"

// ONE DAY, TWO PLACES. A time-zone answer is a pair of clock readings, and
// the question behind most of them is "is that a decent hour there?" — so
// both are marked on one midnight-to-midnight bar, night dark and day lit,
// each place at its own local time. The first label sits above the bar and
// the second below, so two places an hour apart do not write over each other.
Item {
  id: strip

  property var marks: []     // [{label, min}] — minutes after local midnight

  implicitHeight: 46

  readonly property color night: Qt.rgba(Zenon.blue.r, Zenon.blue.g, Zenon.blue.b, 0.10)
  readonly property color dawn: Qt.rgba(Zenon.yellow.r, Zenon.yellow.g, Zenon.yellow.b, 0.45)
  readonly property color day: Qt.rgba(Zenon.sand.r, Zenon.sand.g, Zenon.sand.b, 0.55)

  Rectangle {
    id: bar
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    height: 6
    radius: 3
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0.00; color: strip.night }
      GradientStop { position: 0.23; color: strip.night }
      GradientStop { position: 0.29; color: strip.dawn }
      GradientStop { position: 0.35; color: strip.day }
      GradientStop { position: 0.76; color: strip.day }
      GradientStop { position: 0.82; color: strip.dawn }
      GradientStop { position: 0.89; color: strip.night }
      GradientStop { position: 1.00; color: strip.night }
    }
  }

  // 6, 12, 18 — enough to read a position by
  Repeater {
    model: [6, 12, 18]
    delegate: Rectangle {
      required property int modelData
      x: bar.x + bar.width * modelData / 24 - width / 2
      anchors.verticalCenter: bar.verticalCenter
      width: 1
      height: 10
      color: Zenon.border
    }
  }

  Repeater {
    model: strip.marks

    delegate: Item {
      id: mark
      required property var modelData
      required property int index
      readonly property real cx: bar.width * Math.max(0, Math.min(1439, modelData.min)) / 1440
      readonly property bool above: index === 0
      anchors.fill: parent

      Rectangle {
        x: mark.cx - width / 2
        anchors.verticalCenter: parent.verticalCenter
        width: 11
        height: 11
        radius: 5.5
        color: mark.index === 0 ? Zenon.keyInk : Zenon.blue
        border.width: 2
        border.color: Zenon.layerBg
      }

      Text {
        id: tag
        x: Math.max(0, Math.min(strip.width - implicitWidth, mark.cx - implicitWidth / 2))
        y: mark.above ? bar.y - implicitHeight - 6 : bar.y + bar.height + 6
        text: mark.modelData.label + "  "
          + String(Math.floor(mark.modelData.min / 60)).padStart(2, "0") + ":"
          + String(mark.modelData.min % 60).padStart(2, "0")
        color: mark.index === 0 ? Zenon.keyInk : Zenon.blue
        font.family: Zenon.face
        font.weight: Font.Bold
        font.pixelSize: Zenon.px(11)
        font.features: { "tnum": 1 }
      }
    }
  }
}
