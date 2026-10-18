// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A GLYPH BUTTON ON A SIDEBAR HEADING — "New container", "From a template",
// "New journal" sit on the heading's own line, at its right, instead of being
// rows of their own under the group (user, 2026-10-17). Hover lights it, a
// press darkens it; the tip says what it does.

import QtQuick
import "../morpheus"

Rectangle {
  id: hb
  property var win: null
  property string glyph: ""
  property string tip: ""
  property string keys: ""
  property bool held: false
  signal clicked(real x, real y)
  signal menu(real x, real y)

  width: 26
  height: 24
  radius: Zenon.windowRadius
  color: press.pressed ? Zenon.pressWash(0.16) : hb.held ? Zenon.wash(0.08) : "transparent"
  Text {
    anchors.centerIn: parent
    text: hb.glyph
    color: press.pressed ? Zenon.accentSoft : hb.held ? Zenon.ink : Zenon.accentMuted
    font.family: Zenon.glyphFace
    font.pixelSize: Zenon.px(14)
  }
  MouseArea {
    id: press
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: (m) => {
      const p = hb.win ? hb.mapToItem(hb.win.stageItem, m.button === Qt.RightButton ? m.x : 0, m.button === Qt.RightButton ? m.y : hb.height) : Qt.point(0, 0);
      if (m.button === Qt.RightButton) hb.menu(p.x, p.y); else hb.clicked(p.x, p.y);
    }
    onContainsMouseChanged: {
      if (!hb.win || hb.tip === "") return;
      if (containsMouse) hb.win.tipsItem.show(hb, hb.tip, hb.keys); else hb.win.tipsItem.hide(hb);
    }
  }
}
