// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A BUBBLE — a small speech-bubble card hanging from something in a window,
// its tail pointing up at it: for more than a tooltip's line (a list, a
// progress, a few facts) while the pointer is on the thing it is about.
// Delphi's upload indicator was the first (each file and where it has got
// to); the user wants it used more widely (2026-10-10).
//
//     Bubble { window: win; target: pill; shown: pillHover.hovered
//              width: 420
//              Text { … }  UploadRows { … } }      // stacked, 10 apart
//
// Its own popup surface, placed against the target as morpheus/WindowTip
// places a tooltip — so the compositor frosts it, and it may hang past the
// window's edge, sliding along it rather than being cut — in the tooltip's
// own ground (Zenon.tipBg), border and glass rim. It fades in with a small
// drop, as a card does.
//
// The card and its tail are ONE outline (a Canvas path), filled and drawn
// once: a tail laid over a bordered card left the card's border running
// across the tail's root (user, 2026-10-11).
//
// `sticky`: the pointer may go from the target onto the bubble and stay —
// it holds the bubble up (after a moment's grace to cross the gap), so what
// is in it can be scrolled. Without, it goes as the pointer leaves the
// target. `over` says the pointer is on it.

import QtQuick
import Quickshell
import "../morpheus"

PopupWindow {
  id: bub
  property var window: null
  property Item target: null
  property bool shown: false
  // the card's width; its height is what is in it
  property real cardWidth: 380
  default property alias content: col.data

  readonly property int tail: 8
  readonly property int pad: 6
  property bool sticky: false
  readonly property bool over: overCard.hovered
  readonly property bool open: bub.shown || (bub.sticky && (overCard.hovered || grace.running))
  Timer { id: grace; interval: 350 }
  property real shade: bub.open ? 1 : 0
  Behavior on shade { NumberAnimation { duration: Zenon.menuFade; easing.type: Easing.OutCubic } }

  visible: bub.window !== null && bub.target !== null && bub.shade > 0.01
  color: "transparent"
  implicitWidth: card.width + bub.pad * 2
  implicitHeight: card.height + bub.tail + bub.pad * 2

  // where the target is, read as it is shown (a binding around mapToItem
  // does not re-run when the geometry under it moves), and again when it
  // is handed another target while up — a list's rows, one after another
  property rect at: Qt.rect(0, 0, 1, 1)
  function measure() {
    if (!bub.shown || !bub.target) return;
    const p = bub.target.mapToItem(null, 0, 0);
    bub.at = Qt.rect(p.x, p.y, bub.target.width, bub.target.height);
  }
  onShownChanged: {
    if (!bub.shown && bub.sticky) grace.restart();
    bub.measure();
  }
  onTargetChanged: bub.measure()
  anchor {
    window: bub.window
    rect.x: Math.round(bub.at.x)
    rect.y: Math.round(bub.at.y)
    rect.width: Math.max(1, Math.round(bub.at.width))
    rect.height: Math.max(1, Math.round(bub.at.height))
    edges: Edges.Bottom
    gravity: Edges.Bottom
    adjustment: PopupAdjustment.Slide
  }

  Item {
    anchors.fill: parent
    opacity: bub.shade
    transform: Translate { y: (1 - bub.shade) * -4 }

    // where the tail's point is: under the target's middle when the card
    // lets it be
    readonly property real tailX: Math.max(card.x + 14 + bub.tail,
      Math.min(card.x + card.width - 14 - bub.tail, bub.width / 2))
    // the outline: card and tail as one path, filled, then drawn once
    Canvas {
      id: outline
      anchors.fill: parent
      onWidthChanged: requestPaint()
      onHeightChanged: requestPaint()
      Connections { target: Zenon; function onThemeEpochChanged() { outline.requestPaint(); } }
      Connections { target: card; function onHeightChanged() { outline.requestPaint(); } function onWidthChanged() { outline.requestPaint(); } }
      Connections { target: outline.parent; function onTailXChanged() { outline.requestPaint(); } }
      onPaint: {
        const c = getContext("2d");
        c.reset();
        const x = card.x + 0.5, y = card.y + 0.5, w = card.width - 1, h = card.height - 1;
        const r = Math.min(card.radius, h / 2), t = bub.tail, tx = Math.round(outline.parent.tailX) + 0.5;
        c.beginPath();
        c.moveTo(x + r, y);
        c.lineTo(tx - t, y);
        c.lineTo(tx, y - t);
        c.lineTo(tx + t, y);
        c.lineTo(x + w - r, y);
        c.arcTo(x + w, y, x + w, y + r, r);
        c.lineTo(x + w, y + h - r);
        c.arcTo(x + w, y + h, x + w - r, y + h, r);
        c.lineTo(x + r, y + h);
        c.arcTo(x, y + h, x, y + h - r, r);
        c.lineTo(x, y + r);
        c.arcTo(x, y, x + r, y, r);
        c.closePath();
        c.fillStyle = Zenon.tipBg;
        c.fill();
        c.lineWidth = 1;
        c.strokeStyle = Zenon.border;
        c.stroke();
        // the glass rim, as the tooltips have it (see Zenon.rim): a light
        // along the top, faded at its ends, broken where the tail rises
        if (Zenon.rimOn) {
          const y1 = y + 1, a = x + r, b = x + w - r;
          const g = c.createLinearGradient(a, 0, b, 0);
          g.addColorStop(0, Zenon.alpha(Zenon.rim, 0));
          g.addColorStop(0.25, Zenon.rim);
          g.addColorStop(0.75, Zenon.rim);
          g.addColorStop(1, Zenon.alpha(Zenon.rim, 0));
          c.strokeStyle = g;
          c.beginPath();
          c.moveTo(a, y1); c.lineTo(Math.max(a, tx - t - 2), y1);
          c.moveTo(Math.min(b, tx + t + 2), y1); c.lineTo(b, y1);
          c.stroke();
        }
      }
    }
    Item {
      id: card
      x: bub.pad
      y: bub.pad + bub.tail
      width: bub.cardWidth
      height: col.implicitHeight + 24
      readonly property real radius: Zenon.windowRadius
      // the pointer on it holds a sticky bubble up
      HoverHandler { id: overCard; enabled: bub.sticky }
      Column {
        id: col
        x: 14
        y: 12
        width: card.width - 28
        spacing: 10
      }
    }
  }
}
