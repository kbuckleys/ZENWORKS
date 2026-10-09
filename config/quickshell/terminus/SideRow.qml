// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// One row of the sidebar: a bookmark or a disk. The disk half adds the mount
// switch on the right, because "go there" and "make it possible to go there"
// are two different actions and a single click cannot be both.
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
  id: sideRow
  property string label: ""
  property string detail: ""
  property string glyph: ""
  // A COLOUR OF ITS OWN, when the row has one to give. Bookmarks and disks
  // do not — their glyph says what KIND of thing the row is and the muted
  // grey is right for that — but a tag's colour IS the tag, and a row that
  // drew it grey was throwing away the one thing that tells two of them
  // apart at a glance. Unset means the old behaviour, unchanged.
  property color ink: "transparent"
  // Whether right-clicking this row means anything. Off for bookmarks and
  // disks, which are places rather than definitions.
  property bool editable: false
  property bool active: false
  property bool mounted: false
  property bool showMount: false
  // Taken off the list from the row itself, by the cross that shows on
  // hover. ONLY by the cross: middle click used to remove a bookmark too,
  // which put "delete this" on the button every other list here uses for
  // "open this in a tab" — see `tabbed`.
  property bool showRemove: false

  // 0..1 for a mounted disk, -1 when there is nothing to show a gauge from
  property real used: -1

  signal chosen()
  signal removed()
  // Middle click: this place, in a tab of its own — the gesture the
  // listing, the grid and the crumbs already answer the same way.
  signal tabbed()
  signal toggledMount()
  signal edited()
  // A row with a menu of its own — a disk. Where in the row it was asked
  // for, so the menu opens under the pointer.
  property bool hasMenu: false
  signal menuAsked(real x, real y)

  // ── CARRYING ONE UP OR DOWN THE LIST ────────────────────────────────
  // Its place among the bookmarks, or -1 for a row that is not one — the
  // disks and the two fixed entries are not in an order anybody chose, so
  // they do not move.
  property int slot: -1

  readonly property bool dragging: sideDrag.active
  // Moved by a TRANSFORM rather than by y: the rows live in a Column and a
  // Column owns its children's y, so setting it would be overwritten on the
  // next layout pass. A transform moves the pixels and leaves the layout
  // believing nothing happened, which is exactly the lie wanted here.
  // A BINDING, never written to. Assigned imperatively it could be left
  // stranded: a hot reload during a drag orphaned the row off-screen with
  // the drop line parked behind it, and the sidebar read as having lost a
  // bookmark. Off `active`, the moment the grab ends — however it ends — the
  // row is home.
  // Held to the bookmarks, give or take a few pixels: carried off past
  // the first or the last, the row stops with the list instead of
  // wandering over the tags and disks with nothing there to drop into.
  readonly property real dragY: {
    if (!sideRow.dragging) return 0;
    const h = sideRow.height;
    const lo = -sideRow.slot * h - 6;
    const hi = (term.bookmarks.length - 1 - sideRow.slot) * h + 6;
    return Math.max(lo, Math.min(hi, sideDrag.translation.y));
  }

  // ── THE OTHERS MAKE WAY ─────────────────────────────────────────────
  // While one is carried, the bookmarks between where it was and where it
  // would land slide over by its height, live, so the gap it would drop
  // into is open under it — rather than a line drawn where it would go.
  // Still only pixels: the order is committed on release (see the
  // handler), as the tab strip does it. A binding, like dragY, so nothing
  // can be left stranded: no drag, no offset.
  readonly property real makeWay: {
    const f = term.markDragFrom, t = term.markDragTo, i = sideRow.slot;
    if (f < 0 || i < 0 || i === f) return 0;
    const dest = t > f ? t - 1 : t;
    if (i > f && i <= dest) return -term.markDragH;
    if (i < f && i >= dest) return term.markDragH;
    return 0;
  }
  property real shift: sideRow.makeWay
  Behavior on shift {
    enabled: term.markDragFrom >= 0
    NumberAnimation { duration: Zenon.fast; easing.type: Easing.OutCubic }
  }
  // the carried row is lifted: a touch bigger while it is in the hand
  property real lift: sideRow.dragging ? 1 : 0
  Behavior on lift { NumberAnimation { duration: Zenon.fast; easing.type: Easing.OutCubic } }
  // and, dropped, glides the last few pixels into its slot
  property real settleY: 0
  // where the carried row was last drawn, for the drop
  property real heldY: 0
  ParallelAnimation {
    id: settleIn
    NumberAnimation { target: sideRow; property: "settleY"; to: 0; duration: Zenon.fast; easing.type: Easing.OutCubic }
    NumberAnimation { target: sideRow; property: "lift"; from: 1; to: 0; duration: Zenon.fast; easing.type: Easing.OutCubic }
  }
  function settleFrom(dy) { settleIn.stop(); sideRow.settleY = dy; settleIn.start(); }

  transform: [
    Translate { y: sideRow.dragY + sideRow.shift + sideRow.settleY },
    Scale {
      origin.x: sideRow.width / 2
      origin.y: sideRow.height / 2
      xScale: 1 + 0.035 * Math.max(sideRow.swell, sideRow.lift)
      yScale: 1 + 0.035 * Math.max(sideRow.swell, sideRow.lift)
    }
  ]
  z: sideRow.dragging || sideRow.settleY !== 0 ? 2 : (sideRow.swell > 0 ? 1 : 0)
  // ── A CARD IN THE HAND ──────────────────────────────────────────────
  // A row has no ground of its own, so carried over the others its text
  // lay on top of theirs, and the two read as one smear. Lifted, it is a
  // solid card, so what slides under it stays under it.
  Rectangle {
    anchors.fill: parent
    anchors.leftMargin: 4
    anchors.rightMargin: 4
    visible: sideRow.lift > 0.01
    opacity: sideRow.lift
    radius: 4
    color: Qt.rgba(Zenon.layerBg.r, Zenon.layerBg.g, Zenon.layerBg.b, 1)
    border.width: 1
    border.color: Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.55)
  }

  // The colour a gauge is drawn in. Nearly full is worth saying in colour
  // rather than making you read the number and do the arithmetic.
  readonly property color gaugeInk: sideRow.used > 0.95 ? Zenon.red
    : (sideRow.used > 0.85 ? Zenon.yellow : Zenon.cyan)

  // A gauged row is two lines — the name, and the band with the figure in
  // it — so it is taller. A bookmark has one line and keeps the old height:
  // the sidebar should not grow by a third to hold rows with nothing to
  // measure.
  height: sideRow.used >= 0 ? 46 : 32

  // NO FILL AND NO HOVER TINT. The cursor is sideBar, one rectangle the
  // column slides between rows — a fill here is a mark that can only blink.
  // And the hover never coloured anything after the listing's argument was
  // applied here: the cursor is already marked, and a third highlight
  // following the pointer made the list twitch as it crossed. The hover is
  // still WATCHED, because it is what reveals the remove cross.
  //
  // THE ACTIVE ROW ANNOUNCES ITSELF rather than the bar hunting for it. The
  // rows are of two heights in two Repeaters under a Column, so there is no
  // index the bar could count with; the one row that knows it is the one is
  // the row itself.
  // AND IT HAS TO LET GO AGAIN. This only ever CLAIMED the cursor, never
  // released it, so the bar stayed on whatever was last active — walk out
  // of a collection into an ordinary directory and it sat there marking a
  // collection you were no longer in. It went unnoticed while bookmarks
  // were the only rows that lit, because navigating between them moved it
  // along; a collection you leave for somewhere unlisted has nothing to
  // hand it to.
  onActiveChanged: {
    if (sideRow.active) { term.armSideSlide(); term.sideAt = sideRow; }
    else if (term.sideAt === sideRow) term.sideAt = null;
  }
  Component.onCompleted: {
    if (sideRow.active) term.sideAt = sideRow;
    // the row just dropped here, rebuilt by the move: in from the hand
    const m = term.markSettle;
    if (m && sideRow.slot >= 0 && sideRow.slot === m.slot) {
      term.markSettle = null;
      sideRow.settleFrom(m.dy);
    }
  }

  // AND IT HAS TO LET GO WHEN IT IS DESTROYED, which is not the same
  // event as going inactive and is the one that actually bit.
  //
  // Opening a collection rewrites the collections list — it records the
  // view it opened with — so the Repeater rebuilds every row underneath
  // it. The row holding the cursor was destroyed with sideAt still
  // pointing at it, and reading `.visible` off a destroyed QObject
  // THROWS rather than returning undefined: the bar's own visible
  // binding died with it, so the cursor vanished from a sidebar whose
  // row was perfectly, correctly active.
  Component.onDestruction: {
    if (term.sideAt === sideRow) term.sideAt = null;
    if (term.sideMenuAt === sideRow) term.sideMenuAt = null;
  }

  // A cyan bar down the left of the active row stood here, mirroring the
  // mark the listing puts on a selected file. The fill says it already,
  // and now that the fill starts exactly on the heading's rule the bar
  // was a second, shorter, differently-aligned edge inside it.
  HoverHandler { id: sideHover }

  // ── A DIRECTORY YOU CAN DROP ONTO ──────────────────────────────────────
  // The directory this row stands for, when it stands for one: a bookmark,
  // a mounted disk. Dropping onto it asks the same Move / Copy question a
  // directory in the listing asks, and offers to bookmark what was carried
  // when that is something that could become a bookmark. Tags and
  // collections are not places, so they have none, and a drop on them
  // falls through to the sidebar's own "bookmark this".
  property string dropPath: ""
  // the trash's row: what is dropped on it is trashed, not moved in
  property bool trashDrop: false

  DropArea {
    id: rowDrop
    anchors.fill: parent
    enabled: sideRow.dropPath !== "" || sideRow.trashDrop
    onDropped: (d) => {
      const urls = term.urlsFrom(d);
      if (sideRow.trashDrop) { term.trashDropped(urls); return; }
      const fresh = term.localPaths(urls).filter((p) => term.bookmarks.indexOf(p) < 0);
      term.dropUris(urls, d.proposedAction, sideRow.dropPath, sideRow, d.x, d.y,
        fresh.length === 0 ? []
          : [{ label: "Add to bookmarks", act: () => term.bookmarkDropped(urls) }]);
    }
  }

  // ── A ROW WITH SOMETHING HELD OVER IT SWELLS ────────────────────
  // Lit like a directory in the listing that a drop is about to go into, and
  // more: the whole row grows a little, label and all, and its outline
  // breathes in cyan for as long as the drop is on offer, so where it will
  // land is seen without hunting for a faint tint.
  property real swell: rowDrop.containsDrag ? 1 : 0
  Behavior on swell { NumberAnimation { duration: Zenon.fast; easing.type: Easing.OutCubic } }
  property real breath: 0.35
  SequentialAnimation on breath {
    running: rowDrop.containsDrag
    loops: Animation.Infinite
    NumberAnimation { to: 1; duration: 520; easing.type: Easing.InOutSine }
    NumberAnimation { to: 0.35; duration: 520; easing.type: Easing.InOutSine }
  }
  Rectangle {
    anchors.fill: parent
    anchors.leftMargin: 4
    anchors.rightMargin: 4
    visible: sideRow.swell > 0.01
    opacity: sideRow.swell
    color: Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.14)
    border.width: 1
    border.color: Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, sideRow.breath)
    radius: 4
  }

  // ── THE ROW A MENU WAS ASKED OF ─────────────────────────────────────
  // Outlined while its menu is open, so which disk the menu is about is
  // seen at a glance. Not the cursor: the bar stays where you are, and a
  // right click is a question about a row, not a step onto it.
  property real held: term.sideMenuAt === sideRow ? 1 : 0
  Behavior on held { NumberAnimation { duration: Zenon.fast; easing.type: Easing.OutCubic } }
  Rectangle {
    anchors.fill: parent
    anchors.leftMargin: 4
    anchors.rightMargin: 4
    visible: sideRow.held > 0.01 && sideRow.swell <= 0.01
    opacity: sideRow.held
    color: Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.08)
    border.width: 1
    border.color: Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.6)
    radius: 4
  }

  // ── WHERE IT WOULD LAND ─────────────────────────────────────────────
  // An INSERTION POINT, 0..n, not a row index: there are n rows and n+1
  // places to put one, and the place after the last row is a real answer
  // — carried down past the bookmarks into the disks, it means "at the
  // end". Shown by the others making way (see makeWay), not by a line.

  DragHandler {
    id: sideDrag
    enabled: sideRow.slot >= 0
    // Nothing to move on our behalf — the transform above is the movement,
    // so the handler only has to report the distance.
    target: null
    xAxis.enabled: false

    onActiveChanged: {
      if (sideDrag.active) {
        settleIn.stop();
        sideRow.settleY = 0;
        sideRow.heldY = 0;
        term.markSettle = null;
        term.markDragH = sideRow.height;
        term.markDragFrom = sideRow.slot;
        term.markDragTo = sideRow.slot;
        return;
      }
      // The line is drawn BEFORE row `to`; pulling this row out first
      // shifts everything after it down one, so a drop below its old home
      // lands one short unless that is taken off here.
      const at = term.markDragTo;
      const from = sideRow.slot;
      const to = at > from ? at - 1 : at;
      const dest = Math.max(0, Math.min(term.bookmarks.length - 1, to));
      if (at < 0) return;
      // where the row was let go, against the slot it is going to
      // (dragY is already 0 here, the grab being over: the last one seen)
      const dy = sideRow.heldY - (dest - from) * sideRow.height;
      if (dest === from) {
        // back where it came from: no rebuild, so it glides home itself
        term.markDragFrom = -1;
        term.markDragTo = -1;
        sideRow.settleFrom(dy);
        return;
      }
      // LATER, not here. The move rebuilds the rows, this one included, and
      // destroying a row from inside its own handler's signal left the
      // sidebar half-drawn for a frame or two. The others stay parted until
      // then, and the drag is ended BEFORE the move, so the rebuilt rows
      // are not handed the old drag's offsets.
      term.markSettle = { slot: dest, dy: dy };
      Qt.callLater(() => {
        term.markDragFrom = -1;
        term.markDragTo = -1;
        // LAST: the rebuild destroys this row, and `root` with its
        // context, so nothing may follow it here. The rebuilt row clears
        // markSettle as it takes it up.
        term.moveBookmark(from, to, true);
      });
    }

    onTranslationChanged: {
      if (!sideDrag.active) return;
      // The row it would take, from how far it has come, held to the
      // bookmarks (dragY is clamped to them, and so is this); said as an
      // insertion point, which below its old home is one past that row.
      sideRow.heldY = sideRow.dragY;
      const f = sideRow.slot;
      const dest = Math.max(0, Math.min(term.bookmarks.length - 1,
        f + Math.round(sideRow.dragY / Math.max(1, sideRow.height))));
      term.markDragTo = dest > f ? dest + 1 : dest;
    }
  }

  MouseArea {
    anchors.fill: parent
    // BELOW the drag handler, which claims the press first once it decides
    // the pointer is travelling. A click that never travelled still lands
    // here, so tapping a bookmark goes there as it always did.
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    onClicked: (m) => {
      if (sideRow.dragging) return;
      if (m.button === Qt.MiddleButton) { sideRow.tabbed(); return; }
      // Right click OPENS it for editing, where the row has an editor to
      // open — a collection is the only kind of sidebar row that is a
      // thing you wrote rather than a place that exists. Rows without one
      // fall through to being chosen, so the button is never dead.
      if (m.button === Qt.RightButton) {
        if (sideRow.hasMenu) { sideRow.menuAsked(m.x, m.y); return; }
        if (sideRow.editable) { sideRow.edited(); return; }
        sideRow.chosen();
        return;
      }
      sideRow.chosen();
    }
  }

  Text {
    id: sideGlyph
    anchors.left: parent.left
    anchors.leftMargin: 12
    anchors.verticalCenter: parent.verticalCenter
    // A fixed column, for the same reason the listing's glyphs got one: the
    // nerd font is proportional, so a wide icon and a narrow one ended their
    // labels at different places and the names came out ragged.
    width: 20
    horizontalAlignment: Text.AlignHCenter
    text: sideRow.glyph
    // The row's own colour wins even while active: the cyan is there to
    // say "this is where you are", and the label beside it already says
    // that. Taking a tag's colour away to repeat it would lose more than
    // it tells.
    color: sideRow.ink.a > 0 ? sideRow.ink
      : (sideRow.active ? Zenon.cyan : Zenon.muted)
    font.family: Zenon.face
    font.weight: Zenon.weight
    font.pixelSize: Zenon.px(15)
  }

  // The name and the figure are TWO items, not one string.
  //
  // They were concatenated — "nvme0n1p8  855.7G free" in a single Text — so
  // a long disk label pushed the figure off the end and elided away the one
  // part you were looking for. Separated, the name gives up its own width
  // and the figure always survives.
  Text {
    id: sideLabel
    anchors.left: sideGlyph.right
    anchors.leftMargin: 8
    anchors.right: sideDetail.visible ? sideDetail.left
      : (mountBtn.visible ? mountBtn.left
        : (removeBtn.visible ? removeBtn.left : sideRow.right))
    anchors.rightMargin: 8
    anchors.verticalCenter: parent.verticalCenter
    // Above the band rather than centred on the row, once there is a band.
    anchors.verticalCenterOffset: sideRow.used >= 0 ? -11 : 0
    text: sideRow.label
    elide: Text.ElideMiddle
    // THE TITLE SAYS IT TOO, not just the bar beside it. White against
    // keyInk is a difference you have to go looking for on a row whose
    // glyph is already carrying a colour of its own — so the active row
    // takes that colour for its name as well, and the one you are
    // looking at is the one that is lit.
    color: sideRow.active
      ? (sideRow.ink.a > 0 ? sideRow.ink : Zenon.white)
      : Zenon.keyInk
    font.weight: sideRow.active ? Font.DemiBold : Font.Normal
    font.family: Zenon.face
    font.pixelSize: Zenon.px(15)
  }

  Text {
    id: sideDetail
    anchors.right: mountBtn.visible ? mountBtn.left : parent.right
    anchors.rightMargin: mountBtn.visible ? 8 : 12
    anchors.verticalCenter: sideLabel.verticalCenter
    // Only when there is no band to put it in. A mounted disk writes its
    // figure INSIDE the gauge — the size column does the same thing, and one
    // reading beside a bar plus another on it would be the same number twice.
    visible: sideRow.detail !== "" && sideRow.used < 0
    text: sideRow.detail
    color: Zenon.muted
    font.family: Zenon.face
    font.weight: Zenon.weight
    font.pixelSize: Zenon.px(13)
  }

  // How full it is, under the name it belongs to, and how much is left
  // written inside it. A figure tells you the amount; a bar tells you whether
  // that is a lot — and which of three disks is the one filling up.
  //
  // THE SAME BAR the size column draws, from UsageBar.qml. It used to be a
  // 2px hairline with the figure sitting off to the side, which was a second
  // answer to a question the listing had already settled on an answer for.
  // Only for a mounted filesystem: an unmounted one reports no figures, and
  // a bar drawn from a guess is worse than no bar.
  UsageBar {
    id: gauge
    anchors.left: sideGlyph.right
    anchors.leftMargin: 8
    anchors.right: mountBtn.visible ? mountBtn.left : parent.right
    anchors.rightMargin: mountBtn.visible ? 8 : 12
    anchors.bottom: parent.bottom
    anchors.bottomMargin: 7
    height: 16
    visible: sideRow.used >= 0
    // a disk fills from the left, the way every gauge does
    frac: sideRow.used
    accent: sideRow.gaugeInk
    label: sideRow.detail
    ink: sideRow.used > 0.85 ? sideRow.gaugeInk
      : (sideRow.active ? Zenon.white : Zenon.keyInk)
    fontSize: 13
  }

  Text {
    id: removeBtn
    anchors.right: parent.right
    anchors.rightMargin: 10
    anchors.verticalCenter: parent.verticalCenter
    // Only while the row is under the pointer: a column of crosses down the
    // sidebar would be four ways to delete something you were only trying to
    // click on.
    visible: sideRow.showRemove && sideHover.hovered
    text: "\uf00d"   // nf-fa-times
    color: removeHov.hovered ? Zenon.red : Zenon.muted
    font.family: Zenon.faceMono
    font.weight: Zenon.weight
    font.pixelSize: Zenon.px(13)

    HoverHandler { id: removeHov }
    MouseArea {
      anchors.fill: parent
      anchors.margins: -6
      onClicked: sideRow.removed()
    }
  }

  Text {
    id: mountBtn
    anchors.right: parent.right
    anchors.rightMargin: 10
    anchors.verticalCenter: parent.verticalCenter
    visible: sideRow.showMount
    // eject when it is mounted, mount when it is not — the glyph is the
    // action the click performs, not the state it is in
    text: sideRow.mounted ? "\uF052" : "\uF0AB"
    // The eject wears the crumb bar's "where you are" grey rather than
    // green: it is a verb sitting on every mounted disk at once, and a
    // column of green marks down the sidebar was louder than the disks.
    color: mountHov.hovered ? Zenon.cyan
      : (sideRow.mounted ? term.crumbInk : Zenon.muted)
    font.family: Zenon.face
    font.weight: Zenon.weight
    font.pixelSize: Zenon.px(14)

    HoverHandler { id: mountHov }
    MouseArea {
      anchors.fill: parent
      anchors.margins: -6
      onClicked: sideRow.toggledMount()
    }
  }
}
