// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A SEAM YOU CAN TAKE HOLD OF — the line between two panes, and the grip
// that drags it. Terminus' pane divider made a thing of its own (its
// sidebar's and its split's grips, and plato's tree edge, are this same
// design written in place): a 1px line in the border colour, a 9px grip
// straddling it with the resize cursor, and the line CYAN under the pointer
// and while dragged — the seam answering the cursor that changed shape over
// it. Double click: back to where it starts.
//
//     SeamGrip { frame: page; at: leftW            // where the line is, in frame
//                min: 280; max: page.width - 360
//                onMoved: (p) => leftW = p; onReset: leftW = 400 }
//     SeamGrip { vertical: false; frame: col; at: topH; … }  // a seam across
//
// Measured in `frame`, which does not move while the seam does: a delta
// read off the grip itself is read against an origin sliding under the
// pointer, which is what made terminus' divider jitter before it learned
// this. It places itself along `at`; the holder sizes the panes from the
// same number.

import QtQuick
import "../morpheus"

Item {
  id: seam
  // true: a line down (panes left and right); false: a line across
  property bool vertical: true
  property Item frame: null
  property real at: 0
  property real min: 0
  property real max: 1e9
  // the line itself drawn here, or only the grip (the holder has a line)
  property bool line: true
  signal moved(real pos)
  signal reset()
  readonly property bool held: grip.pressed
  readonly property bool lit: grip.pressed || grip.containsMouse

  x: seam.vertical ? Math.round(seam.at) : 0
  y: seam.vertical ? 0 : Math.round(seam.at)
  width: seam.vertical ? 1 : (seam.parent ? seam.parent.width : 0)
  height: seam.vertical ? (seam.parent ? seam.parent.height : 0) : 1
  z: 9

  Rectangle {
    visible: seam.line
    anchors.fill: parent
    color: seam.lit ? Zenon.cyan : Zenon.border
    Behavior on color { ColorAnimation { duration: Zenon.fast } }
  }
  MouseArea {
    id: grip
    x: seam.vertical ? -4 : 0
    y: seam.vertical ? 0 : -4
    width: seam.vertical ? 9 : seam.width
    height: seam.vertical ? seam.height : 9
    hoverEnabled: true
    preventStealing: true
    cursorShape: seam.vertical ? Qt.SizeHorCursor : Qt.SizeVerCursor
    // where in the grip it was taken hold of, so the line stays under the
    // same part of the pointer for the whole drag
    property real grab: 0
    onPressed: (m) => { grip.grab = seam.vertical ? m.x - 4 : m.y - 4; }
    onPositionChanged: (m) => {
      if (!grip.pressed || !seam.frame) return;
      const p = grip.mapToItem(seam.frame, m.x, m.y);
      const want = (seam.vertical ? p.x : p.y) - grip.grab;
      seam.moved(Math.round(Math.max(seam.min, Math.min(seam.max, want))));
    }
    onDoubleClicked: seam.reset()
  }
}
