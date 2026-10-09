// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// EMPTY MARK — what a listing with nothing in it says: a large, faint glyph
// over the word.
//
// The word alone, small in the middle of a whole pane, read as something that
// had failed to load rather than as an answer. The glyph gives the page a
// centre and says which answer it is — an open directory for "Empty", a lens for
// "No matches" — before the word is read.
//
// One file because both panes draw it, and two panes saying the same thing
// two different ways reads as two different states.

import QtQuick
import "../morpheus"

Column {
  id: mark

  // The search's answer rather than the directory's.
  property bool filtered: false

  spacing: 10

  Text {
    anchors.horizontalCenter: parent.horizontalCenter
    // nf-fa-folder_open_o, nf-fa-search
    text: mark.filtered ? "" : ""
    color: Zenon.muted
    opacity: 0.35
    font.family: Zenon.face
    font.weight: Zenon.weight
    font.pixelSize: Zenon.px(64)
  }

  Text {
    anchors.horizontalCenter: parent.horizontalCenter
    text: mark.filtered ? "No matches" : "Empty"
    color: Zenon.muted
    font.family: Zenon.face
    font.weight: Font.Bold
    font.pixelSize: Zenon.px(15)
  }
}
