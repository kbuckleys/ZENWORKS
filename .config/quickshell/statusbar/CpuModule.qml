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
  property string text: ""
  property string tooltipText: ""

  Row {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    leftPadding: 4
    rightPadding: 4

    BarText {
      id: label
      src: root.text
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

  Tooltip {
    anchorItem: root
    text: root.tooltipText
    styled: true
    show: mouse.containsMouse && root.tooltipText !== ""
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
    command: [Helpers.home() + "/.config/quickshell/statusbar/scripts/cpu.sh"]
    stdout: SplitParser {
      onRead: (line) => {
        try {
          const o = JSON.parse(line);
          root.usage = o.usage ?? 0;
          root.text = o.text ?? "";
          root.tooltipText = o.tooltip ?? "";
        } catch (e) {}
      }
    }
  }

  Component.onCompleted: proc.running = true
}