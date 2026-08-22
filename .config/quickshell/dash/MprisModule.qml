// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/

import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import "helpers.js" as Helpers
import "."

Item {
  id: root
  implicitWidth: row.implicitWidth
  implicitHeight: 32

  property var player: null
  property string title: ""
  property string artist: ""
  property string album: ""

  visible: root.player !== null

  Row {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    leftPadding: root.visible ? 4 : 0
    rightPadding: root.visible ? 4 : 0

    BarText {
      id: label
      text: {
        if (!root.player) return "";
        return root.player.isPlaying ? "\uF04B" : "\uF04C";
      }
      color: "#9bbfbf"
    }
  }

  property bool hovered: mouse.containsMouse
  property string mprisTooltipText: {
    if (!root.player) return "";
    const parts = [root.title, root.artist, root.album].filter((s) => s && s !== "");
    return parts.join("\n");
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    onClicked: (mouse) => {
      console.log("MPR clicked button=", mouse.button)
      if (mouse.button !== Qt.LeftButton) return;
      if (root.player) root.player.previous();
      else Quickshell.execDetached(["playerctl", "previous"]);
    }
    onPressed: (mouse) => {
      console.log("MPR pressed button=", mouse.button, "player=", root.player ? root.player.identity : "none")
      if (mouse.button === Qt.RightButton) {
        if (root.player) root.player.next();
        else Quickshell.execDetached(["playerctl", "next"]);
      } else if (mouse.button === Qt.MiddleButton) {
        if (root.player) root.player.togglePlaying();
        else Quickshell.execDetached(["playerctl", "play-pause"]);
      }
    }
  }

  Timer {
    id: refresh
    interval: 1000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Component.onCompleted: root.refresh()

  function refresh() {
    const players = Mpris.players.values;
    let paused = null;
    for (let i = 0; i < players.length; ++i) {
      const p = players[i];
      if (p.isPlaying) {
        root.player = p;
        root.title = p.trackTitle;
        root.artist = p.trackArtist;
        root.album = p.trackAlbum;
        return;
      }
      if (paused === null && p.playbackState === MprisPlaybackState.Paused) paused = p;
    }
    if (paused) {
      root.player = paused;
      root.title = paused.trackTitle;
      root.artist = paused.trackArtist;
      root.album = paused.trackAlbum;
    } else {
      root.player = null;
      root.title = "";
      root.artist = "";
      root.album = "";
    }
  }
}
