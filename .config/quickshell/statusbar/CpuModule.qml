// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/

import QtQuick
import Quickshell
import Quickshell.Io
import "helpers.js" as Helpers
import "."

Item {
  id: root
  implicitWidth: row.implicitWidth
  implicitHeight: 32

  property int usage: 0
  property var prev: null

  Row {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    leftPadding: 4
    rightPadding: 4

    BarText {
      id: label
      src: " <span foreground='#a2a8bc'>CPU</span>  " + root.usage + "% "
      styled: true
      color: {
        if (root.usage >= 90) return "#e78284";
        if (root.usage >= 50) return "#e0d8a4";
        return "#dfdfdd";
      }
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: Quickshell.execDetached(["kitty", "-1", "-T", "sysmon", "btop"])
  }

  Timer {
    id: refresh
    interval: 1000
    running: true
    repeat: true
    onTriggered: {
      if (!proc.running) proc.running = true;
    }
  }

  Process {
    id: proc
    command: ["cat", "/proc/stat"]
    stdout: SplitParser {
      onRead: (line) => root.parseCpu(line)
    }
  }

  Component.onCompleted: proc.running = true

  function parseCpu(line) {
    if (!line.startsWith("cpu ")) return;
    const parts = line.trim().split(/\s+/).map(Number);
    const idle = parts[4] + (parts[5] || 0);
    const total = parts.slice(1).reduce((a, b) => a + b, 0);
    if (root.prev) {
      const dIdle = idle - root.prev.idle;
      const dTotal = total - root.prev.total;
      if (dTotal > 0) root.usage = Math.round(100 * (1 - dIdle / dTotal));
    }
    root.prev = { idle: idle, total: total };
  }
}
