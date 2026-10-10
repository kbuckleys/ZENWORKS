// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ── a continuous setting in the settings panel ──────────────────────────
// Opacity and zoom are both a narrow useful range where the difference
// between two neighbouring values is something you judge by looking at the
// window rather than by counting presses. Which is a slider, twice.
//
// Its own file since 2026-10-08, out of TerminusWindow.qml, where it was an
// inline component. `term` is the terminus window; every place that makes
// one passes it (`term: root`).

import QtQuick
import QtQuick.Shapes
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick.Effects
import QtMultimedia
import Qt.labs.folderlistmodel
import "../morpheus"
import "../picasso"
import "../oracle"
import "terminus.js" as Terminus
import "../morpheus/icons.js" as Icons
import "../morpheus/thumbs.js" as Thumbs
import "tags.js" as Tags
import "collections.js" as Coll

Item {
  // the terminus window — passed in by whoever makes one. NOT `root`:
  // inside a delegate a property of that name shadowed the window's id
  // and bound to itself (2026-10-08)
  property var term: null
  id: sl
  property string label: ""
  property real value: 0
  property real from: 0
  property real to: 1
  property string readout: ""
  // dimmed when the value is the ordinary one, so it reads as "normal"
  // rather than as something you have changed
  property real neutral: -1
  // Wide enough for the longest label the panel actually uses. At 88 "Text
  // size" came out as "Text s…", which is a slider labelled by a guess.
  property real labelW: 116
  // One notch of the wheel. A fraction of the span by default, so a slider
  // that says nothing still behaves; the zoom passes the same 0.1 its keys
  // and ctrl+wheel already use, because three ways of doing one thing that
  // move by different amounts is three things to learn.
  property real wheelStep: sl.span / 20
  signal moved(real v)

  // Nudged by the WHEEL'S OWN NOTCH, so the arrows and the wheel and the
  // keys that already step the zoom all move it by the same amount. Nothing
  // to activate: a slider has no state to flip.
  readonly property bool reachable: true
  function activate() {}
  function nudge(d) {
    const v = Math.max(sl.from,
                       Math.min(sl.to, sl.value + d * sl.wheelStep));
    if (v !== sl.value) sl.moved(v);
  }
  Component.onCompleted: term.prefEnrol(sl)

  width: parent ? parent.width : 0
  height: 34

  readonly property real span: sl.to - sl.from
  readonly property real frac: sl.span > 0
    ? Math.max(0, Math.min(1, (sl.value - sl.from) / sl.span)) : 0

  Text {
    anchors.left: parent.left
    anchors.leftMargin: 14
    anchors.right: slTrack.left
    anchors.rightMargin: 10
    anchors.verticalCenter: parent.verticalCenter
    text: sl.label
    elide: Text.ElideRight
    color: Zenon.white
    font.family: Zenon.face
    font.weight: Zenon.weight
    font.pixelSize: Zenon.px(15)
  }

  Text {
    id: slRead
    anchors.right: parent.right
    anchors.rightMargin: 14
    anchors.verticalCenter: parent.verticalCenter
    width: 38
    horizontalAlignment: Text.AlignRight
    text: sl.readout
    color: (sl.neutral >= 0 && Math.abs(sl.value - sl.neutral) < 0.001)
      ? Zenon.muted : Zenon.cyan
    font.family: Zenon.face
    font.weight: Zenon.weight
    font.pixelSize: Zenon.px(13)
  }

  Rectangle {
    id: slTrack
    anchors.left: parent.left
    anchors.leftMargin: sl.labelW
    anchors.right: slRead.left
    anchors.rightMargin: 10
    anchors.verticalCenter: parent.verticalCenter
    height: 4
    radius: 2
    color: Qt.rgba(Zenon.white.r, Zenon.white.g, Zenon.white.b, 0.10)

    Rectangle {
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: Math.round(sl.frac * slTrack.width)
      radius: 2
      color: Zenon.cyan
    }

    Rectangle {
      x: Math.round(sl.frac * slTrack.width) - 6
      anchors.verticalCenter: parent.verticalCenter
      width: 12
      height: 12
      radius: 6
      color: slArea.pressed ? Zenon.white : Zenon.cyan
      border.width: 1
      border.color: Zenon.border
    }

    // GRABBABLE, which a 4px line is not. The negative margins give the
    // pointer ten pixels either side — and mean a position has to have
    // those ten taken back off it before it is a fraction of the track.
    MouseArea {
      id: slArea
      anchors.fill: parent
      anchors.margins: -10

      function seek(x) {
        if (slTrack.width <= 0) return;
        const f = Math.max(0, Math.min(1, (x - 10) / slTrack.width));
        sl.moved(sl.from + f * sl.span);
      }
      onPressed: (m) => slArea.seek(m.x)
      onPositionChanged: (m) => { if (slArea.pressed) slArea.seek(m.x); }

      // The wheel steps it. Accepted rather than passed on, so a wheel
      // aimed at the slider does not scroll the panel out from under it —
      // the pointer is on the control, so the control is what it means.
      onWheel: (w) => {
        const d = w.angleDelta.y > 0 ? sl.wheelStep : -sl.wheelStep;
        sl.moved(Math.max(sl.from, Math.min(sl.to, sl.value + d)));
        w.accepted = true;
      }
    }
  }
}
