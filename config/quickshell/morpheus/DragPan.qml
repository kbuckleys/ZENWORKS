// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// DRAGPAN — a zoomed-in view, dragged about by hand. Picasso's grab: an
// open hand while there is somewhere to pan to, closed while panning.
//
//     Flickable {
//       id: flick
//       DragPan { flick: flick; on: <wider than the view> }   // FIRST child
//       Repeater { ... }
//     }
//
// The FIRST child of the Flickable's content, as big as the content: under
// everything else there, so a link's own cursor and tap still win over it,
// and a press reaches the content's handlers too. A drag pans only once it
// is a drag (the threshold), so a click is still a click. Plain drags only:
// a modified drag is left to whatever is under it (minerva's PDF selects
// text on shift).
//
// A TOUCHPAD IS A POINTER TOO (user, 2026-10-21): its clicks and drags
// come as their own device type, and a handler taking only Mouse and Stylus
// showed the hand and never panned. All three are taken.
//
// Measured in the scene, not here: the content moves under the pointer
// while it pans, and a translation in its own coordinates fed back on
// itself. The wheel's glide (Elastic) is halted at the grab, so the two do
// not fight.

import QtQuick

Item {
  id: pan

  property Flickable flick: null
  // an ElasticScroll's coast, if the flick is one: looked up untyped, as a
  // plain Flickable has none
  readonly property var host: pan.flick
  readonly property var coast: pan.host ? pan.host.elastic || null : null
  // whether there is anywhere to pan to
  property bool on: false
  readonly property bool panning: grab.active

  width: pan.flick ? pan.flick.contentWidth : 0
  height: pan.flick ? pan.flick.contentHeight : 0

  property point last: Qt.point(0, 0)

  HoverHandler {
    enabled: pan.on
    cursorShape: Qt.OpenHandCursor
  }
  DragHandler {
    id: grab
    enabled: pan.on && !!pan.flick
    target: null
    acceptedButtons: Qt.LeftButton
    acceptedModifiers: Qt.NoModifier
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.Stylus
    cursorShape: Qt.ClosedHandCursor
    // from the press, not from where the drag threshold was crossed: the
    // page stays under the hand rather than trailing it by the threshold
    onActiveChanged: if (grab.active) {
      pan.last = grab.centroid.scenePressPosition;
      if (pan.coast) pan.coast.halt(pan.flick);
    }
    onCentroidChanged: {
      if (!grab.active) return;
      const p = grab.centroid.scenePosition, f = pan.flick;
      f.contentX = Math.max(0, Math.min(f.contentWidth - f.width, f.contentX - (p.x - pan.last.x)));
      f.contentY = Math.max(0, Math.min(f.contentHeight - f.height, f.contentY - (p.y - pan.last.y)));
      pan.last = p;
    }
  }
}
