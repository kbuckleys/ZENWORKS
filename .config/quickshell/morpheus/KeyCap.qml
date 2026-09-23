// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A KEY, DRAWN AS A KEY — the one cap every hint in the shell is written on.
//
// Five panels carried a word-for-word copy of this (lexi, zeus, ideo, folio,
// artemis), terminus had its own KeyChip, and ceres a sixth; metis and calypso
// wrote their keys as bold text instead. One file now, so a key reads the same
// wherever it is shown and a change to it reaches every panel at once.
//
// Sized by its type: `fontSize` 11 is the panels' strip (19 tall), terminus
// passes 12 for its context menu and F1 list. The padding scales with it.

import QtQuick
import "."

Rectangle {
  id: cap
  property string label: ""
  property int fontSize: 11

  implicitWidth: capText.implicitWidth + Math.round(cap.fontSize * 1.15)
  implicitHeight: cap.fontSize + 8
  radius: 5
  color: Qt.rgba(Zenon.keyInk.r, Zenon.keyInk.g, Zenon.keyInk.b, 0.10)
  border.width: 1
  border.color: Zenon.border
  visible: cap.label !== ""

  Text {
    id: capText
    anchors.centerIn: parent
    text: cap.label
    color: Zenon.keyInk
    font.family: Zenon.face
    font.pixelSize: cap.fontSize
  }
}
