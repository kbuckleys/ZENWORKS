// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/

import QtQuick
import "helpers.js" as Helpers

Text {
  id: root
  property string src: ""
  property bool styled: false
  property color textColor: "#ffffff"

  text: root.styled ? Helpers.apply(root.src) : Helpers.collapse(root.src)
  textFormat: root.styled ? Text.StyledText : Text.PlainText
  color: root.textColor
  font.family: "JetBrainsMono Nerd Font Propo"
  font.weight: Font.Bold
  font.pixelSize: 16
  verticalAlignment: Text.AlignVCenter
  horizontalAlignment: Text.AlignHCenter
  renderType: Text.QtRendering
}
