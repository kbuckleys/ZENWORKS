// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/

import QtQuick
import Quickshell
import "."

PopupWindow {
  id: root

  required property var menuHandle
  required property Item anchorItem
  property bool isSubMenu: false

  property var childMenu: null
  signal menuClosed

  color: "transparent"
  visible: false
  grabFocus: true

  implicitWidth: 220
  implicitHeight: Math.min(720, content.implicitHeight + 12)

  anchor {
    window: root.anchorItem.QsWindow.window
    adjustment: PopupAdjustment.Slide
    gravity: Edges.Bottom | Edges.Right
    onAnchoring: {
      const pos = root.anchorItem.QsWindow.contentItem.mapFromItem(root.anchorItem, 0, 0);
      anchor.rect.x = pos.x + (root.isSubMenu ? root.anchorItem.width + 6 : 0);
      anchor.rect.y = pos.y + (root.isSubMenu ? 0 : -root.height - 6);
    }
  }

  onVisibleChanged: {
    if (!root.visible) root.menuClosed();
  }

  onImplicitHeightChanged: {
    if (root.visible) Qt.callLater(() => anchor.updateAnchor());
  }
  onImplicitWidthChanged: {
    if (root.visible) Qt.callLater(() => anchor.updateAnchor());
  }

  QsMenuOpener {
    id: opener
    menu: root.menuHandle
  }

  Rectangle {
    id: background
    anchors.fill: parent
    color: "#000000"
    border.color: "#20242a"
    border.width: 1
    radius: 6

    Column {
      id: content
      anchors.fill: parent
      anchors.margins: 4
      spacing: 2

      Repeater {
        id: repeater
        model: opener.children

        delegate: Item {
          id: entry
          required property var modelData

          width: content.width
          height: modelData.isSeparator ? 8 : Math.max(28, label.implicitHeight + 12)

          Rectangle {
            id: highlight
            anchors.fill: parent
            radius: 3
            color: hover.containsMouse && !modelData.isSeparator ? "#20242a" : "transparent"
          }

          Rectangle {
            id: separatorLine
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: "#20242a"
            visible: modelData.isSeparator
          }

          Item {
            id: row
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8

            Image {
              id: icon
              anchors.verticalCenter: parent.verticalCenter
              width: 16
              height: 16
              source: modelData.icon
              sourceSize.width: 16
              sourceSize.height: 16
              visible: modelData.icon !== ""
            }

            Text {
              id: label
              anchors.left: icon.visible ? icon.right : parent.left
              anchors.leftMargin: 8
              anchors.right: rightArea.left
              anchors.rightMargin: 8
              anchors.verticalCenter: parent.verticalCenter
              horizontalAlignment: Text.AlignHCenter
              text: modelData.text
              elide: Text.ElideRight
              color: modelData.enabled ? "#e8e8e8" : "#606060"
              font.family: "JetBrainsMono Nerd Font Propo"
              font.weight: Font.Medium
              font.pixelSize: 15
            }

            Item {
              id: rightArea
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: 16
              height: 16

              Text {
                id: check
                anchors.centerIn: parent
                visible: modelData.checkState === 2 && !modelData.hasChildren
                text: "✓"
                color: "#e8e8e8"
                font.family: "JetBrainsMono Nerd Font Propo"
                font.weight: Font.Medium
                font.pixelSize: 13
              }

              Text {
                id: arrow
                anchors.centerIn: parent
                visible: modelData.hasChildren
                text: "▶"
                color: "#808080"
                font.pixelSize: 10
              }
            }
          }

          MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            enabled: modelData.enabled && !modelData.isSeparator
            onEntered: {
              if (modelData.hasChildren) root.openChild(entry);
            }
            onClicked: (mouse) => {
              if (modelData.hasChildren) {
                root.openChild(entry);
                return;
              }
              modelData.triggered();
              root.closeMenu();
            }
          }
        }
      }
    }
  }

  function open() {
    root.visible = true;
  }

  function openChild(entry) {
    if (root.childMenu && root.childMenu.menuHandle === entry.modelData) return;
    if (root.childMenu) root.childMenu.closeMenu();
    const comp = Qt.createComponent("TrayMenu.qml");
    root.childMenu = comp.createObject(root, {
      menuHandle: entry.modelData,
      anchorItem: entry,
      isSubMenu: true
    });
    root.childMenu.open();
  }

  function closeMenu() {
    if (root.childMenu) {
      root.childMenu.closeMenu();
      root.childMenu.destroy();
      root.childMenu = null;
    }
    root.visible = false;
  }
}
