// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// HOW FAR, AS A FILL — ceres' transaction band (lifted out of ceres/TxView,
// 2026-10-13), laid inside whatever shows it:
//
//     Rectangle { id: band; radius: 6; …
//       ProgressFill { anchors.fill: parent; anchors.margins: 1; frac: 0.4
//                      radius: band.radius - 1 } }
//
// In the accent (`ink`), not a wash: a ramp that deepens toward the leading
// edge, so the band reads as moving rightward even while it is still. No
// line at the edge — it read as a text cursor. Translucent, so the words on
// it stay the loudest thing there. The width eases as `frac` moves.
//
// `fades`: the fill goes (fades out) when `done` comes, rather than sitting
// full.

import QtQuick
import "../morpheus"

Item {
  id: pf
  property real frac: 0            // 0..1
  property color ink: Zenon.cyan
  property real radius: 0
  property bool done: false
  property bool fades: false
  Component.onCompleted: pf._at = Math.max(0, Math.min(1, pf.frac))

  opacity: pf.fades && pf.done ? 0 : 1
  Behavior on opacity { NumberAnimation { duration: Zenon.slow; easing.type: Zenon.ease } }

  // forward it eases; back (a new start) it is simply there — a fill
  // sliding backward across the band read as something undone
  property real _at: 0
  property bool _back: false
  onFracChanged: {
    const f = Math.max(0, Math.min(1, pf.frac));
    pf._back = f < pf._at;
    pf._at = f;
  }

  Item {
    id: fill
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: Math.max(0, parent.width * pf._at)
    Behavior on width { enabled: !pf._back; NumberAnimation { duration: Zenon.slow; easing.type: Zenon.ease } }

    Rectangle {
      anchors.fill: parent
      radius: pf.radius
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0.0; color: Qt.rgba(pf.ink.r, pf.ink.g, pf.ink.b, 0.04) }
        GradientStop { position: 1.0; color: Qt.rgba(pf.ink.r, pf.ink.g, pf.ink.b, 0.20) }
      }
    }
  }
}
