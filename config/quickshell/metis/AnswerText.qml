// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/

import QtQuick
import "../morpheus"
import "metis.js" as Metis

// AN ANSWER, WEIGHTED BY WHAT IT IS FOR. The number is what you came for,
// so it is the large thing in the blue; the unit beside it is smaller and
// quieter, and a time zone's date after the " · " quieter still. The split
// is Metis.answerChars.
//
// THE DIGITS ROLL. Each is a column of 0–9 behind a one-digit window that
// slides to its new value, so an answer settling as you type is seen
// settling rather than flickering. The slots are by position: as long as the
// answer keeps its length, every digit rolls from where it was.
//
// Every digit is the width of a 0, so the face being proportional no longer
// shuffles the answer sideways as it changes.
Item {
  id: root

  property string value: ""
  property color ink: Zenon.blue
  property color unitInk: Zenon.keyInk
  property int big: 26
  readonly property int small: Math.round(root.big * 0.65)
  readonly property var chars: Metis.answerChars(root.value)

  implicitWidth: row.implicitWidth
  implicitHeight: bigFm.height

  FontMetrics { id: bigFm; font.family: Zenon.face; font.weight: Font.Bold; font.pixelSize: root.big }
  FontMetrics { id: smallFm; font.family: Zenon.face; font.weight: Font.Bold; font.pixelSize: root.small }
  FontMetrics { id: quietFm; font.family: Zenon.face; font.weight: Font.Bold; font.pixelSize: root.small - 2 }

  Row {
    id: row

    Repeater {
      model: root.chars.length

      delegate: Item {
        id: slot
        required property int index
        readonly property var ch: root.chars[slot.index] || ({ c: "", big: false, quiet: false })
        readonly property bool digit: slot.ch.big && /^[0-9]$/.test(slot.ch.c)
        readonly property var fm: slot.ch.big ? bigFm : slot.ch.quiet ? quietFm : smallFm

        width: slot.digit ? bigFm.advanceWidth("0") : slot.fm.advanceWidth(slot.ch.c)
        height: bigFm.height
        clip: slot.digit

        // anything that is not a digit: a unit, a comma, a colon
        Text {
          visible: !slot.digit
          // on the large figures' baseline, whatever its own size
          y: bigFm.ascent - slot.fm.ascent
          text: slot.ch.c
          color: slot.ch.big ? root.ink : root.unitInk
          opacity: slot.ch.quiet ? 0.85 : 1
          font.family: Zenon.face
          font.weight: Font.Bold
          font.pixelSize: slot.fm.font.pixelSize
        }

        // a digit: 0–9 stacked, the window over the one it is
        Column {
          visible: slot.digit
          y: slot.digit ? -Number(slot.ch.c) * bigFm.height : 0
          Behavior on y {
            NumberAnimation { duration: Zenon.slow * 2; easing.type: Easing.OutCubic }
          }

          Repeater {
            model: 10
            delegate: Text {
              required property int index
              width: bigFm.advanceWidth("0")
              height: bigFm.height
              horizontalAlignment: Text.AlignHCenter
              text: String(index)
              color: root.ink
              font.family: Zenon.face
              font.weight: Font.Bold
              font.pixelSize: root.big
            }
          }
        }
      }
    }
  }
}
