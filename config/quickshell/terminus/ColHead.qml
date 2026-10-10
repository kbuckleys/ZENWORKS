// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
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
  id: head
  property string label: ""
  property string sortKey: ""
  property var pane: term.act
  readonly property bool lit: head.sortKey !== "" && head.pane
    && head.pane.sortBy === head.sortKey
  property bool rightAlign: false
  // Matched to the DATA cell this names, not assumed. The size column keeps
  // a 14px gutter before the modified column; the modified column is the
  // last one and sits flush. A single hard-coded pad here put MODIFIED 14px
  // to the left of the times underneath it, which read as centred.
  property real padRight: 14
  height: 22

  Text {
    anchors.fill: parent
    verticalAlignment: Text.AlignVCenter
    horizontalAlignment: head.rightAlign ? Text.AlignRight : Text.AlignLeft
    rightPadding: head.rightAlign ? head.padRight : 0
    text: head.lit ? head.label + (head.pane.sortDesc ? " ▾" : " ▴") : head.label
    color: head.lit ? Zenon.cyan
      : (headMa.containsMouse ? Zenon.keyInk : Zenon.muted)
    font.family: Zenon.faceFixed
    font.weight: Zenon.weight
    font.pixelSize: Zenon.px(12)
  }

  MouseArea {
    id: headMa
    anchors.fill: parent
    hoverEnabled: true
    // A heading with no key sorts nothing, so it does not offer to: the
    // pointer stays an arrow rather than promising a click that would set
    // the sort key to the empty string and leave the list in no order at all.
    enabled: head.sortKey !== ""
    onClicked: {
      if (head.pane && head.pane !== term.act) term.activatePane(head.pane.side);
      if (term.sortKey === head.sortKey) term.sortDesc = !term.sortDesc;
      else { term.sortKey = head.sortKey; term.sortDesc = false; }
    }
  }
}
