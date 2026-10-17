// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// WHAT THE CHECKS SAID — a commit's CI, as one small mark: a green dot
// passed, a red one failed, a ring still running, a gray dot nothing
// either way. Nothing at all where there are no checks (or none asked
// yet). `c` is DelphiManager.ciOf's answer.
//
//     CiDot { c: pg.win.mgr.ciOf(forge, full, sha) }

import QtQuick
import "../morpheus"

Item {
  id: dot
  property var c: null
  property real size: Zenon.px(9)
  readonly property string state_: dot.c ? dot.c.state : "none"
  visible: dot.state_ !== "none"
  width: dot.size
  height: dot.size
  Rectangle {
    anchors.fill: parent
    radius: width / 2
    color: dot.state_ === "pending" ? "transparent"
      : dot.state_ === "success" ? Zenon.green : dot.state_ === "failure" ? Zenon.red : Zenon.accentMuted
    border.width: dot.state_ === "pending" ? Math.max(1.5, dot.size / 5) : 0
    border.color: Zenon.yellow
  }
}
