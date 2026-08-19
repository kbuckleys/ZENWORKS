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

  visible: popup.show
  color: "transparent"

  implicitWidth: content.implicitWidth + 12
  implicitHeight: content.implicitHeight + 12

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
    anchors.fill: parent
    color: "#000000"
    border.color: "#20242a"
    border.width: 1

    Column {
      id: content
      anchors.fill: parent
      anchors.margins: 6
      spacing: 2

      Text {
        id: header
        text: popup.monthName + " " + popup.year
        color: "#9bbfbf"
        width: parent.width
        font.family: "JetBrainsMono Nerd Font Propo"
        font.weight: Font.Bold
        font.pixelSize: 16
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
      }

      Row {
        id: weekRow
        Repeater {
          model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
          delegate: Text {
            required property string modelData
            width: 26
            height: 18
            text: modelData
            color: "#56606d"
            font.family: "JetBrainsMono Nerd Font Propo"
            font.weight: Font.Bold
            font.pixelSize: 16
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
          }
        }
      }

      Grid {
        id: grid
        columns: 7

        Repeater {
          model: popup.monthCells()
          delegate: Rectangle {
            required property int modelData
            width: 26
            height: 18
            color: modelData === popup.today ? "#dfdfdd" : "transparent"

            Text {
              anchors.centerIn: parent
              text: modelData === 0 ? "" : String(modelData)
              color: modelData === popup.today ? "#000000" : "#dfdfdd"
              font.family: "JetBrainsMono Nerd Font Propo"
              font.weight: Font.Bold
              font.pixelSize: 16
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
