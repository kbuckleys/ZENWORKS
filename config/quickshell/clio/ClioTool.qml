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
  // a word's size and weight (the format bar's style names)
  property int wordPx: Zenon.px(15)
  property int wordWeight: Font.Bold
  // what the lit state is drawn in: the lock's yellow, the format bar's cyan
  property color litInk: Zenon.yellow
  readonly property bool hovered: hov.hovered
  // `menu`: it opens the window's menu, and stays pressed while that is up
  // (the window's menuHeld names it; user, 2026-10-17)
  property bool menu: false
  readonly property bool held: tool.menu && !!tool.pane && !!tool.pane.win && tool.pane.win.menuRef.isOpen
    && tool.pane.win.menuHeld === "tool:" + tool.glyph
  signal pressed(real x, real y)

  // the format bar's are narrower, to fit every format across the note
  property int size: 34
  property int pad: 18
  width: tool.word !== "" ? Math.max(tool.size, label.implicitWidth + tool.pad) : tool.size
  height: 30
  opacity: tool.enabled ? 1 : 0.35
  Rectangle {
    anchors.fill: parent
    radius: Zenon.windowRadius
    color: press.pressed || tool.held ? Zenon.pressWash(0.14) : tool.lit ? Zenon.alpha(tool.litInk, 0.14) : "transparent"
  }
  Text {
    id: label
    anchors.centerIn: parent
    text: tool.word !== "" ? tool.word : tool.glyph
    color: tool.lit ? tool.litInk : Zenon.accentSoft
    font.family: tool.word !== "" ? Zenon.face : Zenon.glyphFace
    font.weight: tool.word !== "" ? tool.wordWeight : Font.Bold
    font.pixelSize: tool.word !== "" ? tool.wordPx : Zenon.px(16)
  }
  MouseArea {
    id: press
    anchors.fill: parent
    onClicked: {
      const p = tool.mapToItem(tool.pane.win.stageItem, 0, tool.height + 4);
      tool.pressed(p.x, p.y);
      if (tool.menu && tool.pane.win.menuRef.isOpen) tool.pane.win.menuHeld = "tool:" + tool.glyph;
    }
  }
  HoverHandler {
    id: hov
    onHoveredChanged: hovered && tool.tip !== "" ? tool.pane.win.tipsItem.show(tool, tool.tip, tool.keys) : tool.pane.win.tipsItem.hide(tool)
  }
}
