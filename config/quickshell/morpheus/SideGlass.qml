// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE GLASS A SIDEBAR IS MADE OF — an inactive tab's thinner glass with the
// sheet's veil over it, laid straight on the window's blur (nothing opaque
// under it: the desktop shows through, frosted by the compositor), and a
// hairline on the edge it meets the page by. Terminus' sidebar and plato's
// tree set the look (user, 2026-10-10); alexandria, argus, calypso, clio,
// delphi and minerva each wrote the same three rectangles out, and stylus,
// writing a fourth copy, put the window's own ground under it and lost the
// frost (user, 2026-10-24: "i thought we had a shared sidebar helper").
// One file now. (Terminus' and plato's own grounds are cut around their tab
// strips and stay theirs.)
//
//     Item { id: side
//       SideGlass { edge: "right" }       // first, so the rows draw over it
//       … }
//
// `edge` is the side the page is on: "right" for a sidebar on the left,
// "left" for one on the right (minerva's). A sidebar whose page runs on
// under it frosted lays its own Frost below this (minerva's reading view).

import QtQuick
import "."

Item {
  id: glass

  property string edge: "right"

  anchors.fill: parent

  Rectangle { anchors.fill: parent; color: Zenon.alpha(Zenon.tabAwayInk, Zenon.tabAway(Zenon.layerBg.a)) }
  Rectangle { anchors.fill: parent; color: Zenon.ground; opacity: 0.6 }
  // in the sidebar itself, not in this item, so its z stands over the
  // sidebar's own toolbars (minerva's sits at 4)
  Rectangle {
    parent: glass.parent
    z: 5
    x: glass.edge === "left" ? 0 : parent.width - 1
    width: 1
    height: parent.height
    color: Zenon.border
  }
}
