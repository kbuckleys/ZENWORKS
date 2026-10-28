// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// HOW FAST A DRIVE READS, IN A SHEET — forge.py bench: read speed at points
// from its start to its end, drawn as bars (a spinning disk slows toward
// its end; flash mostly holds level), the average and the spread, and how
// long a random 4 KiB read takes. Read-only: nothing on it is touched,
// the system's own disk included. The run is the manager's.
//
//     Sheet { cardH: body.implicitHeight
//       StylusBench { id: body; width: parent.width; win: sw } }

import QtQuick
import "../morpheus"
import "../terminus"
import "stylus.js" as S

FocusScope {
  id: body

  property var win: null
  readonly property var mgr: body.win ? body.win.mgr : null
  readonly property var job: body.mgr ? body.mgr.benchJob : null
  readonly property var drive: body.job ? body.job.drive : (body.win ? body.win.drive : null)
  readonly property string face: !body.job ? "ready" : body.job.result ? "done" : "running"
  readonly property var result: body.job && body.job.result && body.job.result.ok ? body.job.result : null
  readonly property var bars: S.benchBars(body.result)

  function go() {
    if (body.face === "running") return;
    if (body.face === "done") body.mgr.clearBench();
    body.mgr.bench(body.drive);
  }

  implicitHeight: col.implicitHeight + 2 * 24

  Column {
    id: col
    x: 24
    y: 24
    width: parent.width - 48
    spacing: 14

    Column {
      width: parent.width
      spacing: 3
      Text {
        textFormat: Text.PlainText
        width: parent.width
        elide: Text.ElideRight
        text: "Benchmark " + S.driveTitle(body.drive)
        color: Zenon.ink
        font.family: Zenon.face
        font.weight: Zenon.titleWeight
        font.pixelSize: Zenon.px(17)
      }
      Text {
        width: parent.width
        wrapMode: Text.Wrap
        text: "It is only read — nothing on it changes. Close what is busy with it for a fair number."
        color: Zenon.accentMuted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(13)
      }
    }

    // the bars: start of the drive at the left, its end at the right
    Item {
      visible: body.bars.length > 0
      width: parent.width
      height: 120
      Rectangle { anchors.fill: parent; radius: Zenon.radiusCard; color: Zenon.wash(0.04); border.width: 1; border.color: Zenon.border }
      Row {
        id: barRow
        anchors.fill: parent
        anchors.margins: 14
        spacing: 3
        Repeater {
          model: body.bars
          Item {
            required property var modelData
            width: (barRow.width - barRow.spacing * (body.bars.length - 1)) / Math.max(1, body.bars.length)
            height: barRow.height
            Rectangle {
              anchors.bottom: parent.bottom
              width: parent.width
              height: Math.max(2, parent.height * modelData.frac)
              radius: Zenon.rad(2)
              color: Zenon.cyan
              opacity: 0.85
            }
          }
        }
      }
    }
    Item {
      visible: body.bars.length > 0
      width: parent.width
      height: startWord.implicitHeight
      Text { id: startWord; text: "start"; color: Zenon.muted; font.family: Zenon.face; font.pixelSize: Zenon.px(11) }
      Text { anchors.right: parent.right; text: "end"; color: Zenon.muted; font.family: Zenon.face; font.pixelSize: Zenon.px(11) }
    }

    // while it runs
    Rectangle {
      id: band
      visible: body.face === "running"
      width: parent.width
      height: 8
      radius: Zenon.rad(4)
      color: Zenon.wash(0.06)
      ProgressFill { anchors.fill: parent; radius: band.radius; frac: S.phaseFrac(body.job) }
    }

    Column {
      width: parent.width
      spacing: 4
      Text {
        textFormat: Text.PlainText
        width: parent.width
        wrapMode: Text.Wrap
        text: body.face === "running" ? S.progressLine(body.job)
          : body.result ? S.benchWords(body.result)
          : body.job && body.job.result ? (body.job.result.why || "It stopped") : "About a minute: 24 points across it, then 200 random reads"
        color: body.job && body.job.result && !body.job.result.ok ? Zenon.red : Zenon.ink
        font.family: Zenon.face
        font.weight: body.result ? Zenon.titleWeight : Zenon.weight
        font.pixelSize: Zenon.px(14)
      }
      Text {
        textFormat: Text.PlainText
        visible: !!body.result
        text: body.result ? S.accessWords(body.result.accessMs) : ""
        color: Zenon.accentMuted
        font.family: Zenon.face
        font.weight: Zenon.weight
        font.pixelSize: Zenon.px(13)
      }
    }

    Row {
      anchors.right: parent.right
      spacing: 10
      DialogButton { label: "Close"; ink: Zenon.accentMuted; onClicked: body.win.closeBench() }
      DialogButton {
        visible: body.face === "running"
        label: "Stop"
        ink: Zenon.red
        onClicked: body.mgr.stopBench()
      }
      DialogButton {
        visible: body.face !== "running"
        label: body.face === "done" ? "Again" : "Start"
        primary: true
        ink: Zenon.cyan
        ready: !!body.drive
        onClicked: body.go()
      }
    }
  }

  Keys.onEscapePressed: body.win.closeBench()
  Keys.onReturnPressed: body.go()
}
