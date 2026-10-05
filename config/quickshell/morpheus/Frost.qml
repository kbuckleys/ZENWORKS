// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ── FROSTED GLASS OVER WHATEVER IS UNDER IT ─────────────────────────────
// A bar, a panel, laid over content that runs on underneath it: this is the
// material — what the content draws in this item's rectangle, blurred. The
// compositor can blur what is behind a WINDOW; what is behind a bar inside
// one is ours to do, and this is where it is done.
//
//     Rectangle {                         // the bar, in a translucent ground
//       color: Zenon.headBg
//       Frost { anchors.fill: parent; z: -1; source: stage }
//       ...
//     }
//
// z -1 inside the bar puts it under the bar's own ground, which then tints
// it, and over everything else; `source` is the item the content lives in
// (a picture's stage), which must draw under the bar too.
//
// ScrollEdge is the other half: rows past a list's edge that its view does
// not draw. Here the content IS drawn under the bar, sharp, and this covers
// it with its own blur.
//
// (Sheets wear one under their card: see Sheet's cardFrost.)
//
// WHAT IT COSTS. Nothing while `active` is off — say so whenever there is
// nothing under the bar (a picture fitted clear of it). On, one capture of
// this rectangle, re-rendered only when what it shows changes, and a blur.

import QtQuick
import QtQuick.Effects
import "."

Item {
  id: frost

  // the item whose drawing is under this one
  property Item source: null
  // off when nothing of the source reaches under here
  property bool active: true
  // blurMax is the kernel, the real softness knob (see Glow, ScrollEdge)
  property int blurMax: 64
  property real saturation: -0.3
  // ── AND DARKER, FOR WHAT IS WRITTEN ON IT ─────────────────────────────
  // A bright picture blurred is still bright, and a bar's quieter labels
  // (muted grey) vanished into it. The glass is dimmed (brightness), then
  // this much black goes over it — eased in only while there is something
  // under it, so a bar over nothing is exactly what it always was. The
  // same answer ScrollEdge's scrim gives the lists.
  property real brightness: -0.12
  property real scrim: 0.45
  // anything that moves this item or the source without either knowing (a
  // parent sliding): bind it to a list of what to watch
  property var track: null
  // rounded corners, for glass that is not a bar (a sheet's card). Masked
  // here rather than clipped by a rounded parent: a ClippingRectangle does
  // not render a MultiEffect inside it at all (see picasso's Loupe), which
  // is how the sheets came out see-through and unblurred.
  property real radius: 0
  // ── A FLOOR UNDER THE GLASS ───────────────────────────────────────────
  // The blur covers the sharp content beneath only where that content is
  // solid. A picture is; a listing is thin text on a see-through window,
  // and blurred that far it is a haze the sharp rows read straight through
  // (sheets over terminus looked unblurred, ceres only right because its
  // stage blurs itself). Give such glass a solid floor: the blur is drawn
  // on it, and nothing sharp gets past. Transparent for none (bars over a
  // picture, where the window's own see-through ground should stay).
  property color base: "transparent"
  // ── FADED IN FROM AN EDGE ─────────────────────────────────────────────
  // Glass that hangs from a bar (a spliced sheet) starts as nothing but its
  // floor and tint, exactly the bar's black, and the blur comes in over
  // this many pixels — so the seam between the bar and the card is no seam.
  property real fadeTop: 0
  // ── THIN CONTENT, BROUGHT BACK UP ─────────────────────────────────────
  // Text blurred far enough to be frost spreads its few pixels so thin
  // they all but vanish; blurred only a little, it is still text (plato's
  // sheets: "not really frosted"). So blur it properly and lay the result
  // over itself this many times: each copy adds what the last let through,
  // and the streaks come back to strength without turning legible. One
  // blur per copy, over this item's area only — keep it small.
  property int gain: 1
  property real fadeBottom: 0
  readonly property bool masked: frost.radius > 0 || frost.fadeTop > 0 || frost.fadeBottom > 0

  readonly property bool on: frost.active && !!frost.source && frost.visible
    && frost.width > 0 && frost.height > 0

  // ── A MARGIN ALL ROUND ────────────────────────────────────────────────
  // A blur at a texture's edge averages in the nothing beyond it, which
  // reads as a dark rim on the glass. The capture is taken this much larger
  // on every side and the excess clipped away.
  readonly property int pad: Math.min(48, frost.blurMax)

  // where this rectangle is, in the source's coordinates
  readonly property rect at: {
    const s = frost.source;
    if (!s) return Qt.rect(0, 0, 0, 0);
    void [frost.x, frost.y, frost.width, frost.height, s.x, s.y, s.width, s.height, frost.track];
    const o = frost.mapToItem(s, 0, 0);
    return Qt.rect(o.x - frost.pad, o.y - frost.pad,
                   frost.width + 2 * frost.pad, frost.height + 2 * frost.pad);
  }

  ShaderEffectSource {
    id: cap
    width: frost.at.width
    height: frost.at.height
    sourceItem: frost.on ? frost.source : null
    sourceRect: frost.at
    live: frost.on
    hideSource: false
    visible: false
  }

  Rectangle {
    anchors.fill: parent
    radius: frost.radius
    color: frost.base
    visible: frost.on && frost.base.a > 0
  }

  Item {
    anchors.fill: parent
    clip: true
    visible: frost.on

    // `gain` copies of the one blur, stacked: see `gain`
    Repeater {
      model: Math.max(1, frost.gain)
      MultiEffect {
        x: -frost.pad
        y: -frost.pad
        width: cap.width
        height: cap.height
        source: cap
        autoPaddingEnabled: false
        blurEnabled: true
        blur: 1.0
        blurMax: frost.blurMax
        saturation: frost.saturation
        brightness: frost.brightness
        // the corners, in the effect's own (padded) frame
        maskEnabled: frost.masked
        maskSource: cornerTex
        maskThresholdMin: 0.5
        maskSpreadAtMin: 0.2
      }
    }
  }

  Item {
    id: cornerMask
    width: cap.width
    height: cap.height
    visible: frost.masked
    Rectangle {
      x: frost.pad
      y: frost.pad
      width: frost.width
      height: frost.height
      radius: frost.radius
      readonly property real h: Math.max(1, height)
      gradient: Gradient {
        GradientStop { position: 0.0; color: frost.fadeTop > 0 ? "#00ffffff" : "#ffffffff" }
        GradientStop { position: Math.min(0.5, frost.fadeTop / Math.max(1, frost.height)); color: "#ffffffff" }
        GradientStop { position: Math.max(0.5, 1 - frost.fadeBottom / Math.max(1, frost.height)); color: "#ffffffff" }
        GradientStop { position: 1.0; color: frost.fadeBottom > 0 ? "#00ffffff" : "#ffffffff" }
      }
    }
  }
  ShaderEffectSource {
    id: cornerTex
    width: cornerMask.width
    height: cornerMask.height
    // always its source, so hideSource keeps the white shape off the window
    sourceItem: cornerMask
    hideSource: true
    visible: false
  }

  Rectangle {
    anchors.fill: parent
    radius: frost.radius
    color: "#000000"
    opacity: frost.on ? frost.scrim : 0
    visible: opacity > 0.001
    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
  }
}
