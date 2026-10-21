// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ── THE SPACE MAP ────────────────────────────────────────────────────────
// The directory you are in, as rectangles as big as what each entry takes
// up (2026-10-21): the disk-usage mode's question — what in here is taking
// the room — answered as a picture rather than a list of bars. Inks are the
// listing's own (Terminus.inkOf: directories cyan, pictures green, media
// sand, archives orange…), so a big orange block is an archive at a glance.
//
// The measuring is the usage mode's: while the map is up the window counts
// as sizing (TerminusWindow.sizing), so every directory here is measured by
// the same du, into the same dirSizes, and comes back already known.
//
// A directory's tile goes into it — the listing goes there too, and the
// map follows; backspace or the crumb comes back up. A file's tile selects
// it in the listing and closes the map; the head says what is under the
// pointer, for tiles too small to. The biggest sixty are drawn and
// the rest are one tile, so a directory of thousands is still a picture
// (treemap.js).
//
// `term` is the terminus window, as in every sheet split out of it.

import QtQuick
import "../morpheus"
import "terminus.js" as Terminus
import "treemap.js" as Tree

Rectangle {
  id: space
  property var term: null
  anchors.fill: parent
  z: 13
  visible: opacity > 0.01
  opacity: space.open ? 1 : 0
  color: "transparent"
  Rectangle {
    anchors.fill: parent
    anchors.topMargin: term.tabStripRef.height + term.crumbBarRef.height
    color: term.cardScrim
  }
  Rectangle {
    width: term.sideRef.width
    height: term.tabStripRef.height + term.crumbBarRef.height
    color: term.cardScrim
  }
  Behavior on opacity {
    NumberAnimation {
      duration: space.open ? spaceSheet.slideIn : spaceSheet.slideOut
      easing.type: Zenon.ease
    }
  }

  property bool open: false
  property int sel: 0
  // the tile under the pointer, said in the head (a small one has no room)
  property var hovered: null

  // ── WHAT IS HERE, AND HOW BIG ──────────────────────────────────────────
  readonly property var rows: term ? term.view : []
  readonly property int unmeasured: {
    let n = 0;
    void term.dirSizes;
    for (const r of space.rows) if (r.isDir && term.dirSizes[r.path] === undefined) n++;
    return n;
  }
  readonly property real total: {
    let s = 0;
    void term.dirSizes;
    for (const r of space.rows) s += term.usageOf(r);
    return s;
  }
  readonly property var items: {
    void term.dirSizes;
    return Tree.capItems(space.rows.map((r) => ({ key: r.path, value: term.usageOf(r), row: r })), 60);
  }
  readonly property var tiles: {
    const w = mapBox.width, h = mapBox.height;
    if (w <= 0 || h <= 0) return [];
    return Tree.squarify(space.items.map((it) => it.value), 0, 0, w, h)
      .map((q) => Object.assign({}, q, { it: space.items[q.i] }));
  }
  // the cursor walks the tiles biggest first, which is the order they come in
  readonly property var cur: space.tiles[space.sel] || null
  onTilesChanged: if (space.sel >= space.tiles.length) space.sel = Math.max(0, space.tiles.length - 1)

  function ask() {
    space.sel = 0;
    space.open = true;
  }
  function dismiss() {
    space.open = false;
    term.contentRef.forceActiveFocus();
  }
  function step(d) {
    const n = space.tiles.length;
    if (n === 0) return;
    space.sel = (space.sel + d + n) % n;
  }
  function enter(t) {
    const q = t || space.cur;
    if (!q || !q.it || q.it.rest) return;
    const r = q.it.row;
    if (r.isDir) { term.goTo(r.path); space.sel = 0; return; }
    // a file: chosen in the listing, which is where something is done to it
    space.dismiss();
    const i = term.view.findIndex((x) => x.path === r.path);
    if (i >= 0) { term.act.sel = i; term.positionSel(); }
  }
  function up() {
    term.goUp();
    space.sel = 0;
  }

  InputShield { keepTop: term.tabStripRef.height + term.crumbBarRef.height; onClicked: space.dismiss() }
  Sheet {
    ground: "transparent"
    backdrop: term.sheetBackdrop   // the listing, frosted under the card
    seamFrost: term.sheetSeam   // the bar's frost, carried over the seam
    splice: true
    onCardInkChanged: term.noteSheet("s11", cardInk, drawnX, drawnW, drawnY, drawnH)
    onDrawnXChanged: term.noteSheet("s11", cardInk, drawnX, drawnW, drawnY, drawnH)
    onDrawnWChanged: term.noteSheet("s11", cardInk, drawnX, drawnW, drawnY, drawnH)
    onDrawnYChanged: term.noteSheet("s11", cardInk, drawnX, drawnW, drawnY, drawnH)
    onDrawnHChanged: term.noteSheet("s11", cardInk, drawnX, drawnW, drawnY, drawnH)
    id: spaceSheet
    leftInset: term.sideRef.width
    floating: false   // hangs from the bar, which carries its title — see barTitle
    title: term.sheetTitle
    glyph: term.sheetGlyph
    titleInk: term.sheetTitleInk
    glyphInk: term.sheetGlyphInk
    shown: space.open
    fromTop: term.tabStripRef.height + term.crumbBarRef.height
    cardW: 980
    cardH: 520 + spaceFoot.height + 44

    // ── where, and how much ────────────────────────────────────────────
    Item {
      id: spaceHead
      anchors.left: parent.left
      anchors.right: parent.right
      height: 44
      Text {
        id: whereText
        anchors.left: parent.left
        anchors.leftMargin: 18
        anchors.right: totalText.left
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideMiddle
        text: term.cwd
        color: Zenon.accentKey
        font.family: Zenon.faceMono
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(14)
      }
      Text {
        id: totalText
        anchors.right: parent.right
        anchors.rightMargin: 18
        anchors.verticalCenter: parent.verticalCenter
        text: space.hovered ? (space.hovered.rest ? space.hovered.count + " smaller items" : space.hovered.row.name)
            + "  \u00b7  " + Terminus.formatSize(space.hovered.value)
          : Terminus.formatSize(space.total)
          + (space.unmeasured > 0 ? "  ·  measuring " + space.unmeasured
              + (space.unmeasured === 1 ? " directory…" : " directories…") : "")
        color: space.unmeasured > 0 ? Zenon.cyan : Zenon.white
        font.family: Zenon.face
        font.weight: 600
        font.pixelSize: Zenon.px(14)
      }
    }

    // ── the map ────────────────────────────────────────────────────────
    Item {
      id: mapBox
      anchors.top: spaceHead.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: spaceFoot.top
      anchors.leftMargin: 14
      anchors.rightMargin: 14
      anchors.bottomMargin: 12
      clip: true

      EmptyState {
        anchors.centerIn: parent
        visible: space.tiles.length === 0
        text: space.rows.length === 0 ? "Nothing here" : space.unmeasured > 0 ? "Measuring…" : "Everything here is empty"
      }

      Repeater {
        model: space.tiles.length
        delegate: Item {
          id: tile
          required property int index
          readonly property var q: space.tiles[index] || null
          readonly property var it: q ? q.it : null
          readonly property var row: it && !it.rest ? it.row : null
          readonly property color ink: !it ? Zenon.muted : it.rest ? Zenon.muted : Terminus.inkOf(row)
          readonly property int say: q ? Tree.labelFit(q.w, q.h) : 0
          readonly property bool here: index === space.sel
          x: q ? q.x : 0
          y: q ? q.y : 0
          width: q ? q.w : 0
          height: q ? q.h : 0
          // a hairline of the card between tiles, so neighbors of one ink
          // still read as two
          Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: Zenon.radiusControl
            color: tilePress.pressed ? Zenon.alpha(tile.ink, 0.42)
              : Zenon.alpha(tile.ink, tile.here ? 0.34 : (tile.row && tile.row.isDir ? 0.22 : 0.16))
            border.width: tile.here ? 2 : 1
            border.color: tile.here ? tile.ink : Zenon.alpha(tile.ink, 0.35)
          }
          Column {
            x: 8
            y: 6
            width: parent.width - 16
            visible: tile.say > 0
            spacing: 1
            Text {
              width: parent.width
              elide: Text.ElideRight
              text: !tile.it ? "" : tile.it.rest ? tile.it.count + " smaller items"
                : (tile.row.isDir ? " " : "") + tile.row.name
              color: Zenon.white
              font.family: Zenon.face
              font.weight: 600
              font.pixelSize: Zenon.px(13)
            }
            Text {
              width: parent.width
              elide: Text.ElideRight
              visible: tile.say > 1
              text: !tile.it ? "" : Terminus.formatSize(tile.it.value)
                + (space.total > 0 ? "  ·  " + Math.round(100 * tile.it.value / space.total) + "%" : "")
              color: Zenon.accentKey
              font.family: Zenon.face
              font.weight: Zenon.weight
              font.pixelSize: Zenon.px(12)
            }
          }
          MouseArea {
            id: tilePress
            anchors.fill: parent
            onClicked: { space.sel = tile.index; space.enter(tile.q); }
          }
          HoverHandler {
            onHoveredChanged: {
              if (hovered) space.hovered = tile.it;
              else if (space.hovered === tile.it) space.hovered = null;
            }
          }
        }
      }
    }

    HintBar {
      id: spaceFoot
      anchors.bottom: parent.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      rows: [["←→", "tile"], ["↵", "into it"], ["backspace", "up"], ["esc", "close"]]
    }
  }
}
