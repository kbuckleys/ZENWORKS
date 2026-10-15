// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE SEARCH OVER CLIO'S LIST — every word somewhere, and Apple's tokens
// (#tag, is:pinned, has:checklist…), offered as chips while it is empty and
// focused. Typing in the list lands here; Esc clears it, then hands the
// keys back.

import QtQuick
import "../morpheus"
import "../terminus"

Item {
  id: bar
  property var win: null
  function grab() { searchField.forceActiveFocus(); searchField.selectAll(); }
  function type(t) { searchField.text += t; searchField.forceActiveFocus(); }
  function clear() { searchField.text = ""; }
  Connections { target: bar.win; function onQueryChanged() { if (searchField.text !== bar.win.query) searchField.text = bar.win.query; } }

  Rectangle { anchors.fill: parent; color: Zenon.headBg }
  Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Zenon.border }

  Rectangle {
    id: box
    anchors.left: parent.left
    anchors.right: newBtn.left
    anchors.rightMargin: 8
    anchors.leftMargin: 12
    anchors.verticalCenter: parent.verticalCenter
    height: 34
    radius: Zenon.windowRadius
    color: Zenon.wash(0.06)
    border.width: 1
    border.color: Zenon.border
    Text {
      id: lens
      anchors.left: parent.left
      anchors.leftMargin: 12
      anchors.verticalCenter: parent.verticalCenter
      text: ""
      color: Zenon.accentMuted
      font.family: Zenon.glyphFace
      font.pixelSize: Zenon.px(13)
    }
    TextInput {
      id: searchField
      cursorDelegate: Caret { field: searchField }
      anchors.left: lens.right
      anchors.leftMargin: 9
      anchors.right: clearChip.visible ? clearChip.left : parent.right
      anchors.rightMargin: clearChip.visible ? 8 : 12
      anchors.verticalCenter: parent.verticalCenter
      clip: true
      color: Zenon.ink
      selectionColor: Zenon.alpha(Zenon.cyan, 0.4)
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(15)
      onTextChanged: if (bar.win && bar.win.query !== text) { bar.win.query = text; bar.win.wantTop = true; }
      Keys.onPressed: (e) => {
        if (e.key === Qt.Key_Escape) {
          if (searchField.text !== "") searchField.text = "";
          else bar.win.refocus();
          e.accepted = true;
          return;
        }
        if (e.key === Qt.Key_Down || e.key === Qt.Key_Up) { bar.win.move(e.key === Qt.Key_Down ? 1 : -1); e.accepted = true; return; }
        if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { bar.win.paneRef.focusEditor(false); e.accepted = true; }
      }
      Text {
        visible: searchField.text === ""
        anchors.verticalCenter: parent.verticalCenter
        text: !bar.win ? "" : bar.win.inJournal ? "Search entries" : bar.win.onDesktop ? "Search stickies" : "Search notes"
        color: Zenon.accentMuted
        font: searchField.font
      }
    }
    ClearChip {
      id: clearChip
      size: Zenon.px(15)
      shown: searchField.text !== ""
      anchors.right: parent.right
      anchors.rightMargin: 9
      anchors.verticalCenter: parent.verticalCenter
      onClicked: { searchField.text = ""; searchField.forceActiveFocus(); }
    }
    HeldRing { anchors.fill: parent; radius: parent.radius; z: 10; on: searchField.activeFocus }
  }

  // a new note (or entry, or sticky) where you are
  DialogButton {
    id: newBtn
    anchors.right: parent.right
    anchors.rightMargin: 12
    anchors.verticalCenter: parent.verticalCenter
    glyph: true
    label: ""
    ink: Zenon.sand
    onClicked: bar.win.inJournal ? bar.win.newEntry() : bar.win.newNote()
    // a right click: from a template
    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.RightButton
      onClicked: (m) => { if (bar.win.onDesktop) return; const p = mapToItem(bar.win.stageItem, m.x, m.y); bar.win.templateMenu(p.x, p.y); }
    }
    HoverHandler {
      onHoveredChanged: hovered
        ? bar.win.tipsItem.show(newBtn, bar.win.inJournal ? "New entry" : bar.win.onDesktop ? "New sticky" : "New note", bar.win.inJournal ? "ctrl j" : "ctrl n")
        : bar.win.tipsItem.hide(newBtn)
    }
  }

  // the tokens, offered while the search is empty and has the keys
  Rectangle {
    visible: searchField.activeFocus && searchField.text === "" && !bar.win.onDesktop
    z: 20
    anchors.top: box.bottom
    anchors.topMargin: 6
    anchors.left: box.left
    width: box.width + 44
    height: tokens.implicitHeight + 20
    radius: Zenon.windowRadius
    color: Zenon.tipBg
    border.width: 1
    border.color: Zenon.border
    Flow {
      id: tokens
      x: 10
      y: 10
      width: parent.width - 20
      spacing: 6
      Repeater {
        model: bar.win && bar.win.inJournal
          ? ["is:bookmarked", "has:photo", "has:mood", "has:checklist"]
          : ["is:pinned", "is:todo", "is:done", "is:locked", "has:checklist", "has:picture", "has:file", "has:table", "has:sketch", "has:link"]
        delegate: Rectangle {
          required property string modelData
          width: tk.implicitWidth + 16
          height: 24
          radius: Zenon.windowRadius
          color: Zenon.wash(0.06)
          border.width: 1
          border.color: Zenon.border
          Text {
            id: tk
            anchors.centerIn: parent
            text: modelData
            color: Zenon.accentSoft
            font.family: Zenon.face
            font.weight: Zenon.weight
            font.pixelSize: Zenon.px(12)
          }
          MouseArea {
            anchors.fill: parent
            onPressed: (m) => { m.accepted = true; searchField.text = modelData + " "; searchField.forceActiveFocus(); searchField.cursorPosition = searchField.text.length; }
          }
        }
      }
    }
  }
}
