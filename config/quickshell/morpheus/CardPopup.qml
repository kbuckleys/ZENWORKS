// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE CARD, FOR A WINDOW. CardMenu stands on a layer surface placed in
// screen coordinates — which a window cannot supply, because a wayland client
// is never told where its own window is. An xdg-popup can be placed by
// something it DOES know: a point inside its own window. So this hangs the same
// card (CardBody) off that point, and the compositor puts it on screen,
// flipping it up or sliding it sideways when there is no room below.
//
//     CardPopup {
//       window: myWindow
//       at: chip.mapToItem(null, 0, chip.height + 4)   // window coordinates
//       open: …; model: […]; onChosen: …
//     }
//
// The row format is CardMenu's, and one more: a row with `children` opens
// them in a card of their own beside it, on hover — see BRANCHES.
import QtQuick
import Quickshell
import "."

PopupWindow {
  id: root

  // the window it hangs off, and where in it: the card's top-left
  property var window: null
  property point at: Qt.point(0, 0)

  property var model: []
  property bool open: false
  property int cardWidth: 220
  // as wide as its longest row, and never narrower than cardWidth
  property bool fit: false
  property int activeIndex: -1

  signal chosen(int index)
  signal hovered(int index)
  signal unhovered(int index)
  signal secondary(int index)

  // A key pressed while the card's own surface has the keyboard. Whether a
  // popup or the window under it gets the keys is the compositor's call, so
  // a holder that wants a key on a row (oracle: Delete on a theme) listens
  // here as well as on its own window. Opt in with `takeKeys`.
  property bool takeKeys: false
  signal keyPressed(var event)
  Item {
    focus: root.takeKeys
    Keys.onPressed: (event) => root.keyPressed(event)
  }

  // A third of a layer card's shadow room, as terminus' menus have it: the
  // compositor fits the SURFACE, not the card, so every pixel of padding is a
  // pixel the card can be shoved by near a screen edge.
  readonly property int pad: 36

  FontMetrics {
    id: rowMetrics
    font.family: Zenon.face
    font.weight: Font.Medium
    font.pixelSize: Zenon.px(16)
  }

  FontMetrics {
    id: hintMetrics
    font.family: Zenon.face
    font.weight: Zenon.weight
    font.pixelSize: Zenon.px(13)
  }

  readonly property int cardW: {
    if (!root.fit) return root.cardWidth;
    let most = 0;
    const rows = root.model || [];
    for (let i = 0; i < rows.length; ++i) {
      const r = rows[i];
      if (!r || r.isSeparator) continue;
      let w = rowMetrics.advanceWidth(String(r.text || "")) + 12 + 10;
      if (r.icon || r.image) w += 16 + Zenon.menuIconGap;
      if (r.hasChildren || r.children || r.mark !== undefined) w += 16 + 8;
      if (r.hint) w += hintMetrics.advanceWidth(String(r.hint)) + 12;
      most = Math.max(most, w);
    }
    return Math.max(root.cardWidth, Math.ceil(most + Zenon.menuCardPad * 2 + 2));
  }

  readonly property int contentH: {
    let h = 8;
    const rows = root.model || [];
    for (let i = 0; i < rows.length; ++i) h += body.rowHeight(rows[i]);
    return h;
  }

  property real shade: 0
  onOpenChanged: {
    root.shade = root.open ? 1 : 0;
    if (!root.open) root.closeBranch();
    // on its current answer, once the card has its height (CardBody.reveal)
    else Qt.callLater(body.reveal);
  }

  // ── BRANCHES ──────────────────────────────────────────────────────────
  // A row carrying `children` (rows of its own) is a branch: pointed at, its
  // card opens beside it — another CardPopup, its own surface, hinged on the
  // row as terminus' submenu is (subPop): anchored to THIS surface across the
  // card's width, so FlipX mirrors it to the card's left where the screen
  // runs out, rather than onto the card. Pointing at any other row puts it
  // away. A row picked in it comes out as subChosen(branch, index).
  signal subChosen(int branch, int index)
  // set on a branch's card: the card it hangs off, and how far down that
  // card the row is
  property var parentCard: null
  property real hingeY: 0
  property int branch: -1
  property var child: null

  function rowY(i) {
    let y = Zenon.menuCardPad;
    for (let k = 0; k < i && k < root.model.length; ++k) y += body.rowHeight(root.model[k]);
    // where the row is NOW, in a card scrolled down its list
    return y - body.scrollY;
  }
  function openBranch(i) {
    const r = root.model[i];
    if (!r || !r.children || r.enabled === false) { root.closeBranch(); return; }
    if (root.branch === i && root.child) return;
    root.closeBranch();
    const comp = Qt.createComponent("CardPopup.qml");
    if (comp.status !== Component.Ready) return;
    const c = comp.createObject(root, {
      window: root, parentCard: root, hingeY: root.rowY(i) - Zenon.menuCardPad,
      fit: true, cardWidth: root.cardWidth, model: r.children
    });
    if (!c) return;
    root.branch = i;
    root.child = c;
    c.chosen.connect((k) => root.subChosen(i, k));
    c.open = true;
  }
  function closeBranch() {
    const c = root.child;
    root.child = null;
    root.branch = -1;
    if (c) { c.open = false; c.destroy(); }
  }
  // The rows given again while a branch is open — an owner's model is often a
  // binding, re-made whenever anything it reads changes: the branch keeps its
  // card with its new rows, or loses it if that row is a branch no more.
  onModelChanged: {
    if (!root.child) return;
    const r = root.model[root.branch];
    if (r && r.children) root.child.model = r.children;
    else root.closeBranch();
  }
  Behavior on shade {
    NumberAnimation { duration: Zenon.menuFade; easing.type: Easing.OutCubic }
  }

  visible: root.window !== null && (root.open || root.shade > 0.01)
  color: "transparent"
  implicitWidth: root.cardW + root.pad * 2
  // no taller than Zenon.menuMaxHeight; the rest scrolls (CardBody)
  implicitHeight: Math.min(root.contentH, Zenon.menuMaxHeight) + root.pad * 2

  anchor {
    window: root.window
    // a rect the size of the padding box, so the CARD's corner lands on the
    // point and the shadow's room is taken out of the way on either side.
    // A branch's card: the parent card's width, at its row — both shifted
    // back by this surface's own inset, so the CARD lands flush against the
    // parent card rather than a shadow's width away from it.
    rect.x: root.parentCard ? root.parentCard.pad - root.pad : Math.round(root.at.x) - root.pad
    rect.y: root.parentCard ? root.parentCard.pad + root.hingeY - root.pad : Math.round(root.at.y) - root.pad
    rect.width: root.parentCard ? root.parentCard.cardW : 2 * root.pad
    rect.height: root.parentCard ? 1 : 2 * root.pad
    edges: root.parentCard ? (Edges.Right | Edges.Top) : (Edges.Left | Edges.Top)
    gravity: Edges.Right | Edges.Bottom
    // flip and slide, never resize: a list that fits by losing its bottom
    // rows is not fitting
    adjustment: root.parentCard ? (PopupAdjustment.FlipX | PopupAdjustment.SlideY)
                                : (PopupAdjustment.Flip | PopupAdjustment.Slide)
  }

  CardBody {
    id: body
    anchors.fill: parent
    pad: root.pad
    model: root.model
    shade: root.shade
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
}
