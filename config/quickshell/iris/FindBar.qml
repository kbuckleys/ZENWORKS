// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// FIND IN PAGE (Ctrl+F) — a strip along the window's foot, in the bar's own
// glass (the window's ground, as terminus' bars) and hairline: terminus/BulkField to type in, found as it is typed
// (Chromium's own findText, highlights and all), "3 of 12", and the next or
// previous match (Return / ↓, Shift+Return / ↑, or the keys beside it).
// Escape, or the ×, clears the highlights and puts it away.

import QtQuick
import QtWebEngine
import "../morpheus"
import "../terminus" as Term

Rectangle {
  id: find
  required property var deck
  property bool open: false
  property alias text: field.text
  property int matches: 0
  property int at: 0

  height: find.open ? 42 : 0
  visible: find.open
  color: Zenon.layerBg
  Rectangle { width: parent.width; height: 1; color: Zenon.border }

  function show() {
    find.open = true;
    field.claim();
    if (field.text !== "") find.go(false);
  }
  function close() {
    if (!find.open) return;
    find.open = false;
    if (find.deck.here) { find.deck.here.findText(""); find.deck.here.forceActiveFocus(); }
    find.matches = 0;
  }
  function go(back) {
    const p = find.deck.here;
    if (!p) return;
    p.findText(field.text, back ? WebEngineView.FindBackward : 0);
  }
  Connections {
    target: find.deck.here
    ignoreUnknownSignals: true
    function onFindTextFinished(result) {
      find.matches = result.numberOfMatches;
      find.at = result.activeMatch;
    }
  }
  // another tab: its own page, unsearched
  Connections {
    target: find.deck
    function onHereChanged() { find.matches = 0; if (find.open && field.text !== "") find.go(false); }
  }

  Row {
    anchors.left: parent.left
    anchors.leftMargin: 14
    anchors.verticalCenter: parent.verticalCenter
    spacing: 14
    Term.BulkField {
      id: field
      width: 320
      textSize: Zenon.px(14)
      ghost: "Find in page"
      clearable: true
      onTextChanged: if (find.open) find.go(false)
      onAccepted: find.go(false)
      Keys.onPressed: (e) => {
        if (e.key === Qt.Key_Escape) { e.accepted = true; find.close(); }
        else if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && (e.modifiers & Qt.ShiftModifier)) { e.accepted = true; find.go(true); }
        else if (e.key === Qt.Key_Down) { e.accepted = true; find.go(false); }
        else if (e.key === Qt.Key_Up) { e.accepted = true; find.go(true); }
      }
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: field.text === "" ? "" : find.matches === 0 ? "No matches" : find.at + " of " + find.matches
      color: field.text !== "" && find.matches === 0 ? Zenon.red : Zenon.muted
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(13)
    }
    TransportKey {
      anchors.verticalCenter: parent.verticalCenter
      glyph: "\u{F0143}"
      size: Zenon.px(18)
      enabled: find.matches > 0
      ink: enabled ? Zenon.white : Zenon.muted
      onActivated: find.go(true)
    }
    TransportKey {
      anchors.verticalCenter: parent.verticalCenter
      glyph: "\u{F0140}"
      size: Zenon.px(18)
      enabled: find.matches > 0
      ink: enabled ? Zenon.white : Zenon.muted
      onActivated: find.go(false)
    }
  }
  TransportKey {
    anchors.right: parent.right
    anchors.rightMargin: 16
    anchors.verticalCenter: parent.verticalCenter
    glyph: "\u{F0156}"
    size: Zenon.px(18)
    onActivated: find.close()
  }
}
