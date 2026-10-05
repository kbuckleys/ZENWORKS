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
//   handleWheel           the panels take the wheel over the bar themselves
//                         (wheelStep a notch, or a quarter of the view), with
//                         the shell's one feel (Elastic); in the windows it
//                         passes through to the list's own ElasticScroll.
//   owner                 told `railHover`/`railDragging` — terminus, whose
//                         rubber band must not arm over the bar.
//   horizontal            along the BOTTOM edge of a sideways list instead —
//                         picasso's filmstrip. The same bar turned on its
//                         side; a sideways ListView's margins and origin are
//                         counted, since its contentX starts at -leftMargin.

import QtQuick
import "."

Item {
  id: root

  // the ListView, GridView or Flickable this reports on
  property Flickable flick: null
  // false while its view is not the one on screen
  property bool on: true
  // along the bottom edge of a sideways list — see the header
  property bool horizontal: false

  // the painted column at the right edge, and how far the grab reaches in
  // past it — see the header
  property int thickness: 12
  property int grabPad: 14
  property int minThumb: 28
  // panels: a wheel notch over the bar moves this far (0: a quarter view)
  property real wheelStep: 0
  property bool handleWheel: true
  property var owner: null
  readonly property Elastic rootElastic: Elastic { horizontal: root.horizontal }

  // ── THE AXIS ───────────────────────────────────────────────────────────
  // Everything below is said along the bar: its length, the view's, the
  // content's, and where the view is in it. Upright, that is the plain
  // contentY it always was; on its side, contentX measured from where a
  // sideways list really starts.
  readonly property real trackLen: root.horizontal ? root.width : root.height
  readonly property real viewLen: !root.flick ? 0
    : (root.horizontal ? root.flick.width : root.flick.height)
  readonly property real contentLen: !root.flick ? 0
    : (root.horizontal ? root.flick.contentWidth + root.flick.leftMargin + root.flick.rightMargin
                       : root.flick.contentHeight)
  readonly property real startAt: root.horizontal && root.flick
    ? root.flick.originX - root.flick.leftMargin : 0
  readonly property real pos: !root.flick ? 0
    : (root.horizontal ? root.flick.contentX - root.startAt : root.flick.contentY)
  function setPos(v) {
    const c = Math.max(0, Math.min(root.overflow, v));
    if (root.horizontal) { root.flick.cancelFlick(); root.flick.contentX = root.startAt + c; }
    else root.flick.contentY = c;
  }

  readonly property real overflow: root.flick ? Math.max(0, root.contentLen - root.viewLen) : 0

  // WHAT THE THUMB WOULD BE, before asking whether it is worth drawing: the
  // viewport as a share of the content, floored so a very long list still
  // leaves something to grab.
  readonly property real fullThumb: (root.overflow > 0 && root.contentLen > 0)
    ? Math.max(root.minThumb, Math.round(root.trackLen * (root.viewLen / root.contentLen)))
    : root.trackLen

  // A BAR WHOSE THUMB CANNOT TRAVEL IS NOT A BAR. One or two pixels of
  // overflow — a Text's rounding, a descender — passed "is there anything
  // past the edge" and drew a thumb filling the whole track that went
  // nowhere. The question is whether there is anywhere for it to go.
  readonly property real minTravel: 6
  readonly property bool scrollable:
    root.overflow > 0 && (root.trackLen - root.fullThumb) >= root.minTravel

  readonly property real thumbH: root.scrollable ? root.fullThumb : 0
  readonly property real travel: Math.max(0, root.trackLen - root.thumbH)
  readonly property real progress:
    root.overflow > 0 ? Math.max(0, Math.min(1, root.pos / root.overflow)) : 0
  readonly property real thumbY: Math.round(root.travel * root.progress)
  readonly property bool dragging: ma.dragging

  width: root.horizontal ? implicitWidth : root.thickness + root.grabPad
  height: root.horizontal ? root.thickness + root.grabPad : implicitHeight
  // above the view's own overlays: a scrollbar has to be the topmost thing
  // along its strip or it is not a scrollbar
  z: 9
  visible: root.on && root.scrollable

  // the painted column's centre, against the right edge (the bottom one, on
  // its side)
  readonly property real lineX: root.horizontal ? root.height - root.thickness / 2
                                                : root.width - root.thickness / 2

  // the track: there only under the pointer
  Rectangle {
    readonly property real across: root.thickness - 2
    x: root.horizontal ? 2 : root.lineX - across / 2
    y: root.horizontal ? root.lineX - across / 2 : 2
    width: root.horizontal ? root.width - 4 : across
    height: root.horizontal ? across : root.height - 4
    radius: across / 2
    color: Zenon.border
    opacity: ma.containsMouse || ma.dragging ? 0.30 : 0.0
    Behavior on opacity { NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }
  }

  Rectangle {
    id: thumb
    property real across: ma.containsMouse || ma.dragging ? 6 : 4
    // where it starts along the bar, whichever way the bar runs
    readonly property real along: root.horizontal ? thumb.x : thumb.y
    x: root.horizontal ? root.thumbY : root.lineX - across / 2
    y: root.horizontal ? root.lineX - across / 2 : root.thumbY
    width: root.horizontal ? root.thumbH : across
    height: root.horizontal ? across : root.thumbH
    radius: across / 2
    color: Zenon.keyInk
    opacity: ma.dragging ? 0.90 : (ma.containsMouse ? 0.70 : 0.40)
    Behavior on across { NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease } }
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
    function along(m) { return root.horizontal ? m.x : m.y; }

    onPressed: (m) => {
      const a = ma.along(m);
      // the bare track: the thumb comes to the pointer, by its middle
      if (a < thumb.along || a > thumb.along + root.thumbH)
        root.setPos(ma.contentForTop(a - root.thumbH / 2));
      ma.pressY = a;
      ma.startContent = root.pos;
      ma.dragging = true;
      if (root.owner) root.owner.railDragging = true;
    }
    // the point that was grabbed stays under the pointer
    onPositionChanged: (m) => {
      if (!ma.dragging || root.travel <= 0) return;
      root.setPos(ma.startContent + ((ma.along(m) - ma.pressY) / root.travel) * root.overflow);
    }
    onReleased: { ma.dragging = false; if (root.owner) root.owner.railDragging = false; }
    onCanceled: { ma.dragging = false; if (root.owner) root.owner.railDragging = false; }

    // over the bar, the wheel scrolls exactly as it does over the list: the
    // shell's one feel (Elastic), never a step of the bar's own
    onWheel: (w) => {
      if (!root.handleWheel || !root.flick) { w.accepted = false; return; }
      const step = root.wheelStep > 0 ? root.wheelStep : root.viewLen * 0.25;
      w.accepted = root.rootElastic.wheel(root.flick, w, step);
    }
  }
}
