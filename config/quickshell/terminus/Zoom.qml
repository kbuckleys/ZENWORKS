// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// Terminus' zoom … logic, out of TerminusWindow.qml
// (2026-10-08). The state stays on the window (term); the window keeps a
// one-line forwarder for each function here, so callers are unchanged.

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
  id: zoom
  property var term: null

  function zoomClamp(v) {
    return Math.max(term.zoomMin, Math.min(term.zoomMax, v));
  }
  function zoomBy(step) {
    if (term.viewMode === "grid") term.act.zoom = term.zoomClamp(term.thumbZoom + step);
    else term.zoom = term.zoomClamp(term.zoom + step);
    Qt.callLater(term.positionSel);
  }
  function zoomReset() {
    if (term.viewMode === "grid") term.act.zoom = term.thumbZoomDefault;
    else term.zoom = 1.0;
    Qt.callLater(term.positionSel);
  }
  // Straight to a value, for the settings panel's slider — the keys step, and
  // stepping is the wrong gesture when the whole range is drawn in front of
  // you. Which zoom it lands on follows the same rule zoomBy uses: the grid
  // scales its pictures, everything else scales its text, and the two are
  // deliberately independent.
  function setZoom(v) {
    const z = term.zoomClamp(v);
    if (term.viewMode === "grid") term.act.zoom = z;
    else term.zoom = z;
    Qt.callLater(term.positionSel);
  }
}
