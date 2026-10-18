// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// THE BOX A LIST STANDS IN: darker than the page, one hairline round it, the
// window's radius. Ceres' mirror list (Maintenance › Mirrors), a job's log
// and its progress bar all wore this as their own Rectangle; Oracle's Tools
// asked for "the same container mirror list uses" (user, 2026-10-18), so it
// is one thing now. What goes in it is the caller's — usually a list inset
// 6 px, so its rows' own highlights clear the hairline.
//
//   import "../morpheus/controls" as Controls
//   Controls.ListFrame { anchors.fill: list; anchors.margins: -6 }
//
// A directory with no qmldir, imported by path (see Check.qml).

import QtQuick
import ".."

Rectangle {
  radius: Zenon.windowRadius
  color: Zenon.darken(0.25)
  border.width: 1
  border.color: Zenon.border
}
