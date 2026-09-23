// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// WHAT THE KEYS DO, as a row of caps: `rows` is a list of [key, what it does].
// The strip it stands on (its ground, its rule, its height) belongs to each
// panel; the row is the same everywhere, which is the point of it being here.

import QtQuick
import "."

Row {
  id: hints
  property var rows: []
  spacing: 14

  Repeater {
    model: hints.rows
    delegate: Row {
      id: pair
      required property var modelData
      spacing: 5

      KeyCap {
        anchors.verticalCenter: parent.verticalCenter
        label: pair.modelData[0]
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: pair.modelData[1]
        color: Zenon.muted
        font.family: Zenon.face
        font.pixelSize: 13
      }
    }
  }
}
