// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// The completion menu: nvim's popup menu, drawn by plato.
//
// NVIM STILL DRIVES IT. What is in it (mini.completion, from the language
// server or the buffer's words), which item is selected (<C-n>, <C-p>), and
// the filtering as you type all happen in nvim; this only draws the list it
// is sent and says which one was clicked. The keys never come here — they go
// to nvim like every other key.
//
// Under the word being completed, or above it when there is no room below.

import QtQuick
import "../../morpheus"

Item {
  id: menu

  required property var ed
  required property var client
  required property real cellW
  required property real cellH
  required property font face
  required property real originX
  required property real areaW
  required property real areaH

  readonly property int pad: 4
  readonly property int maxRows: 12
  readonly property var items: menu.ed.pumItems
  readonly property int shownRows: Math.min(menu.maxRows, menu.items.length)

  // columns: the word, then its kind and source, dimmed
  readonly property int wordCols: {
    let w = 8;
    for (let i = 0; i < menu.items.length; ++i)
      w = Math.max(w, String(menu.items[i].word).length);
    return Math.min(w, 48);
  }
  readonly property int kindCols: {
    let w = 0;
    for (let i = 0; i < menu.items.length; ++i) {
      const k = String(menu.items[i].kind || "") + (menu.items[i].menu ? " " + menu.items[i].menu : "");
      w = Math.max(w, k.length);
    }
    return Math.min(w, 24);
  }

  // the command line's completions are the status bar's to draw
  visible: menu.up && !menu.ed.pumCmdline && menu.items.length > 0
  // NOT GONE BETWEEN TWO KEYS. As you type, nvim closes the menu and opens
  // it again with the narrower list — a blink on every letter. A close is
  // only drawn once nothing reopens it straight away.
  property bool up: false
  Connections {
    target: menu.ed
    function onPumShownChanged() {
      if (menu.ed.pumShown) { hideSoon.stop(); menu.up = true; }
      else hideSoon.restart();
    }
  }
  Timer { id: hideSoon; interval: 60; onTriggered: menu.up = false }
  z: 200
  width: (menu.wordCols + (menu.kindCols > 0 ? menu.kindCols + 2 : 0) + 2) * menu.cellW
  height: menu.shownRows * menu.cellH + menu.pad * 2

  readonly property bool below: (menu.ed.pumRow + 1) * menu.cellH + menu.height <= menu.areaH
  x: Math.max(0, Math.min(menu.areaW - menu.width,
    menu.originX + menu.ed.pumCol * menu.cellW - menu.cellW))
  y: menu.below ? (menu.ed.pumRow + 1) * menu.cellH : menu.ed.pumRow * menu.cellH - menu.height

  // ── a path's file, beside the menu ──────────────────────────────────
  // Paths are offered as they are typed (paths.lua), each with its file; the
  // selected one — or, before any is, the first — is shown in a card beside
  // the menu, on whichever side has the room.
  readonly property var shownItem: menu.ed.pumSelected >= 0
    ? menu.items[menu.ed.pumSelected] : menu.items[0]
  PathCard {
    id: pathCard
    file: menu.shownItem && menu.shownItem.path ? menu.shownItem.path : ""
    codeFamily: menu.face.family
    codeWeight: menu.face.weight
    pixelSize: Math.max(11, menu.face.pixelSize - 2)
    maxW: Math.min(620, Math.max(280, menu.areaW * 0.45))
    maxH: Math.min(420, Math.max(160, menu.areaH * 0.6))
    readonly property bool fitsRight: menu.x + menu.width + 6 + pathCard.width <= menu.areaW
    x: pathCard.fitsRight ? menu.width + 6 : -pathCard.width - 6
    y: menu.below ? 0 : menu.height - pathCard.height
  }

  Rectangle {
    anchors.fill: parent
    radius: Zenon.windowRadius
    color: Zenon.alpha(Zenon.card, 0.97)
    // the hairline at full strength: zenon's 0.3 border was lost against
    // the text it floats over, and the card read as part of the page
    border.width: 1
    border.color: Qt.rgba(Zenon.border.r, Zenon.border.g, Zenon.border.b, 0.9)
  }

  ListView {
    id: list
    // the shell's one scroll (morpheus Elastic), a few items a notch
    ElasticScroll { view: list; step: list.height / 3 }
    x: 0
    y: menu.pad
    width: menu.width
    height: menu.shownRows * menu.cellH
    clip: true
    model: menu.items
    currentIndex: menu.ed.pumSelected
    boundsBehavior: Flickable.StopAtBounds
    // keep the selected item in view as <C-n> walks past the edge
    onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)

    delegate: Item {
      id: item
      required property var modelData
      required property int index
      readonly property bool chosen: item.index === menu.ed.pumSelected
      width: list.width
      height: menu.cellH

      Rectangle {
        anchors.fill: parent
        anchors.leftMargin: 2
        anchors.rightMargin: 2
        radius: 3
        visible: item.chosen
        color: Qt.rgba(Zenon.green.r, Zenon.green.g, Zenon.green.b, 0.22)
      }
      Text {
        x: menu.cellW
        width: menu.wordCols * menu.cellW
        height: menu.cellH
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        textFormat: Text.PlainText
        font: menu.face
        color: item.chosen ? Zenon.green : menu.ed.normalFg
        text: item.modelData.word
      }
      Text {
        visible: menu.kindCols > 0
        x: (menu.wordCols + 2) * menu.cellW
        width: menu.kindCols * menu.cellW
        height: menu.cellH
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        textFormat: Text.PlainText
        font: menu.face
        color: Zenon.muted
        text: String(item.modelData.kind || "")
          + (item.modelData.menu ? " " + item.modelData.menu : "")
      }
      MouseArea {
        anchors.fill: parent
        onClicked: menu.client.pumPick(item.index)
      }
    }
  }
}
