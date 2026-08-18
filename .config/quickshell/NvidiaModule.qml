import QtQuick
import Quickshell
import Quickshell.Io
import "helpers.js" as Helpers
import "."

Item {
  id: root
  implicitWidth: row.implicitWidth
  implicitHeight: 32

  property string text: ""
  property string tooltipText: ""

  Row {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    leftPadding: 4
    rightPadding: 4

    BarText {
      src: root.text
      styled: true
      color: "#dfdfdd"
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
  }

  Tooltip {
    anchorItem: root
    text: root.tooltipText
    styled: true
    show: mouse.containsMouse && root.tooltipText !== ""
  }

  Timer {
    id: refresh
    interval: 3000
    running: true
    repeat: true
    onTriggered: {
      if (!proc.running) proc.running = true;
    }
  }

  Process {
    id: proc
    command: [Helpers.home() + "/.config/quickshell/nvidia.sh"]
    stdout: SplitParser {
      onRead: (line) => {
        try {
          const o = JSON.parse(line);
          root.text = o.text ?? "";
          root.tooltipText = o.tooltip ?? "";
        } catch (e) {}
      }
    }
  }

  Component.onCompleted: proc.running = true
}
