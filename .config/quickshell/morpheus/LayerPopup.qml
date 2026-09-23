// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// LAYERPOPUP — what every layer the pill can wear has in common.
//
// A fullscreen transparent overlay whose panel scales and fades in and out on
// `showFactor`, and which, when it opens on the pill's own monitor, is drawn
// as the pill (`morphMode`) instead of as a panel of its own. This was written
// out in each of eleven layers, identical down to the comments; each layer now
// declares only what is its own.
//
// Opening and closing go through playOpen() and playClose(). The animations
// are ids in this file, and a layer built on it cannot reach them by name.

import QtQuick
import Quickshell
import Quickshell.Wayland
import "."

PanelWindow {
  id: layer

  WlrLayershell.layer: WlrLayer.Overlay

  property bool shown: false
  property bool morphMode: false
  // 0..1, driven by shell.qml, which owns the crossfade schedule: 0 until the
  // pill's own row has finished clearing, then rising to 1 as the pill
  // finishes taking this layer's shape
  property real morphFade: 1
  property real showFactor: 0
  property bool collapsing: false
  // the bar, for the pill's live size and position while morphed
  property var statusbar: null

  // Emitted once a close has finished and `shown` has gone false.
  signal closed()

  // ── NO SCALE WHEN MORPHED, AND THAT IS THE POINT ────────────────────
  // Detached, the panel is arriving out of nothing and 0.94 -> 1.0 reads as
  // arrival. Morphed, the container is ALREADY THERE — it is the pill — so
  // the same scale is not an entrance, it is the text being stretched in
  // place. So a morph is a straight crossfade inside a shape that is already
  // right, and the scale belongs to the case that has something to scale
  // from.
  readonly property real growth: layer.showFactor
  readonly property real panelX: (layer.collapsing ? 0.985 + 0.015 * layer.growth
                        : 0.94 + 0.06 * layer.growth)
  readonly property real panelY: (layer.collapsing ? 0.82 + 0.18 * layer.growth
                        : 0.90 + 0.10 * layer.growth)
  // Morphed, the handover is timed off the PILL's progress (morphFade), not
  // this layer's own front-loaded showFactor, which crossed the threshold
  // ~25ms in and faded content up over a morpheus row still 80% opaque.
  // Math.min, not morphFade alone: handing the pill straight to another layer
  // leaves morphFade pinned at 1, so this layer would stay fully opaque until
  // its window blinked out. Its closeAnim is already easing showFactor to 0,
  // so the lower of the two fades it out between layers and leaves the
  // normal open schedule untouched.
  readonly property real contentFade: layer.morphMode
    ? Math.min(layer.morphFade, layer.showFactor) : layer.showFactor

  visible: layer.showFactor > 0.01
  color: "transparent"

  anchors { left: true; right: true; top: true; bottom: true }
  exclusionMode: ExclusionMode.Ignore

  NumberAnimation {
    id: openAnim
    target: layer; property: "showFactor"
    to: 1; duration: Zenon.slow; easing.type: Zenon.ease
  }

  NumberAnimation {
    id: closeAnim
    target: layer; property: "showFactor"
    to: 0; duration: Zenon.slow; easing.type: Zenon.ease
    onFinished: {
      layer.shown = false;
      layer.closed();
    }
  }

  // From nothing, and never alongside a close still running: left running, a
  // close finishes after the reopen and takes the panel down with it.
  function playOpen() {
    closeAnim.stop();
    layer.showFactor = 0;
    openAnim.restart();
  }

  function playClose() {
    openAnim.stop();
    closeAnim.restart();
  }
}
