// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A FIELD'S LITTLE BUTTON — copy, reveal, open: a glyph in a small rounded
// square at the end of a field's row, its name in the window's tooltip
// (morpheus/WindowTip). No hover tint (the suite's buttons answer none,
// user 2026-10-11): it darkens while pressed, and `on` turns the glyph cyan
// (a field shown, a copy just made).
//
//     FieldAct { glyph: "…"; tip: "Copy"; tips: win.tipsItem; onClicked: … }

import QtQuick
import "../morpheus"

Rectangle {
  id: act
  property string glyph: ""
  property string tip: ""
  property var tips: null
  property bool on: false
  property color ink: Zenon.muted
  signal clicked()

  width: 28
  height: 28
  radius: Zenon.windowRadius
  // no chip behind a lit glyph (user, 2026-10-12): `on` colours the glyph
  color: press.pressed ? Zenon.wash(0.14) : Zenon.wash(0.0)
  Behavior on color { ColorAnimation { duration: Zenon.fast } }

  Text {
    anchors.centerIn: parent
    text: act.glyph
    color: act.on ? Zenon.cyan : act.ink
    font.family: Zenon.glyphFace
    font.pixelSize: Zenon.px(14)
    Behavior on color { ColorAnimation { duration: Zenon.fast } }
  }
  MouseArea {
    id: press
    anchors.fill: parent
    onClicked: act.clicked()
  }
  HoverHandler {
    onHoveredChanged: if (act.tips && act.tip !== "") { if (hovered) act.tips.show(act, act.tip, ""); else act.tips.hide(act); }
  }
}
