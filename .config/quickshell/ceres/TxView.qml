// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A TRANSACTION, WATCHED — its progress while it runs and what it did once it
// has. One view for the panel and the window, reading Ceres and nothing
// else, so the same run looks the same wherever you look at it from.
//
//   running   what paru is doing, a bar filled by pacman.log's own record
//             of each package (pacman draws no bar without a terminal), the
//             last package handled, and the raw log under it
//   done      counts by verb, the disk moved, and every package changed
//   failed    paru's own last error, and the log's tail that led to it

import QtQuick
import "../morpheus"
import "."
import "ceres.js" as Cer

Item {
  id: view
  // Text size over the panel's: the window reads 2px larger.
  property int grow: 0

  readonly property bool running: Ceres.txBusy
  readonly property bool failed: Ceres.txState === "failed"
  readonly property var tally: Cer.tally(Ceres.txEvents)

  // What a holder of this view needs to size itself for the result.
  readonly property int resultRows: view.failed ? 8 : Ceres.txEvents.length

  // ── running ─────────────────────────────────────────────────────────────
  Item {
    visible: view.running
    anchors.fill: parent

    // ── THE PHASE IS THE BAR ──────────────────────────────────────────────
    // What paru is doing, on a band that fills as pacman records each package
    // — rather than a label with a thin bar under it, two things to read
    // for one fact. The fill is translucent so the words on it stay the
    // loudest thing in the band.
    Rectangle {
      id: track
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      height: 36
      radius: Zenon.windowRadius
      color: Zenon.headBg
      border.width: 1
      border.color: Zenon.border
      clip: true

      Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        radius: Zenon.windowRadius
        color: Qt.rgba(Zenon.yellow.r, Zenon.yellow.g, Zenon.yellow.b, 0.22)
        width: parent.width * Math.min(1, Ceres.txEvents.length
          / Math.max(1, Ceres.txExpected, Ceres.txEvents.length))
        Behavior on width { NumberAnimation { duration: Zenon.slow; easing.type: Zenon.ease } }
      }

      Text {
        id: phase
        anchors.left: parent.left
        anchors.leftMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        text: Ceres.txPhase !== "" ? Ceres.txPhase : "Working"
        color: Zenon.white
        font.family: Zenon.face
        font.weight: Font.Bold
        font.pixelSize: 15 + view.grow
      }
      Text {
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        text: Ceres.txEvents.length + " / " + Math.max(Ceres.txExpected, Ceres.txEvents.length)
        color: Zenon.keyInk
        font.family: Zenon.face
        font.pixelSize: 14 + view.grow
      }
    }

    Text {
      id: lastEvent
      anchors.top: track.bottom
      anchors.topMargin: 10
      anchors.left: parent.left
      anchors.right: parent.right
      elide: Text.ElideRight
      text: {
        const e = Ceres.txEvents[Ceres.txEvents.length - 1];
        return e ? e.verb + " " + e.name + (e.to ? " " + e.to : "") : "";
      }
      color: Zenon.white
      font.family: Zenon.face
      font.pixelSize: 14 + view.grow
    }

    ListView {
      id: logView
      // terminus' scrollbar — see morpheus/ScrollRail. Parented to the view
      // itself, so in a Flickable it stays put instead of scrolling away.
      ScrollRail {
        target: logView
        parent: logView
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
      }
      anchors.top: lastEvent.bottom
      anchors.topMargin: 10
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      clip: true
      model: Ceres.txLog
      onCountChanged: logView.positionViewAtEnd()
      delegate: Text {
        required property string modelData
        width: logView.width - 14
        elide: Text.ElideRight
        text: modelData
        // the log is read, not glanced at: keyInk, not muted
        color: Zenon.keyInk
        font.family: Zenon.face
        font.pixelSize: 14 + view.grow
      }
    }
  }

  // ── done, or not ────────────────────────────────────────────────────────
  Item {
    visible: !view.running
    anchors.fill: parent

    Text {
      id: resultLine
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      wrapMode: Text.Wrap
      text: {
        if (view.failed) return Ceres.txError;
        const t = view.tally, parts = [];
        for (const v of Cer.VERBS) if (t[v].length) parts.push(t[v].length + " " + v);
        // A run that changed no package — paccache, the download sweep — is
        // reported in the tool's own words rather than as "nothing changed",
        // which for a cache cleanup reads as the button not working.
        return (parts.length ? parts.join(" · ")
                             : ((Cer.summaryLine ? Cer.summaryLine(Ceres.txLog) : "") || "nothing changed"))
          + (Ceres.txDisk !== "" ? "      " + Ceres.txDisk : "");
      }
      color: view.failed ? Zenon.red : Zenon.white
      font.family: Zenon.face
      font.weight: Font.Bold
      font.pixelSize: 15 + view.grow
    }

    // On failure the log's last lines are the explanation.
    ListView {
      id: failLog
      ScrollRail {
        target: failLog
        parent: failLog
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
      }
      visible: view.failed
      anchors.top: resultLine.bottom
      anchors.topMargin: 10
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      clip: true
      model: view.failed ? Ceres.txLog.slice(-8) : []
      delegate: Text {
        required property string modelData
        width: failLog.width - 14
        elide: Text.ElideRight
        text: modelData
        // the log is read, not glanced at: keyInk, not muted
        color: Zenon.keyInk
        font.family: Zenon.face
        font.pixelSize: 14 + view.grow
      }
    }

    // On success, what changed is.
    ListView {
      id: changes
      ScrollRail {
        target: changes
        parent: changes
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
      }
      ElasticScroll { view: changes }
      visible: !view.failed
      anchors.top: resultLine.bottom
      anchors.topMargin: 10
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      model: view.failed ? [] : Ceres.txEvents
      delegate: ChangeRow {
        required property var modelData
        width: changes.width - 14
        u: modelData
        glyph: modelData.verb === "removed" ? ""
          : modelData.verb === "installed" ? "" : ""
        glyphInk: modelData.verb === "removed" ? Zenon.red
          : modelData.verb === "installed" ? Zenon.green : Zenon.blue
      }
    }
  }
}
