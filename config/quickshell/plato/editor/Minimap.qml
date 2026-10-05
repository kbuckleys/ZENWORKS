// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// The minimap: the file in miniature down the editor's right edge — every
// line two pixels tall, every character under a pixel wide, in its syntax
// colour — with the part on screen outlined. A click puts the view there;
// a drag carries it; the wheel scrolls the editor as it does over the text.
//
// nvim sends the lines (nvim/lua/plato/minimap.lua): as many as fit, and for
// a longer file the stretch the view is in, sliding through it as you go.
// The scrollbar's marks (errors, matches, git) are drawn over it, at the
// same lines, so the map shows where things are as well as what is there.

import QtQuick
import "../../morpheus"

Item {
  id: map

  required property var ed
  required property var client
  readonly property real lineH: 2
  readonly property real charW: 0.8
  // how many lines the map has room for: told to nvim, which sends that many
  readonly property int rows: Math.max(20, Math.floor(map.height / map.lineH))
  signal rowsWanted(int rows)
  // held down on the map: the editor follows the pointer without its glide,
  // which made a drag lag behind the hand
  readonly property bool dragging: drag.pressed
  onRowsChanged: rowsTimer.restart()
  Timer { id: rowsTimer; interval: 120; onTriggered: map.rowsWanted(map.rows) }

  readonly property var mm: map.ed.minimap
  readonly property int first: map.mm ? map.mm.first : 1
  readonly property var win: map.ed.curWin
  readonly property var scroll: { map.ed.frame; return map.win ? map.ed.scrollOf(map.win.id) : null; }
  readonly property int viewRows: map.win ? map.win.height : 0

  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.12)
  }
  Rectangle { width: 1; height: parent.height; color: Zenon.border; opacity: 0.6 }

  Canvas {
    id: art
    anchors.fill: parent
    anchors.leftMargin: 6
    onPaint: {
      const ctx = getContext("2d");
      ctx.reset();
      const d = map.mm;
      if (!d) return;
      const lines = d.lines;
      const normal = String(map.ed.normalFg);
      ctx.globalAlpha = 0.75;
      for (let i = 0; i < lines.length; ++i) {
        const runs = lines[i];
        if (!runs) continue;
        const y = i * map.lineH;
        if (y > height) break;
        for (let k = 0; k < runs.length; ++k) {
          const r = runs[k];
          ctx.fillStyle = r[2] ? r[2] : normal;
          ctx.fillRect(r[0] * map.charW, y, Math.max(0.8, r[1] * map.charW), map.lineH - 0.5);
        }
      }
    }
    Connections {
      target: map
      function onMmChanged() { art.requestPaint(); }
    }
  }

  // the marks, at their lines on the map (errors, warnings, matches, git)
  Repeater {
    // only the marks on the map's own stretch of the file, one a row a side
    // (the most urgent): not every mark in the file, mostly drawn nowhere
    model: {
      if (!map.mm) return [];
      const rank = { e: 0, w: 1, s: 2, i: 3, h: 4, d: 0, c: 1, a: 2 };
      const best = {};
      const list = map.ed.marks;
      for (let i = 0; i < list.length; ++i) {
        const at = list[i][0] - map.first, k = list[i][1];
        if (at < 0 || at * map.lineH >= map.height) continue;
        const key = (k === "a" || k === "c" || k === "d" ? "g" : "o") + at;
        if (!best[key] || rank[k] < rank[best[key][1]]) best[key] = list[i];
      }
      return Object.keys(best).map((key) => best[key]);
    }
    Rectangle {
      required property var modelData
      readonly property int at: modelData[0] - map.first
      readonly property string k: modelData[1]
      x: k === "a" || k === "c" || k === "d" ? 1 : map.width - 4
      y: at * map.lineH
      width: 3
      height: map.lineH
      color: k === "e" ? Zenon.red : k === "w" ? Zenon.yellow : k === "s" ? Zenon.sand
        : k === "a" ? Zenon.green : k === "c" ? Zenon.yellow : k === "d" ? Zenon.red : Zenon.blue
    }
  }

  // ── what is on screen ──────────────────────────────────────────────
  Rectangle {
    id: viewport
    visible: map.scroll !== null && map.mm !== null
    x: 1
    width: map.width - 1
    y: map.scroll ? (map.scroll.top - map.first) * map.lineH : 0
    height: Math.max(8, map.viewRows * map.lineH)
    // the shell's cursor colour, as every "you are here" in it
    color: Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, drag.pressed ? 0.32 : hover.hovered ? 0.26 : 0.20)
    border.width: 1
    border.color: Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, drag.pressed ? 0.85 : 0.60)
    Behavior on y { enabled: !drag.pressed; NumberAnimation { duration: Zenon.brisk; easing.type: Zenon.travelEase } }
  }
  HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }

  // a click or a drag: the view centred on the line under the pointer
  MouseArea {
    id: drag
    anchors.fill: parent
    function goTo(y) {
      if (!map.win) return;
      const line = map.first + Math.floor(y / map.lineH) - Math.floor(map.viewRows / 2);
      map.client.scrollTo(map.win.id, Math.max(1, line));
    }
    onPressed: (m) => drag.goTo(m.y)
    onPositionChanged: (m) => { if (drag.pressed) drag.goTo(m.y); }
    // the wheel is the editor's (EditorView: the shell's one feel), not a
    // second, fixed step of the map's own
    onWheel: (w) => { w.accepted = false; }
  }
}
