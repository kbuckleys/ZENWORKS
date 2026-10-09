// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ── ONE COLUMN OF THE MILLER VIEW ─────────────────────────────────────
// Three of these stand side by side: the directory above, the one you are
// in, and the one under the cursor. They were three separate ListViews with
// three different model shapes — an array, the pane's ListModel, another
// array — which is why a directory moving from one to the next was a
// rebuild rather than a hand-off: no two of them could ever hold the same
// thing, so every step destroyed a column's worth of delegates and built
// them again from data it already had.
//
// Interchangeable now, and each owns a ListModel it syncs IN PLACE. What a
// column is depends only on its `slot`, and nothing about the delegate is
// conditional on it at the top level — role changes rebind properties,
// which is cheap; a conditional `delegate` would rebuild the view, which is
// the thing being removed.
//
//   slot 0  the parent directory   inert, click walks up
//   slot 1  the one you are in     live: cursor, marks, rename, menu
//   slot 2  the one under the cursor   inert, click walks in
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

Item {
  // the terminus window — passed in by whoever makes one. NOT `root`:
  // inside a delegate a property of that name shadowed the window's id
  // and bound to itself (2026-10-08)
  property var term: null
  id: col

  required property int slot
  // The rows this column is showing. A plain array, assigned; the model
  // below follows it without ever being cleared.
  property var rows: []
  // its list, for the frost that carries its rows on under the chrome
  // (the ScrollEdges beside `chrome`)
  readonly property var list: colView

  // ── THE PREVIEW COLUMN ARRIVES, IT DOES NOT APPEAR ──────────────────
  // MEASURED, off a 60fps capture of a step in and a step out:
  //
  //   out  7.3 → 7.4 → 9.8 → 11.7 → 11.85   eased in over three frames
  //   in   7.8 → 7.6 → 7.5 → 7.4 → 7.3 → 13.66   one frame, full strength
  //
  // Walking out, the preview is the listing you just left — it is in hand,
  // settlePreview runs, and previewPane's fade covers it. Walking in, it is
  // a cold read that comes back through previewOut and never touches
  // settlePreview, so the column sat empty for a tenth of a second and then
  // cut in at full strength on a still frame. That single frame is the
  // flicker in the third column on the way in.
  //
  // DRIVEN FROM sync(), not from the preview pipeline. Rows reach this
  // column by several routes — a cache hit, a cold read, a rotation — and
  // hanging the fade off any one of them misses the others. sync() is the
  // only place colModel can change, whoever asked for it.
  property real ink: 1
  opacity: col.ink

  NumberAnimation {
    id: inkFade
    target: col
    property: "ink"
    to: 1
    duration: Zenon.fast
    easing.type: Zenon.travelEase
  }

  // ── THE SLOT THIS COLUMN IS DRAWN IN ────────────────────────────────
  // Not always the slot it IS. `slot` moves the instant millerOrder
  // rotates; the model behind it does not, because onRowsChanged defers
  // sync to the end of the tick — and has to, since at the moment of the
  // rotation the sources for the new slots still describe the old position.
  //
  // Geometry bound to `slot` therefore moved a frame ahead of its own
  // contents. CAUGHT ON A 60fps CAPTURE of a step into ~/.config/btop: for
  // exactly one frame the column that had been the parent was drawn in the
  // preview seat, shifted by the travel offset, still holding the whole of
  // ~ — .cache, .cargo, .claude — at full brightness down the right-hand
  // edge. One frame at 60Hz, three at 180. That is the flash of a directory
  // in the third column on the way in.
  //
  // So the geometry waits for the model rather than racing it: sync() moves
  // this at the end of its own call, and the seat and the rows in it change
  // on the same frame. Everything the eye or the mouse can tell apart reads
  // this — position, width, which column is live, which row is current.
  // `rows` is the exception and must stay on `slot`: it is what drives sync.
  property int drawnSlot: -1
  Component.onCompleted: col.drawnSlot = col.slot
  // Queued here as well as on rows, so a rotation into a slot whose source
  // is the array this column already holds still catches up — callLater
  // coalesces the two into the single sync it would have done anyway.
  onSlotChanged: Qt.callLater(col.sync)

  readonly property bool isLive: col.drawnSlot === 1
  readonly property alias view: colView

  // path -> row, rebuilt with the model. The delegate holds a path so that
  // replacing a row rebinds the item standing there instead of rebuilding
  // it, and something has to turn that path back into an entry — scanning
  // the array per delegate would be quadratic on a big directory.
  property var index: ({})
  property var prevAt: ({})
  function rowAt(p) { const r = col.index["k:" + p]; return r === undefined ? null : r; }

  // COALESCED TO THE END OF THE TICK, and that is not an optimisation.
  //
  // A step changes two things: which slot this column stands in, and what
  // each slot is about. QML re-evaluates a binding the instant one of its
  // dependencies moves, so between those two writes there is a moment when
  // a column has its NEW slot and the OLD rows for it — the column rotating
  // into the preview slot sees the child directory it was showing a moment
  // ago. Syncing there rebuilds to rows nobody asked for, and then rebuilds
  // again when the real ones land: two rebuilds where the answer was
  // already in the column all along.
  //
  // callLater coalesces repeats, so however many times `rows` moves within
  // one step, the model is synced once, against the value it settled on. It
  // runs before the next frame, so nothing is drawn a tick late.
  onRowsChanged: Qt.callLater(col.sync)

  function sync() {
    const next = col.rows || [];
    const wasEmpty = colModel.count === 0;
    const ix = ({});
    for (let i = 0; i < next.length; ++i)
      if (next[i]) ix["k:" + next[i].path] = next[i];
    col.index = ix;

    const m = colModel;
    // where each row stood, for the glide of a reorder in the live
    // column — see Pane.reflow
    if (col.isLive && term.act && term.act.reflowing) {
      const at = ({});
      for (let i = 0; i < m.count; ++i) at["k:" + m.get(i).path] = i;
      // the same rows reordered, not a listing arriving — see syncView
      let kept = 0;
      for (let i = 0; i < next.length; ++i) if (next[i] && at["k:" + next[i].path] !== undefined) ++kept;
      col.prevAt = (next.length > 0 && kept >= next.length * 0.5) ? at : ({});
    }
    const keep = Math.min(m.count, next.length);
    for (let i = 0; i < keep; ++i)
      if (m.get(i).path !== next[i].path) m.set(i, { path: next[i].path });
    for (let i = keep; i < next.length; ++i) m.append({ path: next[i].path });
    if (m.count > next.length) m.remove(next.length, m.count - next.length);

    // LAST, with the rows above and in the same call. This is the line that
    // keeps a column's seat and its contents on the same frame.
    col.drawnSlot = col.slot;

    // Rows landing in an empty PREVIEW column are an arrival and ease in.
    // Anywhere else is full strength: the parent and the middle are where
    // you already are, and a column caught mid-fade by the next step must
    // not carry a part-opacity into its new seat.
    if (col.slot === 2 && wasEmpty && next.length > 0) {
      inkFade.stop();
      col.ink = 0;
      inkFade.start();
    } else if (col.slot !== 2) {
      inkFade.stop();
      col.ink = 1;
    }
  }

  ListModel { id: colModel }

  // the bar's shade on this column once it is scrolled (TopShade.qml)
  TopShade { view: colView; width: col.width }

  // The listing's bar, in the columns too. `current` here is not one number
  // — the leftmost column marks where you came FROM and the live one marks
  // where you are — so the bar asks the same question the delegate does and
  // stands down on the column that has no cursor of its own.
  SelectBar {
    host: term
    view: colView
    index: col.drawnSlot === 0 ? term.parentIndex : term.sel
    rowH: term.rowH
    on: (col.drawnSlot === 0 || col.isLive)
        && !term.cursorOutline(term.act)
    // Only the live column has a cursor that MOVES. The left-hand one marks
    // where you came from — it changes because the columns rotated, not
    // because anything travelled — and during the rotation itself the live
    // one is being handed a new directory, so neither should ease.
    animate: col.isLive && !term.millerAnimation.running && !term.visualOn
  }

  ListView {
    id: colView
    anchors.fill: parent
    clip: true
    model: colModel
    reuseItems: true
    // ── ELASTIC EDGES, THE WAY FINDER HAS THEM ───────────────────
    // Pull past the end and the listing follows with resistance, then
    // settles back. The wheel's band is driven by hand — see
    // the body's ElasticScroll — because Flickable overshoots only for gestures.
    boundsBehavior: Flickable.DragAndOvershootBounds
    boundsMovement: Flickable.FollowBoundsBehavior
    // Only the live column scrolls under the hand; the other two are what
    // is around you, not what you are working in.
    interactive: col.isLive

    delegate: EntryRow {
      host: term
      id: colRow
      required property string path
      required property int index
      readonly property var row: col.rowAt(path)

      width: col.width
      entry: colRow.row
      // the live column is the listing: the filter's letters lit, and a
      // reorder glides (Pane.reflow)
      mark: col.isLive && term.act ? term.act.query : ""
      Glide { id: colGlide; limit: col.height }
      function glideCheck() {
        if (!col.isLive || !term.act || !term.act.reflowing) { colGlide.stop(); return; }
        const was = col.prevAt["k:" + colRow.path];
        if (was === undefined) return;
        colGlide.from(0, (was - colRow.index) * term.rowH);
      }
      onPathChanged: colRow.glideCheck()
      onIndexChanged: colRow.glideCheck()
      current: col.drawnSlot === 0 ? (colRow.index === term.parentIndex)
             : (col.isLive ? (colRow.index === term.sel) : false)
      live: col.isLive
      // ONLY THE LIVE COLUMN OPENS A MENU. EntryRow opens one itself on a
      // right click when `actionable`, and that menu acts on
      // root.currentRow() — never on a hit test. The live column gets away
      // with it because its rows call clickRow() first, which moves the
      // cursor to the row you clicked; the other two navigate instead, so
      // the cursor never moves and the menu came up about whatever was
      // under it in the middle column. Right-clicking a parent directory
      // offered you actions on a completely different file.
      actionable: col.isLive
      dim: col.isLive && !!term.cutSet[colRow.path]
      ticked: col.isLive && !!term.marked[colRow.path]
      // No metadata this narrow, where the name says everything there is
      // room to say — but results are not a directory, and two of them can
      // share a name. See colFoundNarrow.
      showMeta: col.isLive && term.searchMode !== ""
      whereOnly: col.isLive

      onChosen: (right, shift, ctrl) => {
        if (col.isLive) { term.clickRow(colRow.index, right, shift, ctrl); return; }
        // The two inert columns are places you can SEE, and clicking a thing
        // you can see should get you there. Slot 2 enters the previewed
        // directory rather than the row clicked, so a click there can never
        // act on the wrong file.
        if (col.drawnSlot === 0) { if (colRow.row && colRow.row.isDir) term.goTo(colRow.path); return; }
        const r = term.currentRow();
        if (r && r.isDir) term.goTo(r.path);
      }
      onOpened: {
        if (col.isLive) { term.act.sel = colRow.index; term.activate(); return; }
        if (col.drawnSlot === 0) { if (colRow.row && colRow.row.isDir) term.goTo(colRow.path); return; }
        const r = term.currentRow();
        if (r && r.isDir) term.goTo(r.path);
      }
      onTabbed: {
        if (col.drawnSlot === 2) {
          const r = term.currentRow();
          if (r && r.isDir) term.openInNewTab(r.path);
          return;
        }
        if (colRow.row && colRow.row.isDir) term.openInNewTab(colRow.path);
      }
    }
  }

  // ── THE DIRECTORY, AT THE FOOT OF ITS PREVIEW ─────────────────────────
  // A previewed directory was a third copy of a list: parent, current, and
  // this. Its cover and what it holds now sit at the bottom of the column,
  // so the preview says something the two columns beside it cannot.
  //
  // AT THE FOOT, not over the rows. A header above them would push the
  // rows down, and on a step into the directory this column slides into the
  // middle and becomes the listing — the header would have to go and every
  // row would jump up under the cursor. Down here nothing moves: it shows
  // only while the rows leave it room, and fades as the column leaves the
  // preview slot.
  Item {
    id: colFoot
    readonly property var dir: col.drawnSlot === 2 && term.previewKind === "dir"
      ? term.currentRow() : null
    // what the rows leave below them
    readonly property bool room: colView.contentHeight + colFoot.implicitH + 24
      <= col.height
    readonly property real implicitH: colCover.height + 10 + colSum.height
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: 16
    height: colFoot.implicitH
    opacity: (!!colFoot.dir && colFoot.room && (colCover.shown || colSum.text !== ""))
      ? 1 : 0
    visible: colFoot.opacity > 0.01
    Behavior on opacity {
      NumberAnimation { duration: Zenon.fast; easing.type: Zenon.travelEase }
    }

    FolderCover {
      id: colCover
      anchors.top: parent.top
      anchors.horizontalCenter: parent.horizontalCenter
      width: parent.width
      height: colCover.shown ? Math.round(Math.min(parent.width / 1.5, 160)) : 0
      live: term.thumbsOn && !!colFoot.dir
      path: colFoot.dir ? colFoot.dir.path : ""
      stamp: colFoot.dir ? (colFoot.dir.mtime || 0) : 0
      glyph: colFoot.dir ? colFoot.dir.glyph : ""
      ink: term.inkFor(colFoot.dir)
    }

    // What it holds, counted from the rows already shown above, and its
    // size once du has been round — never a guess at it.
    Text {
      id: colSum
      anchors.top: colCover.bottom
      anchors.topMargin: colCover.shown ? 10 : 0
      anchors.left: parent.left
      anchors.right: parent.right
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
      color: Zenon.muted
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Math.round(13 * term.zoom)
      text: {
        if (!colFoot.dir) return "";
        const rows = col.rows || [];
        let files = 0, dirs = 0;
        for (let i = 0; i < rows.length; ++i)
          if (rows[i]) { if (rows[i].isDir) ++dirs; else ++files; }
        const parts = [];
        if (files > 0) parts.push(files + (files === 1 ? " file" : " files"));
        if (dirs > 0) parts.push(dirs + (dirs === 1 ? " directory" : " directories"));
        const walked = term.dirSizes[colFoot.dir.path];
        if (walked !== undefined) parts.push(Terminus.formatSize(walked));
        return parts.join("  \u00b7  ");
      }
    }
  }
}
