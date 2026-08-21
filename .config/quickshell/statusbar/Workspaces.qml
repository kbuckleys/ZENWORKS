// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/

import QtQuick
import Quickshell.Hyprland
import "helpers.js" as Helpers
import "."

Item {
  id: root
  implicitWidth: row.implicitWidth
  implicitHeight: 32

  property string specialName: "special"

  readonly property var specialWorkspace: {
    var values = Hyprland.workspaces.values;
    for (var i = 0; i < values.length; i++) {
      if (String(values[i].name).startsWith("special:")) return values[i];
    }
    return null;
  }

  property bool specialFocused: false

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "activespecial") {
        root.specialFocused = String(event.data).startsWith("special:");
      }
    }
  }

  Row {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    leftPadding: 4

    Repeater {
      model: Hyprland.workspaces

      delegate: Item {
        id: btn
        required property var modelData
        visible: !String(modelData.name).startsWith("special:")

        property bool isActive: modelData.focused

        width: label.implicitWidth + 16
        height: 32

        BarText {
          id: label
          anchors.centerIn: parent
          text: {
            return ["1", "2", "3", "4", "5"].includes(String(modelData.id)) ? String(modelData.id) : " ";
          }
          color: btn.isActive ? "#9bbfbf" : "#506060"
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            Hyprland.dispatch('hl.dsp.focus({ workspace = "' + modelData.name + '" })');
          }
        }
      }
    }

    Item {
      width: 8
      height: 32
      visible: root.specialWorkspace !== null
    }

    Item {
      id: special
      visible: root.specialWorkspace !== null
      width: label.implicitWidth + 14
      height: 32

      BarText {
        id: label
        anchors.centerIn: parent
        text: " "
        color: root.specialFocused ? "#e78284" : "#eebebe"
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          var sp = root.specialWorkspace !== null
              ? root.specialWorkspace.name.replace(/^special:/, "")
              : root.specialName;
          Hyprland.dispatch('hl.dsp.workspace.toggle_special("' + sp + '")');
        }
      }
    }
  }
}
