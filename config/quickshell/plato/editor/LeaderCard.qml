// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// The leader menu: <Space> in normal mode, and what can follow it.
//
// What which-key was in the terminal, drawn as a card instead of a split: the
// keys that can come next, each with what it does, and groups (+) that open
// onto keys of their own. Typing a key takes it; Backspace goes back up a
// group; Esc, or a key with nothing behind it, closes the card.
//
// The entries are actions.js's — the same list the command palette searches —
// and the keycaps are morpheus' KeyCap, as on every other key hint in the
// shell. It is a terminus sheet (PlatoSheet), RISING FROM THE STATUS BAR —
// down by the keys being typed, as the key hints for g, z and the rest do,
// which wear the same card: the keys in two columns of terminus' rows, every
// one in the same white (a group says so with its +), the path typed so far
// in its footer.

import QtQuick
import "../../morpheus"
import "actions.js" as Actions

PlatoSheet {
  id: card

  required property font face
  property var ctx: null

  signal closed()

  property string prefix: ""
  readonly property var entries: card.shown ? Actions.next(card.prefix) : []

  onDismissed: card.close()

  function open() {
    card.prefix = "";
    card.shown = true;
    keys.forceActiveFocus();
  }
  function close() {
    card.shown = false;
    card.closed();
  }

  // three across, fewer in a narrow window
  readonly property real colW: 290
  readonly property int columns: card.fitColumns(3, card.colW)
  readonly property int rows: Math.max(1, Math.ceil(card.entries.length / card.columns))
  cardW: card.columns * card.colW + 20
  cardH: 12 + card.rows * card.rowH
  foot: false

  Grid {
    x: 10
    y: 6
    columns: card.columns
    flow: Grid.TopToBottom
    rows: card.rows
    Repeater {
      model: card.entries
      Item {
        id: entry
        required property var modelData
        width: card.colW
        height: card.rowH
        KeyCap {
          id: cap
          x: 8
          anchors.verticalCenter: parent.verticalCenter
          label: entry.modelData.key === " " ? "space" : entry.modelData.key
          fontSize: 12
        }
        Text {
          anchors.left: cap.right
          anchors.leftMargin: 12
          anchors.right: parent.right
          anchors.rightMargin: 8
          anchors.verticalCenter: parent.verticalCenter
          elide: Text.ElideRight
          textFormat: Text.PlainText
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: 16
          color: Zenon.white
          text: (entry.modelData.group ? "+" : "") + entry.modelData.title
        }
        MouseArea {
          anchors.fill: parent
          onClicked: card.take(entry.modelData)
        }
      }
    }
  }

  function take(e) {
    if (e.group) { card.prefix += e.key; return; }
    card.close();
    e.action.run(card.ctx);
  }

  Item {
    id: keys
    focus: card.shown
    Keys.onPressed: (event) => {
      event.accepted = true;
      if (event.key === Qt.Key_Escape) { card.close(); return; }
      if (event.key === Qt.Key_Backspace) {
        if (card.prefix === "") card.close();
        else card.prefix = card.prefix.slice(0, -1);
        return;
      }
      // modifiers alone say nothing yet
      if (event.text === "") return;
      const hit = card.entries.filter((e) => e.key === event.text)[0];
      if (hit) card.take(hit);
      else card.close();
    }
  }
}
