// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE SCROLLBAR — the one scrollbar in the shell, for any Flickable.
//
// There were two designs: this one, for the panels (a track always faintly
// there, a thumb that went cyan when dragged), and terminus' ScrollRail (a
// thin thumb, a track only under the pointer). Two designs are two ways of
// saying the same thing, and the rail's was the one chosen for ceres. So this
// is the rail's LOOK with both of their BEHAVIOURS, and ScrollRail is now a
// thin setting of this file rather than a second implementation.
//
//     Scrollbar { flick: list; anchors.right: parent.right
//                 anchors.top: parent.top; anchors.bottom: parent.bottom }
//
// How it looks: a 4px thumb at the right edge, 6px under the pointer, its
// track appearing only then; drawn only when there is somewhere for the
// thumb to go.
//
// What differs by where it is used, as settings rather than as designs:
//
//   thickness + grabPad   the width that can be GRABBED. The panels reach 26px
//                         in from the edge (aiming at a hairline against a
//                         panel's edge is a miss), terminus and ceres keep to
//                         10px (their rows carry columns right up to the edge,
//                         and a wide grab would take those clicks).
//   handleWheel           the panels scroll by wheel over the bar in fixed
//                         steps (wheelStep, or a quarter of the view); in the
//                         windows the wheel passes through to the list's own
//                         smooth scroll, which is better and was already there.
//   owner                 told `railHover`/`railDragging` — terminus, whose
//                         rubber band must not arm over the bar.

import QtQuick
import "."

Item {
  id: root

  // the ListView, GridView or Flickable this reports on
  property Flickable flick: null
  // false while its view is not the one on screen
  property bool on: true

  // the painted column at the right edge, and how far the grab reaches in
  // past it — see the header
  property int thickness: 12
  property int grabPad: 14
  property int minThumb: 28
  // panels: a wheel notch over the bar moves this far (0: a quarter view)
  property real wheelStep: 0
  property bool handleWheel: true
  property var owner: null

  readonly property real overflow:
    root.flick ? Math.max(0, root.flick.contentHeight - root.flick.height) : 0

  // WHAT THE THUMB WOULD BE, before asking whether it is worth drawing: the
  // viewport as a share of the content, floored so a very long list still
  // leaves something to grab.
  readonly property real fullThumb: (root.overflow > 0 && root.flick.contentHeight > 0)
    ? Math.max(root.minThumb, Math.round(root.height * (root.flick.height / root.flick.contentHeight)))
    : root.height

  // A BAR WHOSE THUMB CANNOT TRAVEL IS NOT A BAR. One or two pixels of
  // overflow — a Text's rounding, a descender — passed "is there anything
  // past the edge" and drew a thumb filling the whole track that went
  // nowhere. The question is whether there is anywhere for it to go.
  readonly property real minTravel: 6
  readonly property bool scrollable:
    root.overflow > 0 && (root.height - root.fullThumb) >= root.minTravel

  readonly property real thumbH: root.scrollable ? root.fullThumb : 0
  readonly property real travel: Math.max(0, root.height - root.thumbH)
  readonly property real progress:
    root.overflow > 0 ? Math.max(0, Math.min(1, root.flick.contentY / root.overflow)) : 0
  readonly property real thumbY: Math.round(root.travel * root.progress)
  readonly property bool dragging: ma.dragging
  readonly property bool hovering: ma.containsMouse

  width: root.thickness + root.grabPad
  // above the view's own overlays: a scrollbar has to be the topmost thing
  // along its strip or it is not a scrollbar
  z: 9
  visible: root.on && root.scrollable

  // the painted column's centre, against the right edge
  readonly property real lineX: root.width - root.thickness / 2

  // the track: there only under the pointer
  Rectangle {
    x: root.lineX - width / 2
    y: 2
    width: root.thickness - 2
    height: root.height - 4
    radius: width / 2
    color: Zenon.border
    opacity: ma.containsMouse || ma.dragging ? 0.30 : 0.0
    Behavior on opacity { NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }
  }

  Rectangle {
    id: thumb
    width: ma.containsMouse || ma.dragging ? 6 : 4
    x: root.lineX - width / 2
    y: root.thumbY
    height: root.thumbH
    radius: width / 2
    color: Zenon.keyInk
    opacity: ma.dragging ? 0.90 : (ma.containsMouse ? 0.70 : 0.40)
    Behavior on width { NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }
    Behavior on opacity { NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }
  }

  MouseArea {
    id: ma
    anchors.fill: parent
    hoverEnabled: true
    enabled: root.visible
    // A Flickable takes the grab as soon as it decides a press has become a
    // flick; this keeps it for the whole stroke.
    preventStealing: true

    property real pressY: 0
    property real startContent: 0
    property bool dragging: false

    onContainsMouseChanged: if (root.owner) root.owner.railHover = ma.containsMouse

    function contentForTop(top) {
      if (root.travel <= 0) return 0;
      return Math.max(0, Math.min(root.overflow, (top / root.travel) * root.overflow));
    }

    onPressed: (m) => {
      // the bare track: the thumb comes to the pointer, by its middle
      if (m.y < thumb.y || m.y > thumb.y + root.thumbH)
        root.flick.contentY = ma.contentForTop(m.y - root.thumbH / 2);
      ma.pressY = m.y;
      ma.startContent = root.flick.contentY;
      ma.dragging = true;
      if (root.owner) root.owner.railDragging = true;
    }
    // the point that was grabbed stays under the pointer
    onPositionChanged: (m) => {
      if (!ma.dragging || root.travel <= 0) return;
      root.flick.contentY = Math.max(0, Math.min(root.overflow,
        ma.startContent + ((m.y - ma.pressY) / root.travel) * root.overflow));
    }
    onReleased: { ma.dragging = false; if (root.owner) root.owner.railDragging = false; }
    onCanceled: { ma.dragging = false; if (root.owner) root.owner.railDragging = false; }

    onWheel: (w) => {
      if (!root.handleWheel) { w.accepted = false; return; }
      const step = root.wheelStep > 0 ? root.wheelStep : root.flick.height * 0.25;
      root.flick.contentY = Math.max(0, Math.min(root.overflow,
        root.flick.contentY + (w.angleDelta.y > 0 ? -step : step)));
      w.accepted = true;
    }
  }
}
