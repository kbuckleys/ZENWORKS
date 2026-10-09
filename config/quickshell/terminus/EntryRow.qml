// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ENTRYROW — one row of terminus' listing: a file or a directory, its glyph and
// name, the tree's guides and chevron, git, tags, size and date, rename in
// place, drag and drop.
//
// It was an inline component of TerminusWindow, which kept it where nothing
// else could use it. It lives in its own file so that everything which draws
// a row of files draws terminus' row — plato's file tree (morpheus/FileTree)
// is the second user.
//
// THE HOST. Everything the row reads about the window it sits in — its zoom,
// the git marks, what is being renamed, the column widths, how to open the
// context menu — it reads off `host`. Terminus hands itself (`host: root`),
// so to terminus nothing has changed; another host supplies the same names,
// and the notes below that say "root" mean the host. With `showMeta: false`
// the row is name, tree and git alone, which is how a sidebar wants it.

import QtQuick
import QtQuick.Shapes
import "../morpheus"
import "terminus.js" as Terminus

Item {
  // the window this row belongs to: terminus' own, or any host with the same
  // members (see FileTree's)
  required property var host
  id: entryRow

  property var entry: null
  property bool current: false
  property bool ticked: false
  // size and modified, which only the full-width list has room for
  property bool showMeta: true
  // A row a pending CUT will take away, faded to say so. It was written for
  // the parent and preview columns, which turned out to read worse at 65%
  // than at full strength, and then sat unused — this is the question it was
  // the right answer to all along.
  property bool dim: false
  // the filter being typed: what it matched in the name is lit (terminus.js
  // markMatch — the substring, or the letters a fuzzy match took)
  property string mark: ""
  property color markInk: Zenon.yellow
  property bool clickable: true
  // Whether this row is in THE LISTING THE CURSOR MOVES THROUGH.
  //
  // False in the parent column, in the preview, and in the second pane —
  // all of which draw an EntryRow with a `current` row of their own that the
  // cursor has nothing to do with. Two things hang off it: renaming in place
  // is only ever about the active listing, and so is the sweep. Without it
  // every cursor move animated the parent column's highlighted row as well,
  // which is why the parent directory kept flashing at you.
  property bool live: false
  readonly property bool editable: entryRow.live
  readonly property bool editing:
    host.renaming && entryRow.editable && !!entryRow.entry
    && entryRow.entry.path === host.renamePath
  // ── WHERE THIS ROW SITS IN THE TREE ───────────────────────────
  // All three default to the flat case, so the four other places that
  // draw an EntryRow — the parent column, the preview, the second pane,
  // the picker — are untouched by the list's tree. Only PaneList sets
  // them.
  property int depth: 0
  // Which of the columns to the left of this row carry a line, as a
  // bitmask — see the pane's `flat`. -1 draws nothing, which is the
  // default and so the flat case everywhere else.
  property int guide: -1
  // Whether this row is being drawn inside a tree, which decides the
  // indent a row with no branch of its own still reserves.
  property bool inTree: false
  // A directory the list may open in place. Not simply `entry.isDir`: a
  // row in the parent column is a directory too and has no branch.
  property bool branch: false
  // NOT `opened`, which is already a SIGNAL on this component — the one
  // a double click emits. A property of the same name shadows it, and
  // `entryRow.opened()` then fails with "not a function": that is why
  // double clicking a row did nothing at all.
  property bool expanded: false
  // Known to hold nothing, so there is nothing to disclose.
  property bool hollow: false
  // Air between a tree's marker and the icon after it (user, 2026-10-08:
  // they touched). Inside the disclosure strip, so the guides' columns stay
  // where they were and only the arm to a markerless row grows by it.
  readonly property int twistGap: Math.round(4 * host.zoom)
  signal toggled()

  // Whether a right-click on this row opens the actions menu. False in the
  // panes that are not the active listing — the second pane, and the parent
  // and preview columns — because the menu acts on the ACTIVE selection, so
  // opening it from over there offers a set of verbs aimed at rows you are
  // not pointing at.
  property bool actionable: true

  // The column widths, from the same two sets the headings read — so a cell
  // is under the heading that names it by construction rather than by two
  // lists of numbers being kept in step by hand. Only the LIVE listing grows
  // a WHERE column: results replace the active pane and nothing else.
  // Set on a pane that has room for the WHERE column but not for the
  // numbers beside it — the miller middle column, and nothing else so far.
  property bool whereOnly: false
  readonly property var frac:
    (host.searchMode !== "" && entryRow.live)
      ? (entryRow.whereOnly ? host.colFoundNarrow : host.colFound)
      : host.colPlain

  // The same five columns in pixels — see host.colWidths. `frac` still
  // says WHICH layout; this says how wide each part of it comes out.
  readonly property var cols: host.colWidths(entryRow.width - 24, entryRow.frac)

  // What was held down when it was clicked. The row does not decide what
  // that means — clickRow does — because the same three modifiers have to
  // mean the same three things in all three views.
  signal chosen(bool right, bool shift, bool ctrl)
  signal opened()
  // middle click: a directory in a tab of its own, the way a browser opens
  // a link. Files have nothing sensible to do with it and ignore it.
  signal tabbed()

  // true while a drag hovers THIS directory — see host.dropDirAt
  readonly property bool dropTarget: host.dropDir !== "" && !!entryRow.entry
    && entryRow.entry.isDir && host.dropDir === entryRow.entry.path

  height: host.rowH


  // ── dragging this row out ───────────────────────────────────────
  // The drag itself is NOT on this row any more — it is on root's
  // dragProxy, which host.beginDrag (called from rowDrag below) fills in.
  // A row is a delegate and dies whenever its listing is rebuilt, which
  // is exactly what opening a directory on hold does to the pane the drag
  // came from. See dragProxy for the rest.

  // Resolved once per delegate. It was inkFor(entry) in two bindings — the
  // glyph's colour and the name's — and a function call in a binding cannot
  // be compiled, so every row paid for two interpreted calls on every
  // repaint. The value is already on the row; this just reads it.
  //
  // Through the row's SLOT (inkKey, see terminus.js), so a theme change
  // reaches a row that is already on screen: Zenon[key] is a property read
  // the binding depends on, and it is only re-run when that changes.
  readonly property color rowInk: !entryRow.entry ? Zenon.muted
    : entryRow.entry.inkKey ? Zenon[entryRow.entry.inkKey]
    : entryRow.entry.ink !== undefined ? entryRow.entry.ink : Zenon.muted
  // and the name's, which leaves the kind to the glyph — see nameInkOf
  readonly property color nameInk: !entryRow.entry ? entryRow.rowInk
    : entryRow.entry.nameKey ? Zenon[entryRow.entry.nameKey]
    : entryRow.entry.nameInk !== undefined ? entryRow.entry.nameInk : entryRow.rowInk

  // The CURSOR and a SELECTION are two different things, and they only need
  // to look different once both are on screen.
  //
  // They shared one fill, so opening a directory — where the cursor rests on
  // the first row by default — and then marking files elsewhere left that
  // first row looking selected when it was not in the selection at all.
  //
  // With nothing marked the cursor keeps its filled highlight, because then
  // there is nothing for it to be confused with. The moment a selection
  // exists, a cursor that is not part of it drops to an outline: still
  // plainly where you are, no longer claiming to be one of the chosen.
  // The cursor of a pane the keyboard is NOT in. Still plainly where that
  // side's cursor is; no longer claiming to be a selection. Two filled
  // highlights on screen at once, one of them in a pane no key reaches, read
  // as terminus having chosen something on its own — which is exactly what it
  // was reported as.
  property bool passive: false

  // ── TICKED AND THE CURSOR ARE TWO FACTS, NOT A CHOICE ─────────
  // This carried `!ticked`, on the reading that a ticked row is already
  // marked out and does not need the outline too. It does: the tick is
  // what every OTHER ticked row is wearing. With things selected the
  // SelectBar stands down, so a cursor sitting on one of them had the
  // bar off and the outline suppressed, and the row was indistinguishable
  // from its neighbours — select all and the cursor is simply not there.
  // (A 3px tick survives in the left gutter, outside the row, which is
  // not something anybody finds.)
  //
  // So the two are drawn independently now: the fill says "selected" and
  // the outline says "and you are standing here".
  readonly property bool cursorOnly:
    entryRow.current && (entryRow.passive || host.markedCount > 0)

  // THE ROW'S TAGS, CAPPED. A map lookup by path, exactly as the git
  // gutter does it — no field on the row object, because the note above
  // enrich records what happens when a 4000-row directory pays for one
  // computation per row before first paint.
  //
  // Four dots. Past that they stop being countable at a glance and start
  // eating the name, which is the one thing on the row that cannot be
  // given up. The rest are still on the file and still in the sheet.
  readonly property var tagList: {
    if (!entryRow.entry) return [];
    const all = host.tagMarks[entryRow.entry.path];
    if (!all || all.length === 0) return [];
    return all.length > 4 ? all.slice(0, 4) : all;
  }


  // A light passing across the bar as the row is OPENED — Return, or a
  // double click. The same acknowledgement the grid's tiles have always
  // flared with, so a directory opened from a list and the same directory
  // opened from thumbnails answer the same way.
  //
  // NOT when the cursor arrives on it. That was the first version, and it
  // fired on every j, every k, every click and every pointer drift across
  // the list — a light washing over rows you were only passing through,
  // which reads as the window flashing at the pointer rather than as an
  // answer to anything.
  //
  // Driven by a COUNTER the window bumps, not by `current` changing. The
  // list recycles its delegates, so `current` goes true again whenever a row
  // is reused for the cursor's index — which would replay the sweep on every
  // scroll and every return to a tab.
  Connections {
    target: host
    // ── A LIGHT ACROSS THE ROW THAT WAS OPENED, ON FILES ONLY ───────
    // The distinction is what makes it worth having. Opening a DIRECTORY
    // replaces the entire listing, which is the loudest acknowledgement this
    // window can give and needs no help; opening a FILE hands off to another
    // application, and if that takes a moment there is nothing on screen to
    // say the keypress landed. This says it, on the row it landed on.
    //
    // It was removed wholesale once for playing over every open, directories
    // included, which is exactly the half that did not need it.
    function onOpenPulseChanged() {
      if (entryRow.live && entryRow.current
          && entryRow.entry && !entryRow.entry.isDir) rowSweep.restart();
    }

    // A fuller flash for a row that has just been MADE, so `a` shows you
    // where the new thing went before you have typed a character of its
    // name.
    function onMadePulseChanged() {
      if (entryRow.live && entryRow.current) rowBorn.restart();
    }
  }

  property real bornGlow: 0
  SequentialAnimation {
    id: rowBorn
    NumberAnimation { target: entryRow; property: "bornGlow"; to: 1;
                      duration: 110; easing.type: Easing.OutQuad }
    NumberAnimation { target: entryRow; property: "bornGlow"; to: 0;
                      duration: 520; easing.type: Easing.InQuad }
  }

  Rectangle {
    anchors.fill: parent
    clip: true
    // No hover tint. The cursor is already marked and a selection is already
    // marked; a third highlight that follows the pointer just made the list
    // twitch as it crossed.
    // NO CURSOR FILL. The cursor is the SelectBar beside the view, one
    // rectangle that slides between rows; a fill here is a mark that can
    // only blink. What is left is the tick, which is a property of the ROW
    // rather than of where the cursor happens to be, so it stays with it.
    //
    // EXCEPT WHERE THE CURSOR IS AMONG MARKS. With things selected the
    // SelectBar stands down, and an outline alone on a row the same tint
    // as its neighbours was the cursor you could not find. So on the pane
    // you are keying, the cursor's row is filled harder than the marks
    // around it — a ticked one at more than twice their tint, an unticked
    // one with a wash of its own — and ringed in cyan (below).
    readonly property bool cursorHere: entryRow.cursorOnly && !entryRow.passive
    color: entryRow.ticked
      ? Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, cursorHere ? 0.24 : 0.10)
      : (cursorHere ? Zenon.wash(0.07) : "transparent")

    Rectangle {
      anchors.fill: parent
      visible: entryRow.bornGlow > 0
      color: Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b,
                     0.30 * entryRow.bornGlow)
    }

    // The sweep itself — see the Connections above for when it runs.
    Rectangle {
      id: rowSweepBar
      width: parent.width * 0.45
      height: parent.height
      visible: rowSweep.running
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0.0; color: "transparent" }
        GradientStop {
          position: 0.5
          color: Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.30)
        }
        GradientStop { position: 1.0; color: "transparent" }
      }
    }

    NumberAnimation {
      id: rowSweep
      target: rowSweepBar
      property: "x"
      from: -rowSweepBar.width
      to: rowSweepBar.parent ? rowSweepBar.parent.width : 0
      duration: 340
      easing.type: Easing.OutCubic
    }

    // ── THE OUTLINE THAT REPLACES THE BAR ────────────────────
    // In the window's own cyan on the pane you are keying, because
    // that is what the SelectBar it stands in for is drawn in, and a
    // muted grey over a cyan-tinted tick read as one more row
    // separator. On the PASSIVE pane it stays muted on purpose: that
    // cursor is a memory of where you were, not where you are.
    border.width: entryRow.cursorOnly ? 1 : 0
    border.color: entryRow.passive ? Zenon.border : Zenon.cyan
  }

  // Still tracked, for the drag box: whether the pointer is ON a row is what
  // decides whether a drag moves that row or draws a selection rectangle.
  HoverHandler {
    id: entryHov
    enabled: entryRow.clickable
    onHoveredChanged: {
      if (hovered) host.hoverRow = true;
      else if (host.hoverRow) host.hoverRow = false;
    }
  }

  // The gesture that starts a drag. Artemis' shape: a DragHandler with no
  // target, which sets Drag.active imperatively once it activates — the
  // handler decides WHEN, host.dragProxy decides WHAT.
  DragHandler {
    id: rowDrag
    target: null
    enabled: entryRow.clickable && !!entryRow.entry && !host.modal
             && !host.railHover && !host.railDragging
    onActiveChanged: {
      if (!rowDrag.active) return;
      host.beginDrag(entryRow.entry, 16, entryRow.height / 2);
    }
  }

  // The row's clicks.
  //
  // The drag used to be a DragHandler, and it never once activated — proved
  // with a logging handler across drags of every length and speed, in every
  // view, with and without permission to take the grab from anything. The
  // row lives inside a Flickable, and whatever the arbitration was doing, the
  // handler was not winning it.
  //
  // This MouseArea, on the other hand, demonstrably receives the press: row
  // clicks and ctrl-clicks have always worked. So the drag is started from
  // here instead, by setting Drag.active once the pointer has moved far
  // enough to mean it — with Drag.Automatic that is what hands the gesture to
  // the platform, and no startDrag() call is needed (calling it as well is
  // what once logged "startDrag() drag must be active").
  //
  // preventStealing keeps the ListView from claiming the gesture as a flick
  // half way through. Nothing is lost by it: the rubber band is already
  // disabled while the pointer is on a row.
  MouseArea {
    id: rowMouse
    anchors.fill: parent
    enabled: entryRow.clickable
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

    property bool dragging: rowDrag.active

    // ── THE DOUBLE CLICK IS COUNTED HERE, AND THIS IS WHY ──────────
    // Qt only calls two presses a double click when the second lands
    // within a few pixels of the first — mouseDoubleClickDistance,
    // which is a sensible rule for a checkbox and the wrong one for a
    // row a thousand pixels wide and twenty-four tall. A hand that
    // drifts across one has still hit the same row twice, and being
    // told otherwise reads as the click not registering.
    //
    // Measured on this listing, two presses inside the interval: four
    // pixels apart opens the row, twenty-two does not — and nothing
    // about the second gesture felt different from the first. That is
    // the "sometimes I have to double click twice".
    //
    // So the rule is THE ROW, not the pixel: two presses on this row
    // inside the system's own interval are a double click, however far
    // apart on it they land. The path is compared as well as the time
    // because the view reuses delegates — a recycled row must not
    // inherit the press that belonged to the one before it.
    property real lastPress: 0
    property string lastPath: ""
    // Set on the press that opens, so the release behind it is not also
    // read as a plain click on the row.
    property bool opening: false

    onPressed: (m) => {
      if (m.button !== Qt.LeftButton) return;
      const here = entryRow.entry ? String(entryRow.entry.path || "") : "";
      const now = Date.now();
      if (here !== "" && here === rowMouse.lastPath
          && now - rowMouse.lastPress <= host.doubleMs) {
        rowMouse.lastPress = 0;
        rowMouse.lastPath = "";
        rowMouse.opening = true;
        entryRow.opened();
        return;
      }
      rowMouse.lastPress = now;
      rowMouse.lastPath = here;
    }

    onClicked: (m) => {
      // a gesture that became a drag is not also a click
      if (rowMouse.dragging) return;
      // nor is the release of the press that just opened the row
      if (rowMouse.opening) { rowMouse.opening = false; return; }
      if (m.button === Qt.MiddleButton) { entryRow.tabbed(); return; }
      const right = m.button === Qt.RightButton;
      entryRow.chosen(right,
                      (m.modifiers & Qt.ShiftModifier) !== 0,
                      (m.modifiers & Qt.ControlModifier) !== 0);
      if (right && entryRow.actionable) host.openMenuAt(entryRow, m);
    }
  }

  // The row a menu is open about (HeldRing.qml), as a disk row is.
  HeldRing {
    anchors.fill: parent
    z: 5
    on: !!host && host.sideMenuAt === entryRow
  }

  // Lit while a drag is over this directory, so a drop says where it is
  // going before you let go of it.
  Rectangle {
    anchors.fill: parent
    z: 6
    visible: entryRow.dropTarget
    color: Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.12)
    border.width: 1
    border.color: Zenon.border
    radius: 4
  }

  // NO SEPARATE CURSOR TICK IN THE GUTTER. A 3px bar used to sit here to
  // say where the cursor was among checked rows, because the row itself
  // could not: its outline was suppressed whenever the cursor landed on a
  // row that was itself checked, which left the tick as the only mark and
  // a 3px mark outside the row is not one anybody finds. The outline is
  // drawn in every one of those states now — see cursorOnly — so the
  // gutter bar was the same answer given twice, and the quieter of the two.
  //
  // Every case is still covered: nothing checked and the pane active is
  // the SelectBar; anything checked, or the passive pane, is the outline.

  Row {
    anchors.fill: parent
    leftPadding: 12
    rightPadding: 12

    // the same widths the headings use, so a cell is always under the
    // heading that names it — see host.colWidths
    Item {
      width: entryRow.showMeta ? entryRow.cols.name : (parent.width - 24)
      height: parent.height

      // ── THE DISCLOSURE COLUMN ───────────────────────────────────
      // One strip holding the indent AND the triangle, so a name sits in
      // the same place whether its row is a directory or a file: the arrow's
      // width is reserved at every depth, and only a branch draws one.
      // Without that, files at a given level hung a chevron's width left
      // of their sibling directories.
      //
      // Zero width in a flat list, which is every other view and every
      // other place an EntryRow is drawn.
      Item {
        id: entryTwist
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height
        // ── AND EVERY ROW IN A TREE RESERVES IT ─────────────────
        // `branch || depth > 0` aligned the nested rows and left the top
        // level ragged: a directory there is a branch and took the width, a
        // file beside it was neither and took none, so the two columns of
        // icons sat a chevron apart. Invisible until the guides went in
        // and the rows below lined up exactly.
        //
        // `inTree` is the list saying it is drawing a tree at all, which
        // is the real question — the other four places an EntryRow is
        // drawn leave it false and keep a flat row with no indent.
        width: (entryRow.inTree || entryRow.branch || entryRow.depth > 0)
          ? entryRow.depth * host.treeStep + host.treeArrowW + entryRow.twistGap : 0

        // ── THE LINES THAT JOIN A BRANCH TO ITS PARENT ──────────
        // A nested row used to sit in space at an indent, with nothing
        // saying what it hung from; at two levels down you counted
        // pixels to work out whose child it was.
        //
        // DRAWN, NOT WRITTEN. The archive preview builds the same tree
        // out of box-drawing characters and it reads beautifully there
        // — because its rows are 21px and the glyph very nearly fills
        // them. This listing's rows are 26px, and a 15px `│` in one
        // leaves a gap above and below every single one: the column
        // would come out dashed, which is worse than the nothing it
        // replaced. Rectangles meet exactly, at any row height and any
        // zoom, and cost two nodes per level.
        //
        // Beneath the chevron on purpose — declared first — so a turned
        // triangle sits on top of the line rather than being cut by it.
        Repeater {
          model: entryRow.guide < 0 ? 0 : entryRow.depth
          delegate: Item {
            id: guideCol
            required property int index
            // The column this row actually hangs from, as opposed to one
            // its ancestors merely pass through.
            readonly property bool tail: guideCol.index === entryRow.depth - 1
            // Does the branch in this column keep going below this row?
            // For the tail that is "have I a sibling still to come",
            // which is the bit for this row's OWN depth.
            readonly property bool through: guideCol.tail
              ? (entryRow.guide & (1 << entryRow.depth)) !== 0
              : (entryRow.guide & (1 << (guideCol.index + 1))) !== 0
            // How far the arm reaches, and it depends on what is in the
            // way. A row with a chevron has something already filling
            // the cell at the end of the indent, so the line stops at
            // its near edge rather than running under the triangle. A
            // row without one — a file, or a directory known to be empty —
            // has an empty cell there, and stopping short of it left the
            // line hanging a chevron's width away from the icon it was
            // pointing at. Those rows get the whole indent.
            readonly property int arm: entryChev.visible
              ? host.treeStep - Math.floor(host.treeArrowW / 2)
                + Math.round(2 * host.zoom)
              : host.treeStep + Math.floor(host.treeArrowW / 2) + entryRow.twistGap
            // HALF A PIXEL, so a one-pixel stroke lands ON a pixel row
            // instead of across two and comes out grey and two wide. The
            // plain Rectangles beside it fill the same pixel, so a curve
            // and a straight line in one column meet exactly.
            readonly property real mid: Math.round(guideCol.height / 2) + 0.5
            // Small on purpose: at a 14px step a wide bend eats most of
            // the arm and the corner stops reading as a corner.
            readonly property real bend:
              Math.min(Math.round(3 * host.zoom), guideCol.arm,
                       guideCol.mid - 1)
            // Centred on where a chevron at this depth would sit, so the
            // line runs straight down through the parent's own triangle.
            x: guideCol.index * host.treeStep
               + Math.floor(host.treeArrowW / 2)
            width: guideCol.tail ? guideCol.arm + 1 : 1
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            opacity: entryRow.dim ? 0.3 : 0.6

            // ── A LEVEL PASSED THROUGH, OR A JUNCTION ──────────
            // Full height whenever the branch in this column carries on
            // below this row. There is no corner to round on one of
            // these: the line goes straight down and the arm meets it,
            // which is a T and not a bend.
            Rectangle {
              visible: guideCol.through
              x: 0
              y: 0
              width: 1
              height: guideCol.height
              color: Zenon.muted
            }

            Rectangle {
              visible: guideCol.tail && guideCol.through
              x: 1
              y: Math.round(guideCol.height / 2)
              width: guideCol.arm
              height: 1
              color: Zenon.muted
            }

            // ── THE LAST CHILD, WHERE THE BRANCH TURNS ─────────
            // The only real corner in the drawing, and the one Buck
            // asked to round. A quadratic with its control point exactly
            // on the corner gives the turn a constant, even sweep — an
            // arc of a circle would need its centre computed and looks
            // no different at six pixels.
            //
            // Shapes rather than Rectangles ONLY here: everything else
            // is axis-aligned and a Rectangle is a cheaper node, so a
            // deep tree pays for one path per row that ends a branch and
            // nothing for the rest.
            Shape {
              visible: guideCol.tail && !guideCol.through
              anchors.fill: parent
              preferredRendererType: Shape.CurveRenderer
              ShapePath {
                strokeColor: Zenon.muted
                strokeWidth: 1
                fillColor: "transparent"
                capStyle: ShapePath.FlatCap
                startX: 0.5
                startY: 0
                PathLine { x: 0.5; y: guideCol.mid - guideCol.bend }
                PathQuad {
                  x: 0.5 + guideCol.bend
                  y: guideCol.mid
                  controlX: 0.5
                  controlY: guideCol.mid
                }
                PathLine { x: guideCol.arm + 0.5; y: guideCol.mid }
              }
            }
          }
        }

        Item {
          id: entryChev
          // Hidden for a directory KNOWN to be empty — see host.dirEmpty
          // — at every depth. It was briefly shown on nested ones, on the
          // theory that a directory with no marker reads as a file; it does
          // not, because the guide line already says where it sits and
          // the directory glyph already says what it is. A marker that
          // discloses nothing is the thing worth removing.
          //
          // The strip keeps its width either way, so a name never moves
          // when the answer arrives.
          visible: entryRow.branch && !entryRow.hollow
          anchors.right: parent.right
          anchors.rightMargin: entryRow.twistGap
          anchors.verticalCenter: parent.verticalCenter
          width: host.treeArrowW
          height: parent.height
          opacity: entryRow.dim ? 0.65 : 1

          // ── A NODE ON THE LINE, NOT AN ARROW BESIDE IT ────────
          // nf-fa-circle_o closed and nf-fa-circle open: the same ring,
          // filled in once the branch is showing. One shape changing
          // state rather than two unrelated glyphs swapping.
          //
          // NOT U+F0557, which a Nerd Fonts v2 chart calls a filled
          // circle and v3 does not — in the JetBrainsMono the shell
          // actually loads it is a ring with a connector stub out of its
          // right side. Rendered it to check rather than trusting the
          // chart. F111 is F10C's own filled twin, so the two share
          // their metrics and the marker cannot shift when it opens.
          //
          // NO CROSSFADE BETWEEN THEM, tried and dropped: at fourteen
          // pixels the two rings differ by a few pixels of fill and
          // fading one into the other is motion nobody can see. The
          // turn the triangle used to do was worth animating because
          // it swept a whole glyph; this does not.
          Text {
            anchors.centerIn: parent
            width: host.treeArrowW
            horizontalAlignment: Text.AlignHCenter
            text: entryRow.expanded ? "\uf111" : "\uf10c"
            // ONE COLOUR. The fill is the state; brightening it as well
            // said the same thing twice and made an open branch's
            // marker compete with the name beside it.
            color: Zenon.muted
            font.family: Zenon.glyphMono   // JetBrainsMono's, whatever the shell face (Zenon.glyphFace)
            font.weight: Zenon.weight
            font.pixelSize: Math.round(14 * host.zoom)
          }
        }

        // Its own hit area, a little wider than the glyph: a triangle is a
        // small target and clicking beside it should still work. Clicks
        // here must not reach the row underneath, or opening a branch
        // would also move the cursor onto it.
        MouseArea {
          visible: entryRow.branch
          anchors.right: parent.right
          anchors.rightMargin: entryRow.twistGap - 3
          anchors.verticalCenter: parent.verticalCenter
          width: host.treeArrowW + 6
          height: parent.height
          acceptedButtons: Qt.LeftButton
          onClicked: (m) => { m.accepted = true; entryRow.toggled(); }
        }
      }

      // ── what git thinks of this row ─────────────────────────────
      // A one-character gutter, and only while the mode is on: it takes no
      // width otherwise, so a listing outside a repository looks exactly as
      // it did. The mark is git's own letter where git has one, which makes
      // it free to learn for anyone who has read a `git status`.
      Text {
        id: entryGit
        anchors.left: entryTwist.right
        anchors.verticalCenter: parent.verticalCenter
        readonly property string state: (host.git && entryRow.entry)
          ? (host.gitMarks[entryRow.entry.path] || "") : ""
        visible: host.git
        width: host.git ? Math.round(18 * host.zoom) : 0
        horizontalAlignment: Text.AlignHCenter
        text: Terminus.gitMark(entryGit.state)
        color: host.gitInk(entryGit.state)
        opacity: entryRow.dim ? 0.65 : 1
        font.family: Zenon.glyphMono   // JetBrainsMono's, whatever the shell face (Zenon.glyphFace)
        font.weight: Font.Bold
        // The FILE ICON's size, not something smaller. It was 13 against a
        // 16px name and an 18px glyph, which made the whole gutter read as a
        // footnote — and the one mark that is not a letter disappeared
        // outright. A mark you have to look for twice is not doing the job a
        // gutter exists for.
        font.pixelSize: Math.round(18 * host.zoom)
      }

      Text {
        id: entryGlyph
        anchors.left: entryGit.right
        anchors.verticalCenter: parent.verticalCenter
        // A fixed COLUMN, not the glyph's own width. The nerd font is
        // proportional, so a wide icon and a narrow one ended the glyph at
        // different places and the name followed — which made the gap read
        // as cramped after the wide ones and left the names ragged down the
        // list. A column of constant width fixes both: the icons sit on one
        // centre line and every name starts at the same x.
        width: Math.round(24 * host.zoom)
        horizontalAlignment: Text.AlignHCenter
        text: entryRow.entry ? entryRow.entry.glyph : ""
        color: entryRow.rowInk
        opacity: entryRow.dim ? 0.65 : 1
        font.family: Zenon.glyphFace   // JetBrainsMono's, whatever the shell face (Zenon.glyphFace)
        font.weight: Zenon.weight
        // a step above the name it sits beside, as it always was
        font.pixelSize: Math.round(18 * host.zoom)
      }

      // ── the bookmark, beside the name ─────────────────────────
      // So that `b b` is a key you can aim. The toggle goes both ways and
      // the only way to know which way it will go was to open the sidebar
      // and read the list; now the row says so itself. Same glyph the
      // sidebar lists it under, because it is the same fact.
      Text {
        id: entryBookmark
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        visible: !!entryRow.entry && host.isBookmarked(entryRow.entry.path)
        text: "\uF02E"
        color: Zenon.sand
        opacity: entryRow.dim ? 0.65 : 1
        font.family: Zenon.glyphFace   // JetBrainsMono's, whatever the shell face (Zenon.glyphFace)
        font.weight: Zenon.weight
        font.pixelSize: Math.round(13 * host.zoom)
      }

      // ── the tags, beside the name ────────────────────────────
      // Dots rather than words, and on the RIGHT, which is where Finder
      // puts them and where this row already keeps its bookmark: a tag is
      // a property OF the file, read after you have read which file it is.
      // Words would cost the name its room on every tagged row; a colour
      // is the whole of what a tag says at a glance, and the sheet has
      // the names.
      Row {
        id: entryTags
        anchors.right: entryBookmark.visible ? entryBookmark.left : parent.right
        anchors.rightMargin: entryBookmark.visible ? 7 : 12
        anchors.verticalCenter: parent.verticalCenter
        // Room between them. At three pixels two tags read as one wide
        // mark rather than as two, which is the one thing the row has to
        // get right — the count is half of what a glance takes from here.
        spacing: Math.max(4, Math.round(7 * host.zoom))
        visible: entryRow.tagList.length > 0
        opacity: entryRow.dim ? 0.65 : 1

        Repeater {
          model: entryRow.tagList
          // THE SIDEBAR'S OWN MARK. A dot said "tagged, in this colour"
          // and a label glyph says the same thing while also matching
          // what the row is listed under — one shape for one idea, in
          // the three places tags appear.
          delegate: Text {
            required property var modelData
            anchors.verticalCenter: parent.verticalCenter
            text: "\uF02B"
            color: host.tagInk(modelData)
            font.family: Zenon.glyphFace   // JetBrainsMono's, whatever the shell face (Zenon.glyphFace)
            font.weight: Zenon.weight
            font.pixelSize: Math.round(12 * host.zoom)
          }
        }
      }

      Text {
        id: entryName
        anchors.left: entryGlyph.right
        // The glyph column already centres the icon with air either side;
        // 12 on top of that left a gap wider than the icon (user, 2026-10-09)
        anchors.leftMargin: Math.round(6 * host.zoom)
        anchors.right: entryTags.visible ? entryTags.left
          : (entryBookmark.visible ? entryBookmark.left : parent.right)
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        visible: !entryRow.editing
        // plain unless a filter has something to light, so the common row
        // pays for no markup
        textFormat: entryRow.mark !== "" ? Text.StyledText : Text.PlainText
        text: !entryRow.entry ? ""
          : entryRow.mark !== ""
            ? Terminus.markMatch(entryRow.entry.name, entryRow.mark, entryRow.markInk) + (entryRow.entry.isLink ? " →" : "")
            : entryRow.entry.name + (entryRow.entry.isLink ? " →" : "")
        elide: Text.ElideMiddle
        color: entryRow.nameInk
        // The leading dot already says a file is hidden. Dimming it as well
        // said it twice and made half of ~ harder to read for nothing.
        opacity: entryRow.dim ? 0.65 : 1
        font.family: Zenon.face
        // the same weight as every other name: the cursor's ground already
        // says which one it is, and bold only made the name jump wider
        font.weight: Font.Medium
        // 16, the same number the grid's tile labels and the preview pane's
        // metadata rows use. Three different places were showing the same
        // filename at three different sizes, and a window reads as one thing
        // or it does not.
        font.pixelSize: Math.round(16 * host.zoom)
      }

      // ── renaming, IN PLACE ──────────────────────────────────────
      // The name is edited where the name is. A dialog for this asked you to
      // read the old name off a card that was covering the list it came
      // from, and answered a question you could see the answer to.
      //
      // The STEM is selected and the extension is not: renaming is almost
      // always about the name and almost never about the type, and a
      // selection that includes ".jpg" makes the common case start with an
      // arrow key.
      //
      // BEHIND A LOADER, and that is a performance change rather than a
      // structural one. A TextInput is among the heaviest items Qt Quick
      // has — an input-method bridge, a selection model, a cursor delegate —
      // and with reuseItems and a cacheBuffer this deep a directory keeps
      // upwards of a hundred delegates alive, every one of which was
      // carrying an edit field and its retry Timer for a rename that only
      // ever happens on one row. Now the field exists while there is
      // something to type into, which is also why the setup moved from
      // onVisibleChanged to Component.onCompleted: being created IS the
      // event.
      // ringed while it takes keys, so the one row being named stands out
      EditRing {
        target: entryEditBox
        on: entryRow.editing
        fontPx: Math.round(16 * host.zoom)
      }
      Loader {
        id: entryEditBox
        anchors.left: entryGlyph.right
        anchors.leftMargin: Math.round(6 * host.zoom)
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        height: entryRow.height
        active: entryRow.editing
        sourceComponent: entryEditField
      }

      Component {
        id: entryEditField

        TextInput {
        id: entryEdit

        cursorDelegate: Caret { field: entryEdit }
        anchors.fill: parent
        verticalAlignment: Text.AlignVCenter
        color: Zenon.white
        selectionColor: Zenon.selBg
        selectedTextColor: Zenon.white
        font.family: Zenon.face
        font.weight: Font.Bold
        font.pixelSize: Math.round(16 * host.zoom)
        clip: true

        Component.onCompleted: {
          entryEdit.hadFocus = false;
          // blank for something just made — see the note on the tile's field
          const madeNow = host.freshPath !== "" && entryRow.entry
            && entryRow.entry.path === host.freshPath;
          entryEdit.text = madeNow ? "" : (entryRow.entry ? entryRow.entry.name : "");
          if (!madeNow) {
            const stem = Terminus.stem(entryEdit.text);
            entryEdit.select(0, stem.length > 0 ? stem.length : entryEdit.text.length);
          }
          entryEdit.forceActiveFocus();
          editClaim.tries = 0;
          editClaim.restart();
        }

        // ASK UNTIL IT HAS IT, the same as the window's own focusClaim.
        //
        // A rename opened by `r` is asking for focus on an item that has
        // been on screen for a while, and that works first time. Creating
        // something does not: the row is built by the listing that arrives
        // after the file is made, so the forceActiveFocus above lands on an
        // item the scene has not finished placing and is dropped. The field
        // was visible and the keyboard was still in the listing, which is
        // exactly "it makes the file and will not let me name it".
        Timer {
          id: editClaim
          interval: 40
          repeat: true
          property int tries: 0
          onTriggered: {
            if (!entryRow.editing || entryEdit.activeFocus
                || editClaim.tries++ > 12) {
              editClaim.stop();
              return;
            }
            entryEdit.forceActiveFocus();
          }
        }

        Keys.onReturnPressed: (e) => {
          e.accepted = true;
          host.commitRename(entryRow.entry, entryEdit.text);
        }
        Keys.onEnterPressed: (e) => {
          e.accepted = true;
          host.commitRename(entryRow.entry, entryEdit.text);
        }
        Keys.onEscapePressed: (e) => { e.accepted = true; host.endRename(true); }
        // Clicking away is not an answer either way, so it is a cancel — the
        // same as Escape, and never a silent rename you did not ask for. But
        // only once the field has actually HAD the keyboard, or the retry
        // above would be cancelling the very edit it is trying to open; and
        // not when the whole window goes to the background (alt-tab), which
        // takes activeFocus too — the edit is waiting when you come back.
        onActiveFocusChanged: {
          if (activeFocus) { entryEdit.hadFocus = true; return; }
          // Only once it has STOPPED asking. editClaim runs until the field
          // has the keyboard or it gives up; a loss while it is still trying
          // is the scene settling, not you clicking away.
          if (entryRow.editing && entryEdit.hadFocus && !editClaim.running
              && entryEdit.Window.active)
            host.endRename(false);
        }
        // Nothing to reset per edit any more — the field IS the edit now,
        // and it is destroyed with it. It used to be one field per recycled
        // row, which is why this had to be cleared by hand or a row would
        // carry "I once had focus" into the next file it was reused for and
        // cancel the moment anything blinked.
        property bool hadFocus: false
        }
      }
    }

    // WHERE it was found, and only while there is a search to have found it.
    //
    // A result carries its whole path and the NAME column shows the last
    // component of it, which for a search across a tree is the half you
    // cannot act on: two files called notes.md are the same row twice until
    // this column says which is which. Written relative to the directory the
    // search started in — see Terminus.whereOf — because the absolute path
    // is mostly a prefix repeated down every row.
    Text {
      width: entryRow.cols.where
      height: parent.height
      visible: entryRow.showMeta && entryRow.frac.where > 0
      verticalAlignment: Text.AlignVCenter
      text: entryRow.entry && entryRow.frac.where > 0
        ? Terminus.whereOf(entryRow.entry.path, host.cwd) : ""
      // The FRONT is what repeats. Two results deep in the same tree differ
      // at the end of the path, so eliding the tail would leave two rows
      // reading the same and eliding the head keeps them apart.
      elide: Text.ElideLeft
      color: Zenon.muted
      opacity: entryRow.dim ? 0.65 : 1
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Math.round(13 * host.zoom)
    }

    // What KIND of thing it is, under the heading that sorts by it. The word
    // rather than the extension: the sort groups by kind, so the column has
    // to show the thing being grouped or the arrangement looks arbitrary.
    Text {
      width: entryRow.cols.kind
      height: parent.height
      visible: entryRow.showMeta && entryRow.frac.kind > 0
      // Right, so the kinds stack against the size column rather than
      // ragging out from the name's edge. The padding keeps them off
      // it — the sizes beside them are right-aligned too, and two
      // right-aligned columns touching read as one.
      horizontalAlignment: Text.AlignRight
      rightPadding: Math.round(14 * host.zoom)
      verticalAlignment: Text.AlignVCenter
      // EXCEPT A DIRECTORY'S. "directory" thirty rows running was the loudest
      // thing in the column and told you nothing the glyph and the sort had
      // not: directories come first and wear a directory. Left blank, the column
      // speaks only where the answer varies. Here and not in host.kindOf,
      // whose word the sort and the info sheet still want.
      text: (entryRow.entry && !entryRow.entry.isDir)
        ? host.kindOf(entryRow.entry) : ""
      elide: Text.ElideRight
      color: Zenon.muted
      opacity: entryRow.dim ? 0.65 : 1
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Math.round(13 * host.zoom)
    }

    // ── the size cell, and in the usage view its bar ────────────
    //
    // The bar itself lives in UsageBar.qml, shared with the disks down the
    // sidebar — the same measurement drawn the same way in both halves of
    // the window. What is decided here is only what this column measures
    // against, and how far along it this row sits. A share too narrow to reach
    // the figure, and an edge mark that would cut through it, are UsageBar's
    // to leave undrawn, not this cell's.
    Item {
      id: sizeCell
      width: entryRow.cols.size
      height: parent.height
      visible: entryRow.showMeta && entryRow.frac.size > 0

      readonly property bool on: host.usage && !!entryRow.entry
      // ONE call, not three. usageOf was asked once by `frac` and twice by
      // `biggest`, and it reads host.dirSizes — so the read has to stay a
      // property read for the dependency, but it only has to happen once.
      readonly property real bytes:
        sizeCell.on ? host.usageOf(entryRow.entry) : 0
      // This row's share of the biggest thing here. 0 before anything is
      // measured, which draws an empty track rather than a lie.
      // WHICH LISTING THIS ROW IS ONE OF. `live` is already the window's
      // word for "in the listing the cursor moves through", so the second
      // pane's rows measure against the second pane's own contents. The
      // parent and preview columns draw no bar at all — showMeta is false
      // there — so they need no third answer.
      readonly property real ceiling:
        entryRow.live ? host.usageMax : host.otherUsageMax
      //
      // ON A LOG SCALE, from a kibibyte up to the ceiling. Linear, one big
      // directory flattened everything else: in home, .local at 742 GiB left
      // every other bar under 3% — thirty-eight empty tracks and one full
      // one, which is a column that answers only "which is biggest". Sizes on
      // a disk span nine orders of magnitude, so length is given to the
      // ORDER and the figure written on the bar keeps the exact amount. A
      // kibibyte is the floor because below it nothing is worth a length.
      readonly property real frac: {
        if (!sizeCell.on || sizeCell.ceiling <= 0 || sizeCell.bytes <= 0) return 0;
        const lo = Math.log(1024);
        const top = Math.log(Math.max(sizeCell.ceiling, 2048)) - lo;
        return Math.max(0, Math.log(Math.max(sizeCell.bytes, 1)) - lo) / top;
      }
      // The row the mode was opened to find. Warmer, so "which is the big
      // one" is answered before any bar has been compared to any other.
      readonly property bool biggest: sizeCell.on && sizeCell.ceiling > 0
        && sizeCell.bytes >= sizeCell.ceiling
      // Measured, or still being walked. An empty track says "asked, no
      // answer yet"; no track at all would say "not part of this".
      readonly property bool pending: sizeCell.on && !!entryRow.entry
        && entryRow.entry.isDir && host.dirSizes[entryRow.entry.path] === undefined

      UsageBar {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height - 9
        // outside the usage mode this column is a figure, not a proportion
        bars: sizeCell.on
        // grows leftwards, so it ends where the number ends and the two
        // share an edge rather than merely overlapping
        fromRight: true
        frac: sizeCell.frac
        pending: sizeCell.pending
        accent: sizeCell.biggest ? Zenon.sand : Zenon.cyan
        // Brighter in the usage view than the muted grey it uses elsewhere,
        // because grey on a tinted band is the one place that colour stops
        // being readable.
        ink: sizeCell.on
          ? (sizeCell.biggest ? Zenon.sand : Zenon.white) : Zenon.muted
        fontSize: Math.round(14 * host.zoom)
        fontWeight: sizeCell.on ? Font.Medium : Font.Normal
        label: {
          const e = entryRow.entry;
          if (!e) return "";
          if (!e.isDir) return host.sizeTextOf(e);
          // a dash until someone asks, and the real number afterwards
          const walked = host.dirSizes[e.path];
          return walked === undefined ? "\u2014" : Terminus.formatSize(walked);
        }
      }
    }

    Text {
      width: entryRow.cols.time
      height: parent.height
      visible: entryRow.showMeta && entryRow.frac.time > 0
      // Left. It is the last column, so right-aligning it pinned the
      // times to the window's edge with the ragged side facing in.
      horizontalAlignment: Text.AlignLeft
      leftPadding: Math.round(14 * host.zoom)
      verticalAlignment: Text.AlignVCenter
      text: entryRow.entry ? host.whenOf(entryRow.entry) : ""
      color: Zenon.muted
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Math.round(14 * host.zoom)
    }
  }
}
