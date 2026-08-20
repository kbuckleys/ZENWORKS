// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/

import QtQuick
import Quickshell
import "helpers.js" as Helpers

PopupWindow {
  id: popup

  required property Item anchorItem
  property bool show: false
  property int gap: 5

  readonly property var now: new Date()
  readonly property string monthName: [
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December"
  ][popup.now.getMonth()]
  readonly property int year: popup.now.getFullYear()
  readonly property int today: popup.now.getDate()
  readonly property string weekdayName: ["Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"][popup.now.getDay()]

  visible: popup.show
  color: "transparent"

  implicitWidth: bg.implicitWidth
  implicitHeight: bg.implicitHeight

  anchor {
    window: anchorItem.QsWindow.window
    adjustment: PopupAdjustment.Slide
    gravity: Edges.Bottom | Edges.Right
    onAnchoring: {
      const pos = anchorItem.QsWindow.contentItem.mapFromItem(
          anchorItem, anchorItem.width / 2 - popup.width / 2, -popup.height - popup.gap);
      anchor.rect.x = pos.x;
      anchor.rect.y = pos.y;
    }
  }

  Rectangle {
    id: bg
    implicitWidth: content.implicitWidth + 16
    implicitHeight: content.implicitHeight + 16
    color: "#000000"
    border.color: "#20242a"
    border.width: 1
    radius: 4

    Column {
      id: content
      anchors.centerIn: parent
      spacing: 10

      Column {
        width: parent.width
        spacing: 2

        Text {
          text: popup.monthName
          color: "#DFDFDD"
          font.family: "JetBrainsMono Nerd Font Propo"
          font.weight: Font.Bold
          font.pixelSize: 14
          font.capitalization: Font.Capitalize
          horizontalAlignment: Text.AlignHCenter
          anchors.horizontalCenter: parent.horizontalCenter
        }

        Text {
          text: popup.year + "  " + popup.weekdayName
          color: "#6a707f"
          font.family: "JetBrainsMono Nerd Font Propo"
          font.weight: Font.Bold
          font.pixelSize: 14
          horizontalAlignment: Text.AlignHCenter
          anchors.horizontalCenter: parent.horizontalCenter
        }
      }

      Rectangle {
        width: parent.width
        height: 1
        color: "#1e2228"
        radius: 1
      }

      Row {
        Repeater {
          model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
          delegate: Text {
            required property string modelData
            required property int index
            width: 34
            height: 18
            text: modelData
            color: index >= 5 ? "#7a8a9e" : "#4e5a6a"
            font.family: "JetBrainsMono Nerd Font Propo"
            font.weight: Font.Bold
            font.pixelSize: 14
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
          }
        }
      }

      Grid {
        columns: 7
        columnSpacing: 2
        rowSpacing: 0

        Repeater {
          model: popup.monthCells()
          delegate: Rectangle {
            required property int modelData
            required property int index
            width: 34
            height: 28
            radius: 3
            color: "transparent"

            Text {
              anchors.centerIn: parent
              text: modelData === 0 ? "" : String(modelData)
              color: modelData === popup.today ? "#9bbfbf" : (index % 7 >= 5 ? "#a2a8bc" : "#DFDFDD")
              opacity: modelData === 0 ? 0 : 1
              font.family: "JetBrainsMono Nerd Font Propo"
              font.weight: modelData === popup.today ? Font.Black : Font.Bold
              font.pixelSize: 14
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
            }
          }
        }
      }
    }
  }

  function monthCells() {
    const y = popup.year;
    const m = popup.now.getMonth();
    const first = new Date(y, m, 1);
    const offset = (first.getDay() + 6) % 7;
    const days = new Date(y, m + 1, 0).getDate();
    const cells = [];
    for (let i = 0; i < 42; ++i) {
      cells.push(i < offset || i >= offset + days ? 0 : i - offset + 1);
    }
    return cells;
  }
}
