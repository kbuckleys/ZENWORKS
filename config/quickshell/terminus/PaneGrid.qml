// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ── and as a grid ──────────────────────────────────────────────────────
// The same argument, and the one the refactor was actually for: a tile
// holds a decoded image, and the old exchange left a whole pane's worth of
// them referenced by nothing for an instant — which is all it takes for Qt
// to free them and decode them again on the next frame.
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

GridView {
  // the terminus window — passed in by whoever makes one. NOT `root`:
  // inside a delegate a property of that name shadowed the window's id
  // and bound to itself (2026-10-08)
  property var term: null
  id: pgrid
  property Pane pane: null
  readonly property bool act: !!pgrid.pane && pgrid.pane.active
  readonly property bool on: !!pgrid.pane
    && (term.dual || pgrid.pane.side === 0)
    && pgrid.pane.viewMode === "grid"
  readonly property int side: pgrid.pane ? pgrid.pane.side : 0
  readonly property real zoom: pgrid.pane ? pgrid.pane.zoom : 1.0

  x: term.paneX(pgrid.side)
  y: term.paneHeadH(pgrid.side)
  width: term.paneW(pgrid.side)
  height: parent.height - pgrid.y
  visible: pgrid.on
  clip: true
  model: pgrid.on ? pgrid.pane.vm : null
  // ── ELASTIC EDGES, THE WAY FINDER HAS THEM ───────────────────
  // Pull past the end and the listing follows with resistance, then
  // settles back. The wheel's band is driven by hand — see
  // the body's ElasticScroll — because Flickable overshoots only for gestures.
  boundsBehavior: Flickable.DragAndOvershootBounds
  boundsMovement: Flickable.FollowBoundsBehavior
  // drained with the model — see the note on PaneList
  reuseItems: pgrid.on

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


  // A target width rather than a fixed one: the cells divide the pane
  // exactly, so there is never a ragged strip of dead space down the
  // right-hand edge, and they land near enough to the target that a
  // thumbnail is worth looking at.
  readonly property int targetCell: Math.round(190 * pgrid.zoom)
  cellWidth: Math.floor(pgrid.width
    / Math.max(1, Math.round(pgrid.width / pgrid.targetCell)))
  cellHeight: Math.round(168 * pgrid.zoom)

  // ── THE MOMENT THE LISTING GETS SHORTER ──────────────────
  // and not a frame later. positionSel is too early — it runs before
  // the view has taken the new model, so contentHeight is still the old
  // one and the bounds it computes are the old bounds. This is the
  // signal that says the content is now a different size, which is
  // exactly when a scroll position can have become impossible.
  //
  // contentHeight and not contentY: a drag overshoots on purpose and
  // Flickable eases it back itself. Only a RESIZE can strand it.
  onContentHeightChanged: term.snapInBounds(pgrid)
  onOriginYChanged: term.snapInBounds(pgrid)
  // THREE SIGNALS, because no one of them is reliably last. Measured
  // going back out of a scrolled 481-row grid into a 30-row one: the
  // count lands first at oy=4844 cy=6954, and the origin and the
  // content height settle after it. Whichever arrives last, the check
  // is cheap and idempotent.
  onCountChanged: {
    // FORCE THE LAYOUT FIRST. The origin is not merely out of date, it
    // is nonsense: a fresh 21-row listing reported originY 4844, the
    // position the 481 rows before it had drifted to. Every number
    // agreed with every other — contentY, the first delegate, the
    // content height — and the view still drew nothing, because none
    // of them had been recomputed against the rows now in the model.
    // forceLayout is what asks for that recompute; snapping the scroll
    // afterwards then has real bounds to snap to.
    pgrid.forceLayout();
    term.snapInBounds(pgrid);
  }



  // ── ONE FADE FOR THE SCREENFUL ──────────────────────────────────────
  // Each picture used to fade in the moment IT had decoded, and they
  // decode in no particular order — so arriving in a directory was a few
  // blank frames and then a patchwork of tiles developing one by one, a
  // different moment for each. Revisiting did not help: Qt keeps only a
  // couple of megabytes of decoded images nobody is showing, so a directory
  // of pictures is decoded again every time you come back to it.
  //
  // So on arriving somewhere the grid HOLDS: a tile whose picture is
  // still on its way waits, and the moment every tile on screen has its
  // picture — or a short ceiling passes, so a slow disk never costs a
  // blank grid — they are let go together and fade in as one. A tile
  // whose picture was already up is not held; one that arrives after the
  // release (scrolled to, or slow) fades in on its own as before.
  property bool held: false
  property int heldFor: 0
  Connections {
    target: pgrid.pane
    function onCwdChanged() {
      if (term.quietArrive) { holdPoll.stop(); pgrid.held = false; return; }
      pgrid.held = true;
      pgrid.heldFor = 0;
      holdPoll.restart();
    }
  }
  function anyWaiting() {
    const kids = pgrid.contentItem.children;
    const top = pgrid.contentY, bottom = pgrid.contentY + pgrid.height;
    for (let i = 0; i < kids.length; ++i) {
      const k = kids[i];
      if (!k.visible || k.y + k.height < top || k.y > bottom) continue;
      if (k.thumbLoading) return true;
    }
    return false;
  }
  Timer {
    id: holdPoll
    interval: 16
    repeat: true
    onTriggered: {
      pgrid.heldFor += holdPoll.interval;
      // the rows themselves arrive asynchronously too
      const listed = pgrid.count > 0;
      if (pgrid.heldFor < 450 && (!listed || pgrid.anyWaiting())) return;
      holdPoll.stop();
      pgrid.held = false;
    }
  }

  delegate: Tile { term: pgrid.term
    id: tileItem
    required property string path
    required property int index
    held: pgrid.held
    riseView: pgrid
    riseIndex: index
    GridView.onReused: tileItem.riseReset()
    readonly property var row: pgrid.pane.rowFor(path)
    width: pgrid.cellWidth
    height: pgrid.cellHeight
    // the filter's letters, lit in the name
    mark: pgrid.pane.query
    // from its old cell to this one, on a reorder — see Pane.reflow
    Glide { id: tileGlide; limit: pgrid.height }
    function glideCheck() {
      if (!pgrid.pane || !pgrid.pane.reflowing) { tileGlide.stop(); return; }
      const was = pgrid.pane.wasAt(tileItem.path);
      // not there before (a filter loosened): it fades in where it stands
      if (was < 0) { tileGlide.stop(); tileItem.opacity = 0; tileFade.restart(); return; }
      const cols = Math.max(1, Math.floor(pgrid.width / Math.max(1, pgrid.cellWidth)));
      tileGlide.from(((was % cols) - (tileItem.index % cols)) * pgrid.cellWidth,
                     (Math.floor(was / cols) - Math.floor(tileItem.index / cols)) * pgrid.cellHeight);
    }
    NumberAnimation { id: tileFade; target: tileItem; property: "opacity"; to: 1; duration: 260; easing.type: Easing.OutCubic }
    onPathChanged: tileItem.glideCheck()
    onIndexChanged: tileItem.glideCheck()
    Component.onCompleted: tileItem.glideCheck()
    entry: row
    current: index === pgrid.pane.sel
    dim: !!term.cutSet[path]
    ticked: pgrid.act && !!pgrid.pane.marked[path]
    live: pgrid.act
    passive: !pgrid.act
    tileZoom: pgrid.zoom
    onChosen: (right, shift, ctrl, mx, my) => {
      // Come over, then act — see the list's note.
      if (!pgrid.act) term.focusPane(pgrid.pane, index);
      term.clickRow(index, right, shift, ctrl);
      if (right) term.openMenuAt(tileItem, { x: mx, y: my });
    }
    onOpened: {
      if (pgrid.act) pgrid.pane.sel = index;
      else term.focusPane(pgrid.pane, index);
      term.activate();
    }
    onTabbed: if (row && row.isDir) term.openInNewTab(path)
  }
}
