import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import "."

Item {
  id: root
  implicitWidth: row.implicitWidth
  implicitHeight: 32

  readonly property bool micActive: Pipewire.linkGroups.values.some(g =>
      (g.source.type & PwNodeType.AudioSource) !== 0
      && (g.target.type & PwNodeType.AudioInStream) !== 0)

  readonly property bool videoActive: Pipewire.linkGroups.values.some(g =>
      (g.source.type & PwNodeType.VideoSource) !== 0)

  property string tooltipText: {
    const parts = [];
    if (root.micActive) parts.push("Microphone in use");
    if (root.videoActive) parts.push("Camera / screen sharing");
    return parts.join("\n");
  }

  Row {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    leftPadding: root.micActive || root.videoActive ? 12 : 0
    rightPadding: root.micActive || root.videoActive ? 12 : 0
    spacing: 8

    BarText {
      visible: root.micActive
      src: " 󰍬 "
      color: "#9bbfbf"
    }

    BarText {
      visible: root.videoActive
      src: " 󰅶 "
      color: "#9bbfbf"
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
}