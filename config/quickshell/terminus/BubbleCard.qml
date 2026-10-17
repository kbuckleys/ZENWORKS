// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A BUBBLE'S CARD — the speech bubble itself, wherever it is hung: its card,
// its tail, its shadow, what is in it. terminus/Bubble hangs it in a popup
// surface of its own beside a shell window. Plain Qt Quick.
//
// In the tooltip's own ground (Zenon.tipBg), border and glass rim. It fades
// in (`shade`, 0 → 1) and expands out of its tail with a spring.
//
// The card and its tail are ONE outline, filled and drawn once: a tail laid
// over a bordered card left the card's border running across the tail's
// root (user, 2026-10-11). It is a Shape, not a Canvas (2026-10-14): a
// Canvas paints a frame after it is asked, so on every change of size the
// outline trailed what was in it — the content floating, then the card
// catching up. A Shape's path is a binding, drawn in the same frame.
//
// It casts a menu's shadow (MenuShadow's lamp, sized to fit the room left
// around the card), hollow like MenuShadow's — cut to the card AND
// its tail, so the translucent glass is not darkened from under it (user,
// 2026-10-11: shadow and frost, as the menus have).
//
// ── STEADY (user, 2026-10-14: "not very stable … no clipping") ────────
// The surface (`room`) only ever grows while the bubble is up, and is
// sized afresh each opening: what is in it changing no longer resizes and
// re-places the popup every refit, the card under the hand jumping. The
// CARD moves instead, inside the room — its width and height glide to what
// is in it, and what is in it is clipped to the card, so a growing line is
// uncovered by the card rather than hanging out of it.
//
// Its size is the room plus the space for that shadow (`pad`, `padTop` and
// the tail); `card` is where the card itself sits, for a pointer mask.
// `aim` is the x the tail points at — the holder's to keep (Bubble aims it
// at the pointer); it is held inside the card's straight top edge.

import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import "../morpheus"

Item {
  id: face
  property real shade: 0
  // the card's widest; its height is what is in it, and its width is too —
  // FITTED (user, 2026-10-12: "bubble needs to autofit"): the card is as
  // wide as what is in it is naturally, up to this. Two short lines no
  // longer hang in a card sized for a paragraph. `fit: false` keeps the
  // card at cardWidth whatever is in it.
  property real cardWidth: 380
  property bool fit: true
  readonly property int fitMin: 120
  // the pointer on the card says so (`over`) — only while sticky
  property bool sticky: false
  readonly property bool over: overCard.hovered
  // where the tail's point is, in this item's x
  property real aim: face.width / 2
  // the card grows rightwards from its tail's side (Bubble's `lean`): it
  // sits at the room's left, not its middle
  property bool lean: false
  default property alias content: col.data
  readonly property Item card: card

  readonly property int tail: 8
  // ── OR STANDING ON ITS TARGET, POINTING DOWN ────────────────────────
  // For a target at the bottom of the screen (the bar, at the bottom by
  // default): the card above, the tail under it. The room is turned over
  // with it — the target's side keeps the small `padTop` (it is never
  // raised off the target, see below), the far side takes `pad`. The
  // shadow's last 20 px below the card are then cut by the surface's edge,
  // which sits on the bar's: the bar reads as what it falls on.
  property bool up: false
  // the room around the card for its shadow, at the sides and below; above
  // it, only the 6 it always had. The anchor rect is the target's own and
  // never moved: raised to make room above, it went past the window's top
  // for anything in a head bar, and the bubble never came (2026-10-11).
  // 40, not 36: the spring's small overshoot needs a few px of it.
  readonly property int pad: 40
  readonly property int padTop: 6
  // `roomBelow` (standing up only): the full `pad` under the tail too, so
  // the shadow is not cut there — for a bubble standing on something in
  // the middle of a panel (metis' chips, its trend), where the cut showed
  // as a hard edge across what is under it (user, 2026-10-14). Bubble
  // lowers its anchor by the difference, so the tail still lands where it did.
  property bool roomBelow: false
  readonly property int near: face.up && face.roomBelow ? face.pad : face.padTop
  // the shadow, cut to that room: it reaches spread + blur - drop = 14 above
  // the card (padTop + tail), 24 to the sides, 34 below — inside the pad
  readonly property int castSpread: 6
  readonly property int castBlur: 18
  readonly property int castDrop: 10

  // ── WHAT THE CARD WANTS, AND THE ROOM ────────────────────────────────
  // `wantW`/`wantH` are the card's size for what is in it now; the card
  // glides to them. `roomW`/`roomH` are the largest asked this opening —
  // the surface, which never shrinks under an open bubble.
  readonly property real wantW: Math.round(face.fit ? face.fitWidth : face.cardWidth)
  readonly property real wantH: Math.round(col.implicitHeight + 24)
  property real roomW: 0
  property real roomH: 0
  function stretch() {
    if (!face.opening) return;
    if (face.wantW > face.roomW) face.roomW = face.wantW;
    if (face.wantH > face.roomH) face.roomH = face.wantH;
  }
  onWantWChanged: face.stretch()
  onWantHChanged: face.stretch()

  implicitWidth: Math.max(face.roomW, face.wantW) + face.pad * 2
  implicitHeight: face.near + face.tail + Math.max(face.roomH, face.wantH) + face.pad
  // where the tail's point is, in this item's y
  readonly property real tipY: face.up ? card.y + card.height + face.tail : face.padTop
  // the glass comes up fast, so the spring is what is seen; going, it
  // stays until the spring has nearly drawn it back into the tail
  opacity: face.opening ? Math.min(1, face.shade * 2) : Math.min(1, Math.max(0, face.grow) * 2.5)
  // ── IT EXPANDS OUT OF ITS TAIL, WITH A SPRING (user, 2026-10-14) ──────
  // macOS' popovers: from half its size at the tail's point to a hair past
  // full and back, on its own clock rather than the fade's. The swell is
  // small (about 1%): the old one (10%) pushed card and shadow past the
  // surface's edge and they were cut, and it read as a wobble, not a pop.
  // Closing is quicker and plain: drawn straight back into the tail, at
  // once — no wait, no swell (user, 2026-10-14). `opening` is which
  // way the holder's fade is going; `grow` 0 → 1 is the size, and the
  // bubble is up while either is (Bubble.visible).
  //
  // ONE AFTER ANOTHER (ceres' package peek, the pointer going down the
  // names): the holder keeps it shown across the hop (ceres' peekShown),
  // so it never starts to go. Asked back while going, it grows from where
  // it had got to.
  property bool opening: true
  property real lastShade: 0
  property real grow: 0
  property real heldW: 0
  property real heldH: 0
  readonly property int springTime: 260
  onShadeChanged: {
    const wasShut = face.lastShade <= 0.001;
    // the size it leaves at, taken before `opening` turns and holds it
    if (face.opening && face.shade < face.lastShade) { face.heldW = card.width; face.heldH = card.height; }
    face.opening = face.shade >= face.lastShade;
    face.lastShade = face.shade;
    if (face.opening && face.shade > 0 && (wasShut || growOut.running || !growIn.running && face.grow < 1)) {
      growOut.stop();
      // a fresh opening: the room is measured afresh, the card put at
      // its size at once (no glide out of the last one's)
      if (wasShut && face.grow <= 0.001) {
        face.refit();
        face.roomW = face.wantW;
        face.roomH = face.wantH;
      }
      growIn.from = Math.max(0, face.grow);
      growIn.restart();
    } else if (!face.opening && !growOut.running && face.grow > 0) {
      growIn.stop();
      growOut.from = Math.min(1, face.grow);
      growOut.restart();
    }
  }
  NumberAnimation {
    id: growIn
    target: face
    property: "grow"
    to: 1
    duration: face.springTime
    easing.type: Easing.OutBack
    easing.overshoot: 0.9
  }
  // going: straight back into the tail, no swell first (user, 2026-10-14)
  NumberAnimation {
    id: growOut
    target: face
    property: "grow"
    to: 0
    duration: 160
    easing.type: Easing.InCubic
  }
  readonly property real pop: Math.max(0, face.grow)
  transform: Scale {
    origin.x: face.tailX
    origin.y: face.tipY
    xScale: 0.5 + 0.5 * face.pop
    yScale: 0.5 + 0.5 * face.pop
  }

  readonly property real tailX: Math.max(card.x + 14 + face.tail,
    Math.min(card.x + card.width - 14 - face.tail, face.aim))
  // card and tail as one path, in SVG's words (the outline and the
  // shadow's hole share it)
  readonly property string outlinePath: {
    const x = card.x + 0.5, y = card.y + 0.5, w = card.width - 1, h = card.height - 1;
    const r = Math.max(0, Math.min(card.radius, h / 2)), t = face.tail, tx = Math.round(face.tailX) + 0.5;
    let s = "M " + (x + r) + " " + y;
    if (!face.up) s += " L " + (tx - t) + " " + y + " L " + tx + " " + (y - t) + " L " + (tx + t) + " " + y;
    s += " L " + (x + w - r) + " " + y
      + " A " + r + " " + r + " 0 0 1 " + (x + w) + " " + (y + r)
      + " L " + (x + w) + " " + (y + h - r)
      + " A " + r + " " + r + " 0 0 1 " + (x + w - r) + " " + (y + h);
    if (face.up) s += " L " + (tx + t) + " " + (y + h) + " L " + tx + " " + (y + h + t) + " L " + (tx - t) + " " + (y + h);
    s += " L " + (x + r) + " " + (y + h)
      + " A " + r + " " + r + " 0 0 1 " + x + " " + (y + h - r)
      + " L " + x + " " + (y + r)
      + " A " + r + " " + r + " 0 0 1 " + (x + r) + " " + y + " Z";
    return s;
  }

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
  Shape {
    id: hole
    anchors.fill: parent
    visible: false
    layer.enabled: true
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      strokeWidth: -1
      fillColor: "white"
      PathSvg { path: face.outlinePath }
    }
  }
  // the outline: card and tail as one path, filled, then drawn once
  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      strokeWidth: 1
      strokeColor: Zenon.border
      fillColor: Zenon.tipBg
      joinStyle: ShapePath.MiterJoin
      PathSvg { path: face.outlinePath }
    }
  }
  // ── THE FIT ─────────────────────────────────────────────────────
  // What the content would take, unconstrained: a Text's implicitWidth is
  // its unwrapped line (whatever width it has been given), a layout's is
  // what its children ask, a scrolling view asks for everything. A plain
  // Item or positioner is read through its children's (x + their own),
  // never through its width — that is usually bound to the card's, which
  // is what is being worked out. Measured by hand, not bound, for the same
  // reason, and again whenever the content may have changed.
  property real fitWidth: face.cardWidth
  function natural(it) {
    if (!it || !it.visible) return 0;
    if (it.contentY !== undefined) return 1e6;               // a Flickable/ListView
    if (it.wrapMode !== undefined || it.font !== undefined)   // Text, TextEdit, a label
      return it.implicitWidth;
    const isPositioner = it.populate !== undefined;           // Row, Column, Flow, Grid
    if (!isPositioner && it.implicitWidth > 0) return it.implicitWidth;
    let w = 0;
    for (let i = 0; i < it.children.length; i++) {
      const k = it.children[i];
      const n = face.natural(k);
      if (n > 0) w = Math.max(w, (isPositioner ? k.x : Math.max(0, k.x)) + n);
    }
    return w;
  }
  function refit() {
    // never while it goes (see the spring): it leaves at the size it had.
    // Shut, it may: a bubble about to open again is fitted before it does
    // (`opening` only turns once its fade has started)
    if (!face.opening && (face.shade > 0.001 || face.grow > 0.001)) return;
    let w = 0;
    for (let i = 0; i < col.children.length; i++)
      w = Math.max(w, face.natural(col.children[i]));
    face.fitWidth = Math.max(face.fitMin, Math.min(face.cardWidth, Math.ceil(w) + 28));
  }
  onCardWidthChanged: face.refit()
  // content that changes while it is up (a progress, a peek's next row)
  Timer {
    interval: 250
    repeat: true
    running: face.fit && face.shade > 0
    onTriggered: face.refit()
  }
  Connections {
    target: col
    function onChildrenChanged() { refitSoon.restart(); }
    function onImplicitHeightChanged() { refitSoon.restart(); }
  }
  Timer { id: refitSoon; interval: 0; onTriggered: face.refit() }
  Component.onCompleted: refitSoon.restart()

  // the card glides to a new size only once it is well up — while it is
  // still springing out of the tail (small, faint) it takes it at once,
  // so what an opening's content settles to is never seen as a slide
  readonly property bool glide: face.opening && face.pop > 0.6

  Item {
    id: card
    // in its room: in the middle (under the tail's home), or at the left
    // for a leaning bubble; hugging the tail's side top-to-bottom
    x: face.lean ? face.pad : Math.round(face.pad + (face.width - face.pad * 2 - card.width) / 2)
    y: face.up ? face.height - face.near - face.tail - card.height : face.padTop + face.tail
    // held as it was while it goes: a holder clearing what is in it as it
    // shuts must not shrink the card under its own outline
    width: face.opening ? face.wantW : face.heldW
    height: face.opening ? face.wantH : face.heldH
    Behavior on width { enabled: face.glide; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    Behavior on height { enabled: face.glide; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    readonly property real radius: Zenon.windowRadius
    // what is in it never shows past its edge, gliding or not
    clip: true
    // the pointer on it holds a sticky bubble up
    HoverHandler { id: overCard; enabled: face.sticky }
    Column {
      id: col
      x: 14
      y: 12
      // the width it is going to, not the gliding one: text is wrapped
      // once, and the card uncovers it
      width: (face.opening ? face.wantW : face.heldW) - 28
      spacing: 10
    }
  }
  // the glass rim, as the tooltips have it (see Zenon.rim): a light along
  // the top, faded at its ends, broken where the tail rises
  Item {
    id: rim
    visible: Zenon.rimOn
    x: card.x + card.radius
    y: card.y + 1
    width: Math.max(0, card.width - 2 * card.radius)
    height: 1
    readonly property real gapA: face.up ? width : Math.max(0, Math.round(face.tailX) - face.tail - 2 - x)
    readonly property real gapB: face.up ? width : Math.min(width, Math.round(face.tailX) + face.tail + 3 - x)
    Item {
      width: parent.gapA
      height: 1
      clip: true
      Rectangle { width: rim.width; height: 1; gradient: rimInk }
    }
    Item {
      x: parent.gapB
      width: Math.max(0, parent.width - parent.gapB)
      height: 1
      clip: true
      Rectangle { x: -parent.x; width: rim.width; height: 1; gradient: rimInk }
    }
  }
  Gradient {
    id: rimInk
    orientation: Gradient.Horizontal
    GradientStop { position: 0.0; color: Zenon.alpha(Zenon.rim, 0) }
    GradientStop { position: 0.25; color: Zenon.rim }
    GradientStop { position: 0.75; color: Zenon.rim }
    GradientStop { position: 1.0; color: Zenon.alpha(Zenon.rim, 0) }
  }
}
