// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A FILE'S NAME AS A TITLE YOU CAN RENAME IT FROM (user, 2026-10-15) — the
// properties sheet's title: picasso's and plato's on the card (Sheet's
// head), terminus' on its bar. Drawn as the title it always was; a click
// (`editable` only) makes it a field with the stem selected, Return hands
// the new name up as `renamed`, Escape or a click away puts it back.
// Nothing is moved here: the holder renames by its own rules (a name
// taken, tags and marks following the file) and says so.
//
//     TitleName { text: row.name; editable: true
//                 onRenamed: (n) => win.renameTo(row.path, n)
//                 onDone: keys.forceActiveFocus() }
//
// `done` comes after either ending, for the holder to take its keys back.

import QtQuick
import "."

Item {
  id: tn
  property string text: ""
  property color color: Zenon.white
  property real pixelSize: Zenon.px(16)
  property int weight: Font.Bold
  // the most it may take before the name elides (the field scrolls instead)
  property real maxWidth: 400
  property bool editable: false
  readonly property bool editing: field.visible
  readonly property Item input: field
  signal renamed(string name)
  signal done()

  implicitWidth: tn.editing
    ? Math.min(tn.maxWidth, Math.max(field.contentWidth, tn.pixelSize * 6) + 2)
    : Math.min(tn.maxWidth, shown.implicitWidth)
  implicitHeight: shown.implicitHeight
  width: implicitWidth
  height: implicitHeight

  function begin() {
    if (!tn.editable || tn.editing) return;
    field.text = tn.text;
    // the stem, not the extension; a dotfile is all stem
    const dot = tn.text.lastIndexOf(".");
    field.visible = true;
    field.select(0, dot > 0 ? dot : tn.text.length);
    field.forceActiveFocus();
  }
  function cancel() {
    if (!tn.editing) return;
    field.visible = false;
    tn.done();
  }
  function commit() {
    if (!tn.editing) return;
    const n = String(field.text).trim();
    field.visible = false;
    if (n !== "" && n !== tn.text) tn.renamed(n);
    tn.done();
  }
  // the name changed under it (another file shown): not this one's to finish
  onTextChanged: tn.cancel()
  onEditableChanged: if (!tn.editable) tn.cancel()

  Text {
    id: shown
    visible: !tn.editing
    width: Math.min(implicitWidth, tn.maxWidth)
    elide: Text.ElideMiddle
    text: tn.text
    color: tn.color
    font.family: Zenon.face
    font.weight: tn.weight
    font.pixelSize: tn.pixelSize
    TapHandler { enabled: tn.editable; onTapped: tn.begin() }
  }

  TextInput {
    id: field
    visible: false
    anchors.fill: parent
    verticalAlignment: Text.AlignVCenter
    horizontalAlignment: contentWidth < width ? Text.AlignHCenter : Text.AlignLeft
    // through tn: inside the Caret, a bare `field` is its own property, and
    // `field: field` bound it to itself (a binding loop, 2026-10-15)
    cursorDelegate: Caret { field: tn.input }
    color: Zenon.white
    selectionColor: Zenon.alpha(Zenon.cyan, 0.22)
    selectedTextColor: Zenon.white
    selectByMouse: true
    clip: true
    font.family: Zenon.face
    font.weight: tn.weight
    font.pixelSize: tn.pixelSize
    // every key is the field's while it is open: the sheet's Escape and the
    // window's letters must not reach past it
    Keys.onPressed: (e) => {
      if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { e.accepted = true; tn.commit(); }
      else if (e.key === Qt.Key_Escape) { e.accepted = true; tn.cancel(); }
    }
    Keys.onShortcutOverride: (e) => { e.accepted = true; }
    onActiveFocusChanged: if (!activeFocus && visible) tn.cancel()
  }

  // the ring every field being typed in wears (terminus' EditRing look)
  Rectangle {
    anchors.fill: parent
    // little reach up and down: the bar is short, and the sheet's card
    // hanging under it covered the lower edge (user, 2026-10-15: "sunken")
    anchors.margins: -2
    anchors.leftMargin: -7
    anchors.rightMargin: -7
    radius: 4
    color: "transparent"
    border.width: 2
    border.color: Zenon.alpha(Zenon.cyan, 0.6)
    opacity: tn.editing ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }
  }
}
