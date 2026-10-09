// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// SELECTCELL — the cursor over a grid of tiles: SelectBar on two axes.
//
//     SelectCell { view: grid; index: grid.currentIndex; host: root }
//
// Terminus' grid cursor, lifted out of it so picasso's gallery wears the same
// one. One rounded box behind the tiles that travels between cells, on both
// axes, so a grid of pictures is walked rather than blinked through.
//
// THE HOST, when there is one, is the window it belongs to, read the way
// SelectBar reads it: whether the cursor is to slide at all (cursorSlide),
// and a pulse that says "land where you are now, without the slide"
// (thawPulse).
//
// A list has one axis and an index is a row; a grid has two and an index is
// a row AND a column, so the bar travels diagonally between tiles that are
// not neighbours. Everything else is SelectBar's argument unchanged — one
// rectangle that moves, not a fill that blinks from one cell to the next.
//
// HOW MANY COLUMNS is not something GridView will tell you, so it is worked
// out the same way the view works it out: the pane's width over the cell's.
// Asking the delegates instead would mean asking an item that may not exist,
// because the view only builds the cells it can see.
//
// INSET BY 4 WITH A RADIUS OF 6, which is the tile's own fill — this stands
// exactly where that stood, so nothing about the grid's spacing changes.

import QtQuick
import "../morpheus"

Item {
  id: cell
  property var host: null
  property GridView view: null
  property int index: 0
  property bool on: true
  property bool animate: true
  readonly property bool slides: !cell.host || cell.host.cursorSlide !== false

  readonly property int cols: (cell.view && cell.view.cellWidth > 0)
    ? Math.max(1, Math.floor(cell.view.width / cell.view.cellWidth)) : 1

  // NOTHING TO MARK WHEN THERE IS NOTHING THERE. `on` is about whether this
  // list wants a cursor at all; this is about whether it has a row to put
  // one on. An empty directory drew the bar at index 0 anyway — a lone
  // rectangle in the corner of a pane that says "Empty" underneath it.
  //
  // Asked of the VIEW rather than of the caller, so every list that wears
  // one of these is covered by construction and no call site has to
  // remember. Flickable has no `count`; ListView and GridView both do, and
  // the guard is for the moment before `view` is assigned.
  readonly property bool filled: !!cell.view && cell.view.count > 0




  // Parented to the view for the reasons SelectBar gives: outside anyone's
  // layout, and outside contentItem, whose children the view repositions.
  parent: cell.view
  anchors.fill: cell.view
  clip: true
  z: -1

  // ── ON THE RENDER THREAD, for the reason SelectBar's note gives ─────
  // And this is the view that needs it most: a grid is where the thumbnails
  // are, so the GUI thread is at its busiest exactly when the cursor is
  // being run down it.
  //
  // Split the same way — the wrapper takes the scroll on the GUI thread, the
  // cell inside takes the travel on the render thread. Two axes here, so
  // both x and y get an Animator.
  Item {
    width: parent.width
    height: parent.height
    // MINUS THE ORIGIN. The slot below is worked out from the index —
    // index * cellHeight — which is a position relative to where the
    // view reckons its content STARTS, and that is originY, not zero.
    // originY drifts when rows are replaced in place (see
    // root.snapInBounds), and a scroll offset measured from zero then
    // puts this box a whole origin away from the row it is marking:
    // measured at 1038px above the viewport, which reads as the cursor
    // having disappeared.
    y: -(cell.view ? cell.view.contentY - cell.view.originY : 0)

    Rectangle {
      id: box
      readonly property real cw: cell.view ? cell.view.cellWidth : 0
      readonly property real ch: cell.view ? cell.view.cellHeight : 0

      readonly property real slotX: (cell.index % cell.cols) * box.cw + 4
      readonly property real slotY:
        Math.floor(cell.index / cell.cols) * box.ch + 4

      x: box.slotX
      y: box.slotY
      Behavior on x {
        id: slideX
        enabled: cell.animate && cell.slides
        XAnimator { duration: Zenon.fast; easing.type: Zenon.travelEase }
      }
      Behavior on y {
        id: slideY
        enabled: cell.animate && cell.slides
        YAnimator { duration: Zenon.fast; easing.type: Zenon.travelEase }
      }

      // See root.thawPulse — the same stranding, on two axes here.
      // DEFERRED. The pulse is sent as the rows are written, which is
      // before the view has taken them — index and cols are still the
      // old ones, the slot still agrees with where the box is, and
      // reseat returns having done nothing. One turn later the new
      // slot is known and the check is asked the question it is for.
      Connections {
        target: cell.host
        ignoreUnknownSignals: true
        function onThawPulseChanged() { Qt.callLater(box.reseat); }
      }
      function reseat() {
        if (Math.abs(box.x - box.slotX) < 0.5
            && Math.abs(box.y - box.slotY) < 0.5) return;
        slideX.enabled = false;
        slideY.enabled = false;
        box.x = Qt.binding(function() { return box.slotX; });
        box.y = Qt.binding(function() { return box.slotY; });
        slideX.enabled = Qt.binding(function() {
          return cell.animate && cell.slides;
        });
        slideY.enabled = Qt.binding(function() {
          return cell.animate && cell.slides;
        });
      }

      width: Math.max(0, cw - 8)
      height: Math.max(0, ch - 8)
      radius: 6
      color: Zenon.border
      // See the note on Tile's border: over a thumbnail the fill is
      // hidden by the picture, so the outline is what says "here" —
      // and it has to be on the thing that travels.
      border.width: 1
      border.color: Zenon.border
      visible: cell.on && cell.filled
    }
  }
}
