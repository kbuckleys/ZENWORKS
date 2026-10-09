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
  id: act
  property string label: ""
  // What the row is about to do, or what there is to do it to.
  property string verb: ""
  property bool enabled: true
  signal triggered()

  // The one row that can refuse: with nothing remembered there is nothing to
  // forget, and the cursor steps straight over it rather than landing on a
  // row where return does nothing.
  readonly property bool reachable: act.enabled
  function activate() { if (act.enabled) act.triggered(); }
  function nudge(d) {}
  Component.onCompleted: term.prefEnrol(act)

  width: parent ? parent.width : 0
  height: 32
  opacity: act.enabled ? 1 : 0.45

  // Kept for the verb at the end of the row, which goes cyan under the
  // pointer — a word lighting up is a button saying it is one, and that is
  // not the same thing as a band across the row. The cursor itself is
  // prefBar; see its note.
  HoverHandler { id: actHov }
  MouseArea {
    anchors.fill: parent
    enabled: act.enabled
    onClicked: act.triggered()
  }

  Text {
    anchors.left: parent.left
    anchors.leftMargin: 14
    anchors.right: actVerb.left
    anchors.rightMargin: 10
    anchors.verticalCenter: parent.verticalCenter
    text: act.label
    elide: Text.ElideRight
    color: Zenon.white
    font.family: Zenon.face
    font.weight: Zenon.weight
    font.pixelSize: Zenon.px(15)
  }

  Text {
    id: actVerb
    anchors.right: parent.right
    anchors.rightMargin: 14
    anchors.verticalCenter: parent.verticalCenter
    text: act.verb
    color: actHov.hovered && act.enabled ? Zenon.cyan : Zenon.muted
    font.family: Zenon.face
    font.weight: Zenon.weight
    font.pixelSize: Zenon.px(13)
    Behavior on color { ColorAnimation { duration: Zenon.fast } }
  }
}
