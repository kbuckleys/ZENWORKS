// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// Its own file since 2026-10-08, out of TerminusWindow.qml, where it was an
// inline component. `term` is the terminus window; every place that makes
// one passes it (`term: root`).

import QtQuick
import Quickshell
import "../morpheus"

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

  // NO HOVER TINT in the sheets (user, 2026-10-17): the verb no longer goes
  // cyan under the pointer. The cursor itself is prefBar; see its note.
  MouseArea {
    id: actPress
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
    color: Zenon.accentMuted
    // pressed, dimmed as every button in the suite (user, 2026-10-17)
    opacity: actPress.pressed ? Zenon.pressDim : 1
    font.family: Zenon.face
    font.weight: Zenon.weight
    font.pixelSize: Zenon.px(13)
    Behavior on color { ColorAnimation { duration: Zenon.fast } }
  }
}
