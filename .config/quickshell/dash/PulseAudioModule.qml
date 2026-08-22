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
    leftPadding: 12
    rightPadding: 8

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

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: Quickshell.execDetached(["kitty", "-1", "-T", "Wiremix", "wiremix"])
    onPressed: (mouse) => { if (mouse.button === Qt.RightButton) Quickshell.execDetached(["pamixer", "-t"]) }
  }
}
