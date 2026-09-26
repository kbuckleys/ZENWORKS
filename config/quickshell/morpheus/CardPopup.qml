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
//       open: …; model: […]; onChosen: …; onDismissed: …
//     }
//
// The row format is CardMenu's.
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
  signal dismissed()
  signal hovered(int index)
  signal unhovered(int index)
  signal secondary(int index)

  // A third of a layer card's shadow room, as terminus' menus have it: the
  // compositor fits the SURFACE, not the card, so every pixel of padding is a
  // pixel the card can be shoved by near a screen edge.
  readonly property int pad: 36

  FontMetrics {
    id: rowMetrics
    font.family: Zenon.face
    font.weight: Font.Medium
    font.pixelSize: 16
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
      if (r.hasChildren || r.mark !== undefined) w += 16 + 8;
      most = Math.max(most, w);
    }
    return Math.max(root.cardWidth, Math.ceil(most + Zenon.menuCardPad * 2 + 2));
  }

  readonly property int contentH: {
    let h = 8;
    for (let i = 0; i < root.model.length; ++i) h += body.rowHeight(root.model[i]);
    return h;
  }

  property real shade: 0
  onOpenChanged: root.shade = root.open ? 1 : 0
  Behavior on shade {
    NumberAnimation { duration: Zenon.menuFade; easing.type: Easing.OutCubic }
  }

  visible: root.window !== null && (root.open || root.shade > 0.01)
  color: "transparent"
  implicitWidth: root.cardW + root.pad * 2
  implicitHeight: root.contentH + root.pad * 2

  anchor {
    window: root.window
    // a rect the size of the padding box, so the CARD's corner lands on the
    // point and the shadow's room is taken out of the way on either side
    rect.x: Math.round(root.at.x) - root.pad
    rect.y: Math.round(root.at.y) - root.pad
    rect.width: 2 * root.pad
    rect.height: 2 * root.pad
    // flip and slide, never resize: a list that fits by losing its bottom
    // rows is not fitting
    adjustment: PopupAdjustment.Flip | PopupAdjustment.Slide
  }

  CardBody {
    id: body
    anchors.fill: parent
    pad: root.pad
    model: root.model
    shade: root.shade
    activeIndex: root.activeIndex
    onChosen: (i) => root.chosen(i)
    onHovered: (i) => root.hovered(i)
    onUnhovered: (i) => root.unhovered(i)
    onSecondary: (i) => root.secondary(i)
  }
}
