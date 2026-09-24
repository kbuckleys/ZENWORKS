// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/

import QtQuick
import Quickshell
import Quickshell.Io
import "helpers.js" as Helpers
import "../oracle"
import "."

// Privacy/status indicators. Each icon owns its own slot and eases away when
// its signal goes quiet, so the group only ever shows what is actually live.
Collapsible {
  id: root

  property bool micActive: false
  property bool screenActive: false
  property bool recording: false

  active: Oracle.showStatus
    && (root.micActive || root.screenActive || root.recording)
  openWidth: row.implicitWidth

  Row {
    id: row
    anchors.centerIn: parent
    leftPadding: Zenon.padModule
    rightPadding: Zenon.padModule
    spacing: 0

    Collapsible {
      active: root.micActive
      openWidth: micIcon.implicitWidth + 8
      BarText {
        id: micIcon
        anchors.centerIn: parent
        text: "󰍬"
        color: Zenon.yellow
      }
    }

    Collapsible {
      active: root.screenActive
      openWidth: shareIcon.implicitWidth + 8
      BarText {
        id: shareIcon
        anchors.centerIn: parent
        text: "󰹁"
        color: Zenon.cyan
      }
    }

    Collapsible {
      active: root.recording
      openWidth: recIcon.implicitWidth + 8
      BarText {
        id: recIcon
        anchors.centerIn: parent
        text: ""
        color: Zenon.red
        font.pixelSize: 13

        // a recording light should read as live, not as a static glyph
        SequentialAnimation on opacity {
          running: root.recording
          loops: Animation.Infinite
          NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutSine }
          NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutSine }
        }
      }
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
  }

  Tooltip {
    anchorItem: root
    cursorArea: mouse
    text: {
      const parts = [];
      if (root.recording) parts.push("Recording screen");
      if (root.screenActive) parts.push("Screen being shared");
      if (root.micActive) parts.push("Microphone in use");
      return parts.join("\n");
    }
    show: mouse.containsMouse && root.active
  }

  // One long-lived `status.sh watch`, which prints a line only when the answer
  // changes — see the script for how it listens. It replaced running the
  // one-shot every two seconds for the whole session.
  //
  // Started and stopped by hand rather than bound: quickshell writes `running`
  // false when the process exits, which would break a binding for good.
  Process {
    id: proc
    command: [Helpers.script("status.sh"), "watch"]
    stdout: SplitParser {
      onRead: (line) => {
        try {
          const o = JSON.parse(line);
          root.micActive = o.mic === 1;
          root.screenActive = o.screen === 1;
          root.recording = o.recording === 1;
        } catch (e) {}
      }
    }
    // It never ends on its own while wanted, so an exit means it fell over.
    onExited: if (Oracle.showStatus) respawn.restart()
  }

  Timer {
    id: respawn
    interval: 2000
    onTriggered: if (Oracle.showStatus && !proc.running) proc.running = true
  }

  // Switched off in oracle there is nothing to report, and nothing to run.
  function sync() {
    if (Oracle.showStatus) {
      if (!proc.running) proc.running = true;
    } else {
      respawn.stop();
      proc.running = false;
      root.micActive = false;
      root.screenActive = false;
      root.recording = false;
    }
  }

  Connections {
    target: Oracle
    function onShowStatusChanged() { root.sync(); }
  }

  Component.onCompleted: root.sync()
}
