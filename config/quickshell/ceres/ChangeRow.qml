// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// One package moving: "name   from → to". The same three inks as the bar's
// tooltip and the toast — the old version greyed, the arrow in the accent,
// the new one plain — so a change reads the same wherever it is shown.

import QtQuick
import "../morpheus"
import "."
import "ceres.js" as Cer

Item {
  id: ch
  // Text size over the panel's: the window reads 2px larger.
  property int grow: 0
  // { name, from, to } — from may be "" for something new
  property var u: null
  property string glyph: ""
  property color glyphInk: Zenon.blue
  implicitHeight: 28

  Text {
    id: chGlyph
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    width: ch.glyph !== "" ? 22 : 0
    text: ch.glyph
    color: ch.glyphInk
    font.family: Zenon.face
    font.pixelSize: 13 + ch.grow
  }

  Text {
    anchors.left: chGlyph.right
    anchors.right: vers.left
    anchors.rightMargin: 12
    anchors.verticalCenter: parent.verticalCenter
    elide: Text.ElideRight
    text: ch.u ? ch.u.name : ""
    color: Zenon.white
    font.family: Zenon.face
    font.pixelSize: 15 + ch.grow
  }

  Text {
    id: vers
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    textFormat: Text.StyledText
    text: !ch.u ? "" : (ch.u.from
      ? "<font color='" + Ceres.ink.muted + "'>" + Cer.esc(ch.u.from) + "</font>  "
        + "<font color='" + Ceres.ink.arrow + "'>→</font>  " + Cer.esc(ch.u.to)
      : Cer.esc(ch.u.to || ""))
    color: Zenon.white
    font.family: Zenon.face
    font.pixelSize: 14 + ch.grow
  }
}
