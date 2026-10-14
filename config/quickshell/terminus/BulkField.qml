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
  // the modifiers held with that Return — read in onAccepted
  property int acceptModifiers: 0
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
  // ── CHIPS INSIDE, AND A FACE AT REST (2026-10-13) ─────────────────────
  // `leadIn` / `tailIn`: room kept clear inside either end for the holder's
  // own chips (children of the field, anchored there). `restText`: what the
  // field shows, centred, while it is not being typed in (Safari's line: the
  // site, not the whole address) — typing in it brings the text back whole.
  property real leadIn: 0
  property real tailIn: 0
  property string restText: ""
  // the ghost centred in the field, not at its start
  property bool ghostCentred: false
  // CENTRED ON THE FIELD ITSELF (user, 2026-10-13): the resting text and a
  // centred ghost stand at the field's middle whatever the chips at either
  // end are — kept clear of the wider end on both sides, so the middle holds
  readonly property real centreIn: Math.max(8 + fld.leadIn, (clearChip.visible ? clearChip.width + 12 : 8) + fld.tailIn)
  // ── AT REST, NOT YET A TEXT FIELD (2026-10-13) ──────────────────────
  // `restPointer`: until it has the keyboard the field is a thing to click,
  // not text to place a caret in — the ordinary pointer over it, and a faint
  // light that fades in under the pointer and out again; a press takes it
  // into typing with the whole text chosen (claim), as a browser's line does.
  property bool restPointer: false
  // the light held on from outside
  property bool hoverLit: false
  readonly property bool resting: fld.restText !== "" && !fldIn.activeFocus
  readonly property string family: fld.mono ? Zenon.faceMono : Zenon.face
  signal cleared()
  function clear() { fldIn.text = ""; fld.cleared(); }
  // Where Tab goes from here. The card owns the ring — a field should not
  // know what is next to it.
  signal tabbed()
  signal backTabbed()

  function claim() { fldIn.forceActiveFocus(); fldIn.selectAll(); }
  // for a holder that completes what is typed:
  // the text from `from` on chosen, the caret where the typing is
  function select(from, to) { fldIn.select(from, to); }
  readonly property alias cursorPosition: fldIn.cursorPosition
  readonly property alias selectionStart: fldIn.selectionStart
  readonly property alias selectionEnd: fldIn.selectionEnd
  // Backspace in an empty field
  signal emptyBackspace()

  // WHETHER IT ACTUALLY HAS THE KEYBOARD. The retry that opens the card has
  // to ask the field, not the scope around it: activeFocus propagates up a
  // FocusScope, so a scope that got focus while the claim inside it was
  // dropped looks exactly like success from the outside.
  readonly property alias focused: fldIn.activeFocus

  height: Math.max(26, fld.textSize + 12)
  radius: 4
  // ── A CARD HANGING FROM IT (2026-10-13) ───────────────────────────
  // `spliced`: a list hangs flush from the field's foot as one piece with it
  // — the field squares its bottom corners and wears the card's ground
  // (Zenon.menuBg), so the two are one surface; the focus ring steps aside
  // (it would draw a box round half of it).
  property bool spliced: false
  // the selection's colours: the field's own by default
  property color selColor: Zenon.selBg
  property color selInk: Zenon.white
  // `squareLeft` / `squareRight` 0..1: that end's corners squared off, by
  // so much, where something joins it
  property real squareLeft: 0
  property real squareRight: 0
  topLeftRadius: fld.radius * (1 - fld.squareLeft)
  topRightRadius: fld.radius * (1 - fld.squareRight)
  bottomLeftRadius: fld.spliced ? 0 : fld.radius * (1 - fld.squareLeft)
  bottomRightRadius: fld.spliced ? 0 : fld.radius * (1 - fld.squareRight)
  color: fld.spliced ? Zenon.menuBg : Qt.rgba(Zenon.white.r, Zenon.white.g, Zenon.white.b, 0.05)
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
    anchors.leftMargin: fld.ghostCentred ? fld.centreIn : 8 + fld.leadIn
    anchors.rightMargin: fld.ghostCentred ? fld.centreIn : 8 + fld.tailIn
    verticalAlignment: Text.AlignVCenter
    horizontalAlignment: fld.ghostCentred ? Text.AlignHCenter : Text.AlignLeft
    elide: Text.ElideRight
    visible: fldIn.text === ""
    text: fld.ghost
    color: Zenon.muted
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
    visible: fld.overflows && !fldIn.activeFocus && !fld.resting
    text: fld.masked ? "\u2022".repeat(fldIn.text.length) : fldIn.text
    elide: fld.elide
    color: Zenon.white
    font.family: fld.family
    font.weight: Zenon.weight
    font.pixelSize: fld.textSize
  }

  Text {
    anchors.fill: parent
    anchors.leftMargin: fld.centreIn
    anchors.rightMargin: fld.centreIn
    verticalAlignment: Text.AlignVCenter
    horizontalAlignment: Text.AlignHCenter
    visible: fld.resting && fldIn.text !== ""
    text: fld.restText
    elide: Text.ElideMiddle
    color: Zenon.white
    font.family: fld.family
    font.weight: Zenon.weight
    font.pixelSize: fld.textSize
  }

  TextInput {
    id: fldIn
    opacity: (fld.overflows && !fldIn.activeFocus) || (fld.resting && fldIn.text !== "") ? 0 : 1

    cursorDelegate: Caret { field: fldIn }
    anchors.fill: parent
    anchors.leftMargin: 8 + fld.leadIn
    anchors.rightMargin: (clearChip.visible ? clearChip.width + 12 : 8) + fld.tailIn
    verticalAlignment: Text.AlignVCenter
    color: Zenon.white
    selectionColor: fld.selColor
    selectedTextColor: fld.selInk
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
      if (e.key === Qt.Key_Backspace && fldIn.text === "") { e.accepted = true; fld.emptyBackspace(); return; }
      if (e.key === Qt.Key_Backtab) { e.accepted = true; fld.backTabbed(); return; }
      if (fld.copyHook && (e.matches(StandardKey.Copy) || e.matches(StandardKey.Cut))) {
        e.accepted = true;
        const t = fldIn.selectedText !== "" ? fldIn.selectedText : fldIn.text;
        if (t !== "") fld.copyHook(t);
        if (e.matches(StandardKey.Cut) && fldIn.selectedText !== "") fldIn.remove(fldIn.selectionStart, fldIn.selectionEnd);
        return;
      }
    }
    Keys.onReturnPressed: (e) => { e.accepted = true; fld.acceptModifiers = e.modifiers; fld.accepted(); }
    Keys.onEnterPressed: (e) => { e.accepted = true; fld.acceptModifiers = e.modifiers; fld.accepted(); }
  }
  // the resting field's pointer and light (restPointer): over the input,
  // under the holder's chips (z 2)
  Rectangle {
    anchors.fill: parent
    anchors.margins: 1
    z: 0.5
    radius: Math.max(0, fld.radius - 1)
    topLeftRadius: Math.max(0, fld.topLeftRadius - 1)
    topRightRadius: Math.max(0, fld.topRightRadius - 1)
    bottomLeftRadius: Math.max(0, fld.bottomLeftRadius - 1)
    bottomRightRadius: Math.max(0, fld.bottomRightRadius - 1)
    color: Zenon.alpha(Zenon.white, 0.06)
    opacity: fld.restPointer && (restArea.containsMouse || fld.hoverLit) && !fldIn.activeFocus ? 1 : 0
    visible: opacity > 0.001
    Behavior on opacity { NumberAnimation { duration: Zenon.normal; easing.type: Easing.OutCubic } }
  }
  MouseArea {
    id: restArea
    anchors.fill: parent
    z: 1
    visible: fld.restPointer && !fldIn.activeFocus
    hoverEnabled: true
    cursorShape: Qt.ArrowCursor
    onPressed: fld.claim()
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
  HeldRing { anchors.fill: parent; radius: parent.radius; z: 10; on: fldIn.activeFocus && !fld.spliced }
}
