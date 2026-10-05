// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// One diagnostic count in the status line: its glyph and its number, in its
// severity's ink, and nothing at all at 0. (A file of its own, not an inline
// component of StatusBar: a new inline component is not seen by a live
// reload.)

import QtQuick
import "../../morpheus"

Row {
  id: count
  property font font
  property int n: 0
  property string glyph: ""
  property int glyphSize: count.font.pixelSize
  property color ink: Zenon.white
  visible: count.n > 0
  spacing: 5
  anchors.verticalCenter: parent ? parent.verticalCenter : undefined
  Text {
    anchors.verticalCenter: parent.verticalCenter
    font.family: Zenon.faceMono
    font.pixelSize: count.glyphSize
    color: count.ink
    text: count.glyph
  }
  Text { anchors.verticalCenter: parent.verticalCenter; font: count.font; color: count.ink; text: String(count.n) }
}
