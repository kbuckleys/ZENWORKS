// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ── A HALF OF THE WINDOW, AS A LIST ────────────────────────────────────
// One definition, instantiated once per side and never moved, which is the
// whole of the refactor as far as the screen is concerned: the item drawing
// a directory is decided when the window is built rather than when the
// keyboard moves, so Tab destroys nothing.
//
// There used to be two of these written out in full — the active pane's and
// a deliberately plainer one for the other side — and stepping across swapped
// which of them held which directory. Whether a half is ACTIVE now changes
// how it BEHAVES and never which item it is: a passive row draws its cursor
// as an outline rather than a fill, takes no marks, opens no menu, and a
// click in it is a request to come over.
//
// Its own file since 2026-10-08, out of TerminusWindow.qml, where it was an
// inline component. `term` is the terminus window; every place that makes
// one passes it (`term: root`).

import QtQuick
import QtQuick.Shapes
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick.Effects
import QtMultimedia
import Qt.labs.folderlistmodel
import "../morpheus"
import "../picasso"
import "../oracle"
import "terminus.js" as Terminus
import "../morpheus/icons.js" as Icons
import "../morpheus/thumbs.js" as Thumbs
import "tags.js" as Tags
import "collections.js" as Coll

ListView {
  // the terminus window — passed in by whoever makes one. NOT `root`:
  // inside a delegate a property of that name shadowed the window's id
  // and bound to itself (2026-10-08)
  property var term: null
  id: plist
  property Pane pane: null
  readonly property bool act: !!plist.pane && plist.pane.active
  readonly property bool on: !!plist.pane
    && (term.dual || plist.pane.side === 0)
    && plist.pane.viewMode === "list"
  readonly property int side: plist.pane ? plist.pane.side : 0

  // The list can be stranded past the end of a shorter listing exactly
  // as the grid can — see PaneGrid's note and root.snapInBounds.
  onContentHeightChanged: term.snapInBounds(plist)
  onOriginYChanged: term.snapInBounds(plist)
  onCountChanged: {
    // Same recompute the grid needs — see PaneGrid's note.
    plist.forceLayout();
    term.snapInBounds(plist);
  }

  x: term.paneX(plist.side)
  y: term.paneHeadH(plist.side)
  width: term.paneW(plist.side)
  height: parent.height - plist.y
  visible: plist.on
  clip: true
  // Only the view that is ON SCREEN holds delegates. An invisible ListView
  // still builds every one of them. null rather than an empty list, so a
  // hidden view holds none at all.
  model: plist.on ? plist.pane.vm : null
  // ── ELASTIC EDGES, THE WAY FINDER HAS THEM ───────────────────
  // Pull past the end and the listing follows with resistance, then
  // settles back. The wheel's band is driven by hand — see
  // the body's ElasticScroll — because Flickable overshoots only for gestures.
  boundsBehavior: Flickable.DragAndOvershootBounds
  boundsMovement: Flickable.FollowBoundsBehavior
  // RECYCLING IS TURNED OFF WITH THE MODEL, not left running across it. A
  // view whose model goes null releases its delegates into the reuse pool,
  // and the pool survives the detach — coming back it hands those items out
  // again WITHOUT re-injecting the model's roles, so a recycled delegate
  // keeps the `path` it was holding before the view was hidden and draws as
  // an empty row you can still click. Binding it to the model's own gate
  // drains the pool the moment the model is detached.
  reuseItems: plist.on

  // ── THE VIEW MUST NOT WALK WHILE A NAME IS BEING TYPED ──────────────
  // The listing's own handler already refuses every key during an inline
  // rename, and that was not enough here: an item view has key navigation of
  // its own, and it is an ANCESTOR of the field. A Right the TextInput could
  // not use — the caret already at the end of the text, which is exactly
  // where you are when you reach for an extension — bubbled into the view,
  // moved currentIndex, destroyed the delegate being edited and took the
  // rename with it. It never got as far as the handler that would have
  // stopped it.
  //
  // Swallowed here, before the view sees it. Return and Escape never arrive:
  // the field consumes both.
  Keys.onPressed: (event) => { if (term.renaming) event.accepted = true; }

  // ── NO ARRIVAL ANIMATION, AND THAT IS A DECISION ─────────────────
  // A branch opening used to fade its rows in while the list below slid
  // down, through the view's add/remove/displaced transitions. It looked
  // right and it cost three separate faults, all of the same kind: a
  // transition keeps a delegate alive past the point the view would
  // otherwise have reclaimed it, and this view recycles aggressively
  // (reuseItems) into a model that is rebuilt wholesale on every
  // navigation. Rows from the top of a collection were still being
  // painted over rows twenty places down; the cursor bar marked a
  // delegate that was no longer where it appeared to be; clicks landed
  // on neither.
  //
  // Gating them to genuine splices was not enough, because a collection
  // filling in IS a splice — the results arrive in chunks at the end.
  //
  // The expansion still reads as an expansion: the rows appear where
  // they belong and the ones below are already in their new places. It
  // is worth less than a list that is always exactly what it says.

  // ── THE DELEGATE IS A CELL, NOT A ROW ────────────────────────────
  // It was the EntryRow itself. Wrapping it lets a heading sit above the
  // row without EntryRow's own height changing — and EntryRow is drawn in
  // five places, of which only this one groups, so making IT taller would
  // have moved the parent column, the preview and both panes as well.
  //
  // The cell is exactly a row tall until it carries a heading.
  delegate: Item {
    id: cell
    // The model carries identity; the row comes from the pane's index. A
    // file whose size or date changed re-evaluates this one binding instead
    // of being destroyed and built again.
    required property string path
    required property int index
    readonly property var row: plist.pane.rowFor(path)
    readonly property string head: plist.pane.groupHeadAt(cell.index)
    width: plist.width

    // from its old row to this one, on a reorder — see Pane.reflow
    Glide { id: rowGlide; limit: plist.height }
    function glideCheck() {
      if (!plist.pane || !plist.pane.reflowing) { rowGlide.stop(); return; }
      const was = plist.pane.wasAt(cell.path);
      if (was < 0) return;
      rowGlide.from(0, (was - cell.index) * term.rowH);
    }
    onPathChanged: cell.glideCheck()
    onIndexChanged: cell.glideCheck()
    Component.onCompleted: cell.glideCheck()

    height: term.rowH + (cell.head !== "" ? term.groupHeadH : 0)

    // ── THE HEADING ──────────────────────────────────────────────
    // Set in the same muted small caps the sidebar's section heads use,
    // so a band in the listing reads as the same kind of thing as a
    // section in the sidebar rather than as a row you could click.
    Item {
      id: headBand
      visible: cell.head !== ""
      height: visible ? term.groupHeadH : 0
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top

      Text {
        id: headText
        anchors.left: parent.left
        // 12, which is what a row insets its own content by — see the
        // name cell — so the heading starts on the same line the names do.
        anchors.leftMargin: 12
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 3
        text: cell.head
        color: Zenon.muted
        font.family: Zenon.face
        font.weight: Font.Bold
        font.pixelSize: Math.round(11 * term.zoom)
        font.letterSpacing: 0.6
      }

      // The rule runs from the end of the words to the far edge, so the
      // heading reads as a divider with a name on it rather than as a
      // label floating over the list.
      Rectangle {
        anchors.left: headText.right
        anchors.leftMargin: 8
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: headText.verticalCenter
        height: 1
        color: Zenon.border
      }
    }

    EntryRow {
      host: term
    y: headBand.height
    width: plist.width
    entry: cell.row
    // the filter's letters, lit in the name
    mark: plist.pane.query
    // ── THE TREE ─────────────────────────────────────────────
    // Only the list has one, and only over a real directory. A
    // search result is a path from anywhere and has no place in
    // this listing's tree — see pane.tree.
    depth: plist.pane.depthOf(cell.path)
    guide: plist.pane.guideOf(cell.path)
    inTree: plist.pane.treed
    branch: !!cell.row && cell.row.isDir && term.treeRealm
    expanded: plist.pane.isOpen(cell.path)
    hollow: term.dirEmpty[cell.path] === true
    onToggled: {
      if (!plist.act) term.focusPane(plist.pane, cell.index);
      // the view stays where it is — see root.scrollHold
      term.scrollHold = term.keepScroll();
      term.listScrollHold.restart();
      plist.pane.toggleOpen(cell.path);
    }
    current: cell.index === plist.pane.sel
    // Marks are the active half's business — two sets of ticks on screen
    // at once read as terminus having chosen things on its own.
    ticked: plist.act && !!plist.pane.marked[cell.path]
    dim: !!term.cutSet[cell.path]
    live: plist.act
    passive: !plist.act
    // Not `plist.act`: by the time EntryRow asks, the click above has
    // already brought this pane over, so the menu is about a row in the
    // active listing either way.
    actionable: true
    showMeta: plist.width >= term.metaMinWidth
    onChosen: (right, shift, ctrl) => {
      // A click in the half the keyboard is not in comes over FIRST and
      // then does what it came to do. Stopping at the hand-over meant a
      // right click over there only ever switched panes — you had to click
      // once to arrive and again to ask, and the first click looked like it
      // had done nothing but move the focus.
      if (!plist.act) term.focusPane(plist.pane, cell.index);
      term.clickRow(cell.index, right, shift, ctrl);
    }
    // ── DOUBLE CLICK WORKS THE TREE ──────────────────────────────
    // On a directory in the list, a double click opens the BRANCH rather
    // than navigating into it — the same thing the triangle does, for
    // the hand that is already on the row. Going in is still Return,
    // and still a double click in every other view.
    //
    // Finder navigates here and expands only from the triangle. This
    // does not, because the triangle is a small target and the row is
    // a large one, and in a view whose whole point is the tree the
    // large target should be the tree's.
    onOpened: {
      if (plist.act) plist.pane.sel = cell.index;
      else term.focusPane(plist.pane, cell.index);
      if (plist.pane.treed && cell.row && cell.row.isDir) {
        plist.pane.toggleOpen(cell.path);
        return;
      }
      term.activate();
    }
    onTabbed: if (cell.row && cell.row.isDir) term.openInNewTab(cell.path)
    }
  }
}
