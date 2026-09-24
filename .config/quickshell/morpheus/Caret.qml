// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// CARET — the text cursor every field in this shell wears.
//
//   cursorDelegate: Caret { field: myField }
//
// A cursorDelegate REPLACES the built-in one, so there is exactly one caret
// and this decides how it behaves. It breathes rather than blinking: a hard
// on/off is Qt's default, and in a field that is already asking for your
// attention it reads as a fault.
//
// Only while the field has focus. The breath stops on focus loss but the
// delegate does not go away, so without `visible` a field you had typed in
// kept a caret frozen at whatever opacity the breath had reached. Clio found
// that first; it was one copy of fourteen that knew.

import QtQuick
import "."

Rectangle {
  id: caret

  // the TextInput or TextEdit this is the cursor of
  property Item field: null

  width: 2
  color: Zenon.cyan
  visible: caret.field !== null && caret.field.activeFocus

  SequentialAnimation on opacity {
    running: caret.visible
    loops: Animation.Infinite
    NumberAnimation { to: 0.2; duration: 620; easing.type: Easing.InOutQuad }
    NumberAnimation { to: 1.0; duration: 620; easing.type: Easing.InOutQuad }
  }
}
