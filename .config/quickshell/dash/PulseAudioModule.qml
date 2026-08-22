// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import "helpers.js" as Helpers
import "."

Item {
  id: root
  implicitWidth: row.implicitWidth
  implicitHeight: 32

  PwObjectTracker {
    objects: [Pipewire.defaultAudioSink]
  }

  Row {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    leftPadding: 4
    rightPadding: 4

    BarText {
      text: {
        const sink = Pipewire.defaultAudioSink;
        if (!sink || !sink.audio) return "";
        if (sink.audio.muted) return "";
        return String(Math.round(sink.audio.volume * 100));
      }
      color: {
        const sink = Pipewire.defaultAudioSink;
        if (sink && sink.audio && sink.audio.muted) return "#e78284";
        return "#9bbfbf";
      }
    }
  }

  property string tooltipText: {
    const sink = Pipewire.defaultAudioSink;
    if (!sink || !sink.audio) return "Volume: --";
    if (sink.audio.muted) return "Volume: Muted";
    return "Volume: " + Math.round(sink.audio.volume * 100) + "%";
  }
  property bool hovered: mouse.containsMouse

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: Quickshell.execDetached(["kitty", "-1", "-T", "Wiremix", "wiremix"])
    onPressed: (mouse) => { if (mouse.button === Qt.RightButton) Quickshell.execDetached(["pamixer", "-t"]) }
    onWheel: (wheel) => {
      const sink = Pipewire.defaultAudioSink;
      if (!sink || !sink.audio) return;
      let vol = sink.audio.volume;
      if (wheel.angleDelta.y > 0) vol = Math.min(1, vol + 0.01);
      else if (wheel.angleDelta.y < 0) vol = Math.max(0, vol - 0.01);
      else return;
      sink.audio.volume = vol;
      wheel.accepted = true;
    }
  }
}
