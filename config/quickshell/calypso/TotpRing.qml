// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// HOW LONG A ONE-TIME CODE HAS LEFT — a ring emptying, and the seconds. A
// code with two seconds to live is a code that expires on the way to the
// server, so it goes red for the last five: wait for the ring to refill.
//
// Codes turn over on the wall clock's period boundaries, the same for every
// item, so the ring is drawn from the clock alone — no code is fetched to
// draw it.
//
//     TotpRing { period: 30; size: 16; running: win.visible }

import QtQuick
import "../morpheus"

Item {
  id: ring
  property int period: 30
  property int size: 16
  property bool running: true
  property bool showSeconds: true
  property real remain: ring.period
  readonly property bool late: ring.remain <= 5
  readonly property color ink: ring.late ? Zenon.red : Zenon.cyan
  // a new period began (the code it showed is spent)
  signal rolled()

  implicitWidth: row.implicitWidth
  implicitHeight: Math.max(ring.size, secs.implicitHeight)

  Timer {
    interval: 250
    repeat: true
    triggeredOnStart: true
    running: ring.running && ring.visible
    onTriggered: {
      const was = ring.remain;
      ring.remain = ring.period - (Date.now() / 1000) % ring.period;
      if (ring.remain > was + 1) ring.rolled();
    }
  }

  Row {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    spacing: 6
    Text {
      id: secs
      visible: ring.showSeconds
      anchors.verticalCenter: parent.verticalCenter
      text: Math.ceil(ring.remain) + "s"
      color: ring.ink
      font.family: Zenon.faceMono
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(11)
      font.features: { "tnum": 1 }
    }
    Canvas {
      id: arc
      anchors.verticalCenter: parent.verticalCenter
      width: ring.size
      height: ring.size
      readonly property real frac: ring.remain / ring.period
      onFracChanged: requestPaint()
      onVisibleChanged: if (visible) requestPaint()
      // painted, not bound: a theme change has to ask for the repaint
      Connections { target: Zenon; function onThemeChanged() { arc.requestPaint(); } }
      onPaint: {
        const ctx = getContext("2d");
        const c = ring.size / 2, r = c - 2;
        ctx.reset();
        ctx.lineWidth = 2;
        ctx.strokeStyle = Zenon.border;
        ctx.beginPath();
        ctx.arc(c, c, r, 0, Math.PI * 2);
        ctx.stroke();
        ctx.strokeStyle = ring.ink;
        ctx.lineCap = "round";
        ctx.beginPath();
        ctx.arc(c, c, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * frac);
        ctx.stroke();
      }
    }
  }
}
