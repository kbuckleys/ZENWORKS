import QtQuick
import "."

Item {
  id: root
  implicitWidth: row.implicitWidth
  implicitHeight: 32

  Row {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    leftPadding: 8
    rightPadding: 8

    BarText {
      text: "󰇙"
      color: "#dfdfdd"
    }
  }
}
