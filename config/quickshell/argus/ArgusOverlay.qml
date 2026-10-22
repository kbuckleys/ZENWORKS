// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// WHAT ARGUS PUTS ON THE SCREEN AROUND A RECORDING — made the first time
// it is asked for (ArgusManager), never before:
//
//   the countdown   3 · 2 · 1 in the middle of the focused screen before
//                   argus.lua starts wf-recorder; gone before the first
//                   frame (the script waits the count out, then a beat)
//   the camera      the webcam in a round bubble in a corner (Oracle's
//                   recCameraCorner) while a recording runs, so it is in
//                   the video
//
// Neither takes the pointer or the keys (an empty input mask): what is
// under them is still what is clicked.

import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import "../morpheus"
import "../oracle"
import "argus.js" as A

Scope {
  id: ov

  // ── THE COUNTDOWN ──────────────────────────────────────────────────────
  property int left: 0
  function countdown(secs) {
    ov.left = Math.max(0, Math.min(10, secs));
    countWin.screen = Oracle.focusedScreen();
    if (ov.left > 0) tickTimer.restart();
  }
  Timer {
    id: tickTimer
    interval: 1000
    repeat: true
    onTriggered: { ov.left = Math.max(0, ov.left - 1); if (ov.left === 0) tickTimer.stop(); }
  }
  PanelWindow {
    id: countWin
    visible: ov.left > 0
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "argus-countdown"
    mask: Region {}
    Rectangle {
      anchors.centerIn: parent
      width: 180
      height: 180
      radius: 90
      color: Zenon.hud(0.8)
      border.width: 1
      border.color: Zenon.border
      Text {
        id: digit
        anchors.centerIn: parent
        text: String(ov.left)
        color: Zenon.ink
        font.family: Zenon.face
        font.weight: Zenon.titleWeight
        font.pixelSize: Zenon.px(88)
        font.features: { "tnum": 1 }
      }
      // each number arrives a little large and settles, so a change reads
      scale: 1
      SequentialAnimation on scale {
        id: pop
        running: false
        NumberAnimation { from: 1.12; to: 1; duration: Zenon.ms(260); easing.type: Easing.OutCubic }
      }
    }
    Connections { target: ov; function onLeftChanged() { if (ov.left > 0) pop.restart(); } }
  }

  // ── THE CAMERA ─────────────────────────────────────────────────────────
  property bool recording: false
  readonly property bool hasCamera: devices.videoInputs.length > 0
  readonly property bool cameraOn: ov.recording && Oracle.recCamera && ov.hasCamera
  readonly property var corner: A.cornerAnchors(Oracle.recCameraCorner)
  MediaDevices { id: devices }
  CaptureSession {
    camera: Camera { active: ov.cameraOn }
    videoOutput: ov.cameraOn ? camView : null
  }
  PanelWindow {
    id: camWin
    visible: ov.cameraOn
    screen: Oracle.focusedScreen()
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: 240
    implicitHeight: 240
    anchors { top: ov.corner.top; bottom: ov.corner.bottom; left: ov.corner.left; right: ov.corner.right }
    margins { top: 28; bottom: 28; left: 28; right: 28 }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "argus-camera"
    mask: Region {}
    // the picture cut round (a ClippingRectangle, as every round picture
    // in the suite is), a ring around it
    ClippingRectangle {
      anchors.fill: parent
      radius: width / 2
      color: Zenon.layerBg
      VideoOutput {
        id: camView
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectCrop
      }
    }
    Rectangle {
      anchors.fill: parent
      radius: width / 2
      color: "transparent"
      border.width: 3
      border.color: Zenon.alpha(Zenon.white, 0.85)
    }
  }
}
