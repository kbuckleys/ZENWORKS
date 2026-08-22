// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/

import QtQuick
import "."

Item {
  id: root
  implicitWidth: 9
  implicitHeight: 32

  Column {
    anchors.centerIn: parent
    spacing: 3
    Repeater {
      model: 6
      Rectangle {
        width: 1
        height: 2
        radius: 1
        color: "#6a707f"
      }
    }
  }
}
