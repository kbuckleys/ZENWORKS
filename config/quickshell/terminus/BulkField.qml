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
  // ── A CHIP TO CLEAR IT (user, 2026-10-11) ─────────────────────────
  // For a search or a filter: a small round × inside the field's right
  // end, there while it holds text. Pressed, the text goes and `cleared`
  // tells the holder — one that searches on Return searches again on it.
  property bool clearable: false
  // ── A SECRET, OR CODE (calypso's editor, 2026-10-12) ──────────────
  // `masked`: drawn as dots, as a password field is, until the holder
  // shows it; `mono`: in the monospaced face (a key, a code).
  property bool masked: false
  property bool mono: false
  // A field holding a secret hands its copies to the holder instead of the
  // clipboard: calypso's go out marked sensitive, so the clipboard history
  // never keeps them (user, 2026-10-12). function(text) or null.
  property var copyHook: null
  readonly property string family: fld.mono ? Zenon.faceMono : Zenon.face
  signal cleared()
  function clear() { fldIn.text = ""; fld.cleared(); }
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
    anchors.rightMargin: 8
    verticalAlignment: Text.AlignVCenter
    elide: Text.ElideRight
    visible: fldIn.text === ""
    text: fld.ghost
    color: Zenon.accentMuted
    font.family: fld.family
    font.weight: Zenon.weight
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
    text: fld.masked ? "\u2022".repeat(fldIn.text.length) : fldIn.text
    elide: fld.elide
    color: Zenon.white
    font.family: fld.family
    font.weight: Zenon.weight
    font.pixelSize: fld.textSize
  }

  TextInput {
    id: fldIn
    opacity: fld.overflows && !fldIn.activeFocus ? 0 : 1

    cursorDelegate: Caret { field: fldIn }
    anchors.fill: parent
    anchors.leftMargin: 8
    anchors.rightMargin: clearChip.visible ? clearChip.width + 12 : 8
    verticalAlignment: Text.AlignVCenter
    color: Zenon.white
    selectionColor: Zenon.selBg
    selectedTextColor: Zenon.white
    font.family: fld.family
    font.weight: Zenon.weight
    font.pixelSize: fld.textSize
    echoMode: fld.masked ? TextInput.Password : TextInput.Normal
    passwordCharacter: "\u2022"
    clip: true
    // Before the specific handlers below, which is where Tab has to be
    // caught: a TextInput otherwise hands it to the scene's own focus chain,
    // which in a card full of list delegates lands somewhere arbitrary.
    Keys.onPressed: (e) => {
      if (e.key === Qt.Key_Tab) { e.accepted = true; fld.tabbed(); return; }
      if (e.key === Qt.Key_Backtab) { e.accepted = true; fld.backTabbed(); return; }
      if (fld.copyHook && (e.matches(StandardKey.Copy) || e.matches(StandardKey.Cut))) {
        e.accepted = true;
        const t = fldIn.selectedText !== "" ? fldIn.selectedText : fldIn.text;
        if (t !== "") fld.copyHook(t);
        if (e.matches(StandardKey.Cut) && fldIn.selectedText !== "") fldIn.remove(fldIn.selectionStart, fldIn.selectionEnd);
        return;
      }
    }
    Keys.onReturnPressed: (e) => { e.accepted = true; fld.accepted(); }
    Keys.onEnterPressed: (e) => { e.accepted = true; fld.accepted(); }
  }
  ClearChip {
    id: clearChip
    size: fld.textSize
    shown: fld.clearable && fldIn.text !== ""
    anchors.right: parent.right
    anchors.rightMargin: Math.round((fld.height - height) / 2)
    anchors.verticalCenter: parent.verticalCenter
    onClicked: fld.clear()
  }
  // focused for typing: terminus' held ring (user, 2026-10-11 — every
  // text field wears it, its own border staying neutral)
  HeldRing { anchors.fill: parent; radius: parent.radius; z: 10; on: fldIn.activeFocus }
}
