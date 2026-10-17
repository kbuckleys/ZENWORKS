// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/

import QtQuick
import "../morpheus"
import "metis.js" as Metis

// THREE MONTHS OF A RATE. Under a money answer, the line the rate has
// drawn a week at a time (scripts/metis-trend.py), ending on the rate the
// answer was worked out with: whether now is a good day to change money is
// the question after "how much is it". Faint where it has been, a dot where
// it is; how far it has moved on the right, the weeks it covers on the left.
// Up and down are neither good nor bad — it depends which way you are
// changing — so the move is said, not colored.
Item {
  id: strip

  property var points: []       // [{date, v}], oldest first
  property string from: ""
  property string to: ""
  readonly property var sum: Metis.trendSummary(strip.points)
  readonly property bool hovered: hover.containsMouse

  implicitHeight: 46

  readonly property real labelW: Math.max(leftTag.implicitWidth, rightTag.implicitWidth) + 12

  Text {
    id: leftTag
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    text: strip.sum ? strip.sum.weeks + " wk" : ""
    color: Zenon.muted
    font.family: Zenon.face
    font.weight: Font.Bold
    font.pixelSize: Zenon.px(11)
  }

  Canvas {
    id: line
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: strip.labelW
    anchors.rightMargin: strip.labelW
    anchors.verticalCenter: parent.verticalCenter
    height: 30
    // drawn left to right as it arrives, rather than appearing whole
    property real reveal: 0
    onRevealChanged: requestPaint()
    onWidthChanged: requestPaint()
    Connections {
      target: strip
      function onPointsChanged() { line.reveal = 0; grow.restart(); }
    }
    NumberAnimation {
      id: grow
      target: line
      property: "reveal"
      from: 0
      to: 1
      duration: Zenon.slow * 3
      easing.type: Easing.OutCubic
    }
    Component.onCompleted: grow.restart()

    onPaint: {
      const ctx = getContext("2d");
      ctx.reset();
      const p = strip.points, n = p.length;
      if (n < 2 || width <= 0) return;
      const s = strip.sum;
      const span = Math.max(s.high - s.low, s.high * 1e-4);
      const pad = 4;
      const X = (i) => i / (n - 1) * width;
      const Y = (v) => pad + (1 - (v - s.low) / span) * (height - pad * 2);
      const upto = Math.max(1, (n - 1) * line.reveal);
      ctx.save();
      ctx.beginPath();
      ctx.rect(0, 0, X(upto) + 1, height);
      ctx.clip();
      // the wash under it
      ctx.beginPath();
      ctx.moveTo(X(0), height);
      for (let i = 0; i < n; ++i) ctx.lineTo(X(i), Y(p[i].v));
      ctx.lineTo(X(n - 1), height);
      ctx.closePath();
      const g = ctx.createLinearGradient(0, 0, 0, height);
      g.addColorStop(0, Zenon.alpha(Zenon.green, 0.22));
      g.addColorStop(1, Zenon.alpha(Zenon.green, 0));
      ctx.fillStyle = g;
      ctx.fill();
      // the line
      ctx.beginPath();
      for (let i = 0; i < n; ++i) i === 0 ? ctx.moveTo(X(i), Y(p[i].v)) : ctx.lineTo(X(i), Y(p[i].v));
      ctx.lineWidth = 1.6;
      ctx.lineJoin = "round";
      ctx.strokeStyle = Zenon.green;
      ctx.stroke();
      ctx.restore();
      // where it is now
      if (line.reveal > 0.98) {
        ctx.beginPath();
        ctx.arc(X(n - 1), Y(p[n - 1].v), 3.5, 0, Math.PI * 2);
        ctx.fillStyle = Zenon.green;
        ctx.fill();
        ctx.lineWidth = 2;
        ctx.strokeStyle = Zenon.layerBg;
        ctx.stroke();
      }
    }
  }

  Text {
    id: rightTag
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    text: strip.sum ? strip.sum.pctText : ""
    color: Zenon.keyInk
    font.family: Zenon.face
    font.weight: Font.Bold
    font.pixelSize: Zenon.px(12)
    font.features: { "tnum": 1 }
  }

  MouseArea {
    id: hover
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.NoButton
  }
}
