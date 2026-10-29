// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/

import QtQuick
import "."

Item {
  id: root
  implicitWidth: 48
  implicitHeight: 16

  property var values: []
  property color lineColor: Zenon.cyan
  property color fillColor: Zenon.sparkFill
  property real fillOpacity: 0.18
  property int maxPoints: 32
  property real lineWidth: root.panel ? 2 : 1.4

  // ── THE PANEL LOOK (2026-10-29) ───────────────────────────────────────
  // What the bar's performance tooltips and the jobs card both wear, so a
  // reading over time looks the same wherever it is hovered: a framed well,
  // dashed quarter lines, a fill that fades to nothing at the floor, a dot
  // on the newest point, and the peak written in the corner. The trace fills
  // the well left to right over maxPoints, so a job that has just started
  // is a short line growing rightwards rather than one stretched edge to
  // edge from two samples. Off by default — zeus and chronos draw their own
  // frames round a plain line.
  property bool panel: false
  // `values` are raw (bytes a second, entries a second) rather than 0..100,
  // and are drawn against their own peak: the top of the well is the
  // fastest point on it, which is what the peak label says.
  property bool scaleToPeak: false
  // What the peak is read from (raw, when `values` are levels — the
  // network's are log-scaled), and how it is written: function(max) → text.
  // No format, no label.
  property var peakValues: root.values
  property var peakFormat: null

  // history is trimmed externally, but also handle here
  readonly property var trimmed: {
    if (!root.values || root.values.length <= root.maxPoints) return root.values;
    return root.values.slice(root.values.length - root.maxPoints);
  }
  readonly property real peak: {
    const v = root.peakValues ?? [];
    let m = 0;
    for (let i = Math.max(0, v.length - root.maxPoints); i < v.length; ++i)
      m = Math.max(m, v[i]);
    return m;
  }

  Rectangle {
    anchors.fill: parent
    visible: root.panel
    radius: Zenon.rad(8)
    color: Zenon.wash(0.04)
    border.color: Zenon.border
    border.width: 1
  }

  Text {
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.topMargin: 3
    anchors.rightMargin: 8
    visible: root.panel && root.peakFormat !== null && root.peak > 0
    text: visible ? "Peak " + root.peakFormat(root.peak) : ""
    color: Zenon.muted
    font.family: Zenon.face
    font.weight: Zenon.weight
    font.pixelSize: Zenon.px(11)
  }

  Canvas {
    id: canvas
    anchors.fill: parent
    antialiasing: true
    // Painted synchronously rather than on the cooperative queue: the default
    // can put a frame on screen between the clearRect and the redraw, which
    // reads as a blink. These are small, so painting them inline is free.
    renderStrategy: Canvas.Immediate
    onPaint: {
      const ctx = getContext("2d");
      ctx.clearRect(0, 0, width, height);
      // Inset in the well, by translating rather than by margins so the
      // newest point's dot is never clipped at the canvas edge: room above
      // for the peak, and round the dot.
      const inL = root.panel ? 8 : 0, inR = root.panel ? 10 : 0;
      const inT = root.panel ? 20 : 0, inB = root.panel ? 7 : 0;
      ctx.save();
      ctx.translate(inL, inT);
      const w = width - inL - inR;
      const h = height - inT - inB;

      if (root.panel) {
        // dashed quarter lines, drawn as dashes: Context2D has no setLineDash
        ctx.strokeStyle = Zenon.wash(0.10);
        ctx.lineWidth = 1;
        ctx.beginPath();
        for (let q = 1; q <= 3; ++q) {
          const y = Math.round(h * q / 4) + 0.5;
          for (let x = 0; x < w; x += 7) {
            ctx.moveTo(x, y);
            ctx.lineTo(Math.min(w, x + 3), y);
          }
        }
        ctx.stroke();
      }

      const vals = root.trimmed;
      if (!vals || vals.length < 2) { ctx.restore(); return; }
      const n = vals.length;
      // Plain: scaled to the samples actually held, not to maxPoints. Every
      // module caps its history at 30 while this reserved 32 slots, so the
      // trace was permanently inset by two steps on the left and never
      // reached the right edge — which read as the sparkline sitting
      // off-center in its tooltip. The panel fills over maxPoints instead,
      // on purpose — see above.
      const step = root.panel ? w / Math.max(1, root.maxPoints - 1)
                              : (n > 1 ? w / (n - 1) : 0);
      const top = root.scaleToPeak ? Math.max(root.peak, 1e-9) : 100;
      const yAt = (v) => h - (Math.max(0, Math.min(top, v)) / top) * h;

      // fill
      ctx.save();
      ctx.beginPath();
      for (let i = 0; i < n; ++i) {
        const x = i * step;
        const y = yAt(vals[i]);
        if (i === 0) ctx.moveTo(x, y);
        else ctx.lineTo(x, y);
      }
      ctx.lineTo((n - 1) * step, h);
      ctx.lineTo(0, h);
      ctx.closePath();
      if (root.panel) {
        const g = ctx.createLinearGradient(0, 0, 0, h);
        g.addColorStop(0, Zenon.alpha(root.fillColor, Math.min(1, root.fillOpacity * 2.8)));
        g.addColorStop(1, Zenon.alpha(root.fillColor, 0.02));
        ctx.fillStyle = g;
      } else {
        ctx.fillStyle = root.fillColor;
        ctx.globalAlpha = root.fillOpacity;
      }
      ctx.fill();
      ctx.restore();

      // line
      ctx.beginPath();
      ctx.strokeStyle = root.lineColor;
      ctx.lineWidth = root.lineWidth;
      ctx.lineCap = "round";
      ctx.lineJoin = "round";
      for (let i = 0; i < n; ++i) {
        const x = i * step;
        const y = yAt(vals[i]);
        if (i === 0) ctx.moveTo(x, y);
        else ctx.lineTo(x, y);
      }
      ctx.stroke();

      // the newest point, ringed
      if (root.panel) {
        const x = (n - 1) * step;
        const y = yAt(vals[n - 1]);
        ctx.beginPath();
        ctx.fillStyle = Zenon.alpha(root.lineColor, 0.25);
        ctx.arc(x, y, 6, 0, Math.PI * 2);
        ctx.fill();
        ctx.beginPath();
        ctx.fillStyle = root.lineColor;
        ctx.arc(x, y, 3, 0, Math.PI * 2);
        ctx.fill();
      }
      ctx.restore();
    }
  }

  Connections {
    target: root
    function onValuesChanged() { canvas.requestPaint(); }
    function onLineColorChanged() { canvas.requestPaint(); }
    function onFillColorChanged() { canvas.requestPaint(); }
    function onFillOpacityChanged() { canvas.requestPaint(); }
    function onLineWidthChanged() { canvas.requestPaint(); }
    function onMaxPointsChanged() { canvas.requestPaint(); }
    function onPanelChanged() { canvas.requestPaint(); }
    function onPeakChanged() { canvas.requestPaint(); }
  }
  onWidthChanged: canvas.requestPaint()
  onHeightChanged: canvas.requestPaint()
}
