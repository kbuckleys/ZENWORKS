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
import "../../morpheus/scrollfeel.js" as Feel

Item {
  id: view

  required property var ed
  required property var client
  property int fontSize: 16
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
  readonly property real mapW: view.minimap && view.width > 70 * view.cellW + 100 ? 100 : 0
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
      smoothScroll: view.smoothScroll && !minimapItem.dragging
      animateLayout: view.animateLayout
      // the text area's width as it is now, for the window at the right edge
      liveW: view.width - view.mapW
      gitGutter: view.gitGutter
      jumpTrail: view.jumpTrail
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
  // nvim leaves one column between side-by-side windows, and with no status
  // lines nothing between stacked ones; plato draws a hairline in each place.
  Repeater {
    model: view.ed.wins
    Item {
      required property var modelData
      readonly property var w: modelData
      // a separator on the right, when another window is there
      Rectangle {
        visible: w.col + w.width < view.ed.gridCols
        x: (w.col + w.width) * view.cellW + Math.floor(view.cellW / 2)
        y: w.row * view.cellH
        width: 1
        height: w.height * view.cellH
        color: Zenon.border
      }
      // and on top, when one is above it
      Rectangle {
        visible: w.row > 0
        x: w.col * view.cellW
        y: w.row * view.cellH
        width: w.width * view.cellW
        height: 1
        color: Zenon.border
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
    if (m === "replace") return "underline";
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
  readonly property real curX: view.ed.curWin
    ? (view.ed.curWin.col + view.ed.curWin.textoff + view.ed.cursorCol) * view.cellW : 0
  readonly property real curY: (view.ed.curWin
    ? (view.ed.curWin.row + view.ed.cursorRow) * view.cellH : 0)
    + (view.curItem ? view.curItem.body.y : 0)

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
      enabled: cursor.glides
      NumberAnimation { duration: Zenon.brisk; easing.type: Zenon.travelEase }
    }
    Behavior on y {
      // riding a scroll glide is not a move of its own: no second easing
      enabled: cursor.glides && (!view.curItem || view.curItem.body.y === 0)
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

    Rectangle {
      id: caret
      visible: view.activeFocus
      y: view.shape === "underline" ? view.cellH - 2 : 0
      width: view.shape === "bar" ? 2 : view.cellW
      height: view.shape === "underline" ? 2 : view.cellH
      color: view.textInk
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
          return Array.from(r.t)[view.ed.cursorChar] || "";
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
        const chars = Array.from(row.t);
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
  function flash(ev) { flashes.show(ev); }

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
  //   <Space>        the leader menu — in normal mode only, so it never
  //                  steals a space from insert mode or a pending operator
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
    if (normal && event.key === Qt.Key_Space && m === 0) {
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
    cursorShape: overRail || view.railHeld ? Qt.ArrowCursor : Qt.IBeamCursor
    property bool overRail: false
    function onRail(x, y) {
      const under = windowAt(x, y);
      return !!under && x >= under.x + under.width - 12;
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
      held = button(mouse.button);
      lastRow = row(mouse.y);
      lastCol = col(mouse.x);
      view.client.mouse(held, "press", mods(mouse.modifiers), lastRow, lastCol);
    }
    hoverEnabled: true
    onExited: { peek.hide(); overRail = false; }
    onPositionChanged: (mouse) => {
      if (held === "") {
        overRail = onRail(mouse.x, mouse.y);
        if (overRail) peek.hide(); else peek.hover(mouse.x, mouse.y);
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
      const target = windowAt(x, y);
      view.client.request("scroll", { lines: -lines, row: row(y), col: col(x) },
        (moved) => { if (moved === false) { coast.stop(); if (target) target.band(px); } });
    }
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
}
