// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A TOOLTIP FOR A WINDOW. Tooltip rides a layer surface, placed in screen
// coordinates, and says plainly that inside an ordinary window it cannot —
// a wayland client is never told where its window is. An xdg-popup can be
// placed by a point inside its own window, which is what CardPopup does for
// menus and what this does for a label: hung under the button it names,
// flipped above it by the compositor when there is no room below.
//
// ONE PER WINDOW, shared by every button in it — the buttons say what they
// are when the pointer arrives and let go when it leaves:
//
//     WindowTip { id: tip; window: myWindow }
//     MouseArea {
//       hoverEnabled: true
//       onContainsMouseChanged: containsMouse ? tip.show(button, "Crop", "c")
//                                             : tip.hide(button)
//     }
//
// A short wait before the first one, none between neighbors: running the
// pointer along a toolbar reads each name as it passes, as it does anywhere.
// Wears Tooltip's card, smaller, as a window's labels are (terminus/TipCard).

import QtQuick
import Quickshell
import "."
import "../terminus" as Term

PopupWindow {
  id: tip

  // the window the buttons are in
  property var window: null

  property Item target: null
  property string text: ""
  // the key that does the same thing, shown after the name, dimmer
  property string key: ""

  property bool wanted: false

  function show(item, text, key) {
    tip.target = item;
    tip.text = text;
    tip.key = key || "";
    const p = item.mapToItem(null, 0, 0);
    tip.at = Qt.rect(p.x, p.y, item.width, item.height);
    // already up for a neighbor: straight across, no second wait
    if (tip.shade > 0.5) { wait.stop(); tip.wanted = true; }
    else wait.restart();
  }
  function hide(item) {
    if (item && item !== tip.target) return;
    wait.stop();
    tip.wanted = false;
  }

  property rect at: Qt.rect(0, 0, 1, 1)

  Timer { id: wait; interval: Zenon.hoverWait; onTriggered: tip.wanted = true }

  property real shade: tip.wanted ? 1 : 0
  Behavior on shade { NumberAnimation { duration: Zenon.menuFade; easing.type: Easing.OutCubic } }

  // the gap between the button and the card, carried inside the surface so
  // the card never touches what it names
  readonly property int gap: 6

  // away while the window switcher is up (Zenon.tipsAway says why)
  visible: tip.window !== null && tip.target !== null && tip.shade > 0.01 && !Zenon.tipsAway
  color: "transparent"
  implicitWidth: card.width
  implicitHeight: card.height + tip.gap * 2

  anchor {
    window: tip.window
    rect.x: Math.round(tip.at.x)
    rect.y: Math.round(tip.at.y)
    rect.width: Math.max(1, Math.round(tip.at.width))
    rect.height: Math.max(1, Math.round(tip.at.height))
    edges: Edges.Bottom
    gravity: Edges.Bottom
    adjustment: PopupAdjustment.Flip | PopupAdjustment.Slide
  }

  Term.TipCard {
    id: card
    y: tip.gap
    opacity: tip.shade
    text: Strings.escapeHtml(tip.text)
      + (tip.key !== "" ? "&#160;&#160;<font color=\"" + Zenon.hex(Zenon.muted) + "\">"
         + Strings.escapeHtml(tip.key) + "</font>" : "")
  }
}
