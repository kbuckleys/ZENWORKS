// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// EMPTYSTATE — the line a list, pane or popup shows when it has nothing in
// it: "No clipboard entries", "Nothing matches “x”", "Nothing bookmarked
// yet — b a adds this directory".
//
//     EmptyState { anchors.centerIn: parent; visible: rows.length === 0; text: "Nothing yet" }
//
// Placement and `visible` are the caller's; the look is this file's. Twenty
// of them had been styled one by one over three greys, three weights and
// four sizes (2026-10-20). The chrome grey, the shell's own weight — an
// absence is not a heading — and centered when it wraps. A warning that
// something is missing (no mkfs tools, no preview) is not an empty state:
// that stays yellow where it is.

import QtQuick
import "."

Text {
  color: Zenon.accentMuted
  font.family: Zenon.face
  font.weight: Zenon.weight
  font.pixelSize: Zenon.px(14)
  wrapMode: Text.WordWrap
  horizontalAlignment: Text.AlignHCenter
}
