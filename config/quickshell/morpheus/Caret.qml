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

  // how thick, and how far the breath fades — a page of writing (clio)
  // wants a plainer caret than a one-line field
  property int thick: 2
  property real low: 0.2
  // `steady`: held full while the caret moves (typing, arrows), breathing
  // again only once it rests
  property bool steady: false

  width: caret.thick
  color: Zenon.cyan
  visible: caret.field !== null && caret.field.activeFocus

  SequentialAnimation on opacity {
    id: breath
    running: caret.visible
    loops: Animation.Infinite
    PauseAnimation { duration: caret.steady ? 500 : 0 }
    NumberAnimation { to: caret.low; duration: 620; easing.type: Easing.InOutQuad }
    NumberAnimation { to: 1.0; duration: 620; easing.type: Easing.InOutQuad }
  }
  Connections {
    target: caret.steady ? caret.field : null
    ignoreUnknownSignals: true
    function onCursorPositionChanged() { caret.opacity = 1; if (breath.running) breath.restart(); }
  }
}
