// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A selection over several rows, drawn as one shape.
//
// Each row's part is [row, from, to] in cells. Rows next to each other whose
// parts overlap are one outline: down the right-hand ends, back up the
// left-hand starts. Every corner of it is then rounded by the same rule — a
// quadratic curve through the corner, cut back by the radius along both
// edges — which rounds an outside corner out and the step between two rows
// in, as an editor that draws its selections well does. Parts that do not
// touch (the end of a long line above the start of a short one) are
// separate outlines.

import QtQuick
import QtQuick.Shapes
import "../../morpheus"

Shape {
  id: sel

  required property real cellW
  required property real cellH
  required property real textX
  property color ink: "transparent"
  property var parts: []
  property string key: ""
  readonly property real radius: 4

  preferredRendererType: Shape.CurveRenderer
  visible: sel.parts.length > 0

  // in from nothing: a selection just begun fades in rather than appearing
  onVisibleChanged: if (sel.visible) fadeIn.restart()
  NumberAnimation { id: fadeIn; target: sel; property: "opacity"; from: 0; to: 1; duration: Zenon.fast; easing.type: Easing.OutQuad }

  // the outlines, as corner points: one list a group of touching rows
  function outlines(parts) {
    const groups = [];
    let g = null;
    for (const p of parts) {
      const prev = g ? g[g.length - 1] : null;
      if (prev && p[0] === prev[0] + 1 && p[1] < prev[2] && prev[1] < p[2]) g.push(p);
      else { g = [p]; groups.push(g); }
    }
    const X = (c) => sel.textX + c * sel.cellW;
    const Y = (r) => r * sel.cellH;
    return groups.map((rows) => {
      const pts = [];
      const n = rows.length;
      pts.push([X(rows[0][1]), Y(rows[0][0])], [X(rows[0][2]), Y(rows[0][0])]);
      for (let j = 0; j + 1 < n; ++j) {
        const y = Y(rows[j][0] + 1);
        pts.push([X(rows[j][2]), y], [X(rows[j + 1][2]), y]);
      }
      pts.push([X(rows[n - 1][2]), Y(rows[n - 1][0] + 1)], [X(rows[n - 1][1]), Y(rows[n - 1][0] + 1)]);
      for (let j = n - 1; j > 0; --j) {
        const y = Y(rows[j][0]);
        pts.push([X(rows[j][1]), y], [X(rows[j - 1][1]), y]);
      }
      // the same point twice, and points mid-way along a straight edge,
      // are no corners
      const out = [];
      for (const p of pts) {
        const q = out[out.length - 1];
        if (!q || q[0] !== p[0] || q[1] !== p[1]) out.push(p);
      }
      if (out.length > 1 && out[0][0] === out[out.length - 1][0] && out[0][1] === out[out.length - 1][1]) out.pop();
      const corners = [];
      for (let i = 0; i < out.length; ++i) {
        const a = out[(i - 1 + out.length) % out.length], b = out[i], c = out[(i + 1) % out.length];
        const straight = (a[0] === b[0] && b[0] === c[0]) || (a[1] === b[1] && b[1] === c[1]);
        if (!straight) corners.push(b);
      }
      return corners;
    });
  }

  function svg(parts) {
    let d = "";
    for (const pts of sel.outlines(parts)) {
      const n = pts.length;
      if (n < 3) continue;
      for (let i = 0; i < n; ++i) {
        const p = pts[(i - 1 + n) % n], v = pts[i], q = pts[(i + 1) % n];
        const l1 = Math.hypot(p[0] - v[0], p[1] - v[1]);
        const l2 = Math.hypot(q[0] - v[0], q[1] - v[1]);
        const r = Math.min(sel.radius, l1 / 2, l2 / 2);
        const ax = v[0] + (p[0] - v[0]) / l1 * r, ay = v[1] + (p[1] - v[1]) / l1 * r;
        const bx = v[0] + (q[0] - v[0]) / l2 * r, by = v[1] + (q[1] - v[1]) / l2 * r;
        d += (i === 0 ? "M" : " L") + ax + " " + ay + " Q" + v[0] + " " + v[1] + " " + bx + " " + by;
      }
      d += " Z ";
    }
    return d;
  }

  ShapePath {
    strokeWidth: -1
    strokeColor: "transparent"
    fillColor: sel.ink
    fillRule: ShapePath.WindingFill
    PathSvg { path: sel.svg(sel.parts) }
  }
}
