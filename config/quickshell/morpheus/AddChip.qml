// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A SMALL + — ClearChip's disc with the cross upright and the disc drawn
// tighter round it (user, 2026-10-22). For "add one" beside a heading:
//
//     AddChip { size: Zenon.px(13)
//               anchors.right: parent.right; anchors.rightMargin: 12
//               anchors.verticalCenter: label.verticalCenter
//               onClicked: … }

import QtQuick

ClearChip {
  disc: 1.05
  strokes: [0, 90]
}
