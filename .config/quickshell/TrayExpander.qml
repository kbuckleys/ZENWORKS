import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import "."

Item {
  id: root
  implicitWidth: row.implicitWidth
  implicitHeight: 32

  property bool hasTray: SystemTray.items.values.length > 0
  property bool hovered: false
  property bool iconHovered: false
  property bool menuOpen: false
  property bool open: root.hasTray && (root.hovered || root.iconHovered || root.menuOpen)

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    onEntered: root.hovered = true
    onExited: root.hovered = false
  }

  Row {
    id: row
    anchors.verticalCenter: parent.verticalCenter

    BarText {
      text: root.hasTray ? " \uf08b " : ""
      color: "#9bbfbf"
    }

    Row {
      id: drawer
      clip: true
      visible: root.hasTray
      anchors.verticalCenter: parent.verticalCenter
      width: root.open ? implicitWidth : 0
      opacity: root.open ? 1 : 0
      spacing: 12

      Behavior on width {
        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
      }
      Behavior on opacity {
        NumberAnimation { duration: 120 }
      }

      Repeater {
        model: SystemTray.items.values

        delegate: Item {
          id: trayItem
          required property var modelData

          width: 14
          height: 14
          anchors.verticalCenter: parent.verticalCenter

          IconImage {
            anchors.fill: parent
            source: modelData.icon
          }

          TrayMenu {
            id: trayMenu
            menuHandle: modelData.menu
            anchorItem: trayItem
            onMenuClosed: root.menuOpen = false
          }

          MouseArea {
            id: iconMouse
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            hoverEnabled: true
            onClicked: (mouse) => {
              if (mouse.button === Qt.LeftButton) modelData.activate()
              else if (modelData.hasMenu) {
                root.menuOpen = true
                trayMenu.open()
              }
              else modelData.secondaryActivate()
            }
            onEntered: root.iconHovered = true
            onExited: root.iconHovered = false
          }

          Tooltip {
            anchorItem: trayItem
            text: (modelData.tooltipTitle || modelData.title || "")
                + (modelData.tooltipDescription ? "\n" + modelData.tooltipDescription : "")
            show: iconMouse.containsMouse && text !== ""
          }
        }
      }
    }
  }
}
