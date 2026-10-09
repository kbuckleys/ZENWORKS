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
// AN INSTRUMENT YOU CAN ALSO TURN: press or drag along it to set the zoom,
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
    vertical: false
    segCount: 8
    segLength: 3
    segGap: 2
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

  // The hit area is the wrapper, not the meter: the notches are 7px tall and
  // a 7px target is not a target. Twelve pixels of padding top and bottom,
  // taken inside the row's own height so nothing moves.
  MouseArea {
    id: zoomMa
    anchors.fill: parent
    anchors.topMargin: -12
    anchors.bottomMargin: -12
    anchors.leftMargin: -4
    anchors.rightMargin: -4
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton

    // the fraction of the METER the pointer is over, with the padding taken
    // back off
    function seekAt(x) {
      const w = zoomMeter.width;
      if (w <= 0) return;
      zm.seek(Math.max(0, Math.min(1, (x - 4) / w)));
    }

    onPressed: (m) => {
      // middle click is the reset every other meter-shaped thing on this
      // desktop uses
      if (m.button === Qt.MiddleButton) { zm.reset(); return; }
      zoomMa.seekAt(m.x);
    }
    onPositionChanged: (m) => { if (zoomMa.pressed) zoomMa.seekAt(m.x); }
    onWheel: (w) => {
      zm.step(w.angleDelta.y > 0 ? 1 : -1);
      w.accepted = true;
    }
  }
}
