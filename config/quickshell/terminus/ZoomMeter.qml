// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// WHAT THE ZOOM IS AT, as an instrument rather than as a number — terminus'
// status strip meter, shared with picasso's bar. "140%" is a figure you have
// to read and then convert into "how much room is left before it stops"; a
// notched bar answers that at a glance, and it is the same instrument the
// shell bar's own meters are.
//
// AN INSTRUMENT YOU CAN ALSO TURN: press or drag up and down it to set the zoom,
// the wheel steps it, a middle click resets it. The holder owns the zoom and
// its scale — this only reports where along the travel the pointer was.
//
//   value     0–1, where the zoom sits between as small as it goes and as large
//   seek(f)   pressed or dragged to fraction f of the travel
//   step(d)   a wheel notch, +1 or -1
//   reset()   middle click

import QtQuick
import "../morpheus"

Item {
  id: zm

  property real value: 0
  signal seek(real f)
  signal step(int d)
  signal reset()

  implicitWidth: zoomMeter.implicitWidth
  implicitHeight: zoomMeter.implicitHeight

  Meter {
    id: zoomMeter
    anchors.centerIn: parent
    // standing up, like the shell bar's own meters: it fills from the
    // bottom, so "more zoom" reads as "higher", and it takes a sliver of the
    // row's width instead of a stretch of it
    vertical: true
    segCount: 8
    segLength: 2
    segGap: 1
    thickness: 7
    accent: zoomMa.containsMouse || zoomMa.pressed ? Zenon.white : Zenon.cyan
    Behavior on accent {
      ColorAnimation { duration: Zenon.fast; easing.type: Zenon.ease }
    }
    value: zm.value
    // The bottom notch is a real setting, not "off" — deadZone would
    // otherwise draw the smallest zoom as an unlit bar.
    deadZone: -1
  }

  // The hit area is the wrapper, not the meter: the notches are 7px wide and
  // a 7px target is not a target. Twelve pixels of padding either side,
  // taken inside the row's own spacing so nothing moves.
  MouseArea {
    id: zoomMa
    anchors.fill: parent
    anchors.topMargin: -4
    anchors.bottomMargin: -4
    anchors.leftMargin: -12
    anchors.rightMargin: -12
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton

    // the fraction of the METER the pointer is over, with the padding taken
    // back off — counted up from the bottom, the way it fills
    function seekAt(y) {
      const h = zoomMeter.height;
      if (h <= 0) return;
      zm.seek(Math.max(0, Math.min(1, 1 - (y - 4) / h)));
    }

    onPressed: (m) => {
      // middle click is the reset every other meter-shaped thing on this
      // desktop uses
      if (m.button === Qt.MiddleButton) { zm.reset(); return; }
      zoomMa.seekAt(m.y);
    }
    onPositionChanged: (m) => { if (zoomMa.pressed) zoomMa.seekAt(m.y); }
    onWheel: (w) => {
      zm.step(w.angleDelta.y > 0 ? 1 : -1);
      w.accepted = true;
    }
  }
}
