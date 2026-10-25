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
// window's edge, sliding along it rather than being cut. What is drawn —
// card, tail, shadow, rim — is terminus/BubbleCard; this file
// is where the card hangs and where its tail points.
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
  // the card's widest — it fits what is in it, up to this (BubbleCard's
  // `fit`); `fit: false` holds it at this width. Its height is what is in it
  property real cardWidth: 380
  property bool fit: true
  default property alias content: face.content

  // the card's measures (BubbleCard says why they are what they are)
  readonly property int tail: face.tail
  readonly property int pad: face.pad
  readonly property int padTop: face.padTop
  // standing up, room for the shadow under the tail as well (BubbleCard);
  // the anchor goes down by that room, so the tail's point does not move
  property bool roomBelow: false
  readonly property real drop: bub.up && bub.roomBelow ? face.pad - face.padTop : 0
  property bool sticky: false
  // ── A CLICK OFF IT ────────────────────────────────────────────────────
  // `dismissable`: while it is up, a press anywhere else in its window says
  // `dismissed` (and goes no further) — for a bubble opened by a click,
  // which the holder shuts. A catcher laid over the window's content.
  property bool dismissable: false
  signal dismissed()
  property var _catch: null
  readonly property bool catching: bub.dismissable && bub.shown && bub.window !== null
  onCatchingChanged: {
    if (bub._catch) { bub._catch.destroy(); bub._catch = null; }
    if (!bub.catching || !bub.window.contentItem) return;
    // (its own `hit`: a MouseArea's `pressed` is a property as well as a
    // signal, and the property is what a connect finds)
    bub._catch = Qt.createQmlObject('import QtQuick; MouseArea { signal hit(); anchors.fill: parent; z: 1e9; acceptedButtons: Qt.AllButtons; onPressed: hit() }',
                                    bub.window.contentItem);
    bub._catch.hit.connect(() => bub.dismissed());
  }
  // standing on the target, tail down, instead of hanging under it — for a
  // target at the bottom of the screen (the bar's jobs). See BubbleCard.up.
  property bool up: false
  readonly property bool over: face.over
  // (a dismissable bubble was opened by a click and goes on one, at once:
  // the grace and the hover hold are for bubbles that come on a hover)
  // ── ONLY WHEN WHAT IS IN IT IS IN (user, 2026-10-14) ───────────────────
  // A bubble that opened and then grew as its content arrived — a rate
  // fetched, a row read — looked like it was still being built. `ready`
  // is the holder saying it is all there (true unless it says otherwise);
  // until then `shown` waits, up to `readyWait` ms, after which it opens
  // with what it has rather than not at all. And it is fitted to that
  // content before the first frame, not a tick after: `armed`.
  property bool ready: true
  property int readyWait: 700
  property bool armed: false
  Timer {
    id: readyGive
    interval: bub.readyWait
    onTriggered: bub.arm()
  }
  function arm() {
    if (!bub.shown) { bub.armed = false; return; }
    face.refit();
    if (!bub.armed) settle.restart();
  }
  // FITTED A FRAME LATER, THEN OPENED (user's bubble.mp4, 2026-10-17): a
  // fit taken in the same tick as `shown` could read the words before they
  // were laid out — calypso's cards opened at the card's narrowest (120),
  // text cut, and jumped to their width a refit later. One frame on, the
  // words are in; the fit is taken again and only then does it open.
  Timer {
    id: settle
    interval: 16
    onTriggered: { if (!bub.shown) return; face.refit(); bub.armed = true; }
  }
  function rearm() {
    if (!bub.shown) { readyGive.stop(); bub.armed = false; return; }
    if (bub.ready) { readyGive.stop(); bub.arm(); }
    else if (!bub.armed && !readyGive.running) readyGive.restart();
  }
  onReadyChanged: bub.rearm()
  readonly property bool open: bub.armed || (bub.sticky && !bub.dismissable && (face.over || grace.running))
  Timer { id: grace; interval: 350 }
  property real shade: bub.open ? 1 : 0
  Behavior on shade { NumberAnimation { duration: Zenon.menuFade; easing.type: Easing.OutCubic } }

  // away while the window switcher is up (Zenon.tipsAway says why)
  visible: bub.window !== null && bub.target !== null && (bub.shade > 0.01 || face.grow > 0.01)
    && !Zenon.tipsAway
  color: "transparent"
  // only the card (and its tail) takes the pointer, never the shadow's room
  mask: Region { x: face.card.x; y: bub.up ? face.card.y : face.card.y - bub.tail
                 width: face.card.width; height: face.card.height + bub.tail }
  implicitWidth: face.implicitWidth
  implicitHeight: face.implicitHeight

  // where the target is, read as it is shown (a binding around mapToItem
  // does not re-run when the geometry under it moves), and again when it
  // is handed another target while up — a list's rows, one after another
  property rect at: Qt.rect(0, 0, 1, 1)
  // THE TAIL POINTS AT THE POINTER (user, 2026-10-11: it sat in the middle
  // of a wide row whatever part of it was hovered). The bubble opens under
  // the pointer — the anchor narrowed to its x on the target — and then
  // only the tail moves, along the card, as the pointer goes along the
  // target: the popup itself is never moved under the hand.
  // `pointX`: the pointer's x in the window (-1 off it), from a passive
  // HoverHandler put on the window's content (it sees every move, whatever
  // takes the hover underneath).
  property real pointX: -1
  property var _hover: null
  function watch() {
    if (bub._hover) { bub._hover.destroy(); bub._hover = null; }
    const root = bub.window ? bub.window.contentItem : null;
    if (!root) return;
    bub._hover = Qt.createQmlObject("import QtQuick; HoverHandler {}", root, "BubbleHover");
    bub._hover.pointChanged.connect(() => {
      bub.pointX = bub._hover.hovered ? bub._hover.point.position.x : -1;
    });
  }
  onWindowChanged: bub.watch()
  Component.onCompleted: bub.watch()
  Component.onDestruction: { if (bub._hover) bub._hover.destroy(); if (bub._catch) bub._catch.destroy(); }
  // `lean`: the card grows to the RIGHT of the target instead of centering
  // under it — for a target at a window's left edge (plato's gutter bars),
  // where a centered card hung out past the window and was slid back by the
  // compositor, its tail left pointing at nothing
  property bool lean: false
  // where the target's middle was (window x) when the bubble was placed
  property real homeX: 0
  function measure() {
    if (!bub.shown || !bub.target) return;
    const p = bub.target.mapToItem(null, 0, 0);
    const w = bub.target.width;
    const follow = bub.pointX >= p.x && bub.pointX <= p.x + w && w > 40;
    bub.homeX = follow ? bub.pointX : p.x + w / 2;
    if (bub.lean)
      bub.at = Qt.rect(Math.max(0, bub.homeX - (bub.pad + 14 + bub.tail)), p.y, 1, bub.target.height);
    else if (follow)
      bub.at = Qt.rect(bub.pointX, p.y, 1, bub.target.height);
    else
      bub.at = Qt.rect(p.x, p.y, w, bub.target.height);
  }
  // the popup's left edge, in the window (a slide at the screen's edge is
  // not known here)
  readonly property real popupX: bub.lean ? bub.at.x : bub.at.x + bub.at.width / 2 - bub.width / 2
  // the pointer's x in the popup while it is on a wide target, else -1
  readonly property real pointIn: {
    if (bub.pointX < 0 || !bub.target || bub.target.width <= 40) return -1;
    const p = bub.target.mapToItem(null, 0, 0);
    if (bub.pointX < p.x || bub.pointX > p.x + bub.target.width) return -1;
    return bub.pointX - bub.popupX;
  }
  onShownChanged: {
    bub.rearm();
    if (!bub.shown && bub.sticky && !bub.dismissable) grace.restart();
    bub.measure();
  }
  onTargetChanged: bub.measure()
  // a target moved while it is up (or just before): measured again
  Connections {
    target: bub.target
    ignoreUnknownSignals: true
    function onXChanged() { bub.measure(); }
    function onYChanged() { bub.measure(); }
  }
  anchor {
    window: bub.window
    rect.x: Math.round(bub.at.x)
    rect.y: Math.round(bub.at.y + bub.drop)
    rect.width: Math.max(1, Math.round(bub.at.width))
    rect.height: Math.max(1, Math.round(bub.at.height - bub.drop))
    edges: bub.up ? (bub.lean ? Edges.Top | Edges.Left : Edges.Top)
      : (bub.lean ? Edges.Bottom | Edges.Left : Edges.Bottom)
    gravity: bub.up ? (bub.lean ? Edges.Top | Edges.Right : Edges.Top)
      : (bub.lean ? Edges.Bottom | Edges.Right : Edges.Bottom)
    adjustment: PopupAdjustment.Slide
  }

  BubbleCard {
    id: face
    anchors.fill: parent
    shade: bub.shade
    up: bub.up
    lean: bub.lean
    roomBelow: bub.roomBelow
    cardWidth: bub.cardWidth
    fit: bub.fit
    sticky: bub.sticky

    // where the tail's point is: at the pointer while it goes along a wide
    // target; held there while it crosses onto the card; otherwise at the
    // target's middle
    function reaim() {
      if (bub.pointIn >= 0) face.aim = bub.pointIn;
      else if (!face.over) face.aim = bub.homeX - bub.popupX;
    }
    Connections {
      target: bub
      function onPointInChanged() { face.reaim(); }
      function onHomeXChanged() { face.reaim(); }
      function onPopupXChanged() { face.reaim(); }
      function onWidthChanged() { face.reaim(); }
    }
  }
}
