// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A SKETCH — Apple's drawing in a note: pens in the theme's colours, three
// widths, a highlighter, an eraser that takes whole strokes, undo and
// redo. Kept as strokes by colour name (notes.js paintStrokes), so the
// note draws it afresh in whatever theme is worn; a picture of it is saved
// beside the note for exports and thumbnails.
//
//   ctrl+z / ctrl+shift+z   undo, redo       e  eraser     h  highlighter
//   1–7  a pen's colour     [ ]  thinner, thicker          return  done

import QtQuick
import "../morpheus"
import "notes.js" as N

Item {
  id: pad
  property var win: null
  signal finished(var strokes, bool ok)

  property var strokes: []
  property var undone: []
  property var live: null
  property string pen: "ink"
  property real width_: 0.006
  property bool marker: false
  property bool erasing: false
  readonly property real aspect: board.height / Math.max(1, board.width)
  readonly property var pens: ["ink", "cyan", "magenta", "yellow", "green", "red", "blue"]
  function inkOf(name) { return String(Zenon[name] || Zenon.ink); }

  function begin(strokes) {
    pad.strokes = (strokes || []).map((s) => Object.assign({}, s));
    pad.undone = [];
    pad.live = null;
    pad.erasing = false;
    paper.requestPaint();
  }
  function save(path, done) {
    paper.requestPaint();
    Qt.callLater(() => { paper.save(path); done(); });
  }
  function undo() { if (pad.strokes.length === 0) return; pad.undone = pad.undone.concat([pad.strokes[pad.strokes.length - 1]]); pad.strokes = pad.strokes.slice(0, -1); paper.requestPaint(); }
  function redo() { if (pad.undone.length === 0) return; pad.strokes = pad.strokes.concat([pad.undone[pad.undone.length - 1]]); pad.undone = pad.undone.slice(0, -1); paper.requestPaint(); }
  function key(e) {
    const ctrl = e.modifiers & Qt.ControlModifier, shift = e.modifiers & Qt.ShiftModifier;
    if (ctrl && e.key === Qt.Key_Z && !shift) { pad.undo(); return true; }
    if (ctrl && (e.key === Qt.Key_Y || e.key === Qt.Key_Z && shift)) { pad.redo(); return true; }
    if (e.key === Qt.Key_E) { pad.erasing = !pad.erasing; return true; }
    if (e.key === Qt.Key_H) { pad.marker = !pad.marker; pad.erasing = false; return true; }
    if (e.key >= Qt.Key_1 && e.key <= Qt.Key_7) { pad.pen = pad.pens[e.key - Qt.Key_1]; pad.erasing = false; return true; }
    if (e.key === Qt.Key_BracketLeft) { pad.width_ = Math.max(0.002, pad.width_ / 1.6); return true; }
    if (e.key === Qt.Key_BracketRight) { pad.width_ = Math.min(0.04, pad.width_ * 1.6); return true; }
    if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { pad.finished(pad.strokes, true); return true; }
    return false;
  }
  Connections { target: Zenon; function onThemeEpochChanged() { paper.requestPaint(); } }

  // ── THE TOOLS ──
  Row {
    id: tools
    x: 18
    y: 14
    spacing: 8
    Repeater {
      model: pad.pens
      delegate: Rectangle {
        required property string modelData
        width: 26
        height: 26
        radius: 13
        anchors.verticalCenter: parent.verticalCenter
        color: Zenon[modelData] || Zenon.ink
        border.width: pad.pen === modelData && !pad.erasing ? 3 : 1
        border.color: pad.pen === modelData && !pad.erasing ? Zenon.cyan : Zenon.border
        MouseArea { anchors.fill: parent; onClicked: { pad.pen = modelData; pad.erasing = false; } }
      }
    }
    Item { width: 10; height: 1 }
    Repeater {
      model: [[0.003, 6], [0.006, 10], [0.014, 16]]
      delegate: Rectangle {
        required property var modelData
        anchors.verticalCenter: parent.verticalCenter
        width: 30
        height: 30
        radius: Zenon.windowRadius
        color: Math.abs(pad.width_ - modelData[0]) < 0.001 ? Zenon.alpha(Zenon.cyan, 0.16) : "transparent"
        border.width: 1
        border.color: Zenon.border
        Rectangle { anchors.centerIn: parent; width: modelData[1]; height: width; radius: width / 2; color: Zenon.ink }
        MouseArea { anchors.fill: parent; onClicked: pad.width_ = modelData[0] }
      }
    }
    Item { width: 10; height: 1 }
    DialogButton { anchors.verticalCenter: parent.verticalCenter; glyph: true; label: "\u{F0652}"; ink: pad.marker ? Zenon.yellow : Zenon.muted; onClicked: { pad.marker = !pad.marker; pad.erasing = false; } }
    DialogButton { anchors.verticalCenter: parent.verticalCenter; glyph: true; label: "\u{F01FE}"; ink: pad.erasing ? Zenon.red : Zenon.muted; onClicked: pad.erasing = !pad.erasing }
    DialogButton { anchors.verticalCenter: parent.verticalCenter; glyph: true; label: ""; ready: pad.strokes.length > 0; onClicked: pad.undo() }
    DialogButton { anchors.verticalCenter: parent.verticalCenter; glyph: true; label: ""; ready: pad.undone.length > 0; onClicked: pad.redo() }
    DialogButton { anchors.verticalCenter: parent.verticalCenter; label: "Clear"; ready: pad.strokes.length > 0; onClicked: { pad.undone = pad.strokes.slice().reverse(); pad.strokes = []; paper.requestPaint(); } }
  }
  Row {
    anchors.right: parent.right
    anchors.rightMargin: 18
    y: 14
    spacing: 8
    DialogButton { label: "Cancel"; onClicked: pad.finished(null, false) }
    DialogButton { label: "Done"; ink: Zenon.cyan; primary: true; onClicked: pad.finished(pad.strokes, true) }
  }

  // ── THE PAPER ──
  Rectangle {
    id: board
    x: 18
    y: tools.y + 44
    width: parent.width - 36
    height: parent.height - y - 18
    radius: Zenon.windowRadius
    color: Zenon.wash(0.03)
    border.width: 1
    border.color: Zenon.border
    // dots, as a sketchbook's
    Canvas {
      anchors.fill: parent
      opacity: 0.25
      onPaint: {
        const c = getContext("2d");
        c.reset();
        c.fillStyle = String(Zenon.muted);
        for (let x = 24; x < width; x += 24) for (let y = 24; y < height; y += 24) c.fillRect(x, y, 1.5, 1.5);
      }
    }
    Canvas {
      id: paper
      anchors.fill: parent
      onPaint: {
        const c = getContext("2d");
        c.reset();
        N.paintStrokes(c, pad.strokes.concat(pad.live ? [pad.live] : []), width, pad.inkOf);
      }
    }
    MouseArea {
      anchors.fill: parent
      cursorShape: pad.erasing ? Qt.PointingHandCursor : Qt.CrossCursor
      preventStealing: true
      function at(m) { return [m.x / board.width, m.y / board.width]; }
      function erase(m) {
        const p = at(m), r = 10 / board.width;
        const keep = pad.strokes.filter((s) => !(s.p || []).some((q) => Math.abs(q[0] - p[0]) < r && Math.abs(q[1] - p[1]) < r));
        if (keep.length !== pad.strokes.length) { pad.undone = []; pad.strokes = keep; paper.requestPaint(); }
      }
      onPressed: (m) => {
        if (pad.erasing) { erase(m); return; }
        pad.live = { c: pad.pen, w: pad.marker ? Math.max(0.02, pad.width_ * 3) : pad.width_, hl: pad.marker, p: [at(m)] };
        paper.requestPaint();
      }
      onPositionChanged: (m) => {
        if (pad.erasing) { if (pressed) erase(m); return; }
        if (!pad.live) return;
        pad.live.p.push(at(m));
        paper.requestPaint();
      }
      onReleased: {
        if (!pad.live) return;
        const s = pad.live;
        s.p = N.thin(s.p, 1.5 / board.width);
        pad.live = null;
        pad.strokes = pad.strokes.concat([s]);
        pad.undone = [];
        paper.requestPaint();
      }
    }
  }
}
