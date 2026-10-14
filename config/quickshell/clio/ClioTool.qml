// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ONE BUTTON OF A NOTE'S TOOLBAR — a glyph (or Apple's "Aa"), its tooltip
// with the keys that do the same, and `pressed(x, y)`: where a menu it
// opens should hang, in the window's stage, under the button.

import QtQuick
import "../morpheus"

Item {
  id: tool
  property var pane: null
  property string glyph: ""
  property string word: ""
  property string tip: ""
  property string keys: ""
  property bool lit: false
  signal pressed(real x, real y)

  width: 34
  height: 30
  opacity: tool.enabled ? 1 : 0.35
  Rectangle {
    anchors.fill: parent
    radius: Zenon.windowRadius
    color: press.pressed ? Zenon.wash(0.14) : tool.lit ? Zenon.alpha(Zenon.yellow, 0.14) : "transparent"
  }
  Text {
    anchors.centerIn: parent
    text: tool.word !== "" ? tool.word : tool.glyph
    color: tool.lit ? Zenon.yellow : Zenon.soft
    font.family: tool.word !== "" ? Zenon.face : Zenon.glyphFace
    font.weight: Font.Bold
    font.pixelSize: tool.word !== "" ? Zenon.px(15) : Zenon.px(16)
  }
  MouseArea {
    id: press
    anchors.fill: parent
    onClicked: {
      const p = tool.mapToItem(tool.pane.win.stageItem, 0, tool.height + 4);
      tool.pressed(p.x, p.y);
    }
  }
  HoverHandler {
    onHoveredChanged: hovered && tool.tip !== "" ? tool.pane.win.tipsItem.show(tool, tool.tip, tool.keys) : tool.pane.win.tipsItem.hide(tool)
  }
}
