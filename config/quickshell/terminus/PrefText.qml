// ┌─┐┌─┐┌┐┌┬ ┬┌─┐┬─┐┬┌─┌─┐
// ┌─┘├┤ │││││││ │├┬┘├┴┐└─┐
// └─┘└─┘┘└┘└┴┘└─┘┴└─┴ ┴└─┘
// https://github.com/kbuckleys/
//
// ── A LINE YOU TYPE INTO, ON THE SETTINGS PANEL ────────────────────────
// The panel had switches, segments, sliders and one action — every control
// it needed while every setting was a choice between things the window
// already knew about. A terminal command is not: it is a string only you
// know, so it needs somewhere to put one.
//
// Committed on Return or on losing the field, never per keystroke: half a
// command is not a command, and writing one to disk on every letter would
// persist a dozen broken ones on the way to a good one.
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
  id: ptext
  property string label: ""
  property string value: ""
  property string ghost: ""
  signal committed(string v)

  // Worked by being TYPED INTO, so return on it hands the field the keyboard
  // rather than doing something to it. From there the field has the keys and
  // this branch of the handler never runs — see ptextIn's own Tab.
  readonly property bool reachable: true
  function activate() { ptextIn.forceActiveFocus(); }
  function nudge(d) {}
  Component.onCompleted: term.prefEnrol(ptext)

  width: parent ? parent.width : 0
  height: 34

  // No ground: the cursor is prefBar. The field's own border goes cyan when
  // it has the keyboard, which is already a mark and a better one.

  Text {
    id: ptextLabel
    anchors.left: parent.left
    anchors.leftMargin: 14
    anchors.verticalCenter: parent.verticalCenter
    width: 116
    text: ptext.label
    elide: Text.ElideRight
    color: Zenon.white
    font.family: Zenon.face
    font.weight: Zenon.weight
    font.pixelSize: Zenon.px(13)
  }

  Rectangle {
    anchors.left: ptextLabel.right
    anchors.leftMargin: 6
    anchors.right: parent.right
    anchors.rightMargin: 14
    anchors.verticalCenter: parent.verticalCenter
    height: 24
    radius: 4
    color: Qt.rgba(Zenon.white.r, Zenon.white.g, Zenon.white.b, 0.05)
    border.width: 1
    border.color: ptextIn.activeFocus ? Zenon.cyan : Zenon.border
    Behavior on border.color { ColorAnimation { duration: Zenon.fast } }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.IBeamCursor
      onClicked: ptextIn.forceActiveFocus()
    }

    Text {
      anchors.fill: parent
      anchors.leftMargin: 8
      verticalAlignment: Text.AlignVCenter
      visible: ptextIn.text === "" && !ptextIn.activeFocus
      text: ptext.ghost
      color: Zenon.muted
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(12)
    }

    TextInput {
      id: ptextIn

      cursorDelegate: Caret { field: ptextIn }
      anchors.fill: parent
      anchors.leftMargin: 8
      anchors.rightMargin: 8
      verticalAlignment: Text.AlignVCenter
      text: ptext.value
      color: Zenon.white
      selectionColor: Zenon.selBg
      selectedTextColor: Zenon.white
      font.family: Zenon.face
      font.weight: Zenon.weight
      font.pixelSize: Zenon.px(12)
      clip: true
      onEditingFinished: ptext.committed(ptextIn.text)

      // TAB LEAVES THE FIELD RATHER THAN PUTTING A TAB IN IT. While the
      // field has the keyboard, dialogKeys does not — so the panel's own Tab
      // handler never sees this one, and the walk would have stopped dead at
      // the one row you can type into. Commits on the way out, the same as
      // clicking away does.
      Keys.onPressed: (e) => {
        if (e.key !== Qt.Key_Tab && e.key !== Qt.Key_Backtab) return;
        e.accepted = true;
        ptext.committed(ptextIn.text);
        term.prefsDialogKeys.forceActiveFocus();
        term.prefStep(e.key === Qt.Key_Tab ? 1 : -1);
      }

      // BACK TO THE PANEL, not to the listing. Focusing content left the
      // panel open with nothing holding the keyboard, so the next Tab went
      // nowhere.
      Keys.onEscapePressed: (e) => {
        e.accepted = true;
        ptextIn.text = ptext.value;
        if (term.prefsSheet.open) term.prefsDialogKeys.forceActiveFocus();
        else term.prefsContent.forceActiveFocus();
      }
    }
  }
}
