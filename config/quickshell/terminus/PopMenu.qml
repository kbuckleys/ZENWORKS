// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A RIGHT-CLICK MENU INSIDE A WINDOW — morpheus' CardPopup (the card every
// menu is), with what a window needs around it: a shield over the window so
// the click that puts it away is not also a click on what is under it, and
// Esc. The card is its own surface and never has the keyboard, so keys are
// caught here while it is up; any key closes it.
//
//     PopMenu { id: menu; anchors.fill: parent; window: win
//               onClosed: list.forceActiveFocus() }
//     menu.open(x, y, [ { text, icon, mark, enabled, danger, run },
//                       { isSeparator: true }, … ])
//
// x, y are in this item's coordinates. `mark` is the key that does the same
// (drawn on the right, so the menu teaches it); `run` is called after the
// card has gone. `held` is whatever the holder says the menu is about,
// until it closes — for a HeldRing on that row.
//
// Out of plato's editor menu (plato/editor/ContextMenu.qml, 2026-10-10),
// when delphi's lists wanted the same; plato's menu is now its items and
// this.

import QtQuick
import Quickshell
import "../morpheus"

Item {
  id: menu
  property var window: null
  property int cardWidth: 240
  property var items: []
  property var held: null
  readonly property bool isOpen: card.open
  // the menu went away, chosen from or not: the keyboard goes back
  signal closed()

  function open(x, y, items, held) {
    menu.items = items || [];
    menu.held = held === undefined ? null : held;
    card.at = menu.mapToItem(null, x, y);
    card.open = true;
    catcher.forceActiveFocus();
  }
  function close() {
    if (!card.open) return;
    card.open = false;
    menu.held = null;
    menu.closed();
  }

  InputShield {
    parent: menu.window ? menu.window.contentItem : menu
    anchors.fill: parent
    visible: card.open
    z: 1000
    onClicked: menu.close()
  }
  Item {
    id: catcher
    Keys.onPressed: (event) => {
      event.accepted = true;
      menu.close();
    }
  }

  CardPopup {
    id: card
    window: menu.window
    fit: true
    cardWidth: menu.cardWidth
    model: menu.items.map((it) => it.isSeparator ? { isSeparator: true }
      : { text: it.text, icon: it.icon, hint: it.mark || "", enabled: it.enabled !== false,
          danger: !!it.danger })
    onChosen: (i) => {
      const it = menu.items[i];
      menu.close();
      if (it && it.run && it.enabled !== false) it.run();
    }
  }
}
