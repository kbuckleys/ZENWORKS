import QtQuick
import Quickshell.Hyprland
import "helpers.js" as Helpers
import "."

Item {
  id: root
  implicitWidth: row.implicitWidth
  implicitHeight: 32

  Row {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    leftPadding: 4

    Repeater {
      model: Hyprland.workspaces

      delegate: Item {
        id: btn
        required property var modelData

        property bool isSpecial: modelData.id < 0
        property bool isActive: modelData.focused

        width: label.implicitWidth + (isSpecial ? 14 : 16)
        height: 32

        BarText {
          id: label
          anchors.centerIn: parent
          text: {
            if (btn.isSpecial) return " ";
            return ["1", "2", "3", "4", "5"].includes(String(modelData.id)) ? String(modelData.id) : " ";
          }
          color: btn.isSpecial
              ? (btn.isActive ? "#e78284" : "#eebebe")
              : (btn.isActive ? "#9bbfbf" : "#506060")
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (btn.isSpecial) Hyprland.dispatch("togglespecialworkspace " + modelData.name);
            else Hyprland.dispatch("workspace " + modelData.name);
          }
        }
      }
    }
  }
}
