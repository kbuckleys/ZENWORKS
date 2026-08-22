// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/

import QtQuick
import Quickshell
import "."
import "helpers.js" as Helpers

PanelWindow {
  id: popup

  required property Item anchorItem
  required property string text
  property bool show: false
  property bool styled: false
  property int gap: 5
  property var history: []
  property color historyLineColor: "#9bbfbf"
  property color historyFillColor: "#9bbfbf"

  visible: popup.show && anchorItem.QsWindow.window !== null
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  aboveWindows: true
  screen: anchorItem.QsWindow.window?.screen ?? null

  mask: Region {}

  implicitWidth: background.implicitWidth
  implicitHeight: background.implicitHeight

  anchors { top: true; left: true }

  readonly property var barWin: anchorItem.QsWindow.window

  readonly property real targetX: {
    if (!barWin || !anchorItem) return 0;
    const p = anchorItem.mapToItem(barWin.contentItem, anchorItem.width / 2, 0);
    return p.x - popup.implicitWidth / 2;
  }

  margins.left: !barWin || !popup.screen ? 0 :
    Math.max(8, Math.min(Math.round(popup.targetX), Math.round(popup.screen.width - popup.implicitWidth - 8))) | 0
  margins.top: !barWin || !popup.screen ? 0 :
    (popup.screen.height - barWin.height - popup.gap - popup.implicitHeight) | 0

  Rectangle {
    id: background
    implicitWidth: layout.width
    implicitHeight: layout.height
    color: "#80000000"
    border.color: "#20242a"
    border.width: 1
    radius: 6

    Column {
      id: layout
      width: Math.max(content.implicitWidth, spark.visible ? spark.width + 40 : content.implicitWidth)
      height: content.implicitHeight + (spark.visible ? spark.height + 10 + 6 : 0)
      spacing: 0

      Text {
        id: content
        width: parent.width
        leftPadding: 20
        rightPadding: 20
        topPadding: 10
        bottomPadding: spark.visible ? 6 : 10
        text: popup.styled ? Helpers.tooltip(popup.text) : popup.text
        textFormat: popup.styled ? Text.StyledText : Text.PlainText
        color: "#DFDFDD"
        font.family: "JetBrainsMono Nerd Font Propo"
        font.weight: Font.Bold
        font.pixelSize: 16
        horizontalAlignment: Text.AlignLeft
        verticalAlignment: Text.AlignVCenter
        wrapMode: Text.NoWrap
      }

      Sparkline {
        id: spark
        visible: popup.history && popup.history.length >= 2
        width: Math.max(160, content.implicitWidth - 20)
        height: 32
        anchors.horizontalCenter: parent.horizontalCenter
        values: popup.history
        lineColor: popup.historyLineColor
        fillColor: popup.historyFillColor
        fillOpacity: 0.18
      }

      Item { width: 1; height: spark.visible ? 10 : 0 }
    }
  }
}
