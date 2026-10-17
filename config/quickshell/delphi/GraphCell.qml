// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ONE ROW OF THE COMMIT GRAPH. The lanes come laid out from the backend
// (delphi/core/graph.py): the node's column, and the row's two halves as
// [from, to, color] — the top half from the row's top edge to its center,
// the bottom half from the center down. This only draws them: a straight
// stroke where a line passes, an S where it changes column, a dot for the
// commit (a ring for a merge, larger for the one checked out).
//
// Colors are the graph's own numbers, mapped onto the theme's accents
// (delphi.js laneInk), and repainted on a theme change.

import QtQuick
import "../morpheus"
import "delphi.js" as D

Canvas {
  id: cell
  property var g: null
  property bool merge: false
  property bool head: false
  property real lane: 14
  width: cell.g ? Math.max(1, cell.g.width) * cell.lane + 6 : 0
  renderStrategy: Canvas.Cooperative

  onGChanged: requestPaint()
  onHeightChanged: requestPaint()
  Connections { target: Zenon; function onThemeEpochChanged() { cell.requestPaint(); } }

  function xOf(c) { return 3 + c * cell.lane + cell.lane / 2; }
  onPaint: {
    const ctx = getContext("2d");
    ctx.reset();
    const g = cell.g;
    if (!g) return;
    const h = cell.height, mid = h / 2;
    ctx.lineWidth = 2;
    ctx.lineCap = "round";
    const seg = (a, b, c, y0, y1) => {
      ctx.strokeStyle = Zenon[D.laneInk(c)];
      ctx.beginPath();
      const x0 = cell.xOf(a), x1 = cell.xOf(b);
      ctx.moveTo(x0, y0);
      if (a === b) ctx.lineTo(x1, y1);
      else {
        const m = (y0 + y1) / 2;
        ctx.bezierCurveTo(x0, m, x1, m, x1, y1);
      }
      ctx.stroke();
    };
    for (const s of g.top) seg(s[0], s[1], s[2], 0, mid);
    for (const s of g.bottom) seg(s[0], s[1], s[2], mid, h);
    const x = cell.xOf(g.col), r = cell.head ? 5 : 4;
    const ink = Zenon[D.laneInk(g.colour)];
    ctx.beginPath();
    ctx.arc(x, mid, r, 0, Math.PI * 2);
    if (cell.merge) {
      ctx.fillStyle = Zenon.layerBg;
      ctx.fill();
      ctx.lineWidth = 2;
      ctx.strokeStyle = ink;
      ctx.stroke();
    } else {
      ctx.fillStyle = ink;
      ctx.fill();
    }
    if (cell.head) {
      ctx.beginPath();
      ctx.arc(x, mid, r + 3, 0, Math.PI * 2);
      ctx.lineWidth = 1.5;
      ctx.strokeStyle = Zenon.alpha(ink, 0.5);
      ctx.stroke();
    }
  }
}
