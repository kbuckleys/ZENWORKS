// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/

import QtQuick
import Quickshell
import Quickshell.Io
import "helpers.js" as Helpers

Item {
  id: root
  implicitWidth: row.implicitWidth
  implicitHeight: 32

  property string iface: ""
  property string ipaddr: ""
  property bool connected: false
  property string downText: "0.0B/s"
  property string upText: "0.0B/s"
  property var sample: null

  onIfaceChanged: {
    root.sample = null;
    root.downText = "0.0B/s";
    root.upText = "0.0B/s";
  }

  Row {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    leftPadding: 4
    rightPadding: 4

    BarText {
      src: root.connected
          ? " <span foreground='#9bbfbf'>󱞡</span> " + root.downText + " <span foreground='#9bbfbf'>~</span> " + root.upText + " <span foreground='#9bbfbf'>󱞿</span> "
          : "󰱟 "
      styled: true
      textColor: root.connected ? "#dfdfdd" : "#e78284"
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: Quickshell.execDetached(["kitty", "-1", "-T", "bandwhich", "sudo", "bandwhich"])
  }

  Tooltip {
    anchorItem: root
    text: root.connected ? root.iface + ": " + root.ipaddr : "NO NETWORK SIGNAL"
    show: mouse.containsMouse
  }

  Timer {
    id: infoTimer
    interval: 3000
    running: true
    repeat: true
    onTriggered: {
      if (!infoProc.running) infoProc.running = true;
    }
  }

  Process {
    id: infoProc
    command: ["sh", Helpers.script("netinfo.sh")]
    stdout: SplitParser {
      onRead: (line) => {
        const parts = line.split("|");
        if (parts.length === 3) {
          root.iface = parts[0];
          root.ipaddr = parts[1];
          root.connected = parts[0] !== "" && parts[2].trim() === "1";
        }
      }
    }
  }

  Process {
    id: devProc
    command: ["sh", "-c", "while true; do cat /proc/net/dev; echo __END__; sleep 1; done"]
    running: true
    stdout: SplitParser {
      onRead: (line) => root.devLine(line)
    }
  }

  property var devLines: []

  function devLine(line) {
    if (line === "__END__") {
      root.finalizeSample();
      return;
    }
    root.devLines.push(line);
  }

  function finalizeSample() {
    let rx = 0;
    let tx = 0;
    for (const l of root.devLines) {
      const idx = l.indexOf(":");
      if (idx <= 0) continue;
      const name = l.slice(0, idx).trim();
      if (name === "lo") continue;
      if (root.iface !== "" && name !== root.iface) continue;
      const nums = l.slice(idx + 1).trim().split(/\s+/).map(Number);
      if (nums.length >= 16) {
        rx += nums[0];
        tx += nums[8];
      }
    }
    root.devLines = [];
    const now = Date.now();
    if (root.sample) {
      const elapsed = (now - root.sample.time) / 1000;
      if (elapsed > 0) {
        const down = Math.max(0, (rx - root.sample.rx) / elapsed);
        const up = Math.max(0, (tx - root.sample.tx) / elapsed);
        root.downText = Helpers.powFormat(down);
        root.upText = Helpers.powFormat(up);
      }
    }
    root.sample = { rx: rx, tx: tx, time: now };
  }

  Component.onCompleted: infoProc.running = true
}
