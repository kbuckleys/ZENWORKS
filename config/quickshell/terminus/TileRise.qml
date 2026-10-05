// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// TILERISE — a grid's tiles coming up one after another, top to bottom, as a
// folder is arrived in: each fades in and rises a few pixels into its place,
// a beat after the one before it.
//
//     TileRise { id: rise }              // inside the delegate
//     rise.hide()                        // held back, until…
//     rise.start(grid, index)            // …let go, in its turn
//
// It moves its PARENT (the delegate): the parent's opacity, and a Translate
// it adds to the parent's transform. Shared by terminus' grid, which lets a
// screenful go once its pictures have decoded (PaneGrid.held), and picasso's
// gallery, which lets a fresh directory go as it is listed.

import QtQuick
import "../oracle"

Item {
  id: rise
  width: 0
  height: 0

  // a beat between tiles, and the most any tile waits
  readonly property int beat: Math.round(14 * Oracle.motionScale)
  readonly property int most: Math.round(240 * Oracle.motionScale)
  readonly property int ms: Math.round(140 * Oracle.motionScale)

  property Translate shift: Translate {}
  property int delay: 0
  Component.onCompleted: {
    const t = [];
    for (let i = 0; i < rise.parent.transform.length; ++i) t.push(rise.parent.transform[i]);
    t.push(rise.shift);
    rise.parent.transform = t;
  }

  function hide() {
    anim.stop();
    rise.parent.opacity = 0;
    rise.shift.y = 14;
  }
  // Its turn is counted from the first tile on screen; one off the screen
  // (or past the cap) simply appears.
  function start(view, index) {
    const cols = Math.max(1, Math.floor(view.width / Math.max(1, view.cellWidth)));
    const first = Math.floor(Math.max(0, view.contentY - view.originY) / Math.max(1, view.cellHeight)) * cols;
    const nth = index - first;
    if (nth < 0 || rise.beat * nth > rise.most) { rise.show(); return; }
    rise.delay = rise.beat * nth;
    anim.restart();
  }
  function show() {
    anim.stop();
    rise.parent.opacity = 1;
    rise.shift.y = 0;
  }

  SequentialAnimation {
    id: anim
    PauseAnimation { duration: rise.delay }
    ParallelAnimation {
      NumberAnimation { target: rise.parent; property: "opacity"; to: 1; duration: rise.ms; easing.type: Easing.OutCubic }
      NumberAnimation { target: rise.shift; property: "y"; to: 0; duration: rise.ms + 40; easing.type: Easing.OutCubic }
    }
  }
}
