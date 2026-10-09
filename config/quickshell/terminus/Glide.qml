// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// GLIDE — a row or a tile easing from where it WAS to where it is, when a
// filter or a new order moves it. Terminus' list, columns and grid, and
// picasso's gallery.
//
//     Glide { id: glide }                         // inside the delegate
//     …  glide.from(oldX - newX, oldY - newY)
//
// It moves its PARENT, through a Translate it adds to the parent's
// transform — as TileRise does, so the two stack on a grid tile.
//
// DRAWING ONLY. The views' own move and displaced transitions were taken out
// of terminus on purpose: a transition keeps a delegate alive past the point
// the view would have reclaimed it, and with reuseItems that painted rows over
// rows and put clicks on neither. This touches nothing the view knows about —
// the delegate is where the view put it from the first frame, only drawn
// offset, and the offset runs out to nothing. A delegate torn down or reused
// mid-glide takes its Glide with it, or is given a new one.
//
// `limit` caps the distance: a row that came from four hundred rows away
// slides in from just past the edge rather than across the whole list.

import QtQuick

Item {
  id: glide
  width: 0
  height: 0
  visible: false

  readonly property Translate shift: Translate {}
  Component.onCompleted: {
    const t = [];
    for (let i = 0; i < glide.parent.transform.length; ++i) t.push(glide.parent.transform[i]);
    t.push(glide.shift);
    glide.parent.transform = t;
  }
  property int duration: 320
  property real limit: 600

  function from(dx, dy) {
    const c = (v) => Math.max(-glide.limit, Math.min(glide.limit, v));
    anim.stop();
    if (Math.abs(dx) < 1 && Math.abs(dy) < 1) { glide.shift.x = 0; glide.shift.y = 0; return; }
    glide.shift.x = c(dx);
    glide.shift.y = c(dy);
    anim.start();
  }
  function stop() {
    anim.stop();
    glide.shift.x = 0;
    glide.shift.y = 0;
  }

  ParallelAnimation {
    id: anim
    NumberAnimation { target: glide.shift; property: "x"; to: 0; duration: glide.duration; easing.type: Easing.OutCubic }
    NumberAnimation { target: glide.shift; property: "y"; to: 0; duration: glide.duration; easing.type: Easing.OutCubic }
  }
}
