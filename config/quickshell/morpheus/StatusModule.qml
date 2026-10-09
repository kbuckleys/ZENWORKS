// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
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
  property bool cameraActive: false
  // socordia's Keep Awake: the screen will not lock or sleep. Handed in by
  // shell.qml; a click on the cup asks for it to be switched off.
  property bool awake: false
  signal awakeToggled()

  active: Oracle.showStatus
    && (root.micActive || root.micMuted || root.screenActive || root.recording
        || root.cameraActive || root.awake)
  openWidth: row.implicitWidth

  // ── THE MIC'S MUTE ──────────────────────────────────────────────────
  // The default source's own switch, the one pavucontrol flips. A muted mic
  // stays on the bar, struck through, whether or not anything is capturing:
  // the moment you most need to know it is muted is the moment before you
  // speak, and nothing is capturing then yet.
  PwObjectTracker { objects: [Pipewire.defaultAudioSource] }
  readonly property var micAudio: Pipewire.defaultAudioSource ? Pipewire.defaultAudioSource.audio : null
  readonly property bool micMuted: root.micAudio ? root.micAudio.muted : false
  function toggleMic() { if (root.micAudio) root.micAudio.muted = !root.micAudio.muted; }

  // Through hyprland's own recorder (hypr/lua/wf-recorder.lua) rather than a
  // pkill here, so the file is finished and announced the way Super+R does it.
  function stopRecording() {
    Quickshell.execDetached(["hyprctl", "repl", 'ZenRecord("stop")']);
  }

  Row {
    id: row
    anchors.centerIn: parent
    leftPadding: Zenon.padModule
    rightPadding: Zenon.padModule
    spacing: 0

    Collapsible {
      id: awakeBox
      active: root.awake
      openWidth: awakeIcon.implicitWidth + 8
      BarText {
        id: awakeIcon
        anchors.centerIn: parent
        text: "\uEC15"
        color: Zenon.sand
        // the bell's and the update glyph's size, not body text's
        numeric: true
        font.pixelSize: Zenon.clockSize
      }
    }

    Collapsible {
      id: micBox
      active: root.micActive || root.micMuted
      openWidth: micIcon.implicitWidth + 8
      BarText {
        id: micIcon
        anchors.centerIn: parent
        text: root.micMuted ? "󰍭" : "󰍬"
        color: root.micMuted ? Zenon.muted : Zenon.yellow
      }
    }

    Collapsible {
      active: root.cameraActive
      openWidth: camIcon.implicitWidth + 8
      BarText {
        id: camIcon
        anchors.centerIn: parent
        text: "\uEAD9"
        color: Zenon.magenta
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
      id: recBox
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
    // The cup, the mic and the recording light take a click — each is a
    // switch you would otherwise go hunting for. Screen sharing and the
    // camera only report: what to stop is the application's to say.
    cursorShape: root.hit(mouseX) !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: (e) => {
      const what = root.hit(e.x);
      if (what === "awake") root.awakeToggled();
      else if (what === "mic") root.toggleMic();
      else if (what === "rec") root.stopRecording();
    }
  }

  // Which clickable icon is under x, or "". Boxes that have eased shut are
  // zero wide, so they never match.
  function hit(x) {
    const boxes = [[awakeBox, "awake"], [micBox, "mic"], [recBox, "rec"]];
    for (const [box, name] of boxes) {
      const p = box.mapFromItem(mouse, x, 0);
      if (box.width > 0 && p.x >= 0 && p.x <= box.width) return name;
    }
    return "";
  }

  Tooltip {
    anchorItem: root
    cursorArea: mouse
    text: {
      const parts = [];
      if (root.recording) parts.push("Recording screen — click the light to stop");
      if (root.screenActive) parts.push("Screen being shared");
      if (root.cameraActive) parts.push("Camera in use");
      if (root.micMuted) parts.push("Microphone muted — click to unmute");
      else if (root.micActive) parts.push("Microphone in use — click to mute");
      if (root.awake) parts.push("Keep Awake is on — click the cup to let the screen sleep");
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
          root.cameraActive = o.camera === 1;
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
      root.cameraActive = false;
    }
  }

  Connections {
    target: Oracle
    function onShowStatusChanged() { root.sync(); }
  }

  Component.onCompleted: root.sync()
}
