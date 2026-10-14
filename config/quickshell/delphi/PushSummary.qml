// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// WHAT A PUSH SENDS (win.pushing): where to and how it went, the commits
// going out, and — given the job — how far along it is on a meter. The
// push bubble wears it, and so does Changes' clean view, in its own place
// while the push runs (user, 2026-10-14).
//
//     PushSummary { p: win.pushing; job: win.netJob; lineWidth: 460 - 28 }

import QtQuick
import "../morpheus"

Column {
  id: ps
  property var p: null
  property var job: null           // the network job, for its meter; null: none
  property real lineWidth: 432
  property bool centered: false
  readonly property var q: ps.p || ({ commits: [], more: 0, state: "going", where: "", branch: "" })
  spacing: 4

  Text {
    width: ps.lineWidth
    horizontalAlignment: ps.centered ? Text.AlignHCenter : Text.AlignLeft
    elide: Text.ElideRight
    text: (ps.q.state === "done" ? "Pushed to " : ps.q.state === "failed" ? "Not pushed to " : "Pushing to ")
      + ps.q.where + "  ·  " + ps.q.branch
    color: ps.q.state === "done" ? Zenon.green : ps.q.state === "failed" ? Zenon.red : Zenon.ink
    font.family: Zenon.face
    font.weight: Font.Bold
    font.pixelSize: Zenon.px(ps.centered ? 17 : 14)
  }
  // how far along: the job's own phase and percent, a meter under it; full
  // once it has landed, so the meter does not drop out as it ends
  Item {
    visible: !!ps.job || ps.q.state === "done"
    width: ps.lineWidth
    height: phaseText.implicitHeight + 8 + 6 + 6
    readonly property real frac: ps.q.state === "done" ? 1 : ps.job && ps.job.progress >= 0 ? ps.job.progress / 100 : 0
    Text {
      id: phaseText
      width: parent.width
      horizontalAlignment: ps.centered ? Text.AlignHCenter : Text.AlignLeft
      text: ps.q.state === "done" ? "Done" : !ps.job ? "" : ps.job.progress >= 0
        ? ps.job.phase + "  ·  " + ps.job.progress + "%" : "Connecting…"
      color: Zenon.cyan
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.features: { "tnum": 1 }
      font.pixelSize: Zenon.px(13)
    }
    Meter {
      anchors.horizontalCenter: parent.horizontalCenter
      y: phaseText.implicitHeight + 8
      vertical: false
      thickness: 6
      segLength: 6
      segGap: 3
      deadZone: 0
      accent: ps.q.state === "done" ? Zenon.green : Zenon.cyan
      segCount: Math.max(10, Math.floor(ps.lineWidth / 9))
      value: parent.frac
    }
  }
  Text {
    width: ps.lineWidth
    horizontalAlignment: ps.centered ? Text.AlignHCenter : Text.AlignLeft
    visible: ps.q.whole || ps.q.commits === null || ps.q.commits.length === 0
    text: ps.q.whole ? "A new branch there: every commit on it goes"
      : ps.q.commits === null ? "Reading the commits…" : "No new commits — the branch moves to this one"
    color: Zenon.muted
    font.family: Zenon.face
    font.weight: Zenon.weight
    font.pixelSize: Zenon.px(13)
  }
  Column {
    spacing: 4
    anchors.horizontalCenter: ps.centered ? parent.horizontalCenter : undefined
    visible: !!ps.q.commits && ps.q.commits.length > 0
    Repeater {
      model: ps.q.commits || []
      delegate: Row {
        id: cr
        required property var modelData
        spacing: 10
        Text {
          text: cr.modelData.sha
          color: Zenon.yellow
          font.family: Zenon.face
          font.features: { "tnum": 1 }
          font.pixelSize: Zenon.px(13)
        }
        Text {
          width: ps.lineWidth - 80
          elide: Text.ElideRight
          text: cr.modelData.subject
          color: Zenon.ink
          font.family: Zenon.face
          font.weight: Zenon.weight
          font.pixelSize: Zenon.px(14)
        }
      }
    }
    Text {
      visible: ps.q.more > 0
      text: "and " + ps.q.more + " more"
      color: Zenon.muted
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(13)
    }
  }
}
