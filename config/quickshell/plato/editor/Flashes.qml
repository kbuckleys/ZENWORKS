// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A yank lights up, and a delete fades out where it was.
//
// nvim measures the region (editing.lua, on TextYankPost) and sends it as
// runs of cells on its grid; this draws them, over the text and under the
// floats, and lets each go once its animation is done.
//
//   yank     a wash of yellow that rises over the text and ebbs away
//   delete   A GHOST OF WHAT WENT. TextYankPost runs before the text is
//            taken, so the rows on screen when the flash arrives still hold
//            it: each run is drawn again from them, in red, on the editor's
//            own background, over whatever slid into its place. A line is
//            struck through it, and it fades — a whole line folding shut as
//            it goes, a few characters lifting away.
//
//   undo     A REWIND: a cyan wash sweeps back across what the undo changed,
//   redo     right to left, with a bright edge leading it, and fades; a redo
//            sweeps the other way. Each covers the line's text, not the
//            empty width past it (editing.lua's undos()).
//
// The settings sheet's "Flash yanks and deletes" turns them all off (in the
// engine: nothing is sent).

import QtQuick
import "../../morpheus"
import "cells.js" as Cells

Item {
  id: root

  required property var ed
  required property real cellW
  required property real cellH
  required property font face
  // how far a window's drawing is gliding behind nvim, at a grid row
  function lagAt(row) { return 0; }

  ListModel { id: live }
  property int _uid: 0

  // the characters of grid cells [col, col+len) on grid row `row`, as the
  // window there is drawing them right now
  function textAt(row, col, len) {
    const ws = root.ed.wins;
    for (let i = 0; i < ws.length; ++i) {
      const w = ws[i];
      if (row < w.row || row >= w.row + w.height || col < w.col || col >= w.col + w.width) continue;
      const r = root.ed.rowsOf(w.id)[row - w.row];
      if (!r) return "";
      const from = col - w.col - w.textoff;
      // cells, not characters: a wide character before the flash is two
      return Cells.slice(r.t, Math.max(0, from), Math.max(0, len + Math.min(0, from)));
    }
    return "";
  }

  ListModel { id: sweeps }
  // how many cells of grid row `row` hold text, from `col` on
  function textCells(row, col, len) {
    return Cells.count(root.textAt(row, col, len).replace(/\s+$/, ""));
  }
  function show(ev) {
    const cells = root.ed._list(ev.cells);
    if (ev.kind === "undo" || ev.kind === "redo") {
      for (const c of cells) {
        // the line's text, from its first character: not the indent before
        // it, nor the empty width after
        const t = root.textAt(c.row, c.col, c.len);
        const lead = Cells.count(t) - Cells.count(t.replace(/^\s+/, ""));
        const n = Math.max(1, root.textCells(c.row, c.col, c.len) - lead);
        sweeps.append({ uid: ++root._uid, back: ev.kind === "undo",
          gx: (c.col + lead) * root.cellW, gy: c.row * root.cellH + root.lagAt(c.row),
          gw: Math.min(c.len - lead, n + 1) * root.cellW });
      }
      while (sweeps.count > 100) sweeps.remove(0);
      return;
    }
    const del = ev.kind === "delete";
    for (const c of cells) {
      live.append({
        uid: ++root._uid, del: del, linewise: ev.linewise === true,
        gx: c.col * root.cellW, gy: c.row * root.cellH + root.lagAt(c.row),
        gw: c.len * root.cellW, ghost: del ? root.textAt(c.row, c.col, c.len) : "",
      });
    }
    // a burst (a held `x`) never piles up more than a screen of them
    while (live.count > 200) live.remove(0);
  }
  function swept(uid) {
    for (let i = 0; i < sweeps.count; ++i) if (sweeps.get(i).uid === uid) { sweeps.remove(i); return; }
  }
  function done(uid) {
    for (let i = 0; i < live.count; ++i) if (live.get(i).uid === uid) { live.remove(i); return; }
  }

  Repeater {
    model: live
    Item {
      id: fx
      required property int uid
      required property bool del
      required property bool linewise
      required property real gx
      required property real gy
      required property real gw
      required property string ghost

      x: fx.gx
      y: fx.gy
      width: fx.gw
      height: root.cellH
      opacity: 0
      transform: Scale { id: fold; origin.y: root.cellH / 2 }

      // ── yank ────────────────────────────────────────────────────────
      Rectangle {
        visible: !fx.del
        anchors.fill: parent
        anchors.topMargin: -1
        anchors.bottomMargin: -1
        radius: 3
        color: Qt.rgba(Zenon.yellow.r, Zenon.yellow.g, Zenon.yellow.b, 0.38)
      }

      // ── delete ──────────────────────────────────────────────────────
      Rectangle {
        visible: fx.del
        anchors.fill: parent
        color: Zenon.layerBg
        Rectangle {
          anchors.fill: parent
          radius: 2
          color: Qt.rgba(Zenon.red.r, Zenon.red.g, Zenon.red.b, 0.20)
        }
        Text {
          height: parent.height
          verticalAlignment: Text.AlignVCenter
          textFormat: Text.PlainText
          font: root.face
          color: Zenon.red
          text: fx.ghost
        }
        Rectangle {
          id: strike
          anchors.verticalCenter: parent.verticalCenter
          height: 1.5
          width: 0
          color: Zenon.red
        }
      }

      SequentialAnimation {
        running: true
        onFinished: root.done(fx.uid)
        ParallelAnimation {
          NumberAnimation { target: fx; property: "opacity"; to: 1; duration: fx.del ? 0 : 70; easing.type: Easing.OutQuad }
          NumberAnimation { target: strike; property: "width"; to: fx.gw; duration: fx.del ? 110 : 0; easing.type: Easing.OutCubic }
        }
        PauseAnimation { duration: fx.del ? 40 : 140 }
        ParallelAnimation {
          NumberAnimation { target: fx; property: "opacity"; to: 0; duration: fx.del ? 300 : 460; easing.type: Easing.InOutQuad }
          // a line folds shut; a few characters lift away
          NumberAnimation { target: fold; property: "yScale"; to: fx.del && fx.linewise ? 0.15 : 1; duration: 300; easing.type: Easing.InQuad }
          NumberAnimation { target: fx; property: "y"; to: fx.gy - (fx.del && !fx.linewise ? root.cellH * 0.35 : 0); duration: 300; easing.type: Easing.OutQuad }
        }
      }
    }
  }

  // ── undo and redo: the sweep ───────────────────────────────────────
  Repeater {
    model: sweeps
    Item {
      id: sw
      required property int uid
      required property bool back
      required property real gx
      required property real gy
      required property real gw
      x: sw.gx
      y: sw.gy
      width: sw.gw
      height: root.cellH
      clip: true

      // the wash, growing from the side the sweep starts on
      Rectangle {
        id: wash
        width: 0
        height: parent.height
        x: sw.back ? parent.width - width : 0
        radius: 2
        color: Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.28)
      }
      // its leading edge
      Rectangle {
        id: edge
        width: 2
        height: parent.height
        x: sw.back ? parent.width - wash.width : wash.width - width
        color: Zenon.cyan
      }

      SequentialAnimation {
        running: true
        onFinished: root.swept(sw.uid)
        NumberAnimation { target: wash; property: "width"; from: 0; to: sw.gw; duration: 240; easing.type: Easing.OutCubic }
        ParallelAnimation {
          NumberAnimation { target: edge; property: "opacity"; to: 0; duration: 160; easing.type: Easing.OutQuad }
          SequentialAnimation {
            PauseAnimation { duration: 90 }
            NumberAnimation { target: sw; property: "opacity"; to: 0; duration: 380; easing.type: Easing.InOutQuad }
          }
        }
      }
    }
  }
}
