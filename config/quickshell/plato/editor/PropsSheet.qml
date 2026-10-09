// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// PROPERTIES of a file or directory in plato's tree: terminus' own card
// (terminus/PropsCard.qml — path, owner, exact size, what opens it, sha256,
// permissions behind their row) on a plato sheet, answered by the shared
// plain host (terminus/PropsHost.qml). Opened from the tree's menu or with
// alt+return on a row.
//
//     PropsSheet { id: props; onSaid: (t) => toasts.take({ text: t }) }
//     props.showPath("/abs/path")
//
// Its keys while up: the card's own (tab to the permissions page, the grid
// there), Escape backs out of the permissions page, then closes.

import QtQuick
import "../../morpheus"
import "../../terminus" as Term

PlatoSheet {
  id: sheet

  signal closed()
  signal said(string text)
  // the card's "open with" list, for the holder's menu (CardPopup rows)
  signal menuWanted(Item item, var rows)

  modal: true
  cardW: card.wantW
  cardH: card.implicitHeight + 8
  hints: card.tab === 1 ? [["space", "flip"], ["return", "apply"], ["esc", "back"]]
    : [["tab", "permissions"], ["s", "sha256"], ["esc", "close"]]
  onDismissed: sheet.close()

  function showPath(path) {
    if (!path) return;
    card.tab = 0;
    card.askPath(path);
  }
  function takeKeys() { keys.forceActiveFocus(); }
  function close() {
    if (!sheet.shown) return;
    sheet.shown = false;
    sheet.closed();
  }

  Term.PropsHost {
    id: host
    onSaid: (t) => sheet.said(t)
  }

  Item {
    id: keys
    anchors.fill: parent
    focus: sheet.shown
    Keys.onPressed: (e) => {
      e.accepted = true;
      if (e.key === Qt.Key_Escape && card.tab !== 1) { sheet.close(); return; }
      if (!card.handleKey(e.key)) e.accepted = false;
    }

    Term.PropsCard {
      id: card
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.topMargin: 8
      host: host
      onOpened: { sheet.shown = true; keys.forceActiveFocus(); }
      onClosed: sheet.close()
      onMenuWanted: (item, rows) => sheet.menuWanted(item, rows)
    }
  }
}
