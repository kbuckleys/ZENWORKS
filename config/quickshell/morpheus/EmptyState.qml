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
//     EmptyState { anchors.centerIn: parent; visible: …; filtered: query !== "" }
//
// Placement and `visible` are the caller's; the look is this file's. Twenty
// of them had been styled one by one over three greys, three weights and
// four sizes (2026-10-20). The chrome grey, the shell's own weight — an
// absence is not a heading — and centered when it wraps. A warning that
// something is missing (no mkfs tools, no preview) is not an empty state:
// that stays yellow where it is.
//
// ONE LOOK, NOT TWO (2026-10-22). terminus/EmptyMark drew the same answer
// bold and a size up in eighteen panes, beside this in thirty-three — an
// empty stash page and an empty Clio list read as two different states. It
// is folded in here: `filtered` is the search's answer rather than the
// list's, and only it keeps the faint lens above the word (user, 2026-10-10:
// an empty directory says so in the word alone). Unset, the word is "No
// matches" or "Empty"; a caller's `text` replaces it.

import QtQuick
import "."

Text {
  id: empty

  // The search's answer rather than the list's: the lens over the word.
  property bool filtered: false

  readonly property int glyphPx: Zenon.px(64)
  readonly property int glyphGap: 10

  text: filtered ? "No matches" : "Empty"
  color: Zenon.accentMuted
  font.family: Zenon.face
  font.weight: Zenon.weight
  font.pixelSize: Zenon.px(14)
  wrapMode: Text.WordWrap
  horizontalAlignment: Text.AlignHCenter
  // The lens sits in the padding, so a centered state centers lens and word
  // together, as EmptyMark's column did.
  topPadding: filtered ? lens.implicitHeight + glyphGap : 0

  Text {
    id: lens
    visible: empty.filtered
    anchors.top: parent.top
    anchors.horizontalCenter: parent.horizontalCenter
    // nf-fa-search
    text: ""
    color: Zenon.accentMuted
    opacity: 0.35
    font.family: Zenon.face
    font.weight: Zenon.weight
    font.pixelSize: empty.glyphPx
  }
}
