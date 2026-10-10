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
  id: pref
  property string label: ""
  // The key that already did this. The panel's job is partly to teach them.
  property string hint: ""
  property bool on: false
  // False mutes the row, as PrefAction does: a setting that means nothing
  // where you are (group headings outside list view) greys out, refuses
  // the click, and the cursor steps over it. The switch keeps showing the
  // stored state, which comes back with the view it belongs to.
  property bool enabled: true
  signal toggled()

  // ── WHAT THE PANEL'S CURSOR NEEDS OF A ROW ──────────────────────────
  // Three things, and every kind of row answers the same three: whether the
  // cursor is on it, whether the cursor may land on it at all, and what
  // happens when it is worked. A switch is worked by being flipped and has
  // nothing to nudge.
  readonly property bool reachable: pref.enabled
  function activate() { if (pref.enabled) pref.toggled(); }
  function nudge(d) {}
  Component.onCompleted: term.prefEnrol(pref)

  width: parent ? parent.width : 0
  height: 32
  opacity: pref.enabled ? 1 : 0.45

  // NO GROUND OF ITS OWN. The cursor is prefBar, one rectangle the panel
  // slides between rows; a fill here would be a second mark that can only
  // blink. And no hover tint either, which is the listing's own rule — a
  // highlight that follows the pointer made the panel twitch as the mouse
  // crossed it.
  MouseArea {
    anchors.fill: parent
    enabled: pref.enabled
    onClicked: pref.toggled()
  }

  Text {
    anchors.left: parent.left
    anchors.leftMargin: 14
    anchors.right: prefHint.visible ? prefHint.left : prefSwitch.left
    anchors.rightMargin: 10
    anchors.verticalCenter: parent.verticalCenter
    text: pref.label
    elide: Text.ElideRight
    color: Zenon.white
    font.family: Zenon.face
    font.weight: Zenon.weight
    font.pixelSize: Zenon.px(15)
  }

  // A CHIP, like every other key this window writes down. It was bare muted
  // text, which is what a footnote looks like — and the context menu, the
  // F1 sheet and the pending-prefix bar all draw the same fact as a key cap.
  // Three places saying "press this" one way and a fourth saying it another
  // is the panel looking like it came from somewhere else.
  KeyCap {
    id: prefHint
    anchors.right: prefSwitch.left
    anchors.rightMargin: 10
    anchors.verticalCenter: parent.verticalCenter
    label: pref.hint
  }

  // A SWITCH, not a tick. A tick says "chosen from a list" and these are not
  // a list — they are four things that are each either on or off, and the
  // knob moving is what makes flipping one feel like flipping a switch.
  Rectangle {
    id: prefSwitch
    anchors.right: parent.right
    anchors.rightMargin: 14
    anchors.verticalCenter: parent.verticalCenter
    width: 30
    height: 16
    radius: 8
    color: pref.on
      ? Qt.rgba(Zenon.cyan.r, Zenon.cyan.g, Zenon.cyan.b, 0.32)
      : Qt.rgba(Zenon.white.r, Zenon.white.g, Zenon.white.b, 0.07)
    border.width: 1
    border.color: pref.on ? Zenon.cyan : Zenon.border
    Behavior on color { ColorAnimation { duration: Zenon.fast } }
    Behavior on border.color { ColorAnimation { duration: Zenon.fast } }

    Rectangle {
      y: 3
      x: pref.on ? parent.width - width - 3 : 3
      width: 10
      height: 10
      radius: width / 2   // a knob: round whatever the window is
      color: pref.on ? Zenon.cyan : Zenon.muted
      Behavior on x {
        NumberAnimation { duration: Zenon.fast; easing.type: Zenon.ease }
      }
      Behavior on color { ColorAnimation { duration: Zenon.fast } }
    }
  }
}
