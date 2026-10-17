// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A PASSWORD IN LARGE TYPE — for reading it off the screen into another
// device: each character large, numbered under it, digits and symbols in
// their own colors (1Password's Large Type). On a sheet; any key or click
// puts it away, and the window forgets the value as it goes.

import QtQuick
import "../morpheus"

Item {
  id: big
  property string value: ""
  property string label: ""
  implicitHeight: col.implicitHeight + 48

  Column {
    id: col
    x: 24
    y: 24
    width: parent.width - 48
    spacing: 18
    Text {
      text: big.label
      color: Zenon.accentMuted
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(13)
    }
    Flow {
      width: parent.width
      spacing: 6
      Repeater {
        model: Array.from(big.value)
        delegate: Rectangle {
          required property var modelData
          required property int index
          width: 44
          height: 66
          radius: Zenon.windowRadius
          color: index % 2 ? Zenon.wash(0.06) : Zenon.wash(0.02)
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 4
            text: modelData === " " ? "␣" : modelData
            color: /[0-9]/.test(modelData) ? Zenon.blue : /[A-Za-z]/.test(modelData) ? Zenon.ink : Zenon.pink
            font.family: Zenon.faceMono
            font.weight: Font.DemiBold
            font.pixelSize: 34
          }
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 3
            text: index + 1
            color: Zenon.accentMuted
            font.family: Zenon.face
            font.pixelSize: 10
          }
        }
      }
    }
  }
}
