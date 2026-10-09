// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// The editing surface: nvim's windows where nvim laid them out, a cursor,
// and nvim's floats and completion menu on top. It decides nothing about
// text — every key that is not plato's own goes to nvim, and what comes back
// through EditorState is what is drawn.
//
// A GRID OF FIXED CELLS. Every column is one advance of a monospace face and
// every row one line height, so anything nvim places at (row, col) — a
// window, a float, the cursor, the completion menu — is at (col × cellW,
// row × cellH) with no measuring. The cells that fit this item are what nvim
// is told its screen is; zooming changes the cell, and with it how many fit.

import QtQuick
import Quickshell
import "../../morpheus"
import "keys.js" as KeyMap
import "cells.js" as Cells
import "../../morpheus/scrollfeel.js" as Feel

Item {
  id: view

  required property var ed
  required property var client
  property int fontSize: 17
  property string fontFamily: Zenon.faceFixed
  property int fontWeight: Font.DemiBold
  // the settings sheet's motion settings (core/Settings.qml)
  property bool cursorBreathes: true
  property bool cursorGlides: true
  property bool smoothScroll: true
  // how many lines one wheel notch scrolls
  readonly property int wheelLines: 4
  property bool animateLayout: true
  property bool gitGutter: true
  property bool jumpTrail: true
  property bool dimInactive: true
  // where the windows lay their frost (under the bars), and the bars it
  // goes under — see WindowView's ScrollEdges; null for none
  property Item edgeHost: null
  property Item topBar: null
  property Item bottomBar: null

  // ── the cell ───────────────────────────────────────────────────────
  FontMetrics {
    id: fm
    font.family: view.fontFamily
    font.pixelSize: view.fontSize
    font.weight: view.fontWeight
  }
  readonly property font cellFont: fm.font
  // ONE CELL IS MEASURED OFF A RUN OF A HUNDRED, BY TextMetrics — never
  // FontMetrics.advanceWidth. Under quickshell that said 10.875px for this
  // face at 16px, while every Text actually lays a character out in 9.594:
  // everything placed by cells (the selection's background, the cursor,
  // underlines, a click) drifted a pixel and a third further right with
  // every column, ninety pixels by column 64, and a visual selection sat
  // beside the text it had selected. TextMetrics lays text out the way a
  // Text does, so the grid and the glyphs cannot disagree.
  TextMetrics {
    id: cellRun
    font: fm.font
    text: "M".repeat(100)
  }
  readonly property real cellW: cellRun.advanceWidth / 100
  // ROWS AS TALL AS THE FACE, AND NO TALLER. The face's own line height —
  // ascent to descent — is where its box-drawing characters reach, so ASCII
  // art and tree guides join up from one row to the next. The first version
  // added a third again for air, and every drawing came out barred with
  // gaps. Rounded to a whole pixel, so rows never fall between pixels.
  readonly property real cellH: Math.round(fm.height)

  readonly property int rowsFit: Math.max(1, Math.floor(view.height / view.cellH))
  // the minimap's strip down the right edge comes out of nvim's columns
  property bool minimap: true
  // ONLY WITH SOMETHING TO SCROLL (user, 2026-10-09): a file that fits has
  // no map, as it has no scrollbar. Counted as the scrollbar counts, in
  // lines against the window's height (WindowView's proxy), so the two
  // agree, and the map's own width, rewrapping the text, cannot flip it.
  readonly property bool mapNeeded: {
    view.ed.frame;
    const w = view.ed.curWin;
    return !!w && view.ed.scrollOf(w.id).lines > w.height;
  }
  readonly property real mapW: view.minimap && view.mapNeeded && view.width > 70 * view.cellW + 100 ? 100 : 0
  readonly property int colsFit: Math.max(1, Math.floor((view.width - view.mapW) / view.cellW))

  // told to nvim a frame after the last change, so a window being dragged
  // wider sends one resize rather than one per pixel
  onRowsFitChanged: sizeSend.restart()
  onColsFitChanged: sizeSend.restart()
  // held while something is animating the editor's size (the tree sliding
  // out): one resize when it settles, rather than one per frame
  property bool holdSize: false
  onHoldSizeChanged: if (!view.holdSize) sizeSend.restart()
  Timer {
    id: sizeSend
    interval: 16
    onTriggered: if (!view.holdSize) view.client.resize(view.rowsFit, view.colsFit)
  }
  Connections {
    target: view.client
    function onHello() { view.client.resize(view.rowsFit, view.colsFit); }
  }

  // ── the windows ────────────────────────────────────────────────────
  Repeater {
    id: windows
    // by id, so a window keeps its items when it only changes size or place
    model: view.ed.winIds
    WindowView {
      ed: view.ed
      client: view.client
      cellW: view.cellW
      cellH: view.cellH
      face: fm.font
      smoothScroll: view.smoothScroll
      railShown: view.mapW <= 0
      animateLayout: view.animateLayout
      // the text area's width as it is now, for the window at the right edge
      liveW: view.width - view.mapW
      gitGutter: view.gitGutter
      jumpTrail: view.jumpTrail
      dimInactive: view.dimInactive
      // the frost under the tabs and the status line — see WindowView
      edgeHost: view.edgeHost
      topBar: view.topBar
      bottomBar: view.bottomBar
      edgeTrack: [view.x, view.y, view.width, view.height]
    }
  }
  // a window's scrollbar thumb is being dragged
  readonly property bool railHeld: {
    for (let i = 0; i < windows.count; ++i) {
      const it = windows.itemAt(i);
      if (it && it.railDragging) return true;
    }
    return false;
  }
  function windowItem(id) {
    for (let i = 0; i < windows.count; ++i) {
      const it = windows.itemAt(i);
      if (it && it.w.id === id) return it;
    }
    return null;
  }

  // ── between the windows ────────────────────────────────────────────
  // TERMINUS' DIVIDER, without its shadows (user, 2026-10-09: the hairline
  // that was here was barely visible). A 1px line in the neutral border
  // colour that turns cyan under the pointer; a 9px grip straddling it, so
  // the cursor changes over the seam and a drag resizes the window — a
  // double click evens them (wincmd =); and two short bars either side of
  // its middle, the one on the side of the current window lit. nvim leaves
  // one column between side-by-side windows — the line runs down its
  // middle — and with no status lines nothing between stacked ones, so
  // that line lies on the lower window's first row edge.
  //
  // One per window: its right edge when another window is there, its top
  // when one is above it. The GRIPS are a second Repeater further down,
  // above `area` (which would otherwise take the pointer first); the lines
  // stay down here, under the completion menu and the cards.
  // "v:<id>" / "h:<id>" — the seam under the pointer or being dragged
  property string seamHot: ""
  function seamOf(w) {
    const right = w.col + w.width < view.ed.gridCols;
    const vx = (w.col + w.width) * view.cellW + Math.floor(view.cellW / 2);
    return { right: right, top: w.row > 0, vx: vx, hy: w.row * view.cellH,
             x: w.col * view.cellW, y: w.row * view.cellH,
             w: w.width * view.cellW, h: w.height * view.cellH };
  }
  Repeater {
    model: view.ed.wins
    Item {
      id: seams
      required property var modelData
      readonly property var w: modelData
      readonly property var g: view.seamOf(w)
      readonly property var cur: view.ed.curWin
      readonly property bool hereCurrent: !!cur && cur.id === w.id
      // the window across each seam, when it is the current one
      readonly property bool rightCurrent: !!cur && cur.id !== w.id
        && cur.col === w.col + w.width + 1
        && cur.row < w.row + w.height && cur.row + cur.height > w.row
      readonly property bool aboveCurrent: !!cur && cur.id !== w.id
        && cur.row + cur.height === w.row
        && cur.col < w.col + w.width && cur.col + cur.width > w.col

      Rectangle {
        visible: seams.g.right
        x: seams.g.vx
        y: seams.g.y
        width: 1
        height: seams.g.h
        color: view.seamHot === "v:" + seams.w.id ? Zenon.cyan : Zenon.border
      }
      Repeater {
        model: seams.g.right ? [0, 1] : []
        Rectangle {
          required property int modelData
          readonly property bool lit: modelData === 0 ? seams.hereCurrent : seams.rightCurrent
          width: 2
          height: 14
          radius: 1
          x: modelData === 0 ? seams.g.vx - 4 : seams.g.vx + 3
          y: seams.g.y + (seams.g.h - height) / 2
          color: lit ? Zenon.cyan : Zenon.muted
          Behavior on color { ColorAnimation { duration: Zenon.fast } }
        }
      }
      Rectangle {
        visible: seams.g.top
        x: seams.g.x
        y: seams.g.hy
        width: seams.g.w
        height: 1
        color: view.seamHot === "h:" + seams.w.id ? Zenon.cyan : Zenon.border
      }
      Repeater {
        model: seams.g.top ? [0, 1] : []
        Rectangle {
          required property int modelData
          // 0 above the line (the window over it), 1 below (this one)
          readonly property bool lit: modelData === 0 ? seams.aboveCurrent : seams.hereCurrent
          width: 14
          height: 2
          radius: 1
          x: seams.g.x + (seams.g.w - width) / 2
          y: modelData === 0 ? seams.g.hy - 4 : seams.g.hy + 3
          color: lit ? Zenon.cyan : Zenon.muted
          Behavior on color { ColorAnimation { duration: Zenon.fast } }
        }
      }
    }
  }

  // ── the cursor ─────────────────────────────────────────────────────
  // THE SHELL'S CARET, AT EDITOR SIZE. morpheus' Caret breathes rather than
  // blinks — 1 to 0.2 and back, 620ms each way — in cyan, and so does this:
  // solid while anything is happening, breathing once it has sat still. It
  // glides from cell to cell on Zenon.travelEase, briskly, so the eye can
  // follow a jump without a keystroke ever waiting on it. (Both can be
  // switched off in the settings sheet.)
  //
  // IN THE INK OF WHAT IT IS ON. A block over a string is the string's
  // green, over a keyword the keyword's colour: the cursor reads as part of
  // the text rather than a cyan hole in it. Off the text (blank space, past
  // the end) it is the text's own colour; an ink too dark to see itself —
  // black on a search match — gives way to it too.
  readonly property string shape: {
    const m = view.ed.modeName;
    if (m === "insert" || m === "command") return "bar";
    if (m === "replace" || view.ed.replacePending) return "underline";
    // select mode is insert mode's shift selection (cua.lua): a selection
    // between characters, so the caret is still a bar
    if (/^[sS\u0013]/.test(view.ed.mode)) return "bar";
    return "block";
  }
  readonly property var curItem: {
    view.ed.frame;
    return view.ed.curWin ? view.windowItem(view.ed.curWin.id) : null;
  }
  // the cursor's cell on the grid, plus the scroll glide it rides along with
  readonly property real curX: (view.ed.curWin
    ? (view.ed.curWin.col + view.ed.curWin.textoff + view.ed.cursorCol) * view.cellW : 0)
    + (view.curItem ? view.curItem.gapXAt(view.ed.cursorRow, view.ed.cursorCol) : 0)
  readonly property real curY: (view.ed.curWin
    ? (view.ed.curWin.row + view.ed.cursorRow) * view.cellH : 0)
    + (view.curItem ? view.curItem.body.y + view.curItem.gapAt(view.ed.cursorRow) : 0)

  readonly property color textInk: {
    view.ed.frame;
    const fallback = view.ed.normalFg;
    const w = view.ed.curWin;
    if (!w) return fallback;
    const r = view.ed.rowsOf(w.id)[view.ed.cursorRow];
    if (!r || !r.s) return fallback;
    const c = view.ed.cursorCol;
    for (let i = 0; i < r.s.length; ++i) {
      const sp = r.s[i];
      if (c < sp[0] || c >= sp[0] + sp[1]) continue;
      const st = view.ed.styles[sp[2]];
      if (!st || !st.fg) return fallback;
      const ink = Qt.color(st.fg);
      // too dark to show against the editor's background
      return 0.2126 * ink.r + 0.7152 * ink.g + 0.0722 * ink.b < 0.28 ? fallback : ink;
    }
    return fallback;
  }

  property bool moving: false
  Timer { id: still; interval: 500; onTriggered: view.moving = false }
  function wake() { view.moving = true; still.restart(); }
  Connections {
    target: view.ed
    function onCursorRowChanged() { view.wake(); }
    function onCursorColChanged() { view.wake(); }
    function onModeChanged() { view.wake(); }
  }

  Item {
    id: cursor
    visible: !view.ed.cmdlineShown && !view.ed.inFloat && view.ed.curWin !== null
    x: view.curX
    y: view.curY
    width: view.cellW
    height: view.cellH
    // TYPING DOES NOT GLIDE. In insert mode the caret is where the next
    // letter goes, and a caret easing after each one trailed the text it
    // had just typed; it lands at once, as any editor's does. Motions —
    // a jump, a word, a line — still glide, so the eye can follow them.
    readonly property bool glides: view.cursorGlides
      && view.ed.modeName !== "insert" && view.ed.modeName !== "replace"
    Behavior on x {
      // riding an in-line delete's slide is not a move of its own either
      enabled: cursor.glides && (!view.curItem || view.curItem.igW === 0)
      NumberAnimation { duration: Zenon.brisk; easing.type: Zenon.travelEase }
    }
    Behavior on y {
      // riding a scroll glide is not a move of its own: no second easing
      enabled: cursor.glides && (!view.curItem || (view.curItem.body.y === 0 && view.curItem.gapH === 0))
      NumberAnimation { duration: Zenon.brisk; easing.type: Zenon.travelEase }
    }

    // without the keyboard: a hollow block, still, as a terminal shows it
    Rectangle {
      visible: !view.activeFocus
      anchors.fill: parent
      color: "transparent"
      border.width: 1
      border.color: Zenon.muted
    }

    // A NEW MODE MORPHS THE CARET: the block narrows to insert's bar, the
    // bar widens back, and replace's underline settles from the block —
    // briskly, so it reads as the same cursor changing rather than a swap.
    // Clipped, so the block's letter never spills out of a bar.
    Rectangle {
      id: caret
      visible: view.activeFocus
      clip: true
      // r waiting for its character: a thicker underline in peach, the
      // character above it left readable — what will be replaced
      readonly property int under: view.ed.replacePending ? 3 : 2
      y: view.shape === "underline" ? view.cellH - caret.under : 0
      width: view.shape === "bar" ? 2 : view.cellW
      height: view.shape === "underline" ? caret.under : view.cellH
      Behavior on width { NumberAnimation { duration: Zenon.brisk; easing.type: Zenon.travelEase } }
      Behavior on height { NumberAnimation { duration: Zenon.brisk; easing.type: Zenon.travelEase } }
      Behavior on y { NumberAnimation { duration: Zenon.brisk; easing.type: Zenon.travelEase } }
      color: view.ed.replacePending ? Zenon.yellow : view.textInk
      Behavior on color { ColorAnimation { duration: Zenon.brisk } }
      opacity: 1
      SequentialAnimation on opacity {
        running: caret.visible && !view.moving && view.cursorBreathes
        loops: Animation.Infinite
        NumberAnimation { to: 0.2; duration: 620; easing.type: Easing.InOutQuad }
        NumberAnimation { to: 1.0; duration: 620; easing.type: Easing.InOutQuad }
      }
      // back to solid the moment it moves
      Connections {
        target: view
        function onMovingChanged() { if (view.moving) caret.opacity = 1; }
        function onCursorBreathesChanged() { if (!view.cursorBreathes) caret.opacity = 1; }
      }

      // a block covers its character, so the character is drawn again on
      // top of it in the background's colour — the terminal's reverse video
      Text {
        visible: view.shape === "block"
        width: view.cellW
        height: view.cellH
        verticalAlignment: Text.AlignVCenter
        textFormat: Text.PlainText
        font: fm.font
        color: Zenon.black
        text: {
          view.ed.frame;
          const w = view.ed.curWin;
          if (!w) return "";
          const r = view.ed.rowsOf(w.id)[view.ed.cursorRow];
          if (!r) return "";
          return Cells.chars(r.t)[view.ed.cursorChar] || "";
        }
      }
    }
  }

  // ── the minimap ────────────────────────────────────────────────────
  signal minimapRows(int rows)
  Minimap {
    id: minimapItem
    visible: view.mapW > 0
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: view.mapW
    z: 4
    ed: view.ed
    client: view.client
    onRowsWanted: (n) => view.minimapRows(n)
    onHand: (id, held) => { const it = view.windowItem(id); if (it) it.mapHeld = held; }
    onSeek: (id, line) => { const it = view.windowItem(id); if (it) it.handTo(line); }
  }
  // THE TABS RUN ON OVER THE MAP. The windows' frost under the tab strip
  // (WindowView's ScrollEdge, and its darkening) stops at their right edge,
  // where the map begins, so the last tab came out two shades: dark over
  // the text, the bar's own grey over the map. The map's column, and the
  // inset past it to the window's edge, goes under the bar the same way,
  // whenever the window beside it has rows above.
  property real mapEdgeOut: 0
  readonly property bool mapRowsAbove: {
    for (let i = 0; i < windows.count; ++i) {
      const it = windows.itemAt(i);
      if (it && it.atRight && it.w.row === 0) return it.moreAbove;
    }
    return false;
  }
  // and the same at the foot, under the status line
  readonly property bool mapRowsBelow: {
    for (let i = 0; i < windows.count; ++i) {
      const it = windows.itemAt(i);
      if (it && it.atRight && it.w.row + it.w.height >= view.ed.gridRows) return it.moreBelow;
    }
    return false;
  }
  Item {
    id: mapEdge
    visible: minimapItem.visible
    x: minimapItem.x
    width: view.width - minimapItem.x + view.mapEdgeOut
    height: minimapItem.height
    // what ScrollEdge captures: the map's own top (it has nothing above)
    readonly property Item contentItem: minimapItem
    readonly property real contentX: 0
    readonly property real contentY: 0
  }
  // any edge under a bar is on: the plato window lays the bar's one scrim
  // (the edges lay none — see WindowView's edgeAboveOn)
  readonly property bool edgesAbove: {
    if (mapTopEdge.on) return true;
    for (let i = 0; i < windows.count; ++i) {
      const it = windows.itemAt(i);
      if (it && it.edgeAboveOn) return true;
    }
    return false;
  }
  readonly property bool edgesBelow: {
    if (mapFootEdge.on) return true;
    for (let i = 0; i < windows.count; ++i) {
      const it = windows.itemAt(i);
      if (it && it.edgeBelowOn) return true;
    }
    return false;
  }
  ScrollEdge {
    id: mapTopEdge
    parent: view.edgeHost
    view: mapEdge
    follow: true
    scrim: 0
    bar: view.topBar
    track: [view.x, view.y, view.width, view.height]
    scrolled: view.mapRowsAbove
    visible: !!view.edgeHost && !!view.topBar && mapEdge.visible
  }
  ScrollEdge {
    id: mapFootEdge
    parent: view.edgeHost
    view: mapEdge
    scrim: 0
    below: true
    follow: true
    bar: view.bottomBar
    track: [view.x, view.y, view.width, view.height]
    scrolled: view.mapRowsBelow
    visible: !!view.edgeHost && !!view.bottomBar && mapEdge.visible
  }

  // ── A PATH, SHOWN ──────────────────────────────────────────────────
  // The pointer resting on a path ("~/todo", logo.png, "../lib/x.lua")
  // brings up its file in a card beside it (PathCard.qml): the text
  // highlighted, a picture as itself, a directory's entries. A word that
  // names no file brings up nothing. A relative path is the current file's
  // directory's, as gf reads it; gf on a picture opens it in Picasso
  // (editing.lua).
  property string fileDir: ""
  PathCard {
    id: peek
    z: 6
    property real px: 0
    property real py: 0
    codeFamily: fm.font.family
    pixelSize: Math.max(11, fm.font.pixelSize - 2)
    maxW: Math.min(620, Math.max(280, view.width * 0.5))
    maxH: Math.min(420, Math.max(160, view.height * 0.6))
    hint: peek.kind === "image" ? "gf opens it in Picasso" : ""
    function hide() { hoverWait.stop(); peek.file = ""; }
    function hover(x, y) {
      // moved off what it is showing: gone; still: look again
      if (peek.file !== "" && (Math.abs(x - peek.px) > view.cellW * 3 || Math.abs(y - peek.py) > view.cellH)) peek.file = "";
      peek.px = x;
      peek.py = y;
      hoverWait.restart();
    }
    // the word under the pointer, if it reads as a path
    function look() {
      const r = Math.floor(peek.py / view.cellH), c = Math.floor(peek.px / view.cellW);
      const ws = view.ed.wins;
      for (let i = 0; i < ws.length; ++i) {
        const w = ws[i];
        if (r < w.row || r >= w.row + w.height || c < w.col + w.textoff || c >= w.col + w.width) continue;
        const row = view.ed.rowsOf(w.id)[r - w.row];
        if (!row || !row.t) return;
        const chars = Cells.chars(row.t);
        const at = c - w.col - w.textoff;
        if (at >= chars.length) return;
        const stop = /[\s"'`()<>\[\]{},;|=]/;
        let a = at, b = at;
        while (a > 0 && !stop.test(chars[a - 1])) a--;
        while (b < chars.length && !stop.test(chars[b])) b++;
        let word = chars.slice(a, b).join("").replace(/^file:\/\//, "").replace(/[.:]+$/, "");
        // a slash or a dot to be a path at all; not a URL, not a comment's //
        if (word.length < 2 || !/[\/.]/.test(word) || word.indexOf("://") >= 0 || /^\/+$/.test(word)) return;
        const home = Quickshell.env("HOME");
        if (word === "~" || word.startsWith("~/")) word = home + word.slice(1);
        else if (!word.startsWith("/")) word = (view.fileDir || home) + "/" + word.replace(/^\.\//, "");
        peek.file = word.replace(/\/+$/, "") || "/";
        return;
      }
    }
    Timer { id: hoverWait; interval: 450; onTriggered: peek.look() }
    Connections {
      target: view.ed
      function onFileChanged() { peek.hide(); }
    }
    // beside the pointer, kept inside the editor
    x: Math.max(8, Math.min(view.width - peek.width - 8, peek.px + 16))
    y: peek.py + view.cellH + peek.height + 8 < view.height ? peek.py + view.cellH : Math.max(8, peek.py - peek.height - 8)
  }

  // ── yanks and deletes, flashed ─────────────────────────────────────
  // see Flashes.qml; above the text, under the floats
  Flashes {
    id: flashes
    anchors.fill: parent
    ed: view.ed
    cellW: view.cellW
    cellH: view.cellH
    face: fm.font
    function lagAt(row) {
      const ws = view.ed.wins;
      for (let i = 0; i < ws.length; ++i) {
        const w = ws[i];
        if (row >= w.row && row < w.row + w.height) {
          const it = view.windowItem(w.id);
          return it ? it.body.y : 0;
        }
      }
      return 0;
    }
  }
  function flash(ev) {
    // AN UNDO OR REDO THAT IS ONE PLAIN CHANGE SLIDES as the edit it
    // reverses (editing.lua slideOf): text taken away plays a delete's
    // ghost and gap, text brought back a paste's opening — lines or cells,
    // either way. Anything else sweeps.
    if ((ev.kind === "undo" || ev.kind === "redo") && ev.slide) {
      if (ev.slide === "out") view.flash({ kind: "delete", linewise: !!ev.linewise, cells: ev.cells, trim: !!ev.linewise });
      else view.flash({ kind: "arrive", put: true, linewise: !!ev.linewise, cells: ev.cells,
                        slideRow: ev.slideRow, slideN: ev.slideN });
      return;
    }
    if (ev.kind === "move") {
      // a moved line: the window it is in slides its rows (WindowView)
      const ws = view.ed.wins;
      for (let i = 0; i < ws.length; ++i) {
        const w = ws[i];
        if (ev.to >= w.row && ev.to < w.row + w.height) {
          const it = view.windowItem(w.id);
          if (it) it.slideNext(ev.from - w.row, ev.to - w.row, ev.rows);
          return;
        }
      }
      return;
    }
    // A PASTE SLIDES IN, as a delete slides out (no green wash): whole lines
    // open room below and fade into it; cells in one line push the rest of
    // the line along (WindowView's gaps, played forwards). A charwise paste
    // across lines opens room for the lines it added. A format (no `put`)
    // keeps its wash.
    if (ev.kind === "arrive" && ev.put) {
      const cells = view.ed._list(ev.cells);
      // a linewise undo says where and how many itself (blank lines write
      // no cells)
      const counted = ev.linewise && ev.slideRow !== undefined && ev.slideRow !== null;
      if (cells.length === 0 && !counted) return;
      const rows = counted ? Array.from({ length: ev.slideN }, (_, k) => ev.slideRow + k)
        : [...new Set(cells.map((c) => c.row))].sort((a, b) => a - b);
      const top = rows[0];
      const ws = view.ed.wins;
      for (let i = 0; i < ws.length; ++i) {
        const w = ws[i];
        if (top < w.row || top >= w.row + w.height) continue;
        const it = view.windowItem(w.id);
        if (!it) return;
        if (ev.linewise) it.openNext(top - w.row, rows.length);
        else if (rows.length === 1) {
          // an undo says how many cells are new (slideN): the last of what
          // it wrote — a step that also rewrote some text lights all of it
          const c = cells[0];
          const n = ev.slideN > 0 ? Math.min(ev.slideN, c.len) : c.len;
          it.inlineOpenNext(top - w.row, c.col + c.len - n - w.col - w.textoff, n);
        }
        else it.openNext(top + 1 - w.row, rows.length - 1);
        return;
      }
      return;
    }
    // a delete within one line: the text after it held, then slid back
    // (WindowView's in-line gap)
    if (ev.kind === "delete" && !ev.linewise) {
      const cells = view.ed._list(ev.cells);
      if (cells.length === 1 && cells[0].len > 0) {
        const c = cells[0];
        const ws = view.ed.wins;
        for (let i = 0; i < ws.length; ++i) {
          const w = ws[i];
          if (c.row >= w.row && c.row < w.row + w.height && c.col >= w.col && c.col < w.col + w.width) {
            const it = view.windowItem(w.id);
            if (it) it.inlineNext(c.row - w.row, c.col - w.col - w.textoff, c.len);
            break;
          }
        }
      }
    }
    // whole lines deleted: their window holds their room while the ghost
    // plays, then closes it (WindowView's gap)
    if (ev.kind === "delete" && ev.linewise) {
      const cells = view.ed._list(ev.cells);
      if (cells.length > 0) {
        const rows = new Set(cells.map((c) => c.row));
        const top = Math.min(...rows);
        const ws = view.ed.wins;
        for (let i = 0; i < ws.length; ++i) {
          const w = ws[i];
          if (top >= w.row && top < w.row + w.height) {
            const it = view.windowItem(w.id);
            if (it) it.gapNext(top - w.row, rows.size);
            break;
          }
        }
      }
    }
    flashes.show(ev);
  }

  // ── floats and the completion menu ─────────────────────────────────
  // above the text and the cursor; see FloatCard.qml and CompletionMenu.qml.
  // Both are placed on nvim's grid, which starts at this item's left edge.
  Repeater {
    model: view.ed.floats
    FloatCard {
      ed: view.ed
      cellW: view.cellW
      cellH: view.cellH
      face: fm.font
      originX: 0
      areaW: view.width
      areaH: view.height
    }
  }
  CompletionMenu {
    ed: view.ed
    client: view.client
    cellW: view.cellW
    cellH: view.cellH
    face: fm.font
    originX: 0
    areaW: view.width
    areaH: view.height
  }

  // ── keys ────────────────────────────────────────────────────────────
  // Plato's own, decided first; everything else goes to nvim.
  //   <Space>        the leader menu — in normal and visual mode (where
  //                  Space only moves a character right, as l does), never
  //                  in insert mode, nor while a command waits for its next
  //                  key: f<Space> finds a space
  //   |              the file tree: shown and focused; focused if shown
  //                  elsewhere — normal mode, as in terminus
  //   <C-,>          plato's settings — anywhere
  //   <C-p>          find a file — normal mode (in insert it is completion's)
  //   <C-S-p>        the command palette — anywhere
  //   <C-=> <C-->    this tab's text bigger, smaller — anywhere
  //   <C-0>          this tab's text back to oracle's size
  //   <C-Tab>        the next tab, <C-S-Tab> the previous, in the strip's order
  signal leaderRequested()
  signal pickerRequested(string mode)
  signal zoomRequested(int step)   // +1, -1, or 0 for the default
  // a key went to nvim: what a message waiting for one listens for
  signal typed()
  // | in normal mode: the file tree, shown or put away, as | does in terminus
  signal treeToggleRequested()
  signal settingsRequested()
  // a right click: plato's context menu, at this point in the editor
  signal contextRequested(real x, real y)
  // Alt and a letter answers a question card first, if one has that choice
  // (Toasts.tryKey); otherwise it goes to nvim as always
  property var answerKey: null
  // 1-9 in normal mode, offered first to whoever wants it (the start card);
  // a count to nvim otherwise
  property var digitKey: null
  focus: true
  Keys.onPressed: (event) => {
    const m = event.modifiers & (Qt.ControlModifier | Qt.ShiftModifier | Qt.AltModifier | Qt.MetaModifier);
    if (m === Qt.AltModifier && event.key >= Qt.Key_A && event.key <= Qt.Key_Z && view.answerKey
        && view.answerKey(String.fromCharCode(event.key).toLowerCase())) {
      event.accepted = true; return;
    }
    const normal = view.ed.mode === "n" && !view.ed.inFloat;
    const ctrl = (m & Qt.ControlModifier) !== 0 && (m & (Qt.AltModifier | Qt.MetaModifier)) === 0;
    if (normal && m === 0 && !view.ed.blocking && view.ed.pending === "" && /^[1-9]$/.test(event.text)
        && view.digitKey && view.digitKey(Number(event.text))) {
      event.accepted = true; return;
    }
    const visual = (view.ed.mode === "v" || view.ed.mode === "V" || view.ed.mode === "\u0016") && !view.ed.inFloat;
    if ((normal || visual) && event.key === Qt.Key_Space && m === 0
        // (in visual mode showcmd is the selection's size, never empty: only
        // the keys sent since the last frame say a command is waiting)
        && !view.ed.blocking && (visual ? view.ed._tail === "" : view.ed.pending === "")) {
      view.leaderRequested(); event.accepted = true; return;
    }
    // THE TREE ON |, AS IN TERMINUS. Taken from nvim's | (go to a column),
    // which a count makes useful and nothing else does — and only when nvim
    // is waiting for a command, not halfway through one (d|, 3|).
    if (normal && event.text === "|" && !view.ed.blocking) {
      view.treeToggleRequested(); event.accepted = true; return;
    }
    if (ctrl && event.key === Qt.Key_Comma) {
      view.settingsRequested(); event.accepted = true; return;
    }
    if (event.key === Qt.Key_P && m === (Qt.ControlModifier | Qt.ShiftModifier)) {
      view.pickerRequested("commands"); event.accepted = true; return;
    }
    // <C-Tab> / <C-S-Tab>: the next and previous tab, in the strip's order
    if ((event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) && (m & Qt.ControlModifier)) {
      const back = event.key === Qt.Key_Backtab || (m & Qt.ShiftModifier) !== 0;
      const t = view.ed.tabAfter(back ? -1 : 1);
      if (t) view.client.bufShow(t.id);
      event.accepted = true; return;
    }
    // ctrl p: the command palette too (files are space f). Normal mode only,
    // since in insert <C-p> is nvim's own completion.
    if (normal && event.key === Qt.Key_P && m === Qt.ControlModifier) {
      view.pickerRequested("commands"); event.accepted = true; return;
    }
    // Ctrl with = or + (either is "bigger", whatever the layout needs shift
    // for), - and 0
    if (ctrl && (event.key === Qt.Key_Equal || event.key === Qt.Key_Plus)) {
      view.zoomRequested(1); event.accepted = true; return;
    }
    if (ctrl && (event.key === Qt.Key_Minus || event.key === Qt.Key_Underscore)) {
      view.zoomRequested(-1); event.accepted = true; return;
    }
    if (ctrl && event.key === Qt.Key_0) {
      view.zoomRequested(0); event.accepted = true; return;
    }
    peek.hide();
    const keys = KeyMap.translate(event);
    if (keys === "") return;
    view.client.input(keys);
    view.typed();
    event.accepted = true;
  }

  // ── the mouse ───────────────────────────────────────────────────────
  // Handed to nvim as mouse input on its own grid rather than turned into
  // cursor moves here, so a click in another split moves into it, a drag is
  // a visual selection and a double-click selects a word, as in the terminal.
  MouseArea {
    id: area
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    // AN ARROW OVER THE SCROLLBAR. This area lies over every window's rail
    // (which only gets the press it lets through), so its I-beam showed on
    // the bar too — and stayed while the thumb was dragged.
    cursorShape: overRail || overFold || view.railHeld ? Qt.ArrowCursor : Qt.IBeamCursor
    property bool overRail: false
    // over a fold's ring or a closed fold's pill: things to click, not text
    // to place a caret in, so the pointer is the arrow (user, 2026-10-09)
    property bool overFold: false
    function onRail(x, y) {
      const under = windowAt(x, y);
      return !!under && under.railShown && x >= under.x + under.width - 12;
    }
    property int lastRow: -1
    property int lastCol: -1
    property string held: ""

    function mods(m) {
      return ((m & Qt.ControlModifier) ? "C" : "") + ((m & Qt.ShiftModifier) ? "S" : "")
        + ((m & Qt.AltModifier) ? "A" : "");
    }
    function button(b) {
      return b === Qt.RightButton ? "right" : b === Qt.MiddleButton ? "middle" : "left";
    }
    function row(y) { return Math.max(0, Math.min(view.rowsFit - 1, Math.floor(y / view.cellH))); }
    function col(x) { return Math.max(0, Math.min(view.colsFit - 1, Math.floor(x / view.cellW))); }
    function windowAt(x, y) {
      const r = row(y), c = col(x);
      const ws = view.ed.wins;
      for (let i = 0; i < ws.length; ++i) {
        const w = ws[i];
        if (r >= w.row && r < w.row + w.height && c >= w.col && c < w.col + w.width)
          return view.windowItem(w.id);
      }
      return null;
    }

    onPressed: (mouse) => {
      // the right edge of a window is its scrollbar's: let the press through
      if (onRail(mouse.x, mouse.y)) { mouse.accepted = false; return; }
      view.forceActiveFocus();
      // THE RIGHT BUTTON IS PLATO'S MENU. A selection is kept for it to act
      // on; with none, the cursor goes to the click first, so "go to
      // definition" means the word clicked on.
      if (mouse.button === Qt.RightButton) {
        if (view.ed.modeName !== "visual") {
          view.client.mouse("left", "press", "", row(mouse.y), col(mouse.x));
          view.client.mouse("left", "release", "", row(mouse.y), col(mouse.x));
        }
        view.contextRequested(mouse.x, mouse.y);
        return;
      }
      // A CLOSED FOLD'S PILL OPENS IT. "⋯ N lines" read as text that had
      // been cut off, with nothing to say it could be had back (user,
      // 2026-10-09): the cursor goes to the fold and the fold opens.
      if (mouse.button === Qt.LeftButton && mouse.modifiers === Qt.NoModifier && foldPillAt(mouse.x, mouse.y)) {
        view.client.mouse("left", "press", "", row(mouse.y), col(mouse.x));
        view.client.mouse("left", "release", "", row(mouse.y), col(mouse.x));
        view.client.cmd("normal! zo");
        return;
      }
      // the gutter's ring (EditorRow): the fold on its line, opened or closed
      const ringLine = mouse.button === Qt.LeftButton && mouse.modifiers === Qt.NoModifier
        ? foldRingAt(mouse.x, mouse.y) : 0;
      if (ringLine > 0) {
        view.client.cmd("call cursor(" + ringLine + ", 1) | normal! za");
        return;
      }
      held = button(mouse.button);
      lastRow = row(mouse.y);
      lastCol = col(mouse.x);
      view.client.mouse(held, "press", mods(mouse.modifiers), lastRow, lastCol);
    }
    // whether (x, y) is on a closed fold's "⋯ N lines" pill: the row's `fc`
    // is where the pill starts and how many cells it takes, from the start
    // of the window's text
    // the line whose fold ring (x, y) is on, or 0: the two cells left of the
    // text, a little wider than the glyph, as the tree's expander is
    function foldRingAt(x, y) {
      const r = row(y), c = col(x);
      const ws = view.ed.wins;
      for (let i = 0; i < ws.length; ++i) {
        const w = ws[i];
        if (r < w.row || r >= w.row + w.height || c < w.col || c >= w.col + w.width) continue;
        const info = view.ed.rowsOf(w.id)[r - w.row];
        if (!info || !info.fo || info.n <= 0) return 0;
        const at = c - w.col;
        const off = w.textoff || 0;
        return at >= off - 2 && at < off ? info.n : 0;
      }
      return 0;
    }
    function foldPillAt(x, y) {
      const r = row(y), c = col(x);
      const ws = view.ed.wins;
      for (let i = 0; i < ws.length; ++i) {
        const w = ws[i];
        if (r < w.row || r >= w.row + w.height || c < w.col || c >= w.col + w.width) continue;
        const info = view.ed.rowsOf(w.id)[r - w.row];
        if (!info || !info.fc) return false;
        const at = c - w.col - (w.textoff || 0);
        return at >= info.fc[0] - 1 && at <= info.fc[0] + info.fc[1];
      }
      return false;
    }
    hoverEnabled: true
    onExited: { peek.hide(); overRail = false; overFold = false; }
    onPositionChanged: (mouse) => {
      if (held === "") {
        overRail = onRail(mouse.x, mouse.y);
        overFold = !overRail && (foldRingAt(mouse.x, mouse.y) > 0 || foldPillAt(mouse.x, mouse.y));
        if (overRail || overFold) peek.hide(); else peek.hover(mouse.x, mouse.y);
        return;
      }
      const r = row(mouse.y), c = col(mouse.x);
      if (r === lastRow && c === lastCol) return;
      lastRow = r;
      lastCol = c;
      view.client.mouse(held, "drag", mods(mouse.modifiers), r, c);
    }
    onReleased: (mouse) => {
      if (held === "") return;
      view.client.mouse(held, "release", mods(mouse.modifiers), row(mouse.y), col(mouse.x));
      held = "";
    }
    onWheel: (wheel) => {
      // Ctrl and the wheel: zoom, as everywhere else
      if (wheel.modifiers & Qt.ControlModifier) {
        if (wheel.angleDelta.y !== 0) view.zoomRequested(wheel.angleDelta.y > 0 ? 1 : -1);
        return;
      }
      // THE SHELL'S ONE FEEL (morpheus/scrollfeel.js, what Elastic moves
      // every list with), in nvim's whole lines. A touchpad's fingers are
      // followed pixel for pixel and, let go, coast; a wheel's notch is four
      // lines (the terminal's three felt slow here), more when it is spun.
      // What nvim could not take — the top, the end — goes to the window's
      // rubber band instead.
      const now = Date.now();
      const pd = wheel.pixelDelta.y;
      if (wheel.phase !== Qt.NoScrollPhase && (pd !== 0 || wheel.phase === Qt.ScrollEnd)) {
        if (wheel.phase === Qt.ScrollBegin) { coast.stop(); track.at = []; track.d = []; }
        if (wheel.phase === Qt.ScrollEnd) {
          const v = Feel.clampVelocity(Feel.trackVelocity(track, now));
          if (Math.abs(v) > Feel.REST) coast.launch(wheel.x, wheel.y, v);
          return;
        }
        coast.stop();
        if (wheel.phase !== Qt.ScrollMomentum) Feel.trackAdd(track, now, pd);
        feed(pd, wheel.x, wheel.y);
        return;
      }
      coast.stop();
      const notches = wheel.angleDelta.y / 120;
      if (notches === 0) return;
      const gain = Feel.wheelGain(Feel.rateAdd(rate, now, notches));
      feed(notches * view.wheelLines * gain * view.cellH, wheel.x, wheel.y);
    }
    // `px` of scroll (positive: towards the top), added up until it makes
    // whole lines, which go to nvim; an answer that nothing moved bands the
    // window and ends any coast
    function feed(px, x, y) {
      acc += px / view.cellH;
      const lines = acc > 0 ? Math.floor(acc) : Math.ceil(acc);
      if (lines === 0) return;
      acc -= lines;
      area.owed += lines;
      area.owedAt = { x: x, y: y, px: px };
      if (!area.inFlight) area.sendOwed();
    }
    // ── ONE SCROLL IN FLIGHT ──────────────────────────────────────────
    // Each notch used to be its own request. nvim answers a scroll in ~3 ms
    // on most files, but an 8,000-line markdown file takes it far longer per
    // scroll, and the requests queued faster than it could answer: the user
    // let go of the wheel and the text went on scrolling, through the
    // backlog, by itself (2026-10-09). Now the lines add up while one
    // request is out and go as one when it is answered, so letting go
    // stops it within a single answer, however slow.
    property int owed: 0
    property var owedAt: null
    property bool inFlight: false
    function sendOwed() {
      if (area.owed === 0) { area.inFlight = false; return; }
      const n = area.owed;
      const at = area.owedAt;
      area.owed = 0;
      area.inFlight = true;
      owedLost.restart();
      const target = windowAt(at.x, at.y);
      const sent = view.client.request("scroll", { lines: -n, row: row(at.y), col: col(at.x) },
        (moved) => {
          owedLost.stop();
          if (moved === false) { coast.stop(); area.owed = 0; if (target) target.band(at.px); }
          area.inFlight = false;
          area.sendOwed();
        });
      if (!sent) { owedLost.stop(); area.inFlight = false; area.owed = 0; }
    }
    // an answer that never comes (nvim restarted under it) must not hold
    // every later scroll back for good
    Timer { id: owedLost; interval: 1000; onTriggered: { area.inFlight = false; area.sendOwed(); } }
    property real acc: 0
    readonly property var rate: Feel.makeRate()
    readonly property var track: Feel.makeTrack()
    FrameAnimation {
      id: coast
      property real vel: 0
      property real px: 0
      property real py: 0
      function launch(x, y, v) { coast.px = x; coast.py = y; coast.vel = v; coast.start(); }
      onTriggered: {
        const s = Feel.coastStep(coast.vel, Math.min(64, coast.frameTime * 1000));
        area.feed(s.d, coast.px, coast.py);
        coast.vel = s.v;
        if (s.v === 0) coast.stop();
      }
    }
  }

  // the dividers' grips — see "between the windows"; above `area`
  Repeater {
    model: view.ed.wins
    Item {
      id: grips
      required property var modelData
      readonly property var w: modelData
      readonly property var g: view.seamOf(w)
      MouseArea {
        id: vGrip
        visible: grips.g.right
        x: grips.g.vx - 4
        y: grips.g.y
        width: 9
        height: grips.g.h
        hoverEnabled: true
        cursorShape: Qt.SizeHorCursor
        preventStealing: true
        property int sent: -1
        readonly property bool hot: vGrip.pressed || vGrip.containsMouse
        onHotChanged: view.seamHot = vGrip.hot ? "v:" + grips.w.id
          : (view.seamHot === "v:" + grips.w.id ? "" : view.seamHot)
        onPressed: vGrip.sent = -1
        onPositionChanged: (m) => {
          if (!vGrip.pressed) return;
          const px = vGrip.mapToItem(view, m.x, 0).x;
          const n = Math.max(1, Math.round(px / view.cellW) - grips.w.col);
          if (n === vGrip.sent) return;
          vGrip.sent = n;
          view.client.cmd("lua vim.api.nvim_win_set_width(" + grips.w.id + ", " + n + ")");
        }
        onDoubleClicked: view.client.cmd("wincmd =")
      }
      MouseArea {
        id: hGrip
        visible: grips.g.top
        x: grips.g.x
        y: grips.g.hy - 4
        width: grips.g.w
        height: 9
        hoverEnabled: true
        cursorShape: Qt.SizeVerCursor
        preventStealing: true
        property int sent: -1
        readonly property bool hot: hGrip.pressed || hGrip.containsMouse
        onHotChanged: view.seamHot = hGrip.hot ? "h:" + grips.w.id
          : (view.seamHot === "h:" + grips.w.id ? "" : view.seamHot)
        onPressed: hGrip.sent = -1
        // this seam is the TOP of w, so a drag sizes the window above it:
        // from that window's own top row to the pointer
        onPositionChanged: (m) => {
          if (!hGrip.pressed) return;
          const ws = view.ed.wins;
          let above = null;
          for (let i = 0; i < ws.length; ++i) {
            const o = ws[i];
            if (o.row + o.height === grips.w.row && o.col < grips.w.col + grips.w.width
                && o.col + o.width > grips.w.col) { above = o; break; }
          }
          if (!above) return;
          const py = hGrip.mapToItem(view, 0, m.y).y;
          const n = Math.max(1, Math.round(py / view.cellH) - above.row);
          if (n === hGrip.sent) return;
          hGrip.sent = n;
          view.client.cmd("lua vim.api.nvim_win_set_height(" + above.id + ", " + n + ")");
        }
        onDoubleClicked: view.client.cmd("wincmd =")
      }
    }
  }
}
