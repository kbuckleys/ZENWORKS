// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// OPENFLARE — a cyan flare on the thing that was just opened: a wash and a
// 3px ring, up fast and fading slowly.
//
//     OpenFlare { id: flare; anchors.fill: parent; radius: parent.radius }
//     flare.fire()
//
// Opening hands off to something that comes up somewhere else, and if it
// takes a moment there is nothing to say the press landed. This says it, on
// the thing it landed on, and is gone before it can become clutter.
//
// Lifted out of terminus' Tile (2026-10-15) when howler's toasts wanted the
// same answer to a left click — a click that opens and a click that dismisses
// had looked exactly alike.

import QtQuick

Rectangle {
  id: flare
  property real glow: 0
  readonly property bool running: run.running
  // How long until it has peaked — a caller that acts on the flare's tail
  // waits this long, so the light is seen before whatever it opens.
  readonly property int rise: 140
  // The tint inside the ring. A tile wants it; a toast is the ring alone
  // (user, 2026-10-15) — a wash over a cover and its words read as dimming.
  property bool wash: true

  function fire() { run.restart(); }

  visible: flare.glow > 0.003
  opacity: flare.glow
  color: flare.wash ? Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.18) : "transparent"
  border.width: 3
  border.color: Zenon.cyan

  // The flare in and out on smooth curves. It used to drive the border's
  // WIDTH (1 → 3 → 1), which can only move in whole pixels, so it went
  // up and down in visible steps. The ring keeps one width and the flare
  // fades it instead.
  SequentialAnimation {
    id: run
    NumberAnimation { target: flare; property: "glow"; to: 1; duration: flare.rise;
                      easing.type: Easing.OutCubic }
    NumberAnimation { target: flare; property: "glow"; to: 0; duration: 620;
                      easing.type: Easing.InOutSine }
  }
}
