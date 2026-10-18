// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A MENU CARD, WITHOUT ITS SURFACE — what CardPopup is, less the window it
// hangs on: the card (CardBody) sized to its rows, its fade, and branches (a
// row with `children` opening its own card beside it). Lifted out of
// CardPopup (2026-10-18), which is this on a quickshell PopupWindow; a
// surface of another kind puts the same core in itself.
//
//     MenuCore { anchors.fill: parent; model: […]; open: …
//                makeBranch: (rows, core, hingeY) => <a surface holding a MenuCore> }
//
// `makeBranch` is the surface's half of a branch: given the branch's rows,
// this card and how far down it the row is, it returns the new surface (with
// `open`, `model` and a `chosen(int)` signal). Everything else is here.

import QtQuick
import "."

Item {
  id: core

  property var model: []
  property bool open: false
  property int cardWidth: 220
  // as wide as its longest row (cardWidth is then ignored; see Zenon.menuMinWidth)
  property bool fit: false
  property int activeIndex: -1
  // A third of a layer card's shadow room, as terminus' menus have it: the
  // compositor fits the SURFACE, not the card, so every pixel of padding is a
  // pixel the card can be shoved by near a screen edge.
  property int pad: 36

  signal chosen(int index)
  signal hovered(int index)
  signal unhovered(int index)
  signal secondary(int index)
  // a row picked in a branch's card
  signal subChosen(int branch, int index)

  FontMetrics {
    id: rowMetrics
    font.family: Zenon.face
    font.weight: Zenon.weight
    font.pixelSize: Zenon.px(16)
  }

  FontMetrics {
    id: hintMetrics
    font.family: Zenon.face
    font.weight: Zenon.weight
    font.pixelSize: Zenon.px(13)
  }

  readonly property int cardW: {
    if (!core.fit) return core.cardWidth;
    let most = 0;
    const rows = core.model || [];
    for (let i = 0; i < rows.length; ++i) {
      const r = rows[i];
      if (!r || r.isSeparator) continue;
      let w = rowMetrics.advanceWidth(String(r.text || "")) + 12 + 10;
      if (r.icon || r.image) w += 16 + Zenon.menuIconGap;
      if (r.hasChildren || r.children || r.mark !== undefined) w += 16 + 8;
      if (r.hint) w += hintMetrics.advanceWidth(String(r.hint)) + 12;
      most = Math.max(most, w);
    }
    return Math.max(Zenon.menuMinWidth, Math.ceil(most + Zenon.menuCardPad * 2 + 2 + Zenon.menuFitSlack));
  }

  readonly property int contentH: {
    let h = 2;   // the border, top and bottom: the rows run edge to edge
    const rows = core.model || [];
    for (let i = 0; i < rows.length; ++i) h += body.rowHeight(rows[i]);
    return h;
  }

  // the surface's size: the card and its shadow's room; no taller than
  // Zenon.menuMaxHeight, the rest scrolls (CardBody)
  implicitWidth: core.cardW + core.pad * 2
  implicitHeight: Math.min(core.contentH, Zenon.menuMaxHeight) + core.pad * 2

  property real shade: 0
  readonly property bool showing: core.open || core.shade > 0.01
  onOpenChanged: {
    core.shade = core.open ? 1 : 0;
    if (!core.open) core.closeBranch();
    // on its current answer, once the card has its height (CardBody.reveal)
    else Qt.callLater(body.reveal);
  }
  Behavior on shade {
    NumberAnimation { duration: Zenon.menuFade; easing.type: Easing.OutCubic }
  }

  // ── BRANCHES ──────────────────────────────────────────────────────────
  // A row carrying `children` (rows of its own) is a branch: pointed at, its
  // card opens beside it on a surface of its own (makeBranch), hinged on the
  // row. Pointing at any other row puts it away. A row picked in it comes out
  // as subChosen(branch, index).
  property var makeBranch: null
  property int branch: -1
  property var child: null

  function rowY(i) {
    let y = 1;   // just inside the border (CardBody: edge to edge)
    for (let k = 0; k < i && k < core.model.length; ++k) y += body.rowHeight(core.model[k]);
    // where the row is NOW, in a card scrolled down its list
    return y - body.scrollY;
  }
  function openBranch(i) {
    const r = core.model[i];
    if (!r || !r.children || r.enabled === false || !core.makeBranch) { core.closeBranch(); return; }
    if (core.branch === i && core.child) return;
    core.closeBranch();
    const c = core.makeBranch(r.children, core, core.rowY(i) - 1);
    if (!c) return;
    core.branch = i;
    core.child = c;
    c.chosen.connect((k) => core.subChosen(i, k));
    c.open = true;
  }
  function closeBranch() {
    const c = core.child;
    core.child = null;
    core.branch = -1;
    if (c) { c.open = false; c.destroy(); }
  }
  // The rows given again while a branch is open — an owner's model is often a
  // binding, re-made whenever anything it reads changes: the branch keeps its
  // card with its new rows, or loses it if that row is a branch no more.
  onModelChanged: {
    if (!core.child) return;
    const r = core.model[core.branch];
    if (r && r.children) core.child.model = r.children;
    else core.closeBranch();
  }

  CardBody {
    id: body
    anchors.fill: parent
    pad: core.pad
    model: core.model
    shade: core.shade
    // the branch whose card is open stays lit while the pointer is in it
    activeIndex: core.branch >= 0 ? core.branch : core.activeIndex
    onChosen: (i) => {
      const r = core.model[i];
      if (r && r.children) { core.openBranch(i); return; }
      core.chosen(i);
    }
    onHovered: (i) => { core.openBranch(i); core.hovered(i); }
    onUnhovered: (i) => core.unhovered(i)
    onSecondary: (i) => core.secondary(i)
  }
}
