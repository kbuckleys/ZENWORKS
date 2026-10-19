// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A TOOLTIP'S CARD — the label itself, wherever it hangs: morpheus/WindowTip
// hangs it in a popup surface beside a shell window. Tooltip's
// card, smaller, as a window's labels are. Here in terminus, beside
// BubbleCard, for the same reason: a live reload finds a new file in a
// directory without a qmldir (morpheus/tip/ importing its own parent did
// not reload).
//
// `text` is the holder's, rich: WindowTip escapes it and adds its muted key,
// through Strings.

import QtQuick
import "../morpheus"

Rectangle {
  id: card
  property string text: ""
  width: label.implicitWidth
  height: label.implicitHeight
  // frosted: its own surface, so hyprland blurs what is behind it (tipBg)
  color: Zenon.tipBg
  border.color: Zenon.border
  border.width: 1
  radius: Zenon.windowRadius
  // the glass rim, as Tooltip's card has it — see Zenon.rim
  Rectangle {
    visible: Zenon.rimOn
    z: 100
    x: parent.radius
    y: 1
    width: Math.max(0, parent.width - 2 * parent.radius)
    height: 1
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0.0; color: Zenon.alpha(Zenon.rim, 0) }
      GradientStop { position: 0.25; color: Zenon.rim }
      GradientStop { position: 0.75; color: Zenon.rim }
      GradientStop { position: 1.0; color: Zenon.alpha(Zenon.rim, 0) }
    }
  }

  Text {
    id: label
    leftPadding: 12
    rightPadding: 12
    topPadding: 6
    bottomPadding: 6
    textFormat: Text.StyledText
    text: card.text
    color: Zenon.white
    font.family: Zenon.face
    font.weight: Font.Bold
    font.pixelSize: Zenon.px(13)
  }
}
