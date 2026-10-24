// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ONE DRIVE IN STYLUS' WRITE SHEET — what it is and what is on it now
// (what writing will lose), with a box to add it to the write when it is
// not the drive the sheet was opened on (`pickable`). While it is being
// written the row is the progress: the fill runs across it and the line
// under its name says how far; once done, how it went.
//
//     StylusDrive { drive: d; picked: …; pickable: true; job: mgr.job
//                   why: …; onToggled: … }

import QtQuick
import "../morpheus"
import "../morpheus/controls"
import "../terminus"
import "stylus.js" as S

Rectangle {
  id: card

  property var drive: null
  property bool picked: false
  property bool pickable: false
  // the write this drive is part of, or null
  property var job: null
  // why the chosen image cannot go here, "" when it can
  property string why: ""
  signal toggled()

  readonly property var result: card.job && card.job.result ? S.resultOf(card.job.result, card.drive ? card.drive.dev : "") : null
  readonly property bool running: !!card.job && !card.job.result

  width: parent ? parent.width : 0
  height: 68
  radius: Zenon.radiusCard
  color: Zenon.wash(0.04)
  border.width: 1
  border.color: Zenon.border

  ProgressFill {
    anchors.fill: parent
    anchors.margins: 1
    radius: card.radius - 1
    visible: !!card.job
    frac: S.phaseFrac(card.job)
    ink: card.result && !card.result.ok ? Zenon.red : Zenon.cyan
  }

  // a box of its own, so every drive's name starts at the same x whatever
  // its glyph's width
  Text {
    id: glyph
    x: 16
    width: 36
    horizontalAlignment: Text.AlignHCenter
    anchors.verticalCenter: parent.verticalCenter
    text: S.driveGlyph(card.drive)
    color: card.result ? (card.result.ok ? Zenon.green : Zenon.red) : card.picked ? Zenon.cyan : Zenon.accentMuted
    font.family: Zenon.glyphFace
    font.pixelSize: Zenon.px(26)
  }

  Column {
    anchors.left: glyph.right
    anchors.leftMargin: 14
    anchors.right: box.visible ? box.left : parent.right
    anchors.rightMargin: 16
    anchors.verticalCenter: parent.verticalCenter
    spacing: 3
    Text {
      width: parent.width
      elide: Text.ElideRight
      text: S.driveTitle(card.drive) + "  ·  " + S.driveLine(card.drive)
      color: Zenon.ink
      font.family: Zenon.face
      font.weight: Zenon.titleWeight
      font.pixelSize: Zenon.px(14)
    }
    // what is on it; while writing, how far; after, how it went; and when
    // the image cannot go here, why
    Text {
      width: parent.width
      elide: Text.ElideRight
      text: card.result ? card.result.words : card.running ? S.progressLine(card.job)
        : card.why !== "" ? card.why : S.partsLine(card.drive)
      color: card.result ? (card.result.ok ? Zenon.green : Zenon.red)
        : card.running ? Zenon.ink : card.why !== "" ? Zenon.yellow : Zenon.muted
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(12)
    }
  }

  TapHandler { enabled: card.pickable && !card.job; onTapped: card.toggled() }

  Check {
    id: box
    anchors.right: parent.right
    anchors.rightMargin: 16
    anchors.verticalCenter: parent.verticalCenter
    visible: card.pickable && !card.job
    lit: card.picked
    onToggled: card.toggled()
  }
}
