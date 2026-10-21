// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// The editor's timeline: the clip as a filmstrip, the part being kept
// framed in yellow between two handles, what is cut away dimmed, and the
// playhead. Press anywhere on the strip to seek; drag a handle to move that
// end of the cut (the picture follows it, so you see the frame you are
// cutting at).
//
// It owns no times: it is handed them and says where the pointer wants
// them (seek, inMoved, outMoved), and the window keeps the range sane.

import QtQuick
import "../morpheus"

Item {
  id: strip

  property var frames: []
  property real duration: 0
  property real inMs: 0
  property real outMs: 0
  property real position: 0
  // which handle is held: "in", "out", or ""
  readonly property string holding: inGrab.pressed ? "in" : outGrab.pressed ? "out" : ""
  readonly property bool scrubbing: body.pressed

  signal seek(real ms)
  signal inMoved(real ms)
  signal outMoved(real ms)

  readonly property real handleW: 14
  // the strip proper sits between the two handles' outer edges
  readonly property real trackX: strip.handleW
  readonly property real trackW: Math.max(1, strip.width - 2 * strip.handleW)
  function xOf(ms) { return strip.trackX + (strip.duration > 0 ? ms / strip.duration : 0) * strip.trackW; }
  function msAt(x) { return Math.max(0, Math.min(1, (x - strip.trackX) / strip.trackW)) * strip.duration; }

  implicitHeight: 72

  // ── the film ──────────────────────────────────────────────────────────
  Rectangle {
    id: film
    x: strip.trackX
    width: strip.trackW
    height: strip.height
    radius: Zenon.radiusControl
    color: Zenon.wash(0.06)
    clip: true
    Row {
      anchors.fill: parent
      Repeater {
        model: strip.frames
        delegate: Image {
          required property var modelData
          width: film.width / Math.max(1, strip.frames.length)
          height: film.height
          source: modelData
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          cache: false
          sourceSize.height: 96
        }
      }
    }
    // what is cut away, dimmed
    Rectangle {
      x: 0
      width: Math.max(0, strip.xOf(strip.inMs) - strip.trackX)
      height: parent.height
      color: Zenon.shade(0.62)
    }
    Rectangle {
      x: strip.xOf(strip.outMs) - strip.trackX
      width: Math.max(0, film.width - x)
      height: parent.height
      color: Zenon.shade(0.62)
    }
  }

  // ── the kept part's frame ─────────────────────────────────────────────
  Rectangle {
    x: strip.xOf(strip.inMs) - strip.handleW
    width: strip.xOf(strip.outMs) - strip.xOf(strip.inMs) + 2 * strip.handleW
    height: strip.height
    color: "transparent"
    radius: Zenon.radiusCard
    border.width: 3
    border.color: Zenon.yellow
  }

  // ── seeking: the whole strip ──────────────────────────────────────────
  MouseArea {
    id: body
    anchors.fill: parent
    onPressed: (m) => strip.seek(strip.msAt(m.x))
    onPositionChanged: (m) => { if (body.pressed) strip.seek(strip.msAt(m.x)); }
  }

  // ── the playhead ──────────────────────────────────────────────────────
  Rectangle {
    x: Math.round(strip.xOf(strip.position) - width / 2)
    y: -4
    width: 3
    height: strip.height + 8
    radius: 1.5
    color: Zenon.white
    visible: strip.duration > 0
    border.width: 1
    border.color: Zenon.shade(0.5)
  }

  // ── the handles, over everything so they win the press ────────────────
  Rectangle {
    id: inHandle
    x: strip.xOf(strip.inMs) - strip.handleW
    width: strip.handleW
    height: strip.height
    topLeftRadius: Zenon.radiusCard
    bottomLeftRadius: Zenon.radiusCard
    color: inGrab.pressed ? Zenon.white : Zenon.yellow
    Text {
      anchors.centerIn: parent
      text: ""
      color: Zenon.onAccent
      font.family: Zenon.glyphFace
      font.pixelSize: Zenon.px(10)
    }
    MouseArea {
      id: inGrab
      anchors.fill: parent
      anchors.margins: -6
      property real grabDx: 0
      onPressed: (m) => { grabDx = m.x - 6 - strip.handleW; }
      onPositionChanged: (m) => {
        if (!inGrab.pressed) return;
        const p = mapToItem(strip, m.x, 0);
        strip.inMoved(strip.msAt(p.x - inGrab.grabDx));
      }
    }
  }
  Rectangle {
    id: outHandle
    x: strip.xOf(strip.outMs)
    width: strip.handleW
    height: strip.height
    topRightRadius: Zenon.radiusCard
    bottomRightRadius: Zenon.radiusCard
    color: outGrab.pressed ? Zenon.white : Zenon.yellow
    Text {
      anchors.centerIn: parent
      text: ""
      color: Zenon.onAccent
      font.family: Zenon.glyphFace
      font.pixelSize: Zenon.px(10)
    }
    MouseArea {
      id: outGrab
      anchors.fill: parent
      anchors.margins: -6
      property real grabDx: 0
      onPressed: (m) => { grabDx = m.x - 6; }
      onPositionChanged: (m) => {
        if (!outGrab.pressed) return;
        const p = mapToItem(strip, m.x, 0);
        strip.outMoved(strip.msAt(p.x - outGrab.grabDx));
      }
    }
  }
}
