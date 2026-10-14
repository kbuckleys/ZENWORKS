// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A GROUP'S HEADING in a delphi list — STAGED  3, NEEDS ATTENTION  2,
// LOCAL  5 — the same in every page (user, 2026-10-14: each list had drawn
// its own, at three insets and three heights). The word bold and spaced,
// its count beside it a step fainter, a note after (History's Everywhere:
// where the repository is). Sits a little low in its row, so it reads as
// the start of what is under it rather than the end of what is above.
//
//   GroupHead { title: "Staged"; count: 3; inset: 16; ink: Zenon.red }

import QtQuick
import "../morpheus"

Row {
  id: head
  property string title: ""
  property int count: -1
  property string note: ""
  property int inset: 22
  property color ink: Zenon.muted
  x: head.inset
  anchors.verticalCenter: parent ? parent.verticalCenter : undefined
  anchors.verticalCenterOffset: 4
  spacing: 10
  Text {
    text: head.title.toUpperCase()
    color: head.ink
    font.family: Zenon.face
    font.weight: Font.Bold
    font.letterSpacing: 1
    font.pixelSize: Zenon.px(12)
  }
  Text {
    visible: head.count >= 0
    text: head.count >= 0 ? String(head.count) : ""
    color: head.ink
    opacity: 0.6
    font.family: Zenon.face
    font.weight: Font.Bold
    font.features: { "tnum": 1 }
    font.pixelSize: Zenon.px(12)
  }
  Text {
    visible: head.note !== ""
    text: head.note
    color: Zenon.muted
    opacity: 0.8
    font.family: Zenon.face
    font.weight: Zenon.weight
    font.pixelSize: Zenon.px(12)
  }
}
