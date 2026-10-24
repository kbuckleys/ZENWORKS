// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// A POPUP'S GROUND, inside its LayerPanel (which takes it as `ground`).
// Eight popups built this same box by hand (2026-10-24); each still sets its
// own color, and chronos its radius.
//
// ClippingRectangle, not Rectangle + clip: true. Qt's own clip is
// RECTANGULAR — it clips to the bounding box and knows nothing about the
// radius — so every square child painted to the panel's edge (the bottom
// strip most visibly) filled in the rounded corners behind it. This one
// clips to the rounded shape itself.
//
// Grown by its own border: a ClippingRectangle insets its children by
// border.width on every side, so the content box came out 2px smaller than
// the panel and any layout measured against the panel's size fell one row
// or one column short. The margin hands the content its full box back.

import QtQuick
import Quickshell.Widgets
import "."

ClippingRectangle {
  id: ground
  anchors.fill: parent
  anchors.margins: -ground.border.width
  color: Zenon.layerBg
  radius: Zenon.pillRadius
  border.color: Zenon.border
  border.width: 1
  focus: true
}
