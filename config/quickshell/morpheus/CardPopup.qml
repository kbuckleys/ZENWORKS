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
// them in a card of their own beside it, on hover — see MenuCore's BRANCHES.
//
// THE SURFACE ONLY. The menu itself — sizing, fade, branches, the card — is
// morpheus/MenuCore (2026-10-18), so any other surface can hang the same core.
import QtQuick
import Quickshell
import "."

PopupWindow {
  id: root

  // the window it hangs off, and where in it: the card's top-left
  property var window: null
  property point at: Qt.point(0, 0)

  property alias model: core.model
  property alias open: core.open
  property alias cardWidth: core.cardWidth
  // as wide as its longest row (cardWidth is then ignored; see Zenon.menuMinWidth)
  property alias fit: core.fit
  property alias activeIndex: core.activeIndex
  readonly property alias pad: core.pad
  readonly property alias cardW: core.cardW
  readonly property alias contentH: core.contentH
  readonly property alias shade: core.shade
  readonly property alias branch: core.branch
  readonly property alias child: core.child

  signal chosen(int index)
  signal hovered(int index)
  signal unhovered(int index)
  signal secondary(int index)
  // a row picked in a branch's card
  signal subChosen(int branch, int index)

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

  // set on a branch's card: the card it hangs off, and how far down that
  // card the row is
  property var parentCard: null
  property real hingeY: 0

  function rowY(i) { return core.rowY(i); }
  function openBranch(i) { core.openBranch(i); }
  function closeBranch() { core.closeBranch(); }

  visible: root.window !== null && core.showing
  color: "transparent"
  implicitWidth: core.implicitWidth
  implicitHeight: core.implicitHeight

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

  MenuCore {
    id: core
    anchors.fill: parent
    // a branch's card: another CardPopup, its own surface, hinged on the row
    // as terminus' submenu is — anchored to THIS surface across the card's
    // width, so FlipX mirrors it to the card's left where the screen runs out
    makeBranch: (rows, from, hingeY) => {
      const c = Qt.createComponent("CardPopup.qml");
      return c.status === Component.Ready
        ? c.createObject(root, { window: root, parentCard: root, hingeY: hingeY, fit: true,
                                 cardWidth: core.cardWidth, model: rows })
        : null;
    }
    onChosen: (i) => root.chosen(i)
    onHovered: (i) => root.hovered(i)
    onUnhovered: (i) => root.unhovered(i)
    onSecondary: (i) => root.secondary(i)
    onSubChosen: (b, i) => root.subChosen(b, i)
  }
}
