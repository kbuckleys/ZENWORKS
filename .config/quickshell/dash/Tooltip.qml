// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/

import QtQuick
import Quickshell
import "helpers.js" as Helpers

PanelWindow {
  id: popup

  required property Item anchorItem
  required property string text
  property bool show: false
  property bool styled: false
  property int gap: 5

  visible: popup.show && anchorItem.QsWindow.window !== null
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  aboveWindows: true
  screen: anchorItem.QsWindow.window?.screen ?? null

  mask: Region {}

  implicitWidth: content.implicitWidth
  implicitHeight: content.implicitHeight

  anchors { top: true; left: true }

  readonly property var barWin: anchorItem.QsWindow.window

  readonly property real targetX: {
    if (!barWin || !anchorItem) return 0;
    const p = barWin.contentItem.mapFromItem(
        anchorItem,
        anchorItem.width / 2 - popup.implicitWidth / 2,
        0);
    return p.x;
  }

  margins.left: !barWin || !popup.screen ? 0 :
    Math.max(8, Math.min(Math.round(popup.targetX), Math.round(popup.screen.width - popup.implicitWidth - 8))) | 0
  margins.top: !barWin || !popup.screen ? 0 :
    (popup.screen.height - barWin.height - popup.gap - popup.implicitHeight) | 0

  Rectangle {
    id: background
    anchors.fill: parent
    color: "#80000000"
    border.color: "#20242a"
    border.width: 1
    radius: 6

    Text {
      id: content
      anchors.fill: parent
      leftPadding: 20
      rightPadding: 20
      topPadding: 10
      bottomPadding: 10
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
  }
}
