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
  required property string text
  property bool show: false
  property bool styled: false
  property int gap: 5

  visible: popup.show
  color: "transparent"

  implicitWidth: content.implicitWidth
  implicitHeight: content.implicitHeight

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
    id: background
    anchors.fill: parent
    color: "#000000"
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
