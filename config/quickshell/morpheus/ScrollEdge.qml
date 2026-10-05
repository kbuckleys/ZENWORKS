// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ── WHAT SCROLLS UP GOES UNDER THE BAR ──────────────────────────────────
// Finder's toolbar: rows that leave the top of a list do not stop at a hard
// edge, they carry on under the chrome above it, frosted and fading out as
// they go. This is that, for any Flickable, without moving the view.
//
//     ScrollEdge {
//       view: rows
//       x: <rows' left>; width: rows.width
//       y: <top of the chrome>; height: <down to rows' top edge>
//     }
//
// LAID UNDER THE CHROME, NOT OVER IT. Declare it before the bar (or below it
// in z) so the bar's own translucent ground tints the ghosts, the way the
// toolbar's material does; its bottom edge must sit exactly on the view's
// top edge, so the rows carry on from where the view stops drawing them.
//
// THE VIEW STAYS WHERE IT IS. The rows above its top are never drawn by it
// (it clips); they are drawn here, from its own content, by a capture of
// the strip just above the viewport. An item view would have culled them —
// it keeps only the rows inside its bounds alive — so displayMarginBeginning
// is raised to this item's height, which keeps that many pixels of rows
// built above the top. That is a handful of rows, not the list.
//
// WHAT IT COSTS. Nothing while the list sits at its top, nothing while it is
// still: the capture is live only when there are rows above the edge, and a
// live capture renders only when what it shows changes. While scrolling, one
// strip of this height is rendered and blurred a frame — small next to the
// window blur the compositor is already doing behind it.

import QtQuick
import QtQuick.Effects
import "."

Item {
  id: edge

  // the view whose rows go under (a ListView, GridView or plain Flickable),
  // spanning the same x range as this item
  property var view: null

  // blurred, as the toolbar's material does it
  property bool frost: true
  // fading out as they rise, macOS' soft scroll edge; with frost off this
  // alone is the edge: sharp rows that dissolve upward
  property bool fade: true
  // how much of them shows through at the seam, before the bar's own tint
  property real strength: 0.75
  // blurMax is the kernel, the real softness knob (see Glow, the crumbs)
  property int blurMax: 32

  // ── THE BAR DARKENS WHILE IT HAS SOMETHING UNDER IT ───────────────────
  // What the material does for its labels: bright pictures frosted behind
  // light grey text left the bar's quieter words hard to read, so over the
  // ghosts goes this much black, and only while there are ghosts. At the top
  // the bar is exactly what it always was.
  property real scrim: 0.35

  // ── OR FROM THE BOTTOM UP ─────────────────────────────────────────────
  // The same thing turned over, for a bar BELOW the view (a hint strip, a
  // status line): rows that have not arrived yet show through it, rising
  // out of it as they come. This item then sits under that bar with its TOP
  // edge on the view's bottom edge, and everything below mirrors: the rows
  // kept built are past the end (displayMarginEnd), the capture is the strip
  // under the viewport, and the fade dies away downward.
  property bool below: false

  // ── OR IT FINDS THE VIEW ITSELF ───────────────────────────────────────
  // For a view nested some panes down under the chrome, where adding up the
  // offsets by hand would be a sum per view: set `follow`, and `chromeTop` to where
  // the chrome begins in this item's parent. It then spans the view's width
  // and runs from `chromeTop` down to the view's top edge. A mapping announces no
  // change of its own, so it is re-measured whenever the view moves, resizes
  // or is shown, or this item's parent (the window, near enough) resizes.
  // (Not `top`: Item already has one, and it is FINAL.) Turned over
  // (`below`), it runs from the view's bottom edge down to `chromeBottom`,
  // which is this item's parent's height until set.
  property bool follow: false
  property real chromeTop: 0
  property real chromeBottom: -1

  // ── THE BAR, WHEN THERE IS ROOM BEFORE IT ─────────────────────────────
  // Followed views do not always stop where their bar starts: a list with a
  // margin, a page with a notes strip, stand a little short of it. That
  // stretch is not chrome, and frosting and darkening it drew a black band
  // across the window with nothing over it. Name the bar and this item still
  // runs from the view's edge to it, but only the bar's own part is frosted;
  // the stretch before it shows the rows as they are, as if the view went on.
  property Item bar: null
  readonly property real gap: edge.follow ? edge.at.gap : edge.gapSet
  // or, placed by hand, how much of this item lies before the bar
  property real gapSet: 0

  // Anything else that moves the view without the view knowing: a parent
  // sliding, say. Bind it to a list of what to watch; only read, never used.
  property var track: null

  readonly property var at: {
    const v = edge.view, p = edge.parent, b = edge.bar;
    if (!edge.follow || !v || !p) return { x: 0, y: 0, w: 0, h: 0, gap: 0 };
    void [v.x, v.y, v.width, v.height, v.visible, p.width, p.height, edge.track];
    if (b) void [b.x, b.y, b.width, b.height, b.visible];
    // a bar folded away (zen) leaves nothing to go under, gap included
    if (b && (!b.visible || b.height <= 0)) return { x: 0, y: 0, w: 0, h: 0, gap: 0 };
    const o = v.mapToItem(p, 0, 0);
    const bo = b ? b.mapToItem(p, 0, 0) : null;
    if (edge.below) {
      const from = o.y + v.height;
      const end = bo ? bo.y + b.height
        : edge.chromeBottom >= 0 ? edge.chromeBottom : p.height;
      const gap = bo ? Math.max(0, bo.y - from) : 0;
      return { x: o.x, y: from, w: v.width, h: Math.max(0, end - from), gap: gap };
    }
    const start = bo ? bo.y : edge.chromeTop;
    const gap = bo ? Math.max(0, o.y - (bo.y + b.height)) : 0;
    return { x: o.x, y: start, w: v.width, h: Math.max(0, o.y - start), gap: gap };
  }
  x: edge.at.x
  y: edge.at.y
  width: edge.at.w
  height: edge.at.h

  // where the bar's part of this item is: the rest is the gap, by the view
  readonly property real barH: Math.max(0, edge.height - edge.gap)
  readonly property real barY: edge.below ? edge.gap : 0

  // ── A LITTLE OF THE VIEW TOO ──────────────────────────────────────────
  // A blur near the bottom of a texture averages in the nothing below it, so
  // a capture that stopped at the view's edge would come out half as bright
  // along the very seam where it must match the rows. The capture runs this
  // far into the view and the excess is clipped off.
  readonly property int pad: edge.frost ? Math.min(24, edge.blurMax) : 0

  // ── ONLY WHILE THERE IS SOMETHING UP THERE ────────────────────────────
  // At the top (or banded past it) nothing is above the edge, so nothing is
  // captured and nothing is drawn; turned over, the same at the end. The
  // bounds are Elastic's (originY and the margins counted).
  readonly property real lo: !edge.view ? 0
    : (edge.view.originY || 0) - (edge.view.topMargin || 0)
  readonly property real hi: !edge.view ? 0
    : edge.lo + Math.max(0, edge.view.contentHeight + (edge.view.topMargin || 0)
        + (edge.view.bottomMargin || 0) - edge.view.height)
  // A view that is not a Flickable (plato's, whose rows nvim hands over)
  // says for itself whether there is anything past the edge; it must still
  // offer contentItem, contentX and contentY for the capture.
  property var scrolled: undefined
  readonly property bool on: !!edge.view && edge.visible && edge.view.visible
    && edge.width > 0 && edge.height > 0 && (edge.frost || edge.fade)
    && (typeof edge.scrolled === "boolean" ? edge.scrolled
        : edge.below ? edge.view.contentY < edge.hi - 0.5
                     : edge.view.contentY > edge.lo + 0.5)

  // keep the rows past the edge built — see the note at the head of the file
  readonly property bool itemView: !!edge.view && edge.view.displayMarginBeginning !== undefined
  Binding {
    target: edge.view
    property: "displayMarginBeginning"
    value: Math.ceil(edge.height)
    when: edge.itemView && !edge.below
    restoreMode: Binding.RestoreBindingOrValue
  }
  Binding {
    target: edge.view
    property: "displayMarginEnd"
    value: Math.ceil(edge.height)
    when: edge.itemView && edge.below
    restoreMode: Binding.RestoreBindingOrValue
  }

  // The strip just above the viewport, in the content's own coordinates: the
  // content item sits at -contentX, -contentY, so the viewport's top is
  // contentY there. The view's clip is its own, and is not in the capture.
  ShaderEffectSource {
    id: cap
    width: edge.width
    height: edge.height + edge.pad
    sourceItem: edge.on ? edge.view.contentItem : null
    sourceRect: edge.on
      ? Qt.rect(edge.view.contentX,
                edge.below ? edge.view.contentY + edge.view.height - edge.pad
                           : edge.view.contentY - edge.height,
                edge.view.width, edge.height + edge.pad)
      : Qt.rect(0, 0, 0, 0)
    live: edge.on
    hideSource: false
    visible: false
  }

  // ── THE FADE ──────────────────────────────────────────────────────────
  // Nothing at the top of the bar, all of it from about two thirds of the way
  // down to the seam. Through the crumbs' recipe (threshold half, spread
  // full), which turns the ramp into an eased ramp in the alpha.
  Rectangle {
    id: ramp
    width: cap.width
    height: cap.height
    // turned over, the seam (and the pad) is at the top of the texture
    // fading across the bar's part only; the gap, by the view, is solid
    readonly property real solid: (edge.barH * 0.7) / Math.max(1, cap.height)
    gradient: Gradient {
      GradientStop { position: 0.0; color: edge.below ? "#ff000000" : "#00000000" }
      GradientStop { position: edge.below ? 1 - ramp.solid : ramp.solid; color: "#ff000000" }
      GradientStop { position: 1.0; color: edge.below ? "#00000000" : "#ff000000" }
    }
    // drawn only into rampTex: hideSource keeps it off the window (an
    // invisible item would render nothing into the texture either)
  }
  ShaderEffectSource {
    id: rampTex
    width: ramp.width
    height: ramp.height
    // ALWAYS the ramp's: hideSource is what keeps a black gradient off the
    // window, and a texture with no source hides nothing — gating this on
    // `on` left the ramp painted under the chrome and 24px into the list
    // whenever the list sat at its top. It is drawn once, and again only
    // when its size changes.
    sourceItem: ramp
    hideSource: true
    visible: false
  }

  // ── THE GAP: THE ROWS AS THEY ARE ─────────────────────────────────────
  // Between the view's edge and the bar (see `bar`), the capture drawn
  // plainly, so the rows carry on to the bar before they frost.
  Item {
    y: edge.below ? 0 : edge.barH
    width: parent.width
    height: edge.gap
    clip: true
    visible: edge.on && edge.gap > 0

    MultiEffect {
      y: (edge.below ? -edge.pad : 0) - parent.y
      width: cap.width
      height: cap.height
      source: cap
    }
  }

  // ── THE BAR'S PART: FROSTED ───────────────────────────────────────────
  Item {
    y: edge.barY
    width: parent.width
    height: edge.barH
    clip: true
    visible: edge.on
    opacity: edge.strength

    MultiEffect {
      // turned over, the pad is above the seam, so it hangs off the top
      y: (edge.below ? -edge.pad : 0) - parent.y
      width: cap.width
      height: cap.height
      source: cap
      blurEnabled: edge.frost
      blur: 1.0
      blurMax: edge.blurMax
      // the material is a little brighter and less loud than what is under it
      saturation: edge.frost ? -0.2 : 0
      maskEnabled: edge.fade
      maskSource: rampTex
      maskThresholdMin: 0.5
      maskSpreadAtMin: 1.0
    }
  }

  // Over the ghosts and under the bar — the bar's part only: over the gap
  // it is a black band with nothing above it. Eased in and out so crossing
  // the top of the list never flicks the bar between two greys; it outlives
  // `on` by its own fade, which is why it is not inside the item above.
  Rectangle {
    y: edge.barY
    width: parent.width
    height: edge.barH
    color: "#000000"
    opacity: edge.on ? edge.scrim : 0
    visible: opacity > 0.001
    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
  }
}
