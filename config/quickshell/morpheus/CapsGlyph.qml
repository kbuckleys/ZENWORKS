// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// The caps-lock warning, as every password field wears it: the glyph alone,
// in red — red being what this shell keeps for what is actively wrong, and a
// password about to be refused for this is. It arrives and leaves rather than
// blinking. `shown` is the field's say in it (only while it takes input);
// CapsLock says the rest.
//
//     CapsGlyph { shown: field.visible; size: 16 }

import QtQuick
import "."

Text {
  id: glyph
  property bool shown: true
  property real size: 16

  text: "󰌎"
  color: Zenon.red
  font.family: Zenon.face
  font.pixelSize: glyph.size
  opacity: glyph.shown && CapsLock.on ? 1 : 0
  visible: opacity > 0.01
  Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutQuint } }
}
