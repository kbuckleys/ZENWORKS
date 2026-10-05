// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A labelled slider: the name on the left, the track, the value on the
// right. A click on the value puts it back to its default.
//
// One of picasso's controls, shared by the focus card and the viewer.

import QtQuick
import "../morpheus"

Item {
  id: sl
  property string label: ""
  property real value: 0
  property real from: 0
  property real to: 1
  property real rest: 0
  property string valueText: ""
  property bool kbOn: false
  signal moved(real v)
  height: 30

  Text {
    id: slLabel
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    width: 88
    text: sl.label
    color: sl.value !== sl.rest ? Zenon.white : Zenon.muted
    font.family: Zenon.face
    font.pixelSize: 14
  }
  Text {
    id: slValue
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    width: 44
    horizontalAlignment: Text.AlignRight
    text: sl.valueText
    color: slValMa.containsMouse ? Zenon.cyan : Zenon.muted
    font.family: Zenon.face
    font.pixelSize: 13
    MouseArea {
      id: slValMa
      anchors.fill: parent
      hoverEnabled: true
      onClicked: sl.moved(sl.rest)
    }
  }
  Item {
    id: track
    anchors.left: slLabel.right
    anchors.right: slValue.left
    anchors.rightMargin: 10
    anchors.verticalCenter: parent.verticalCenter
    height: 18
    readonly property real t: (sl.value - sl.from) / (sl.to - sl.from)
    readonly property real t0: (Math.max(sl.from, Math.min(sl.to, sl.rest)) - sl.from) / (sl.to - sl.from)

    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width
      height: 4
      radius: 2
      color: Qt.rgba(1, 1, 1, 0.1)
    }
    // filled from the resting value, so a signed slider fills both ways
    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      x: Math.min(track.t, track.t0) * track.width
      width: Math.abs(track.t - track.t0) * track.width
      height: 4
      radius: 2
      color: Zenon.cyan
    }
    Rectangle {
      x: track.t * track.width - width / 2
      anchors.verticalCenter: parent.verticalCenter
      width: 14
      height: 14
      radius: 7
      color: slMa.pressed || slMa.containsMouse ? Zenon.cyan : Zenon.white
    }
    MouseArea {
      id: slMa
      anchors.fill: parent
      anchors.margins: -4
      hoverEnabled: true
      preventStealing: true
      function set(m) {
        const t = Math.max(0, Math.min(1, (m.x - 4) / track.width));
        sl.moved(Math.round((sl.from + t * (sl.to - sl.from)) * 100) / 100);
      }
      onPressed: (m) => set(m)
      onPositionChanged: (m) => { if (pressed) set(m); }
    }
    Ring { on: sl.kbOn; anchors.margins: -5 }
  }
}
