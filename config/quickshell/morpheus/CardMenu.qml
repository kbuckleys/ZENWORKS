// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE CARD every menu on this desktop is. Icarus wrote this shape three times
// over — a root menu, a session submenu, a trash submenu — and terminus wrote
// it again for its own context menu. All four agree on every number, because
// a menu that measured itself differently from the one beside it was the
// loudest thing saying they were different kinds of object. They are not:
// they are one card, drawn wherever a menu is wanted.
//
// So this is that card, driven by a plain array instead of by any particular
// menu's data:
//
//     CardMenu {
//       open: root.menuOpen
//       at: Qt.point(x, y)            // screen coordinates of the top-left
//       model: [ { text: "Open" }, { isSeparator: true }, { text: "Empty" } ]
//       onChosen: (i) => …
//     }
//
// Putting it away is the caller's: it sets `open` false — on a choice, on a
// focus grab clearing, on escape. The card never closes itself.
//
// A row is { text, icon, image, swatch, weight, hasChildren, isSeparator,
// enabled, mark, danger, asks }. Everything but `text` is optional. `icon`
// is a font glyph and `image` a URL, for the menus whose icons come from
// applications rather than from the font; `swatch` is a theme's three
// colors (see Swatch), `weight` the row's own font weight; `mark` is a tick
// on the right, for the rows that report a current choice rather than
// perform an action; `danger` reddens a row that is armed and waiting to be
// confirmed; `asks` means the row opens a question rather than acting, so
// it does not flash. A row with `children` (rows of
// its own) is a branch: pointed at, they open in CardPopup's card beside it
// (MenuCore's BRANCHES), and a row picked there comes out as subChosen.
//
// IT DOES NOT GRAB FOCUS ITSELF. A menu is almost never alone — a submenu is
// open beside it, and the layer that opened them both is underneath — and a
// grab per card fights every other grab on screen. The OWNER holds one grab
// over all of them; see `window`, which is what it lists.

import QtQuick
import Quickshell
import Quickshell.Wayland
import "."

PanelWindow {
  id: root

  // ON THE OVERLAY LAYER, and it has to be said out loud.
  //
  // `aboveWindows` is about ordinary application windows; it says nothing
  // about where this sits relative to another LAYER surface. Picasso is an
  // overlay, and a card left on the default layer was drawn underneath it —
  // the rows were genuinely there, faintly legible through the translucent
  // panel on top of them, which is a very confusing way to fail.
  //
  // A menu is the topmost thing on screen by definition, so this is the
  // default rather than something each caller has to remember; within one
  // layer wlroots stacks by creation order, and a card's surface is created
  // when it first opens, which is always after whatever opened it.
  WlrLayershell.layer: WlrLayer.Overlay
  // a menu animates itself (shade: fade + scale, as CardPopup's do); the
  // namespace lets hyprland's rules turn its own layer animation off, which
  // ran on top and made these cards move unlike terminus' (user, 2026-10-19)
  WlrLayershell.namespace: "morpheus-menu"

  property var model: []
  property bool open: false
  // the card's top-left, in screen coordinates. Clamped to the screen below,
  // so a caller may hand over a position that does not quite fit.
  property point at: Qt.point(0, 0)
  property int cardWidth: 220

  // ── OR AS WIDE AS ITS LONGEST ROW ─────────────────────────────────────
  // Off by default, and cardWidth is then the width. On, the card is as wide
  // as its longest label and no wider (Zenon.menuMinWidth the least) —
  // capped at the screen, less the gap at each edge. Opt-in rather than a
  // rule because some menus list things of no fixed length (recent files)
  // and those are better elided than as wide as a path.
  property bool fit: false

  FontMetrics {
    id: rowMetrics
    font.family: Zenon.face
    font.weight: Zenon.weight
    font.pixelSize: Zenon.px(16)
  }

  // The label's width plus everything a row puts around it: the row's own
  // insets, an icon and its gap when there is one, the tail (tick or
  // chevron) and its gap when there is one, and the card's padding.
  readonly property int fitWidth: {
    if (!root.fit) return 0;
    // measured again on every opening: icarus' root menu was seen live at the
    // width of its rows from before the shell's own entries joined them
    // (user, 2026-10-19 — "Set backg…", "Display se…"), and the card is only
    // ever seen open
    root.open;
    rowMetrics.height;   // and when the face resolves (advanceWidth is a call)
    let most = 0;
    const rows = root.model || [];
    for (let i = 0; i < rows.length; ++i) {
      const r = rows[i];
      if (!r || r.isSeparator) continue;
      let w = rowMetrics.advanceWidth(String(r.text || "")) + 12 + 10;
      if (r.swatch) w += 22 + Zenon.menuIconGap;
      else if (r.icon || r.image) w += 16 + Zenon.menuIconGap;
      if (r.hasChildren || r.children || r.mark !== undefined) w += 16 + 8;
      most = Math.max(most, w);
    }
    return Math.ceil(most + Zenon.menuCardPad * 2 + 2 + Zenon.menuFitSlack);
  }

  // The width everything below uses.
  readonly property int cardW: {
    if (!root.fit) return root.cardWidth;
    const cap = root.screen ? root.screen.width - root.edgeGap * 2 : 100000;
    return Math.min(cap, Math.max(Zenon.menuMinWidth, root.fitWidth));
  }

  // A choice is reported, not acted on: a caller usually wants to put the
  // whole stack of menus away on one, and that is its decision rather than
  // this card's.
  signal chosen(int index)

  // What a submenu needs to place itself against a row of this one, and what
  // an owner needs to include this card in its focus grab.
  readonly property alias card: body.card
  function rowY(i) {
    // the rows start just inside the 1px border (CardBody: edge to edge)
    let y = 1;
    for (let k = 0; k < i && k < root.model.length; ++k)
      y += root.rowHeight(root.model[k]);
    // where the row is NOW, in a card scrolled down its list
    return y - body.scrollY;
  }
  // The same row every menu on this desktop uses, so a card opened on a
  // background and one opened on the desktop measure identically.
  function rowHeight(m) {
    return (m && m.isSeparator) ? Zenon.menuSepHeight : Zenon.menuRowHeight;
  }

  readonly property int contentH: {
    let h = 2;   // the border, top and bottom: the rows run edge to edge
    for (let i = 0; i < root.model.length; ++i) h += root.rowHeight(root.model[i]);
    return h;
  }

  // ── the arrival, as terminus' context menu does it ──────────────────
  // 0 closed, 1 open. The opacity and the scale are both functions of this
  // one number, and the card is kept alive through the fade OUT — a menu that
  // vanishes on the frame you click it never shows you which row you clicked.
  property real shade: 0
  onOpenChanged: {
    root.shade = root.open ? 1 : 0;
    if (!root.open) root.closeBranch();
    // on its current answer, once the card has its height (CardBody.reveal)
    if (root.open) Qt.callLater(body.reveal);
  }
  Behavior on shade {
    NumberAnimation { duration: Zenon.menuFade; easing.type: Easing.OutCubic }
  }

  visible: root.open || root.shade > 0.01
  focusable: false
  aboveWindows: true
  exclusionMode: ExclusionMode.Ignore
  color: "transparent"
  // THE CARD'S RECTANGLE, NOT THE CARD. It arrives scaled up from
  // Zenon.menuScaleFrom, and a Region following an ITEM re-reads it only when
  // its geometry changes — never when its scale does. So the mask could be
  // left at the arrival's 94%, and the bottom rows of a long menu sat outside
  // it: a click on them went through to the desktop, the focus grab took it
  // as a click away, and the menu closed without its row ever flashing.
  mask: Region { x: body.card.x; y: body.card.y; width: body.card.width; height: body.card.height }
  anchors { top: true; left: true }

  implicitWidth: root.cardW + Zenon.menuShadowPad * 2
  // no taller than Zenon.menuMaxHeight, nor than the screen; the rest scrolls.
  // `whole`: every row shown, only the screen limiting it (a sticky's menu,
  // whose spelling rows pushed it past the cap — user, 2026-10-17)
  property bool whole: false
  implicitHeight: {
    const cap = root.whole ? root.contentH : Math.min(root.contentH, Zenon.menuMaxHeight);
    if (!root.screen) return cap + Zenon.menuShadowPad * 2;
    const maxH = root.screen.height - Zenon.menuShadowPad * 2;
    return Math.min(cap, maxH) + Zenon.menuShadowPad * 2;
  }

  // The card is inset inside its own window by the shadow's padding, so the
  // window goes menuShadowPad further up and left than the card does.
  // A SUBMENU FLIPS; A ROOT CARD CLAMPS.
  //
  // Set `flipFrom` to the right edge of the card this one hangs off and it
  // will go there if it fits, to that card's other side if it does not, and
  // only clamp if neither side has room. Clamping alone was fine for a menu
  // opened at a pointer, but a submenu that clamps slides back OVER its own
  // parent and hides the row you opened it from.
  //
  // `hinged` is an explicit BOOLEAN and not a NaN sentinel. A QML `real` does
  // not reliably carry NaN — coerced to 0 it makes isNaN() false, the flip
  // branch runs with an edge of 0, and the card lands against the left of the
  // screen. Every card that did NOT want a hinge was one coercion away from
  // being thrown across the display.
  property bool hinged: false
  // ── AND SQUARE WHERE IT MEETS SOMETHING ELSE ──────────────────────────
  // "top" or "bottom": the edge this card sits flush against — the tray's
  // menu opening out of the pill. The same rule as a hinged submenu: where
  // two surfaces meet, the corner is square.
  property string squareEdge: ""
  property real flipFrom: 0
  property real flipParentLeft: 0

  // HOW CLOSE A CARD MAY COME TO A SCREEN EDGE. Not the shadow's padding:
  // that is 80px of decoration, and reserving it meant a menu standing on the
  // pill was shoved up by whatever the pill did not leave underneath it —
  // 42px of daylight between the menu and the bar it was supposed to sit on.
  // The CARD is what has to stay on screen; the shadow may clip against the
  // edge, which is what a shadow at a screen edge does anyway.
  readonly property int edgeGap: Zenon.padScreen

  readonly property real placedX: {
    if (!root.screen) return 0;
    const pad = root.edgeGap;
    const w = root.cardW;
    const limit = root.screen.width - pad;
    if (root.hinged) {
      return Math.round(Zenon.hingeX(root.flipParentLeft,
        root.flipFrom - root.flipParentLeft, w, root.screen.width, pad));
    }
    return Math.round(Math.max(pad, Math.min(root.at.x, limit - w)));
  }

  margins.left: root.placedX - Zenon.menuShadowPad

  // Which side a hinged card landed on.
  readonly property bool onRight: root.hinged
    && root.placedX >= root.flipFrom - 0.5
  margins.top: {
    if (!root.screen) return 0;
    const pad = Zenon.menuShadowPad;
    const h = root.implicitHeight - pad * 2;
    const gap = root.edgeGap;
    const y = Math.max(gap, Math.min(root.at.y, root.screen.height - h - gap));
    return Math.round(y - pad);
  }

  // where the card actually ended up, for a submenu to measure against
  readonly property real cardX: root.margins.left + Zenon.menuShadowPad
  readonly property real cardY: root.margins.top + Zenon.menuShadowPad

  // the card itself, shared with CardPopup
  CardBody {
    id: body
    anchors.fill: parent
    pad: Zenon.menuShadowPad
    model: root.model
    shade: root.shade
    hinged: root.hinged
    onRight: root.onRight
    squareEdge: root.squareEdge
    // (a whole menu taller than the screen still scrolls, or its last rows
    // could not be reached)
    still: root.whole && (!root.screen || root.contentH <= root.screen.height - Zenon.menuShadowPad * 2)
    // the branch whose card is open stays lit while the pointer is in it
    activeIndex: root.branch >= 0 ? root.branch : root.activeIndex
    onChosen: (i) => {
      const r = root.model[i];
      if (r && r.children) { root.openBranch(i); return; }
      root.chosen(i);
    }
    onHovered: (i) => { root.openBranch(i); root.hovered(i); }
    onUnhovered: (i) => root.unhovered(i)
    onSecondary: (i) => root.secondary(i)
  }

  signal hovered(int index)
  signal unhovered(int index)
  signal secondary(int index)
  property int activeIndex: -1

  // ── BRANCHES ──────────────────────────────────────────────────────────
  // CardPopup's card hung off this surface at the row (a layer surface takes
  // an xdg-popup as a window does), flipping to the left where the screen
  // runs out. `child` is that card, for an owner's focus grab to list.
  signal subChosen(int branch, int index)
  property int branch: -1
  property var child: null
  function openBranch(i) {
    const r = root.model[i];
    if (!r || !r.children || r.enabled === false) { root.closeBranch(); return; }
    if (root.branch === i && root.child) return;
    root.closeBranch();
    const c = Qt.createComponent("CardPopup.qml");
    if (c.status !== Component.Ready) return;
    // as a card a CardPopup hangs off: its inset, its width, the row's depth
    const hinge = { pad: Zenon.menuShadowPad, cardW: root.cardW };
    const k = c.createObject(root, { window: root, parentCard: hinge, hingeY: root.rowY(i) - 1,
                                     fit: true, cardWidth: root.cardWidth, model: r.children });
    if (!k) return;
    root.branch = i;
    root.child = k;
    root.child.chosen.connect((j) => root.subChosen(i, j));
    root.child.open = true;
  }
  function closeBranch() {
    const k = root.child;
    root.child = null;
    root.branch = -1;
    if (k) { k.open = false; k.destroy(); }
  }
  onModelChanged: {
    if (!root.child) return;
    const r = root.model[root.branch];
    if (r && r.children) root.child.model = r.children;
    else root.closeBranch();
  }
}
