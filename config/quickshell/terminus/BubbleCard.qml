// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A BUBBLE'S CARD — the speech bubble itself, wherever it is hung: its card,
// its tail, its shadow, what is in it. terminus/Bubble hangs it in a popup
// surface of its own beside a shell window; iris, which is not quickshell,
// lays it over its page. Plain Qt Quick, so both can.
//
// In the tooltip's own ground (Zenon.tipBg), border and glass rim. It fades
// in with a small drop (`shade`, 0 → 1), as a card does.
//
// The card and its tail are ONE outline (a Canvas path), filled and drawn
// once: a tail laid over a bordered card left the card's border running
// across the tail's root (user, 2026-10-11).
//
// It casts a menu's shadow (MenuShadow's lamp, sized to fit the room left
// around the card), hollow like MenuShadow's — cut to the card AND
// its tail, so the translucent glass is not darkened from under it (user,
// 2026-10-11: shadow and frost, as the menus have).
//
// Its size is the card plus the room for that shadow (`pad`, `padTop` and
// the tail); `card` is where the card itself sits, for a pointer mask.
// `aim` is the x the tail points at — the holder's to keep (Bubble aims it
// at the pointer); it is held inside the card's straight top edge.

import QtQuick
import QtQuick.Effects
import "../morpheus"

Item {
  id: face
  property real shade: 0
  // the card's width; its height is what is in it
  property real cardWidth: 380
  // the pointer on the card says so (`over`) — only while sticky
  property bool sticky: false
  readonly property bool over: overCard.hovered
  // where the tail's point is, in this item's x
  property real aim: face.width / 2
  default property alias content: col.data
  readonly property Item card: card

  readonly property int tail: 8
  // the room around the card for its shadow, at the sides and below; above
  // it, only the 6 it always had. The anchor rect is the target's own and
  // never moved: raised to make room above, it went past the window's top
  // for anything in a head bar, and the bubble never came (2026-10-11)
  readonly property int pad: 36
  readonly property int padTop: 6
  // the shadow, cut to that room: it reaches spread + blur - drop = 14 above
  // the card (padTop + tail), 24 to the sides, 34 below — inside the pad
  readonly property int castSpread: 6
  readonly property int castBlur: 18
  readonly property int castDrop: 10

  implicitWidth: card.width + face.pad * 2
  implicitHeight: face.padTop + face.tail + card.height + face.pad
  opacity: face.shade
  transform: Translate { y: (1 - face.shade) * -4 }

  readonly property real tailX: Math.max(card.x + 14 + face.tail,
    Math.min(card.x + card.width - 14 - face.tail, face.aim))
  // card and tail as one path, traced into a 2d context (the outline's
  // and the shadow's hole share it)
  function trace(c) {
    const x = card.x + 0.5, y = card.y + 0.5, w = card.width - 1, h = card.height - 1;
    const r = Math.min(card.radius, h / 2), t = face.tail, tx = Math.round(face.tailX) + 0.5;
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
  }
  function repaint() { outline.requestPaint(); hole.requestPaint(); }
  onTailXChanged: face.repaint()
  onWidthChanged: face.repaint()
  onHeightChanged: face.repaint()
  Connections { target: Zenon; function onThemeEpochChanged() { face.repaint(); } }
  Connections { target: card; function onHeightChanged() { face.repaint(); } function onWidthChanged() { face.repaint(); } }

  // the shadow, as MenuShadow casts it, with the outline punched out
  Item {
    anchors.fill: parent
    layer.enabled: true
    layer.effect: MultiEffect {
      maskEnabled: true
      maskSource: hole
      maskInverted: true
      maskThresholdMin: 0.5
    }
    RectangularShadow {
      x: card.x
      y: card.y
      width: card.width
      height: card.height
      radius: card.radius
      blur: face.castBlur
      spread: face.castSpread
      offset: Qt.vector2d(0, face.castDrop)
      color: Zenon.menuShadowInk
    }
  }
  // the outline's footprint, never drawn: the texture the mask reads
  Canvas {
    id: hole
    anchors.fill: parent
    visible: false
    layer.enabled: true
    onPaint: {
      const c = getContext("2d");
      c.reset();
      face.trace(c);
      c.fillStyle = "white";
      c.fill();
    }
  }
  // the outline: card and tail as one path, filled, then drawn once
  Canvas {
    id: outline
    anchors.fill: parent
    onPaint: {
      const c = getContext("2d");
      c.reset();
      const x = card.x + 0.5, y = card.y + 0.5, w = card.width - 1;
      const r = Math.min(card.radius, (card.height - 1) / 2), t = face.tail, tx = Math.round(face.tailX) + 0.5;
      face.trace(c);
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
    x: face.pad
    y: face.padTop + face.tail
    width: face.cardWidth
    height: col.implicitHeight + 24
    readonly property real radius: Zenon.windowRadius
    // the pointer on it holds a sticky bubble up
    HoverHandler { id: overCard; enabled: face.sticky }
    Column {
      id: col
      x: 14
      y: 12
      width: card.width - 28
      spacing: 10
    }
  }
}
