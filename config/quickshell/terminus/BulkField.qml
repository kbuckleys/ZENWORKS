// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//

//
// Shared, as BulkDrop is.

import QtQuick
import "../morpheus"

Rectangle {
  id: fld
  property string ghost: ""
  // As BulkDrop has one — the two sit side by side in a row and have to
  // agree about how big the type is.
  property int textSize: 14
  property alias text: fldIn.text
  // Which end gives way when the text is wider than the field and the field
  // is not being typed in. A path keeps its tail, so a path field says Left.
  property int elide: Text.ElideRight
  signal accepted()
  // Where Tab goes from here. The card owns the ring — a field should not
  // know what is next to it.
  signal tabbed()
  signal backTabbed()

  function claim() { fldIn.forceActiveFocus(); fldIn.selectAll(); }

  // WHETHER IT ACTUALLY HAS THE KEYBOARD. The retry that opens the card has
  // to ask the field, not the scope around it: activeFocus propagates up a
  // FocusScope, so a scope that got focus while the claim inside it was
  // dropped looks exactly like success from the outside.
  readonly property alias focused: fldIn.activeFocus

  height: Math.max(26, fld.textSize + 12)
  radius: 4
  color: Qt.rgba(Zenon.white.r, Zenon.white.g, Zenon.white.b, 0.05)
  border.width: 1
  border.color: Zenon.border
  Behavior on border.color { ColorAnimation { duration: Zenon.fast } }

  // Declared FIRST, so the input above it still gets the clicks that place
  // its own caret. This one only catches the padding either side of the
  // text, which is otherwise a strip of field that does not focus it.
  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.IBeamCursor
    onClicked: fldIn.forceActiveFocus()
  }

  Text {
    anchors.fill: parent
    anchors.leftMargin: 8
    verticalAlignment: Text.AlignVCenter
    visible: fldIn.text === ""
    text: fld.ghost
    color: Zenon.muted
    font.family: Zenon.face
    font.pixelSize: fld.textSize
  }

  // ── AT REST, A LONG VALUE IS SHORTENED, NOT CUT ───────────────────
  // A TextInput wider than itself scrolls to its caret and clips wherever
  // that leaves it — the search sheet's "~/.config/quickshell/terminus"
  // came out as "’.config/…", the last sliver of the slash reading as a
  // stray apostrophe. Unfocused and overflowing, the field shows this
  // elided copy instead; a click hands it back to the input, which shows
  // the whole thing for editing.
  readonly property bool overflows: fldIn.contentWidth > fldIn.width
  Text {
    anchors.fill: fldIn
    verticalAlignment: Text.AlignVCenter
    visible: fld.overflows && !fldIn.activeFocus
    text: fldIn.text
    elide: fld.elide
    color: Zenon.white
    font.family: Zenon.face
    font.pixelSize: fld.textSize
  }

  TextInput {
    id: fldIn
    opacity: fld.overflows && !fldIn.activeFocus ? 0 : 1

    cursorDelegate: Caret { field: fldIn }
    anchors.fill: parent
    anchors.leftMargin: 8
    anchors.rightMargin: 8
    verticalAlignment: Text.AlignVCenter
    color: Zenon.white
    selectionColor: Zenon.selBg
    selectedTextColor: Zenon.white
    font.family: Zenon.face
    font.pixelSize: fld.textSize
    clip: true
    // Before the specific handlers below, which is where Tab has to be
    // caught: a TextInput otherwise hands it to the scene's own focus chain,
    // which in a card full of list delegates lands somewhere arbitrary.
    Keys.onPressed: (e) => {
      if (e.key === Qt.Key_Tab) { e.accepted = true; fld.tabbed(); return; }
      if (e.key === Qt.Key_Backtab) { e.accepted = true; fld.backTabbed(); return; }
    }
    Keys.onReturnPressed: (e) => { e.accepted = true; fld.accepted(); }
    Keys.onEnterPressed: (e) => { e.accepted = true; fld.accepted(); }
  }
}
