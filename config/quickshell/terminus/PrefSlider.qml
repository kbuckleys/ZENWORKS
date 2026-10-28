// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ── a continuous setting in the settings panel ──────────────────────────
// Opacity and zoom are both a narrow useful range where the difference
// between two neighboring values is something you judge by looking at the
// window rather than by counting presses. Which is a slider, twice.
//
// Its own file since 2026-10-08, out of TerminusWindow.qml, where it was an
// inline component. `term` is the terminus window; every place that makes
// one passes it (`term: root`).

import QtQuick
import "../morpheus"
import "../morpheus/helpers.js" as Helpers

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
  // room for the readout: a percent fits the 38 it always had, a size
  // ("28.6 GiB", stylus' partition sheet) does not
  property real readoutW: 38
  // the readout as a reading — the bar's segment digits over their unlit
  // "8"s, the unit beside in the text face — where the number is the point
  // (Control Hub's brightness, 2026-10-26); off, the plain small text
  property bool segments: false
  // the unlit digits behind it: as wide as the longest reading ("888" for a
  // percent, so 9 and 100 sit on one ground); "" mirrors the reading itself
  property string ghost: ""
  readonly property var readParts: Helpers.splitRate(sl.readout)
  // dimmed when the value is the ordinary one, so it reads as "normal"
  // rather than as something you have changed
  property real neutral: -1
  // Wide enough for the longest label the panel actually uses. At 88 "Text
  // size" came out as "Text s…", which is a slider labeled by a guess.
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
  // ── HELD TO BE SLID (user, 2026-10-19): return rings it, the arrows
  // then move it, escape or return lets go — see DialogKeys. Moving off
  // the row, or the panel closing, lets go too.
  property bool held: false
  readonly property bool atCursor: !!sl.term && sl.term.prefAt() === sl
  onAtCursorChanged: if (!sl.atCursor) sl.held = false
  function activate() { sl.held = !sl.held; }
  function nudge(d) {
    const v = Math.max(sl.from,
                       Math.min(sl.to, sl.value + d * sl.wheelStep));
    if (v !== sl.value) sl.moved(v);
  }
  // enrolled with terminus' panel for its keys; outside it (calypso's
  // generator) a plain slider
  Component.onCompleted: if (term) term.prefEnrol(sl)

  width: parent ? parent.width : 0
  height: 34

  HeldRing {
    anchors.fill: parent
    anchors.margins: 2
    z: 5
    on: sl.held
  }

  readonly property real span: sl.to - sl.from
  readonly property real frac: sl.span > 0
    ? Math.max(0, Math.min(1, (sl.value - sl.from) / sl.span)) : 0

  Text {
    textFormat: Text.PlainText
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
    width: sl.readoutW
    horizontalAlignment: Text.AlignRight
    text: sl.readout
    visible: !sl.segments
    color: sl.readInk
    font.family: Zenon.face
    font.weight: Zenon.weight
    font.pixelSize: Zenon.px(13)
  }
  readonly property color readInk: (sl.neutral >= 0 && Math.abs(sl.value - sl.neutral) < 0.001)
    ? Zenon.accentMuted : Zenon.cyan
  Row {
    anchors.right: slRead.right
    anchors.verticalCenter: parent.verticalCenter
    visible: sl.segments
    spacing: 3
    Item {
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(segGhost.implicitWidth, segNum.implicitWidth)
      height: segNum.implicitHeight
      Text {
        id: segGhost
        anchors.right: parent.right
        text: sl.ghost !== "" ? sl.ghost : Helpers.ghostText(sl.readParts.num)
        color: Zenon.trough(sl.readInk)
        font: segNum.font
      }
      Text {
        id: segNum
        anchors.right: parent.right
        text: sl.readParts.num
        color: sl.readInk
        font.family: Zenon.clockFamily
        font.weight: Font.Bold
        font.pixelSize: Zenon.px(16)
      }
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: sl.readParts.unit
      color: Zenon.accentMuted
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(12)
    }
  }

  Rectangle {
    id: slTrack
    anchors.left: parent.left
    anchors.leftMargin: sl.labelW
    anchors.right: slRead.left
    anchors.rightMargin: 10
    anchors.verticalCenter: parent.verticalCenter
    height: 4
    radius: height / 2
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
      radius: height / 2
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
